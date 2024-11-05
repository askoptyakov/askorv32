#Для создания исполнительного файла EXE используем строку:
#pyinstaller --noconsole --onefile sw/mergetool/mergetool.py

import re
from sys import argv
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
#0.3 Переменые для передачи путей файлов в атрибуты cmd
inputBin = argv[1]
inputPosp = argv[2]
inputFs = argv[3]
output = argv[4]

#0.4 Переменные объёма памяти инструкций и данных
imem_bytesize = 0
dmem_bytesize = 0

#1 Анализируем файл размещения BSRAM в плис *.posp
with open(inputPosp, "r") as file:                                                   #Открываем *.posp
#with open("hw/impl/pnr/riscv.posp", "r") as file:
    text_data = file.read()
mem_list = re.findall("[id]mem.*", text_data)                                                         #Ищем место где размещается память инструкций(imem)
bsram_loc = [[[],[],[],[]],[[],[],[],[]]]
for string in mem_list:
    num_list = re.findall('[id]mem|[0-9]+', string)                                                                                                
    #print(num_list)
    #Наполнение списка позиций BSRAM
    if (num_list[0] == 'imem'):
        bsram_loc[0][int(num_list[1])].append([num_list[2], num_list[3], num_list[4]])
    else:
        bsram_loc[1][int(num_list[1])].append([num_list[2], num_list[3], num_list[4]])
#Удаление незадействоанных кластеров
bsram_loc_sort = [[],[]]
for i, mem in enumerate(bsram_loc):
        bsram_loc_sort[i] = [element for element in mem if element]
#Превращаем строковые элементы в числа + сортировка внутри секторов
for m, mem in enumerate(bsram_loc_sort):
    for c, cluster in enumerate(mem):
        for s, sector in enumerate(cluster):                                                             #Удаляем все символы из строк и преобразовываем строки в числа
            for e, element in enumerate(sector):
                if (e == 1):                                                                                #Если элемент 1, то происходит замена, на:                                                                           
                    match element:                                                                          #Свитч R10, R28
                        case '10': bsram_loc_sort[m][c][s][e] = 0                                                     #Заменяем R10 на 0
                        case '28': bsram_loc_sort[m][c][s][e] = 1                                                     #Заменяем R28 на 1
                        case _: print(element,'Ошибка! Сектор BSRAM не существует!')                        #Несуществующий сектор BSRAM
                else: bsram_loc_sort[m][c][s][e] = int(element)                                  #Откидываем квадратные скобки
        bsram_loc_sort[m][c].sort()                                                                     #Сортируем строки по порядку расположения BSRAM внутри клсастера
                                                                          
#2 Открываем бинарник mcu
with open(inputBin, "rb") as file:
#with open("fw/Debug/riscv.bin", "rb") as file:
    binary_data = file.read()
#3 Преобразуем машинный код в 4 строки для BSRAM и заполняем строки до полного обьема
bsram_mem = [[],[]]
i = 0
#Подсчитываем кол-во используемых кластеров
num_of_imem_clusters = len(bsram_loc_sort[0])
num_of_dmem_clusters = len(bsram_loc_sort[1])                                                                          
#Наполняем массивы памяти BSRAM данными                                                      
for b, byte in enumerate(binary_data):
    cluster = b//8192
    if (b < 32768): #Наполнение памяти инструкций  
        #Расчитываем фактический объём занятой памяти инструкций
        if (byte): imem_bytesize = b + 1  
        if (cluster < num_of_imem_clusters):
            #Добавляем кластер при наличии данных
            if not(b%8192): bsram_mem[0].insert(cluster, [[],[],[],[]])
            #Наполняем сектора данными
            bsram_mem[0][cluster][i].append(byte)
            if (i == 3):
                i = 0
            else: i = i + 1 
    else:           #Наполнение памяти данных
        #Расчитываем фактический объём занятой памяти данных
        if (byte): dmem_bytesize = b - 32768 + 1
        if (cluster < (num_of_dmem_clusters + 4)):
            if not(b%8192): bsram_mem[1].insert(cluster-4, [[],[],[],[]])
            bsram_mem[1][cluster-4][i].append(byte)
            if (i == 3):
                i = 0
            else: i = i + 1

#Дополнение пустых кластеров в памяти данных
while (len(bsram_mem[1]) < num_of_dmem_clusters):
    bsram_mem[1].append([[],[],[],[]])

#Дополняем массивы данных нулями до полного объёма BSRAM
if bsram_mem[0]:
    for c, cluster in enumerate(bsram_mem[0]):
        for i in range(4):
            for j in range(len(bsram_mem[0][c][i]), 2048):                                                            #Дополняем строки до полного объёма блоков BSRAM
                bsram_mem[0][c][i].append(0)                                                                          #Добавляем в массив 
if bsram_mem[1]:
    for c, cluster in enumerate(bsram_mem[1]):
        for i in range(4):
            for j in range(len(bsram_mem[1][c][i]), 2048):                                                            
                bsram_mem[1][c][i].append(0) 

