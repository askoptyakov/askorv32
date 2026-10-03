//==============================================================================================
// sifu_top - СИФУ: система импульсно-фазового управления трёхфазным мостовым тиристорным
//            выпрямителем (6 тиристоров VS1..VS6, синхронизация от платы NSB)
//==============================================================================================
//DESCRIPTION: Перенос проекта test_nsb (ветка test_nsb, hw/Documents/test_nsb/src/top.v) в
//периферию askoRV32: та же структура - фильтры filter_2bit, генераторы пилы OnePulse_3 на каждую
//пару фаз, делитель my_divider, сдвиг DELAY_RC_COMPENSATION, - но угол, сдвиг, длительность
//импульса и делитель задаёт процессор через регистры. Подробно - README.md в этой папке, тест -
//tb_sifu.sv, библиотека на Си - fw/Core/Inc/sifu.h, fw/Core/Src/sifu.c.
//
//Путь сигнала:
//  входы NSB (активный 0: оптрон открыт, линейное напряжение данной полярности больше порога)
//  -> [SIM: имитатор сети sifu_simgen вместо входов]
//  -> filter_2bit (синхронизатор 2 триггера + реверсивный счётчик 0..3 с гистерезисом)
//  -> OnePulse_3 x3 (пары AB/BA, BC/CB, CA/AC): пила - счётчик тиков ГПН от начала полуволны
//     (смены полярности) до начала следующей, через мёртвую зону; импульс, пока
//     ALPHA + DELAY <= пила < ALPHA + DELAY + WIDTH
//  -> сдвоенные импульсы (своему тиристору и предыдущему по очереди) -> разрешение EN и «сеть есть»
//  -> выходы vs1..vs6 (через регистр); выход grid_o - «сеть есть» (индикатор).
//Тик ГПН - раз в DIV + 1 тактов clk (my_divider): 45 МГц / 90 = 500 кГц, полупериод сети 50 Гц -
//5000 тиков, 1 тик = 0.036 эл. град. Пила 12 бит, насыщается на 4095 (без переполнения).
//
//Карта регистров (по шаблону periph_regs, hw/src/periph/periph_regs.sv):
//<>0x00 CR     - [0] EN   - импульсы разрешены;
//                [1] DBL  - сдвоенные (подтверждающие) импульсы, после сброса 1;
//                [2] SIM  - имитатор сети вместо входов NSB (проверка без силовой части);
//                [3] FLT  - фильтр входов считает по тикам ГПН (подавляет помехи до ~3 тиков),
//                           0 - по каждому такту clk, как в test_nsb; после сброса 1;
//                [4] SIE  - прерывание по началу полуволны (SR.SYNCF);
//                [5] LIE  - прерывание по потере синхронизации (SR.LOSSF)
//<>0x04 ALPHA  - [11:0] угол управления, тиков ГПН от точки естественной коммутации; после сброса
//                4095 - импульсов нет. Новое значение берётся каждой парой в начале её полуволны
//<>0x08 WIDTH  - [11:0] длительность импульса, тиков ГПН (после сброса - WIDTH_INIT)
//<>0x0C DELAY  - [11:0] DELAY_RC_COMPENSATION: сдвиг пилы на запаздывание RC-фильтра NSB
//                (после сброса - DELAY_INIT); берётся, как ALPHA, в начале полуволны
//<>0x10 DIV    - [15:0] делитель: тик ГПН раз в DIV + 1 тактов clk (после сброса - DIV_INIT)
//<>0x14 SR     - [5:0] SYNC - входы после фильтра (1 - оптрон закрыт): 0 AB, 1 BA, 2 BC, 3 CB,
//                4 CA, 5 AC; [8] GRID - сеть есть (открыт хотя бы один оптрон);
//                [9] SYNCF - началась полуволна (любой пары), сброс записью 1;
//                [10] LOSSF - пропала синхронизация (какая-то пара дольше 8192 тиков без начала
//                полуволны), сброс записью 1; [11] LOST - сейчас нет синхронизации;
//                [18:16] CH - номер тиристора (1..6), чья полуволна началась последней
//<<0x18 HPER   - [15:0] полупериод сети, тиков ГПН: между последними началами полуволн пары AB
//<<0x1C CNT1   - [11:0] пила пары AB/BA (VS1/VS4)
//<<0x20 CNT2   - [11:0] пила пары BC/CB (VS3/VS6)
//<<0x24 CNT3   - [11:0] пила пары CA/AC (VS5/VS2)
//<<0x28 GATE   - [5:0] выходы vs1..vs6 (бит 0 - VS1); [13:8] импульсы пар до сдваивания и EN
//<>0x2C SIMCFG - имитатор: [15:0] SECT - тиков ГПН на 60 эл. град. (после сброса 1667: 50 Гц
//                при 500 кГц); [27:16] DZ - мёртвая зона у нуля линейного напряжения, тиков (56).
//                Без имитатора (SIM_EN = 0) регистр и бит CR.SIM читаются как 0
//Запрос прерывания irq = (SYNCF & SIE) | (LOSSF & LIE), через регистр (на такт позже флага).
module sifu_top
  #(parameter bit          MEMORY_TYPE = 0,
    parameter logic [15:0] DIV_INIT    = 16'd89,     //Тик ГПН: 45 МГц / (89 + 1) = 500 кГц
    parameter logic [11:0] DELAY_INIT  = 12'd400,    //DELAY_RC_COMPENSATION (настроено на стенде)
    parameter logic [11:0] WIDTH_INIT  = 12'd150,    //Длительность импульса: 150 тиков = 300 мкс
    parameter bit          SIM_EN      = 1'b1)       //Имитатор сети (CR.SIM, SIMCFG): 0 - нет
   (input  logic        clk, rst,
    // Интерфейс обмена
    input  logic [ 3:0] Write,
    input  logic [31:0] Addr, WData,
    output logic [31:0] RData,
    // Сигналы платы синхронизации NSB: 0 - оптрон открыт (sync_ab - положительное U_AB...)
    input  logic        sync_ab, sync_ba, sync_bc, sync_cb, sync_ca, sync_ac,
    // Импульсы управления тиристорами (1 - импульс): VS1, VS3, VS5 - катодная группа (фазы A, B, C),
    // VS4, VS6, VS2 - анодная группа (фазы A, B, C); порядок включения VS1 -> VS2 -> ... -> VS6
    output logic        vs1, vs2, vs3, vs4, vs5, vs6,
    // «Сеть есть» (SR.GRID, через регистр): индикатор, как user_pin (ENABLE) в test_nsb
    output logic        grid_o,
    output logic        irq
);
    //#1 Регистры
    localparam int N = 12;
    logic [N-1:0][3:0] we;
    logic      [31:0] wdata;

    logic [ 5:0] cr;
    logic [11:0] alpha, width, delay;
    logic [15:0] div;
    logic [15:0] sim_sect;
    logic [11:0] sim_dz;
    logic        syncf, lossf;
    logic [ 2:0] ch;
    logic [ 5:0] sync_f;                 //Входы после фильтра: {ac, ca, cb, bc, ba, ab}
    logic        grid, lost;
    logic [15:0] hper;
    logic [11:0] cnt1, cnt2, cnt3;
    logic [ 6:1] d;                      //Импульсы пар (до сдваивания и разрешения), номер - тиристор
    logic [ 6:1] g;                      //Выходы

    periph_regs #(.N(N), .MEMORY_TYPE(MEMORY_TYPE)) regs
        (.clk(clk), .Write(Write), .Read(1'b0), .Addr(Addr), .WData(WData), .RData(RData),
         .we(we), .re(), .wdata(wdata),
         .rdata({{4'd0, sim_dz, sim_sect},                                        //0x2C SIMCFG
                 32'({d, 2'b00, g}),                                              //0x28 GATE
                 32'(cnt3), 32'(cnt2), 32'(cnt1),                                 //0x24..0x1C CNT
                 32'(hper),                                                       //0x18 HPER
                 32'({ch, 4'd0, lost, lossf, syncf, grid, 2'b00, sync_f}),       //0x14 SR
                 32'(div), 32'(delay), 32'(width), 32'(alpha),                    //0x10..0x04
                 32'(cr)}));                                                      //0x00 CR

    logic [ 5:0] cr_q;
    periph_reg #(.W(6),  .INIT(6'b00_1010))  r_cr    (.clk(clk), .rst(rst), .we(we[0]), .wdata(wdata), .q(cr_q));
    assign cr = {cr_q[5:3], cr_q[2] & SIM_EN, cr_q[1:0]};
    periph_reg #(.W(12), .INIT(12'hFFF))     r_alpha (.clk(clk), .rst(rst), .we(we[1]), .wdata(wdata), .q(alpha));
    periph_reg #(.W(12), .INIT(WIDTH_INIT))  r_width (.clk(clk), .rst(rst), .we(we[2]), .wdata(wdata), .q(width));
    periph_reg #(.W(12), .INIT(DELAY_INIT))  r_delay (.clk(clk), .rst(rst), .we(we[3]), .wdata(wdata), .q(delay));
    periph_reg #(.W(16), .INIT(DIV_INIT))    r_div   (.clk(clk), .rst(rst), .we(we[4]), .wdata(wdata), .q(div));
    generate if (SIM_EN) begin : g_sim_reg
        periph_reg #(.W(28), .INIT({12'd56, 16'd1667})) r_sim
            (.clk(clk), .rst(rst), .we(we[11]), .wdata(wdata), .q({sim_dz, sim_sect}));
    end else begin : g_no_sim_reg
        assign {sim_dz, sim_sect} = '0;
    end
    endgenerate

    wire en  = cr[0];
    wire dbl = cr[1];
    wire sim = cr[2];
    wire flt = cr[3];
    wire sie = cr[4];
    wire lie = cr[5];

    //#2 Тик ГПН (my_divider) и имитатор сети
    logic tick;
    my_divider divider (.clk(clk), .rst(rst), .div(div), .tick(tick));

    logic [5:0] sim_n;                   //Сигналы имитатора, как у NSB: {ac, ca, cb, bc, ba, ab}
    generate if (SIM_EN) begin : g_sim
        sifu_simgen simgen (.clk(clk), .rst(rst), .tick(tick), .en(sim),
                            .sect(sim_sect), .dz(sim_dz), .sig_n(sim_n));
    end else begin : g_no_sim
        assign sim_n = 6'b11_1111;
    end
    endgenerate

    //#3 Фильтры входов: в режиме SIM - сигналы имитатора
    wire [5:0] sync_in = sim ? sim_n : {sync_ac, sync_ca, sync_cb, sync_bc, sync_ba, sync_ab};
    wire       flt_en  = flt ? tick : 1'b1;
    for (genvar i = 0; i < 6; i++) begin : g_flt
        filter_2bit flt_i (.clk(clk), .rst(rst), .en(flt_en), .in(sync_in[i]), .out(sync_f[i]));
    end

    //#4 Пороги импульса - общие для пар (через регистр): начало t_on = ALPHA + DELAY, конец
    //t_off = t_on + WIDTH. Каждая пара фиксирует их у себя в начале своей полуволны
    logic [12:0] t_on;
    logic [13:0] t_off;
    always_ff @(posedge clk) begin
        t_on  <= 13'(alpha) + 13'(delay);
        t_off <= 14'(alpha) + 14'(delay) + 14'(width);
    end

    //#5 Генераторы пилы и импульсов: пара фаз XY/YX - тиристор катодной группы фазы X (положительное
    //U_XY) и анодной группы фазы X (положительное U_YX)
    logic [6:1] st;                      //Начало полуволны, номер - тиристор
    logic [15:0] per1;
    logic       lost1, lost2, lost3;
    OnePulse_3 #(.PER_W(16)) p_ab (.clk(clk), .rst(rst), .tick(tick), .t_on(t_on), .t_off(t_off),
                     .sync1(sync_f[0]), .sync2(sync_f[1]), .thyr_out1(d[1]), .thyr_out2(d[4]),
                     .start1(st[1]), .start2(st[4]), .cnt(cnt1), .per(per1), .lost(lost1));
    //У пар BC и CA полупериод не нужен - счётчик только до порога потери синхронизации (14 бит)
    OnePulse_3 #(.PER_W(14)) p_bc (.clk(clk), .rst(rst), .tick(tick), .t_on(t_on), .t_off(t_off),
                     .sync1(sync_f[2]), .sync2(sync_f[3]), .thyr_out1(d[3]), .thyr_out2(d[6]),
                     .start1(st[3]), .start2(st[6]), .cnt(cnt2), .per(), .lost(lost2));
    OnePulse_3 #(.PER_W(14)) p_ca (.clk(clk), .rst(rst), .tick(tick), .t_on(t_on), .t_off(t_off),
                     .sync1(sync_f[4]), .sync2(sync_f[5]), .thyr_out1(d[5]), .thyr_out2(d[2]),
                     .start1(st[5]), .start2(st[2]), .cnt(cnt3), .per(), .lost(lost3));
    assign hper = per1;
    assign grid = ~&sync_f;
    assign lost = lost1 | lost2 | lost3;

    //#6 Выходы: импульс тиристора VSk и подтверждающий - вместе с импульсом VSk+1 (через 60 эл. град.),
    //чтобы в режиме прерывистого тока при включении VSk+1 была открыта и пара для него (VS6 - с VS1)
    wire [6:1] d_next = {d[1], d[6:2]};
    always_ff @(posedge clk)
        if (rst) g <= '0;
        else     g <= {6{en & grid}} & (d | ({6{dbl}} & d_next));
    assign {vs6, vs5, vs4, vs3, vs2, vs1} = g;
    always_ff @(posedge clk)
        if (rst) grid_o <= 1'b0;
        else     grid_o <= grid;

    //#7 Флаги и прерывание
    logic lost_q;
    logic [2:0] st_num;
    always_comb begin
        st_num = 3'd0;
        for (int k = 1; k <= 6; k++) if (st[k]) st_num = 3'(k);
    end
    always_ff @(posedge clk)
        if (rst) begin
            syncf <= 1'b0; lossf <= 1'b0; ch <= 3'd0; lost_q <= 1'b1; irq <= 1'b0;
        end else begin
            lost_q <= lost;
            if (|st)                              begin syncf <= 1'b1; ch <= st_num; end
            else if (we[5][1] && wdata[9])        syncf <= 1'b0;
            if (lost & ~lost_q)                   lossf <= 1'b1;
            else if (we[5][1] && wdata[10])       lossf <= 1'b0;
            irq <= (syncf & sie) | (lossf & lie);
        end
