//Размер памяти BSRAM_SIZE можно изменять только кратно 8кБайт(от 8 до 32)
module mem #(parameter bit MEMORY_TYPE =    0, //Тип памяти: 1 - BSRAM;       0 - Синтезированная;
             parameter int SYNTH_SIZE  =   10, //Размер синтезированной памяти в словах по 4 Байта;
             parameter int BSRAM_SIZE  =    8, //Размер памяти BSRMA в кБайт
             parameter     INIT_FILE   = "mem_init/i.mem")
            (input logic clk, reset, re, 
             input logic  [3 :0] wstrb,
             input logic  [31:0] a,
             input logic  [31:0] wd,
             output logic [31:0] rd);

    localparam int CLUSTERS = BSRAM_SIZE / 8;

    //DESCRIPTION: Память типа RAM доступна для чтения/записи. Имеет один вход
    //адреса a, выход считанных данных rd, а также вход записи
    //данных wd по сигналам разрешения записи отделных байтов wstrb[3:0]. 
    generate if (MEMORY_TYPE) begin   //#1 - BSRAM
        //Создание BSRAM
        logic [31:0] bsram_out [CLUSTERS-1:0];
        for (genvar i = 0; i<CLUSTERS; i++) begin : cluster
            logic [31:0] dout;
            for (genvar j = 0; j<4; j++) begin : sector
                logic [23:0] dout_empty;
                SP #(   .READ_MODE(1'b0),
                        .WRITE_MODE(2'b00),
                        .BIT_WIDTH(8),
                        .BLK_SEL({1'b0, i[1:0]}),
                        .RESET_MODE("SYNC")                       
                    ) bsram (
                        .DO({dout_empty[23:0],dout[(j*8)+7:j*8]}),
                        .CLK(clk), .OCE(1'b0), .CE(re), .RESET(reset),
                        .WRE(wstrb[j]), .BLKSEL({1'b0, a[14], a[13]}),
                        .AD({a[12:2],{3{1'b0}}}),
                        .DI({{24{1'b0}},wd[(j*8)+7:j*8]}));
            end
            assign bsram_out[i] = dout;
        end
        //Мультиплексирование выходов блоков памяти BSRAM
        case (CLUSTERS)
                  1: assign rd = bsram_out[0];
            default: begin
                        logic [CLUSTERS>>2'd2 : 0] a_r;
                        always_ff @(posedge clk, posedge reset)
                            if (reset) a_r <= 0;
                            else a_r <= a[11+(CLUSTERS>>2'd2) : 11];
                        assign rd = bsram_out[a_r];
                     end
        endcase
    end else begin                  //#0 - Синтезированная память
        logic [31:0] mem [0:SYNTH_SIZE-1];
        initial $readmemh(INIT_FILE, mem);
        assign rd = mem[a>>2'd2];
        always @(posedge clk) begin
            if (wstrb[0]) mem[a>>2'd2][7:0]  <= wd[7:0];
            if (wstrb[1]) mem[a>>2'd2][15:8] <= wd[15:8];
            if (wstrb[2]) mem[a>>2'd2][23:16] <= wd[23:16];
            if (wstrb[3]) mem[a>>2'd2][31:24] <= wd[31:24];
        end
    end
    endgenerate    
endmodule