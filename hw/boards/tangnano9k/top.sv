//==============================================================================================
// top.sv - ВЕРХНИЙ УРОВЕНЬ askoRV32. ФАЙЛ СОЗДАН КОНФИГУРАТОРОМ ПЛИС - НЕ РЕДАКТИРУЙТЕ ВРУЧНУЮ.
// Источник: fw/boards/tangnano9k/tangnano9k.gwsoc; генератор: sw/socgen/socgen.py (кнопка «Собрать» в Eclipse).
// Процессор (ядро, память, отладчик, CLINT, PLIC) - в hw/src/cpu.sv, он правится вручную; здесь -
// параметры платы для cpu и пользовательская периферия на его порту bus_per.
// Плата: Tang Nano 9K; ПЛИС: GW1NR-LV9QN88PC6/I5.
//==============================================================================================

module top #(
                //Ядро
             parameter bit CORE_TYPE         = 0, //1 - однотактное, 0 - конвейерное
             parameter bit M_EXT             = 1, //расширение M
             parameter int DIV_BPC           = 2, //бит частного за такт: 1, 2, 4
             parameter int RF_TYPE           = 0, //регистровый файл: 0 - LUT; BSRAM (2 блока SDPB): 1 - чтение на фронте D->E, 2 - по спаду в D
                //Память команд и данных
             parameter bit IMEM_TYPE         = 1, //1 - BSRAM, 0 - синтезированная
             parameter int BSRAM_IMEM_SIZE   = 32, //кБайт: 8/16/32
             parameter int SYNTH_IMEM_SIZE   = 256, //слов по 4 Байт
             parameter IMEM_INIT_FILE        = "mem_init/i.mem",
             parameter bit DMEM_TYPE         = 1, //1 - BSRAM, 0 - синтезированная
             parameter int BSRAM_DMEM_SIZE   = 8, //кБайт: 8/16/32
             parameter int SYNTH_DMEM_SIZE   = 256, //слов по 4 Байт
             parameter DMEM_INIT_FILE        = "mem_init/d.mem",
                //Отладка и прерывания
             parameter bit DEBUG_EN          = 1, //модуль отладки JTAG (выводы TMS 5, TCK 6, TDI 7, TDO 8)
             parameter int PLIC_SOURCES      = 8, //источников PLIC (1..31)
                //Тактирование: кварц 27 МГц, rPLL -> 40.5 МГц (PFD 13.5, VCO 648 МГц)
             parameter FCLKIN                = "27", //частота кварца, МГц (строка для rPLL)
             parameter PLL_DEVICE            = "GW1NR-9C", //кристалл для rPLL
             parameter int XTAL_KHZ          = 27000, //частота кварца, кГц
             parameter int PLL_IDIV_SEL      = 1,
             parameter int PLL_FBDIV_SEL     = 2,
             parameter int PLL_ODIV_SEL      = 16)
   (
    //Такт и сброс
    input wire          CLOCK,                //вывод 52
    input wire          RESET,                //вывод 3
    //GPIO
    inout wire          DI1,                  //вывод 75
    inout wire          DI2,                  //вывод 77
    inout wire          DI3,                  //вывод 36
    inout wire          RO1,                  //вывод 74
    inout wire          RO2,                  //вывод 76
    inout wire          RO3,                  //вывод 39
    //TM1638
    inout wire   [2:0]  GPIO,                 //выводы 25, 26, 27
    //UART
    output wire         UART_TX,              //вывод 17
    input wire          UART_RX,              //вывод 18
    //SIFU
    input wire          NSB_AB,               //вывод 11
    input wire          NSB_BA,               //вывод 10
    input wire          NSB_BC,               //вывод 15
    input wire          NSB_CB,               //вывод 14
    input wire          NSB_CA,               //вывод 13
    input wire          NSB_AC,               //вывод 16
    output wire         VS1,                  //вывод 69
    output wire         VS2,                  //вывод 29
    output wire         VS3,                  //вывод 57
    output wire         VS4,                  //вывод 68
    output wire         VS5,                  //вывод 30
    output wire         VS6,                  //вывод 56
    output wire         GRID,                 //вывод 51
    //ADC
    output wire         ADC_V_CS,             //вывод 48
    output wire         ADC_V_SCLK,           //вывод 70
    input wire          ADC_V_SDO,            //вывод 71
    input wire          ADC_V_CMP,            //вывод 82
    output wire         ADC_C_CS,             //вывод 32
    output wire         ADC_C_SCLK,           //вывод 72
    input wire          ADC_C_SDO,            //вывод 73
    input wire          ADC_C_CMP             //вывод 79
`ifndef GWSOC_NO_JTAG_PINS
    //Выводы JTAG ПЛИС: для примитива GW_JTAG (отладчик), назначения в .cst не требуются
   ,input  logic        tck_pad_i, tms_pad_i, tdi_pad_i,
    output logic        tdo_pad_o
`endif
);
`ifdef GWSOC_NO_JTAG_PINS
    //Сборка без выводов JTAG (apicula для этого кристалла не поддерживает GW_JTAG, DEBUG_EN = 0)
    logic tck_pad_i = 1'b0, tms_pad_i = 1'b1, tdi_pad_i = 1'b0;
    logic tdo_pad_o;
`endif
    //#1 Карта адресов пользовательской периферии: у каждого устройства окно 16 МБайт (маска 0xFF00_0000).
    //Системные окна - в cpu.sv: IMEM 0x0000_0000, CLINT 0x0200_0000, PLIC 0x0C00_0000, DMEM 0x1000_0000;
    //0x1F00_0000 - устройства тестбенча. Всё вне системных окон cpu отдаёт на порт bus_per
    localparam logic [31:0] GPIO_BASE   = 32'h1100_0000;
    localparam logic [31:0] TM1638_BASE = 32'h1200_0000;
    localparam logic [31:0] UART_BASE   = 32'h1400_0000;
    localparam logic [31:0] SIFU_BASE   = 32'h1600_0000;
    localparam logic [31:0] ADC_BASE    = 32'h1700_0000;
    localparam logic [31:0] WIN_MASK    = 32'hFF00_0000;

    //Частота шины периферии (clk_per), МГц, целая часть: для делителей периферии (TM1638).
    //Однотактное ядро с BSRAM делит базовую частоту на 3. Прошивке то же значение задаёт SYSCLK_HZ.
    localparam int CLK_BASE_MHZ = XTAL_KHZ * (PLL_FBDIV_SEL + 1) / (PLL_IDIV_SEL + 1) / 1000;
    localparam int CLK_DMEM_MHZ = ((IMEM_TYPE | DMEM_TYPE) & CORE_TYPE) ? CLK_BASE_MHZ / 3 : CLK_BASE_MHZ;

    //#2 Процессор (cpu.sv): такт, сброс, ядро, отладчик, память команд и данных, CLINT, PLIC.
    //Параметры платы переопределяют значения по умолчанию из cpu.sv
    logic        clk_per, rst_per;
    logic [ 3:0] bus_per_Write;
    logic        bus_per_Read;
    logic [31:0] bus_per_Addr, bus_per_WData, bus_per_RData;
    logic [15:0] irq_local;
    logic [PLIC_SOURCES:1] irq_src;
    logic        boot_hold;                  //Загрузчик программы из SPI-флеш: ядро в сбросе, пока он пишет память
    logic [ 3:0] boot_Write;
    logic [31:0] boot_Addr, boot_WData;

    cpu #(.CORE_TYPE(CORE_TYPE), .M_EXT(M_EXT), .DIV_BPC(DIV_BPC), .RF_TYPE(RF_TYPE),
          .IMEM_TYPE(IMEM_TYPE), .BSRAM_IMEM_SIZE(BSRAM_IMEM_SIZE), .SYNTH_IMEM_SIZE(SYNTH_IMEM_SIZE), .IMEM_INIT_FILE(IMEM_INIT_FILE),
          .DMEM_TYPE(DMEM_TYPE), .BSRAM_DMEM_SIZE(BSRAM_DMEM_SIZE), .SYNTH_DMEM_SIZE(SYNTH_DMEM_SIZE), .DMEM_INIT_FILE(DMEM_INIT_FILE),
          .DEBUG_EN(DEBUG_EN), .PLIC_SOURCES(PLIC_SOURCES),
          .FCLKIN(FCLKIN), .PLL_DEVICE(PLL_DEVICE), .PLL_IDIV_SEL(PLL_IDIV_SEL), .PLL_FBDIV_SEL(PLL_FBDIV_SEL), .PLL_ODIV_SEL(PLL_ODIV_SEL))
        cpu (.clk(CLOCK), .rst_n(RESET),
             .tck_pad_i(tck_pad_i), .tms_pad_i(tms_pad_i), .tdi_pad_i(tdi_pad_i), .tdo_pad_o(tdo_pad_o),
             .clk_per(clk_per), .rst_per(rst_per),
             .bus_per_Write(bus_per_Write), .bus_per_Read(bus_per_Read), .bus_per_Addr(bus_per_Addr), .bus_per_WData(bus_per_WData), .bus_per_RData(bus_per_RData),
             .irq_local(irq_local), .irq_src(irq_src),
             .boot_hold(boot_hold), .boot_Write(boot_Write), .boot_Addr(boot_Addr), .boot_WData(boot_WData));

    //Такт блоков АЦП ADC121: свой rPLL от кварца, 54 МГц (PFD 27, VCO 864 МГц). Кадр АЦП и период запуска
    //работают от него, регистры - от такта шины (переход между тактами - в adc121.sv); ограничение - в riscv.sdc
    logic clk_adc, adc_lock;
    clk_pll #(.FCLKIN(FCLKIN), .DEVICE(PLL_DEVICE), .IDIV_SEL(0), .FBDIV_SEL(1), .ODIV_SEL(16)) adc_pll
        (.clkin(CLOCK), .clkout(clk_adc), .lock(adc_lock));

    //#3 Шина пользовательской периферии (memmux): ведомые перечислены от старшего номера к младшему
    logic [ 3:0] gpio_Write, tm1638_Write, uart_Write, sifu_Write, adc_Write;
    logic [31:0] gpio_Addr, tm1638_Addr, uart_Addr, sifu_Addr, adc_Addr;
    logic [31:0] gpio_WriteData, tm1638_WriteData, uart_WriteData, sifu_WriteData, adc_WriteData;
    logic [31:0] gpio_ReadData, tm1638_ReadData, uart_ReadData, sifu_ReadData, adc_ReadData;
    logic [ 4:0] sRead;

    memmux #(.MEMORY_TYPE(DMEM_TYPE), .SLAVES(5),
              .MATCH_ADDR ({GPIO_BASE, TM1638_BASE, UART_BASE, SIFU_BASE, ADC_BASE}),
              .MATCH_MASK ({5{WIN_MASK}}))
            permux
             (.clk(clk_per), .rst(rst_per),
              .mWrite(bus_per_Write), .mRead(bus_per_Read), .mAddr(bus_per_Addr), .mWData(bus_per_WData), .mRData(bus_per_RData),
              .sWrite({gpio_Write, tm1638_Write, uart_Write, sifu_Write, adc_Write}),
              .sRead (sRead),
              .sAddr ({gpio_Addr, tm1638_Addr, uart_Addr, sifu_Addr, adc_Addr}),
              .sWData({gpio_WriteData, tm1638_WriteData, uart_WriteData, sifu_WriteData, adc_WriteData}),
              .sRData({gpio_ReadData, tm1638_ReadData, uart_ReadData, sifu_ReadData, adc_ReadData}));

    //-1- GPIO: 6 лин., регистры с 32'h1100_0000 (линия 0 - младший разряд)
    gpio_top #(.MEMORY_TYPE(DMEM_TYPE), .WIDTH(6)) gpio
              (.clk(clk_per), .rst(rst_per),
               .Write(gpio_Write), .Addr(gpio_Addr), .WData(gpio_WriteData), .RData(gpio_ReadData),
               .io_ports({RO3, RO2, RO1, DI3, DI2, DI1}));

    //-2- TM1638: внешний модуль LED&KEY, регистры с 32'h1200_0000
    tm1638_top #(.MEMORY_TYPE(DMEM_TYPE), .CLK_MHZ(CLK_DMEM_MHZ)) tm1638
                (.clk(clk_per), .rst(rst_per),
                 .Write(tm1638_Write), .Addr(tm1638_Addr), .WData(tm1638_WriteData), .RData(tm1638_ReadData),
                 .tm_dio(GPIO[0]), .tm_clk(GPIO[1]), .tm_stb(GPIO[2]));

    //-3- UART: 115200 бит/с (div 351, фактически 115057, ошибка 0.12 %), чётность none, стоп-битов 1, FIFO 16
    //    регистры с 32'h1400_0000
    logic irq_uart;
    uart_top #(.MEMORY_TYPE(DMEM_TYPE), .DEPTH(16), .DIV_INIT(351), .STOP_INIT(1), .PARITY_INIT(0)) uart
                (.clk(clk_per), .rst(rst_per),
                 .Write(uart_Write), .Read(sRead[2]), .Addr(uart_Addr), .WData(uart_WriteData), .RData(uart_ReadData),
                 .tx(UART_TX), .rx(UART_RX), .irq(irq_uart));

    //-4- SIFU: СИФУ трёхфазного мостового выпрямителя, тик ГПН 500 кГц (DIV 80), DELAY 400, импульс 150 тиков
    //    регистры с 32'h1600_0000; входы - плата синхронизации NSB (0 - оптрон открыт), выходы - тиристоры VS1..VS6; есть имитатор сети
    logic irq_sifu;
    sifu_top #(.MEMORY_TYPE(DMEM_TYPE), .DIV_INIT(16'd80), .DELAY_INIT(12'd400), .WIDTH_INIT(12'd150), .SIM_EN(1),
               .AMAX_INIT(12'd3333), .UEXT_EN(1'b0)) sifu
                (.clk(clk_per), .rst(rst_per),
                 .Write(sifu_Write), .Addr(sifu_Addr), .WData(sifu_WriteData), .RData(sifu_ReadData),
                 .sync_ab(NSB_AB), .sync_ba(NSB_BA), .sync_bc(NSB_BC), .sync_cb(NSB_CB), .sync_ca(NSB_CA), .sync_ac(NSB_AC),
                 .vs1(VS1), .vs2(VS2), .vs3(VS3), .vs4(VS4), .vs5(VS5), .vs6(VS6),
                 .grid_o(GRID),
                 .tick_o(), .run_o(), .u_i(16'd0),   //Угол - регистр ALPHA (регулятор - программа)
                 .irq(irq_sifu));

    //-5- ADC: АЦП ADC121S051, каналов 2 (V - плата ADC_V, C - плата ADC_C), такт clk_adc 54 МГц, SCLK 6.75 МГц (DIV 3), до 327 тыс. отсчётов/с на канал, среднее по 1
    //    регистры канала i - с 32'h1700_0000 + i * 0x40
    logic irq_adc;
    logic [1:0][15:0] adc_wmean;   logic [1:0] adc_wstb;   //Средние за окно каналов (код * 16)
    adc_top #(.MEMORY_TYPE(DMEM_TYPE), .NCH(2), .DIV_INIT(8'd3), .AVGSH_INIT(4'd0), .CSS_INIT(4'd1), .QUIET_INIT(4'd8),
              .CSINV_INIT(4'b0000), .CMP_EN(4'b0011), .CPOL_INIT(4'b0000), .CLK_HZ(32'd54000000), .WIN_EN(1'b1)) adc
             (.clk(clk_per), .rst(rst_per), .adc_clk(clk_adc), .adc_lock(adc_lock),
              .Write(adc_Write), .Addr(adc_Addr), .WData(adc_WriteData), .RData(adc_ReadData),
              .adc_cs_n({ADC_C_CS, ADC_V_CS}), .adc_sclk({ADC_C_SCLK, ADC_V_SCLK}),
              .adc_sdo({ADC_C_SDO, ADC_V_SDO}), .adc_cmp({ADC_C_CMP, ADC_V_CMP}),
              .win_i(1'b0), .wmean_o(adc_wmean), .wstb_o(adc_wstb), .irq(irq_adc));

    //-6- Прерывания периферии: источники PLIC (MEI, векторный режим) и локальные линии LI0..LI15
    //    UART: источник PLIC 1
    //    SIFU: источник PLIC 2
    //    ADC: источник PLIC 3
    assign irq_src   = {1'b0, 1'b0, 1'b0, 1'b0, 1'b0, irq_adc, irq_sifu, irq_uart};   //старший разряд - источник 8, младший - источник 1
    assign irq_local = 16'd0;
endmodule
