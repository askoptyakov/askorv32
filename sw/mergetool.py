import re

#0.1 Соотносим блоки BSRAM и начальные позиции записи в строке *.fs
              #    0    1    2    3    4    5    6    7   8   9  10
bsram_stPosR10 = [2570,2390,2210,2030,1850,1670,1490,950,770,590,410]
              #    0    1    2    3    4    5    6    7    8    9   10  11  12  13  14
bsram_stPosR28 = [2750,2570,2390,2210,2030,1850,1670,1490,1310,1130,950,770,590,410,230]
bsram_stPos = [bsram_stPosR10, bsram_stPosR28]
bsram_stStr = [999-1         , 1255-1        ]
#0.2 Позиции изменяемых битов при каждом новом проходе строки BSRAM файла *.fs
bit_loc_pas0 = [138,129,121,112,103,95,86,77,61,51,43,35,26,17,9,0]                                 #Позиции битов для первого прохода
bit_loc_pas1 = [139,130,122,113,104,96,88,78,62,52,44,36,27,18,10,1]                                #Позиции битов для второго прохода
bit_loc_pas2 = [144,135,127,118,110,101,92,84,66,58,49,40,32,23,14,6]                               #Позиции битов для третьего прохода
bit_loc_pas3 = [145,136,128,119,111,102,93,85,68,59,50,41,33,24,16,7]                               #Позиции битов для четвертого прохода
bit_loc_pas = [bit_loc_pas0, bit_loc_pas1, bit_loc_pas2, bit_loc_pas3]                              #Собираем массивы в один лист для дальнейшей работы с ним
#1 Открываем бинарник mcu
with open("fw/Debug/riscv.bin", "rb") as file:
    binary_data = file.read()
#2 Преобразуем машинный код в 4 строки для BSRAM и заполняем строки до полного обьема
bsram = [[],[],[],[]]
i = 0
for byte in binary_data:                                                                            #Раскидываем байты файла *.bin между 4 строками для блоков BSRAM
    bsram[i].append(byte)
    if (i == 3):
        i = 0
    else: i = i + 1   
i = 0
j = 0
for i in range(4):
    for j in range(len(bsram[i]), 2048):                                                            #Дополняем строки до полного объёма блоков BSRAM
        bsram[i].append(0)

#3 Анализируем файл размещения BSRAM в плис *.posp
with open("hw/impl/pnr/riscv.posp", "r") as file:                                                   #Открываем *.posp
    text_data = file.read()
imem_list = re.findall("imem.*", text_data)                                                         #Ищем место где размещается память инструкций(imem)
bsram_loc = []
for string in imem_list:
    block0 = re.findall('([0-9]+ )', string)                                                        #Одна или несколько цифр перед пробелом это номер представления BSRAM
    block1 = re.findall('(R[0-9]+)', string)                                                        #Цифра вместе с буквой R определяет зону расположения блока BSRAM
    block2 = re.findall(r'(\[[0-9]+\])', string)                                                    #Цифра в квадратных скобках показывает расположение блока BSRAM в строке
    bsram_loc.append([block0[0], block1[0], block2[0]])
    print(bsram_loc)
for i , string in enumerate(bsram_loc):                                                             #Удаляем все символы из строк и преобразовываем строки в числа
    for j, element in enumerate(string):
        if (j == 1):                                                                                #Если элемент 1, то происходит замена, на:                                                                           
            match element:
                case 'R10': bsram_loc[i][j] = 0                                                     #Заменяем R10 на 0
                case 'R28': bsram_loc[i][j] = 1                                                     #Заменяем R28 на 1
                case _: print(element,'Ошибка! Сектор BSRAM не существует!')                        #Несуществующий сектор BSRAM
        else: bsram_loc[i][j] = int(re.sub('[^0-9]', '', element))                                  #Откидываем квадратные скобки
bsram_loc.sort()                                                                                    #Сортируем строки по порядку расположения BSRAM в проекте плис
#4 Подменяем нужные фрагменты в файле *.fs
with open("hw/impl/pnr/ao_0.fs", "r") as file:                                                      #Открываем *.fs и выгрузим все строки отдельно в список
    conf_data = file.readlines()

