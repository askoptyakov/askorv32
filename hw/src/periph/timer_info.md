# Модуль TIM

## Вход модуля
|Название       |Размер, bit|  Тип   |Описание|
|:-------:      |:---------:|:------:|:------:|
|Prescaler      |     32    |  reg   | Предделитель системной частоты таймера |
|Counter Mode   |     2     |  reg   | «Up» - считает от 0 до переполнения «Down» - считает от 0 до переполнения |
|Counter Period |     32    |  reg   | Значение до которого считает таймер      |
|Pulse_1          |     32    |  reg   | Значение сравнения                       |
|Pulse_2          |     32    |  reg   | Значение сравнения                       |
|Pulse_3          |     32    |  reg   | Значение сравнения                       |
|Pulse_4          |     32    |  reg   | Значение сравнения                       |
|Pulse_5          |     32    |  reg   | Значение сравнения                       |
|Pulse_6          |     32    |  reg   | Значение сравнения                       |

## Выход модуля

|Название       |Размер, bit|  Тип   |Описание|
|:-------:      |:---------:|:------:|:------:|
|out_p_1        |     -    |  wire  | выхоной сигнал сравнения |
|out_n_1        |     -     |  wire  | выхоной сигнал сравнения |
|out_p_2        |     -    |  wire  | выхоной сигнал сравнения |
|out_n_2        |     -     |  wire  | выхоной сигнал сравнения |
|out_p_3        |     -    |  wire  | выхоной сигнал сравнения |
|out_n_3        |     -     |  wire  | выхоной сигнал сравнения |
|out_p_4        |     -    |  wire  | выхоной сигнал сравнения |
|out_n_4        |     -     |  wire  | выхоной сигнал сравнения |
|out_p_5        |     -    |  wire  | выхоной сигнал сравнения |
|out_n_5        |     -     |  wire  | выхоной сигнал сравнения |
|out_p_6        |     -    |  wire  | выхоной сигнал сравнения |
|out_n_6        |     -     |  wire  | выхоной сигнал сравнения |

## Функционал