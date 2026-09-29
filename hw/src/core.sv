module core #(parameter bit CORE_TYPE = 1, //       Тип процессора: 1 - Однотактный; 0 - Конвейерный;
              parameter bit IMEM_TYPE = 0, //Тип памяти инструкций: 1 - BSRAM;       0 - Синтезированная;
              parameter bit DMEM_TYPE = 0, //    Тип памяти данных: 1 - BSRAM;       0 - Синтезированная;
              parameter bit M_EXT     = 1, //         Расширение M: 1 - есть;        0 - нет (RV32I);
              parameter int DIV_BPC   = 2) //  Бит частного за такт: 1, 2, 4 (деление 32/DIV_BPC + 2 такта)
             (input  logic        clk,       //Вход тактирования
              input  logic        rst,       //Вход сброса (кнопка S2)
              //Интерфейс памяти команд
              input  logic [31:0] imem_data,
              output logic        imem_re, imem_rst,
              output logic [31:0] imem_addr,
              //Интерфейс памяти данных
              input  logic [31:0] dmem_ReadData,
              output logic [ 3:0] dmem_Write,
              output logic        dmem_Read,  //Строб чтения: загрузка в стадии M (для регистров с побочным действием)
              output logic [31:0] dmem_Addr, dmem_WriteData,
              //Запросы прерываний (уровень, активная 1; источник держит запрос, пока программа не сбросит флаг)
              input  logic        irq_msi,   //Программное прерывание машинного режима (CLINT msip)
              input  logic        irq_mti,   //Прерывание машинного таймера (CLINT mtime >= mtimecmp)
              input  logic        irq_mei,   //Внешнее прерывание (резерв под контроллер PLIC)
              input  logic [15:0] irq_local, //Локальные прерывания LI0..LI15 (коды mcause 16..31)
              //Отладка: модуль DM (Debug Module). Доступ к регистрам - только в режиме останова
              input  logic        dbg_haltreq,   //Запрос останова (уровень)
              input  logic        dbg_resumereq, //Запрос продолжения (импульс)
              output logic        dbg_halted,    //Ядро в режиме отладки (остановлено)
              input  logic [ 4:0] dbg_gpr_addr,
              input  logic        dbg_gpr_we,
              output logic [31:0] dbg_gpr_rdata,
              input  logic [11:0] dbg_csr_addr,
              input  logic        dbg_csr_we,
              output logic [31:0] dbg_csr_rdata,
              input  logic [31:0] dbg_wdata
);

    //Сигналы тракта данных
    logic [4: 0] RdD, Rs1D, Rs2D;
    logic [4: 0] RdE, Rs1E, Rs2E;
    logic [4: 0] RdM;
    logic [4: 0] RdW;

    logic [24:0] ImmD;

    logic [31:0] PCPlus4F, PCF, InstrF;
    logic [31:0] PCPlus4D, PCD, InstrD, ImmExtD, RD1D, RD2D;
    logic [31:0] PCPlus4E, PCE,         ImmExtE, RD1E, RD2E, WriteDataE, ALUResultE, PCTargetE, SrcAE;
    logic [31:0] PCPlus4M,                                   WriteDataM, ALUResultM, ReadDataM;
    logic [31:0] PCPlus4W,                                                           ReadDataW, ResultW;
    logic [31:0] ResultWf;                                      //Результат стадии W для байпаса (без загрузок, Ч3)
    logic [31:0] ResultX;                                       //Результат стадии X - запись в регистровый файл (Ч3)
    logic [ 4:0] RdX;
    logic        RegWriteX;

    logic        funct7b5;
    logic [2: 0] funct3;
    logic [6: 0] op;

    //Сигналы блока управления
    logic RegWriteD, MemWriteD, JumpD, BranchD, JALSrcD;                 logic [1:0] ResultSrcD; logic [2:0] Funct3D, ALUSrcD, ImmSrcD; logic [3:0] ALUControlD;
    logic RegWriteE, MemWriteE, JumpE, BranchE, JALSrcE, PCSrcE, TakenE; logic [1:0] ResultSrcE; logic [2:0] Funct3E, ALUSrcE;          logic [3:0] ALUControlE;
    logic RegWriteM, MemWriteM;                                          logic [1:0] ResultSrcM; logic [2:0] Funct3M;
    logic RegWriteW;                                                     logic [1:0] ResultSrcW; logic [2:0] Funct3W;

    //Сигналы системных инструкций и ловушек (прерывания и исключения)
    logic        ValidD, CsrD, MretD, EcallD, EbreakD, IllegalD; //Valid = 0: в стадии «пузырь» (сброшенная инструкция)
    logic        ValidE, CsrE, MretE, EcallE, EbreakE, IllegalE;
    logic        TrapE, KillE, RedirectE, RedirectSelE;          //Ловушка в стадии E; гашение инструкции; смена PC; её адрес
    logic        RedirectEarlyE;                                 //Смена PC ловушкой без части, зависящей от Taken (Ч15)
    logic [2:0]  BrKindD, BrKindE;                               //Условие перехода, one-hot {eq, lt, ltu} (Ч15)
    logic        BrInvD, BrInvE;                                 //Инверсия условия (bne/bge/bgeu) XOR предсказание (Ч15)
    logic        StallFC, FlushEC;                               //Приостановка PC и сброс стадии E с учётом останова
    logic [31:0] RedirectPCE, PCNextSrcE, CsrRDataE, ResultE;
    logic [31:0] AddrSumE;                                       //Адрес загрузки/записи с сумматора АЛУ (Ч8)
    logic        PCSrcF;                                         //Любая смена PC: переход, ловушка, mret (решение в стадии E)
    logic        PCSrcM;                                         //Смена PC применяется (конвейер: на такт позже, Ч1)
    logic [31:0] PCTargetM;                                      //Новый PC
    logic        ValidX;                                         //Инструкция в стадии E действительна и не на неверном пути
    logic        PredD, PredE;                                   //BTFN: переход выполнен уже в стадии D (jal, переход назад)
    logic [31:0] PCTargetD;                                      //Адрес перехода, вычисленный в стадии D

    //Сигналы расширения M
    logic        MulD, DivD, MulE, DivE, MulM, DivM;             //Умножение (mul*) и деление (div*, rem*)
    logic [31:0] MulAM;                                          //Операнд A умножения в стадии M (B - WriteDataM)
    logic [31:0] MulResM, DivResM;                               //Результаты умножения и деления в стадии M
    logic        DivHold;                                        //Деление в стадии E не закончено: F, D, E стоят

    //Сигналы блока предотвращения конфликтов
    logic [3:0] FwdAD, FwdBD, FwdAE, FwdBE;             //Байпас rs1/rs2, one-hot {M, W, X, рег. файл} (Ч7: считается в D)
    logic [4:0] SelAD, SelAE;                           //Операнд A АЛУ, one-hot {M, W, X, рег. файл, PC}; 0 - ноль
    logic       StallF, StallD, FlushD, FlushE;         //Организация приостановки и предсказателя branch

    //Сигналы блока условных переходов
    logic [2:0] BrFlagsE;

    //CONTROL UNIT//////////////////////////////////////////////////////////////////////////////////
    assign funct7b5 = InstrD[30];
    assign funct3   = InstrD[14:12]; //FIXME: Объединить с Funct3D!
    assign op       = InstrD[6:0];
    control_unit #(M_EXT) cu (.op(op), .funct3(funct3), .funct7b5(funct7b5), .imm12(InstrD[31:20]),
                       .RegWrite(RegWriteD), .MemWrite(MemWriteD), .Jump(JumpD), .Branch(BranchD), .JALSrc(JALSrcD),
                       .ResultSrc(ResultSrcD), .ImmSrc(ImmSrcD), .ALUSrc(ALUSrcD), .ALUControl(ALUControlD),
                       .Csr(CsrD), .Mret(MretD), .Ecall(EcallD), .Ebreak(EbreakD), .Illegal(IllegalD),
                       .Mul(MulD), .Div(DivD));
    conflict_prevention_unit #(CORE_TYPE) pu
                              (.RegWriteE(RegWriteE), .RegWriteM(RegWriteM), .RegWriteW(RegWriteW),
                               .RdM(RdM), .RdW(RdW), .ALUSrcAD(ALUSrcD[2:1]),
                               .ResultSrcM0(ResultSrcM[0]), .ValidD(ValidD),
                               .FwdA(FwdAD), .FwdB(FwdBD), .SelA(SelAD),
                               //Организация пузырька
                               //Результат умножения и деления, как у загрузки, в стадии M ещё не готов (есть с W)
                               .ResultSrcE0(ResultSrcE[0] | MulE | DivE), .Rs1D(Rs1D), .Rs2D(Rs2D), .RdE(RdE),
                               .Hold(DivHold),
                               .StallF(StallF), .StallD(StallD), .FlushE(FlushE),
                                //Предсказание перехода branch
                               .PCSrcE(PCSrcM), .PredD(PredD), .FlushD(FlushD));
    //FETCH/////////////////////////////////////////////////////////////////////////////////////////
    //В режиме останова PC заморожен (кроме смены PC при продолжении), стадия E непрерывно сбрасывается
    //Пока идёт деление, стоят F, D и E. Смена PC важнее: в однотактном ядре ловушка во время деления
    //меняет PC в том же такте (в конвейере DivHold и PCSrcM не совпадают - DivHold требует ValidX)
    assign StallFC = StallF | ((DivHold | dbg_halted) & ~PCSrcM);
    //Ч9: сброс стадии D - только регистр ValidD (без выводов RESET памяти инструкций и регистров D);
    //недействительная инструкция в D становится пузырём при переходе в E
    assign FlushEC = (FlushE | dbg_halted | ~ValidD) & ~DivHold;
    fetch fetch(    .clk(clk), .rst(rst), .PCSrc(PCSrcM), .StallF(StallFC),
                    .PCTarget(PCTargetM), .PredD(PredD), .PCTargetD(PCTargetD),
                    .PC(PCF), .PCPlus4(PCPlus4F), .Instr(InstrF),
                    //Интерфейс памяти инструкций
                    .imem_data(imem_data),
                    .imem_re(imem_re), .imem_rst(imem_rst), .imem_addr(imem_addr),
                    //Предсказание перехода branch
                    .StallD(StallD), .FlushD(FlushD));
    ////////////////////////////////////////////////////////////////////////////////////////////////
    regmem  #(CORE_TYPE, IMEM_TYPE) rm_fetch (clk, FlushD|rst, StallD, InstrF, InstrD);
    regdata #(2, CORE_TYPE)         rd_fetch (clk, rst,        StallD, {PCF, PCPlus4F},
                                                                       {PCD, PCPlus4D});
    regcontrol #(1, CORE_TYPE)      rc_fetch (clk, FlushD|rst, StallD, ~dbg_halted, ValidD); //В однотактном ядре ValidD = ~dbg_halted
    //DECODE////////////////////////////////////////////////////////////////////////////////////////
    decode #(CORE_TYPE) decode(  .clk(clk), .rst(rst), .RegWrite(RegWriteX), .ImmSrc(ImmSrcD),
                                 .Addr1(Rs1D), .Addr2(Rs2D), .Addr3(RdX), .Imm(ImmD),
                                 .Result(ResultX),
                                 .RD1(RD1D), .RD2(RD2D), .ImmExt(ImmExtD),
                                 .DbgSel(dbg_halted), .DbgAddr(dbg_gpr_addr), .DbgWe(dbg_gpr_we & dbg_halted), .DbgWData(dbg_wdata),
                                 .DbgRData(dbg_gpr_rdata));
    assign Rs1D    = InstrD[19:15];
    assign Rs2D    = InstrD[24:20];
    assign RdD     = InstrD[11:7];
    assign ImmD    = InstrD[31:7];
    assign Funct3D = InstrD[14:12];
    //Статический предсказатель BTFN (Backward Taken, Forward Not taken) в стадии D. jal и условный
    //переход назад (бит 31 = знак смещения) выполняются сразу из D: PC <= PCD + imm, сбрасывается
    //одна инструкция, выбранная следом, - штраф 1 такт. Переход вперёд идёт дальше как невыполненный.
    //Смещение берётся прямо из битов инструкции (форматы B и J), без общего дешифратора ImmExt.
    //Не предсказываются: переход на невыровненный адрес (imm[1] = 1, ловушку вызывает стадия E),
    //инструкция в приостановленной стадии D и инструкция неверного пути (в этом такте PC меняет E).
    generate if (CORE_TYPE) begin   //#1 - Однотактное ядро: предсказания нет
        assign PredD     = 1'b0;
        assign PCTargetD = 32'd0;
    end else begin                  //#0 - Конвеерное ядро
        logic        is_jal, is_br;
        logic [31:0] imm_j, imm_b;
        assign is_jal = (InstrD[6:0] == 7'b1101111);
        assign is_br  = (InstrD[6:0] == 7'b1100011);
        assign imm_j  = {{12{InstrD[31]}}, InstrD[19:12], InstrD[20], InstrD[30:21], 1'b0};
        assign imm_b  = {{20{InstrD[31]}}, InstrD[7], InstrD[30:25], InstrD[11:8], 1'b0};
        assign PCTargetD = PCD + (is_jal ? imm_j : imm_b);
        //Ч9: выбор адреса PC не ждёт lwStall - при приостановке PC и так держится (StallF), а сброс
        //следующей инструкции (FlushD) разрешается только без приостановки
        assign PredD  = ValidD & ~PCSrcM &
                        ((is_jal & ~InstrD[21]) | (is_br & InstrD[31] & ~InstrD[8]));
    end
    endgenerate
    ////////////////////////////////////////////////////////////////////////////////////////////////
    regdata #(5, CORE_TYPE) rd_decode     (clk, FlushEC|rst, DivHold, {PCD, PCPlus4D, ImmExtD, RD1D, RD2D},
                                                                  {PCE, PCPlus4E, ImmExtE, RD1E, RD2E});
    regrf   #(3, CORE_TYPE) rf_decode     (clk, FlushEC|rst, DivHold, {Rs1D, Rs2D, RdD},
                                                                  {Rs1E, Rs2E, RdE});
    //Пока идёт деление (DivHold), регистры стадии E держат инструкцию и не сбрасываются
    regcontrol #(20, CORE_TYPE) rc_decode (clk, FlushEC|rst, DivHold,
                    {RegWriteD, ResultSrcD[1:0], MemWriteD, JumpD, BranchD, ALUControlD[3:0], ALUSrcD[2:0], Funct3D[2:0], JALSrcD, PredD, MulD, DivD},
                    {RegWriteE, ResultSrcE[1:0], MemWriteE, JumpE, BranchE, ALUControlE[3:0], ALUSrcE[2:0], Funct3E[2:0], JALSrcE, PredE, MulE, DivE});
    regcontrol #(13, CORE_TYPE) rw_decode (clk, FlushEC|rst, DivHold, {FwdAD, FwdBD, SelAD}, {FwdAE, FwdBE, SelAE});
    //Ч15: условие перехода раскладывается в стадии D - какое сравнение (one-hot) и нужна ли инверсия.
    //Инверсия учитывает и предсказание: смена PC нужна, если «выполнен» != «предсказан», то есть
    //cond ^ funct3[0] ^ PredD. В стадии E остаётся И-ИЛИ результатов сравнения и один XOR.
    assign BrKindD = {Funct3D[2:1] == 2'b00, Funct3D[2:1] == 2'b10, Funct3D[2:1] == 2'b11};   //{eq, lt, ltu}
    assign BrInvD  = Funct3D[0] ^ PredD;
    regcontrol #(4, CORE_TYPE)  rb_decode (clk, FlushEC|rst, DivHold, {BrKindD, BrInvD}, {BrKindE, BrInvE});
    //Признаки системных инструкций идут в стадию E вместе с признаком действительной инструкции:
    //сброшенная инструкция 0x00000000 декодируется как недопустимая, но ловушку вызывать не должна
    regcontrol #(6, CORE_TYPE) rs_decode  (clk, FlushEC|rst, DivHold,
                    {ValidD, CsrD & ValidD, MretD & ValidD, EcallD & ValidD, EbreakD & ValidD, IllegalD & ValidD},
                    {ValidE, CsrE,          MretE,          EcallE,          EbreakE,          IllegalE});
    //EXECUTE///////////////////////////////////////////////////////////////////////////////////////
    execute #(CORE_TYPE) execute
             (.JALSrc(JALSrcE), .FwdA(FwdAE), .FwdB(FwdBE), .SelA(SelAE), .ALUSrc(ALUSrcE), .ALUControl(ALUControlE),
              .RD1(RD1E), .RD2(RD2E), .PC(PCE), .ImmExt(ImmExtE), .ResultW(ResultWf), .ALUResultM(ALUResultM), .ResultX(ResultX),
              .BrFlags(BrFlagsE), .ALUResult(ALUResultE), .WriteData(WriteDataE),
              //Особенные
              .PCTarget(PCTargetE), .SrcA(SrcAE), .AddrSum(AddrSumE));
    branch_unit bu (.Branch(BranchE), .funct3(Funct3E), .BrFlags(BrFlagsE), .taken(TakenE));
    ////Логика JUMP/BRANCH
    //Смена PC из стадии E: jal, не выполненный в D (невыровненный адрес - ловушка), jalr и
    //условный переход, предсказанный неверно (Taken != PredE)
    logic br_redirect;              //Условный переход требует смены PC (выполнен, но не предсказан, или наоборот)
    assign br_redirect = ((BrKindE[2] & BrFlagsE[2]) | (BrKindE[1] & BrFlagsE[1]) | (BrKindE[0] & BrFlagsE[0])) ^ BrInvE;
    assign PCSrcE = ValidX & ((JumpE & ~PredE) | (BranchE & br_redirect));
    ////Запросы прерываний
    //Однотактное ядро с BSRAM пишет в периферию в середине своего такта (clk_dmem), и запрос,
    //выставленный этой записью, не должен влиять на решение о ловушке в том же такте - иначе
    //ловушка примется на уже выполненной записи. Поэтому запросы защёлкиваются по фронту ядра.
    //В конвейерном ядре всё меняется по одному фронту, и регистр только добавил бы такт задержки:
    //после снятия запроса обработчиком и mret прерывание приходило бы повторно.
    logic        irq_msi_c, irq_mti_c, irq_mei_c;
    logic [15:0] irq_local_c;
    generate if (CORE_TYPE) begin   //#1 - Однотактное ядро
        always_ff @(posedge clk)
            if (rst) {irq_msi_c, irq_mti_c, irq_mei_c, irq_local_c} <= '0;
            else     {irq_msi_c, irq_mti_c, irq_mei_c, irq_local_c} <= {irq_msi, irq_mti, irq_mei, irq_local};
    end else begin                  //#0 - Конвеерное ядро
        assign {irq_msi_c, irq_mti_c, irq_mei_c, irq_local_c} = {irq_msi, irq_mti, irq_mei, irq_local};
    end
    endgenerate
    ////Регистры CSR, прерывания и исключения
    trap_unit #(.LATE_BR_TRAP(!CORE_TYPE), .M_EXT(M_EXT)) trap_unit
             (.clk(clk), .rst(rst),
              //Инструкция в стадии E
              .Valid(ValidX), .Hold(DivHold), .Csr(CsrE & ValidX), .Mret(MretE & ValidX), .Ecall(EcallE & ValidX), .Ebreak(EbreakE & ValidX), .Illegal(IllegalE & ValidX),
              .Funct3(Funct3E), .CsrAddr(ImmExtE[11:0]), .Zimm(Rs1E), .Rs1Data(SrcAE),
              .PC(PCE), .Jump(JumpE), .Branch(BranchE), .JalrSel(JALSrcE), .Taken(TakenE), .ImmLo(ImmExtE[1:0]),
              .PCTarget(PCTargetE),
              .Load(ResultSrcE == 2'b01), .Store(MemWriteE), .MemAddr(AddrSumE),   //Ч8: mtval - с сумматора, без выбора операции АЛУ
              //Запросы прерываний
              .irq_msi(irq_msi_c), .irq_mti(irq_mti_c), .irq_mei(irq_mei_c), .irq_local(irq_local_c),
              //Отладка
              .haltreq(dbg_haltreq), .resumereq(dbg_resumereq), .Halted(dbg_halted),
              .DbgCsrAddr(dbg_csr_addr), .DbgCsrWe(dbg_csr_we), .DbgWData(dbg_wdata),
              //Результат
              .CsrRData(CsrRDataE), .Trap(TrapE), .Kill(KillE), .Redirect(RedirectE), .RedirectEarly(RedirectEarlyE), .RedirectSel(RedirectSelE), .RedirectPC(RedirectPCE));
    assign dbg_csr_rdata = CsrRDataE;
    //Смена PC: ловушка и mret важнее перехода
    assign PCSrcF     = PCSrcE | RedirectEarlyE;   //Ч15: без части ловушки, зависящей от Taken (её покрывает PCSrcE)
    //Выбор адреса не ждёт сравнения: предсказан «выполнен» -> исправление на PC+4, иначе - адрес перехода
    assign PCNextSrcE = RedirectSelE ? RedirectPCE : PredE ? PCPlus4E : PCTargetE;
    //Ч1: в конвейере решение о смене PC защёлкивается в конце стадии E и применяется в следующем
    //такте (PC, сброс D и E, сброс выхода BSRAM). Так путь «загрузка -> АЛУ -> решение» и путь
    //«решение -> PC» лежат в разных тактах. Цена - переход и ловушка на такт дольше (3 такта).
    //Инструкция, которая в этом такте стоит в стадии E, - следующая за переходом (неверный путь):
    //ValidX = 0 гасит её запись в регистры и память и все её действия в trap_unit.
    //В однотактном ядре смена PC применяется сразу, как раньше.
    generate if (CORE_TYPE) begin   //#1 - Однотактное ядро
        assign PCSrcM    = PCSrcF;
        assign PCTargetM = PCNextSrcE;
        assign ValidX    = ValidE;
    end else begin                  //#0 - Конвеерное ядро
        always_ff @(posedge clk)
            if (rst) PCSrcM <= 1'b0;
            else     PCSrcM <= PCSrcF;
        always_ff @(posedge clk)
            PCTargetM <= PCNextSrcE;
        assign ValidX = ValidE & ~PCSrcM;
    end
    endgenerate
    //Результат CSR-инструкции (старое значение CSR) идёт по тракту ALUResult, поэтому работает байпас
    assign ResultE    = CsrE ? CsrRDataE : ALUResultE;
    ////Расширение M: деление в стадии E
    //Деление занимает 32/DIV_BPC + 2 такта в стадии E: F, D и E стоят (DivHold), в M уходят пузыри.
    //Результат забирается в стадии M, как у умножения: делитель держит его до начала следующего деления.
    //Так в пути «байпас -> АЛУ -> регистр E/M» не появляется ещё один мультиплексор.
    //Ловушка во время деления гасит инструкцию и сбрасывает делитель, после mret деление идёт заново.
    generate if (M_EXT) begin : g_div
        logic div_done;
        mdu_div #(DIV_BPC) mdu_div
                (.clk(clk), .rst(rst),
                 .req(ValidX & DivE), .cancel(CORE_TYPE ? KillE : 1'b0),   //В конвейере гашение снимает req (ValidX)
                 .a(SrcAE), .b(WriteDataE), .is_signed(~Funct3E[0]), .is_rem(Funct3E[1]),
                 .done(div_done), .result(DivResM));
        assign DivHold = ValidX & DivE & ~div_done;
    end else begin : g_nodiv
        assign DivHold = 1'b0;
        assign DivResM = 32'd0;
    end
    endgenerate
    ////////////////////////////////////////////////////////////////////////////////////////////////
    //Инструкция, на которой произошла ловушка, гасится: не пишет в регистры и в память
    regdata    #(3, CORE_TYPE) rd_execute (clk, rst, 1'b0, {PCPlus4E, WriteDataE, ResultE},
                                                           {PCPlus4M, WriteDataM, ALUResultM});
    regrf      #(1, CORE_TYPE) rf_execute (clk, rst, 1'b0, {RdE},
                                                           {RdM});
    //(в однотактном ядре ValidE = 0 в режиме останова: инструкция по замороженному PC не выполняется)
    //Пока идёт деление, в стадию M уходят пузыри: запись разрешена только в последнем такте деления
    regcontrol #(9, CORE_TYPE) rc_execute (clk, rst, 1'b0, {RegWriteE & ValidX & ~KillE & ~DivHold, ResultSrcE[1:0], MemWriteE & ValidX & ~KillE, Funct3E[2:0], MulE, DivE},
                                                           {RegWriteM,                     ResultSrcM[1:0], MemWriteM,          Funct3M[2:0], MulM, DivM});
    //MEMORY////////////////////////////////////////////////////////////////////////////////////////
    memory memory ( .MemWrite(MemWriteM), .Funct3(Funct3M),
                    .ALUResult(ALUResultM), .WriteData(WriteDataM),
                    .ReadData(ReadDataM),
                    //Интерфейс памяти данных
                    .dmem_ReadData(dmem_ReadData),
                    .dmem_Write(dmem_Write), .dmem_Addr(dmem_Addr),
                    .dmem_WriteData(dmem_WriteData));
    ////Расширение M: умножение в стадии M на блоках DSP
    //Операнды защёлкиваются на границе E/M (rs2 - это WriteDataM), результат - на границе M/W (rd_wf).
    //Зависимой инструкции результат доступен из W: при умножении в E она ждёт 1 такт (как после загрузки)
    generate if (M_EXT) begin : g_mul
        regdata #(1, CORE_TYPE) rd_mul (clk, rst, 1'b0, {SrcAE}, {MulAM});
        mdu_mul mdu_mul (.a(MulAM), .b(WriteDataM), .funct3(Funct3M[1:0]), .result(MulResM));
    end else begin : g_nomul
        assign MulAM   = 32'd0;
        assign MulResM = 32'd0;
    end
    endgenerate
    ////////////////////////////////////////////////////////////////////////////////////////////////
    regmem     #(CORE_TYPE, DMEM_TYPE) rm_memory (clk, rst, 1'b0, ReadDataM, ReadDataW);
    regdata    #(1, CORE_TYPE)         rd_memory (clk, rst, 1'b0, {PCPlus4M},
                                                                  {PCPlus4W});
    regrf      #(1, CORE_TYPE)         rf_memory (clk, rst, 1'b0, {RdM},
                                                                  {RdW});
    regcontrol #(6, CORE_TYPE)         rc_memory (clk, rst, 1'b0, {RegWriteM, ResultSrcM[1:0], Funct3M[2:0]}, 
                                                                  {RegWriteW, ResultSrcW[1:0], Funct3W[2:0]});
    assign dmem_Read = (ResultSrcM == 2'b01) & RegWriteM;   //Загрузка, не погашенная ловушкой
    //WRITEBACK/////////////////////////////////////////////////////////////////////////////////////
    writeback writeback (   .ResultSrc(ResultSrcW), .Funct3(Funct3W),
                            .ALUResult(ResultWf), .ReadData(ReadDataW), .PCPlus4(PCPlus4W),   //ResultWf: АЛУ, mul, div
                            //Особенные
                            .Result(ResultW));
    ////////////////////////////////////////////////////////////////////////////////////////////////
    //Ч3: стадия X - результат (в том числе выровненные и расширенные знаком данные загрузки)
    //защёлкивается и пишется в регистровый файл тактом позже. Путь «выход памяти данных -> выбор
    //данных -> выравнивание и знак» заканчивается на регистре, а не идёт дальше в байпас и АЛУ.
    //Байпасу из W остаются только результат АЛУ и PC+4 (ResultWf). В однотактном ядре регистры
    //прозрачны: запись, как раньше, в том же такте.
    //Ч11: значение для байпаса из W (результат АЛУ или PC+4) выбирается ещё в стадии M и защёлкивается:
    //в W оно готово сразу, без мультиплексора по ResultSrcW. Сюда же - результаты умножения и деления;
    //у загрузки это адрес (ALUResultM): по младшим битам writeback выравнивает данные
    regdata    #(1, CORE_TYPE) rd_wf (clk, rst, 1'b0, {MulM ? MulResM : DivM ? DivResM : (ResultSrcM == 2'b10) ? PCPlus4M : ALUResultM}, {ResultWf});
    regdata    #(1, CORE_TYPE) rd_wb (clk, rst, 1'b0, {ResultW},   {ResultX});
    regrf      #(1, CORE_TYPE) rf_wb (clk, rst, 1'b0, {RdW},       {RdX});
    regcontrol #(1, CORE_TYPE) rc_wb (clk, rst, 1'b0, {RegWriteW}, {RegWriteX});

endmodule

//#cu - Блок управления//
//DESCRIPTION: Блоку управления (БУ) формирует управляющие сигналы
//для тракта данных в зависимости от типа инструкции. Условно
//разделён на 3 узла:
//1) Основной дешифратор - формирует основную часть управляющих
//сигналов для всех узлов тракта данных в зависимости от кода опреации
//op[6:0], а также формирует внутренний сигнал ALUOp для предвыбора
//операции АЛУ.
//2) Дешифратор АЛУ - выбирает тип операции в АЛУ на основе сигнала
//ALUOp, 5ого бита поля funct7 и битов [2:0] поля funct3;
//3) Логика JUMP/BRANCH - выбирает источник смещения для приращения
//счётчика команд: PC=PC+4 при PCSrc=0, PC=PC+Imm при PCSrc=0.
//4) Дешифратор системных инструкций - CSR-инструкции (Zicsr), ecall,
//ebreak, mret, wfi и признак недопустимой инструкции.
module control_unit #(parameter bit M_EXT = 1) (
    input logic [6:0]   op,
    input logic [2:0]   funct3,
    input logic         funct7b5,
    input logic [11:0]  imm12,      //Instr[31:20]: адрес CSR или код системной инструкции
    
    output logic        RegWrite, MemWrite, Jump, Branch, JALSrc,
    output logic [1:0]  ResultSrc,
    output logic [2:0]  ImmSrc, ALUSrc,
    output logic [3:0]  ALUControl,
    output logic        Csr, Mret, Ecall, Ebreak, Illegal,
    output logic        Mul, Div        //Расширение M: mul/mulh/mulhsu/mulhu; div/divu/rem/remu
);

    logic [1:0] ALUOp;

    logic [14:0] controls; //Сборка сигналов управлеиня
                                 //A[2:1] B[0]
    assign {RegWrite, ImmSrc[2:0], ALUSrc[2:0], MemWrite, ResultSrc[1:0], Branch, ALUOp[1:0], Jump, JALSrc} = controls;
    //          A          BB           C           D          EE           F         GG        H      I
    ////#cu.1 Основной дешифратор
    always_comb
        casez(op)                    //A_BBB_CCC_D_EE_F_GG_H_I
            7'b0000011: controls = 15'b1_000_001_0_01_0_00_0_0; //Команда lw
            7'b0100011: controls = 15'b0_001_001_1_00_0_00_0_0; //Команда sw
            7'b0110011: controls = 15'b1_000_000_0_00_0_10_0_0; //Команды тип R
            7'b1100011: controls = 15'b0_010_000_0_00_1_01_0_0; //Команда тип B
            7'b0010011: controls = 15'b1_000_001_0_00_0_10_0_0; //Команда тип I
            7'b1101111: controls = 15'b1_011_000_0_10_0_00_1_0; //Команда jal
            7'b1100111: controls = 15'b1_000_000_0_10_0_00_1_1; //Команда jalr
            7'b0010111: controls = 15'b1_100_011_0_00_0_00_0_0; //Команда auipc
            7'b0110111: controls = 15'b1_100_101_0_00_0_00_0_0; //Команда lui
            7'b1110011: controls = {funct3 != 3'b000, 14'b000_000_0_00_0_00_0_0}; //Команды SYSTEM: CSR пишут в rd старое значение CSR
            default:    controls = 15'b0_000_000_0_00_0_00_0_0; //fence и другие команды - NOP (в т.ч. пузырь 0x00000000 после сброса конвейера)
        endcase
    ////#cu.2 Дешифратор АЛУ
    logic opb5;
    logic RtypeSub;
    assign opb5 = op[5];
    assign RtypeSub = funct7b5 & opb5;
    always_comb
        case(ALUOp)
            2'b00:   ALUControl = 4'b0000;                                   //lw,sw,lui,auipc
            2'b01:   ALUControl = 4'b0001;                                   //beq, bne
            default: case(funct3)
                        3'b000:  ALUControl = (RtypeSub) ? 4'b0001 : 4'b0000;//sub : add,addi
                        3'b001:  ALUControl = 4'b0110;                       //sll, slli
                        3'b010:  ALUControl = 4'b0101;                       //slt, slti
                        3'b011:  ALUControl = 4'b1001;                       //sltu, sltiu
                        3'b100:  ALUControl = 4'b0100;                       //xor, xori
                        3'b101:  ALUControl = (funct7b5) ? 4'b1000 : 4'b0111;//sra, srai : srl, srli                       
                        3'b110:  ALUControl = 4'b0011;                       //or, ori
                        3'b111:  ALUControl = 4'b0010;                       //and, andi
                        default: ALUControl = 4'bxxxx;                       //Другие команды
                     endcase
        endcase
    ////#cu.3 Прочие связи 

    ////#cu.5 Расширение M: тип R с funct7 = 0000001, funct3[2] = 0 - умножение, 1 - деление.
    //Операция АЛУ такой инструкции не используется: результат берётся с умножителя или делителя
    logic muldiv;
    assign muldiv = (op == 7'b0110011) & (imm12[11:5] == 7'b0000001);
    assign Mul    = M_EXT & muldiv & ~funct3[2];
    assign Div    = M_EXT & muldiv &  funct3[2];

    ////#cu.4 Дешифратор системных инструкций
    //SYSTEM (1110011): funct3 != 000 - CSR-инструкции (funct3 = 100 не определён);
    //funct3 = 000 - код в imm12: ecall 000, ebreak 001, mret 302, wfi 105 (выполняется как nop)
    logic system;
    assign system = (op == 7'b1110011);
    assign Csr    = system & (funct3 != 3'b000) & (funct3 != 3'b100);
    assign Ecall  = system & (funct3 == 3'b000) & (imm12 == 12'h000);
    assign Ebreak = system & (funct3 == 3'b000) & (imm12 == 12'h001);
    assign Mret   = system & (funct3 == 3'b000) & (imm12 == 12'h302);
    always_comb
        casez(op)
            7'b0110011: Illegal = muldiv & ~M_EXT;                           //Без расширения M - недопустима
            7'b0000011, 7'b0100011,             7'b1100011, 7'b0010011,
            7'b1101111, 7'b1100111, 7'b0010111, 7'b0110111,
            7'b0001111: Illegal = 1'b0;                                       //RV32I и fence
            7'b1110011: Illegal = ~(Csr | Ecall | Ebreak | Mret |
                                    ((funct3 == 3'b000) & (imm12 == 12'h105))); //wfi
            default:    Illegal = 1'b1;
        endcase