for bsram_num in range(4):                                                                          #Сначала определим какой блок BSRAM и стартовый адрес записи
    bsram_zone = bsram_loc[bsram_num][1]                                                            #Зона в которой располагается BSRAM: 0 - R10; 1 - R28;       
    bsram_no   = bsram_loc[bsram_num][2]                                                            #Номер блока BSRAM в который записываем
    base_str   = bsram_stStr[bsram_zone]                                                            #Базовый номер строки для начала записи
    base_pos = bsram_stPos[bsram_zone][bsram_no]                                                    #Базовая позиция символа для начала записи
    shift_str = 0                                                                                   #Смещение базового номера строки
    bsram_str = ['0'] * 155                                                                         #Инициализируем список символов строки BSRAM файла *.fs нулевыми символами
    for i in range(256):                                                                            #Обнуляем все данные в текущем блоке BSRAM
        current_str = base_str - i                                                                  #Проходим по всем строкам
        first_part_of_str = conf_data[current_str][:base_pos-154]                                   #Оставляем без измененной первую часть строки
        second_part_of_str = ''.join(bsram_str)                                                     #Изменяем вторую часть строки на "0" для дальнейшей обработки
        third_part_of_str = conf_data[current_str][base_pos+1:]                                     #Оставляем без измененной третью часть строки
        conf_data[current_str] = first_part_of_str + second_part_of_str + third_part_of_str         #Собираем все части строк в одну
    bit_list0 = []                                                                                  
    bit_list1 = []
    bit_list = [] 
    for i, byte in enumerate(bsram[bsram_num]):
        each2bytes = i%2
        if (each2bytes):                                                                            #Создаём список с битами 2ух байт для записи в строку BSRAM
            bit_list1 = [1 if x=='1' else 0 for x in "{:08b}".format(byte)]
            bit_list = bit_list1 + bit_list0
        else:    
            bit_list0 = [1 if x=='1' else 0 for x in "{:08b}".format(byte)]
        if (each2bytes):                                                                            #Расставляем битики данных в одной строке BSRAM
            j = i//2                                                                                #Счётчик пар байтов
            p = j//256                                                                              #Номер прохода (всего 4 прохода)
            if((j % 256) == 0): shift_str = 0                                                       #Осуществляем сброс смещения строки каждые 256 значений
            current_str = base_str + shift_str
            bsram_str = list(conf_data[current_str][base_pos-154:base_pos+1])                       #Берём за основу строку из файла и заменяем в ней нужные символы
            for k, bit in enumerate(bit_list):
                bsram_str[154-bit_loc_pas[p][k]] = str(bit)
        
        #Записываем битики в строку BSRAM выгруженную из файла *.fs
            first_part_of_str = conf_data[current_str][:base_pos-154]                               #Оставляем без измененной первую часть строки
            second_part_of_str = ''.join(bsram_str)                                                 #Изменяем вторую часть строки (только в ней хронятся полезные данные)
            third_part_of_str = conf_data[current_str][base_pos+1:]                                 #Оставляем без измененной третью часть строки
            conf_data[current_str] = first_part_of_str + second_part_of_str + third_part_of_str     #Собираем 3 части строки в одну
            #Определяем номер строки для следующей записи
            match ((j % 256) % 4):                                                                  #Всего 4 прохода по 256 строк          
                case 0: shift_str = shift_str - 128                                                 #Начальная позиция для первого прохода
                case 1: shift_str = shift_str + 64                                                  #Начальная позиция для второго прохода
                case 2: shift_str = shift_str - 128                                                 #Начальная позиция для третьего прохода
                case 3: shift_str = shift_str + 191                                                 #Начальная позиция для четвертого прохода

    print('Блок BSRAM', bsram_num, 'записан!')   
with open("hw/impl/pnr/riscv.fs", "w") as file:                                                     #Запись данных в новый файл riscv.fs
    file.writelines(conf_data)
