module imem //Память команд (ROM)
            (input logic [4:0] addr,
             output logic [31:0] instr);

    //DESCRIPTION: По входному адресу счётчика команд PC из памяти команд
    //извлекается инструкция Instr.

    always_comb
        case (addr)
            5'b00000: instr = 32'h00500113;//7'h00//main:   addi x2, x0, 5      //x2 = 5
            5'b00001: instr = 32'h00C00193;//7'h04//        addi x3, x0, 12     //x3 = 12
            5'b00010: instr = 32'hFF718393;//7'h08//        addi x7, x3, -9     //x7 = 12  -  9   = 3
            5'b00011: instr = 32'h0023E233;//7'h0C//        or   x4, x7, x2     //x4 = 3  OR  5   = 7
            5'b00100: instr = 32'h0041F2B3;//7'h10//        and  x5, x3, x4     //x5 = 12 AND 7   = 4
            5'b00101: instr = 32'h004282B3;//7'h14//        add  x5, x5, x4     //x5 = 4   +  7   = 11
            5'b00110: instr = 32'h02728863;//7'h18//        beq  x5, x7, end    //pc = (11 == 3)? end : pc + 4    #Ложь
            5'b00111: instr = 32'h0041A233;//7'h1C//        slt  x4, x3, x4     //x4 = 12  <  7   = 0
            5'b01000: instr = 32'h00020463;//7'h20//        beq  x4, x0, around //pc = (0 == 0)? around : pc + 4  #Истина, переход к around
            5'b01001: instr = 32'h00000293;//7'h24//        addi x5, x0, 0      //!x5= 0   +  0   = 0             #Не выполняется
            5'b01010: instr = 32'h0023A233;//7'h28//around: slt  x4, x7, x2     //x4 = 3   <  5   = 1
            5'b01011: instr = 32'h005203B3;//7'h2C//        add  x7, x4, x5     //x7 = 1   +  11  = 12
            5'b01100: instr = 32'h402383B3;//7'h30//        sub  x7, x7, x2     //x7 = 12  -  5   = 7
            5'b01101: instr = 32'hFE71AA23;//7'h34//        sw   x7, -12(x3)    //      dmem[0] <- 7
            5'b01110: instr = 32'h00002103;//7'h38//        lw   x2, 0(x0)      //x2 -> dmem[0]  = 7
            5'b01111: instr = 32'h005104B3;//7'h3C//        add  x9, x2, x5     //x9 = 7   +  11  = 18
            5'b10000: instr = 32'h008001EF;//7'h40//        jal  x3, end        //pc = end, x3 = 0x44             #Переход к end
            5'b10001: instr = 32'h00100113;//7'h44//        addi x2, x0, 1      //!x2= 0   +  1   = 1
            5'b10010: instr = 32'h00910133;//7'h48//end:    add  x2, x2, x9     //x2 = 7   +  18  = 25
            5'b10011: instr = 32'hFC21A023;//7'h4C//        sw   x2, -64(x3)    //      dmem[4] <- 25
            5'b10100: instr = 32'h00210063;//7'h50//done:   beq  x2, x2, done   //pc = (25 == 25)? done : pc + 4  #Истина, бесконечный цикл 
            default: instr = 0;
        endcase
endmodule

module dmem //Память данных
            (input logic clk, we, reset,
             input logic  [31:0] a, wd,
             output logic [31:0] rd);

    //DESCRIPTION: Память типа RAM доступна для чтения/записи. Имеет один вход
    //адреса a, выход считанных данных rd, а также вход записи
    //данных wd по сигналу разрешения записи we.
    
    logic [31:0] RAM[15:0];
    assign rd = RAM[a[31:0]]; //Выравнивание по слову

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
        else if (we) RAM[a[31:0]] <= wd;
    
endmodule
