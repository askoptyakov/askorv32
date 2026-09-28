//Временные ограничения askoRV32 (Tang Nano 9K)
//clk - генератор платы 27 МГц; остальные такты ядра и памяти получаются делением в логике.
//tck_pad_i - JTAG отладчика (выделенные выводы GW1NR-9, IO_LOC не нужен). Сигналы JTAG выбираются
//тактом clk в jtag_tap_gowin, поэтому пути между доменами не анализируются.
create_clock -name clk     -period 37.037 -waveform {0 18.518} [get_ports {clk}]
//Такт конвейерного ядра и памяти (CORE_TYPE = PIPELINE_CORE): 27 МГц / 2 = 13.5 МГц. В однотактном
//ядре такт ядра получается из clk_div2 делением на 3 (clock.sv) и этим ограничением не описан.
create_clock -name clk_core -period 74.074 -waveform {0 37.037} [get_nets {clk_div2}]
create_clock -name clk_tck -period 400.000 -waveform {0 200.000} [get_ports {tck_pad_i}]
set_clock_groups -asynchronous -group [get_clocks {clk_tck}] -group [get_clocks {clk clk_core}]
