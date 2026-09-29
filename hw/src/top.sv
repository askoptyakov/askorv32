//============================================================================================== 
// Определения настроек ядра
//============================================================================================== 
//#1 CORE_TYPE #
`define SINGLECYCLE_CORE 1
`define PIPELINE_CORE    0
//#2 MEMORY_TYPE #
`define BSRAM_MEM        1
`define SYNTH_MEM        0
//DSECRIPTION:
//1) Максимальная суммарная память BSRAM_IMEM_SIZE + BSRAM_DMEM_SIZE = 48кБ.
//============================================================================================== 
        
module top #(parameter bit CORE_TYPE       =    `PIPELINE_CORE,
                //Настройки памяти инструкций
             parameter bit IMEM_TYPE       =        `BSRAM_MEM,
             parameter int BSRAM_IMEM_SIZE =                 8, //кБайт (поддерживаемые значения 8/16/32)
             parameter int SYNTH_IMEM_SIZE =               256, //слов по 4 Байт
             parameter     IMEM_INIT_FILE  =  "mem_init/i.mem",
                //Настройки памяти данных
             parameter bit DMEM_TYPE       =        `BSRAM_MEM, 
             parameter int BSRAM_DMEM_SIZE =                 8, //кБайт (поддерживаемые значения 8/16/32)
             parameter int SYNTH_DMEM_SIZE =               256, //слов по 4 Байт
             parameter     DMEM_INIT_FILE  =  "mem_init/d.mem",
                //Отладка и прерывания
             parameter bit DEBUG_EN        =                 1, //1 - модуль отладки через JTAG (несовместим с GAO)
             parameter int PLIC_SOURCES    =                 8, //Число источников PLIC (1..31)
                //Такт ядра от rPLL: 27 МГц * (FBDIV+1) / (IDIV+1), см. clk_pll в clock.sv
             parameter int PLL_IDIV_SEL    =                 2,
             parameter int PLL_FBDIV_SEL   =                 4, //27 * 5 / 3 = 45 МГц
             parameter int PLL_ODIV_SEL    =                16) //VCO = 45 * 16 = 720 МГц
            (input  logic       clk,     //Вход тактирования
             input  logic       rst_n,   //Вход сброса (кнопка S2)
             inout        [5:0] led,     //Выход на 6 светодиодов
             inout        [5:0] GMB_GPIO,//Выход на дискреты GMB 
             inout        [1:0] GMB_DRIVER_E,//Выход на драйвер порта E
             output        [1:0] GMB_DRIVER_D,//Выход на драйвер порта D 
             inout        [2:0] GPIO,
             //Выводы JTAG ПЛИС: для примитива GW_JTAG (отладчик), назначения в .cst не требуются
             input  logic       tck_pad_i, tms_pad_i, tdi_pad_i,
             output logic       tdo_pad_o
);
    //#0 Настройка тактирования 
    //DESCRIPTION: Для однотактного ядра при использовании BSAM делаем псевдооднотактный процессор
    //с тремя тактами на одну инструкцию. Тактируем imem и dmem 2ым и 3ьим тактом.
    //Базовый такт - от PLL по глобальной тактовой сети (раньше - триггер-делитель clk/2)
    logic clk_base, pll_lock;
    clk_pll #(PLL_IDIV_SEL, PLL_FBDIV_SEL, PLL_ODIV_SEL) clk_pll (.clkin(clk), .clkout(clk_base), .lock(pll_lock));
    //Частота тактирования периферии (clk_dmem), МГц, целая часть: для делителей периферии (TM1638).
    //Однотактное ядро с BSRAM делит базовую частоту на 3. Прошивке то же значение задаёт SYSCLK_HZ.
    localparam int CLK_BASE_MHZ = 27 * (PLL_FBDIV_SEL + 1) / (PLL_IDIV_SEL + 1);
    localparam int CLK_DMEM_MHZ = ((IMEM_TYPE | DMEM_TYPE) & CORE_TYPE) ? CLK_BASE_MHZ / 3 : CLK_BASE_MHZ;

    logic clk_core, clk_imem, clk_dmem;
    generate if ((IMEM_TYPE | DMEM_TYPE) & CORE_TYPE) begin   //#1 - Для однотактного ядра с BSRAM
        divideby3 divideby3(.clk(clk_base), .clk_div3(clk_core), .clk_imem(clk_imem), .clk_dmem(clk_dmem));
    end else begin                                            //#0 - Прочие конфигурации
        assign clk_core = clk_base;
        assign clk_imem = clk_base;
        assign clk_dmem = clk_base;
    end
    endgenerate
    
    //#1 Устранение дребезжания с кнопки S2 (rst_n)
    logic [15:0] btn_sync = 0;
    logic rst_sync_n = 0;
    logic rst_sync;
    
    //Пока PLL не захватил частоту (LOCK = 0), система держится в сбросе, как при нажатой кнопке
    always_ff @(posedge clk_core)
        if (rst_n & pll_lock)
            btn_sync <= {btn_sync[14:0], 1'b1};
        else
            btn_sync <= {1'b0, btn_sync[15:1]};
    
    always_ff @(posedge clk_core) 
        if (btn_sync == 16'b1111_1111_1111_1111) rst_sync_n <= 1'b1;
        else    if (btn_sync == 16'b0000_0000_0000_0000) rst_sync_n <= 1'b0;
                else rst_sync_n <= rst_sync_n;

    assign rst_sync = ~rst_sync_n;

    //#2 Подключаем ядро процессора
        //Сброс системы: кнопка или модуль отладки (ndmreset). Модуль отладки сбрасывает только кнопка
    logic ndmreset, rst_sys;
    assign rst_sys = rst_sync | ndmreset;
        //Интерфейс памяти команд
    logic [31:0] imem_data;
    logic        imem_re, imem_rst;
    logic [31:0] imem_addr;
        //Интерфейс памяти данных
    logic [31:0] dmem_ReadData;
    logic [ 3:0] dmem_Write;
    logic        dmem_Read;
    logic [31:0] dmem_Addr, dmem_WriteData;
        //Прерывания
    logic        irq_msi, irq_mti, irq_stim, irq_plic;
    logic [15:0] irq_local;
    assign irq_local = {15'd0, irq_stim};  //LI0 (mcause 16) - простой таймер STIM
        //Отладка
    logic        dbg_haltreq, dbg_resumereq, dbg_halted;
    logic [ 4:0] dbg_gpr_addr;
    logic        dbg_gpr_we, dbg_csr_we;
    logic [11:0] dbg_csr_addr;
    logic [31:0] dbg_gpr_rdata, dbg_csr_rdata, dbg_wdata;
        //Системная шина модуля отладки
    logic        sb_active, sb_read, sb_imem;
    logic [ 3:0] sb_wstrb;
    logic [31:0] sb_addr, sb_wdata;
        //Ядро

    core #(CORE_TYPE, IMEM_TYPE, DMEM_TYPE)
           riscv
          (.clk(clk_core), .rst(rst_sys),                                                        //Системные
           .imem_data(imem_data), .imem_re(imem_re), .imem_rst(imem_rst), .imem_addr(imem_addr), //Интерфейс памяти команд
           .dmem_ReadData(dmem_ReadData), .dmem_Write(dmem_Write), .dmem_Read(dmem_Read),        //Интерфейс памяти данных
           .dmem_Addr(dmem_Addr), .dmem_WriteData(dmem_WriteData),
           .irq_msi(irq_msi), .irq_mti(irq_mti), .irq_mei(irq_plic), .irq_local(irq_local),     //Прерывания
           .dbg_haltreq(dbg_haltreq), .dbg_resumereq(dbg_resumereq), .dbg_halted(dbg_halted),   //Отладка
           .dbg_gpr_addr(dbg_gpr_addr), .dbg_gpr_we(dbg_gpr_we), .dbg_gpr_rdata(dbg_gpr_rdata),
           .dbg_csr_addr(dbg_csr_addr), .dbg_csr_we(dbg_csr_we), .dbg_csr_rdata(dbg_csr_rdata),
           .dbg_wdata(dbg_wdata));

    //#2.1 Модуль отладки: DTM на пользовательском JTAG GOWIN и DM
    generate if (DEBUG_EN) begin : g_debug
        logic        dmi_req_tgl, dmi_ack_tgl;
        logic [ 6:0] dmi_addr;
        logic [31:0] dmi_wdata, dmi_rdata;
        logic [ 1:0] dmi_op;
        dtm_gowin dtm (.clk(clk),
                       .tck_pad_i(tck_pad_i), .tms_pad_i(tms_pad_i), .tdi_pad_i(tdi_pad_i), .tdo_pad_o(tdo_pad_o),
                       .dmi_req_tgl(dmi_req_tgl), .dmi_addr(dmi_addr), .dmi_wdata(dmi_wdata), .dmi_op(dmi_op),
                       .dmi_ack_tgl(dmi_ack_tgl), .dmi_rdata(dmi_rdata));
        dm dm (.clk(clk_core), .rst(rst_sync),
               .dmi_req_tgl(dmi_req_tgl), .dmi_addr(dmi_addr), .dmi_wdata(dmi_wdata), .dmi_op(dmi_op),
               .dmi_ack_tgl(dmi_ack_tgl), .dmi_rdata(dmi_rdata),
               .ndmreset(ndmreset), .sys_rst(rst_sys),
               .haltreq(dbg_haltreq), .resumereq(dbg_resumereq), .halted(dbg_halted),
               .gpr_addr(dbg_gpr_addr), .gpr_we(dbg_gpr_we), .gpr_rdata(dbg_gpr_rdata),
               .csr_addr(dbg_csr_addr), .csr_we(dbg_csr_we), .csr_rdata(dbg_csr_rdata), .reg_wdata(dbg_wdata),
               .sb_active(sb_active), .sb_addr(sb_addr), .sb_wdata(sb_wdata), .sb_wstrb(sb_wstrb),
               .sb_read(sb_read), .sb_rdata(sb_imem ? imem_data : dmem_ReadData));
    end else begin : g_no_debug
        assign {ndmreset, dbg_haltreq, dbg_resumereq, dbg_gpr_we, dbg_csr_we} = '0;
        assign {dbg_gpr_addr, dbg_csr_addr, dbg_wdata} = '0;
        assign {sb_active, sb_read, sb_wstrb, sb_addr, sb_wdata} = '0;
        assign tdo_pad_o = 1'b0;
    end
    endgenerate
        //Остановленное ядро не обращается к памяти: шины отдаются модулю отладки.
        //Адреса 0x00xxxxxx - память инструкций, остальные - шина данных
    assign sb_imem = sb_active && (sb_addr[31:24] == 8'h00);

    //#3 Подключаем память инструкций
    mem #(IMEM_TYPE, SYNTH_IMEM_SIZE, BSRAM_IMEM_SIZE, IMEM_INIT_FILE) imem
          (.clk(clk_imem), .reset(rst_sys | (imem_rst & ~sb_imem)), .re(imem_re | sb_imem),
           .wstrb(sb_imem ? sb_wstrb : 4'b0000),
           .a(sb_imem ? sb_addr : imem_addr), .wd(sb_wdata),
           .rd(imem_data));

    //#4 Подключаем память данных и периферийные модули

    //-0- Основной мультиплексор (ведущие - ядро или модуль отладки)
    //Ч11: шина данных отдаётся модулю отладки по отдельному регистру - копии «ядро остановлено»,
    //а не логикой от halted через состояние DM и адрес: этот путь шёл в дешифрацию адреса периферии.
    //Пока ядро стоит, к шине обращается только DM: стробы sb_* есть лишь во время его обращения,
    //а адрес IMEM (0x00xxxxxx) не попадает ни в одно устройство memmux. Копия на такт позже halted:
    //при останове DM начинает обращение через несколько тактов, после продолжения первая загрузка
    //или запись ядра доходит до стадии M не раньше чем через 3 такта.
    logic        bus_sb;
    always_ff @(posedge clk_core) bus_sb <= DEBUG_EN & dbg_halted;
    logic [ 3:0] mem_Write, leds_Write, tm_Write, tim_Write, clint_Write, plic_Write;
    logic [31:0] mem_Addr, leds_Addr, tm_Addr, tim_Addr, clint_Addr, plic_Addr;
    logic [31:0] mem_WriteData, leds_WriteData, tm_WriteData, tim_WriteData, clint_WriteData, plic_WriteData;
    logic [31:0] mem_ReadData, leds_ReadData, tm_ReadData, tim_ReadData, clint_ReadData, plic_ReadData;
    logic [ 5:0] sRead;

    memmux #(.MEMORY_TYPE(DMEM_TYPE), .SLAVES(6),
              .MATCH_ADDR ({32'h10000000, 32'h11000000, 32'h12000000, 32'h13000000, 32'h02000000, 32'h0C000000}),
              .MATCH_MASK ({32'hff000000, 32'hff000000, 32'hff000000, 32'hff000000, 32'hff000000, 32'hff000000}))
            memmux
             (.clk(clk_dmem), .rst(rst_sys),
              // Интерфейс мастера
              .mWrite(bus_sb ? sb_wstrb : dmem_Write), .mRead(bus_sb ? sb_read : dmem_Read),
              .mAddr (bus_sb ? sb_addr  : dmem_Addr),  .mWData(bus_sb ? sb_wdata : dmem_WriteData),
              .mRData(dmem_ReadData),
              // Интерфейс подчинённых
              .sWrite({mem_Write,    leds_Write,    tm_Write,       tim_Write,     clint_Write,     plic_Write}),
              .sRead (sRead),
              .sAddr ({mem_Addr,     leds_Addr,     tm_Addr,        tim_Addr,      clint_Addr,      plic_Addr}),
              .sWData({mem_WriteData,leds_WriteData,tm_WriteData,   tim_WriteData, clint_WriteData, plic_WriteData}),
              .sRData({mem_ReadData, leds_ReadData, tm_ReadData,    tim_ReadData,  clint_ReadData,  plic_ReadData}));

    //-1- Память данных
    mem #(DMEM_TYPE, SYNTH_DMEM_SIZE, BSRAM_DMEM_SIZE, DMEM_INIT_FILE) dmem
          (.clk(clk_dmem), .reset(rst_sys), .re(1'b1), .wstrb(mem_Write),
           .a(mem_Addr), .wd(mem_WriteData),
           .rd(mem_ReadData));

    //-2- Встроенные светодиоды(6шт.)
    wire  [17:0] empty_gpio;
    gpio_top #(DMEM_TYPE) gpio
              (.clk(clk_dmem), .rst(rst_sys),
               .Write(leds_Write), .Addr(leds_Addr), .WData(leds_WriteData), .RData(leds_ReadData),
               .io_ports({empty_gpio[17:0], GMB_DRIVER_E[1:0], GMB_GPIO[5:0], led[5:0]}));

    //-3- Внешний модуль tm1638
    tm1638_top #(.MEMORY_TYPE(DMEM_TYPE), .CLK_MHZ(CLK_DMEM_MHZ)) tm1638
                (.clk(clk_dmem), .rst(rst_sys),
                 .Write(tm_Write), .Addr(tm_Addr), .WData(tm_WriteData), .RData(tm_ReadData),
                 .tm_dio(GPIO[0]), .tm_clk(GPIO[1]), .tm_stb(GPIO[2]));

    //-4- Модуль простого таймера
    logic [31:0] empty_tim_port;
    stim_top #(DMEM_TYPE) stim
                (.clk(clk_dmem), .rst(rst_sys),
                 .Write(tim_Write), .Addr(tim_Addr), .WData(tim_WriteData), .RData(tim_ReadData),
                 .tim_out(GMB_DRIVER_D[0]), .irq(irq_stim));

    //-5- Машинный таймер и программное прерывание (CLINT, адреса как у SiFive)
    clint_top #(DMEM_TYPE) clint
                (.clk(clk_dmem), .rst(rst_sys),
                 .Write(clint_Write), .Addr(clint_Addr), .WData(clint_WriteData), .RData(clint_ReadData),
                 .irq_msi(irq_msi), .irq_mti(irq_mti));

    //-6- Контроллер прерываний периферии (PLIC, адреса как у SiFive) -> MEI (mcause 11)
    //Источник 1 - таймер STIM (для примера: он же подключён к LI0, в программе разрешают один путь).
    //Новую периферию (UART, SPI...) подключать к свободным источникам 2..PLIC_SOURCES через irq_ext:
    //например, assign irq_ext[2] = irq_uart; (уровень, держится до обслуживания в устройстве)
    wire [PLIC_SOURCES:2] irq_ext;
    assign irq_ext = '0;
    wire [PLIC_SOURCES:1] plic_src = {irq_ext, irq_stim};
    plic_top #(.MEMORY_TYPE(DMEM_TYPE), .NSRC(PLIC_SOURCES)) plic
                (.clk(clk_dmem), .rst(rst_sys),
                 .Write(plic_Write), .Read(sRead[0]), .Addr(plic_Addr), .WData(plic_WriteData), .RData(plic_ReadData),
                 .src(plic_src), .irq(irq_plic));
endmodule