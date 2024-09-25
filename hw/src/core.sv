module core   
   (input  logic        clk,      //Вход тактирования
    input  logic        rst,      //Вход сброса (кнопка S2)
    output logic [5:0]  out,       //Выход на 6 светодиодов
    //Интерфейс памяти команд
    input  logic [31:0] imem_data,
    output logic [10:0]  imem_addr,
    //Интерфейс памяти данных
    input logic [31:0]  dmem_ReadData,
    output logic        dmem_Write,
    output logic [31:0] dmem_Addr, dmem_WriteData
);

    ////////////////////#cu - Блок управления////////////////////
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
    logic RegWrite, ALUSrc, MemWrite, Branch, Jump;
    logic [1:0] ImmSrc, ResultSrc, ALUOp;
    logic [2:0] ALUControl;
    logic [6:0] op;
    logic Zero, funct7b5, PCSrc;
    logic [2:0] funct3b210;
    assign op = Instr[6:0];
    assign funct7b5 = Instr[30];
    assign funct3b210 = Instr[14:12];

    logic [10:0] ControlS; //Сборка сигналов управлеиня
    assign {RegWrite, ImmSrc[1:0], ALUSrc, MemWrite, ResultSrc[1:0], Branch, ALUOp[1:0], Jump} = ControlS;
    //          A          BB        C         D          EE           F         GG        H
    ////#cu.1 Основной дешифратор
    always_comb
        case(op)                     //A_BB_C_D_EE_F_GG_H
            7'b0000011: ControlS = 11'b1_00_1_0_01_0_00_0; //Команда lw
            7'b0100011: ControlS = 11'b0_01_1_1_00_0_00_0; //Команда sw
            7'b0110011: ControlS = 11'b1_00_0_0_00_0_10_0; //Команды or, and, ???(тип R) 
            7'b1100011: ControlS = 11'b0_10_0_0_00_1_01_0; //Команда beq
            7'b0010011: ControlS = 11'b1_00_1_0_00_0_10_0; //Команда addi
            7'b1101111: ControlS = 11'b1_11_0_0_10_0_00_1; //Команда jal
            default:    ControlS = 11'bx_xx_x_x_xx_x_xx_x; //Другие команды
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
            default: case(funct3b210)
                        3'b000:  ALUControl = (RtypeSub) ? 3'b001 : 3'b000; //sub : add,addi
                        3'b010:  ALUControl = 3'b101;                       //slt
                        3'b110:  ALUControl = 3'b011;                       //or
                        3'b111:  ALUControl = 3'b010;                       //and
                        default: ALUControl = 3'bxxx;                       //Другие команды
                     endcase
        endcase
    ////#cu.3 Логика JUMP/BRANCH
    assign PCSrc = (Zero & Branch) | Jump;
    
    ////////////////////#pc - Счётчик команд////////////////////
    //DESCRIPTION: Счётчик команд PC на каждом такте принимает значение
    //PCNext, значение на который попадает с мультиплесора с сигналом выбора PCSrc.
    //PCNext может принимать значение PCPlus4(приращение текущего значения PC на 4ед.)
    //или значение внешнего источника смещения PCExt(приращение текущего значения PC
    //на значение расширенного знаком непосредственного операнда ImmExt).
    logic [31:0] PC, PCPlus4, PCExt, PCNext;
    assign PCPlus4 = PC + 4;
    assign PCExt = PC + ImmExt;
    assign PCNext = (PCSrc)? PCExt : PCPlus4;

    always_ff @(posedge clk, posedge rst)
        if (rst)  PC <= 0;
        else      PC <= PCNext;

    assign out = PC[6:1];
    
    ////////////////////#imem - Память команд////////////////////
    //DESCRIPTION: По входному адресу счётчика команд PC из памяти команд
    //извлекается инструкция Instr. Выведен внешний интерфейс для подключения
    //памяти на шины imem_addr и imem_data.
    logic [31:0] Instr;
    assign Instr = imem_data;
    assign imem_addr = PC[12:2];

    ////////////////////#rf - Регистровый файл////////////////////
    //DESCRIPTION: Трёхпортовый регистровый файл имеет два порта для считывания
    //и один порт для загрузки данных по сигналу разрешения RegWrite
    logic [5:0] rf_Addr1, rf_Addr2, rf_Addr3;
    logic [31:0] rf_RD1, rf_RD2, Result;
    logic [31:0] rf[31:0];

    assign rf_Addr1[5:0] = Instr[19:15];
    assign rf_Addr2[5:0] = Instr[24:20];
    assign rf_Addr3[5:0] = Instr[11:7];
    
    always_comb //Мультиплексор для выбора данных на запись в рег. файл:
        case (ResultSrc)
            2'b00:   Result = alu_Result;       //Результат вычисления АЛУ                         
            2'b01:   Result = dmem_ReadData;    //Результат выгрузки из памяти данных
            2'b10:   Result = PCPlus4;          //Значение текущего значения счётчика с приращением +4
            default: Result = 0;
        endcase

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
        else if (RegWrite) rf[rf_Addr3] <= Result;

    assign rf_RD1 = (rf_Addr1 != 0) ? rf[rf_Addr1] : 0;
    assign rf_RD2 = (rf_Addr2 != 0) ? rf[rf_Addr2] : 0;

    //////////#ie - Знаковое расширение непосредственного числа//////////
    //DESCRIPTION: Производится знаковое расширение непосредственного числа
    //в зависимости от типа регистра ImmSrc. Знаковый бит Imm[31] копируется
    //в старшие разряды непосредственного значения.
    logic [31:7] Imm;
    logic [31:0] ImmExt;
    assign Imm = Instr[31:7];

    always_comb
        case (ImmSrc)
            2'b00:   ImmExt = {{20{Imm[31]}},Imm[31:20]};                         //тип I
            2'b01:   ImmExt = {{20{Imm[31]}},Imm[31:25],Imm[11:7]};               //тип S
            2'b10:   ImmExt = {{20{Imm[31]}},Imm[7],Imm[30:25],Imm[11:8],1'b0};   //тип B
            2'b11:   ImmExt = {{12{Imm[31]}},Imm[19:12],Imm[20],Imm[30:21],1'b0}; //тип J
            default: ImmExt = 32'd0;
        endcase

    //////////#alu - Арифметикологическое устройство (АЛУ)//////////
    //DESCRIPTION: В зависимости от сигнала управления ALUResult происходит
    //соответствующая операция. На входы alu_A и alu_B поступают входные
    //операнды, результат записывается в alu_Result. Устройство детектирует
    //нулевой результат операции - сигнал Zero=1 при нулевом результате.
    //На вход alu_B может поступать как второй операнд регистрового файла RD2,
    //так и расширенное знаком непосредственное значение ImmExt в зависимости
    //от сигнала управления ALUSrc
    logic [31:0] alu_A;
    logic [31:0] alu_B;
    logic [31:0] alu_Result;
    assign alu_A = rf_RD1;
    assign alu_B = (ALUSrc)? ImmExt : rf_RD2; //Мультипелксор для выбора второго операнда АЛУ: RD2 или ImmExt
    
    always_comb
        case (ALUControl)
            3'b000: alu_Result = alu_A + alu_B;
            3'b001: alu_Result = alu_A - alu_B;
            3'b010: alu_Result = alu_A & alu_B;
            3'b011: alu_Result = alu_A | alu_B;
            3'b101: alu_Result = (alu_A < alu_B)? 32'd1 : 32'd0;
            default: alu_Result = 32'd0;
        endcase

    assign Zero = &(~alu_Result);

    ////////////////////#dmem - Память данных////////////////////
    //DESCRIPTION: Память типа RAM доступна для чтения/записи. Имеет один вход
    //адреса dmem_Addr, выход считанных данных dmem_ReadData, а также вход записи
    //данных dmem_WriteData по сигналу разрешения записи dmem_Write. Выведен внешний
    //интерфейс для подключенияп памяти.
    assign dmem_WriteData = rf_RD2;
    assign dmem_Addr = alu_Result; 
    assign dmem_Write = MemWrite;
    //dmem_ReadData подключен в блок регистрового файла

endmodule