//==============================================================================================
// top.sv - ВЕРХНИЙ УРОВЕНЬ askoRV32. ФАЙЛ СОЗДАН КОНФИГУРАТОРОМ ПЛИС - НЕ РЕДАКТИРУЙТЕ ВРУЧНУЮ.
// Источник: fw/riscv.gwsoc; генератор: sw/socgen/socgen.py (кнопка «Собрать» в Eclipse).
// Процессор (ядро, память, отладчик, CLINT, PLIC) - в cpu.sv, он правится вручную; здесь -
// параметры платы для cpu и пользовательская периферия на его порту per_*.
//==============================================================================================

module top #(
                //Ядро
             parameter bit CORE_TYPE         = 0, //1 - однотактное, 0 - конвейерное
             parameter bit M_EXT             = 1, //расширение M
             parameter int DIV_BPC           = 2, //бит частного за такт: 1, 2, 4
                //Память команд и данных
             parameter bit IMEM_TYPE         = 1, //1 - BSRAM, 0 - синтезированная
             parameter int BSRAM_IMEM_SIZE   = 16, //кБайт: 8/16/32
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
    input wire          clk,                  //вывод 52
    input wire          rst_n,                //вывод 3
    //GPIO
    inout wire   [5:0]  led,                  //выводы 10, 11, 13, 14, 15, 16
    //TM1638
    inout wire   [2:0]  GPIO,                 //выводы 25, 26, 27
    //STIM
    output wire         stim_out,             //вывод 68
    //UART
    output wire         uart_tx,              //вывод 17
    input wire          uart_rx               //вывод 18
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
    //0x1F00_0000 - устройства тестбенча. Всё вне системных окон cpu отдаёт на порт per_*
    localparam logic [31:0] GPIO_BASE   = 32'h1100_0000;
    localparam logic [31:0] TM1638_BASE = 32'h1200_0000;
    localparam logic [31:0] STIM_BASE   = 32'h1300_0000;
    localparam logic [31:0] UART_BASE   = 32'h1400_0000;
    localparam logic [31:0] WIN_MASK    = 32'hFF00_0000;

    //Частота шины периферии (per_clk), МГц, целая часть: для делителей периферии (TM1638).
    //Однотактное ядро с BSRAM делит базовую частоту на 3. Прошивке то же значение задаёт SYSCLK_HZ.
    localparam int CLK_BASE_MHZ = XTAL_KHZ * (PLL_FBDIV_SEL + 1) / (PLL_IDIV_SEL + 1) / 1000;
    localparam int CLK_DMEM_MHZ = ((IMEM_TYPE | DMEM_TYPE) & CORE_TYPE) ? CLK_BASE_MHZ / 3 : CLK_BASE_MHZ;

    //#2 Процессор (cpu.sv): такт, сброс, ядро, отладчик, память команд и данных, CLINT, PLIC.
    //Параметры платы переопределяют значения по умолчанию из cpu.sv
    logic        per_clk, per_rst;
    logic [ 3:0] per_Write;
    logic        per_Read;
    logic [31:0] per_Addr, per_WData, per_RData;
    logic [15:0] irq_local;
    logic [PLIC_SOURCES:1] irq_src;

    cpu #(.CORE_TYPE(CORE_TYPE), .M_EXT(M_EXT), .DIV_BPC(DIV_BPC),
          .IMEM_TYPE(IMEM_TYPE), .BSRAM_IMEM_SIZE(BSRAM_IMEM_SIZE), .SYNTH_IMEM_SIZE(SYNTH_IMEM_SIZE), .IMEM_INIT_FILE(IMEM_INIT_FILE),
          .DMEM_TYPE(DMEM_TYPE), .BSRAM_DMEM_SIZE(BSRAM_DMEM_SIZE), .SYNTH_DMEM_SIZE(SYNTH_DMEM_SIZE), .DMEM_INIT_FILE(DMEM_INIT_FILE),
          .DEBUG_EN(DEBUG_EN), .PLIC_SOURCES(PLIC_SOURCES),
          .FCLKIN(FCLKIN), .PLL_IDIV_SEL(PLL_IDIV_SEL), .PLL_FBDIV_SEL(PLL_FBDIV_SEL), .PLL_ODIV_SEL(PLL_ODIV_SEL))
        cpu (.clk(clk), .rst_n(rst_n),
             .tck_pad_i(tck_pad_i), .tms_pad_i(tms_pad_i), .tdi_pad_i(tdi_pad_i), .tdo_pad_o(tdo_pad_o),
             .per_clk(per_clk), .per_rst(per_rst),
             .per_Write(per_Write), .per_Read(per_Read), .per_Addr(per_Addr), .per_WData(per_WData), .per_RData(per_RData),
             .irq_local(irq_local), .irq_src(irq_src));

    //#3 Шина пользовательской периферии (memmux): ведомые перечислены от старшего номера к младшему
    logic [ 3:0] gpio_Write, tm_Write, tim_Write, uart_Write;
    logic [31:0] gpio_Addr, tm_Addr, tim_Addr, uart_Addr;
    logic [31:0] gpio_WriteData, tm_WriteData, tim_WriteData, uart_WriteData;
    logic [31:0] gpio_ReadData, tm_ReadData, tim_ReadData, uart_ReadData;
    logic [ 3:0] sRead;

    memmux #(.MEMORY_TYPE(DMEM_TYPE), .SLAVES(4),
              .MATCH_ADDR ({GPIO_BASE, TM1638_BASE, STIM_BASE, UART_BASE}),
              .MATCH_MASK ({4{WIN_MASK}}))
            permux
             (.clk(per_clk), .rst(per_rst),
              .mWrite(per_Write), .mRead(per_Read), .mAddr(per_Addr), .mWData(per_WData), .mRData(per_RData),
              .sWrite({gpio_Write, tm_Write, tim_Write, uart_Write}),
              .sRead (sRead),
              .sAddr ({gpio_Addr, tm_Addr, tim_Addr, uart_Addr}),
              .sWData({gpio_WriteData, tm_WriteData, tim_WriteData, uart_WriteData}),
              .sRData({gpio_ReadData, tm_ReadData, tim_ReadData, uart_ReadData}));

    //-1- GPIO: 6 лин., регистры с 32'h1100_0000 (линия 0 - младший разряд)
    gpio_top #(.MEMORY_TYPE(DMEM_TYPE), .WIDTH(6)) gpio
              (.clk(per_clk), .rst(per_rst),
               .Write(gpio_Write), .Addr(gpio_Addr), .WData(gpio_WriteData), .RData(gpio_ReadData),
               .io_ports({led[5:0]}));

    //-2- Внешний модуль TM1638, регистры с 32'h1200_0000
    tm1638_top #(.MEMORY_TYPE(DMEM_TYPE), .CLK_MHZ(CLK_DMEM_MHZ)) tm1638
                (.clk(per_clk), .rst(per_rst),
                 .Write(tm_Write), .Addr(tm_Addr), .WData(tm_WriteData), .RData(tm_ReadData),
                 .tm_dio(GPIO[0]), .tm_clk(GPIO[1]), .tm_stb(GPIO[2]));

    //-3- Простой таймер STIM (16 бит), регистры с 32'h1300_0000
    logic irq_stim;
    stim_top #(.MEMORY_TYPE(DMEM_TYPE), .WIDTH(16)) stim
                (.clk(per_clk), .rst(per_rst),
                 .Write(tim_Write), .Addr(tim_Addr), .WData(tim_WriteData), .RData(tim_ReadData),
                 .tim_out(stim_out), .irq(irq_stim));

    //-4- UART: 115200 бит/с (div 390, фактически 115090, ошибка 0.10 %), чётность none, стоп-битов 1, FIFO 16
    //    регистры с 32'h1400_0000
    logic irq_uart;
    uart_top #(.MEMORY_TYPE(DMEM_TYPE), .DEPTH(16), .DIV_INIT(390), .STOP_INIT(1), .PARITY_INIT(0)) uart
                (.clk(per_clk), .rst(per_rst),
                 .Write(uart_Write), .Read(sRead[0]), .Addr(uart_Addr), .WData(uart_WriteData), .RData(uart_ReadData),
                 .tx(uart_tx), .rx(uart_rx), .irq(irq_uart));

    //-5- Прерывания периферии: источники PLIC (MEI, векторный режим) и локальные линии LI0..LI15
    //    STIM: источник PLIC 1
    //    UART: источник PLIC 2
    assign irq_src   = {1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, irq_uart, irq_stim};   //старший разряд - источник 8, младший - источник 1
    assign irq_local = 16'd0;
endmodule
