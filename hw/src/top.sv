//==============================================================================================
// top.sv - ВЕРХНИЙ УРОВЕНЬ askoRV32. ФАЙЛ СОЗДАН КОНФИГУРАТОРОМ ПЛИС - НЕ РЕДАКТИРУЙТЕ ВРУЧНУЮ.
// Источник: fw/riscv.gwsoc; генератор: sw/socgen/socgen.py (кнопка «Собрать» в Eclipse).
// Процессор (ядро, память, отладчик, CLINT, PLIC) - в cpu.sv, он правится вручную; здесь -
// параметры платы для cpu и пользовательская периферия на его порту bus_per.
//==============================================================================================

module top #(
                //Ядро
             parameter bit CORE_TYPE         = 0, //1 - однотактное, 0 - конвейерное
             parameter bit M_EXT             = 1, //расширение M
             parameter int DIV_BPC           = 2, //бит частного за такт: 1, 2, 4
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
             parameter bit DEBUG_EN          = 1, //модуль отладки JTAG (выводы 5-8)
             parameter int PLIC_SOURCES      = 8, //источников PLIC (1..31)
                //Тактирование: кварц 27 МГц, rPLL -> 45 МГц (PFD 9, VCO 720 МГц)
             parameter FCLKIN                = "27", //частота кварца, МГц (строка для rPLL)
             parameter int XTAL_KHZ          = 27000, //частота кварца, кГц
             parameter int PLL_IDIV_SEL      = 2,
             parameter int PLL_FBDIV_SEL     = 4,
             parameter int PLL_ODIV_SEL      = 16)
   (
    //Такт и сброс
    input wire          CLOCK,                //вывод 52
    input wire          RESET,                //вывод 3
    //GPIO
    inout wire          LED0,                 //вывод 10
    inout wire          LED1,                 //вывод 11
    inout wire          LED2,                 //вывод 13
    inout wire          LED3,                 //вывод 14
    inout wire          LED4,                 //вывод 15
    inout wire          LED5,                 //вывод 16
    //TM1638
    inout wire   [2:0]  GPIO,                 //выводы 25, 26, 27
    //STIM
    output wire         STIM_OUT,             //вывод 68
    //UART0 (UART)
    output wire         UART_TX,              //вывод 17
    input wire          UART_RX               //вывод 18
`ifndef GWSOC_NO_JTAG_PINS
    //Выводы JTAG ПЛИС: для примитива GW_JTAG (отладчик), назначения в .cst не требуются
   ,input  logic        tck_pad_i, tms_pad_i, tdi_pad_i,
    output logic        tdo_pad_o
`endif
);
`ifdef GWSOC_NO_JTAG_PINS
    //Сборка без выводов JTAG (apicula не поддерживает GW_JTAG для GW1N-9C, DEBUG_EN = 0)
    logic tck_pad_i = 1'b0, tms_pad_i = 1'b1, tdi_pad_i = 1'b0;
    logic tdo_pad_o;
`endif
    //#1 Карта адресов пользовательской периферии: у каждого устройства окно 16 МБайт (маска 0xFF00_0000).
    //Системные окна - в cpu.sv: IMEM 0x0000_0000, CLINT 0x0200_0000, PLIC 0x0C00_0000, DMEM 0x1000_0000;
    //0x1F00_0000 - устройства тестбенча. Всё вне системных окон cpu отдаёт на порт bus_per
    localparam logic [31:0] GPIO_BASE   = 32'h1100_0000;
    localparam logic [31:0] TM1638_BASE = 32'h1200_0000;
    localparam logic [31:0] STIM_BASE   = 32'h1300_0000;
    localparam logic [31:0] UART0_BASE  = 32'h1400_0000;
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

    cpu #(.CORE_TYPE(CORE_TYPE), .M_EXT(M_EXT), .DIV_BPC(DIV_BPC),
          .IMEM_TYPE(IMEM_TYPE), .BSRAM_IMEM_SIZE(BSRAM_IMEM_SIZE), .SYNTH_IMEM_SIZE(SYNTH_IMEM_SIZE), .IMEM_INIT_FILE(IMEM_INIT_FILE),
          .DMEM_TYPE(DMEM_TYPE), .BSRAM_DMEM_SIZE(BSRAM_DMEM_SIZE), .SYNTH_DMEM_SIZE(SYNTH_DMEM_SIZE), .DMEM_INIT_FILE(DMEM_INIT_FILE),
          .DEBUG_EN(DEBUG_EN), .PLIC_SOURCES(PLIC_SOURCES),
          .FCLKIN(FCLKIN), .PLL_IDIV_SEL(PLL_IDIV_SEL), .PLL_FBDIV_SEL(PLL_FBDIV_SEL), .PLL_ODIV_SEL(PLL_ODIV_SEL))
        cpu (.clk(CLOCK), .rst_n(RESET),
             .tck_pad_i(tck_pad_i), .tms_pad_i(tms_pad_i), .tdi_pad_i(tdi_pad_i), .tdo_pad_o(tdo_pad_o),
             .clk_per(clk_per), .rst_per(rst_per),
             .bus_per_Write(bus_per_Write), .bus_per_Read(bus_per_Read), .bus_per_Addr(bus_per_Addr), .bus_per_WData(bus_per_WData), .bus_per_RData(bus_per_RData),
             .irq_local(irq_local), .irq_src(irq_src));

    //#3 Шина пользовательской периферии (memmux): ведомые перечислены от старшего номера к младшему
    logic [ 3:0] gpio_Write, tm1638_Write, stim_Write, uart0_Write;
    logic [31:0] gpio_Addr, tm1638_Addr, stim_Addr, uart0_Addr;
    logic [31:0] gpio_WriteData, tm1638_WriteData, stim_WriteData, uart0_WriteData;
    logic [31:0] gpio_ReadData, tm1638_ReadData, stim_ReadData, uart0_ReadData;
    logic [ 3:0] sRead;

    memmux #(.MEMORY_TYPE(DMEM_TYPE), .SLAVES(4),
              .MATCH_ADDR ({GPIO_BASE, TM1638_BASE, STIM_BASE, UART0_BASE}),
              .MATCH_MASK ({4{WIN_MASK}}))
            permux
             (.clk(clk_per), .rst(rst_per),
              .mWrite(bus_per_Write), .mRead(bus_per_Read), .mAddr(bus_per_Addr), .mWData(bus_per_WData), .mRData(bus_per_RData),
              .sWrite({gpio_Write, tm1638_Write, stim_Write, uart0_Write}),
              .sRead (sRead),
              .sAddr ({gpio_Addr, tm1638_Addr, stim_Addr, uart0_Addr}),
              .sWData({gpio_WriteData, tm1638_WriteData, stim_WriteData, uart0_WriteData}),
              .sRData({gpio_ReadData, tm1638_ReadData, stim_ReadData, uart0_ReadData}));

    //-1- GPIO: 6 лин., регистры с 32'h1100_0000 (линия 0 - младший разряд)
    gpio_top #(.MEMORY_TYPE(DMEM_TYPE), .WIDTH(6)) gpio
              (.clk(clk_per), .rst(rst_per),
               .Write(gpio_Write), .Addr(gpio_Addr), .WData(gpio_WriteData), .RData(gpio_ReadData),
               .io_ports({LED5, LED4, LED3, LED2, LED1, LED0}));

    //-2- TM1638: внешний модуль LED&KEY, регистры с 32'h1200_0000
    tm1638_top #(.MEMORY_TYPE(DMEM_TYPE), .CLK_MHZ(CLK_DMEM_MHZ)) tm1638
                (.clk(clk_per), .rst(rst_per),
                 .Write(tm1638_Write), .Addr(tm1638_Addr), .WData(tm1638_WriteData), .RData(tm1638_ReadData),
                 .tm_dio(GPIO[0]), .tm_clk(GPIO[1]), .tm_stb(GPIO[2]));

    //-3- STIM: простой таймер (16 бит), регистры с 32'h1300_0000
    logic irq_stim;
    stim_top #(.MEMORY_TYPE(DMEM_TYPE), .WIDTH(16)) stim
                (.clk(clk_per), .rst(rst_per),
                 .Write(stim_Write), .Addr(stim_Addr), .WData(stim_WriteData), .RData(stim_ReadData),
                 .tim_out(STIM_OUT), .irq(irq_stim));

    //-4- UART0 (UART): 115200 бит/с (div 390, фактически 115090, ошибка 0.10 %), чётность none, стоп-битов 1, FIFO 16
    //    регистры с 32'h1400_0000
    logic irq_uart0;
    uart_top #(.MEMORY_TYPE(DMEM_TYPE), .DEPTH(16), .DIV_INIT(390), .STOP_INIT(1), .PARITY_INIT(0)) uart0
                (.clk(clk_per), .rst(rst_per),
                 .Write(uart0_Write), .Read(sRead[0]), .Addr(uart0_Addr), .WData(uart0_WriteData), .RData(uart0_ReadData),
                 .tx(UART_TX), .rx(UART_RX), .irq(irq_uart0));

    //-5- Прерывания периферии: источники PLIC (MEI, векторный режим) и локальные линии LI0..LI15
    //    STIM: источник PLIC 1
    //    UART0: источник PLIC 2
    assign irq_src   = {1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, irq_uart0, irq_stim};   //старший разряд - источник 8, младший - источник 1
    assign irq_local = 16'd0;
endmodule
