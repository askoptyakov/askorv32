`timescale 1ns/1ps
//==============================================================================================
// tb_pico - CoreMark на PicoRV32 в Icarus Verilog (запускает run_pico.py)
//==============================================================================================
//DESCRIPTION: Та же карта памяти, что у tb_core askoRV32: IMEM с 0x00000000 (32 кБайт),
//DMEM с 0x10000000 (8 кБайт), консоль 0x1F00000C, код завершения 0x1F000000. Память отвечает
//через такт, как BSRAM в pico_top.v. Параметр FULL - как в pico_top.v.
//  +imem=<hex> +dmem=<hex>  - образы памяти (слова по 32 бит)
module tb_pico;
    parameter FULL = 0;
    reg clk = 0, resetn = 0;
    always #5 clk = ~clk;

    wire        mem_valid, mem_instr;
    reg         mem_ready = 0;
    wire [31:0] mem_addr, mem_wdata;
    wire [ 3:0] mem_wstrb;
    reg  [31:0] mem_rdata;

    picorv32 #(
        .ENABLE_IRQ(FULL), .ENABLE_FAST_MUL(FULL), .ENABLE_DIV(FULL),
        .BARREL_SHIFTER(FULL), .COMPRESSED_ISA(FULL)
    ) cpu (.clk(clk), .resetn(resetn), .trap(),
        .mem_valid(mem_valid), .mem_instr(mem_instr), .mem_ready(mem_ready),
        .mem_addr(mem_addr), .mem_wdata(mem_wdata), .mem_wstrb(mem_wstrb), .mem_rdata(mem_rdata),
        .irq(32'd0), .eoi());

    reg [31:0] imem [0:8191];
    reg [31:0] dmem [0:2047];
    reg [1023:0] f;
    integer i;
    initial begin
        for (i = 0; i < 8192; i = i + 1) imem[i] = 0;
        for (i = 0; i < 2048; i = i + 1) dmem[i] = 0;
        if ($value$plusargs("imem=%s", f)) $readmemh(f, imem);
        if ($value$plusargs("dmem=%s", f)) $readmemh(f, dmem);
        repeat (10) @(posedge clk);
        resetn <= 1;
    end

    reg [63:0] cycles = 0;
    always @(posedge clk) cycles <= cycles + 1;

    wire is_imem = mem_addr[31:15] == 0;
    wire is_dmem = mem_addr[31:13] == (32'h10000000 >> 13);
    always @(posedge clk) begin
        mem_ready <= 0;
        if (mem_valid && !mem_ready) begin
            mem_ready <= 1;
            if (is_imem) begin
                mem_rdata <= imem[mem_addr[14:2]];
                if (mem_wstrb[0]) imem[mem_addr[14:2]][ 7: 0] <= mem_wdata[ 7: 0];
                if (mem_wstrb[1]) imem[mem_addr[14:2]][15: 8] <= mem_wdata[15: 8];
                if (mem_wstrb[2]) imem[mem_addr[14:2]][23:16] <= mem_wdata[23:16];
                if (mem_wstrb[3]) imem[mem_addr[14:2]][31:24] <= mem_wdata[31:24];
            end else if (is_dmem) begin
                mem_rdata <= dmem[mem_addr[12:2]];
                if (mem_wstrb[0]) dmem[mem_addr[12:2]][ 7: 0] <= mem_wdata[ 7: 0];
                if (mem_wstrb[1]) dmem[mem_addr[12:2]][15: 8] <= mem_wdata[15: 8];
                if (mem_wstrb[2]) dmem[mem_addr[12:2]][23:16] <= mem_wdata[23:16];
                if (mem_wstrb[3]) dmem[mem_addr[12:2]][31:24] <= mem_wdata[31:24];
            end else begin
                mem_rdata <= 0;
                if (mem_wstrb != 0 && mem_addr == 32'h1F00000C) begin $write("%c", mem_wdata[7:0]); $fflush; end
                if (mem_wstrb != 0 && mem_addr == 32'h1F000000) begin
                    $display("RESULT %0s cycles=%0d", mem_wdata == 1 ? "PASS" : "FAIL", cycles);
                    $finish;
                end
            end
        end
        if (cycles > 64'd40_000_000) begin $display("RESULT TIMEOUT"); $finish; end
    end
    always @(posedge clk) if (cpu.trap) begin $display("RESULT TRAP pc=%h", cpu.reg_pc); $finish; end
endmodule