#4 Подменяем нужные фрагменты в файле *.fs
with open(inputFs, "r") as file:                                                                    #Открываем *.fs и выгрузим все строки отдельно в список
#with open("hw/impl/pnr/ao_0.fs", "r") as file:
    conf_data = file.readlines()
for m, mem in enumerate(bsram_mem):
    if mem:
        for c, cluster in enumerate(mem):
            for bsram_num in range(4):                                                                          #Сначала определим какой блок BSRAM и стартовый адрес записи
                bsram_zone = bsram_loc_sort[m][c][bsram_num][1]                                                            #Зона в которой располагается BSRAM: 0 - R10; 1 - R28;       
                bsram_no   = bsram_loc_sort[m][c][bsram_num][2]                                                            #Номер блока BSRAM в который записываем
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
                bit_list0 = []                                                                                  #Младший бит                                                                                  
                bit_list1 = []                                                                                  #Старший бит
                bit_list = []                                                                                   #Переменая из двух бит
                for i, byte in enumerate(bsram_mem[m][c][bsram_num]):                                                     #Перебераем файл .bin для создания файла .fs
                    each2bytes = i%2                                                                            #Каждые два байта
                    if (each2bytes):                                                                            #Создаём список с битами 2ух байт для записи в строку BSRAM
                        bit_list1 = [1 if x=='1' else 0 for x in "{:08b}".format(byte)]                         #Упращеная запись условия обернутого в цикл
                        bit_list = bit_list1 + bit_list0                                                        #Собираем два байта в один лист
                    else:    
                        bit_list0 = [1 if x=='1' else 0 for x in "{:08b}".format(byte)]                         #Упращеная запись условия обернутого в цикл
                    if (each2bytes):                                                                            #Расставляем битики данных в одной строке BSRAM
                        j = i//2                                                                                #Счётчик пар байтов
                        p = j//256                                                                              #Номер прохода (всего 4 прохода)
                        if((j % 256) == 0): shift_str = 0                                                       #Осуществляем сброс смещения строки каждые 256 значений
                        current_str = base_str + shift_str                                                      #Добовляем смещение текущей строки
                        bsram_str = list(conf_data[current_str][base_pos-154:base_pos+1])                       #Берём за основу строку из файла и заменяем в ней нужные символы
                        for k, bit in enumerate(bit_list):                                                      #Перебераем массив bit_list                                                                                                             
                            bsram_str[154-bit_loc_pas[p][k]] = str(bit)                                         #Создаем строку bsram_str из bit_list                         
                        #Записываем битики в строку BSRAM выгруженную из файла *.fs
                        first_part_of_str = conf_data[current_str][:base_pos-154]                               #Оставляем без измененной первую часть строки
                        second_part_of_str = ''.join(bsram_str)                                                 #Изменяем вторую часть строки (только в ней хронятся полезные данные)
                        third_part_of_str = conf_data[current_str][base_pos+1:]                                 #Оставляем без измененной третью часть строки
                        conf_data[current_str] = first_part_of_str + second_part_of_str + third_part_of_str     #Собираем 3 части строки в одну
                        match ((j % 256) % 4):                                                                  #Определяем номер строки для следующей записи (всего 4 прохода)   
                            case 0: shift_str = shift_str - 128                                                 #Начальная позиция для первого прохода
                            case 1: shift_str = shift_str + 64                                                  #Начальная позиция для второго прохода
                            case 2: shift_str = shift_str - 128                                                 #Начальная позиция для третьего прохода
                            case 3: shift_str = shift_str + 191                                                 #Начальная позиция для четвертого прохода
                #print('Память:', m, '; Кластер:', c, '; Сектор', bsram_num)
with open(output, "w") as file:                                                                     #Запись данных в новый файл riscv.fs
#with open("fw/Debug/riscv.fs", "w") as file:
    file.writelines(conf_data)

##Подсчёт объёма загрузки памяти##
print('Статиситика используемой памяти:')
print('--------------------------------')
imem_bytesize = imem_bytesize + (4-(imem_bytesize%4))
if(num_of_imem_clusters):
    full_imem_bytesize = num_of_imem_clusters * 8192
    imem_percentsize = imem_bytesize * 100/full_imem_bytesize
    print("BSRAM ", end='')
    print("IMEM: {0:5d}/{1:5d} байт({2:1.2f} %)".format(imem_bytesize, full_imem_bytesize, imem_percentsize))
    
else:
    print("SYNTH ", end='')
    print("IMEM: {0:11d} байт".format(imem_bytesize))
    

dmem_bytesize = dmem_bytesize + (4-(dmem_bytesize%4))
if(num_of_dmem_clusters):
    full_dmem_bytesize = num_of_dmem_clusters * 8192
    dmem_percentsize = dmem_bytesize * 100/full_dmem_bytesize
    print("BSRAM ", end='')
    print("DMEM: {0:5d}/{1:5d} байт({2:3.2f} %)".format(dmem_bytesize, full_dmem_bytesize, dmem_percentsize))
else:
    print("SYNTH ", end='')
    print("DMEM: {0:11d} байт".format(dmem_bytesize))