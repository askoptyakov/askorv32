import re
from sys import argv
import sys
sys.stdout.reconfigure(encoding="utf-8") #Вывод в UTF-8: консоль сборки Eclipse (Java 18+) декодирует вывод как UTF-8

string_list = [['#File_format=Hex'], ['#Address_depth=2048'], ['#Data_width=32']]
input = argv[1]
output = argv[2]

with open(input, "r") as file:
    binary_data = file.read()

data = re.findall(r'(\:[\t ][a-fA-F0-9]{8})', binary_data)

instrlist = []
for string in data:
    block0 = re.split('[\t ]', string)  
    instrlist.append([block0[1]])

with open(output, 'w') as file:
    for sublist in instrlist:
        for item in sublist:
            file.write(item + '\n') 

print("Сформирован файл синтезированной памяти")