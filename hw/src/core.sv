module core #(parameter bit CORE_TYPE = 1, //       Тип процессора: 1 - Однотактный; 0 - Конвейерный;
              parameter bit IMEM_TYPE = 0, //Тип памяти инструкций: 1 - BSRAM;       0 - Синтезированная;
              parameter bit DMEM_TYPE = 0) //    Тип памяти данных: 1 - BSRAM;       0 - Синтезированная;
             (input  logic        clk,       //Вход тактирования
              input  logic        rst,       //Вход сброса (кнопка S2)
              //Интерфейс памяти команд
              input  logic [31:0] imem_data,
              output logic        imem_re, imem_rst,
              output logic [31:0] imem_addr,
              //Интерфейс памяти данных
              input  logic [31:0] dmem_ReadData,
              output logic [ 3:0] dmem_Write,
              output logic [31:0] dmem_Addr, dmem_WriteData
);
    
    //Сигналы тракта данных
    logic [4: 0] RdD, Rs1D, Rs2D;
    logic [4: 0] RdE, Rs1E, Rs2E;
    logic [4: 0] RdM;
    logic [4: 0] RdW;

    logic [24:0] ImmD;

    logic [31:0] PCPlus4F, PCF, InstrF;
    logic [31:0] PCPlus4D, PCD, InstrD, ImmExtD, RD1D, RD2D;
    logic [31:0] PCPlus4E, PCE,         ImmExtE, RD1E, RD2E, WriteDataE, ALUResultE, PCTargetE;
    logic [31:0] PCPlus4M,                                   WriteDataM, ALUResultM, ReadDataM;
    logic [31:0] PCPlus4W,                                               ALUResultW, ReadDataW, ResultW; 

    logic        funct7b5;
    logic [2: 0] funct3;
    logic [6: 0] op;

    //Сигналы блока управления
    logic RegWriteD, MemWriteD, JumpD, BranchD, JALSrcD;                 logic [1:0] ResultSrcD; logic [2:0] Funct3D, ALUSrcD, ImmSrcD; logic [3:0] ALUControlD;
    logic RegWriteE, MemWriteE, JumpE, BranchE, JALSrcE, PCSrcE, TakenE; logic [1:0] ResultSrcE; logic [2:0] Funct3E, ALUSrcE;          logic [3:0] ALUControlE;
    logic RegWriteM, MemWriteM;                                          logic [1:0] ResultSrcM; logic [2:0] Funct3M;
    logic RegWriteW;                                                     logic [1:0] ResultSrcW; logic [2:0] Funct3W;

    //Сигналы блока предотвращения конфликтов
    logic [1:0] ForwardAE, ForwardBE;                   //Организация байпасирования
    logic       StallF, StallD, FlushD, FlushE;         //Организация приостановки и предсказателя branch

    //Сигналы блока условных переходов
    logic [3:0] FlagsE;

    //CONTROL UNIT//////////////////////////////////////////////////////////////////////////////////
    assign funct7b5 = InstrD[30];
    assign funct3   = InstrD[14:12]; //FIXME: Объединить с Funct3D!
    assign op       = InstrD[6:0];
    control_unit cu (  .op(op), .funct3(funct3), .funct7b5(funct7b5),
                       .RegWrite(RegWriteD), .MemWrite(MemWriteD), .Jump(JumpD), .Branch(BranchD), .JALSrc(JALSrcD),
                       .ResultSrc(ResultSrcD), .ImmSrc(ImmSrcD), .ALUSrc(ALUSrcD), .ALUControl(ALUControlD));
    conflict_prevention_unit #(CORE_TYPE) pu
                              (.RegWriteM(RegWriteM), .RegWriteW(RegWriteW),                                 
                               .Rs1E(Rs1E), .Rs2E(Rs2E), .RdM(RdM), .RdW(RdW),
                               .ForwardA(ForwardAE), .ForwardB(ForwardBE),
                               //Организация пузырька
                               .ResultSrcE0(ResultSrcE[0]), .Rs1D(Rs1D), .Rs2D(Rs2D), .RdE(RdE),
                               .StallF(StallF), .StallD(StallD), .FlushE(FlushE),
                                //Предсказание перехода branch
                               .PCSrcE(PCSrcE), .FlushD(FlushD));
    //FETCH/////////////////////////////////////////////////////////////////////////////////////////
    fetch fetch(    .clk(clk), .rst(rst), .PCSrc(PCSrcE), .StallF(StallF),
                    .PCTarget(PCTargetE),    
                    .PC(PCF), .PCPlus4(PCPlus4F), .Instr(InstrF),
                    //Интерфейс памяти инструкций
                    .imem_data(imem_data),
                    .imem_re(imem_re), .imem_rst(imem_rst), .imem_addr(imem_addr),
                    //Предсказание перехода branch
                    .StallD(StallD), .FlushD(FlushD));
    ////////////////////////////////////////////////////////////////////////////////////////////////
    regmem  #(CORE_TYPE, IMEM_TYPE) rm_fetch (clk, FlushD|rst, StallD, InstrF, InstrD);
    regdata #(2, CORE_TYPE)         rd_fetch (clk, FlushD|rst, StallD, {PCF, PCPlus4F},
                                                                       {PCD, PCPlus4D});
    //DECODE////////////////////////////////////////////////////////////////////////////////////////
    decode #(CORE_TYPE) decode(  .clk(clk), .rst(rst), .RegWrite(RegWriteW), .ImmSrc(ImmSrcD),
                                 .Addr1(Rs1D), .Addr2(Rs2D), .Addr3(RdW), .Imm(ImmD),
                                 .Result(ResultW),
                                 .RD1(RD1D), .RD2(RD2D), .ImmExt(ImmExtD));
    assign Rs1D    = InstrD[19:15];
    assign Rs2D    = InstrD[24:20];
    assign RdD     = InstrD[11:7];
    assign ImmD    = InstrD[31:7];
    assign Funct3D = InstrD[14:12];
    ////////////////////////////////////////////////////////////////////////////////////////////////
    regdata #(5, CORE_TYPE) rd_decode     (clk, FlushE|rst, 1'b0, {PCD, PCPlus4D, ImmExtD, RD1D, RD2D},
                                                                  {PCE, PCPlus4E, ImmExtE, RD1E, RD2E});
    regrf   #(3, CORE_TYPE) rf_decode     (clk, FlushE|rst, 1'b0, {Rs1D, Rs2D, RdD},
                                                                  {Rs1E, Rs2E, RdE});
    regcontrol #(17, CORE_TYPE) rc_decode (clk, FlushE|rst, 1'b0, 
                    {RegWriteD, ResultSrcD[1:0], MemWriteD, JumpD, BranchD, ALUControlD[3:0], ALUSrcD[2:0], Funct3D[2:0], JALSrcD}, 
                    {RegWriteE, ResultSrcE[1:0], MemWriteE, JumpE, BranchE, ALUControlE[3:0], ALUSrcE[2:0], Funct3E[2:0], JALSrcE});
    //EXECUTE///////////////////////////////////////////////////////////////////////////////////////
    execute #(CORE_TYPE) execute
             (.JALSrc(JALSrcE), .ForwardA(ForwardAE), .ForwardB(ForwardBE), .ALUSrc(ALUSrcE), .ALUControl(ALUControlE),
              .RD1(RD1E), .RD2(RD2E), .PC(PCE), .ImmExt(ImmExtE), .ResultW(ResultW), .ALUResultM(ALUResultM),
              .Flags(FlagsE), .ALUResult(ALUResultE), .WriteData(WriteDataE),
              //Особенные
              .PCTarget(PCTargetE));
    branch_unit bu (.Branch(BranchE), .funct3(Funct3E), .Flags(FlagsE), .taken(TakenE));
    ////Логика JUMP/BRANCH
    assign PCSrcE = TakenE | JumpE;
    ////////////////////////////////////////////////////////////////////////////////////////////////
    regdata    #(3, CORE_TYPE) rd_execute (clk, rst, 1'b0, {PCPlus4E, WriteDataE, ALUResultE},
                                                           {PCPlus4M, WriteDataM, ALUResultM});
    regrf      #(1, CORE_TYPE) rf_execute (clk, rst, 1'b0, {RdE},
                                                           {RdM});
    regcontrol #(7, CORE_TYPE) rc_execute (clk, rst, 1'b0, {RegWriteE, ResultSrcE[1:0], MemWriteE, Funct3E[2:0]}, 
                                                           {RegWriteM, ResultSrcM[1:0], MemWriteM, Funct3M[2:0]});
    //MEMORY////////////////////////////////////////////////////////////////////////////////////////
    memory memory ( .MemWrite(MemWriteM), .Funct3(Funct3M),
                    .ALUResult(ALUResultM), .WriteData(WriteDataM),
                    .ReadData(ReadDataM),
                    //Интерфейс памяти данных
                    .dmem_ReadData(dmem_ReadData),
                    .dmem_Write(dmem_Write), .dmem_Addr(dmem_Addr),
                    .dmem_WriteData(dmem_WriteData));
    ////////////////////////////////////////////////////////////////////////////////////////////////
    regmem     #(CORE_TYPE, DMEM_TYPE) rm_memory (clk, rst, 1'b0, ReadDataM, ReadDataW);
    regdata    #(2, CORE_TYPE)         rd_memory (clk, rst, 1'b0, {PCPlus4M, ALUResultM},
                                                                  {PCPlus4W, ALUResultW});
    regrf      #(1, CORE_TYPE)         rf_memory (clk, rst, 1'b0, {RdM},
                                                                  {RdW});
    regcontrol #(6, CORE_TYPE)         rc_memory (clk, rst, 1'b0, {RegWriteM, ResultSrcM[1:0], Funct3M[2:0]}, 
                                                                  {RegWriteW, ResultSrcW[1:0], Funct3W[2:0]});
    //WRITEBACK/////////////////////////////////////////////////////////////////////////////////////
    writeback writeback (   .ResultSrc(ResultSrcW), .Funct3(Funct3W),
                            .ALUResult(ALUResultW), .ReadData(ReadDataW), .PCPlus4(PCPlus4W),
                            //Особенные
                            .Result(ResultW));
    ////////////////////////////////////////////////////////////////////////////////////////////////

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
module control_unit (
    input logic [6:0]   op,
    input logic [2:0]   funct3,
    input logic         funct7b5,
    
    output logic        RegWrite, MemWrite, Jump, Branch, JALSrc,
    output logic [1:0]  ResultSrc,
    output logic [2:0]  ImmSrc, ALUSrc,
    output logic [3:0]  ALUControl
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
            default:    controls = 15'bx_xxx_xxx_x_xx_x_xx_x_x; //Другие команды
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

endmodule

module branch_unit (
    input  logic       Branch,
    input  logic [2:0] funct3,
    input  logic [3:0] Flags,
    output logic       taken
);

    logic v, c, n, z;               //флаги: overflow, carry out, negative, zero
    logic cond;                     //1 - улсовие перехода выполнено
    assign {v,c,n,z} = Flags;
    assign taken = cond & Branch;

    always_comb
        case (funct3)
            3'b000: cond = z;       //beq
            3'b001: cond = ~z;      //bne
            3'b100: cond = n ^ v;   //blt
            3'b101: cond = ~(n ^ v);//bge
            3'b110: cond = ~c;      //bltu
            3'b111: cond = c;       //bgeu
            default: cond = 1'b0;
        endcase
endmodule

module conflict_prevention_unit 
  #(parameter bit CORE_TYPE = 0)
   (input  logic       RegWriteM, RegWriteW,
    input  logic [4:0] Rs1E, Rs2E, RdM, RdW,    
    output logic [1:0] ForwardA, ForwardB,
    //Организация пузырька
    input  logic       ResultSrcE0,
    input  logic [4:0] Rs1D, Rs2D, RdE,
    output logic       StallF, StallD, FlushE,
    //Предсказание перехода branch
    input  logic       PCSrcE,
    output logic       FlushD
);
    //#1 Байпасирование
    generate if (CORE_TYPE) begin   //#1 - Однотактное ядро
        assign ForwardA = 2'b00;
        assign ForwardB = 2'b00;
    end else begin                  //#0 - Конвеерное ядро
        always_comb begin
            if        ((Rs1E != 0) & (Rs1E == RdM) & RegWriteM) ForwardA = 2'b10;
            else if   ((Rs1E != 0) & (Rs1E == RdW) & RegWriteW) ForwardA = 2'b01;
                 else                                           ForwardA = 2'b00;
            if        ((Rs2E != 0) & (Rs2E == RdM) & RegWriteM) ForwardB = 2'b10;
            else if   ((Rs2E != 0) & (Rs2E == RdW) & RegWriteW) ForwardB = 2'b01;
                 else                                           ForwardB = 2'b00;
        end
    end
    endgenerate

    //#2 Организация пузырька при инструкции lw
    logic lwStall;
    generate if (CORE_TYPE) begin   //#1 - Однотактное ядро
        assign lwStall = 1'b0;
    end else begin                  //#0 - Конвеерное ядро
        assign lwStall = ResultSrcE0 & ((Rs1D == RdE) | (Rs2D == RdE));
    end
    endgenerate

    assign StallF = lwStall;
    assign StallD = lwStall;

    //#3 Предсказатель перехода branch
    generate if (CORE_TYPE) begin   //#1 - Однотактное ядро
        assign FlushD = 1'b0;
        assign FlushE = lwStall;
    end else begin                  //#0 - Конвеерное ядро
        assign FlushD = PCSrcE;
        assign FlushE = lwStall | PCSrcE;
    end
    endgenerate

endmodule

module fetch (
    input  logic        clk, rst, PCSrc, StallF,
    input  logic [31:0] PCTarget,
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
    assign PCNext = (PCSrc)? PCTarget : PCPlus4;
    
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
    assign imem_rst = FlushD; //Чтобы сбросить выход памяти инструкций в BSRAM
endmodule

module decode 
  #(parameter bit CORE_TYPE = 0)
   (input logic         clk, rst, RegWrite,
    input logic  [ 2:0] ImmSrc,
    input logic  [ 4:0] Addr1, Addr2, Addr3,
    input logic  [31:7] Imm,
    input  logic [31:0] Result,
    output logic [31:0] RD1, RD2, ImmExt
);
    //#rf - Регистровый файл//
    //DESCRIPTION: Трёхпортовый регистровый файл имеет два порта для считывания
    //и один порт для загрузки данных по сигналу разрешения RegWrite
    logic [31:0] rf[31:0];
    
    generate if (CORE_TYPE) begin   //Однотактное ядро
        always_ff @(posedge clk, posedge rst)
            if (rst) begin
                rf[1] <= 0;  //x1
                rf[2] <= 0;  //x2
                rf[3] <= 0;  //x3
                rf[4] <= 0;  //x4
                rf[5] <= 0;  //x5
                rf[6] <= 0;  //x6
                rf[7] <= 0;  //x7
                rf[8] <= 0;  //x8
                rf[9] <= 0;  //x9
                rf[10] <= 0; //x10
                rf[11] <= 0; //x11
                rf[12] <= 0; //x12
                rf[13] <= 0; //x13
                rf[14] <= 0; //x14
                rf[15] <= 0; //x15
                rf[16] <= 0; //x16
                rf[17] <= 0; //x17
                rf[18] <= 0; //x18
                rf[19] <= 0; //x19
                rf[20] <= 0; //x20
                rf[21] <= 0; //x21
                rf[22] <= 0; //x22
                rf[23] <= 0; //x23
                rf[24] <= 0; //x24
                rf[25] <= 0; //x25
                rf[26] <= 0; //x26
                rf[27] <= 0; //x27
                rf[28] <= 0; //x28
                rf[29] <= 0; //x29
                rf[30] <= 0; //x30
                rf[31] <= 0; //x31
            end
            else if (RegWrite) rf[Addr3] <= Result;
        assign RD1 = (Addr1 != 0) ? rf[Addr1] : 0;
        assign RD2 = (Addr2 != 0) ? rf[Addr2] : 0;
    end else begin                  //Конвеерное ядро
        always_ff @(negedge clk, posedge rst)
            if (rst) begin
                rf[1] <= 0;  //x1
                rf[2] <= 0;  //x2
                rf[3] <= 0;  //x3
                rf[4] <= 0;  //x4
                rf[5] <= 0;  //x5
                rf[6] <= 0;  //x6
                rf[7] <= 0;  //x7
                rf[8] <= 0;  //x8
                rf[9] <= 0;  //x9
                rf[10] <= 0; //x10
                rf[11] <= 0; //x11
                rf[12] <= 0; //x12
                rf[13] <= 0; //x13
                rf[14] <= 0; //x14
                rf[15] <= 0; //x15
                rf[16] <= 0; //x16
                rf[17] <= 0; //x17
                rf[18] <= 0; //x18
                rf[19] <= 0; //x19
                rf[20] <= 0; //x20
                rf[21] <= 0; //x21
                rf[22] <= 0; //x22
                rf[23] <= 0; //x23
                rf[24] <= 0; //x24
                rf[25] <= 0; //x25
                rf[26] <= 0; //x26
                rf[27] <= 0; //x27
                rf[28] <= 0; //x28
                rf[29] <= 0; //x29
                rf[30] <= 0; //x30
                rf[31] <= 0; //x31
            end
            else if (RegWrite) rf[Addr3] <= Result;
        
        assign RD1 = (Addr1 != 0) ? rf[Addr1] : 0;
        assign RD2 = (Addr2 != 0) ? rf[Addr2] : 0;
        //always_ff @(posedge clk) begin
        //    RD1 <= (Addr1 != 0) ? rf[Addr1] : 0;
        //    RD2 <= (Addr2 != 0) ? rf[Addr2] : 0;
        //end
    end
    endgenerate
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
    input  logic [ 1:0] ForwardA, ForwardB,
    input  logic [ 2:0] ALUSrc, 
    input  logic [ 3:0] ALUControl,
    input  logic [31:0] RD1, RD2, PC, ImmExt, ResultW, ALUResultM,
    output logic [ 3:0] Flags, //используются для операций branch
    output logic [31:0] ALUResult, WriteData,
    //Особенные
    output logic [31:0] PCTarget
);

    //#alu - Арифметикологическое устройство (АЛУ)//
    //DESCRIPTION: В зависимости от сигнала управления ALUControl происходит
    //соответствующая операция. На входы srcA и srcB поступают входные
    //операнды, результат записывается в ALUResult. Устройство детектирует
    //нулевой результат операции - сигнал Zero=1 при нулевом результате.
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
        always_comb
            case (ForwardA)
                  2'b01: SrcAforward = ResultW;
                  2'b10: SrcAforward = ALUResultM;
                default: SrcAforward = RD1;
            endcase
        always_comb
            case (ForwardB)
                  2'b01: SrcBforward = ResultW;
                  2'b10: SrcBforward = ALUResultM;
                default: SrcBforward = RD2;
            endcase
    end
    endgenerate

    //#2 АЛУ
    logic        ALUSrcB;
    logic [ 1:0] ALUSrcA;
    logic [31:0] srcA, srcB;

    assign {ALUSrcA, ALUSrcB} = ALUSrc;
    always_comb
        case (ALUSrcA)
            2'b01: srcA = PC;
            2'b10: srcA = 32'd0;
          default: srcA = SrcAforward;
        endcase
    assign srcB = (ALUSrcB) ? ImmExt : SrcBforward; //Мультипелксор для выбора второго операнда АЛУ: RD2 или ImmExt
    
    wire        v,c,n,z;       //флаги: overflow, carry out, negative, zero
    logic        cout;          //переполнение сумматора
    logic        isAddSub;      //1 - сложение/вычитание; 0 - прочие команды 
    logic [31:0] condinvb, sum;

    assign Flags = {v,c,n,z};
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

    assign z = &(~ALUResult);//(ALUResult == 32'b0);//Так сделано в книжке, мне кажется мой вариант свёртки правильнее
    assign n = ALUResult[31];
    assign c = cout & isAddSub;
    assign v = ~(ALUControl[0] ^ srcA[31] ^ srcB[31]) & (srcA[31] ^ sum[31]) & isAddSub;

    //#3 Сумматор для инструкций JAL/JALR с мультиплексором по первому операнду. Мультиплесора подаёт на один из входов
    //сумматора текущее счётчика инструкций PC или значение со входа SrcAforward основного АЛУ(учтено байпасирование для конвейерного
    //процессора) в зависимости от сигнала управления JALSrc. На второй вход сумматора подаётся расширенное значение
    //непосредственного числа ImmExt.
    logic [31:0] JALOp;
    assign JALOp = (JALSrc) ? SrcAforward : PC;
    assign PCTarget = JALOp + ImmExt;

    //#4 Транслирование сигналов и прочие связи
    assign WriteData = SrcBforward;

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
          (input  logic        clk, rst, en,
           input  logic [31:0] d [QUANTITY-1:0],
           output logic [31:0] q [QUANTITY-1:0]);

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
          (input  logic        clk, rst, en,
           input  logic [4:0] d [QUANTITY-1:0],
           output logic [4:0] q [QUANTITY-1:0]);

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