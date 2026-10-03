//==============================================================================================
// top.sv - ВЕРХНИЙ УРОВЕНЬ askoRV32. ФАЙЛ СОЗДАН КОНФИГУРАТОРОМ ПЛИС - НЕ РЕДАКТИРУЙТЕ ВРУЧНУЮ.
// Источник: fw/boards/tangprimer20k/tangprimer20k.gwsoc; генератор: sw/socgen/socgen.py (кнопка «Собрать» в Eclipse).
// Процессор (ядро, память, отладчик, CLINT, PLIC) - в hw/src/cpu.sv, он правится вручную; здесь -
// параметры платы для cpu и пользовательская периферия на его порту bus_per.
// Плата: Tang Primer 20K; ПЛИС: GW2A-LV18PG256C8/I7.
//==============================================================================================

module top #(
                //Ядро
             parameter bit CORE_TYPE         = 0, //1 - однотактное, 0 - конвейерное
             parameter bit M_EXT             = 1, //расширение M
             parameter int DIV_BPC           = 2, //бит частного за такт: 1, 2, 4
             parameter int RF_TYPE           = 2, //регистровый файл: 0 - LUT; BSRAM (2 блока SDPB): 1 - чтение на фронте D->E, 2 - по спаду в D
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
             parameter bit DEBUG_EN          = 1, //модуль отладки JTAG (выводы TMS B8, TCK A7, TDI A6, TDO C6)
             parameter int PLIC_SOURCES      = 8, //источников PLIC (1..31)
                //Тактирование: кварц 27 МГц, rPLL -> 45 МГц (PFD 9, VCO 720 МГц)
             parameter FCLKIN                = "27", //частота кварца, МГц (строка для rPLL)
             parameter PLL_DEVICE            = "GW2A-18C", //кристалл для rPLL
             parameter int XTAL_KHZ          = 27000, //частота кварца, кГц
             parameter int PLL_IDIV_SEL      = 2,
             parameter int PLL_FBDIV_SEL     = 4,
             parameter int PLL_ODIV_SEL      = 16)
   (
    //Такт и сброс
    input wire          CLOCK,                //вывод H11
    input wire          RESET,                //вывод T10
    //GPIO
    inout wire          LED0,                 //вывод C13
    inout wire          LED1,                 //вывод A13
    inout wire          LED2,                 //вывод N16
    inout wire          LED3,                 //вывод N14
    inout wire          LED4,                 //вывод L14
    inout wire          LED5,                 //вывод L16
    //UART
    output wire         UART_TX,              //вывод M11
    input wire          UART_RX,              //вывод T13
    //SPIFLASH
    output wire         FLASH_SCK,            //вывод L10
    output wire         FLASH_CS,             //вывод M9
    output wire         FLASH_MOSI,           //вывод R10
    input wire          FLASH_MISO,           //вывод P10
    //TM1638
    inout wire          TM1638_DIO,           //вывод T7
    output wire         TM1638_CLK,           //вывод P8
    output wire         TM1638_STB,           //вывод T9
    //SIFU
    input wire          NSB_AB,               //вывод B12
    input wire          NSB_BA,               //вывод C12
    input wire          NSB_BC,               //вывод B13
    input wire          NSB_CB,               //вывод A14
    input wire          NSB_CA,               //вывод B14
    input wire          NSB_AC,               //вывод A15
    output wire         VS1,                  //вывод L9
    output wire         VS2,                  //вывод N8
    output wire         VS3,                  //вывод N9
    output wire         VS4,                  //вывод N7
    output wire         VS5,                  //вывод N6
    output wire         VS6                   //вывод D11
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
    localparam logic [31:0] GPIO_BASE     = 32'h1100_0000;
    localparam logic [31:0] STIM_BASE     = 32'h1300_0000;
    localparam logic [31:0] UART_BASE     = 32'h1400_0000;
    localparam logic [31:0] SPIFLASH_BASE = 32'h1500_0000;
    localparam logic [31:0] TM1638_BASE   = 32'h1200_0000;
    localparam logic [31:0] SIFU_BASE     = 32'h1600_0000;
    localparam logic [31:0] WIN_MASK      = 32'hFF00_0000;

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
    //Программу после сброса копирует из флеш SPIFLASH (порт boot_*)

    //#3 Шина пользовательской периферии (memmux): ведомые перечислены от старшего номера к младшему
    logic [ 3:0] gpio_Write, stim_Write, uart_Write, spiflash_Write, tm1638_Write, sifu_Write;
    logic [31:0] gpio_Addr, stim_Addr, uart_Addr, spiflash_Addr, tm1638_Addr, sifu_Addr;
    logic [31:0] gpio_WriteData, stim_WriteData, uart_WriteData, spiflash_WriteData, tm1638_WriteData, sifu_WriteData;
    logic [31:0] gpio_ReadData, stim_ReadData, uart_ReadData, spiflash_ReadData, tm1638_ReadData, sifu_ReadData;
    logic [ 5:0] sRead;

    memmux #(.MEMORY_TYPE(DMEM_TYPE), .SLAVES(6),
              .MATCH_ADDR ({GPIO_BASE, STIM_BASE, UART_BASE, SPIFLASH_BASE, TM1638_BASE, SIFU_BASE}),
              .MATCH_MASK ({6{WIN_MASK}}))
            permux
             (.clk(clk_per), .rst(rst_per),
              .mWrite(bus_per_Write), .mRead(bus_per_Read), .mAddr(bus_per_Addr), .mWData(bus_per_WData), .mRData(bus_per_RData),
              .sWrite({gpio_Write, stim_Write, uart_Write, spiflash_Write, tm1638_Write, sifu_Write}),
              .sRead (sRead),
              .sAddr ({gpio_Addr, stim_Addr, uart_Addr, spiflash_Addr, tm1638_Addr, sifu_Addr}),
              .sWData({gpio_WriteData, stim_WriteData, uart_WriteData, spiflash_WriteData, tm1638_WriteData, sifu_WriteData}),
              .sRData({gpio_ReadData, stim_ReadData, uart_ReadData, spiflash_ReadData, tm1638_ReadData, sifu_ReadData}));

    //-1- GPIO: 6 лин., регистры с 32'h1100_0000 (линия 0 - младший разряд)
    gpio_top #(.MEMORY_TYPE(DMEM_TYPE), .WIDTH(6)) gpio
              (.clk(clk_per), .rst(rst_per),
               .Write(gpio_Write), .Addr(gpio_Addr), .WData(gpio_WriteData), .RData(gpio_ReadData),
               .io_ports({LED5, LED4, LED3, LED2, LED1, LED0}));

    //-2- STIM: простой таймер (16 бит), регистры с 32'h1300_0000
    logic irq_stim;
    stim_top #(.MEMORY_TYPE(DMEM_TYPE), .WIDTH(16)) stim
                (.clk(clk_per), .rst(rst_per),
                 .Write(stim_Write), .Addr(stim_Addr), .WData(stim_WriteData), .RData(stim_ReadData),
                 .tim_out(), .irq(irq_stim));   //выход ШИМ не выведен

    //-3- UART: 115200 бит/с (div 390, фактически 115090, ошибка 0.10 %), чётность none, стоп-битов 1, FIFO 16
    //    регистры с 32'h1400_0000
    logic irq_uart;
    uart_top #(.MEMORY_TYPE(DMEM_TYPE), .DEPTH(16), .DIV_INIT(390), .STOP_INIT(1), .PARITY_INIT(0)) uart
                (.clk(clk_per), .rst(rst_per),
                 .Write(uart_Write), .Read(sRead[3]), .Addr(uart_Addr), .WData(uart_WriteData), .RData(uart_ReadData),
                 .tx(UART_TX), .rx(UART_RX), .irq(irq_uart));

    //-4- SPIFLASH: SPI-флеш 8 МБайт, SCK 11.25 МГц (DIV 1), загрузка программы с адреса 0x100000, конфигурация ПЛИС с адреса 0 (MSPI)
    //    регистры с 32'h1500_0000
    spiflash_top #(.MEMORY_TYPE(DMEM_TYPE), .DIV_INIT(1), .BOOT_EN(1), .BOOT_ADDR(24'h100000)) spiflash
                (.clk(clk_per), .rst(rst_per),
                 .Write(spiflash_Write), .Read(sRead[2]), .Addr(spiflash_Addr), .WData(spiflash_WriteData), .RData(spiflash_ReadData),
                 .spi_sck(FLASH_SCK), .spi_cs_n(FLASH_CS), .spi_mosi(FLASH_MOSI), .spi_miso(FLASH_MISO),
                 .boot_hold(boot_hold), .boot_Write(boot_Write), .boot_Addr(boot_Addr), .boot_WData(boot_WData));

    //-5- TM1638: внешний модуль LED&KEY, регистры с 32'h1200_0000
    tm1638_top #(.MEMORY_TYPE(DMEM_TYPE), .CLK_MHZ(CLK_DMEM_MHZ)) tm1638
                (.clk(clk_per), .rst(rst_per),
                 .Write(tm1638_Write), .Addr(tm1638_Addr), .WData(tm1638_WriteData), .RData(tm1638_ReadData),
                 .tm_dio(TM1638_DIO), .tm_clk(TM1638_CLK), .tm_stb(TM1638_STB));

    //-6- SIFU: СИФУ трёхфазного мостового выпрямителя, тик ГПН 500 кГц (DIV 89), DELAY 400, импульс 150 тиков
    //    регистры с 32'h1600_0000; входы - плата синхронизации NSB (0 - оптрон открыт), выходы - тиристоры VS1..VS6; есть имитатор сети
    logic irq_sifu;
    sifu_top #(.MEMORY_TYPE(DMEM_TYPE), .DIV_INIT(16'd89), .DELAY_INIT(12'd400), .WIDTH_INIT(12'd150), .SIM_EN(1)) sifu
                (.clk(clk_per), .rst(rst_per),
                 .Write(sifu_Write), .Addr(sifu_Addr), .WData(sifu_WriteData), .RData(sifu_ReadData),
                 .sync_ab(NSB_AB), .sync_ba(NSB_BA), .sync_bc(NSB_BC), .sync_cb(NSB_CB), .sync_ca(NSB_CA), .sync_ac(NSB_AC),
                 .vs1(VS1), .vs2(VS2), .vs3(VS3), .vs4(VS4), .vs5(VS5), .vs6(VS6),
                 .irq(irq_sifu));

    //-7- Прерывания периферии: источники PLIC (MEI, векторный режим) и локальные линии LI0..LI15
    //    STIM: источник PLIC 1
    //    UART: источник PLIC 2
    //    SIFU: источник PLIC 3
    assign irq_src   = {1'b0, 1'b0, 1'b0, 1'b0, 1'b0, irq_sifu, irq_uart, irq_stim};   //старший разряд - источник 8, младший - источник 1
    assign irq_local = 16'd0;
endmodule
