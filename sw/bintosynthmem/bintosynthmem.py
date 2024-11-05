import re
from sys import argv

#Переменные объёма памяти инструкций и данных
imem_bytesize = 0
dmem_bytesize = 0

input = "fw/Debug/riscv.bin" #argv[1]
output_i = "hw/src/mem_init/i.mem" #argv[2]
output_d = "hw/src/mem_init/d.mem" #argv[3]

with open(input, "rb") as file:
    binary_data = file.read()

mem = [[],[]]

#Расчёт размера памяти imem
for b, byte in enumerate(binary_data):
    if (b < 32768):
        if (byte): imem_bytesize = b + 1
    else:
        if (byte): dmem_bytesize = b - 32768 + 1

imem_bytesize = imem_bytesize + (4-(imem_bytesize%4))
dmem_bytesize = dmem_bytesize + (4-(dmem_bytesize%4))

print("SYNTH ", end='')
print("IMEM: {0:11d} байт".format(imem_bytesize))
print("SYNTH ", end='')
print("DMEM: {0:11d} байт".format(dmem_bytesize))


data = re.findall('(\:[\t ][a-fA-F0-9]{8})', binary_data)

instrlist = []
for string in data:
    block0 = re.split('[\t ]', string)  
    instrlist.append([block0[1]])

with open(output, 'w') as file:
    for sublist in instrlist:
        for item in sublist:
            file.write(item + '\n') 

print("Сформирован файл синтезированной памяти")