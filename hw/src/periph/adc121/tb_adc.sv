`timescale 1ns/1ps
//==============================================================================================
// tb_adc - тест блока АЦП из нескольких каналов (adc.sv): два канала - две модели ADC121S051
//==============================================================================================
//DESCRIPTION: Канал 0 (плата напряжения) и канал 1 (плата тока) - свои выводы и модели АЦП с разными
//кодами; такт АЦП 96 МГц, шина 50 МГц. Проверяется: регистры канала 1 - со смещения 0x40, канал 2
//(нет его) читается как 0; значения после сброса из общих параметров и векторов по каналам (CSINV);
//одиночные преобразования каналов независимы (свой код, свой счётчик); непрерывные - оба канала;
//общее закрытие окна: средние обоих каналов за одно окно, стробы wstb_o в один такт; прерывание -
//ИЛИ каналов. Логика самого канала проверена в tb_adc121.sv. Запуск: py hw/sim/run_periph_tests.py adc121
module tb_adc;
    localparam string DEV = "adc";
    `include "periph_tb.svh"

    localparam logic [31:0] CR = 32'h00, DIVR = 32'h04, DATA = 32'h10, SR = 32'h1C, CNT = 32'h20, WMEAN = 32'h28;
    localparam logic [31:0] CH1 = 32'h40, CH2 = 32'h80;
    localparam logic [31:0] EN = 1 << 0, START = 1 << 1, DIE = 1 << 2, WCLOSE = 1 << 9;
    localparam logic [31:0] DRDY = 1 << 0, WRDY = 1 << 4;

    logic adc_clk = 1'b0;
    always #(5.2) adc_clk = ~adc_clk;

    //Модели ADC121S051: DOUT меняется по спаду SCLK, первый ведущий ноль - по спаду CS#
    logic [1:0][11:0] code = '{12'd0, 12'd0};
    wire  [1:0] cs_n, sclk;
    logic [1:0] dout = 2'b11;
    for (genvar k = 0; k < 2; k++) begin : g_model
        logic [15:0] word;
        int nfall;
        always @(negedge cs_n[k]) begin word = {4'b0000, code[k]}; nfall = 0; dout[k] <= #(30) word[15]; end
        always @(posedge cs_n[k]) dout[k] <= #(30) 1'b1;
        always @(negedge sclk[k]) if (!cs_n[k]) begin
            nfall++;
            if (nfall < 16) dout[k] <= #(30) word[15 - nfall];
        end
    end

    logic win = 1'b0;
    wire [1:0][15:0] wmean;
    wire [1:0] wstb;
    wire irq;
    adc_top #(.MEMORY_TYPE(1'b1), .NCH(2), .DIV_INIT(8'd5), .AVGSH_INIT(4'd4), .CSS_INIT(4'd1), .QUIET_INIT(4'd1),
              .CSINV_INIT(4'b0000), .CMP_EN(4'b0000), .CLK_HZ(32'd96000000), .WIN_EN(1'b1)) dut
        (.clk(clk), .rst(rst), .adc_clk(adc_clk), .adc_lock(1'b1),
         .Write(Write), .Addr(Addr), .WData(WData), .RData(RData),
         .adc_cs_n(cs_n), .adc_sclk(sclk), .adc_sdo(dout), .adc_cmp(2'b11),
         .win_i(win), .wmean_o(wmean), .wstb_o(wstb), .irq(irq));

    int both = 0;
    always @(posedge clk) if (wstb == 2'b11) both++;

    logic [31:0] v, c0, c1;

    task automatic single(input logic [31:0] base, output logic [31:0] d);
        bus_wr(base | SR, DRDY);
        bus_wr(base | CR, START);
        do bus_rd(base | SR, d); while (!d[0]);
        bus_rd(base | DATA, d);
    endtask

    initial begin
        reset_dut();

        //#1 Карта: канал 0 - 0x00, канал 1 - 0x40, канала 2 нет
        check_rd(DIVR,       32'h0000_1105, "канал 0: DIV после сброса");
        check_rd(CH1 | DIVR, 32'h0000_1105, "канал 1: DIV после сброса");
        bus_wr(CH1 | DIVR, 32'h0000_1106);
        check_rd(CH1 | DIVR, 32'h0000_1106, "запись в канал 1");
        check_rd(DIVR,       32'h0000_1105, "канал 0 не тронут");
        bus_wr(CH1 | DIVR, 32'h0000_1105);
        check_rd(CH2 | DIVR, 0, "канала 2 нет - 0");
        check_rd(32'h24, 32'd96000000, "FCLK канала 0");

        //#2 Одиночные преобразования - каналы независимы
        code[0] = 12'd451; code[1] = 12'd2114;
        single(32'h0, v);   check(v[11:0] == 12'd451,  "канал 0: код платы напряжения", v[11:0], 451);
        single(CH1, v);     check(v[11:0] == 12'd2114, "канал 1: код платы тока", v[11:0], 2114);
        check_rd(CNT, 1, "канал 0: CNT = 1");
        check_rd(CH1 | CNT, 1, "канал 1: CNT = 1");

        //#3 Непрерывные преобразования обоих, общее окно: средние каналов за одно окно, стробы в один такт
        bus_wr(CR, EN); bus_wr(CH1 | CR, EN);
        tick(200);
        @(negedge clk); win = 1'b1; @(negedge clk); win = 1'b0;     //Начало окна
        tick(60);
        both = 0;
        tick(5000);
        @(negedge clk); win = 1'b1; @(negedge clk); win = 1'b0;
        tick(60);
        check(both == 1, "общее окно: стробы обоих каналов в один такт", both, 1);
        check(wmean[0] == 16'd7216,  "wmean канала 0 = 451 * 16", wmean[0], 7216);
        check(wmean[1] == 16'd33824, "wmean канала 1 = 2114 * 16", wmean[1], 33824);
        bus_rd(CH1 | WMEAN, v);
        check(v[15:0] == 16'd33824 && v[27:16] > 40, "канал 1: WMEAN и число отсчётов", v, 33824);
        bus_rd(CNT, c0); bus_rd(CH1 | CNT, c1);
        check(c0 > 40 && c1 > 40, "оба канала считают отсчёты", c1, 40);

        //#4 Окно процессором - в одном канале
        bus_wr(CH1 | SR, WRDY); bus_wr(SR, WRDY);
        bus_wr(CH1 | CR, EN | WCLOSE);
        tick(60);
        bus_rd(CH1 | SR, v); check(v[4], "WCLOSE канала 1: WRDY канала 1", v, WRDY);
        bus_rd(SR, v);       check(!v[4], "канал 0: окно не закрыто", v, 0);

        //#5 Прерывание - ИЛИ каналов
        bus_wr(CR, 0); bus_wr(CH1 | CR, 0); tick(400);
        bus_wr(SR, DRDY); bus_wr(CH1 | SR, DRDY); tick(3);
        check(irq == 1'b0, "без разрешений irq = 0", irq, 0);
        bus_wr(CH1 | CR, DIE | START);
        wait (irq == 1'b1);
        bus_rd(CH1 | SR, v); check(v[0], "irq от канала 1 (DIE)", v, DRDY);
        bus_wr(CH1 | SR, DRDY); tick(3);
        check(irq == 1'b0, "DRDY канала 1 сброшен - irq снят", irq, 0);

        finish_tests();
    end
endmodule
