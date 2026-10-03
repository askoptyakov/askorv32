`timescale 1ns/1ps
//==============================================================================================
// tb_adc121 - тест контроллера АЦП ADC121S051 (adc121.sv) через шину регистров
//==============================================================================================
//DESCRIPTION: Модель АЦП по листу данных TI: спад CS# выдаёт на DOUT первый ведущий ноль, каждый
//спад SCLK - следующий бит кадра {4'b0000, код[11:0]}, при CS# = 1 - DOUT висит (подтяжка, 1).
//Задержка DOUT после фронта - T_OUT (выход АЦП + два цифровых изолятора туда и обратно). Модель
//считает такты SCLK в кадре и проверяет, что их ровно 16 и SCLK в покое 0.
//Проверяется: значения после сброса, разрядность, байтовая запись; частота SCLK = f / (2 (DIV + 1));
//одиночный запуск START; код в DATA при разных кодах и делителях; непрерывный режим, CNT, период PER;
//среднее MEAN и сумма SUM по 2^AVGSH; ошибка кадра (платы нет - DOUT в 1): ERR, отсчёт не идёт в
//DATA и CNT; флаги и их сброс записью 1; прерывания DIE, AIE, EIE; большая задержка DOUT при
//медленном SCLK. Запуск: py hw/sim/run_periph_tests.py adc121
module tb_adc121;
    localparam string DEV = "adc121";
    `include "periph_tb.svh"

    localparam logic [31:0] CR = 32'h00, DIVR = 32'h04, AVG = 32'h08, PER = 32'h0C, DATA = 32'h10,
                            MEAN = 32'h14, SUM = 32'h18, SR = 32'h1C, CNT = 32'h20;
    localparam logic [31:0] EN = 1 << 0, START = 1 << 1, DIE = 1 << 2, AIE = 1 << 3, EIE = 1 << 4;
    localparam logic [31:0] DRDY = 1 << 0, ARDY = 1 << 1, ERR = 1 << 2, BUSY = 1 << 8;

    //Модель ADC121S051
    real       T_OUT  = 40.0;            //Задержка DOUT, нс
    logic [11:0] code = 12'h000;         //Что «измеряет» АЦП
    logic      board  = 1'b1;            //Плата подключена (иначе DOUT висит в 1)
    logic [15:0] word;
    int        nfall = 0, nrise = 0, frames = 0, bad_frames = 0;
    logic      in_frame = 1'b0;
    logic      dout_m = 1'b1;
    wire       cs_n, sclk, irq;
    wire       sdo = board ? dout_m : 1'b1;

    always @(negedge cs_n) begin
        in_frame = 1'b1;
        word = {4'b0000, code};
        nfall = 0; nrise = 0;
        if (sclk !== 1'b0) bad_frames++;                    //SCLK в покое - 0
        dout_m <= #(T_OUT) word[15];
    end
    always @(posedge cs_n) if (in_frame) begin
        in_frame = 1'b0;
        frames++;
        if (nfall != 16 || nrise != 16) bad_frames++;
        dout_m <= #(T_OUT) 1'b1;                            //Третье состояние - подтяжка
    end
    always @(posedge sclk) if (!cs_n) nrise++;
    always @(negedge sclk) if (!cs_n) begin
        nfall++;
        if (nfall < 16) dout_m <= #(T_OUT) word[15 - nfall];
    end

    adc121_top #(.MEMORY_TYPE(1'b1), .DIV_INIT(8'd3), .AVGSH_INIT(4'd8)) dut
        (.clk(clk), .rst(rst), .Write(Write), .Addr(Addr), .WData(WData), .RData(RData),
         .adc_cs_n(cs_n), .adc_sclk(sclk), .adc_sdo(sdo), .irq(irq));

    //От спада CS# до первого подъёма SCLK, такты
    longint cs_fall = 0, first_rise = 0;
    logic   wait_rise = 1'b0;
    always @(negedge cs_n) begin cs_fall = cycles; wait_rise = 1'b1; end
    always @(posedge sclk) if (wait_rise) begin first_rise = cycles; wait_rise = 1'b0; end

    //Период SCLK, тактов clk (по двум последним подъёмам)
    longint t_r1 = 0, t_r2 = 0;
    always @(posedge sclk) begin t_r1 <= t_r2; t_r2 <= cycles; end

    logic [31:0] v, c0, d0;
    int n;

    //Одно преобразование START и ожидание DRDY
    task automatic single(output logic [31:0] d);
        bus_wr(SR, DRDY | ARDY | ERR);
        bus_wr(CR, START);
        do bus_rd(SR, d); while (!(d & (DRDY | ERR)));
        bus_rd(DATA, d);
    endtask

    initial begin
        reset_dut();

        //#1 Значения после сброса
        check_rd(CR,   0,               "сброс: CR");
        check_rd(DIVR, 32'h0000_2203,   "сброс: DIV = 3, QUIET = 2, CSS = 2");
        check_rd(AVG,  8,               "сброс: AVGSH = 8");
        check_rd(PER,  0,               "сброс: PER");
        check_rd(DATA, 0,               "сброс: DATA");
        check_rd(SR,   0,               "сброс: SR");
        check(cs_n === 1'b1 && sclk === 1'b0, "сброс: CS# = 1, SCLK = 0", {cs_n, sclk}, 2'b10);

        //#2 Разрядность и байтовая запись
        bus_wr(PER, 32'hFFFF_FFFF); check_rd(PER, 32'h00FF_FFFF, "PER 24 бита");
        bus_wr(PER, 0);
        bus_wr(AVG, 32'hFFFF_FFF5); check_rd(AVG, 5, "AVGSH 4 бита");
        bus_wrb(DIVR, 32'h0000_3500, 4'b0010); check_rd(DIVR, 32'h0000_3503, "DIV: байт 1 - QUIET, CSS");
        bus_wr(CR, 32'hFFFF_FFDC); check_rd(CR, 32'h0000_001C, "CR: START не читается, EN не записан");
        bus_wr(CR, 0);
        bus_wr(DIVR, 32'h0000_2203); bus_wr(AVG, 8);
        check_rd(32'h24, 0, "нет регистра 0x24 - читается 0");

        //#3 Одиночный запуск: 16 тактов SCLK, код в DATA, частота SCLK = f / 8 при DIV = 3
        code = 12'hA5C;
        single(v);
        check(v[11:0] == 12'hA5C, "START: код в DATA", v[11:0], 12'hA5C);
        check(bad_frames == 0 && frames == 1, "кадр: 16 тактов SCLK, SCLK в покое 0", bad_frames, 0);
        check(t_r2 - t_r1 == 8, "SCLK = f / (2 (DIV + 1)) = f / 8", t_r2 - t_r1, 8);
        bus_rd(SR, v);
        check(v[0] && !v[2] && !v[8], "SR: DRDY, ошибки нет, не занят", v, DRDY);
        check(v[31:16] == 16'h0A5C, "SR.FRAME - сырой кадр", v[31:16], 16'h0A5C);
        check_rd(CNT, 1, "CNT = 1");
        bus_wr(SR, DRDY);
        bus_rd(SR, v); check(!v[0], "DRDY сброшен записью 1", v, 0);

        //#4 Разные коды и делители. Запас на задержку DOUT - период SCLK минус 2 такта синхронизатора:
        //при 50 МГц и задержке 40 нс годен DIV >= 2 (при DIV = 1 бит приходит вровень с выборкой)
        for (int dv = 2; dv <= 6; dv++) begin
            bus_wr(DIVR, 32'h0000_2200 | dv);
            code = 12'(dv * 613 + 7);
            single(v);
            check(v[11:0] == code, $sformatf("DIV = %0d: код", dv), v[11:0], code);
            check(t_r2 - t_r1 == 2 * (dv + 1), $sformatf("DIV = %0d: период SCLK", dv), t_r2 - t_r1, 2 * (dv + 1));
        end
        code = 12'hFFF; single(v); check(v[11:0] == 12'hFFF, "код 0xFFF", v[11:0], 12'hFFF);
        code = 12'h000; single(v); check(v[11:0] == 12'h000, "код 0x000", v[11:0], 12'h000);
        code = 12'h800; single(v); check(v[11:0] == 12'h800, "код 0x800", v[11:0], 12'h800);
        check(bad_frames == 0, "все кадры - по 16 тактов", bad_frames, 0);

        //#5 Большая задержка DOUT (длинный кабель, изоляторы) при медленном SCLK: DIV = 7, T_OUT = 120 нс
        bus_wr(DIVR, 32'h0000_2207);
        T_OUT = 120.0; code = 12'h3C3; single(v);
        check(v[11:0] == 12'h3C3, "DOUT через 120 нс, SCLK = f / 16", v[11:0], 12'h3C3);
        T_OUT = 40.0;
        bus_wr(DIVR, 32'h0000_2203);

        //#6 Непрерывный режим, среднее по 2^4 = 16 отсчётам, CNT
        bus_wr(AVG, 4);
        bus_rd(CNT, c0);
        code = 12'd1000;
        bus_wr(SR, DRDY | ARDY | ERR);
        bus_wr(CR, EN);
        do bus_rd(SR, v); while (!v[1]);                    //Первое среднее
        bus_wr(SR, ARDY);
        code = 12'd1001;                                    //Половина отсчётов 1000, половина 1001...
        do bus_rd(SR, v); while (!v[1]);
        bus_wr(SR, ARDY);
        do bus_rd(SR, v); while (!v[1]);                    //...это среднее - целиком по 1001
        bus_rd(MEAN, v); check(v == 1001, "MEAN = 1001", v, 1001);
        bus_rd(SUM, v);  check(v == 16 * 1001, "SUM = 16 * 1001", v, 16 * 1001);
        bus_rd(CNT, v);  check(v - c0 >= 32, "CNT растёт в непрерывном режиме", v - c0, 32);
        //Дробное среднее: чередование 1000/1001 через SUM
        bus_wr(CR, 0);
        tick(200);

        //#7 Период PER: 2000 тактов между запусками
        bus_wr(PER, 2000);
        bus_rd(CNT, c0);
        bus_wr(CR, EN);
        tick(20000);
        bus_wr(CR, 0);
        bus_rd(CNT, v);
        check(v - c0 >= 9 && v - c0 <= 11, "PER = 2000: 10 отсчётов за 20000 тактов", v - c0, 10);
        bus_wr(PER, 0);
        tick(200);

        //#8 Платы нет (DOUT в 1): ERR, DATA и CNT не меняются
        bus_rd(CNT, c0);
        bus_rd(DATA, d0);
        board = 1'b0;
        bus_wr(SR, DRDY | ARDY | ERR);
        bus_wr(CR, START);
        do bus_rd(SR, v); while (v[8] || !(v & (DRDY | ERR)));
        check(v[2] && !v[0], "платы нет: ERR, без DRDY", v, ERR);
        check(v[31:16] == 16'hFFFF, "платы нет: кадр 0xFFFF", v[31:16], 16'hFFFF);
        bus_rd(DATA, v); check(v[11:0] == d0[11:0], "платы нет: DATA прежний", v[11:0], d0[11:0]);
        bus_rd(CNT, v);  check(v == c0, "платы нет: CNT не растёт", v, c0);
        bus_wr(SR, ERR);
        bus_rd(SR, v); check(!v[2], "ERR сброшен записью 1", v, 0);
        board = 1'b1;

        //#9 Прерывания: DIE, AIE, EIE
        check(irq == 1'b0, "irq: без разрешений 0", irq, 0);
        bus_wr(CR, DIE);
        code = 12'd77; bus_wr(CR, DIE | START);
        wait (irq == 1'b1);
        bus_rd(DATA, v); check(v[11:0] == 77, "DIE: irq по новому отсчёту", v[11:0], 77);
        bus_wr(SR, DRDY); tick(3);
        check(irq == 1'b0, "DIE: DRDY сброшен - irq снят", irq, 0);
        bus_wr(AVG, 2); bus_wr(CR, AIE | EN);
        wait (irq == 1'b1);
        bus_rd(SR, v); check(v[1], "AIE: irq по новому среднему", v, ARDY);
        bus_wr(CR, 0); tick(200); bus_wr(SR, DRDY | ARDY | ERR); tick(3);
        board = 1'b0; bus_wr(CR, EIE | START);
        wait (irq == 1'b1);
        bus_rd(SR, v); check(v[2], "EIE: irq по ошибке кадра", v, ERR);
        board = 1'b1; bus_wr(CR, 0); bus_wr(SR, ERR);

        //#10 CSINV - вывод CS инвертирован: в покое 0, в кадре 1; CSS = 5 - от CS до SCLK 5 полупериодов
        bus_wr(CR, 32'h20);
        tick(3);
        check(cs_n === 1'b0, "CSINV: в покое вывод CS = 0", cs_n, 0);
        bus_wr(CR, 0); tick(3);
        check(cs_n === 1'b1, "CSINV = 0: в покое CS# = 1", cs_n, 1);
        bus_wr(DIVR, 32'h0000_5203);
        cs_fall = 0; first_rise = 0;
        code = 12'h5A5; single(v);
        check(v[11:0] == 12'h5A5, "CSS = 5: код", v[11:0], 12'h5A5);
        check(first_rise - cs_fall == 5 * 4, "CSS = 5: от CS# до SCLK 5 полупериодов", first_rise - cs_fall, 20);
        bus_wr(DIVR, 32'h0000_2203);

        finish_tests();
    end
endmodule
