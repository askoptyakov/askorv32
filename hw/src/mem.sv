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
        reg [31:0] imem [0:39];
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
