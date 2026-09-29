//==============================================================================================
// pico_top - система на PicoRV32 для сравнения с askoRV32 по ресурсам и Fmax (только синтез)
//==============================================================================================
//DESCRIPTION: Ядро PicoRV32 + 16 кБайт BSRAM (8 IMEM + 8 DMEM, как у askoRV32; у PicoRV32 одна
//шина, поэтому память общая) + регистр светодиодов. Память отвечает через такт.
//  FULL = 0 - RV32I в конфигурации по умолчанию;
//  FULL = 1 - RV32IMC: IRQ, быстрый умножитель (DSP), деление, barrel shifter, сжатые команды.
//Верхний модуль с нужным FULL генерирует run_pico.py.
module pico_top #(parameter FULL = 0) (
    input  wire       clk, rst_n,
    output reg  [5:0] led
);
    reg [3:0] rcnt = 0;
    wire resetn = &rcnt;
    always @(posedge clk) if (!rst_n) rcnt <= 0; else if (!resetn) rcnt <= rcnt + 1;

    wire        mem_valid, mem_instr;
    reg         mem_ready;
    wire [31:0] mem_addr, mem_wdata;
    wire [ 3:0] mem_wstrb;
    reg  [31:0] mem_rdata;

    picorv32 #(
        .ENABLE_IRQ(FULL), .ENABLE_MUL(0), .ENABLE_FAST_MUL(FULL), .ENABLE_DIV(FULL),
        .BARREL_SHIFTER(FULL), .COMPRESSED_ISA(FULL)
    ) cpu (
        .clk(clk), .resetn(resetn), .trap(),
        .mem_valid(mem_valid), .mem_instr(mem_instr), .mem_ready(mem_ready),
        .mem_addr(mem_addr), .mem_wdata(mem_wdata), .mem_wstrb(mem_wstrb), .mem_rdata(mem_rdata),
        .irq(32'd0), .eoi()
    );

    //Память побайтно: так Gowin собирает её в BSRAM со стробами записи
    reg [7:0] m0 [0:4095], m1 [0:4095], m2 [0:4095], m3 [0:4095];
    wire [11:0] wa = mem_addr[13:2];
    always @(posedge clk) begin
        mem_ready <= 1'b0;
        if (mem_valid && !mem_ready) begin
            if (mem_addr[31:14] == 0) begin
                mem_rdata <= {m3[wa], m2[wa], m1[wa], m0[wa]};
                if (mem_wstrb[0]) m0[wa] <= mem_wdata[ 7: 0];
                if (mem_wstrb[1]) m1[wa] <= mem_wdata[15: 8];
                if (mem_wstrb[2]) m2[wa] <= mem_wdata[23:16];
                if (mem_wstrb[3]) m3[wa] <= mem_wdata[31:24];
            end else if (mem_wstrb[0]) led <= ~mem_wdata[5:0];
            mem_ready <= 1'b1;
        end
    end
endmodule