endmodule

//==============================================================================================
// my_divider - тик ГПН: один такт clk из каждых div + 1
//==============================================================================================
//В test_nsb делитель выдавал меандр 500 кГц, на котором работали счётчики (производный такт).
//Здесь тот же делитель даёт разрешение tick, всё работает на такте шины clk. Счёт вниз от div до 0
//с перезагрузкой: новый div действует с ближайшей перезагрузки.
module my_divider
   (input  logic        clk, rst,
    input  logic [15:0] div,
    output logic        tick
);
    logic [15:0] cnt;
    always_ff @(posedge clk)
        if (rst)            begin cnt <= '0;         tick <= 1'b0; end
        else if (cnt == '0) begin cnt <= div;        tick <= 1'b1; end
        else                begin cnt <= cnt - 1'b1; tick <= 1'b0; end
endmodule

//==============================================================================================
// filter_2bit - фильтр дребезга входа синхронизации
//==============================================================================================
//Синхронизатор из двух триггеров (вход асинхронный - от оптрона), затем реверсивный счётчик 0..3:
//в отсчёт en считает вверх при входе 1 и вниз при 0. Выход становится 1, когда счётчик дошёл до 3,
//и 0, когда дошёл до 0 (гистерезис): короткая помеха, не набравшая трёх отсчётов, на выход не
//проходит. Как в test_nsb, но выход - регистр (там была защёлка), отсчёты - по en.
//После сброса выход 1 - «оптрон закрыт».
module filter_2bit
   (input  logic clk, rst,
    input  logic en,                     //Отсчёт: каждый такт или тик ГПН
    input  logic in,
    output logic out
);
    logic [1:0] sync;
    logic [1:0] cnt;
    always_ff @(posedge clk)
        if (rst) begin
            sync <= 2'b11; cnt <= 2'd3; out <= 1'b1;
        end else begin
            sync <= {sync[0], in};
            if (en) begin
                if (sync[1]  && cnt != 2'd3) cnt <= cnt + 1'b1;
                if (!sync[1] && cnt != 2'd0) cnt <= cnt - 1'b1;
            end
            if (cnt == 2'd3)      out <= 1'b1;
            else if (cnt == 2'd0) out <= 1'b0;
        end
endmodule

//==============================================================================================
// OnePulse_3 - пила и импульсы одной пары фаз (тиристоры катодной и анодной групп одной фазы)
//==============================================================================================
//sync1 - оптрон положительной полуволны линейного напряжения U_XY (0 - открыт), sync2 -
//отрицательной (U_YX > 0). Открыт ровно один из них - известна полярность; закрыты оба - мёртвая
//зона у перехода напряжения через 0 (полярность прежняя). Полуволна начинается, когда открылся
//оптрон другой полярности (смена полярности): пила cnt сбрасывается в 0 и считает тики ГПН - через
//мёртвую зону - до начала следующей полуволны или до 4095 (там останавливается). В начале
//полуволны берутся пороги t_on = ALPHA + DELAY, t_off = t_on + WIDTH (их считает sifu_top).
//Импульс начинается, когда пила дошла до t_on, и кончается на t_off, на 4095 или в начале следующей
//полуволны (на такт позже пилы); выход - полярности текущей полуволны: thyr_out1 - положительной,
//thyr_out2 - отрицательной. t_on >= 4095 - импульса нет.
//Отличия от test_nsb (там пила стояла в нуле в мёртвой зоне и импульс шёл только при открытом
//оптроне): при малом напряжении сети мёртвая зона широкая (стенд, 300 В: 47 град., окно оптрона
//133 град.), и импульс при большом угле (120 град. + DELAY = 134 град. от начала окна) пропадал -
//теперь пила идёт и в мёртвой зоне. Помеха, закрывшая оптрон посреди полуволны, пилу не
//перезапускает (полярность та же). «Залипший» оптрон (одна полярность всё время) - начала полуволн
//нет, пила стоит на 4095, импульсов у пары нет, через 8192 тика - потеря синхронизации. Первое окно
//после сброса только запоминает полярность: пила пойдёт со следующей смены.
//Сравнения порогов - на равенство (пила идёт через каждое значение): дешевле сравнения
//«больше/меньше» на цепочке переноса.
module OnePulse_3
  #(parameter int PER_W = 16)            //Разрядность счётчика полупериода: 14..16 (порог потери - 8192)
   (input  logic        clk, rst,
    input  logic        tick,
    input  logic [12:0] t_on,            //ALPHA + DELAY
    input  logic [13:0] t_off,           //ALPHA + DELAY + WIDTH
    input  logic        sync1, sync2,
    output logic        thyr_out1, thyr_out2,
    output logic        start1, start2,  //Начало полуволны: положительной, отрицательной (1 такт)
    output logic [11:0] cnt,             //Пила
    output logic [PER_W-1:0] per,        //Тиков между двумя последними началами полуволн
    output logic        lost             //Больше 8191 тика без начала полуволны
);
    logic active, pol, pol_q, seen;
    assign active = sync1 ^ sync2;                  //Открыт ровно один оптрон: полярность известна
    assign pol    = ~sync1;                         //1 - положительная полуволна

    //Полярность текущей полуволны (держится в мёртвой зоне); seen - полярность уже известна
    always_ff @(posedge clk)
        if (rst) begin
            pol_q <= 1'b0; seen <= 1'b0;
        end else if (active) begin
            pol_q <= pol; seen <= 1'b1;
        end
    wire start = active & seen & (pol != pol_q);   //Смена полярности - начало полуволны
    assign start1 = start & pol;
    assign start2 = start & ~pol;

    //Пила с насыщением, пороги полуволны и триггер импульса. После сброса пила стоит на 4095
    logic [12:0] on_q;
    logic [13:0] off_q;
    logic        pul;
    wire         sat = (cnt == 12'hFFF);
    always_ff @(posedge clk)
        if (rst) begin
            cnt <= '1; on_q <= '1; off_q <= '1; pul <= 1'b0;
        end else if (start) begin
            cnt <= '0; on_q <= t_on; off_q <= t_off; pul <= 1'b0;
        end else begin
            if (tick && !sat) cnt <= cnt + 1'b1;
            if (sat || 14'(cnt) == off_q) pul <= 1'b0;      //Конец важнее начала: WIDTH = 0 - импульса нет
            else if (13'(cnt) == on_q)    pul <= 1'b1;
        end

    assign thyr_out1 = pul & pol_q;
    assign thyr_out2 = pul & ~pol_q;

    //Полупериод и потеря синхронизации: тики от начала последней полуволны (с насыщением)
    logic [PER_W-1:0] age;
    wire              age_max = &age;
    always_ff @(posedge clk)
        if (rst) begin
            age <= '1; per <= '0;
        end else if (start) begin           //Тик в такт начала - ещё прошлой полуволне
            per <= (tick && !age_max) ? age + 1'b1 : age;
            age <= '0;
        end else if (tick && !age_max)
            age <= age + 1'b1;
    assign lost = |age[PER_W-1:13];
endmodule

//==============================================================================================
// sifu_simgen - имитатор сети: сигналы шести оптронов NSB для проверки без силовой части
//==============================================================================================
//Период сети - 6 секторов по sect тиков ГПН (60 эл. град. каждый). Фаза теta = сектор * sect +
//позиция; U_AB > 0 при theta от 0 до 180 град., U_BC отстаёт на 120 град. (2 сектора), U_CA - на
//240. Оптрон положительной полуволны открыт (0) при theta от dz до 3 * sect - dz, отрицательной -
//от 3 * sect + dz до 6 * sect - dz: dz тиков у каждого перехода через 0 закрыты оба (мёртвая зона).
//Выключенный имитатор стоит в начале периода.
module sifu_simgen
   (input  logic        clk, rst,
    input  logic        tick, en,
    input  logic [15:0] sect,            //Тиков на 60 эл. град.
    input  logic [11:0] dz,              //Мёртвая зона, тиков (меньше sect)
    output logic [ 5:0] sig_n            //{ac, ca, cb, bc, ba, ab}, 0 - оптрон открыт
);
    logic [ 2:0] s;                      //Сектор 0..5
    logic [15:0] p;                      //Позиция в секторе 0..sect-1
    logic        head;                   //p >= dz: после мёртвой зоны в начале полуволны
    logic        tail;                   //p < sect - dz: до мёртвой зоны в конце полуволны
    logic [15:0] tail_at;                //sect - dz
    wire  [15:0] p1 = p + 1'b1;
    always_ff @(posedge clk) tail_at <= sect - 16'(dz);
    //Флаги head и tail - по равенству со следующей позицией (дешевле сравнений «больше/меньше»)
    always_ff @(posedge clk)
        if (rst | ~en) begin
            s <= '0; p <= '0; head <= (dz == '0); tail <= 1'b1;
        end else if (tick) begin
            if (p1 == sect) begin
                p <= '0; head <= (dz == '0); tail <= 1'b1;
                s <= (s == 3'd5) ? 3'd0 : s + 1'b1;
            end else begin
                p <= p1;
                if (p1 == 16'(dz))  head <= 1'b1;
                if (p1 == tail_at)  tail <= 1'b0;
            end
        end

    //Сектор пары, отстающей на k секторов: s - k по модулю 6
    wire [2:0] s2 = (s >= 3'd2) ? s - 3'd2 : s + 3'd4;
    wire [2:0] s4 = (s >= 3'd4) ? s - 3'd4 : s + 3'd2;
    wire pos0 = (s  == 3'd0 & head) | (s  == 3'd1) | (s  == 3'd2 & tail);
    wire neg0 = (s  == 3'd3 & head) | (s  == 3'd4) | (s  == 3'd5 & tail);
    wire pos1 = (s2 == 3'd0 & head) | (s2 == 3'd1) | (s2 == 3'd2 & tail);
    wire neg1 = (s2 == 3'd3 & head) | (s2 == 3'd4) | (s2 == 3'd5 & tail);
    wire pos2 = (s4 == 3'd0 & head) | (s4 == 3'd1) | (s4 == 3'd2 & tail);
    wire neg2 = (s4 == 3'd3 & head) | (s4 == 3'd4) | (s4 == 3'd5 & tail);

    always_ff @(posedge clk)
        if (rst | ~en) sig_n <= 6'b11_1111;
        else           sig_n <= ~{neg2, pos2, neg1, pos1, neg0, pos0};
endmodule
