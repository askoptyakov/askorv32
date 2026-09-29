//Цель 100 МГц: P&R тянет ядро до предела, в отчёте - достижимая Fmax. Та же цель задаётся
//для askoRV32 при сравнении (clk_core в hw/src/riscv.sdc, период 10 нс)
create_clock -name clk -period 10 -waveform {0 5} [get_ports {clk}]
