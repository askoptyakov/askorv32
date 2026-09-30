`timescale 1ns/1ps
//==============================================================================================
// tb_stim - тест таймера STIM (stim.sv) через шину регистров
//==============================================================================================
//DESCRIPTION: Регистры (значения после сброса, разрядность, байтовая запись), режимы счёта вверх,
//вниз и вверх-вниз (период события обновления), предделитель, флаг UIF и его сброс записью 1,
//запрос прерывания irq, выход сравнения tim_out. Запуск: py hw/sim/run_periph_tests.py stim
module tb_stim;
    localparam string DEV = "stim";
    `include "periph_tb.svh"

    localparam logic [31:0] PR = 32'h00, CR = 32'h04, PER = 32'h08, PUL = 32'h0C, CNT = 32'h10, SR = 32'h14;
    localparam logic [31:0] CM_UP = 0, CM_DOWN = 1, CM_UPDOWN = 2, ARP = 1 << 2, EN = 1 << 3, UIE = 1 << 4;

    wire tim_out, irq;
    stim_top #(.MEMORY_TYPE(1'b1), .WIDTH(16)) dut
        (.clk(clk), .rst(rst), .Write(Write), .Addr(Addr), .WData(WData), .RData(RData),
         .tim_out(tim_out), .irq(irq));

    //Такты между событиями обновления (внутренний строб таймера)
    longint last_upd = -1, upd_period = 0, upd_count = 0;
    always @(posedge clk)
        if (dut.tim_update) begin
            if (last_upd >= 0) upd_period <= cycles - last_upd;
            last_upd  <= cycles;
            upd_count <= upd_count + 1;
        end

    //Запустить таймер и дождаться нескольких событий обновления, вернуть последний период
    task automatic measure(input logic [31:0] cr, input int events, output longint period);
        int start;
        start = upd_count;
        bus_wr(CR, cr);
        wait (upd_count >= start + events);
        @(negedge clk);
        period = upd_period;
        bus_wr(CR, 32'd0);
    endtask

    //Доля тактов с tim_out = 1 за n тактов
    task automatic duty(input int n, output int high);
        high = 0;
        repeat (n) begin @(posedge clk); if (tim_out) high++; end
    endtask

    longint p;
    int     h;
    logic [31:0] v;

    initial begin
        reset_dut();

        //#1 Значения после сброса
        check_rd(PR,  0, "сброс: PR");
        check_rd(CR,  0, "сброс: CR");
        check_rd(PER, 0, "сброс: PER");
        check_rd(PUL, 0, "сброс: PUL");
        check_rd(SR,  0, "сброс: SR");
        check(irq == 1'b0, "сброс: irq", irq, 0);

        //#2 Разрядность: PR, PER, PUL - 16 бит, CR - 5 бит, старшие читаются как 0
        bus_wr(PR,  32'hFFFF_1234); check_rd(PR,  32'h0000_1234, "PR 16 бит");
        bus_wr(PER, 32'hABCD_5678); check_rd(PER, 32'h0000_5678, "PER 16 бит");
        bus_wr(PUL, 32'h1111_9ABC); check_rd(PUL, 32'h0000_9ABC, "PUL 16 бит");
        bus_wr(CR,  32'hFFFF_FFE0); check_rd(CR,  32'h0000_0000, "CR 5 бит (старшие не пишутся)");
        bus_wr(CR,  32'h0000_0017); check_rd(CR,  32'h0000_0017, "CR 5 бит");
        bus_wr(CR,  32'd0);
        check_rd(32'h18, 0, "нет регистра 0x18 - читается 0");

        //#3 Байтовая запись: меняется только выбранный байт
        bus_wr(PER, 32'h0000_1234);
        bus_wrb(PER, 32'h0000_AB00, 4'b0010); check_rd(PER, 32'h0000_AB34, "байт 1 PER");
        bus_wrb(PER, 32'h0000_00CD, 4'b0001); check_rd(PER, 32'h0000_ABCD, "байт 0 PER");

        //#4 Счёт вверх: событие каждые (PER + 1) * (PR + 1) тактов
        bus_wr(PR, 0); bus_wr(PER, 9);
        measure(EN | CM_UP, 3, p);   check(p == 10, "вверх: период PER + 1", p, 10);
        bus_wr(PR, 3);
        measure(EN | CM_UP, 3, p);   check(p == 40, "вверх: период с предделителем", p, 40);

        //#5 Счёт вниз: событие на нуле, тот же период
        bus_wr(PR, 0); bus_wr(PER, 7);
        measure(EN | CM_DOWN, 3, p); check(p == 8, "вниз: период PER + 1", p, 8);

        //#6 Вверх-вниз: два события за период (в вершине и на нуле), между ними PER тактов
        bus_wr(PER, 6);
        measure(EN | CM_UPDOWN, 4, p); check(p == 6, "вверх-вниз: полупериод PER", p, 6);

        //#7 Текущее значение счётчика меняется и не превышает PER
        bus_wr(PER, 100); bus_wr(PR, 0); bus_wr(CR, EN | CM_UP);
        tick(20);
        bus_rd(CNT, v); check(v > 0 && v <= 100, "CNT считает", v, 20);
        bus_wr(CR, 0);

        //#8 Флаг UIF: ставится событием, сбрасывается записью 1, запись 0 не сбрасывает
        bus_wr(SR, 1);
        bus_wr(PER, 4); bus_wr(CR, EN | CM_UP);
        tick(12);
        bus_wr(CR, 0);
        check_rd(SR, 1, "UIF после события");
        bus_wr(SR, 0); check_rd(SR, 1, "запись 0 не сбрасывает UIF");
        bus_wr(SR, 1); check_rd(SR, 0, "запись 1 сбрасывает UIF");

        //#9 Прерывание: irq = UIF & UIE (через регистр), без UIE - нет
        bus_wr(CR, EN | CM_UP);
        tick(12);
        check(irq == 1'b0, "без UIE прерывания нет", irq, 0);
        bus_wr(CR, EN | UIE | CM_UP);
        tick(2);
        check(irq == 1'b1, "UIE: запрос прерывания", irq, 1);
        bus_wr(CR, 0);
        bus_wr(SR, 1);
        tick(2);
        check(irq == 1'b0, "сброс UIF снимает запрос", irq, 0);

        //#10 Выход сравнения: tim_out = 1, пока CNT < PUL (счёт вверх, период 10 тактов)
        bus_wr(PER, 9); bus_wr(PUL, 3); bus_wr(CR, EN | CM_UP);
        tick(5);
        duty(100, h); check(h == 30, "выход: 3 из 10 тактов", h, 30);
        bus_wr(PUL, 7);
        tick(12);
        duty(100, h); check(h == 70, "выход: 7 из 10 тактов", h, 70);
        bus_wr(CR, 0);

        //#11 Выключенный таймер стоит: событий нет
        begin
            longint n0;
            n0 = upd_count;
            tick(50);
            check(upd_count == n0, "выключенный таймер не считает", upd_count, n0);
        end

        finish_tests();
    end
endmodule
