module core #(parameter [0:0] CORE_TYPE = 1,  //1 - Однотактное ядро; 0 - Конвеерное ядро
              parameter [0:0] MEMORY_TYPE = 1)//1 - BSRAM;            0 - Синтезированная
             (input  logic        clk,      //Вход тактирования
              input  logic        rst,      //Вход сброса (кнопка S2)
              output logic [5:0]  out,      //Выход на 6 светодиодов
              //Интерфейс памяти команд
              input  logic [31:0] imem_data,
              output logic [10:0] imem_addr,
              //Интерфейс памяти данных
              input logic [31:0]  dmem_ReadData,
              output logic        dmem_Write,
              output logic [31:0] dmem_Addr, dmem_WriteData
);
    
    //Сигналы тракта данных
    logic [4: 0] RdD, Rs1D, Rs2D;
    logic [4: 0] RdE, Rs1E, Rs2E;
    logic [4: 0] RdM;
    logic [4: 0] RdW;

    logic [31:0] PCPlus4F,      PCF, InstrF;
    logic [31:0] PCPlus4D, PCD, InstrD, ImmExtD, RD1D, RD2D;
    logic [31:0] PCPlus4E, PCE,         ImmExtE, RD1E, RD2E, WriteDataE, ALUResultE, PCTargetE;
    logic [31:0] PCPlus4M,                                   WriteDataM, ALUResultM, ReadDataM;
    logic [31:0] PCPlus4W,                                               ALUResultW, ReadDataW, ResultW; 

    //Сигналы блока управления
    logic RegWriteD, MemWriteD, JumpD, BranchD, ALUSrcD;                logic [1:0] ResultSrcD, ImmSrcD; logic [2:0] ALUControlD;
    logic RegWriteE, MemWriteE, JumpE, BranchE, ALUSrcE, PCSrcE, ZeroE; logic [1:0] ResultSrcE;          logic [2:0] ALUControlE;
    logic RegWriteM, MemWriteM;                                         logic [1:0] ResultSrcM;
    logic RegWriteW;                                                    logic [1:0] ResultSrcW;

    //Сигналы блока предотвращения конфликтов
    logic [1:0] ForwardAE, ForwardBE;
    //CONTROL UNIT//////////////////////////////////////////////////////////////////////////////////
    control_unit cu (  .op(InstrD[6:0]), .funct3(InstrD[14:12]), .funct7b5(InstrD[30]),
                        .RegWrite(RegWriteD), .ALUSrc(ALUSrcD), .MemWrite(MemWriteD), .Jump(JumpD), .Branch(BranchD),
                        .ImmSrc(ImmSrcD), .ResultSrc(ResultSrcD), .ALUControl(ALUControlD));
    conflict_prevention_unit #(CORE_TYPE) pu
                              (.RegWriteM(RegWriteM), .RegWriteW(RegWriteW),                                 
                               .Rs1E(Rs1E), .Rs2E(Rs2E), .RdM(RdM), .RdW(RdW),
                               .ForwardA(ForwardAE), .ForwardB(ForwardBE));
    //FETCH/////////////////////////////////////////////////////////////////////////////////////////
    fetch fetch(    .clk(clk), .rst(rst), .PCSrc(PCSrcE),
                    .PCTarget(PCTargetE),    
                    .PC(PCF), .PCPlus4(PCPlus4F), .Instr(InstrF),
                    //Интерфейс памяти инструкций
                    .imem_data(imem_data),
                    .imem_addr(imem_addr));
    ////////////////////////////////////////////////////////////////////////////////////////////////
    regmem  #(CORE_TYPE, MEMORY_TYPE) rm_fetch (clk, rst, InstrF, InstrD);
    regdata #(2, CORE_TYPE)           rd_fetch (clk, rst, {PCF, PCPlus4F},
                                                          {PCD, PCPlus4D});
    //DECODE////////////////////////////////////////////////////////////////////////////////////////
    decode #(CORE_TYPE) decode(  .clk(clk), .rst(rst), .RegWrite(RegWriteW), .ImmSrc(ImmSrcD),
                                 .Instr({InstrD[31:12],RdW[4:0],InstrD[6:0]}), .Result(ResultW),
                                 .RD1(RD1D), .RD2(RD2D), .ImmExt(ImmExtD));
    assign Rs1D = InstrD[19:15];
    assign Rs2D = InstrD[24:20];
    assign RdD  = InstrD[11:7];
    ////////////////////////////////////////////////////////////////////////////////////////////////
    regdata #(5, CORE_TYPE) rd_decode (clk, rst, {PCD, PCPlus4D, ImmExtD, RD1D, RD2D},
                                                 {PCE, PCPlus4E, ImmExtE, RD1E, RD2E});
    regrf   #(3, CORE_TYPE) rf_decode (clk, rst, {Rs1D, Rs2D, RdD},
                                                 {Rs1E, Rs2E, RdE});
    regcontrol #(10, CORE_TYPE) rc_decode (clk, rst, 
                    {RegWriteD, ResultSrcD[1:0], MemWriteD, JumpD, BranchD, ALUControlD[2:0], ALUSrcD}, 
                    {RegWriteE, ResultSrcE[1:0], MemWriteE, JumpE, BranchE, ALUControlE[2:0], ALUSrcE});
    //EXECUTE///////////////////////////////////////////////////////////////////////////////////////
    execute #(CORE_TYPE) execute
             (.ALUSrc(ALUSrcE), .ForwardA(ForwardAE), .ForwardB(ForwardBE), .ALUControl(ALUControlE),
              .RD1(RD1E), .RD2(RD2E), .PC(PCE), .ImmExt(ImmExtE), .ResultW(ResultW), .ALUResultM(ALUResultM),
              .Zero(ZeroE), .ALUResult(ALUResultE), .WriteData(WriteDataE),
              //Особенные
              .PCTarget(PCTargetE));
    ////Логика JUMP/BRANCH
    assign PCSrcE = (ZeroE & BranchE) | JumpE;
    ////////////////////////////////////////////////////////////////////////////////////////////////
    regdata    #(3, CORE_TYPE) rd_execute (clk, rst, {PCPlus4E, WriteDataE, ALUResultE},
                                                     {PCPlus4M, WriteDataM, ALUResultM});
    regrf      #(1, CORE_TYPE) rf_execute (clk, rst, {RdE},
                                                     {RdM});
    regcontrol #(4, CORE_TYPE) rc_execute (clk, rst, {RegWriteE, ResultSrcE[1:0], MemWriteE}, 
                                                     {RegWriteM, ResultSrcM[1:0], MemWriteM});
    //MEMORY////////////////////////////////////////////////////////////////////////////////////////
    memory memory ( .MemWrite(MemWriteM), .ALUResult(ALUResultM), .WriteData(WriteDataM),
                    .ReadData(ReadDataM),
                    //Интерфейс памяти данных
                    .dmem_ReadData(dmem_ReadData),
                    .dmem_Write(dmem_Write), .dmem_Addr(dmem_Addr),
                    .dmem_WriteData(dmem_WriteData));
    ////////////////////////////////////////////////////////////////////////////////////////////////
    regmem     #(CORE_TYPE, MEMORY_TYPE) rm_memory (clk, rst, ReadDataM, ReadDataW);
    regdata    #(2, CORE_TYPE)           rd_memory (clk, rst, {PCPlus4M, ALUResultM},
                                                              {PCPlus4W, ALUResultW});
    regrf      #(1, CORE_TYPE)           rf_memory (clk, rst, {RdM},
                                                              {RdW});
    regcontrol #(3, CORE_TYPE)           rc_memory (clk, rst, {RegWriteM, ResultSrcM[1:0]}, 
                                                              {RegWriteW, ResultSrcW[1:0]});
    //WRITEBACK/////////////////////////////////////////////////////////////////////////////////////
    writeback writeback (   .ResultSrc(ResultSrcW),
                            .ALUResult(ALUResultW), .ReadData(ReadDataW), .PCPlus4(PCPlus4W),
                            //Особенные
                            .Result(ResultW));
    ////////////////////////////////////////////////////////////////////////////////////////////////
    assign out = dmem_ReadData[5:0];

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
    
    output logic        RegWrite, ALUSrc, MemWrite, Jump, Branch,
    output logic [1:0]  ImmSrc,ResultSrc,
    output logic [2:0]  ALUControl
);

    logic [1:0] ALUOp;

    logic [10:0] controls; //Сборка сигналов управлеиня
    assign {RegWrite, ImmSrc[1:0], ALUSrc, MemWrite, ResultSrc[1:0], Branch, ALUOp[1:0], Jump} = controls;
    //          A          BB        C         D          EE           F         GG        H
    ////#cu.1 Основной дешифратор
    always_comb
        case(op)                     //A_BB_C_D_EE_F_GG_H
            7'b0000011: controls = 11'b1_00_1_0_01_0_00_0; //Команда lw
            7'b0100011: controls = 11'b0_01_1_1_00_0_00_0; //Команда sw
            7'b0110011: controls = 11'b1_00_0_0_00_0_10_0; //Команды or, and, ???(тип R) 
            7'b1100011: controls = 11'b0_10_0_0_00_1_01_0; //Команда beq
            7'b0010011: controls = 11'b1_00_1_0_00_0_10_0; //Команда addi
            7'b1101111: controls = 11'b1_11_0_0_10_0_00_1; //Команда jal
            default:    controls = 11'bx_xx_x_x_xx_x_xx_x; //Другие команды
        endcase
    ////#cu.2 Дешифратор АЛУ
    logic opb5;
    logic RtypeSub;
    assign opb5 = op[5];
    assign RtypeSub = funct7b5 & opb5;
    always_comb
        case(ALUOp)
            2'b00:   ALUControl = 3'b000;                                   //lw,sw
            2'b01:   ALUControl = 3'b001;                                   //beq
            default: case(funct3)
                        3'b000:  ALUControl = (RtypeSub) ? 3'b001 : 3'b000; //sub : add,addi
                        3'b010:  ALUControl = 3'b101;                       //slt
                        3'b110:  ALUControl = 3'b011;                       //or
                        3'b111:  ALUControl = 3'b010;                       //and
                        default: ALUControl = 3'bxxx;                       //Другие команды
                     endcase
        endcase