endmodule

module branch_unit (
    input  logic       Branch,
    input  logic [2:0] funct3,
    input  logic [2:0] BrFlags,     //{eq, lt, ltu} - сравнение rs1 и rs2 (execute)
    output logic       taken
);

    logic eq, lt, ltu;
    logic cond;                     //1 - условие перехода выполнено
    assign {eq, lt, ltu} = BrFlags;
    assign taken = cond & Branch;

    always_comb
        case (funct3)
            3'b000: cond = eq;      //beq
            3'b001: cond = ~eq;     //bne
            3'b100: cond = lt;      //blt
            3'b101: cond = ~lt;     //bge
            3'b110: cond = ltu;     //bltu
            3'b111: cond = ~ltu;    //bgeu
            default: cond = 1'b0;
        endcase
endmodule

//#trap - Блок CSR, прерываний и исключений машинного режима//
//DESCRIPTION: Работает в стадии E. Реализует Zicsr (csrrw/csrrs/csrrc и варианты
//с непосредственным значением), ловушки и mret по привилегированной спецификации
//RISC-V в объёме ядра SiFive с контроллером CLINT (без CLIC и PLIC).
//1) Ловушка принимается на действительной инструкции в стадии E: инструкция гасится,
//mepc = её PC, в mcause - причина, mstatus.MPIE = MIE, MIE = 0, PC = вектор ловушки.
//Старшие инструкции в стадиях M и W завершаются - ловушка точная.
//2) mtvec.MODE = 0 - все ловушки на BASE; MODE = 1 (векторный режим) - прерывание
//с кодом N на BASE | (N << 2), исключения на BASE. Адрес собирается без сумматора,
//поэтому в векторном режиме BASE выравнивается на 128 байт (32 входа по 4 байта).
//3) Приоритет прерываний фиксированный (как в CLINT): MEI > MSI > MTI > LI0 > ... > LI15.
//4) Для подключения отладчика: ebreak - исключение 3 (Breakpoint); CSR триггеров
//(tselect, tdata1-3) и отладки (dcsr, dpc, dscratch) не реализованы и читаются как 0 -
//по tdata1.type = 0 отладчик определяет, что аппаратных точек останова нет.
//Все прочие нереализованные CSR тоже читаются как 0, запись в них игнорируется.
module trap_unit #(parameter bit LATE_BR_TRAP = 0,    //1 - конвейер: CSR ловушки перехода на такт позже (Ч1),
                                                      //доступ DM к CSR через ИЛИ (Ч13)
                   parameter bit M_EXT = 1)           //Расширение M (бит M в misa)
   (input  logic        clk, rst,
    //Инструкция в стадии E
    input  logic        Valid,             //0 - в стадии пузырь
    input  logic        Hold,              //Инструкция остаётся в стадии E и в следующем такте (деление)
    input  logic        Csr, Mret, Ecall, Ebreak, Illegal,
    input  logic [ 2:0] Funct3,
    input  logic [11:0] CsrAddr,
    input  logic [ 4:0] Zimm,              //Поле rs1: непосредственное значение csrr*i / признак rs1 = x0
    input  logic [31:0] Rs1Data,           //rs1 с учётом байпаса
    input  logic [31:0] PC,
    input  logic        Jump, Branch,      //jal/jalr; условный переход
    input  logic        JalrSel,           //1 - jalr (адрес = rs1 + imm)
    input  logic        Taken,             //Условный переход выполняется
    input  logic [ 1:0] ImmLo,             //Младшие биты непосредственного значения
    input  logic [31:0] PCTarget,          //Адрес перехода - только значение для mtval
    input  logic        Load, Store,
    input  logic [31:0] MemAddr,           //Адрес обращения к памяти - только значение для mtval
    //Запросы прерываний
    input  logic        irq_msi, irq_mti, irq_mei,
    input  logic [15:0] irq_local,
    //Отладка
    input  logic        haltreq, resumereq,
    output logic        Halted,
    input  logic [11:0] DbgCsrAddr,
    input  logic        DbgCsrWe,
    input  logic [31:0] DbgWData,
    //Результат
    output logic [31:0] CsrRData,          //Старое значение CSR - результат CSR-инструкции
    output logic        Trap,              //Ловушка: инструкция в стадии E гасится
    output logic        Kill,              //Инструкция в стадии E гасится (ловушка или вход в отладку)
    output logic        Redirect,          //Смена PC ловушкой или mret
    output logic        RedirectSel,       //Адрес смены PC берётся из RedirectPC (известно до сравнения, Ч1)
    output logic        RedirectEarly,     //Смена PC ловушкой/mret/отладкой без части, зависящей от Taken (Ч15)
    output logic [31:0] RedirectPC
);
    //#1 Адреса CSR
    localparam logic [11:0] MSTATUS  = 12'h300, MISA   = 12'h301, MIE    = 12'h304, MTVEC   = 12'h305,
                            MSCRATCH = 12'h340, MEPC   = 12'h341, MCAUSE = 12'h342, MTVAL   = 12'h343,
                            MIP      = 12'h344, MCYCLE = 12'hB00, MCYCLEH = 12'hB80,
                            CYCLE    = 12'hC00, CYCLEH = 12'hC80,
                            DCSR     = 12'h7B0, DPC    = 12'h7B1;

    //#2 Регистры
    logic        mstatus_mie, mstatus_mpie;
    logic        mie_msie, mie_mtie, mie_meie;
    logic [15:0] mie_local;
    logic [31:2] mtvec_base;
    logic        mtvec_mode;
    logic [31:0] mscratch, mtval;
    logic [31:2] mepc;
    logic        mcause_int;
    logic [ 4:0] mcause_code;
    logic [63:0] mcycle;

    logic [31:0] mip, mie;
    assign mip = {irq_local, 4'b0, irq_mei,  3'b0, irq_mti,  3'b0, irq_msi,  3'b0};
    assign mie = {mie_local, 4'b0, mie_meie, 3'b0, mie_mtie, 3'b0, mie_msie, 3'b0};

    //#3 Выбор прерывания
    logic [31:0] pending;
    logic [ 4:0] irq_code;
    logic        irq_take;
    assign pending = mip & mie;
    always_comb begin
        irq_code = 5'd0;
        for (int i = 31; i >= 16; i--)      //Меньший номер локального прерывания важнее
            if (pending[i]) irq_code = i[4:0];
        if (pending[7])  irq_code = 5'd7;   //MTI
        if (pending[3])  irq_code = 5'd3;   //MSI
        if (pending[11]) irq_code = 5'd11;  //MEI
    end
    //#3.1 Режим отладки (RISC-V Debug 0.13). Вход - в стадии E на действительной инструкции, она не
    //выполняется: dpc = её PC. Причины: ebreak при dcsr.ebreakm = 1 (cause 1), запрос останова от
    //DM (cause 3), завершение шага при dcsr.step = 1 (cause 4). Вход в отладку важнее ловушек.
    //В режиме останова PC заморожен, конвейер пуст; продолжение - PC = dpc. Во время шага
    //прерывания запрещены (dcsr.stepie = 0).
    logic        halted, step_active, step_passed;
    logic        dcsr_ebreakm, dcsr_step;
    logic [ 2:0] dcsr_cause;
    logic [31:2] dpc;
    logic        debug_entry, resume_do;
    logic [ 2:0] debug_cause;
    assign debug_entry = Valid & ~halted & ((Ebreak & dcsr_ebreakm) | haltreq | (step_active & step_passed));
    assign debug_cause = (Ebreak & dcsr_ebreakm) ? 3'd1 : haltreq ? 3'd3 : 3'd4;
    assign resume_do   = halted & resumereq;
    assign Halted      = halted;

    assign irq_take = mstatus_mie & (|pending) & Valid & ~step_active & ~debug_entry;

    //#4 Исключения
    //Выравнивание проверяется по младшим битам операндов, а не по результату АЛУ и сумматора
    //адреса перехода: так решение о ловушке не ждёт 32-битного переноса (критический путь, Ч2).
    //  - PC всегда кратен 4 (сжатых команд нет, все пути смены PC выровнены), поэтому у jal и
    //    условных переходов бит 1 адреса перехода = imm[1];
    //  - у jalr и загрузок/записей адрес = rs1 + imm: младшие 2 бита суммы зависят только от
    //    младших 2 бит слагаемых. Бит 0 адреса jalr обнуляется, проверяется бит 1.
    //Результат АЛУ (MemAddr) и адрес перехода (PCTarget) идут только в mtval.
    logic       misalign_fetch, misalign_load, misalign_store, misalign_mem, exc;
    logic [1:0] addr_lo;
    logic       target1;
    logic [4:0] exc_code;
    logic [31:0] exc_tval;
    assign addr_lo        = Rs1Data[1:0] + ImmLo;
    assign target1        = JalrSel ? addr_lo[1] : ImmLo[1];
    assign misalign_mem   = (Funct3[1:0] == 2'b01 & addr_lo[0]) | (Funct3[1:0] == 2'b10 & |addr_lo);
    //Условный переход с невыровненным адресом - единственная ловушка, которая зависит от результата
    //сравнения (Taken). Кандидат на неё известен до сравнения: по нему заранее выбираются код, mtval
    //и адрес перехода (вектор ловушки), а Taken лишь разрешает ловушку последним вентилем (Ч1).
    //Переход ничего не пишет в регистры и память, поэтому гасить его (Kill) не нужно.
    logic misalign_fetch_cand, exc_early;
    assign misalign_fetch_cand = Valid & target1 & (Jump | Branch);
    assign misalign_fetch      = Valid & target1 & (Jump | (Branch & Taken));
    assign misalign_load  = Valid & Load  & misalign_mem;
    assign misalign_store = Valid & Store & misalign_mem;
    assign exc_early = Illegal | Ecall | Ebreak | (Valid & target1 & Jump) | misalign_load | misalign_store;
    assign exc       = exc_early | misalign_fetch;
    always_comb begin
        exc_tval = 32'd0;
        if      (Illegal)        exc_code = 5'd2;                          //Illegal instruction
        else if (Ecall)          exc_code = 5'd11;                         //Environment call from M-mode
        else if (Ebreak)         exc_code = 5'd3;                          //Breakpoint
        else if (misalign_fetch_cand) begin exc_code = 5'd0; exc_tval = PCTarget; end //Instruction address misaligned
        else if (misalign_load)  begin exc_code = 5'd4; exc_tval = MemAddr;  end //Load address misaligned
        else                     begin exc_code = 5'd6; exc_tval = MemAddr;  end //Store address misaligned
    end

    //#5 Ловушка и смена PC. Прерывание принимается до выполнения инструкции и важнее исключения
    logic mret_do;
    logic trap_sel;                                      //Если ловушка будет, то эта (без Taken)
    assign Trap       = (irq_take | exc) & ~debug_entry;
    assign trap_sel   = (irq_take | exc_early | misalign_fetch_cand) & ~debug_entry;
    assign Kill       = ((irq_take | exc_early) & ~debug_entry) | debug_entry;
    //Запись CSR при ловушке (mepc, mcause, mtval, mstatus). В конвейере ловушка невыровненного
    //условного перехода записывает CSR на такт позже, из защёлкнутых значений: иначе разрешение
    //записи ждало бы сравнения (Taken) - это был бы критический путь. В следующем такте в стадии E
    //погашенная инструкция неверного пути, затем пузыри: обработчик до записи CSR не дойдёт,
    //прерывание и вход в отладку не принимаются (Valid = 0). В однотактном ядре следующая
    //инструкция - уже обработчик, поэтому там запись немедленная.
    logic        trap_csr, br_trap_q;
    logic [31:2] br_epc_q;
    logic [31:0] br_tval_q;
    assign trap_csr = LATE_BR_TRAP ? ((irq_take | exc_early) & ~debug_entry) : Trap;
    always_ff @(posedge clk)
        if (rst) br_trap_q <= 1'b0;
        else     br_trap_q <= LATE_BR_TRAP & Trap & ~trap_csr;   //Ловушка только из-за Taken
    always_ff @(posedge clk) begin
        br_epc_q  <= PC[31:2];
        br_tval_q <= PCTarget;
    end
    assign mret_do    = Mret & ~irq_take & ~debug_entry; //= Mret & ~Kill: других исключений у mret нет (короче путь)
    assign Redirect   = Trap | mret_do | debug_entry | resume_do;
    //Ч15: смена PC без ловушки невыровненного условного перехода - единственной части, которая ждёт
    //сравнения (Taken). Выполненный переход и так даёт PCSrcE = 1, а адрес (вектор ловушки) уже выбран
    //по кандидату (RedirectSel), поэтому для решения «менять ли PC» этой части не нужно
    assign RedirectEarly = ((irq_take | exc_early) & ~debug_entry) | mret_do | debug_entry | resume_do;
    assign RedirectSel = trap_sel | mret_do | debug_entry | resume_do;
    assign RedirectPC = resume_do ? {dpc, 2'b00} :
                        trap_sel  ? ((mtvec_mode & irq_take) ? {mtvec_base[31:7], irq_code, 2'b00} : {mtvec_base, 2'b00}) :
                        mret_do   ? {mepc, 2'b00} : PC;      //При входе в отладку PC не важен: он замораживается

    //#6 Чтение CSR. В режиме останова адрес CSR задаёт модуль отладки (конвейер пуст)
    logic [11:0] csr_addr;
    //Ч13: в конвейере в режиме останова стадия E пуста (CsrAddr = 0, csr_we = 0), а DM выставляет адрес
    //и запись только на время своей команды - поэтому ИЛИ вместо выбора по halted (halted - сигнал
    //с большим разветвлением, и выбор по нему стоял в пути чтения и записи CSR). В однотактном ядре
    //регистры стадий прозрачны: остановленная инструкция держит свой CsrAddr - там выбор по halted
    assign csr_addr = LATE_BR_TRAP ? (CsrAddr | DbgCsrAddr) : (halted ? DbgCsrAddr : CsrAddr);
    always_comb
        case (csr_addr)
            MSTATUS:         CsrRData = {19'd0, 2'b11, 3'd0, mstatus_mpie, 3'd0, mstatus_mie, 3'd0}; //MPP = 11 (M)
            MISA:            CsrRData = 32'h4000_0100 | (32'(M_EXT) << 12);                            //RV32I[M]
            MIE:             CsrRData = mie;
            MTVEC:           CsrRData = {mtvec_base, 1'b0, mtvec_mode};
            MSCRATCH:        CsrRData = mscratch;
            MEPC:            CsrRData = {mepc, 2'b00};
            MCAUSE:          CsrRData = {mcause_int, 26'd0, mcause_code};
            MTVAL:           CsrRData = mtval;
            MIP:             CsrRData = mip;
            MCYCLE,  CYCLE:  CsrRData = mcycle[31:0];
            MCYCLEH, CYCLEH: CsrRData = mcycle[63:32];
            //dcsr: xdebugver = 4, ebreakm, cause, step, prv = 3 (M); доступны только в режиме отладки
            DCSR:            CsrRData = halted ? {4'd4, 12'd0, dcsr_ebreakm, 6'd0, dcsr_cause, 3'd0, dcsr_step, 2'b11} : 32'd0;
            DPC:             CsrRData = halted ? {dpc, 2'b00} : 32'd0;
            default:         CsrRData = 32'd0;
        endcase

    //#7 Запись CSR. csrrs/csrrc с rs1 = x0 (Zimm = 0) только читают CSR
    logic        csr_we;
    logic [31:0] csr_src, csr_wdata;
    assign csr_src = Funct3[2] ? {27'd0, Zimm} : Rs1Data;
    //CSR-инструкция не обращается к памяти и не выполняет переход, поэтому гасит её только
    //прерывание: ~irq_take вместо ~Trap убирает из пути АЛУ и проверки выравнивания
    assign csr_we  = Csr & ~irq_take & ~debug_entry & ((Funct3[1:0] == 2'b01) | (Zimm != 5'd0));
    //Запись от модуля отладки - только в режиме останова, значение целиком
    logic        we_any;
    logic [31:0] wdata_any;
    assign we_any    = LATE_BR_TRAP ? (csr_we | DbgCsrWe)                 : (halted ? DbgCsrWe : csr_we);
    assign wdata_any = LATE_BR_TRAP ? (DbgCsrWe ? DbgWData : csr_wdata) : (halted ? DbgWData : csr_wdata);
    always_comb
        case (Funct3[1:0])
            2'b10:   csr_wdata = CsrRData |  csr_src;   //csrrs
            2'b11:   csr_wdata = CsrRData & ~csr_src;   //csrrc
            default: csr_wdata = csr_src;               //csrrw
        endcase

    //Запись CSR не зависит от решения о ловушке (Ч2): CSR-инструкция с ловушкой не совпадает -
    //прерывание исключено в csr_we, исключений у CSR-инструкций нет, а mret, ecall, ebreak и
    //переходы - не CSR-инструкции. Поэтому запись идёт первой, а ловушка, mret и вход в отладку
    //записываются следом и при совпадении имели бы приоритет.
    always_ff @(posedge clk)
        if (rst) begin
            mstatus_mie <= 1'b0; mstatus_mpie <= 1'b0;
            {mie_local, mie_meie, mie_mtie, mie_msie} <= '0;
            mtvec_base  <= '0;   mtvec_mode   <= 1'b0;
            mscratch    <= '0;   mepc         <= '0;   mtval <= '0;
            mcause_int  <= 1'b0; mcause_code  <= '0;
            mcycle      <= '0;
            dpc         <= '0;   dcsr_cause   <= '0;
            dcsr_ebreakm <= 1'b0; dcsr_step   <= 1'b0;
        end else begin
            mcycle <= mcycle + 64'd1;
            if (we_any)
                case (csr_addr)
                    MSTATUS:  begin mstatus_mie <= wdata_any[3]; mstatus_mpie <= wdata_any[7]; end
                    MIE:      {mie_local, mie_meie, mie_mtie, mie_msie} <= {wdata_any[31:16], wdata_any[11], wdata_any[7], wdata_any[3]};
                    MTVEC:    begin mtvec_base <= wdata_any[31:2]; mtvec_mode <= wdata_any[0]; end
                    MSCRATCH: mscratch <= wdata_any;
                    MEPC:     mepc     <= wdata_any[31:2];
                    MCAUSE:   begin mcause_int <= wdata_any[31]; mcause_code <= wdata_any[4:0]; end
                    MTVAL:    mtval    <= wdata_any;
                    MCYCLE:   mcycle[31:0]  <= wdata_any;
                    MCYCLEH:  mcycle[63:32] <= wdata_any;
                    DCSR:     if (halted) begin dcsr_ebreakm <= wdata_any[15]; dcsr_step <= wdata_any[2]; end
                    DPC:      if (halted) dpc <= wdata_any[31:2];
                    default: ;
                endcase
            if (debug_entry) begin
                dpc        <= PC[31:2];
                dcsr_cause <= debug_cause;
            end else if (trap_csr) begin
                mepc         <= PC[31:2];
                mcause_int   <= irq_take;
                mcause_code  <= irq_take ? irq_code : exc_code;
                mtval        <= irq_take ? 32'd0 : exc_tval;
                mstatus_mpie <= mstatus_mie;
                mstatus_mie  <= 1'b0;
            end else if (mret_do) begin
                mstatus_mie  <= mstatus_mpie;
                mstatus_mpie <= 1'b1;
            end
            if (br_trap_q) begin                 //Отложенная ловушка невыровненного перехода (конвейер)
                mepc         <= br_epc_q;
                mcause_int   <= 1'b0;
                mcause_code  <= 5'd0;            //Instruction address misaligned
                mtval        <= br_tval_q;
                mstatus_mpie <= mstatus_mie;
                mstatus_mie  <= 1'b0;
            end
        end

    //Состояние отладки: останов, шаг
    always_ff @(posedge clk)
        if (rst) begin
            halted <= 1'b0; step_active <= 1'b0; step_passed <= 1'b0;
        end else if (debug_entry) begin
            halted <= 1'b1; step_active <= 1'b0; step_passed <= 1'b0;
        end else if (resume_do) begin
            halted <= 1'b0; step_active <= dcsr_step; step_passed <= 1'b0;
        end else if (step_active & Valid & ~halted & ~Hold)
            step_passed <= 1'b1;             //Первая инструкция шага прошла стадию E (выполнена или вызвала ловушку)
endmodule

module conflict_prevention_unit 
  #(parameter bit CORE_TYPE = 0)
   (input  logic       RegWriteE, RegWriteM, RegWriteW,
    input  logic [4:0] RdM, RdW,
    input  logic [1:0] ALUSrcAD,           //Выбор операнда A АЛУ инструкции в D: 00 - rs1, 01 - PC, 10 - 0
    input  logic       ResultSrcM0,        //В стадии M загрузка (Ч3)
    input  logic       ValidD,             //Инструкция в D действительна (Ч9)
    output logic [3:0] FwdA, FwdB,         //Коды байпаса для стадии E, one-hot {M, W, X, рег. файл}
    output logic [4:0] SelA,               //Операнд A АЛУ для стадии E, one-hot {M, W, X, рег. файл, PC}
    //Организация пузырька
    input  logic       ResultSrcE0,
    input  logic [4:0] Rs1D, Rs2D, RdE,
    input  logic       Hold,               //Деление в стадии E не закончено (StallF и FlushE - в ядре)
    output logic       StallF, StallD, FlushE,
    //Предсказание перехода branch
    input  logic       PCSrcE,
    input  logic       PredD,              //Переход выполнен в стадии D (BTFN)
    output logic       FlushD
);
    //#1 Байпасирование (Ч7: выбор источника считается заранее, в стадии D)
    //Номера RdE, RdM, RdW, которые видит инструкция в D, - это номера, которые в следующем такте,
    //когда она будет в стадии E, окажутся в стадиях M, W, X. Поэтому сравнение делается в D, а в E
    //приходит готовый one-hot-код: в пути операндов АЛУ остаётся только мультиплексор И-ИЛИ.
    //  - RegWriteE берётся без учёта гашения: если инструкцию в E погасят (ловушка, неверный путь,
    //    вход в отладку), следующая за ней тоже будет погашена, и её код байпаса не понадобится;
    //  - загрузку из W не пересылают: если инструкция в D зависит от загрузки в E или M,
    //    lwStall её задержит, а в стадию E в этом такте уйдёт пузырь.
    //Более молодая стадия важнее: M > W > X > регистровый файл.
    generate if (CORE_TYPE) begin   //#1 - Однотактное ядро: байпаса нет
        assign FwdA = 4'b0001;
        assign FwdB = 4'b0001;
        assign SelA = 5'b00000;
    end else begin                  //#0 - Конвеерное ядро
        //Все сигналы - аргументами функции: у непрерывного присваивания чувствительность только
        //к операндам выражения, сигналы модуля внутри функции её не вызывают
        function automatic logic [3:0] fwd(input logic [4:0] rs, re, rm, rw, input logic we, wm, ww);
            if      ((rs != 0) & (rs == re) & we) return 4'b1000;   //будет в M
            else if ((rs != 0) & (rs == rm) & wm) return 4'b0100;   //будет в W
            else if ((rs != 0) & (rs == rw) & ww) return 4'b0010;   //будет в X
            else                                  return 4'b0001;   //регистровый файл
        endfunction
        assign FwdA = fwd(Rs1D, RdE, RdM, RdW, RegWriteE, RegWriteM, RegWriteW);
        assign FwdB = fwd(Rs2D, RdE, RdM, RdW, RegWriteE, RegWriteM, RegWriteW);
        //Операнд A АЛУ: rs1 с байпасом, PC (auipc, jal) или 0 (lui) - один мультиплексор вместо двух
        assign SelA = (ALUSrcAD == 2'b01) ? 5'b00001 :
                      (ALUSrcAD == 2'b10) ? 5'b00000 : {FwdA, 1'b0};
    end
    endgenerate

    //#2 Организация пузырька при инструкции lw
    logic lwStall;
    generate if (CORE_TYPE) begin   //#1 - Однотактное ядро
        assign lwStall = 1'b0;
    end else begin                  //#0 - Конвеерное ядро
        //Ч3: данные загрузки доступны только из стадии X. Инструкция в D ждёт, пока загрузка,
        //от которой она зависит, стоит в стадии E или M (сразу за загрузкой - 2 такта, через одну - 1)
        assign lwStall = ValidD & ((ResultSrcE0 & ((Rs1D == RdE) | (Rs2D == RdE))) |
                                   (ResultSrcM0 & RegWriteM & ((Rs1D == RdM) | (Rs2D == RdM))));
    end
    endgenerate

    //Смена PC (ловушка на lw в стадии E) отменяет приостановку PC, чтобы он принял новый адрес.
    //Регистры стадии D и выход BSRAM при этом сбрасываются FlushD (сброс важнее приостановки),
    //поэтому StallD остаётся коротким путём: от него зависит вход CE блоков памяти инструкций
    assign StallF = lwStall & ~PCSrcE;
    //Деление держит и стадию D. В однотактном ядре регистров стадий нет, достаточно стоящего PC, а StallD
    //запретил бы чтение BSRAM в середине такта - и память не выдала бы инструкцию по новому PC
    assign StallD = lwStall | (CORE_TYPE ? 1'b0 : Hold);

    //#3 Предсказатель перехода branch
    generate if (CORE_TYPE) begin   //#1 - Однотактное ядро
        assign FlushD = 1'b0;
        assign FlushE = lwStall;
    end else begin                  //#0 - Конвеерное ядро
        assign FlushD = PCSrcE | (PredD & ~StallD);   //Переход из D сбрасывает только выбранную следом инструкцию
        assign FlushE = lwStall | PCSrcE;
    end
    endgenerate

endmodule

module fetch (
    input  logic        clk, rst, PCSrc, StallF,
    input  logic [31:0] PCTarget,
    input  logic        PredD,                //Переход, выполняемый в стадии D (BTFN)
    input  logic [31:0] PCTargetD,
    output logic [31:0] PC, PCPlus4, Instr,

    //Интерфейс памяти инструкций
    input  logic [31:0] imem_data,
    output logic        imem_re, imem_rst,
    output logic [31:0] imem_addr,

    //Предсказание перехода branch
    input logic         StallD, FlushD
);
    //#pc - Счётчик команд//
    //DESCRIPTION: Счётчик команд PC на каждом такте принимает значение
    //PCNext, значение на который попадает с мультиплесора с сигналом выбора PCSrc.
    //PCNext может принимать значение PCPlus4(приращение текущего значения PC на 4ед.)
    //или значение внешнего источника смещения PCTarget(приращение текущего значения PC
    //на значение расширенного знаком непосредственного операнда ImmExt).
    
    logic en;
    assign en = ~StallF; //Разрешение на включение(Запрет создаётся при конфликтах в конвейере)

    logic [31:0] PCNext;
    assign PCPlus4 = PC + 4;
    assign PCNext = PCSrc ? PCTarget :      //Смена PC из стадии E (переход, ошибка предсказания, ловушка) важнее
                    PredD ? PCTargetD : PCPlus4;
    
    always_ff @(posedge clk, posedge rst)
        if (rst)        PC <= 0;
        else  if (en)   PC <= PCNext;
    
    //#imem - Память команд//
    //DESCRIPTION: По входному адресу счётчика команд PC из памяти команд
    //извлекается инструкция Instr. Выведен внешний интерфейс для подключения
    //памяти на шины imem_addr и imem_data.
    assign Instr = imem_data;
    assign imem_addr = PC[31:0];
    assign imem_re = ~StallD;
    assign imem_rst = 1'b0;   //Ч9: выход памяти инструкций не сбрасывается - сброшенную инструкцию помечает ValidD = 0
endmodule

module decode 
  #(parameter bit CORE_TYPE = 0)
   (input logic         clk, rst, RegWrite,
    input logic  [ 2:0] ImmSrc,
    input logic  [ 4:0] Addr1, Addr2, Addr3,
    input logic  [31:7] Imm,
    input  logic [31:0] Result,
    output logic [31:0] RD1, RD2, ImmExt,
    //Доступ модуля отладки (ядро остановлено, стадия W пуста): через порты чтения 1 и записи
    input  logic        DbgSel,           //Ядро остановлено: порт чтения 1 отдан отладчику
    input  logic [ 4:0] DbgAddr,
    input  logic        DbgWe,
    input  logic [31:0] DbgWData,
    output logic [31:0] DbgRData
);
    //#rf - Регистровый файл//
    //DESCRIPTION: Трёхпортовый регистровый файл имеет два порта для считывания
    //и один порт для загрузки данных по сигналу разрешения RegWrite.
    //Регистры не сбрасываются: так синтезатор кладёт файл в распределённую память SSRAM
    //(асинхронное чтение) вместо 1024 триггеров с мультиплексорами 32:1 на каждый порт чтения.
    //Спецификация RISC-V начальных значений x1..x31 не требует, стартовый код задаёт sp и gp сам.
    (* syn_ramstyle = "distributed_ram" *) logic [31:0] rf[31:0];
    // synthesis translate_off
    //Моделирование: нули; +rf_garbage - мусор, как на плате после включения (проверка, что программа
    //не рассчитывает на нулевые регистры)
    initial for (int i = 0; i < 32; i++) rf[i] = $test$plusargs("rf_garbage") ? 32'hDEAD_0000 | i : 32'd0;
    // synthesis translate_on
    //Отладчик пользуется портами ядра, а не своими: отдельные порты на регистровом файле из
    //триггеров стоят мультиплексор на каждый бит (запись) и ещё один выбор 32:1 (чтение)
    logic [ 4:0] ra1, wa;
    logic [31:0] wd;
    logic        we;
    assign ra1 = DbgSel ? DbgAddr  : Addr1;
    assign wa  = DbgWe  ? DbgAddr  : Addr3;
    assign wd  = DbgWe  ? DbgWData : Result;
    assign we  = DbgWe | RegWrite;
    
    generate if (CORE_TYPE) begin   //Однотактное ядро
        always_ff @(posedge clk)
            if (we) rf[wa] <= wd;
        assign RD1 = (ra1 != 0) ? rf[ra1] : 0;
        assign RD2 = (Addr2 != 0) ? rf[Addr2] : 0;
    end else begin                  //Конвеерное ядро
        //Ч6: запись по фронту (раньше - по спаду, «запись в первой половине такта, чтение во
        //второй»). По спаду пути «память данных -> регистровый файл» доставалась только половина
        //периода, и он ограничивал частоту. Теперь запись получает полный такт, а инструкция в
        //стадии D, читающая регистр, который стадия W пишет в этом же такте, берёт значение с
        //порта записи (байпас W -> D).
        always_ff @(posedge clk)
            if (we) rf[wa] <= wd;

        logic byp1, byp2;
        //Ч11: сравнение - по полю инструкции (Addr1), а не по адресу после выбора «отладчик / ядро»:
        //в режиме останова DM не читает и не пишет регистр в одном такте, а стадия X пуста
        assign byp1 = we & (wa == Addr1);
        assign byp2 = we & (wa == Addr2);
        assign RD1 = (ra1   == 0) ? 32'd0 : byp1 ? wd : rf[ra1];
        assign RD2 = (Addr2 == 0) ? 32'd0 : byp2 ? wd : rf[Addr2];
        //always_ff @(posedge clk) begin
        //    RD1 <= (Addr1 != 0) ? rf[Addr1] : 0;
        //    RD2 <= (Addr2 != 0) ? rf[Addr2] : 0;
        //end
    end
    endgenerate
    assign DbgRData = RD1;

    //#ie - Знаковое расширение непосредственного числа//
    //DESCRIPTION: Производится знаковое расширение непосредственного числа
    //в зависимости от типа регистра ImmSrc. Знаковый бит Imm[31] копируется
    //в старшие разряды непосредственного значения.

    always_comb
        case (ImmSrc)
            3'b000:   ImmExt = {{20{Imm[31]}},Imm[31:20]};                         //тип I
            3'b001:   ImmExt = {{20{Imm[31]}},Imm[31:25],Imm[11:7]};               //тип S
            3'b010:   ImmExt = {{20{Imm[31]}},Imm[7],Imm[30:25],Imm[11:8],1'b0};   //тип B
            3'b011:   ImmExt = {{12{Imm[31]}},Imm[19:12],Imm[20],Imm[30:21],1'b0}; //тип J
            3'b100:   ImmExt = {Imm[31:12],{12{1'b0}}};                            //тип U
            default:  ImmExt = 32'd0;
        endcase

endmodule

module execute
  #(parameter bit CORE_TYPE = 0)
   (input  logic        JALSrc,
    input  logic [ 3:0] FwdA, FwdB,       //Байпас rs1/rs2, one-hot {M, W, X, рег. файл} (Ч7)
    input  logic [ 4:0] SelA,             //Операнд A АЛУ, one-hot {M, W, X, рег. файл, PC}
    input  logic [ 2:0] ALUSrc, 
    input  logic [ 3:0] ALUControl,
    input  logic [31:0] RD1, RD2, PC, ImmExt, ResultW, ALUResultM, ResultX,
    output logic [ 2:0] BrFlags, //Сравнение для переходов: {eq, lt, ltu} (Ч5)
    output logic [31:0] ALUResult, WriteData,
    //Особенные
    output logic [31:0] PCTarget,
    output logic [31:0] SrcA,      //Значение rs1 с учётом байпаса (операнд CSR-инструкций)
    output logic [31:0] AddrSum    //Выход сумматора АЛУ: адрес загрузки/записи для mtval (Ч8)
);

    //#alu - Арифметикологическое устройство (АЛУ)//
    //DESCRIPTION: В зависимости от сигнала управления ALUControl происходит
    //соответствующая операция. На входы srcA и srcB поступают входные
    //операнды, результат записывается в ALUResult. Условия переходов АЛУ не вычисляет -
    //для них есть отдельная схема сравнения (#2.1).
    //На вход srcB может поступать как второй операнд регистрового файла RD2,
    //так и расширенное знаком непосредственное значение ImmExt в зависимости
    //от сигнала управления ALUSrc
    
    //#1 Мультиплексоры байпасирования конвейерного ядра на входе операндов АЛУ
    logic [31:0] SrcAforward, SrcBforward;
    //logic [31:0] Aabc [2:0] = {ALUResultM, ResultW, RD1};//{RD1, ResultW, ALUResultM};
    //logic [31:0] Babc [2:0] = {ALUResultM, ResultW, RD2};//{RD2, ResultW, ALUResultM};
    //assign SrcAforward = Aabc[ForwardA];
    //assign SrcBforward = Babc[ForwardB];
    
    generate if (CORE_TYPE) begin   //#1 - Однотактное ядро
        assign SrcAforward = RD1;
        assign SrcBforward = RD2;        
    end else begin                  //#0 - Конвеерное ядро
        //Ч7: коды готовы с прошлого такта - только И-ИЛИ, без сравнений номеров регистров
        assign SrcAforward = ({32{FwdA[3]}} & ALUResultM) | ({32{FwdA[2]}} & ResultW) |
                             ({32{FwdA[1]}} & ResultX)    | ({32{FwdA[0]}} & RD1);
        assign SrcBforward = ({32{FwdB[3]}} & ALUResultM) | ({32{FwdB[2]}} & ResultW) |
                             ({32{FwdB[1]}} & ResultX)    | ({32{FwdB[0]}} & RD2);
    end
    endgenerate

    //#2 АЛУ
    logic        ALUSrcB;
    logic [ 1:0] ALUSrcA;
    logic [31:0] srcA, srcB;

    assign {ALUSrcA, ALUSrcB} = ALUSrc;
    generate if (CORE_TYPE) begin   //#1 - Однотактное ядро
        always_comb
            case (ALUSrcA)
                2'b01: srcA = PC;
                2'b10: srcA = 32'd0;
              default: srcA = SrcAforward;
            endcase
    end else begin                  //#0 - Конвеерное ядро: байпас и выбор PC/0 одним мультиплексором (Ч7)
        assign srcA = ({32{SelA[4]}} & ALUResultM) | ({32{SelA[3]}} & ResultW) | ({32{SelA[2]}} & ResultX) |
                      ({32{SelA[1]}} & RD1)        | ({32{SelA[0]}} & PC);
    end
    endgenerate
    assign srcB = (ALUSrcB) ? ImmExt : SrcBforward; //Мультипелксор для выбора второго операнда АЛУ: RD2 или ImmExt
    
    wire        v;             //переполнение (для SLT)
    logic        cout;          //переполнение сумматора
    logic        isAddSub;      //1 - сложение/вычитание; 0 - прочие команды 
    logic [31:0] condinvb, sum;

    assign condinvb = ALUControl[0] ? ~srcB : srcB;
    assign {cout, sum} = srcA + condinvb + ALUControl[0];
    assign isAddSub = ~ALUControl[3] & ~ALUControl[2] & ~ALUControl[1] |
                      ~ALUControl[3] & ~ALUControl[1] &  ALUControl[0];

    always_comb
        case (ALUControl)
            4'b0000: ALUResult = sum;                           //ADD
            4'b0001: ALUResult = sum;                           //SUB
            4'b0010: ALUResult = srcA & srcB;                   //AND
            4'b0011: ALUResult = srcA | srcB;                   //OR
            4'b0100: ALUResult = srcA ^ srcB;                   //XOR
            4'b0101: ALUResult = {31'd0, sum[31] ^ v};          //SLT
            4'b0110: ALUResult = srcA << srcB[4:0];             //SLL
            4'b0111: ALUResult = srcA >> srcB[4:0];             //SRL
            4'b1000: ALUResult = $signed(srcA) >>> srcB[4:0];   //SRA
            4'b1001: ALUResult = {31'd0, ~cout};                //SLTU
            default: ALUResult = 32'dx;
        endcase

    assign v = ~(ALUControl[0] ^ srcA[31] ^ srcB[31]) & (srcA[31] ^ sum[31]) & isAddSub;   //Переполнение для SLT

    //#2.1 Сравнение для условных переходов (Ч5). Раньше переход проверял флаги АЛУ: флаг нуля
    //сворачивался из всех 32 бит результата АЛУ после выбора операции, то есть переход ждал
    //сумматор, мультиплексор операции и свёртку. Отдельная схема сравнивает операнды сразу
    //после байпаса: равенство - без цепочки переноса, «меньше» - один 33-битный вычитатель.
    logic        br_eq, br_lt, br_ltu;
    logic [32:0] br_diff;
    assign br_eq   = (SrcAforward == SrcBforward);
    assign br_diff = {1'b0, SrcAforward} - {1'b0, SrcBforward};
    assign br_ltu  = br_diff[32];                                                  //Заём: a < b без знака
    assign br_lt   = (SrcAforward[31] ^ SrcBforward[31]) ? SrcAforward[31] : br_diff[31];
    assign BrFlags = {br_eq, br_lt, br_ltu};

    //#3 Сумматор для инструкций JAL/JALR с мультиплексором по первому операнду. Мультиплесора подаёт на один из входов
    //сумматора текущее счётчика инструкций PC или значение со входа SrcAforward основного АЛУ(учтено байпасирование для конвейерного
    //процессора) в зависимости от сигнала управления JALSrc. На второй вход сумматора подаётся расширенное значение
    //непосредственного числа ImmExt.
    logic [31:0] JALOp;
    assign JALOp = (JALSrc) ? SrcAforward : PC;
    assign PCTarget = (JALOp + ImmExt) & ~32'd1; //Младший бит адреса перехода обнуляется (спецификация JALR)

    //#4 Транслирование сигналов и прочие связи
    assign WriteData = SrcBforward;
    assign SrcA      = SrcAforward;
    assign AddrSum   = sum;        //У загрузок и записей операция АЛУ - сложение: sum = адрес

endmodule

module memory (
    input logic         MemWrite,
    input logic  [ 2:0] Funct3,
    input logic  [31:0] ALUResult, WriteData,
    output logic [31:0] ReadData,
    //Интерфейс памяти данных
    input logic  [31:0] dmem_ReadData,
    output logic [ 3:0] dmem_Write,
    output logic [31:0] dmem_Addr, dmem_WriteData
);
    
    logic [1:0] MemWordSize;
    assign MemWordSize = Funct3[1:0];

    logic [ 3:0] DataWrite;

    always_comb 
        case (MemWordSize)
            2'b00:      begin //1 байт
                            dmem_WriteData = WriteData[7:0] << {ALUResult[1:0], 3'b000}; // {4{WriteData[7:0]}};
                            DataWrite      = 4'b0001 << ALUResult[1:0];
                        end
            2'b01:      begin //2 байта
                            dmem_WriteData = {2{WriteData[15:0]}}; //WriteData[15:0] << {ALUResult[1], {4{1'b0}};
                            DataWrite      = ALUResult[1] ? 4'b1100: 4'b0011; //4'b0011 << {ALUResult[1], 1'b0};
                        end
            default:    begin //4 байта
                            dmem_WriteData = WriteData;
                            DataWrite      = 4'b1111;
                        end
        endcase

    
    assign ReadData   = dmem_ReadData;
    assign dmem_Write = MemWrite ? DataWrite : 4'b0000;
    assign dmem_Addr  = ALUResult;

    //#dmem - Память данных//
    //DESCRIPTION: Память типа RAM доступна для чтения/записи. Имеет один вход
    //адреса dmem_Addr, выход считанных данных dmem_ReadData, а также вход записи
    //данных dmem_WriteData по сигналу разрешения записи dmem_Write. Выведен внешний
    //интерфейс для подключенияп памяти.

endmodule

module writeback (
    input  logic [ 1:0] ResultSrc,
    input  logic [ 2:0] Funct3,
    input  logic [31:0] ALUResult, ReadData, PCPlus4,
    //Особенные
    output logic [31:0] Result
);
    
    logic       Unsigned;
    logic [1:0] MemWordSize;
    assign {Unsigned, MemWordSize} = Funct3;

    logic [31:0] ShData;
    logic [31:0] ShDataExt;

    ///Вариант описания №1(Из picoRV)
    /*
    //#1 Блок сдвига
    always_comb 
        case (MemWordSize)
            2'b00:      begin //1 байт
                            case (ALUResult[1:0])
                                2'b00: ShData = {24'd0, ReadData[ 7: 0]};
                                2'b01: ShData = {24'd0, ReadData[15: 8]};
                                2'b10: ShData = {24'd0, ReadData[23:16]};
                                2'b11: ShData = {24'd0, ReadData[31:24]};
                            endcase
                        end
            2'b01:      begin //2 байта
                            case (ALUResult[1])
                                1'b0: ShData = {16'd0, ReadData[15: 0]};
                                1'b1: ShData = {16'd0, ReadData[31:16]};
                            endcase
                        end
            default:    begin //4 байта
                            ShData       = ReadData;
                        end
        endcase
    
    //#2 Расширение знаком
    always_comb 
        case (MemWordSize)
            2'b00:  ShDataExt = Unsigned ? ShData : {{24{ShData[7]}},ShData[7:0]};     //1 байт
            2'b01:  ShDataExt = Unsigned ? ShData : {{16{ShData[15]}},ShData[15:0]};   //2 байта
            default:ShDataExt = ShData;                                                //4 байта
        endcase
    */

    ///Вариант описания №2 (Занимает меньше ячеек)
    //#1 Блок сдвига
    wire [4:0] shift;
    assign shift = MemWordSize[0] ? {ALUResult[1],   4'b0000} : {ALUResult[1:0], 3'b000 };
    assign ShData = (MemWordSize[1]) ? ReadData : ReadData >> shift;
    //assign ShData = ReadData >> {ALUResult[1] & ~MemWordSize[1], ALUResult[0] & ~|MemWordSize, 3'b000}; //Занимает на 100 больше ячеек
    
    //#2 Расширение знаком
    always_comb 
        case (MemWordSize)
            2'b00:  ShDataExt = {Unsigned ? 24'd0 : {24{ShData[7]}}, ShData[7:0]};    //1 байт
            2'b01:  ShDataExt = {Unsigned ? 16'd0 : {16{ShData[15]}},ShData[15:0]};   //2 байта
            default:ShDataExt = ShData;                                               //4 байта
        endcase
    

    //#2 Мультиплексор для выбора данных на запись в рег. файл:
    always_comb 
        case (ResultSrc)
            2'b00:   Result = ALUResult;      //Результат вычисления АЛУ                         
            2'b01:   Result = ShDataExt; //Результат выгрузки из памяти данных
            2'b10:   Result = PCPlus4;        //Значение текущего значения счётчика с приращением +4
            default: Result = 0;
        endcase

endmodule

module regdata
          #(parameter int QUANTITY = 2, //Количество регистров без регистра выхода памяти
            parameter bit CORE_TYPE = 0)
          (input  logic                      clk, rst, en,
           input  logic [QUANTITY-1:0][31:0] d, //Упакованный массив: {A, B} даёт d[1]=A, d[0]=B (поддерживается Icarus Verilog)
           output logic [QUANTITY-1:0][31:0] q);

    genvar i;

    generate if (CORE_TYPE) begin   //#1 - Однотактное ядро
        assign q = d;
    end else begin                  //#0 - Конвеерное ядро
        for(i=0; i<QUANTITY; i=i+1) begin : regdataloop
            always_ff @(posedge clk)
                if (rst)      q[i] <= 0;
                else if (~en) q[i] <= d[i];
        end
    end
    endgenerate

endmodule

module regrf
          #(parameter int QUANTITY = 2, //Количество адресных регистров регистрового файла
            parameter bit CORE_TYPE = 0)
          (input  logic                     clk, rst, en,
           input  logic [QUANTITY-1:0][4:0] d, //Упакованный массив: {A, B} даёт d[1]=A, d[0]=B (поддерживается Icarus Verilog)
           output logic [QUANTITY-1:0][4:0] q);

    genvar i;

    generate if (CORE_TYPE) begin   //#1 - Однотактное ядро
        assign q = d;
    end else begin                  //#0 - Конвеерное ядро
        for(i=0; i<QUANTITY; i=i+1) begin : regdataloop
            always_ff @(posedge clk)
                if (rst)      q[i] <= 0;
                else if (~en) q[i] <= d[i];
        end
    end
    endgenerate

endmodule

module regmem #(parameter bit CORE_TYPE = 0, //Количество регистров без регистра выхода памяти
                parameter bit MEMORY_TYPE = 0)
               (input  logic        clk, rst, en,
                input  logic [31:0] dm,
                output logic [31:0] qm);
    
    //При использовании памяти BSRAM в конвеерном ядре межстадийным регистром
    //является сама память поскольку она явлется синхронной и выдаёт данные на выход по такту.
    //При использовании синтезированной памяти в конвеерном ядре нужен дополнительный межстадийный
    //регистр поскольку память асинхронная и необходимо разделить стадии регистрами.

    generate if (MEMORY_TYPE | CORE_TYPE) begin    //#1 - Провод для прочих конфигураций
        assign qm = dm;
    end else begin                                 //#0 - Регистр для конвеерного ядра с синтезированной памятью
        always_ff @(posedge clk)
            if (rst)      qm <= 0;
            else if (~en) qm <= dm;
    end
    endgenerate

endmodule

module regcontrol
          #(parameter int WIDTH = 2,
            parameter bit CORE_TYPE = 0)
          (input  logic             clk, rst, en,
           input  logic [WIDTH-1:0] d,
           output logic [WIDTH-1:0] q);

    generate if (CORE_TYPE) begin   //#1 - Однотактное ядро
        assign q = d;
    end else begin                  //#0 - Конвеерное ядро
        always_ff @(posedge clk)
            if (rst)      q <= 0;
            else if (~en) q <= d;
    end
    endgenerate

endmodule