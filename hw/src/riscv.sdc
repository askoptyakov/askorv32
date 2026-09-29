//Временные ограничения askoRV32 (Tang Nano 9K)
//clk - генератор платы 27 МГц; такт ядра и памяти даёт PLL (clk_pll в clock.sv).
//tck_pad_i - JTAG отладчика (выделенные выводы GW1NR-9, IO_LOC не нужен). Сигналы JTAG выбираются
//тактом clk в jtag_tap_gowin, поэтому пути между доменами не анализируются.
create_clock -name clk     -period 37.037 -waveform {0 18.518} [get_ports {clk}]
//Такт конвейерного ядра и памяти (CORE_TYPE = PIPELINE_CORE): 45 МГц от PLL (параметры PLL_* в top.sv).
//Ограничение - рабочая частота: отчёт должен быть без отрицательного запаса (TNS = 0). Fmax конвейера -
//48.5 МГц при place_option 1 или 2, 45.7 МГц при 0 (журнал в hw/info/performance_roadmap.md). Чтобы
//проверить запас к другой частоте, поменяйте период. В однотактном ядре такт ядра получается из
//clk_base делением на 3 (clock.sv) и этим ограничением не описан.
create_clock -name clk_core -period 22.222 -waveform {0 11.111} [get_nets {clk_base}]
create_clock -name clk_tck -period 400.000 -waveform {0 200.000} [get_ports {tck_pad_i}]
set_clock_groups -asynchronous -group [get_clocks {clk_tck}] -group [get_clocks {clk clk_core}]
//Ч12: clk (27 МГц) и clk_core связаны через PLL, и анализатор считал переходы между ними обычными путями.
//Единственный переход - DTM (clk) <-> DM (clk_core) - защищён синхронизатором (toggle + 2 триггера)
set_false_path -from [get_clocks {clk}] -to [get_clocks {clk_core}]
set_false_path -from [get_clocks {clk_core}] -to [get_clocks {clk}]