endmodule

module conflict_prevention_unit 
  #(parameter CORE_TYPE = 0)
   (input  logic       RegWriteM, RegWriteW,
    input  logic [4:0] Rs1E, Rs2E, RdM, RdW,    
    output logic [1:0] ForwardA, ForwardB
);
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
    
endmodule

module fetch (
    input  logic        clk, rst, PCSrc,
    input  logic [31:0] PCTarget,
    output logic [31:0] PC, PCPlus4, Instr,

    //Интерфейс памяти инструкций
    input  logic [31:0] imem_data,
    output logic [10:0] imem_addr
);
    //#pc - Счётчик команд//
    //DESCRIPTION: Счётчик команд PC на каждом такте принимает значение
    //PCNext, значение на который попадает с мультиплесора с сигналом выбора PCSrc.
    //PCNext может принимать значение PCPlus4(приращение текущего значения PC на 4ед.)
    //или значение внешнего источника смещения PCTarget(приращение текущего значения PC
    //на значение расширенного знаком непосредственного операнда ImmExt).
    logic [31:0] PCNext;
    assign PCPlus4 = PC + 4;
    assign PCNext = (PCSrc)? PCTarget : PCPlus4;

    always_ff @(posedge clk, posedge rst)
        if (rst)  PC <= 0;
        else      PC <= PCNext;
    
    //#imem - Память команд//
    //DESCRIPTION: По входному адресу счётчика команд PC из памяти команд
    //извлекается инструкция Instr. Выведен внешний интерфейс для подключения
    //памяти на шины imem_addr и imem_data.
    assign Instr = imem_data;
    assign imem_addr = PC[12:2];
