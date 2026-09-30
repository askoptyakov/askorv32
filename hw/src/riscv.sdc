//Временные ограничения askoRV32 (Tang Nano 9K). Пути внутри процессорной части - через экземпляр cpu (cpu.sv)
//clk - генератор платы 27 МГц; такт ядра и памяти даёт PLL (clk_pll в clock.sv).
//tck_pad_i - JTAG отладчика (выделенные выводы GW1NR-9, IO_LOC не нужен). Сигналы JTAG выбираются
//тактом clk в jtag_tap_gowin, поэтому пути между доменами не анализируются.
create_clock -name clk     -period 37.037 -waveform {0 18.518} [get_ports {clk}]
//Такт конвейерного ядра и памяти (CORE_TYPE = PIPELINE_CORE): 45 МГц от PLL (параметры PLL_* в top.sv).
//Ограничение - рабочая частота: отчёт должен быть без отрицательного запаса (TNS = 0). Fmax конвейера с
//расширением M - 47.5-48.2 МГц при настройках Gowin по умолчанию (шаг 19 журнала в hw/info/performance_roadmap.md). Чтобы
//проверить запас к другой частоте, поменяйте период. В однотактном ядре такт ядра получается из
//clk_base делением на 3 (clock.sv) и этим ограничением не описан.
create_clock -name clk_core -period 22.222 -waveform {0 11.111} [get_pins {cpu/clk_pll/pll/CLKOUT}]
create_clock -name clk_tck -period 400.000 -waveform {0 200.000} [get_ports {tck_pad_i}]
//Р3/Р4: запас 0.5 нс к периоду такта ядра (джиттер PLL и резерв). Он же заставляет P&R оптимизировать
//размещение под 21.7 нс: с мягкой целью 22.222 нс Gowin останавливается раньше и при любом place_option
//получал 44.3-44.6 МГц, а с запасом 0.5 нс ограничение выполняется при всех трёх вариантах.
set_clock_uncertainty -setup 0.5 -from [get_clocks {clk_core}] -to [get_clocks {clk_core}]
set_clock_groups -asynchronous -group [get_clocks {clk_tck}] -group [get_clocks {clk clk_core}]
//Ч12: clk (27 МГц) и clk_core связаны через PLL, и анализатор считал переходы между ними обычными путями.
//Единственный переход - DTM (clk) <-> DM (clk_core) - защищён синхронизатором (toggle + 2 триггера)
set_false_path -from [get_clocks {clk}] -to [get_clocks {clk_core}]
set_false_path -from [get_clocks {clk_core}] -to [get_clocks {clk}]
//Ч16: модуль отладки (DEBUG_EN = 1) выставляет адрес CSR (csr_addr_q) и адрес System Bus (sbaddress) не меньше
//чем за 2 такта до записи или защёлкивания результата, а значение GPR (gpr_q) забирает через 2 такта после
//выставления адреса (состояния CSR_WR, SB_WAIT, REG_WAIT2 в dm.sv). Пока ядро работает, csr_addr_q = 0, шина
//и gpr_q отладчику не нужны. Поэтому пути от этих регистров и в gpr_q двухтактные. При DEBUG_EN = 0 строки
//не находят регистров (предупреждение, на результат не влияет).
set_multicycle_path -from [get_regs {cpu/g_debug.dm/csr_addr_q*}] -setup -end 2
set_multicycle_path -from [get_regs {cpu/g_debug.dm/csr_addr_q*}] -hold -end 1
set_multicycle_path -from [get_regs {cpu/g_debug.dm/sbaddress*}] -setup -end 2
set_multicycle_path -from [get_regs {cpu/g_debug.dm/sbaddress*}] -hold -end 1
set_multicycle_path -to [get_regs {cpu/g_debug.dm/gpr_q*}] -setup -end 2
set_multicycle_path -to [get_regs {cpu/g_debug.dm/gpr_q*}] -hold -end 1
