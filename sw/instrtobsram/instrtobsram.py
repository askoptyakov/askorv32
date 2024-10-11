import re
from sys import argv

string_list = [['#File_format=Hex'], ['#Address_depth=2048'], ['#Data_width=[32]']]
input = argv[1]
output = argv[2]

with open(input, "r") as file:
    binary_data = file.read()

data = re.findall('(\:[\t ][a-fA-F0-9]{8})', binary_data)

result = []
result2 = []
for string in data:
    block0 = re.split('[\t ]', string)  
    result.append([block0[1]])
    
result2 = string_list + result
print("Файл изменен или создан")

with open(output, 'w') as file:
    for sublist in result2:
        for item in sublist:
            file.write(item + '\n') 