endmodule

module decode 
  #(parameter CORE_TYPE = 0)
   (input logic         clk, rst, RegWrite,
    input logic  [ 1:0] ImmSrc,
    input  logic [31:0] Instr, Result,
    output logic [31:0] RD1, RD2, ImmExt
);
    //#rf - Регистровый файл//
    //DESCRIPTION: Трёхпортовый регистровый файл имеет два порта для считывания
    //и один порт для загрузки данных по сигналу разрешения RegWrite
    logic [5:0] Addr1, Addr2, Addr3;
    logic [31:0] rf[31:0];

    assign Addr1[5:0] = Instr[19:15];
    assign Addr2[5:0] = Instr[24:20];
    assign Addr3[5:0] = Instr[11:7];
    
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
    logic [31:7] Imm;
    assign Imm = Instr[31:7];

    always_comb
        case (ImmSrc)
            2'b00:   ImmExt = {{20{Imm[31]}},Imm[31:20]};                         //тип I
            2'b01:   ImmExt = {{20{Imm[31]}},Imm[31:25],Imm[11:7]};               //тип S
            2'b10:   ImmExt = {{20{Imm[31]}},Imm[7],Imm[30:25],Imm[11:8],1'b0};   //тип B
            2'b11:   ImmExt = {{12{Imm[31]}},Imm[19:12],Imm[20],Imm[30:21],1'b0}; //тип J
            default: ImmExt = 32'd0;
        endcase

