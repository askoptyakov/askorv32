# Модуль TIM

## Вход модуля
|Название       |Размер, bit|  Тип   |Описание|
|:-------:      |:---------:|:------:|:------:|
|Prescaler      |     16    |  reg   | Предделитель системной частоты таймера |
|Counter Mode   |     2     |  reg   | Напрвление счёта |
|Counter Period |     16    |  reg   | Значение переполнения таймера      |
|Pulse_1          |     16    |  reg   | Значение сравнения                       |
|Pulse_2          |     16    |  reg   | Значение сравнения                       |
|Pulse_3          |     16    |  reg   | Значение сравнения                       |
|Pulse_4          |     16    |  reg   | Значение сравнения                       |
|Pulse_5          |     16    |  reg   | Значение сравнения                       |
|Pulse_6          |     16    |  reg   | Значение сравнения                       |

## Выход модуля

|Название       |Размер, bit|  Тип   |Описание|
|:-------:      |:---------:|:------:|:------:|
|Out Counter    |     16    |  reg   | текущее значение счетчика таймера      |
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


## Назначение: 

Управляемый простой счётчик для подключения к процессору risc-v.

## Функционал:
- Управляемое предварительное деление таковой частоты (счётчик со сбросом по значению *Prescaler*);
- Управлемое направление счёта согласно регистру *Counter Mode* (00 - вверх, 01 - вниз, 10 - вверх-вниз);
- Управлемое переполнение счётчика согласно регистру *Counter Period*;
- У таймера реализуется 6 независимых канала они же выходы *out_p*, которые могут подключаться к физическим пинам (так же реализованны инвертированые сигналы *out_n*)
- Управлемое значение сравнения *Pulse* для каждого канала.