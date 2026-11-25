# SIFU_MATLAB

Вариант СИФУ для Tang Nano 9K выбирается полем
`"generator": "SIFU_MATLAB"` у блока `SIFU` в `tangnano9k.gwsoc`.
Если поле убрать и повторно запустить socgen, выбирается штатный RTL.

`sifu_matlab.sv` подключает четыре модуля из
`1_Thyristor_rectifier/build/hdl/synthetic/sifu_replay`. Исходная модель зафиксирована в `1_Thyristor_rectifier`, коммит `b689b21`. Счётчик
`Phase_timer` удерживает 4095 до сигнала `Overlap`. Для обновления
файлов запустить в MATLAB `build_hdl('both')` и скопировать
`HDL_DUT.sv`, `Phase_AB.sv`, `Phase_timer.sv` и `Filter_Neg.sv` в эту
папку. Штатный делитель служит источником clock enable.

Обычные режимы прошивки используют `CR.FLT=1` и `CR.DBL=1`, при этих
установках выходы формирует модель. Диагностические режимы с отключённым
фильтром или без сдваивания используют штатный генератор. Шина, PLIC и
показания синхронизации обслуживаются штатным RTL. `GATE[5:0]` отражает
физические выходы, а `GATE[13:8]` показывает прямые импульсы штатного
генератора. При `LOST=1` выходы MATLAB-варианта блокируются.

Интеграционный тест из корня askorv32 (PowerShell):

```powershell
$hdl = Get-ChildItem hw/src/periph/sifu/matlab -Filter '*.sv' | Select-Object -Expand FullName
iverilog -g2012 -s tb_sifu '-Ptb_sifu.MATLAB_EN=1' -Ihw/src/periph -o "$env:TEMP/tb_sifu_matlab.vvp" hw/src/periph/sifu/tb_sifu.sv hw/src/periph/sifu/sifu.sv hw/src/periph/periph_regs.sv @hdl
vvp -n "$env:TEMP/tb_sifu_matlab.vvp"
```

Интеграционный тест прошёл 154 проверки, включая отсутствие повторного
импульса при малом угле после достижения предела счётчика. Сборка
Tang Nano 9K проверена после запуска из встроенной flash. На имитаторе
получено 49,99 Гц, силовой прогон на стенде прошёл успешно.