endmodule

module execute #(CORE_TYPE) (
    input  logic        ALUSrc,
    input  logic [ 1:0] ForwardA, ForwardB,
    input  logic [ 2:0] ALUControl,
    input  logic [31:0] RD1, RD2, PC, ImmExt, ResultW, ALUResultM,
    output logic        Zero,
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
    
    logic [31:0] Amux, Bmux;
    //logic [31:0] Aabc [2:0] = {ALUResultM, ResultW, RD1};//{RD1, ResultW, ALUResultM};
    //logic [31:0] Babc [2:0] = {ALUResultM, ResultW, RD2};//{RD2, ResultW, ALUResultM};
    //assign Amux = Aabc[ForwardA];
    //assign Bmux = Babc[ForwardB];
    
    generate if (CORE_TYPE) begin   //#1 - Однотактное ядро
        assign Amux = RD1;
        assign Bmux = RD2;        
    end else begin                  //#0 - Конвеерное ядро
        always_comb
            case (ForwardA)
                  2'b01: Amux = ResultW;
                  2'b10: Amux = ALUResultM;
                default: Amux = RD1;
            endcase
        always_comb
            case (ForwardB)
                  2'b01: Bmux = ResultW;
                  2'b10: Bmux = ALUResultM;
                default: Bmux = RD2;
            endcase
    end
    endgenerate
    
    logic [31:0] srcA, srcB;
    assign srcA = Amux;
    assign srcB = (ALUSrc)? ImmExt : Bmux; //Мультипелксор для выбора второго операнда АЛУ: RD2 или ImmExt
    
    always_comb
        case (ALUControl)
            3'b000: ALUResult = srcA + srcB;
            3'b001: ALUResult = srcA - srcB;
            3'b010: ALUResult = srcA & srcB;
            3'b011: ALUResult = srcA | srcB;
            3'b101: ALUResult = (srcA < srcB)? 32'd1 : 32'd0;
            default: ALUResult = 32'd0;
        endcase

    assign Zero = &(~ALUResult);

    //#Сумматор текущего счётчика инструкций PC и расширенного непосредственного числа ImmExt.
    assign PCTarget = PC + ImmExt;

    //#Прочие связи
    assign WriteData = Bmux;

endmodule

