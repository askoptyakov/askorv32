`timescale 1ns/1ps
//==============================================================================================
// tb_rect - тест блока «Выпрямитель» (rect.sv): СИФУ + регулятор CC/CV на модели выпрямителя
//==============================================================================================
//DESCRIPTION: СИФУ работает от своего имитатора сети (CR.SIM, ускоренная сеть: тик - 2 такта,
//сектор 60 эл. град. - 300 тиков). Модель выпрямителя и блока ADC: по каждому стробу tick_o через
//20 тактов на входы fb_u, fb_i приходят «средние за окно»: U = 4 * u (u - выход PI_U, угол =
//AMAX - u), I = U * 1000 / R. Проверяется: карта (SIFU - 0x00, PI_U - 0x40, PI_I - 0x80, 0xC0 - 0);
//tick_o - 6 стробов за период; пока EN = 0 (run = 0) регуляторы стоят; стабилизация напряжения при
//лёгкой нагрузке; ограничение тока при тяжёлой (PI_U на пределе от PI_I); возврат к напряжению;
//действующий угол СИФУ (AEFF) = AMAX - выход PI_U; EN = 0 - регуляторы в нуле, угол AMAX.
//Запуск: py hw/sim/run_periph_tests.py rect
module tb_rect;
    localparam string DEV = "rect";
    `include "periph_tb.svh"

    localparam logic [31:0] S_CR = 32'h00, S_DELAY = 32'h0C, S_WIDTH = 32'h08, S_DIV = 32'h10, S_SR = 32'h14,
                            S_SIMCFG = 32'h2C, S_AMAX = 32'h30;
    localparam logic [31:0] PU = 32'h40, PI = 32'h80;
    localparam logic [31:0] P_CR = 32'h00, P_SP = 32'h04, P_KP = 32'h08, P_KI = 32'h0C, P_OMAX = 32'h10,
                            P_OUT = 32'h18, P_SR = 32'h1C;
    localparam logic [31:0] EN = 1 << 0, DBL = 1 << 1, SIM = 1 << 2, FLT = 1 << 3, UEXT = 1 << 6;
    localparam int AMAX = 600;

    logic [15:0] fb_u = '0, fb_i = '0;
    logic        fb_stb = 1'b0;
    wire  vs1, vs2, vs3, vs4, vs5, vs6, grid_o, tk, irq;
    rect_top #(.MEMORY_TYPE(1'b1), .DIV_INIT(16'd1), .DELAY_INIT(12'd10), .WIDTH_INIT(12'd20),
               .AMAX_INIT(12'd3333)) dut
        (.clk(clk), .rst(rst), .Write(Write), .Addr(Addr), .WData(WData), .RData(RData),
         .sync_ab(1'b1), .sync_ba(1'b1), .sync_bc(1'b1), .sync_cb(1'b1), .sync_ca(1'b1), .sync_ac(1'b1),
         .vs1(vs1), .vs2(vs2), .vs3(vs3), .vs4(vs4), .vs5(vs5), .vs6(vs6), .grid_o(grid_o),
         .fb_u(fb_u), .fb_i(fb_i), .fb_u_stb(fb_stb), .fb_i_stb(fb_stb), .tick_o(tk), .irq(irq));

    //Модель выпрямителя и средних за окно: на каждый tick_o
    int R = 2000, U = 0, I = 0, Umax = 0, nticks = 0;
    always @(posedge clk) if (tk) begin
        nticks++;
        fork begin
            repeat (20) @(posedge clk);
            U = 4 * dut.u_out;
            I = U * 1000 / R;
            @(negedge clk); fb_u = 16'(U); fb_i = 16'(I); fb_stb = 1'b1;
            @(negedge clk); fb_stb = 1'b0;
        end join_none
    end

    logic [31:0] v;
    task automatic sectors(input int n);
        int t0 = nticks;
        while (nticks < t0 + n) @(posedge clk);
        tick(40);
    endtask

    initial begin
        reset_dut();

        //#1 Карта
        check_rd(S_CR, 32'h0000_000A, "SIFU (0x00): CR после сброса = DBL | FLT");
        check_rd(PU | P_OMAX, 3333, "PI_U (0x40): OMAX = AMAX_INIT");
        check_rd(PI | P_OMAX, 3333, "PI_I (0x80): OMAX = AMAX_INIT");
        check_rd(32'hC0, 0, "0xC0 - пусто");
        bus_wr(PU | P_SP, 1234); check_rd(PU | P_SP, 1234, "запись PI_U.SP");
        check_rd(PI | P_SP, 0, "PI_I.SP не тронут");

        //#2 Имитатор сети: 6 начал полуволн за период
        bus_wr(S_SIMCFG, {4'd0, 12'd10, 16'd300});
        bus_wr(S_AMAX, AMAX);
        bus_wr(PU | P_OMAX, AMAX); bus_wr(PI | P_OMAX, AMAX);
        bus_wr(PU | P_SP, 2000); bus_wr(PU | P_KP, 205); bus_wr(PU | P_KI, 205);
        bus_wr(PI | P_SP, 1500); bus_wr(PI | P_KP, 205); bus_wr(PI | P_KI, 205);
        bus_wr(PU | P_CR, 1); bus_wr(PI | P_CR, 1);
        bus_wr(S_CR, SIM | FLT | UEXT);                         //Без EN: импульсов нет
        tick(4 * 1800);
        nticks = 0;
        tick(2 * 3600);                                         //Два периода: 2 * 6 * 300 тиков по 2 такта
        check(nticks >= 11 && nticks <= 13, "tick_o: 6 стробов за период", nticks, 12);

        //#3 EN = 0 - регуляторы стоят, угол AMAX
        sectors(10);
        bus_rd(PU | P_OUT, v); check(v[15:0] == 0, "EN = 0: PI_U стоит, выход 0", v[15:0], 0);
        bus_rd(PU | P_SR, v); check(!v[3], "EN = 0: PI_U.SR.RUN = 0", v, 0);
        bus_rd(S_AMAX, v); check(v[27:16] == AMAX, "EN = 0: угол AEFF = AMAX", v[27:16], AMAX);

        //#4 EN - стабилизация напряжения (R = 2000: ток 1000 < 1500)
        bus_wr(S_CR, SIM | FLT | UEXT | EN);
        sectors(150);
        check(U >= 1990 && U <= 2010, "R = 2000: напряжение 2000", U, 2000);
        check(I < 1500, "R = 2000: ток ниже ограничения", I, 1000);
        bus_rd(PU | P_SR, v); check(v[3] && !v[1], "PI_U работает, не на пределе", v, 8);
        bus_rd(S_AMAX, v);
        check(int'(v[27:16]) == AMAX - int'(dut.u_out), "угол СИФУ = AMAX - выход PI_U", v[27:16], AMAX - dut.u_out);

        //#5 Тяжёлая нагрузка - ограничение тока
        R = 1000;
        sectors(150);
        check(I >= 1490 && I <= 1510, "R = 1000: ток ограничен 1500", I, 1500);
        bus_rd(PU | P_SR, v); check(v[1], "PI_U на пределе от PI_I", v, 2);

        //#6 Нагрузку сняли - снова напряжение без большого перерегулирования
        R = 4000; Umax = 0;
        repeat (150) begin sectors(1); if (U > Umax) Umax = U; end
        check(U >= 1990 && U <= 2010, "R = 4000: снова 2000", U, 2000);
        check(Umax <= 2200, "перерегулирование не больше 10 %", Umax, 2000);

        //#7 EN снят - регуляторы в нуле, угол AMAX
        bus_wr(S_CR, SIM | FLT | UEXT);
        sectors(3);
        check(dut.u_out == 0 && dut.i_out == 0, "EN = 0: выходы регуляторов 0", {dut.u_out, dut.i_out}, 0);
        bus_rd(S_AMAX, v); check(v[27:16] == AMAX, "EN = 0: угол AMAX", v[27:16], AMAX);

        finish_tests();
    end
endmodule
