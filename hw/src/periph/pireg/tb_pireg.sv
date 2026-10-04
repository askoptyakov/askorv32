`timescale 1ns/1ps
//==============================================================================================
// tb_pireg - тест ПИ-регулятора (pireg.sv): работа от процессора, прямые связи, пределы,
//            замкнутый контур «напряжение с ограничением тока» на модели выпрямителя
//==============================================================================================
//DESCRIPTION: Четыре экземпляра на одной шине (выбор - биты адреса [27:24]):
//  0 - dut: без внешних входов (как при работе только через процессор);
//  1 - dl:  LIM_EN, TRK_EN, RUN_EN - входы lim_i, trk_i, run_i задаёт тест;
//  2 - pu:  регулятор напряжения, LIM_EN: предел - выход регулятора тока pc;
//  3 - pc:  регулятор тока, TRK_EN: предел интегратора - выход регулятора напряжения pu.
//Модель выпрямителя: управление u (тики угла) -> напряжение U = 4 * u (единицы обратной связи),
//ток I = U * 1000 / R; каждый «сектор» (60 эл. град.) оба регулятора получают U и I стробом.
//Проверяется: значения после сброса; P и I по формулам; пределы OMAX и 0, флаги LIM и LOW;
//CLR и предустановка INT; шаг по прямой связи (EN, fb_stb, out_stb, FB = fb_i); прерывание;
//внешние lim_i, trk_i, run_i; контур: стабилизация напряжения, переход на ограничение тока при
//снижении R, возврат к напряжению без перерегулирования.
//Запуск: py hw/sim/run_periph_tests.py pireg
module tb_pireg;
    localparam string DEV = "pireg";
    `include "periph_tb.svh"

    localparam logic [31:0] CR = 32'h00, SP = 32'h04, KP = 32'h08, KI = 32'h0C, OMAX = 32'h10,
                            FB = 32'h14, OUT = 32'h18, SR = 32'h1C, INT = 32'h20;
    localparam logic [31:0] EN = 1 << 0, STEP = 1 << 1, IE = 1 << 2, CLR = 1 << 3;
    localparam logic [31:0] RDY = 1 << 0, LIM = 1 << 1, LOW = 1 << 2, RUN = 1 << 3, BUSY = 1 << 8;
    localparam logic [31:0] D0 = 32'h0000_0000, D1 = 32'h0100_0000, PU = 32'h0200_0000, PC = 32'h0300_0000;

    //Шина на четыре экземпляра
    logic [3:0][31:0] rd;
    logic [3:0] wr_sel;
    always_comb for (int i = 0; i < 4; i++) wr_sel[i] = (Addr[25:24] == 2'(i));
    assign RData = rd[Addr[25:24]];

    //Прямые связи
    logic [15:0] fb0 = '0, fb1 = '0, lim1 = 16'hFFFF, trk1 = 16'hFFFF;
    logic        stb0 = 1'b0, stb1 = 1'b0, run1 = 1'b1;
    logic [15:0] out0, out1, out_u, out_c;
    logic        ostb0, ostb1, ostb_u, ostb_c, irq0, irq1, irq_u, irq_c;
    logic [15:0] fb_u = '0, fb_c = '0;
    logic        stb_uc = 1'b0;

    pireg_top #(.MEMORY_TYPE(1'b1), .OMAX_INIT(16'd3000)) dut
        (.clk(clk), .rst(rst), .Write(wr_sel[0] ? Write : 4'b0), .Addr(Addr), .WData(WData), .RData(rd[0]),
         .fb_i(fb0), .fb_stb(stb0), .lim_i(16'd0), .trk_i(16'd0), .run_i(1'b0),
         .out_o(out0), .out_stb(ostb0), .irq(irq0));
    pireg_top #(.MEMORY_TYPE(1'b1), .LIM_EN(1'b1), .TRK_EN(1'b1), .RUN_EN(1'b1)) dl
        (.clk(clk), .rst(rst), .Write(wr_sel[1] ? Write : 4'b0), .Addr(Addr), .WData(WData), .RData(rd[1]),
         .fb_i(fb1), .fb_stb(stb1), .lim_i(lim1), .trk_i(trk1), .run_i(run1),
         .out_o(out1), .out_stb(ostb1), .irq(irq1));
    pireg_top #(.MEMORY_TYPE(1'b1), .LIM_EN(1'b1)) pu
        (.clk(clk), .rst(rst), .Write(wr_sel[2] ? Write : 4'b0), .Addr(Addr), .WData(WData), .RData(rd[2]),
         .fb_i(fb_u), .fb_stb(stb_uc), .lim_i(out_c), .trk_i(16'd0), .run_i(1'b1),
         .out_o(out_u), .out_stb(ostb_u), .irq(irq_u));
    pireg_top #(.MEMORY_TYPE(1'b1), .TRK_EN(1'b1)) pc
        (.clk(clk), .rst(rst), .Write(wr_sel[3] ? Write : 4'b0), .Addr(Addr), .WData(WData), .RData(rd[3]),
         .fb_i(fb_c), .fb_stb(stb_uc), .lim_i(16'd0), .trk_i(out_u), .run_i(1'b1),
         .out_o(out_c), .out_stb(ostb_c), .irq(irq_c));

    logic [31:0] v;
    int n;

    //Шаг процессором: FB, STEP, ожидание RDY; результат - OUT
    task automatic cpu_step(input logic [31:0] base, input logic [15:0] f, output logic [31:0] o);
        bus_wr(base | SR, RDY);
        bus_wr(base | FB, f);
        bus_wr(base | CR, STEP);
        do bus_rd(base | SR, o); while (!o[0]);
        bus_rd(base | OUT, o);
    endtask

    //Строб прямой связи на один такт
    task automatic link_step0(input logic [15:0] f);
        @(negedge clk); fb0 = f; stb0 = 1'b1;
        @(negedge clk); stb0 = 1'b0;
        tick(8);
    endtask
    task automatic link_step1(input logic [15:0] f);
        @(negedge clk); fb1 = f; stb1 = 1'b1;
        @(negedge clk); stb1 = 1'b0;
        tick(8);
    endtask

    //Модель выпрямителя и сектор: оба регулятора получают U и I
    int R = 2000, U = 0, I = 0, Umax = 0;
    task automatic sector();
        U = 4 * out_u;
        I = U * 1000 / R;
        @(negedge clk); fb_u = 16'(U); fb_c = 16'(I); stb_uc = 1'b1;
        @(negedge clk); stb_uc = 1'b0;
        tick(8);
    endtask

    initial begin
        reset_dut();

        //#1 Значения после сброса
        check_rd(D0 | CR,   0,     "сброс: CR");
        check_rd(D0 | OMAX, 3000,  "сброс: OMAX = OMAX_INIT");
        check_rd(D0 | OUT,  0,     "сброс: OUT");
        check_rd(D0 | SR,   LOW | RUN, "сброс: SR = LOW, RUN");
        check_rd(D0 | INT,  0,     "сброс: INT");
        check_rd(D1 | OMAX, 16'hFFFF, "сброс: OMAX по умолчанию 0xFFFF");

        //#2 П-часть: KP = 1.0, e = 1000 - 900 = 100 -> OUT = 100; ошибка в OUT[31:16]
        bus_wr(D0 | SP, 1000); bus_wr(D0 | KP, 4096); bus_wr(D0 | KI, 0);
        cpu_step(D0, 900, v);
        check(v[15:0] == 100, "KP = 1, e = 100: OUT = 100", v[15:0], 100);
        check(v[31:16] == 100, "OUT[31:16] - ошибка e", v[31:16], 100);
        bus_wr(D0 | KP, 4096 * 3 / 2);
        cpu_step(D0, 900, v);
        check(v[15:0] == 150, "KP = 1.5: OUT = 150", v[15:0], 150);
        check_rd(D0 | FB, 900, "FB - записанное значение");

        //#3 И-часть: KI = 0.5 - за шаг +50
        bus_wr(D0 | KP, 0); bus_wr(D0 | KI, 2048);
        cpu_step(D0, 900, v); check(v[15:0] == 50,  "KI = 0.5: шаг 1 - 50", v[15:0], 50);
        cpu_step(D0, 900, v); check(v[15:0] == 100, "шаг 2 - 100", v[15:0], 100);
        cpu_step(D0, 900, v); check(v[15:0] == 150, "шаг 3 - 150", v[15:0], 150);
        check_rd(D0 | INT, 150 * 4096, "INT = 150 * 2^FRAC");

        //#4 Верхний предел OMAX: выход и интегратор не выше, флаг LIM; обратно - сразу
        bus_wr(D0 | OMAX, 170);
        cpu_step(D0, 900, v); check(v[15:0] == 170, "OMAX = 170: OUT = 170", v[15:0], 170);
        cpu_step(D0, 900, v); check(v[15:0] == 170, "OMAX: OUT держится", v[15:0], 170);
        bus_rd(D0 | SR, v);   check(v[1] && !v[2], "SR.LIM", v, LIM | RUN);
        check_rd(D0 | INT, 170 * 4096, "интегратор не выше OMAX << FRAC");
        cpu_step(D0, 1100, v); check(v[15:0] == 120, "e = -100: OUT = 170 - 50 = 120 (без «накопленного» сверху)", v[15:0], 120);
        bus_rd(D0 | SR, v);   check(!v[1] && !v[2], "в пределах: ни LIM, ни LOW", v, RUN);

        //#5 Нижний предел 0: KP = 2, e = -1000 -> OUT = 0, LOW; интегратор не ниже 0
        bus_wr(D0 | KP, 8192); bus_wr(D0 | KI, 4096 * 2);
        cpu_step(D0, 2000, v); check(v[15:0] == 0, "e = -1000: OUT = 0", v[15:0], 0);
        bus_rd(D0 | SR, v);   check(v[2] && !v[1], "SR.LOW", v, LOW | RUN);
        check_rd(D0 | INT, 0, "интегратор не ниже 0");

        //#6 Предустановка INT и CLR
        bus_wr(D0 | KP, 0); bus_wr(D0 | KI, 0); bus_wr(D0 | OMAX, 3000);
        bus_wr(D0 | INT, 1234 * 4096);
        cpu_step(D0, 1000, v); check(v[15:0] == 1234, "INT = 1234 << FRAC: OUT = 1234", v[15:0], 1234);
        bus_wr(D0 | CR, CLR);
        check_rd(D0 | OUT, 0, "CLR: OUT = 0");
        check_rd(D0 | INT, 0, "CLR: INT = 0");

        //#7 Прямая связь: при EN шаг по fb_stb, out_stb, FB = fb_i; без EN - нет шага
        bus_wr(D0 | KP, 4096); bus_wr(D0 | SR, RDY);
        link_step0(16'd700);
        check_rd(D0 | OUT, 0, "без EN строб прямой связи не делает шаг");
        bus_wr(D0 | CR, EN);
        n = 0;
        fork
            begin @(negedge clk); fb0 = 16'd700; stb0 = 1'b1; @(negedge clk); stb0 = 1'b0; end
            begin repeat (12) begin @(posedge clk); if (ostb0) n++; end end
        join
        check(n == 1, "EN: один строб out_stb", n, 1);
        check(out0 == 300, "EN: out_o = SP - fb_i = 300", out0, 300);
        check_rd(D0 | FB, 700, "FB = fb_i шага по прямой связи");
        bus_rd(D0 | SR, v); check(v[0], "RDY по шагу прямой связи", v, RDY | RUN);

        //#8 Прерывание IE
        check(irq0 == 1'b0, "без IE irq = 0", irq0, 0);
        bus_wr(D0 | CR, EN | IE); tick(2);
        check(irq0 == 1'b1, "IE: irq по RDY", irq0, 1);
        bus_wr(D0 | SR, RDY); tick(2);
        check(irq0 == 1'b0, "RDY сброшен - irq снят", irq0, 0);
        bus_wr(D0 | CR, 0);

        //#9 Внешние входы: lim_i ограничивает выход, trk_i - интегратор, run_i = 0 - стоп
        bus_wr(D1 | SP, 1000); bus_wr(D1 | KP, 4096); bus_wr(D1 | KI, 4096); bus_wr(D1 | CR, EN);
        lim1 = 16'd250;
        link_step1(16'd800);                                    //P = 200, I = 200 -> 400, предел 250
        check(out1 == 250, "lim_i = 250: OUT = 250", out1, 250);
        bus_rd(D1 | SR, v); check(v[1], "lim_i: SR.LIM", v, LIM);
        check_rd(D1 | INT, 200 * 4096, "интегратор 200 < 250");
        lim1 = 16'hFFFF; trk1 = 16'd300;
        link_step1(16'd800);                                    //I = 400 -> 300 (trk), P = 200 -> 500
        check_rd(D1 | INT, 300 * 4096, "trk_i = 300: интегратор не выше 300");
        check(out1 == 500, "trk_i ограничивает только интегратор: OUT = 200 + 300", out1, 500);
        run1 = 1'b0; tick(2);
        check(out1 == 0, "run_i = 0: OUT = 0", out1, 0);
        check_rd(D1 | INT, 0, "run_i = 0: INT = 0");
        bus_rd(D1 | SR, v); check(!v[3], "run_i = 0: SR.RUN = 0", v, 0);
        link_step1(16'd800);
        check(out1 == 0, "run_i = 0: шагов нет", out1, 0);
        run1 = 1'b1;

        //#10 Контур «напряжение с ограничением тока»: pu - U (задание 2000), pc - I (предел 1500).
        //Модель: U = 4 * u, I = U * 1000 / R. KP = 0.05, KI = 0.05 у обоих, u до 1000
        bus_wr(PU | SP, 2000); bus_wr(PU | KP, 205); bus_wr(PU | KI, 205); bus_wr(PU | OMAX, 1000);
        bus_wr(PC | SP, 1500); bus_wr(PC | KP, 205); bus_wr(PC | KI, 205); bus_wr(PC | OMAX, 1000);
        bus_wr(PU | CR, EN); bus_wr(PC | CR, EN);
        R = 2000;                                               //Лёгкая нагрузка: I = U / 2
        repeat (120) sector();
        check(U >= 1990 && U <= 2010, "R = 2000: напряжение стабилизировано 2000", U, 2000);
        check(I < 1500, "R = 2000: ток ниже предела", I, 1000);
        bus_rd(PU | SR, v); check(!v[1], "R = 2000: регулятор U не на пределе", v, 0);
        R = 1000;                                               //Тяжёлая: при 2000 ток был бы 2000
        repeat (120) sector();
        check(I >= 1490 && I <= 1510, "R = 1000: ток ограничен 1500", I, 1500);
        check(U < 1600, "R = 1000: напряжение снизилось", U, 1500);
        bus_rd(PU | SR, v); check(v[1], "R = 1000: регулятор U на пределе от регулятора тока", v, LIM);
        R = 4000;                                               //Нагрузку сняли - снова напряжение
        Umax = 0;
        repeat (120) begin sector(); if (U > Umax) Umax = U; end
        check(U >= 1990 && U <= 2010, "R = 4000: снова напряжение 2000", U, 2000);
        check(Umax <= 2200, "возврат без большого перерегулирования (до 10 %)", Umax, 2000);
        R = 1000;                                               //Резкий наброс нагрузки
        n = 0;
        repeat (40) begin sector(); if (I > 1800) n++; end
        check(n <= 3, "наброс нагрузки: ток выше 1800 не дольше 3 секторов", n, 0);
        repeat (80) sector();
        check(I >= 1490 && I <= 1510, "после наброса: ток 1500", I, 1500);

        finish_tests();
    end
endmodule