module memory (
    input logic         MemWrite,
    input logic  [31:0] ALUResult, WriteData,
    output logic [31:0] ReadData,
    //Интерфейс памяти данных
    input logic  [31:0] dmem_ReadData,
    output logic        dmem_Write,
    output logic [31:0] dmem_Addr, dmem_WriteData
);

    //#dmem - Память данных//
    //DESCRIPTION: Память типа RAM доступна для чтения/записи. Имеет один вход
    //адреса dmem_Addr, выход считанных данных dmem_ReadData, а также вход записи
    //данных dmem_WriteData по сигналу разрешения записи dmem_Write. Выведен внешний
    //интерфейс для подключенияп памяти.
    assign dmem_WriteData = WriteData;
    assign dmem_Addr = ALUResult; 
    assign dmem_Write = MemWrite;
    assign ReadData = dmem_ReadData;

endmodule

module writeback (
    input  logic [ 1:0] ResultSrc,
    input  logic [31:0] ALUResult, ReadData, PCPlus4,
    //Особенные
    output logic [31:0] Result
);

    always_comb //Мультиплексор для выбора данных на запись в рег. файл:
        case (ResultSrc)
            2'b00:   Result = ALUResult;   //Результат вычисления АЛУ                         
            2'b01:   Result = ReadData;    //Результат выгрузки из памяти данных
            2'b10:   Result = PCPlus4;     //Значение текущего значения счётчика с приращением +4
            default: Result = 0;
        endcase

endmodule

module regdata
          #(parameter QUANTITY = 2, //Количество регистров без регистра выхода памяти
            parameter CORE_TYPE = 0)
          (input  logic        clk, rst,
           input  logic [31:0] d [QUANTITY-1:0],
           output logic [31:0] q [QUANTITY-1:0]);

    genvar i;

    generate if (CORE_TYPE) begin   //#1 - Однотактное ядро
        assign q = d;
    end else begin                  //#0 - Конвеерное ядро
        for(i=0; i<QUANTITY; i=i+1) begin : regdataloop
            always_ff @(posedge clk, posedge rst)
                if (rst)    q[i] <= 0;
                else        q[i] <= d[i];
        end
    end
    endgenerate

endmodule

module regrf
          #(parameter QUANTITY = 2, //Количество адресных регистров регистрового файла
            parameter CORE_TYPE = 0)
          (input  logic        clk, rst,
           input  logic [4:0] d [QUANTITY-1:0],
           output logic [4:0] q [QUANTITY-1:0]);

    genvar i;

    generate if (CORE_TYPE) begin   //#1 - Однотактное ядро
        assign q = d;
    end else begin                  //#0 - Конвеерное ядро
        for(i=0; i<QUANTITY; i=i+1) begin : regdataloop
            always_ff @(posedge clk, posedge rst)
                if (rst)    q[i] <= 0;
                else        q[i] <= d[i];
        end
    end
    endgenerate

endmodule

module regmem #(parameter CORE_TYPE = 0, //Количество регистров без регистра выхода памяти
                parameter MEMORY_TYPE = 0)
               (input  logic        clk, rst,
                input  logic [31:0] dm,
                output logic [31:0] qm);
    
    //При использовании памяти BSRAM в конвеерном ядре межстадийным регистром
    //является сама память поскольку она явлется синхронной и выдаёт данные на выход по такту.
    //При использовании синтезированной памяти в конвеерном ядре нужен дополнительный межстадийный
    //регистр поскольку память асинхронная и необходимо разделить стадии регистрами.

    generate if (MEMORY_TYPE | CORE_TYPE) begin    //#1 - Провод для прочих конфигураций
        assign qm = dm;
    end else begin                                 //#0 - Регистр для конвеерного ядра с синтезированной памятью
        always_ff @(posedge clk, posedge rst)
            if (rst)    qm <= 0;
            else        qm <= dm;
    end
    endgenerate

endmodule

module regcontrol
          #(parameter WIDTH = 2,
            parameter CORE_TYPE = 0)
          (input  logic             clk, rst,
           input  logic [WIDTH-1:0] d,
           output logic [WIDTH-1:0] q);

    generate if (CORE_TYPE) begin   //#1 - Однотактное ядро
        assign q = d;
    end else begin                  //#0 - Конвеерное ядро
        always_ff @(posedge clk, posedge rst)
            if (rst)    q <= 0;
            else        q <= d;
    end
    endgenerate

endmodule