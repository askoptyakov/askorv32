#### Добавляем целочисленные инструкции RISC-V (RV32I)
| Команда | Описание                            |&check;/&cross;|
|---------|-------------------------------------|:-------------:|
| LUI     | Load Upper Immediate                | &check;       |
| AUIPC   | Add Upper Immediate to PC           | &cross;       |
| JAL     | Jump and Link                       | &check;       |
| JALR    | Jump and Link Register              | &cross;       |
| BEQ     | Branch if Equal                     | &check;       |
| BNE     | Branch if Not Equal                 | &check;       |
| BLT     | Branch if Less Than                 | &cross;       |
| BGE     | Branch if Greater or Equal          | &cross;       |
| BLTU    | Branch if Less Than Unsigned        | &cross;       |
| BGEU    | Branch if Greater or Equal Unsigned | &cross;       |
| LB      | Load Byte                           | &cross;       |
| LH      | Load Half                           | &cross;       |
| LW      | Load Word                           | &check;       |
| LBU     | Load Byte Unsigned                  | &cross;       |
| LHU     | Load Half Unsigned                  | &cross;       |
| SB      | Store Byte                          | &cross;       |
| SH      | Store Half                          | &cross;       |
| SW      | Store Word                          | &check;       |
| ADD     | Add                                 | &check;       |
| ADDI    | Add Immediate                       | &check;       |
| SUB     | Subtract                            | &check;       |
| SLL     | Shift Left Logical                  | &check;       |
| SLLI    | Shift Left Logical Immediate        | &check;       |
| SLT     | Set Less Than                       | &check;       |
| SLTI    | Set Less Than Immediate             | &check;       |
| SLTU    | Set Less Than Unsigned              | &cross;       |
| SLTIU   | Set Less Than Unsigned Immediate    | &cross;       |
| XOR     | Exclusive OR                        | &check;       |
| XORI    | Exclusive OR Immediate              | &check;       |
| SRL     | Shift Right Logical                 | &check;       |
| SRLI    | Shift Right Logical Immediate       | &check;       |
| SRA     | Shift Right Arithmetic              | &check;       |
| SRAI    | Shift Right Arithmetic Immediate    | &check;       |
| OR      | OR                                  | &check;       |
| ORI     | OR Immediate                        | &check;       |
| AND     | AND                                 | &check;       |
| ANDI    | AND Immediate                       | &check;       |

#### Таблица истинности основного дешифратора устройства управления
|Команда|  op   |RegWrite|ImmSrc|AluSrc|MemWrite|ResultSrc|Branch|ALUOp|Jump|
|-------|:-----:|:------:|:----:|:----:|:------:|:-------:|:----:|:---:|:--:|
| lw    |0000011| 1      | 000  | 1    | 0      | 01      | 0    | 00  | 0  |
| sw    |0100011| 0      | 001  | 1    | 1      | 00      | 0    | 00  | 0  |
| тип R |0110011| 1      | 000  | 0    | 0      | 00      | 0    | 10  | 0  |
|beq,bne|1100011| 0      | 010  | 0    | 0      | 00      | 1    | 01  | 0  |
| тип I |0010011| 1      | 000  | 1    | 0      | 00      | 0    | 10  | 0  |
| jal   |1101111| 1      | 011  | 0    | 0      | 10      | 0    | 00  | 1  |
| lui   |0110111| 1      | 100  | 1    | 0      | 00      | 0    | 00  | 0  |

#### Кодировка знакового расширения непосредственного числа
|ImmSrc| ImmExt                                                        |Тип| Описание                    |
|:----:|---------------------------------------------------------------|:-:|:---------------------------:|
| 000  |<code>{{20{Imm[31]}},Imm[31:20]}</code>                        | I |12-битная константа со знаком|
| 001  |<code>{{20{Imm[31]}},Imm[31:25],Imm[11:7]}</code>              | S |12-битная константа со знаком|
| 010  |<code>{{20{Imm[31]}},Imm[7],Imm[30:25],Imm[11:8],1'b0}</code>  | B |13-битная константа со знаком|
| 011  |<code>{{12{Imm[31]}},Imm[19:12],Imm[20],Imm[30:21],1'b0}</code>| J |21-битная константа со знаком|
| 100  |<code>{Imm[31:12],{12{1'b0}}}</code>                           | U |20-битная константа без знака|

#### Управляющие сигналы АЛУ
|ALUControl| Операция | Описание                    |
|:--------:|:--------:|-----------------------------|
| 000      | +        |ADD - Сложение               |
| 001      | -        |SUB - Вычитание              |
| 010      | &        |AND - Побитовое "И"          |
| 011      | |        |OR  - Побитовое "ИЛИ"        |
| 100      | ^        |XOR - Исключающее "ИЛИ"      |
| 101      | <        |SLT - Меньше                 |
| 110      | <<       |SLL - Логический сдвиг влево |
| 111      | >>       |SRL - Логический сдвиг вправо|

#### Полезные ссылки
1. [Дополнительные материалы к серии книг Дэвид М. Харрис и Сара Л. Харрис "Цифровая схемотехника и архитектура компьютера"](https://pages.hmc.edu/harris/ddca/)