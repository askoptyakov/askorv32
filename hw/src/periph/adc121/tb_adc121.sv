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
//медленном SCLK; вход компаратора; такт АЦП отдельно от такта шины (96 МГц против 50 МГц, частоты
//несоизмеримы): переход управления и кадров между тактами, пропадание захвата rPLL, предельная
//частота отсчётов. Запуск: py hw/sim/run_periph_tests.py adc121
module tb_adc121;
    localparam string DEV = "adc121";
    `include "periph_tb.svh"

    localparam logic [31:0] CR = 32'h00, DIVR = 32'h04, AVG = 32'h08, PER = 32'h0C, DATA = 32'h10,
                            MEAN = 32'h14, SUM = 32'h18, SR = 32'h1C, CNT = 32'h20, FCLK = 32'h24;

    //Такт АЦП: 96 МГц (полпериода 5.2 нс), такт шины - 50 МГц; SCLK и кадр считаются в тактах АЦП
    localparam real ADC_HALF = 5.2;
    localparam logic [31:0] ADC_HZ = 32'd96153846;
    logic   adc_clk = 1'b0, adc_lock = 1'b1;
    longint acycles = 0;
    always #(ADC_HALF) adc_clk = ~adc_clk;
    always @(posedge adc_clk) acycles <= acycles + 1;
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

    logic cmp_pin = 1'b1;                //Выход компаратора LM311: 1 - норма, 0 - перегрузка
    adc121_top #(.MEMORY_TYPE(1'b1), .DIV_INIT(8'd3), .AVGSH_INIT(4'd8), .CSS_INIT(4'd2), .QUIET_INIT(4'd1),
                 .CMP_EN(1'b1), .CLK_HZ(ADC_HZ)) dut
        (.clk(clk), .rst(rst), .adc_clk(adc_clk), .adc_lock(adc_lock),
         .Write(Write), .Addr(Addr), .WData(WData), .RData(RData),
         .adc_cs_n(cs_n), .adc_sclk(sclk), .adc_sdo(sdo), .adc_cmp(cmp_pin), .irq(irq));

    //От спада CS# до первого подъёма SCLK, тактов АЦП
    longint cs_fall = 0, first_rise = 0;
    logic   wait_rise = 1'b0;
    always @(negedge cs_n) begin cs_fall = acycles; wait_rise = 1'b1; end
    always @(posedge sclk) if (wait_rise) begin first_rise = acycles; wait_rise = 1'b0; end

    //Период SCLK, тактов АЦП (по двум последним подъёмам)
    longint t_r1 = 0, t_r2 = 0;
    always @(posedge sclk) begin t_r1 <= t_r2; t_r2 <= acycles; end

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
        check_rd(DIVR, 32'h0000_2103,   "сброс: DIV = 3, QUIET = 1, CSS = 2");
        check_rd(FCLK, ADC_HZ,          "FCLK - частота такта АЦП");
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
        bus_wr(CR, 32'hFFFF_FF1C); check_rd(CR, 32'h0000_001C, "CR: START не читается, EN не записан");
        bus_wr(CR, 0);
        bus_wr(DIVR, 32'h0000_2203); bus_wr(AVG, 8);
        check_rd(32'h28, 0, "нет регистра 0x28 - читается 0");
        bus_wr(FCLK, 32'h1234); check_rd(FCLK, ADC_HZ, "FCLK только читается");

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

        //#4 Разные коды и делители. Запас на задержку DOUT - период SCLK минус 3 такта (синхронизатор и
        //выходной регистр): при 96 МГц и задержке 40 нс годен DIV >= 3 (при DIV = 2 запас 31 нс)
        for (int dv = 3; dv <= 7; dv++) begin
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

        //#7 Период PER в тактах АЦП: 3846 тактов (40 мкс) между запусками - 10 отсчётов за 400 мкс
        bus_wr(PER, 3846);
        bus_rd(CNT, c0);
        bus_wr(CR, EN);
        tick(20000);
        bus_wr(CR, 0);
        bus_rd(CNT, v);
        check(v - c0 >= 9 && v - c0 <= 11, "PER = 3846 тактов АЦП: 10 отсчётов за 400 мкс", v - c0, 10);
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
        tick(8);
        check(cs_n === 1'b0, "CSINV: в покое вывод CS = 0", cs_n, 0);
        bus_wr(CR, 0); tick(8);
        bad_frames = 0;                                         //CSINV качнул CS без SCLK - это не кадр
        check(cs_n === 1'b1, "CSINV = 0: в покое CS# = 1", cs_n, 1);
        bus_wr(DIVR, 32'h0000_5203);
        cs_fall = 0; first_rise = 0;
        code = 12'h5A5; single(v);
        check(v[11:0] == 12'h5A5, "CSS = 5: код", v[11:0], 12'h5A5);
        check(first_rise - cs_fall == 5 * 4, "CSS = 5: от CS# до SCLK 5 полупериодов", first_rise - cs_fall, 20);
        bus_wr(DIVR, 32'h0000_2203);

        //#11 Вход cmp (компаратор ADC_C): по умолчанию активный 0; CMP - состояние, CMPF - флаг, CIE
        bus_wr(SR, 32'h8);
        bus_rd(SR, v); check(!v[9] && !v[3], "cmp = 1: не активен, флага нет", v, 0);
        bus_wr(CR, 32'h80);                                     //CIE
        cmp_pin = 1'b0; tick(6);
        bus_rd(SR, v); check(v[9] && v[3], "cmp = 0: CMP и CMPF", v, 32'h208);
        check(irq == 1'b1, "CIE: irq по CMPF", irq, 1);
        cmp_pin = 1'b1; tick(6);
        bus_rd(SR, v); check(!v[9] && v[3], "cmp вернулся: CMP = 0, CMPF держится", v, 32'h8);
        bus_wr(SR, 32'h8); tick(3);
        bus_rd(SR, v); check(!v[3], "CMPF сброшен записью 1", v, 0);
        check(irq == 1'b0, "irq снят", irq, 0);
        bus_wr(CR, 32'h40);                                     //CPOL = 1: активный 1
        tick(6);
        bus_rd(SR, v); check(v[9] && v[3], "CPOL = 1: cmp = 1 активен", v, 32'h208);
        bus_wr(CR, 0); bus_wr(SR, 32'h8);

        //#12 Захват rPLL пропал и вернулся: часть на такте АЦП сброшена и забирает текущие настройки;
        //START, записанный без захвата, выполняется после его возврата
        check(bad_frames == 0, "до #12 все кадры - по 16 тактов SCLK", bad_frames, 0);
        bus_wr(DIVR, 32'h0000_1104);
        tick(10);
        //Дважды: между проходами - один кадр, переключатель «кадр принят» в другом состоянии - ложного кадра нет ни при каком
        for (int k = 0; k < 2; k++) begin
            bus_wr(SR, DRDY | ARDY | ERR);
            adc_lock = 1'b0; tick(20);
            check(cs_n === 1'b1 && sclk === 1'b0, "нет захвата rPLL: CS# = 1, SCLK = 0", {cs_n, sclk}, 2'b10);
            code = 12'h6B1;
            bus_wr(CR, START);                                      //Запрос ждёт такта АЦП
            tick(20);
            bus_rd(SR, v); check(!v[0] && !v[8], "нет захвата: кадра нет", v, 0);
            adc_lock = 1'b1;
            do bus_rd(SR, v); while (!(v & (DRDY | ERR)));
            bus_rd(DATA, v); check(v[11:0] == 12'h6B1, "захват вернулся: START выполнен, код", v[11:0], 12'h6B1);
            check(t_r2 - t_r1 == 10, "захват вернулся: DIV = 4 (записан до пропадания)", t_r2 - t_r1, 10);
            check(bad_frames == 0, "захват: кадры по 16 тактов SCLK", bad_frames, 0);
        end

        //#13 Предельная частота: SCLK = 96 / 12 = 8 МГц (DIV 5), CSS = QUIET = 1 - кадр 34 * 6 + 1 = 205
        //тактов АЦП, 469 тыс. отсчётов/с: за 200 мкс - 93-94 отсчёта, коды верные, кадр сразу за кадром
        bus_wr(DIVR, 32'h0000_1105);
        code = 12'hC35;
        bus_wr(SR, DRDY | ARDY | ERR);
        bus_wr(CR, EN);
        tick(100);                                              //Первый кадр начался
        bus_rd(CNT, c0);
        tick(10000);                                            //200 мкс
        bus_rd(CNT, v);
        n = v - c0;
        check(n >= 92 && n <= 95, "8 МГц, CSS = QUIET = 1: 469 тыс. отсчётов/с", n, 94);
        bus_wr(CR, 0);
        bus_rd(DATA, v); check(v[11:0] == 12'hC35, "8 МГц: код", v[11:0], 12'hC35);
        bus_rd(SR, v); check(!v[2], "8 МГц: ошибок кадра нет", v, 0);
        check(bad_frames == 0, "все кадры - по 16 тактов SCLK", bad_frames, 0);

        finish_tests();
    end
endmodule
