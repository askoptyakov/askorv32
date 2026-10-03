`timescale 1ns/1ps
//==============================================================================================
// tb_sifu - тест СИФУ (sifu.sv) через шину регистров с моделью сети и платы синхронизации NSB
//==============================================================================================
//DESCRIPTION: Модель сети: период P тактов clk, линейные напряжения U_AB, U_BC = U_AB - 120 град.,
//U_CA = U_AB - 240 град.; оптроны NSB открыты (выход 0), пока напряжение своей полярности больше
//порога, то есть вне мёртвой зоны DZ тактов у каждого перехода через 0. Чтобы тест шёл быстро,
//сеть «ускорена»: полупериод H = 9000 тактов, тик ГПН - каждые 2 такта (DIV = 1) - 4500 тиков на
//полупериод, как 5000 у настоящей сети 50 Гц при 500 кГц.
//Проверяется: значения после сброса, разрядность и байтовая запись; полупериод HPER, флаги GRID,
//SYNC, LOST; положение импульсов каждого тиристора от начала его полуволны (ALPHA + DELAY тиков),
//длительность WIDTH, порядок VS1..VS6 через 60 град., сдвоенные импульсы; угол за пределом пилы -
//импульсов нет; ALPHA меняется только с новой полуволны; EN; пропадание сети - флаг LOSSF и
//прерывание; SYNCF, номер CH и прерывание; имитатор сети (SIM); фильтр помех (FLT).
//Запуск: py hw/sim/run_periph_tests.py sifu
module tb_sifu;
    localparam string DEV = "sifu";
    `include "periph_tb.svh"

    localparam logic [31:0] CR = 32'h00, ALPHA = 32'h04, WIDTH = 32'h08, DELAY = 32'h0C, DIV = 32'h10,
                            SR = 32'h14, HPER = 32'h18, CNT1 = 32'h1C, CNT2 = 32'h20, CNT3 = 32'h24,
                            GATE = 32'h28, SIMCFG = 32'h2C;
    localparam logic [31:0] EN = 1 << 0, DBL = 1 << 1, SIM = 1 << 2, FLT = 1 << 3, SIE = 1 << 4, LIE = 1 << 5;
    localparam logic [31:0] SR_GRID = 1 << 8, SR_SYNCF = 1 << 9, SR_LOSSF = 1 << 10, SR_LOST = 1 << 11;

    //Модель сети: время в тактах clk
    localparam int H  = 9000;            //Полупериод, тактов
    localparam int P  = 2 * H;
    int DZ = 150;                        //Мёртвая зона у перехода через 0, тактов (3 эл. град.); меняется в #14
    localparam int TICK = 2;             //Тактов на тик ГПН при DIV = 1

    logic grid_on = 1'b0;                //Сеть подана
    logic glitch  = 1'b0;                //Помеха на входе AB: оптрон на миг «закрывается» (1)
    logic stuck_ca = 1'b0;               //Оптрон CA «залип» открытым (0)
    longint t0 = 0;                      //Такт, с которого отсчитывается фаза сети
    int theta;                           //Фаза U_AB, тактов от перехода через 0 вверх
    always @(posedge clk) theta <= int'((cycles - t0) % P);

    //Оптрон полярности: открыт (0), когда фаза ph (такты от перехода через 0 вверх) в [DZ, H - DZ)
    function automatic logic opto_n(input int ph);
        int x = ((ph % P) + P) % P;
        return !(x >= DZ && x < H - DZ);
    endfunction
    wire n_ab = !grid_on |  opto_n(theta) | glitch;
    wire n_ba = !grid_on |  opto_n(theta - H);
    wire n_bc = !grid_on |  opto_n(theta - P / 3);
    wire n_cb = !grid_on |  opto_n(theta - P / 3 - H);
    wire n_ca = (!grid_on |  opto_n(theta - 2 * P / 3)) & !stuck_ca;
    wire n_ac = !grid_on |  opto_n(theta - 2 * P / 3 - H);

    wire vs1, vs2, vs3, vs4, vs5, vs6, grid_o, irq;
    sifu_top #(.MEMORY_TYPE(1'b1), .DIV_INIT(16'd89), .DELAY_INIT(12'd400), .WIDTH_INIT(12'd150)) dut
        (.clk(clk), .rst(rst), .Write(Write), .Addr(Addr), .WData(WData), .RData(RData),
         .sync_ab(n_ab), .sync_ba(n_ba), .sync_bc(n_bc), .sync_cb(n_cb), .sync_ca(n_ca), .sync_ac(n_ac),
         .vs1(vs1), .vs2(vs2), .vs3(vs3), .vs4(vs4), .vs5(vs5), .vs6(vs6), .grid_o(grid_o), .irq(irq));
    wire [6:1] vs = {vs6, vs5, vs4, vs3, vs2, vs1};

    //Начало полуволны тиристора k на входах (фаза сети, такты): VS1 - U_AB, VS2 - U_AC, VS3 - U_BC,
    //VS4 - U_BA, VS5 - U_CA, VS6 - U_CB; открывается оптрон через DZ после перехода через 0
    function automatic int win_start(input int k);
        case (k)
            1: return DZ;                     //U_AB > 0
            2: return 2 * P / 3 + H + DZ - P; //U_AC > 0 (= -U_CA): 60 град.
            3: return P / 3 + DZ;             //U_BC: 120 град.
            4: return H + DZ;                 //U_BA: 180 град.
            5: return 2 * P / 3 + DZ;         //U_CA: 240 град.
            6: return P / 3 + H + DZ;         //U_CB: 300 град.
        endcase
    endfunction

    //Фронты и длительности импульсов: последний фронт (фаза сети) и последняя длительность
    int rise_ph[6:1], width_cy[6:1], n_pulse[6:1];
    longint rise_t[6:1];
    logic [6:1] vs_q = '0;
    always @(posedge clk) begin
        vs_q <= vs;
        for (int k = 1; k <= 6; k++) begin
            if (vs[k] & ~vs_q[k]) begin rise_ph[k] <= theta; rise_t[k] <= cycles; n_pulse[k] <= n_pulse[k] + 1; end
            if (~vs[k] & vs_q[k]) width_cy[k] <= int'(cycles - rise_t[k]);
        end
    end
    task automatic clear_pulses();
        for (int k = 1; k <= 6; k++) n_pulse[k] = 0;
    endtask

    //Подождать n полупериодов сети
    task automatic halfwaves(input int n);
        tick(n * H);
    endtask

    //Задержка фронта импульса от начала полуволны на входе, в тиках ГПН (по модулю периода)
    function automatic int lag_ticks(input int k);
        int dph = ((rise_ph[k] - win_start(k)) % P + P) % P;
        return dph / TICK;
    endfunction

    logic [31:0] v;
    int lag, exp_lag, w;
    logic f_ab_seen = 1'b0;              //Выход фильтра AB был 1 (помеха прошла)
    always @(posedge clk) if (dut.sync_f[0]) f_ab_seen <= 1'b1;

    initial begin
        reset_dut();

        //#1 Значения после сброса
        check_rd(CR,     32'h0000_000A, "сброс: CR = DBL | FLT");
        check_rd(ALPHA,  32'h0000_0FFF, "сброс: ALPHA = 4095 (импульсов нет)");
        check_rd(WIDTH,  150,           "сброс: WIDTH");
        check_rd(DELAY,  400,           "сброс: DELAY");
        check_rd(DIV,    89,            "сброс: DIV");
        check_rd(SIMCFG, {4'd0, 12'd56, 16'd1667}, "сброс: SIMCFG");
        check_rd(GATE,   0,             "сброс: GATE");
        bus_rd(SR, v);
        check(v[5:0] == 6'h3F && !v[8] && !v[9] && !v[10] && v[11], "сброс: SR - оптроны закрыты, сети нет, LOST", v, 32'h0000_083F);
        check_rd(CNT1, 32'hFFF, "сброс: пила стоит на 4095");
        check(vs == 0 && irq == 0 && grid_o == 0, "сброс: выходы, grid_o и irq в 0", {vs, grid_o, irq}, 0);

        //#2 Разрядность и байтовая запись
        bus_wr(ALPHA, 32'hFFFF_F123); check_rd(ALPHA, 32'h123, "ALPHA 12 бит");
        bus_wr(DIV,   32'h1234_5678); check_rd(DIV,   32'h5678, "DIV 16 бит");
        bus_wr(CR,    32'hFFFF_FFC0); check_rd(CR,    0, "CR 6 бит");
        bus_wrb(DELAY, 32'h0000_0F00, 4'b0010); check_rd(DELAY, 32'hF90, "DELAY: байт 1");
        bus_wr(SIMCFG, 32'hFFFF_FFFF); check_rd(SIMCFG, 32'h0FFF_FFFF, "SIMCFG 28 бит");
        check_rd(32'h30, 0, "нет регистра 0x30 - читается 0");

        //#3 Сеть подана: полупериод, флаги, пилы. DIV = 1 (тик - 2 такта)
        bus_wr(CR, DBL | FLT);
        bus_wr(DIV, 1); bus_wr(DELAY, 400); bus_wr(WIDTH, 150); bus_wr(ALPHA, 0);
        t0 = cycles; grid_on = 1'b1;
        halfwaves(5);
        bus_rd(HPER, v);
        check(v >= H / TICK - 1 && v <= H / TICK + 1, "HPER = полупериод в тиках", v, H / TICK);
        bus_rd(SR, v);
        check(v[8] && !v[11], "сеть есть: GRID = 1, LOST = 0", v, SR_GRID);
        check(grid_o == 1'b1, "сеть есть: выход grid_o = 1", grid_o, 1);
        check(v[9], "SYNCF после начала полуволн", v, SR_SYNCF);
        bus_wr(SR, SR_SYNCF);
        bus_rd(SR, v);
        check(!v[9], "SYNCF сброшен записью 1", v, 0);
        wait (theta == H / 2);               //Середина полуволны AB: пила ~(H / 2 - DZ) / TICK
        bus_rd(CNT1, v); check(v > 2100 && v < 2200, "CNT1 - пила пары AB", v, (H / 2 - DZ) / TICK);
        check(n_pulse[1] == 0 && vs == 0, "EN = 0: импульсов нет", vs, 0);

        //#4 Импульсы без сдваивания: ALPHA = 0 - фронт через DELAY тиков после начала полуволны
        //(плюс фильтр: 3 тика), длительность WIDTH тиков
        bus_wr(CR, EN | FLT);
        halfwaves(3);
        clear_pulses();
        halfwaves(2);
        for (int k = 1; k <= 6; k++) begin
            lag = lag_ticks(k); exp_lag = 400 + 3;
            check(n_pulse[k] == 1, $sformatf("VS%0d: один импульс за период", k), n_pulse[k], 1);
            check(lag >= exp_lag - 1 && lag <= exp_lag + 2, $sformatf("VS%0d: фронт через DELAY тиков (ALPHA 0)", k), lag, exp_lag);
            w = width_cy[k] / TICK;
            check(w >= 149 && w <= 151, $sformatf("VS%0d: длительность WIDTH", k), w, 150);
        end
        //Порядок: VS(k+1) через 60 град. (P / 6) после VSk
        for (int k = 1; k <= 5; k++) begin
            lag = int'(rise_t[k + 1] - rise_t[k]);
            lag = ((lag % P) + P) % P;
            check(lag >= P / 6 - 2 * TICK && lag <= P / 6 + 2 * TICK, $sformatf("VS%0d -> VS%0d: 60 эл. град.", k, k + 1), lag, P / 6);
        end

        //#5 ALPHA = 1000 тиков: фронт сдвигается на ALPHA
        bus_wr(ALPHA, 1000);
        halfwaves(3);
        for (int k = 1; k <= 6; k++) begin
            lag = lag_ticks(k); exp_lag = 1400 + 3;
            check(lag >= exp_lag - 1 && lag <= exp_lag + 2, $sformatf("VS%0d: фронт через ALPHA + DELAY", k), lag, exp_lag);
        end

        //#6 Сдвоенные импульсы: каждый тиристор получает второй импульс вместе со следующим (через 60 град.)
        bus_wr(CR, EN | DBL | FLT);
        halfwaves(2);
        clear_pulses();
        halfwaves(2);
        for (int k = 1; k <= 6; k++)
            check(n_pulse[k] == 2, $sformatf("DBL: VS%0d - два импульса за период", k), n_pulse[k], 2);
        bus_rd(GATE, v);
        check(v[5:0] == 6'(vs) , "GATE[5:0] = выходы", v, 32'(vs));

        //#7 Угол за пределом пилы (ALPHA + DELAY >= 4095) - импульсов нет
        bus_wr(ALPHA, 3700);
        halfwaves(2);
        clear_pulses();
        halfwaves(2);
        for (int k = 1; k <= 6; k++)
            check(n_pulse[k] == 0, $sformatf("ALPHA + DELAY > 4094: VS%0d без импульсов", k), n_pulse[k], 0);
        //Импульс обрезается на 4094: ALPHA + DELAY = 4000, WIDTH 150 - остаётся 95 тиков
        bus_wr(CR, EN | FLT);
        bus_wr(ALPHA, 3600);
        halfwaves(3);
        w = width_cy[1] / TICK;
        check(w >= 93 && w <= 96, "импульс обрезан концом пилы (4095)", w, 95);

        //#8 ALPHA меняется только с новой полуволны: запись посреди полуволны до импульса не сдвигает
        //его (иначе при ALPHA = 0 пришёл бы импульс на 400 тиках, а по старому ALPHA - на 2400)
        bus_wr(ALPHA, 2000);
        halfwaves(3);
        wait (theta == DZ + 300 * TICK);    //Полуволна AB, пила ~300, импульса VS1 ещё не было
        clear_pulses();
        bus_wr(ALPHA, 0);
        wait (theta == H);                   //Конец полуволны AB
        check(n_pulse[1] == 1, "ALPHA посреди полуволны: у VS1 один импульс", n_pulse[1], 1);
        lag = lag_ticks(1);
        check(lag >= 2402 && lag <= 2405, "ALPHA посреди полуволны: импульс по старому углу", lag, 2403);
        halfwaves(2);
        lag = lag_ticks(1);
        check(lag >= 402 && lag <= 405, "новый ALPHA - со следующей полуволны", lag, 403);

        //#9 EN = 0 гасит выходы сразу
        bus_wr(CR, FLT);
        clear_pulses();
        halfwaves(2);
        check(n_pulse[1] + n_pulse[2] + n_pulse[3] + n_pulse[4] + n_pulse[5] + n_pulse[6] == 0, "EN = 0: импульсов нет", 0, 0);

        //#10 SYNCF, CH и прерывание по началу полуволны
        bus_wr(SR, SR_SYNCF | SR_LOSSF);
        bus_wr(CR, FLT | SIE);
        wait (irq == 1'b1);
        bus_rd(SR, v);
        check(v[9], "SIE: irq и SYNCF", v, SR_SYNCF);
        check(v[18:16] >= 1 && v[18:16] <= 6, "CH - номер тиристора 1..6", v[18:16], 1);
        wait (theta == win_start(4) + 100);  //После начала полуволны VS4 (U_BA)
        bus_rd(SR, v);
        check(v[18:16] == 4, "CH = 4 после начала полуволны U_BA", v[18:16], 4);
        bus_wr(SR, SR_SYNCF);
        tick(3);
        check(irq == 1'b0, "SYNCF сброшен - irq снят", irq, 0);
        bus_wr(CR, FLT);

        //#11 Пропадание сети: GRID = 0, через 8192 тика - LOST и флаг LOSSF, прерывание LIE
        bus_wr(CR, EN | FLT | LIE);
        grid_on = 1'b0;
        tick(20);
        bus_rd(SR, v);
        check(!v[8], "сети нет: GRID = 0", v, 0);
        check(vs == 0, "сети нет: выходы в 0", vs, 0);
        check(grid_o == 1'b0, "сети нет: выход grid_o = 0", grid_o, 0);
        tick(8192 * TICK + 100);
        bus_rd(SR, v);
        check(v[10] && v[11], "LOSSF и LOST", v, SR_LOSSF | SR_LOST);
        check(irq == 1'b1, "LIE: irq по LOSSF", irq, 1);
        bus_wr(SR, SR_LOSSF);
        tick(3);
        check(irq == 1'b0, "LOSSF сброшен - irq снят", irq, 0);
        bus_wr(CR, FLT);

        //#12 Имитатор сети: входы NSB закрыты (сети нет), SIM = 1. Сектор 1500 тиков - полупериод 4500
        bus_wr(SIMCFG, {4'd0, 12'd75, 16'd1500});
        bus_wr(ALPHA, 500); bus_wr(DELAY, 0);
        bus_wr(CR, SIM | FLT | EN);
        tick(4 * P);
        check_rd(HPER, 4500, "SIM: HPER = 3 сектора");
        bus_rd(SR, v);
        check(v[8] && !v[11], "SIM: GRID = 1, LOST = 0", v, SR_GRID);
        clear_pulses();
        tick(P);
        for (int k = 1; k <= 6; k++)
            check(n_pulse[k] == 1, $sformatf("SIM: VS%0d - один импульс за период", k), n_pulse[k], 1);
        for (int k = 1; k <= 5; k++) begin
            lag = int'(rise_t[k + 1] - rise_t[k]);
            lag = ((lag % P) + P) % P;
            check(lag >= 1500 * TICK - 2 * TICK && lag <= 1500 * TICK + 2 * TICK, $sformatf("SIM: VS%0d -> VS%0d через сектор", k, k + 1), lag, 1500 * TICK);
        end
        bus_wr(CR, FLT);

        //#13 Фильтр: помеха на входе AB короче 3 тиков (FLT = 1) на выход фильтра не проходит; при
        //FLT = 0 (отсчёт каждый такт) проходит, но пилу не перезапускает - полярность та же
        bus_wr(DELAY, 400); bus_wr(ALPHA, 0);
        bus_wr(CR, EN | FLT);
        t0 = cycles; grid_on = 1'b1;
        halfwaves(4);
        wait (theta == DZ + 200 * TICK);      //Полуволна AB, пила ~200
        f_ab_seen = 1'b0;
        glitch = 1'b1;                        //Вход AB «закрылся» на 2 тика = 4 такта
        tick(2 * TICK);
        glitch = 1'b0;
        tick(10);
        check(!f_ab_seen, "FLT = 1: помеха 2 тика не прошла фильтр", f_ab_seen, 0);
        bus_rd(CNT1, v);
        check(v > 190, "FLT = 1: пила не перезапущена", v, 200);
        bus_wr(CR, EN);
        halfwaves(2);
        wait (theta == DZ + 200 * TICK);
        f_ab_seen = 1'b0;
        glitch = 1'b1;
        tick(2 * TICK);
        glitch = 1'b0;
        tick(10);
        check(f_ab_seen, "FLT = 0: помеха 4 такта прошла фильтр", f_ab_seen, 1);
        bus_rd(CNT1, v);
        check(v > 190, "FLT = 0: та же полярность - пила не перезапущена", v, 200);
        clear_pulses();
        halfwaves(2);
        check(n_pulse[1] == 1, "FLT = 0: после помехи VS1 - один импульс за период", n_pulse[1], 1);

        //#14 Широкая мёртвая зона (малое напряжение сети): окно оптрона короче ALPHA + DELAY - импульс
        //всё равно приходит, в мёртвой зоне (пила идёт до начала следующей полуволны)
        bus_wr(CR, EN | FLT);
        DZ = 1200;                            //Окно 9000 - 2 * 1200 = 6600 тактов = 3300 тиков
        bus_wr(ALPHA, 3100);                  //t_on = 3500 тиков: после конца окна (3300)
        halfwaves(4);
        clear_pulses();
        halfwaves(2);
        for (int k = 1; k <= 6; k++) begin
            lag = lag_ticks(k); exp_lag = 3500 + 3;
            check(n_pulse[k] == 1, $sformatf("мёртвая зона 1200: VS%0d - импульс есть", k), n_pulse[k], 1);
            check(lag >= exp_lag - 1 && lag <= exp_lag + 2, $sformatf("мёртвая зона 1200: VS%0d через ALPHA + DELAY", k), lag, exp_lag);
        end
        DZ = 150;

        //#15 Оптрон CA «залип» открытым: смены полярности у пары CA/AC нет - импульсов VS5, VS2 нет,
        //через 8192 тика - LOST; остальные тиристоры работают
        bus_wr(ALPHA, 0);
        halfwaves(2);
        stuck_ca = 1'b1;
        halfwaves(2);
        clear_pulses();
        halfwaves(4);
        check(n_pulse[5] == 0 && n_pulse[2] == 0, "CA залип: у VS5 и VS2 импульсов нет", {n_pulse[5], n_pulse[2]}, 0);
        check(n_pulse[1] == 2 && n_pulse[3] == 2 && n_pulse[4] == 2 && n_pulse[6] == 2, "CA залип: VS1, VS3, VS4, VS6 работают", n_pulse[1], 2);
        bus_rd(SR, v);
        check(v[11], "CA залип: LOST", v, SR_LOST);
        stuck_ca = 1'b0;
        halfwaves(4);
        bus_rd(SR, v);
        check(!v[11], "CA в порядке: синхронизация вернулась", v, 0);
        clear_pulses();
        halfwaves(2);
        check(n_pulse[5] == 1 && n_pulse[2] == 1, "CA в порядке: VS5 и VS2 снова с импульсами", {n_pulse[5], n_pulse[2]}, 32'h0000_0101);

        finish_tests();
    end
endmodule
