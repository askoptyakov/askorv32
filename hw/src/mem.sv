module imem #(parameter [0:0] MEMORY_TYPE = 0) //Память команд (ROM)
             (input logic clk, rst, re,
              input logic [10:0] addr,
              output logic [31:0] data);

    //DESCRIPTION: По входному адресу счётчика команд PC из памяти команд
    //извлекается инструкция Instr.
    generate if (MEMORY_TYPE) begin   //#1 - BSRAM
        bsram_imem8k imem(
        .dout(data), //output [31:0] dout
        .clk(clk), //input clk
        .oce(1'b0), //input oce
        .ce(re), //input ce
        .reset(rst), //input reset
        .wre(1'b0), //input wre
        .ad(addr), //input [10:0] ad
        .din(32'b0000_0000_0000_0000_0000_0000_0000_0000) //input [31:0] din
        );
    end else begin                  //#0 - Синтезированная память
        //Вариант подгрузки инструкций из внешнего файла - удобный
        logic [31:0] imem [0:99];
        initial $readmemh("mem_init/i.mem", imem);
        assign data = imem[addr];
        /* //Вариант подгрузки инструкций мультиплексором - первоначальный
        always_comb
            case (addr[4:0])
                // Для отработки пузырька
                //5'b00000: data = 32'h00500113;
                //5'b00001: data = 32'h00c00193;
                //5'b00010: data = 32'hff718393;
                //5'b00011: data = 32'h0023e233;
                //5'b00100: data = 32'h0041f2b3;
                //5'b00101: data = 32'h004282b3;
                //5'b00110: data = 32'hfe51aa23;
                //5'b00111: data = 32'h00500393;
                //5'b01000: data = 32'h00600493;
                //5'b01001: data = 32'h00002103;
                //5'b01010: data = 32'h00410433;
                //5'b01011: data = 32'h403404b3;
                //5'b01100: data = 32'h03800113;
                //5'b01101: data = 32'h009101b3;
                //default: data = 0;
                // Отработка минимального набора инструкций из книги Харрисов
                5'b00000: data = 32'h00500113;//7'h00//main:   addi x2, x0, 5      //x2 = 5
                5'b00001: data = 32'h00C00193;//7'h04//        addi x3, x0, 12     //x3 = 12
                5'b00010: data = 32'hFF718393;//7'h08//        addi x7, x3, -9     //x7 = 12  -  9   = 3
                5'b00011: data = 32'h0023E233;//7'h0C//        or   x4, x7, x2     //x4 = 3  OR  5   = 7
                5'b00100: data = 32'h0041F2B3;//7'h10//        and  x5, x3, x4     //x5 = 12 AND 7   = 4
                5'b00101: data = 32'h004282B3;//7'h14//        add  x5, x5, x4     //x5 = 4   +  7   = 11
                5'b00110: data = 32'h02728863;//7'h18//        beq  x5, x7, end    //pc = (11 == 3)? end : pc + 4    #Ложь
                5'b00111: data = 32'h0041A233;//7'h1C//        slt  x4, x3, x4     //x4 = 12  <  7   = 0
                5'b01000: data = 32'h00020463;//7'h20//        beq  x4, x0, around //pc = (0 == 0)? around : pc + 4  #Истина, переход к around
                5'b01001: data = 32'h00000293;//7'h24//        addi x5, x0, 0      //!x5= 0   +  0   = 0             #Не выполняется
                5'b01010: data = 32'h0023A233;//7'h28//around: slt  x4, x7, x2     //x4 = 3   <  5   = 1
                5'b01011: data = 32'h005203B3;//7'h2C//        add  x7, x4, x5     //x7 = 1   +  11  = 12
                5'b01100: data = 32'h402383B3;//7'h30//        sub  x7, x7, x2     //x7 = 12  -  5   = 7
                5'b01101: data = 32'hFE71AA23;//7'h34//        sw   x7, -12(x3)    //      dmem[0] <- 7
                5'b01110: data = 32'h00002103;//7'h38//        lw   x2, 0(x0)      //x2 -> dmem[0]  = 7
                5'b01111: data = 32'h005104B3;//7'h3C//        add  x9, x2, x5     //x9 = 7   +  11  = 18
                5'b10000: data = 32'h008001EF;//7'h40//        jal  x3, end        //pc = end, x3 = 0x44             #Переход к end
                5'b10001: data = 32'h00100113;//7'h44//        addi x2, x0, 1      //!x2= 0   +  1   = 1
                5'b10010: data = 32'h00910133;//7'h48//end:    add  x2, x2, x9     //x2 = 7   +  18  = 25
                5'b10011: data = 32'hFC21A023;//7'h4C//        sw   x2, -64(x3)    //      dmem[4] <- 25
                5'b10100: data = 32'h00210063;//7'h50//done:   beq  x2, x2, done   //pc = (25 == 25)? done : pc + 4  #Истина, бесконечный цикл 
                default: data = 0;
        endcase */
    end 
    endgenerate
endmodule
/*
//Размер памяти MEMORY_SIZE можно изменять только кратно 8кБайт
module imem #(parameter  bit MEMORY_TYPE = 0,               //Память команд (ROM)
              parameter  int MEMORY_SIZE = 8,
              localparam int SECTIONS    = MEMORY_SIZE / 8)
             (input logic clk, rst, re,
              input logic [10:0] addr,
              output logic [31:0] data);

    //DESCRIPTION: По входному адресу счётчика команд PC из памяти команд
    //извлекается инструкция Instr.
    generate if (MEMORY_TYPE) begin   //#1 - BSRAM
        //#1 Предварительная подготовка памяти инструкций
        int imem [];
        
        initial begin
            reg [31:0] imem [0:(SECTIONS*2048)-1];
            reg [255:0] imem_cooked [0:SECTIONS-1][0:3][0:63];
            $readmemh("mem_init/i.mem", imem);
            for (genvar k = 0; k<SECTIONS; k++) begin : INIT_LOOP0
                for (genvar l = 0; l<4; l++) begin : INIT_LOOP1
                    for (genvar m = 0; m<64; m++) begin : INIT_LOOP2
                        for (genvar n = 0; n<32; n++) begin : INIT_LOOP3
                            imem_cooked[k][l][m][(n*8)+7:n*8] = imem[0][(8*l)-1:0];

                            assign imem_cooked[k][1][m] = {,imem[0][15:8]};
                            assign imem_cooked[k][2][m] = {,imem[0][23:16]};
                            assign imem_cooked[k][2][m] = {,imem[0][31:24]};
                        end
                    end
                end
            end
        end
        //#2 Создание структуры памяти BSRAM с инициализацией
        for (genvar i = 0; i<SECTIONS; i++) begin : SECTIONS_LOOP
            for (genvar j = 0; j<4; j++) begin : BSRAM_LOOP
                SP #(   .READ_MODE = 1'b0,
                        .WRITE_MODE = 2'b00,
                        .BIT_WIDTH = 8,
                        .BLK_SEL = 3'b000,
                        .RESET_MODE = "SYNC",
                        .INIT_RAM_00 = imem_cooked[i][j][0],
                        .INIT_RAM_01 = imem_cooked[i][j][1],
                        .INIT_RAM_02 = imem_cooked[i][j][2],
                        .INIT_RAM_03 = imem_cooked[i][j][3],
                        .INIT_RAM_04 = imem_cooked[i][j][4],
                        .INIT_RAM_05 = imem_cooked[i][j][5],
                        .INIT_RAM_06 = imem_cooked[i][j][6],
                        .INIT_RAM_07 = imem_cooked[i][j][7],
                        .INIT_RAM_08 = imem_cooked[i][j][8],
                        .INIT_RAM_09 = imem_cooked[i][j][9],
                        .INIT_RAM_0A = imem_cooked[i][j][10],
                        .INIT_RAM_0B = imem_cooked[i][j][11],
                        .INIT_RAM_0C = imem_cooked[i][j][12],
                        .INIT_RAM_0D = imem_cooked[i][j][13],
                        .INIT_RAM_0E = imem_cooked[i][j][14],
                        .INIT_RAM_0F = imem_cooked[i][j][15],
                        .INIT_RAM_10 = imem_cooked[i][j][16],
                        .INIT_RAM_11 = imem_cooked[i][j][17],
                        .INIT_RAM_12 = imem_cooked[i][j][18],
                        .INIT_RAM_13 = imem_cooked[i][j][19],
                        .INIT_RAM_14 = imem_cooked[i][j][20],
                        .INIT_RAM_15 = imem_cooked[i][j][21],
                        .INIT_RAM_16 = imem_cooked[i][j][22],
                        .INIT_RAM_17 = imem_cooked[i][j][23],
                        .INIT_RAM_18 = imem_cooked[i][j][24],
                        .INIT_RAM_19 = imem_cooked[i][j][25],
                        .INIT_RAM_1A = imem_cooked[i][j][26],
                        .INIT_RAM_1B = imem_cooked[i][j][27],
                        .INIT_RAM_1C = imem_cooked[i][j][28],
                        .INIT_RAM_1D = imem_cooked[i][j][29],
                        .INIT_RAM_1E = imem_cooked[i][j][30],
                        .INIT_RAM_1F = imem_cooked[i][j][31],
                        .INIT_RAM_20 = imem_cooked[i][j][32],
                        .INIT_RAM_21 = imem_cooked[i][j][33],
                        .INIT_RAM_22 = imem_cooked[i][j][34],
                        .INIT_RAM_23 = imem_cooked[i][j][35],
                        .INIT_RAM_24 = imem_cooked[i][j][36],
                        .INIT_RAM_25 = imem_cooked[i][j][37],
                        .INIT_RAM_26 = imem_cooked[i][j][38],
                        .INIT_RAM_27 = imem_cooked[i][j][39],
                        .INIT_RAM_28 = imem_cooked[i][j][40],
                        .INIT_RAM_29 = imem_cooked[i][j][41],
                        .INIT_RAM_2A = imem_cooked[i][j][42],
                        .INIT_RAM_2B = imem_cooked[i][j][43],
                        .INIT_RAM_2C = imem_cooked[i][j][44],
                        .INIT_RAM_2D = imem_cooked[i][j][45],
                        .INIT_RAM_2E = imem_cooked[i][j][46],
                        .INIT_RAM_2F = imem_cooked[i][j][47],
                        .INIT_RAM_30 = imem_cooked[i][j][48],
                        .INIT_RAM_31 = imem_cooked[i][j][49],
                        .INIT_RAM_32 = imem_cooked[i][j][50],
                        .INIT_RAM_33 = imem_cooked[i][j][51],
                        .INIT_RAM_34 = imem_cooked[i][j][52],
                        .INIT_RAM_35 = imem_cooked[i][j][53],
                        .INIT_RAM_36 = imem_cooked[i][j][54],
                        .INIT_RAM_37 = imem_cooked[i][j][55],
                        .INIT_RAM_38 = imem_cooked[i][j][56],
                        .INIT_RAM_39 = imem_cooked[i][j][57],
                        .INIT_RAM_3A = imem_cooked[i][j][58],
                        .INIT_RAM_3B = imem_cooked[i][j][59],
                        .INIT_RAM_3C = imem_cooked[i][j][60],
                        .INIT_RAM_3D = imem_cooked[i][j][61],
                        .INIT_RAM_3E = imem_cooked[i][j][62],
                        .INIT_RAM_3F = imem_cooked[i][j][63],
                    ) imem_inst (
                        .DO({sp_inst_0_dout_w[23:0],dout[7:0]}),
                        .CLK(clk), .OCE(oce), .CE(ce), .RESET(reset),
                        .WRE(wre), .BLKSEL({3{1'b0}}),
                        .AD({ad[10:0],{3{1'b0}}}),
                        .DI({{24{1'b0}},din[7:0]}));
            end
        end
    end else begin                  //#0 - Синтезированная память
        //Подгрузка инструкций из внешнего файла
        reg [31:0] imem [0:63];
        initial $readmemh("mem_init/i.mem", imem);
        assign data = imem[addr];
    end 
    endgenerate
endmodule
*/
/*
module dmem #(parameter [0:0] MEMORY_TYPE = 0) //Память данных (RAM)
            (input logic clk, reset, we, 
             input logic  [31:0] a,
             input logic  [31:0] wd,
             output logic [31:0] rd);

    //DESCRIPTION: Память типа RAM доступна для чтения/записи. Имеет один вход
    //адреса a, выход считанных данных rd, а также вход записи
    //данных wd по сигналу разрешения записи we.
    generate if (MEMORY_TYPE) begin   //#1 - BSRAM
        bsram_dmem8k dmem(
        .dout(rd), //output [31:0] dout
        .clk(clk), //input clk
        .oce(1'b0), //input oce
        .ce(1'b1), //input ce
        .reset(1'b0), //input reset
        .wre(we), //input wre
        .ad(a), //input [10:0] ad
        .din(wd) //input [31:0] din
        );
    end else begin                  //#0 - Синтезированная память
        logic [31:0] RAM[15:0];
        assign rd = RAM[a]; //Выравнивание по слову

        always_ff @(posedge clk, posedge reset)
            if (reset) begin
                RAM[0] <= 0;
                RAM[1] <= 0;
                RAM[2] <= 0;
                RAM[3] <= 0;
                RAM[4] <= 0;
                RAM[5] <= 0;
                RAM[6] <= 0;
                RAM[7] <= 0;
                RAM[8] <= 0;
                RAM[9] <= 0;
                RAM[10] <= 0;
                RAM[11] <= 0;
                RAM[12] <= 0;
                RAM[13] <= 0;
                RAM[14] <= 0;
                RAM[15] <= 0;
            end
            else if (we) RAM[a] <= wd;
    end
    endgenerate
    
endmodule
*/

//Размер памяти MEMORY_SIZE можно изменять только кратно 8кБайт(от 8 до 32)
module dmem #(parameter  bit MEMORY_TYPE = 0, //Память данных (RAM)
              parameter  int MEMORY_SIZE = 8)
            (input logic clk, reset, 
             input logic  [3 :0] wstrb,
             input logic  [31:0] a,
             input logic  [31:0] wd,
             output logic [31:0] rd);

    localparam int SECTIONS = MEMORY_SIZE / 8;

    //DESCRIPTION: Память типа RAM доступна для чтения/записи. Имеет один вход
    //адреса a, выход считанных данных rd, а также вход записи
    //данных wd по сигналу разрешения записи we.
    generate if (MEMORY_TYPE) begin   //#1 - BSRAM
        for (genvar i = 0; i<SECTIONS; i++) begin : d_cluster
            for (genvar j = 0; j<4; j++) begin : d_sector
                logic [23:0] dout_empty;
                SP #(   .READ_MODE(1'b0),
                        .WRITE_MODE(2'b00),
                        .BIT_WIDTH(8),
                        .BLK_SEL({1'b0, i[1:0]}),
                        .RESET_MODE("SYNC")                       
                    ) bsram (
                        .DO({dout_empty[23:0],rd[(j*8)+7:j*8]}),
                        .CLK(clk), .OCE(1'b0), .CE(1'b1), .RESET(reset),
                        .WRE(wstrb[j]), .BLKSEL({1'b0, a[12], a[11]}),
                        .AD({a[10:0],{3{1'b0}}}),
                        .DI({{24{1'b0}},wd[(j*8)+7:j*8]}));
            end
        end
    end else begin                  //#0 - Синтезированная память
        for (genvar i = 0; i<SECTIONS; i++) begin : d_cluster
            for (genvar j = 0; j<4; j++) begin : d_sector
                logic [7:0] mem [9:0];
                assign rd[(j*8)+7:j*8] = mem[a]; 
                always @(posedge clk) begin
                    if (wstrb[j]) begin
                        mem[a] <= wd[(j*8)+7:j*8];
                    end
                end
            end
        end
    end
    endgenerate
/*
        logic [23:0] dout_empty00;
        SP #(   .READ_MODE(1'b0),
                .WRITE_MODE(2'b00),
                .BIT_WIDTH(8),
                .BLK_SEL(3'b000),
                .RESET_MODE("SYNC")                       
            ) dmem_inst00 (
                .DO({dout_empty00[23:0],rd[7:0]}),
                .CLK(clk), .OCE(1'b0), .CE(1'b1), .RESET(reset),
                .WRE(we), .BLKSEL({3{1'b0}}),
                .AD({a[10:0],{3{1'b0}}}),
                .DI({{24{1'b0}},wd[7:0]}));
        logic [23:0] dout_empty01;
        SP #(   .READ_MODE(1'b0),
                .WRITE_MODE(2'b00),
                .BIT_WIDTH(8),
                .BLK_SEL(3'b000),
                .RESET_MODE("SYNC")                          
            ) dmem_inst01 (
                .DO({dout_empty01[23:0],rd[15:8]}),
                .CLK(clk), .OCE(1'b0), .CE(1'b1), .RESET(reset),
                .WRE(we), .BLKSEL({3{1'b0}}),
                .AD({a[10:0],{3{1'b0}}}),
                .DI({{24{1'b0}},wd[15:8]}));
        logic [23:0] dout_empty02;
        SP #(   .READ_MODE(1'b0),
                .WRITE_MODE(2'b00),
                .BIT_WIDTH(8),
                .BLK_SEL(3'b000),
                .RESET_MODE("SYNC")                          
            ) dmem_inst02 (
                .DO({dout_empty02[23:0],rd[23:16]}),
                .CLK(clk), .OCE(1'b0), .CE(1'b1), .RESET(reset),
                .WRE(we), .BLKSEL({3{1'b0}}),
                .AD({a[10:0],{3{1'b0}}}),
                .DI({{24{1'b0}},wd[23:16]}));
        logic [23:0] dout_empty03;
        SP #(   .READ_MODE(1'b0),
                .WRITE_MODE(2'b00),
                .BIT_WIDTH(8),
                .BLK_SEL(3'b000),
                .RESET_MODE("SYNC")                           
            ) dmem_inst03 (
                .DO({dout_empty03[23:0],rd[31:24]}),
                .CLK(clk), .OCE(1'b0), .CE(1'b1), .RESET(reset),
                .WRE(we), .BLKSEL({3{1'b0}}),
                .AD({a[10:0],{3{1'b0}}}),
                .DI({{24{1'b0}},wd[31:24]}));

        logic [23:0] dout_empty10;
        SP #(   .READ_MODE(1'b0),
                .WRITE_MODE(2'b00),
                .BIT_WIDTH(8),
                .BLK_SEL(3'b001),
                .RESET_MODE("SYNC")                       
            ) dmem_inst10 (
                .DO({dout_empty10[23:0],rd[7:0]}),
                .CLK(clk), .OCE(1'b0), .CE(1'b1), .RESET(reset),
                .WRE(we), .BLKSEL({3{1'b0}}),
                .AD({a[10:0],{3{1'b0}}}),
                .DI({{24{1'b0}},wd[7:0]}));
        logic [23:0] dout_empty11;
        SP #(   .READ_MODE(1'b0),
                .WRITE_MODE(2'b00),
                .BIT_WIDTH(8),
                .BLK_SEL(3'b001),
                .RESET_MODE("SYNC")                          
            ) dmem_inst11 (
                .DO({dout_empty11[23:0],rd[15:8]}),
                .CLK(clk), .OCE(1'b0), .CE(1'b1), .RESET(reset),
                .WRE(we), .BLKSEL({3{1'b0}}),
                .AD({a[10:0],{3{1'b0}}}),
                .DI({{24{1'b0}},wd[15:8]}));
        logic [23:0] dout_empty12;
        SP #(   .READ_MODE(1'b0),
                .WRITE_MODE(2'b00),
                .BIT_WIDTH(8),
                .BLK_SEL(3'b001),
                .RESET_MODE("SYNC")                          
            ) dmem_inst12 (
                .DO({dout_empty12[23:0],rd[23:16]}),
                .CLK(clk), .OCE(1'b0), .CE(1'b1), .RESET(reset),
                .WRE(we), .BLKSEL({3{1'b0}}),
                .AD({a[10:0],{3{1'b0}}}),
                .DI({{24{1'b0}},wd[23:16]}));
        logic [23:0] dout_empty13;
        SP #(   .READ_MODE(1'b0),
                .WRITE_MODE(2'b00),
                .BIT_WIDTH(8),
                .BLK_SEL(3'b001),
                .RESET_MODE("SYNC")                           
            ) dmem_inst13 (
                .DO({dout_empty13[23:0],rd[31:24]}),
                .CLK(clk), .OCE(1'b0), .CE(1'b1), .RESET(reset),
                .WRE(we), .BLKSEL({3{1'b0}}),
                .AD({a[10:0],{3{1'b0}}}),
                .DI({{24{1'b0}},wd[31:24]}));
*/
/*
        for (genvar i = 0; i<SECTIONS; i++) begin : SECTIONS_LOOP
            for (genvar j = 0; j<4; j++) begin : BSRAM_LOOP
                logic [23:0] dout_empty;
                SP #(   .READ_MODE = 1'b0,
                        .WRITE_MODE = 2'b00,
                        .BIT_WIDTH = 8,
                        .BLK_SEL = i,//3'b000,
                        .RESET_MODE = "SYNC"                       
                    ) imem_inst (
                        .DO({dout_empty[23:0],dout[7:0]}),
                        .CLK(clk), .OCE(oce), .CE(ce), .RESET(reset),
                        .WRE(wre), .BLKSEL({3{1'b0}}),
                        .AD({ad[10:0],{3{1'b0}}}),
                        .DI({{24{1'b0}},din[7:0]}));

        bsram_dmem8k dmem(
        .dout(rd), //output [31:0] dout
        .clk(clk), //input clk
        .oce(1'b0), //input oce
        .ce(1'b1), //input ce
        .reset(1'b0), //input reset
        .wre(we), //input wre
        .ad(a), //input [10:0] ad
        .din(wd) //input [31:0] din
        );
*/
    
endmodule