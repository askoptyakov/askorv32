#Фильтр вывода для консоли Eclipse: полоса прогресса обновляется в одной строке.
#Когда вывод идёт в трубу, openFPGALoader печатает каждое обновление прогресса как "\r<подпись>: [...] NN%\r\n":
#консоль переводит строку, и полоса повторяется десятки раз. Фильтр убирает "\r\n", если за ним идёт "\r"
#и строка с той же подписью до двоеточия (обновление той же полосы); остальной вывод передаёт без изменений.
#В консоли Eclipse должна быть включена обработка \r (SETUP.md п. 8.5).
#Использование: openFPGALoader ... 2>&1 | py -u sw/conprogress/conprogress.py

import sys

inp = sys.stdin.buffer
out = sys.stdout.buffer

LABEL_MAX = 64      #Подпись полосы длиннее не бывает: дальше ждать двоеточие незачем

NORMAL, CR, CRLF, PEEK = range(4)
state = NORMAL
cur = bytearray()   #Начало текущей строки (от последнего \r или \n) - для сравнения подписи
peek = bytearray()  #Начало новой строки после "\r\n\r", пока не ясно, та же ли это полоса


def put(res, byte):
    """Обычный байт: выводится и запоминается как начало текущей строки."""
    global state
    if byte == 0x0D:
        state = CR
        return
    res.append(byte)
    if byte == 0x0A:
        cur.clear()
    elif len(cur) < LABEL_MAX:
        cur.append(byte)


def decide(res, same):
    """Конец подписи новой строки: без перевода строки, если это та же полоса."""
    global state
    res += b"\r" if same else b"\r\n"
    res += peek
    cur[:] = peek
    peek.clear()
    state = NORMAL


while True:
    chunk = inp.read1(4096)
    if not chunk:
        break
    res = bytearray()
    for byte in chunk:
        if state == CR:
            if byte == 0x0A:
                state = CRLF
                continue
            res += b"\r"                        #Одиночный \r: возврат в начало строки
            cur.clear()
            state = NORMAL
        elif state == CRLF:
            if byte == 0x0D:
                state = PEEK
                continue
            res += b"\r\n"
            cur.clear()
            state = NORMAL
        elif state == PEEK:
            if byte in (0x0D, 0x0A):            #Строка кончилась раньше подписи - это не полоса
                decide(res, False)
            else:
                peek.append(byte)
                if byte == 0x3A:                #':' - подпись целиком
                    decide(res, cur.startswith(peek))
                elif len(peek) >= LABEL_MAX:
                    decide(res, False)
                continue
        put(res, byte)
    out.write(res)
    out.flush()

res = bytearray()
if state == CR:
    res += b"\r"
elif state == CRLF:
    res += b"\r\n"
elif state == PEEK:
    decide(res, False)
out.write(res)
out.flush()
