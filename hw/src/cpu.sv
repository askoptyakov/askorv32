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

//==============================================================================================
// cpu - процессор askoRV32: самодостаточный верхний уровень без пользовательской периферии
//==============================================================================================
//DESCRIPTION: Всё, без чего система не работает: тактирование (rPLL), сброс, ядро, отладчик JTAG,
//память команд и данных, CLINT, PLIC и системная шина. Пользовательская периферия подключается
//снаружи, к порту шины регистров bus_per (правила - hw/info/architecture.md, «Шина данных и
//периферии»): на него уходят обращения к окну 0x1xxx_xxxx.
//  0x0000_0000 IMEM (своя шина команд)   0x0200_0000 CLINT   0x0C00_0000 PLIC   0x1000_0000 DMEM
//  0x1100_0000..0x1FFF_FFFF - порт bus_per (пользовательская периферия; 0x1F00_0000 - устройства тестбенча)
//Загрузчик программы из внешней флеш (контроллер SPI-флеш в top.sv, hw/src/periph/spiflash) подключается
//к порту boot_*: пока он копирует программу в IMEM и DMEM, ядро держится в сбросе.
//Верхний уровень платы hw/boards/<плата>/top.sv создаёт конфигуратор ПЛИС (sw/socgen) из
//fw/boards/<плата>/<плата>.gwsoc: он
//переопределяет параметры cpu и подключает периферию. Тесты ядра (hw/sim) моделируют cpu без
//top.sv, поэтому от конфигурации платы не зависят. Этот файл правится вручную, top.sv - нет.
module cpu #(parameter bit CORE_TYPE       =    `PIPELINE_CORE,
                //Расширение M (умножение и деление)
             parameter bit M_EXT           =                 1, //1 - mul/mulh*/div*/rem*; 0 - RV32I (такие инструкции недопустимы)
             parameter int DIV_BPC         =                 2, //Бит частного за такт: 1, 2, 4 (деление 32/DIV_BPC + 3 такта)
             parameter int RF_TYPE         =                 0, //Регистровый файл: 0 - LUT; BSRAM (2 блока SDPB, конвейер): 1 - чтение на фронте D->E, 2 - по спаду в D
                //Настройки памяти инструкций
             parameter bit IMEM_TYPE       =        `BSRAM_MEM,
             parameter int BSRAM_IMEM_SIZE =                 8, //кБайт (поддерживаемые значения 8/16/32)
             parameter int SYNTH_IMEM_SIZE =               256, //слов по 4 Байт
             parameter     IMEM_INIT_FILE  =  "mem_init/i.mem",
                //Настройки памяти данных (однотактному ядру с BSRAM нужна схема тактирования на 3 такта)
             parameter bit DMEM_TYPE       =        `BSRAM_MEM,
             parameter int BSRAM_DMEM_SIZE =                 8, //кБайт (поддерживаемые значения 8/16/32)
             parameter int SYNTH_DMEM_SIZE =               256, //слов по 4 Байт
             parameter     DMEM_INIT_FILE  =  "mem_init/d.mem",
                //Отладка и прерывания
             parameter bit DEBUG_EN        =                 1, //1 - модуль отладки через JTAG (несовместим с GAO)
             parameter int PLIC_SOURCES    =                 8, //Число источников PLIC (1..31)
                //Такт ядра от rPLL: FCLKIN * (FBDIV+1) / (IDIV+1), см. clk_pll в clock.sv
             parameter     FCLKIN          =              "27", //Частота кварца, МГц (строка, как у rPLL)
             parameter     PLL_DEVICE      =        "GW1NR-9C", //Кристалл для rPLL: "GW1NR-9C", "GW2A-18C" (задаёт top.sv платы)
             parameter int PLL_IDIV_SEL    =                 2,
             parameter int PLL_FBDIV_SEL   =                 4, //27 * 5 / 3 = 45 МГц
             parameter int PLL_ODIV_SEL    =                16) //VCO = 45 * 16 = 720 МГц
            (input  logic        clk,           //Вход тактирования (кварц)
             input  logic        rst_n,         //Вход сброса (кнопка)
             //Выводы JTAG ПЛИС: для примитива GW_JTAG (отладчик), назначения в .cst не требуются
             input  logic        tck_pad_i, tms_pad_i, tdi_pad_i,
             output logic        tdo_pad_o,
             //Порт пользовательской периферии: шина регистров (обращения вне системных окон)
             output logic        clk_per,       //Такт шины (clk_dmem: такт ядра; у однотактного ядра с BSRAM - фаза данных)
             output logic        rst_per,       //Сброс системы (кнопка или отладчик)
             output logic [ 3:0] bus_per_Write,     //Байтовые стробы записи
             output logic        bus_per_Read,      //Строб чтения (для регистров с побочным действием)
             output logic [31:0] bus_per_Addr, bus_per_WData,
             input  logic [31:0] bus_per_RData,     //Данные чтения: при DMEM_TYPE = 1 - на следующем такте
             //Прерывания пользовательской периферии
             input  logic [15:0]           irq_local,   //Локальные LI0..LI15 (mcause 16..31)
             input  logic [PLIC_SOURCES:1] irq_src,     //Источники PLIC 1..PLIC_SOURCES (-> MEI, mcause 11)
             //Загрузчик программы (контроллер SPI-флеш, periph/spiflash): пока boot_hold = 1, ядро в сбросе,
             //а загрузчик пишет словами в IMEM (0x00xx_xxxx) и DMEM (0x10xx_xxxx). Без загрузчика - нули
             input  logic                  boot_hold,
             input  logic [ 3:0]           boot_Write,  //Стробы записи (такт clk_per)
             input  logic [31:0]           boot_Addr, boot_WData
);
    //#0 Настройка тактирования
    //DESCRIPTION: Для однотактного ядра при использовании BSAM делаем псевдооднотактный процессор
    //с тремя тактами на одну инструкцию. Тактируем imem и dmem 2ым и 3ьим тактом.
    //Базовый такт - от PLL по глобальной тактовой сети (раньше - триггер-делитель clk/2)
    logic clk_base, pll_lock;
    clk_pll #(FCLKIN, PLL_DEVICE, PLL_IDIV_SEL, PLL_FBDIV_SEL, PLL_ODIV_SEL) clk_pll (.clkin(clk), .clkout(clk_base), .lock(pll_lock));

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
        //Сброс системы: кнопка или модуль отладки (ndmreset). Модуль отладки сбрасывает только кнопка.
        //Ядро, кроме того, держится в сбросе, пока загрузчик копирует программу из флеш (boot_hold)
    logic ndmreset, rst_sys, rst_core;
    assign rst_sys  = rst_sync | ndmreset;
    assign rst_core = rst_sys | boot_hold;
    assign clk_per = clk_dmem;
    assign rst_per = rst_sys;
        //Интерфейс памяти команд
    logic [31:0] imem_data;
    logic        imem_re, imem_rst;
    logic [31:0] imem_addr;
        //Интерфейс памяти данных
    logic [31:0] dmem_ReadData;
    logic [ 3:0] dmem_Write;
    logic        dmem_Read;
    logic [31:0] dmem_Addr, dmem_WriteData;
        //Прерывания и счётчик mcycle = mtime (Р3)
    logic        irq_msi, irq_mti, irq_mei;
    logic [ 4:0] irq_mei_id, mei_claim_id;     //Векторный режим PLIC: номер источника, захват ядром
    logic        irq_mei_vec, mei_claim;
    logic [63:0] mtime;
    logic [ 1:0] mtime_we;
    logic [31:0] mtime_wdata;
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

    core #(CORE_TYPE, IMEM_TYPE, DMEM_TYPE, M_EXT, DIV_BPC, RF_TYPE)
           riscv
          (.clk(clk_core), .rst(rst_core),                                                       //Системные
           .imem_data(imem_data), .imem_re(imem_re), .imem_rst(imem_rst), .imem_addr(imem_addr), //Интерфейс памяти команд
           .dmem_ReadData(dmem_ReadData), .dmem_Write(dmem_Write), .dmem_Read(dmem_Read),        //Интерфейс памяти данных
           .dmem_Addr(dmem_Addr), .dmem_WriteData(dmem_WriteData),
           .irq_msi(irq_msi), .irq_mti(irq_mti), .irq_mei(irq_mei), .irq_local(irq_local),      //Прерывания
           .irq_mei_id(irq_mei_id), .irq_mei_vec(irq_mei_vec), .mei_claim(mei_claim), .mei_claim_id(mei_claim_id),
           .dbg_haltreq(dbg_haltreq), .dbg_resumereq(dbg_resumereq), .dbg_halted(dbg_halted),   //Отладка
           .dbg_gpr_addr(dbg_gpr_addr), .dbg_gpr_we(dbg_gpr_we), .dbg_gpr_rdata(dbg_gpr_rdata),
           .dbg_csr_addr(dbg_csr_addr), .dbg_csr_we(dbg_csr_we), .dbg_csr_rdata(dbg_csr_rdata),
           .dbg_wdata(dbg_wdata),
           .mtime(mtime), .mtime_we(mtime_we), .mtime_wdata(mtime_wdata));                        //Счётчик mcycle = mtime

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
               .ndmreset(ndmreset), .sys_rst(rst_core),
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

    //#2.2 Внешние ведущие памяти: модуль отладки (ядро остановлено) и загрузчик (ядро в сбросе). Одновременно
    //они не работают, поэтому сводятся в один ведущий ext_* до выбора «ядро или внешний»: путь от ядра к
    //памяти проходит тот же один мультиплексор, что и без загрузчика
    logic        ext_imem;
    logic [ 3:0] ext_wstrb;
    logic [31:0] ext_addr, ext_wdata;
    assign ext_imem  = sb_imem | (boot_hold && (|boot_Write) && boot_Addr[31:24] == 8'h00);
    assign ext_wstrb = boot_hold ? boot_Write : sb_wstrb;
    assign ext_addr  = boot_hold ? boot_Addr  : sb_addr;
    assign ext_wdata = boot_hold ? boot_WData : sb_wdata;

    //#3 Подключаем память инструкций
    mem #(IMEM_TYPE, SYNTH_IMEM_SIZE, BSRAM_IMEM_SIZE, IMEM_INIT_FILE) imem
          (.clk(clk_imem), .reset(rst_sys | (imem_rst & ~ext_imem)), .re(imem_re | ext_imem),
           .wstrb(ext_imem ? ext_wstrb : 4'b0000),
           .a(ext_imem ? ext_addr : imem_addr), .wd(ext_wdata),
           .rd(imem_data));

    //#4 Ведущий шины данных (ядро или модуль отладки)
    //Ч11: шина данных отдаётся модулю отладки по отдельному регистру - копии «ядро остановлено»,
    //а не логикой от halted через состояние DM и адрес: этот путь шёл в дешифрацию адреса периферии.
    //Пока ядро стоит, к шине обращается только DM: стробы sb_* есть лишь во время его обращения,
    //а адрес IMEM (0x00xxxxxx) не попадает ни в одно устройство memmux. Копия на такт позже halted:
    //при останове DM начинает обращение через несколько тактов, после продолжения первая загрузка
    //или запись ядра доходит до стадии M не раньше чем через 3 такта.
    //Загрузчик (boot_hold) владеет шиной так же, по регистру: его первая запись - через сотни тактов
    //после подъёма boot_hold, а ядро выходит из сброса уже после конца загрузки.
    //Запись загрузчика в IMEM (0x00xxxxxx) на шине данных никуда не попадает, как и у модуля отладки
    logic        bus_sb;
    logic [ 3:0] bus_Write;
    logic        bus_Read;
    logic [31:0] bus_Addr, bus_WData;
    always_ff @(posedge clk_core) bus_sb <= (DEBUG_EN & dbg_halted) | boot_hold;
    assign bus_Write = bus_sb ? ext_wstrb             : dmem_Write;
    assign bus_Read  = bus_sb ? sb_read & ~boot_hold  : dmem_Read;
    assign bus_Addr  = bus_sb ? ext_addr              : dmem_Addr;
    assign bus_WData = bus_sb ? ext_wdata             : dmem_WriteData;

    //#5 Системная шина: DMEM, CLINT, PLIC и порт пользовательской периферии. Окна по 16 МБайт, приоритет
    //у младшего номера. Порту периферии отдано окно 0x1xxx_xxxx (проверка старших 4 бит): в него попадает
    //и DMEM (0x1000_0000), но это безвредно - запись в DMEM видна и на порту, где в окне 0x10 нет устройств,
    //а чтение выбирает DMEM по приоритету. Проверка «ни одно окно не совпало» (DEFAULT_LAST) стоила ~70 LUT
    //и удлиняла пути дешифрации (журнал оптимизации, шаг 20)
    localparam logic [31:0] DMEM_BASE  = 32'h1000_0000;
    localparam logic [31:0] CLINT_BASE = 32'h0200_0000;
    localparam logic [31:0] PLIC_BASE  = 32'h0C00_0000;
    localparam logic [31:0] WIN_MASK   = 32'hFF00_0000;
    localparam logic [31:0] PER_BASE   = 32'h1000_0000;   //Порт периферии: 0x1xxx_xxxx (устройства - с 0x1100_0000)
    localparam logic [31:0] PER_MASK   = 32'hF000_0000;

    logic [ 3:0] mem_Write, clint_Write, plic_Write;
    logic [31:0] mem_Addr, clint_Addr, plic_Addr;
    logic [31:0] mem_WriteData, clint_WriteData, plic_WriteData;
    logic [31:0] mem_ReadData, clint_ReadData, plic_ReadData;
    logic [ 3:0] sRead;

    memmux #(.MEMORY_TYPE(DMEM_TYPE), .SLAVES(4),
              .MATCH_ADDR ({PER_BASE, DMEM_BASE, CLINT_BASE, PLIC_BASE}),
              .MATCH_MASK ({PER_MASK, WIN_MASK,  WIN_MASK,   WIN_MASK}))
            memmux
             (.clk(clk_dmem), .rst(rst_sys),
              .mWrite(bus_Write), .mRead(bus_Read), .mAddr(bus_Addr), .mWData(bus_WData), .mRData(dmem_ReadData),
              .sWrite({bus_per_Write, mem_Write,     clint_Write,     plic_Write}),
              .sRead (sRead),
              .sAddr ({bus_per_Addr,  mem_Addr,      clint_Addr,      plic_Addr}),
              .sWData({bus_per_WData, mem_WriteData, clint_WriteData, plic_WriteData}),
              .sRData({bus_per_RData, mem_ReadData,  clint_ReadData,  plic_ReadData}));
    assign bus_per_Read = sRead[3];

    //#6 Память данных
    mem #(DMEM_TYPE, SYNTH_DMEM_SIZE, BSRAM_DMEM_SIZE, DMEM_INIT_FILE) dmem
          (.clk(clk_dmem), .reset(rst_sys), .re(1'b1), .wstrb(mem_Write),
           .a(mem_Addr), .wd(mem_WriteData),
           .rd(mem_ReadData));

    //#7 Машинный таймер и программное прерывание (CLINT, адреса как у SiFive)
    clint_top #(DMEM_TYPE) clint
                (.clk(clk_dmem), .rst(rst_sys),
                 .Write(clint_Write), .Addr(clint_Addr), .WData(clint_WriteData), .RData(clint_ReadData),
                 .irq_msi(irq_msi), .irq_mti(irq_mti),
                 .mtime(mtime), .mtime_we(mtime_we), .mtime_wdata(mtime_wdata));   //Р3: mtime = mcycle ядра

    //#8 Контроллер прерываний периферии (PLIC, адреса как у SiFive) -> MEI (mcause 11)
    plic_top #(.MEMORY_TYPE(DMEM_TYPE), .NSRC(PLIC_SOURCES)) plic
                (.clk(clk_dmem), .rst(rst_sys),
                 .Write(plic_Write), .Read(sRead[0]), .Addr(plic_Addr), .WData(plic_WriteData), .RData(plic_ReadData),
                 .src(irq_src), .irq(irq_mei),
                 .irq_id(irq_mei_id), .vec_en(irq_mei_vec), .vec_claim(mei_claim), .vec_claim_id(mei_claim_id));
endmodule
