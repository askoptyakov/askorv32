//==============================================================================================
// adc121_top - сбор аналоговых сигналов с АЦП ADC121S051 (TI): платы ADC_V (напряжение) и ADC_C (ток)
//==============================================================================================
//DESCRIPTION: Контроллер одного АЦП ADC121S051 (12 бит, последовательный интерфейс: CS#, SCLK, DOUT)
//на шине регистров askoRV32. Плата измерения - ADC_V (делитель ±600 В, дифференциальный усилитель,
//цифровые изоляторы CA-IS3722HS) или ADC_C (ток, та же микросхема АЦП): у каждой платы свой экземпляр
//блока, отличаются только пересчёт кода в единицы (библиотека на Си) и настройки. Вход cmp -
//дискретный сигнал платы (ADC_C: выход компаратора защиты по мгновенному току U2 LM311): состояние,
//флаг срабатывания и прерывание. Описание -
//README.md в этой папке, тест - tb_adc121.sv, библиотека - fw/Core/Inc/adc121.h.
//
//Кадр АЦП (ADC121S051, лист данных TI): спад CS# запускает преобразование, на DOUT выходит первый
//из четырёх ведущих нулей; каждый спад SCLK выдаёт следующий бит: 4 нуля, затем 12 бит данных
//старшим вперёд - 16 бит за 16 тактов SCLK. Модуль держит SCLK в 0, опускает CS#, через полпериода
//поднимает SCLK и далее 16 раз: полпериода SCLK = 1, затем бит DOUT забирается (через синхронизатор)
//и SCLK опускается. Бит берётся в конце высокого полупериода, за полпериода до того, как АЦП его
//сменит: так есть запас на задержки изоляторов и выхода АЦП - бит выходит после спада SCLK и
//забирается перед следующим спадом, сумма задержек должна быть меньше периода SCLK минус 3 такта
//(синхронизатор и выходной регистр; при 96 МГц и SCLK 8 МГц - около 94 нс; изоляторы, оптрон и
//АЦП дают 22..67 нс). Через полупериод после 16-го спада CS# поднимается, пауза QUIET полупериодов -
//и следующий кадр.
//Ведущие нули проверяются: не нули (DOUT висит в 1 - платы нет) - флаг ERR, отсчёт не учитывается.
//
//Такты. Кадр и период запуска работают от своего такта adc_clk (в ПЛИС - отдельный выход rPLL,
//96 МГц: SCLK ровно 8 МГц - предел ADC121S051), регистры, усреднение и флаги - от такта шины clk.
//adc_clk может совпадать с clk (тогда блок подключают к такту шины). Между тактами: управление
//(EN, CSINV, DIV, QUIET, CSS, PER, запрос START) уходит пачкой с подтверждением (новая пачка - только
//после того, как такт АЦП принял прежнюю), принятый кадр возвращается переключателем (кадры идут не
//чаще 35 тактов adc_clk, регистр кадра держится до следующего). adc_lock = 0 (rPLL ещё не захватил
//частоту) держит часть блока на adc_clk в сбросе; после него она забирает текущую пачку.
//SCLK = f_adc / (2 * (DIV + 1)); ADC121S051 - 3.2..8 МГц. Кадр - 32 + CSS + QUIET полупериодов SCLK
//и такт запуска: при 8 МГц, CSS = QUIET = 1 - (34 * 6 + 1) тактов = 468 тыс. отсчётов в секунду.
//
//Карта регистров (по шаблону periph_regs, hw/src/periph/periph_regs.sv):
//<>0x00 CR    - [0] EN - непрерывные преобразования (с периодом PER); [1] START - одно преобразование
//               (запись 1, сам сбрасывается); [2] DIE - прерывание по новому отсчёту (SR.DRDY);
//               [3] AIE - прерывание по новому среднему (SR.ARDY); [4] EIE - по ошибке кадра (SR.ERR);
//               [5] CSINV - вывод CS инвертирован (на плате CS через инвертирующий оптрон/изолятор);
//               [6] CPOL - активный уровень входа cmp: 0 - низкий (LM311 с открытым коллектором), 1 - высокий;
//               [7] CIE - прерывание по срабатыванию cmp (SR.CMPF)
//<>0x04 DIV   - [7:0] делитель SCLK (после сброса - DIV_INIT); [11:8] QUIET - пауза между кадрами,
//               полупериодов SCLK (1..15, после сброса QUIET_INIT); [15:12] CSS - от спада CS# до
//               первого подъёма SCLK, полупериодов (1..15, после сброса CSS_INIT: запас на оптрон CS)
//<>0x08 AVG   - [3:0] AVGSH: среднее по 2^AVGSH отсчётам (0..12; после сброса - AVGSH_INIT)
//<>0x0C PER   - [23:0] период запуска преобразований, тактов adc_clk; 0 - сразу за предыдущим
//<<0x10 DATA  - [11:0] последний отсчёт АЦП (код); [31:16] номер отсчёта (младшие 16 бит CNT)
//<<0x14 MEAN  - [11:0] последнее среднее (SUM >> AVGSH)
//<<0x18 SUM   - [23:0] сумма 2^AVGSH отсчётов последнего усреднения (для разрешения лучше 1 кода)
//<>0x1C SR    - [0] DRDY - новый отсчёт; [1] ARDY - новое среднее; [2] ERR - ошибка кадра (ведущие
//               нули не нули); [3] CMPF - вход cmp перешёл в активный уровень; сброс записью 1;
//               [8] BUSY - идёт кадр; [9] CMP - вход cmp сейчас активен; [31:16] FRAME - сырой кадр
//               последнего преобразования [15:0] (диагностика: в норме 0x0xxx)
//<<0x20 CNT   - [31:0] число отсчётов без ошибок с начала работы
//<<0x24 FCLK  - [31:0] частота adc_clk, Гц (параметр CLK_HZ; 0 - не задана, тогда такт шины)
//Запрос прерывания irq = (DRDY & DIE) | (ARDY & AIE) | (ERR & EIE) | (CMPF & CIE), через регистр.
//Без входа cmp (CMP_EN = 0) CMP и CMPF всегда 0.
module adc121_top
  #(parameter bit         MEMORY_TYPE = 0,
    parameter logic [7:0] DIV_INIT    = 8'd5,       //SCLK = f_adc / 12: 96 МГц -> 8 МГц
    parameter logic [3:0] AVGSH_INIT  = 4'd8,       //Среднее по 256 отсчётам
    parameter logic [3:0] CSS_INIT    = 4'd1,       //От CS# до SCLK, полупериодов
    parameter logic [3:0] QUIET_INIT  = 4'd1,       //Пауза между кадрами, полупериодов
    parameter bit         CSINV_INIT  = 1'b0,       //Вывод CS инвертирован
    parameter bit         CMP_EN      = 1'b0,       //Вход cmp подключён
    parameter bit         CPOL_INIT   = 1'b0,       //Активный уровень cmp: 0 - низкий
    parameter logic [31:0] CLK_HZ     = 32'd0)      //Частота adc_clk, Гц (регистр FCLK)
   (input  logic        clk, rst,
    // Такт кадра АЦП (может совпадать с clk) и его готовность (LOCK rPLL)
    input  logic        adc_clk, adc_lock,
    // Интерфейс обмена
    input  logic [ 3:0] Write,
    input  logic [31:0] Addr, WData,
    output logic [31:0] RData,
    // АЦП
    output logic        adc_cs_n,
    output logic        adc_sclk,
    input  logic        adc_sdo,
    // Дискретный вход платы (ADC_C - компаратор защиты), не используется при CMP_EN = 0
    input  logic        adc_cmp,
    output logic        irq
);
    //#1 Регистры
    localparam int N = 10;
    logic [N-1:0][3:0] we;
    logic [31:0] wdata;

    logic [ 7:0] cr;                     //{CIE, CPOL, CSINV, EIE, AIE, DIE, -, EN}; START - строб
    logic [ 7:0] div;
    logic [ 3:0] quiet, css;
    logic [ 3:0] avgsh;
    logic [23:0] per;
    logic [11:0] data, mean;
    logic [23:0] sum_q;
    logic        drdy, ardy, err, busy, cmpf, cmp;
    logic [15:0] frame;
    logic [31:0] cnt;

    periph_regs #(.N(N), .MEMORY_TYPE(MEMORY_TYPE)) regs
        (.clk(clk), .Write(Write), .Read(1'b0), .Addr(Addr), .WData(WData), .RData(RData),
         .we(we), .re(), .wdata(wdata),
         .rdata({CLK_HZ,                                                  //0x24 FCLK
                 cnt,                                                     //0x20 CNT
                 {frame, 6'd0, cmp, busy, 4'd0, cmpf, err, ardy, drdy},   //0x1C SR
                 32'(sum_q),                                              //0x18 SUM
                 32'(mean),                                               //0x14 MEAN
                 {cnt[15:0], 4'd0, data},                                 //0x10 DATA
                 32'(per),                                                //0x0C PER
                 32'(avgsh),                                              //0x08 AVG
                 {16'd0, css, quiet, div},                                //0x04 DIV
                 {24'd0, cr[7:2], 1'b0, cr[0]}}));                        //0x00 CR

    logic [7:0] cr_q;
    periph_reg #(.W(8), .INIT({1'b0, CPOL_INIT, CSINV_INIT, 5'd0})) r_cr
        (.clk(clk), .rst(rst), .we(we[0]), .wdata(wdata), .q(cr_q));
    assign cr = {cr_q[7:2], 1'b0, cr_q[0]};
    wire start_cmd = we[0][0] & wdata[1];                   //CR.START - запуск одного кадра

    periph_reg #(.W(16), .INIT({CSS_INIT, QUIET_INIT, DIV_INIT})) r_div
        (.clk(clk), .rst(rst), .we(we[1]), .wdata(wdata), .q({css, quiet, div}));
    periph_reg #(.W(4),  .INIT(AVGSH_INIT)) r_avg (.clk(clk), .rst(rst), .we(we[2]), .wdata(wdata), .q(avgsh));
    periph_reg #(.W(24)) r_per (.clk(clk), .rst(rst), .we(we[3]), .wdata(wdata), .q(per));

    wire en  = cr[0];
    wire die = cr[2];
    wire aie = cr[3];
    wire eie = cr[4];
    wire csinv = cr[5];
    wire cpol  = cr[6];
    wire cie   = cr[7];

    //#2a Вход cmp: синхронизатор, активный уровень по CPOL; CMPF - по переходу в активный уровень
    logic [2:0] cmp_s;
    logic       cmp_q, cmp_rise;
    always_ff @(posedge clk)
        if (rst) begin cmp_s <= {3{~CPOL_INIT}}; cmp_q <= 1'b0; end      //После сброса - неактивный уровень
        else begin
            cmp_s <= {cmp_s[1:0], adc_cmp};
            cmp_q <= cmp;
        end
    assign cmp      = CMP_EN & (cmp_s[2] ^ ~cpol);
    assign cmp_rise = cmp & ~cmp_q;

    //#2b Управление -> такт АЦП: пачка {START, EN, CSINV, CSS, QUIET, DIV, PER} с подтверждением.
    //Запись CR, DIV или PER (и START) ставит запрос; пачка уходит, когда такт АЦП принял прежнюю
    //(ack_s = ctl_t), - за такт после записи, чтобы взять уже обновлённые регистры
    localparam int CW = 1 + 1 + 1 + 4 + 4 + 8 + 24;
    logic [CW-1:0] ctl_b;
    logic          ctl_t, ctl_req, st_req, st_b;
    logic [2:0]    ack_s;
    logic          ack_t;                //Подтверждение (такт АЦП)
    wire           ctl_we = we[0][0] | (|we[1]) | (|we[3]);
    always_ff @(posedge clk)
        if (rst) begin
            ctl_b <= {1'b0, 1'b0, CSINV_INIT, CSS_INIT, QUIET_INIT, DIV_INIT, 24'd0};
            ctl_t <= 1'b0; ctl_req <= 1'b0; st_req <= 1'b0; st_b <= 1'b0; ack_s <= '0;
        end else begin
            ack_s <= {ack_s[1:0], ack_t};
            if (start_cmd) st_req <= 1'b1;
            if (ctl_we) ctl_req <= 1'b1;
            else if (ctl_req && ack_s[2] == ctl_t) begin
                ctl_b   <= {st_b ^ st_req, en, csinv, css, quiet, div, per};
                st_b    <= st_b ^ st_req;
                ctl_t   <= ~ctl_t;
                ctl_req <= 1'b0; st_req <= 1'b0;
            end
        end

    //#3 Такт АЦП: сброс, приём пачки, период запуска, кадр
    logic [1:0] rst_s;                   //Сброс в такт АЦП: сброс шины или rPLL без захвата
    always_ff @(posedge adc_clk or negedge adc_lock)
        if (!adc_lock) rst_s <= 2'b11;
        else           rst_s <= {rst_s[0], rst};
    wire rst_a = rst_s[1];

    logic [2:0]  ctl_s;
    logic        fresh;                  //После сброса: забрать текущую пачку
    logic        st_a, en_a, csinv_a;
    logic [3:0]  css_a, quiet_a;
    logic [7:0]  div_a;
    logic [23:0] per_a;
    logic        pend;                   //CR.START, ждёт конца текущего кадра
    logic        go, busy_a, done_a;
    wire         ctl_new = fresh | (ctl_s[2] != ctl_s[1]);
    wire         st_new  = ctl_b[CW-1];
    always_ff @(posedge adc_clk) begin
        ctl_s <= {ctl_s[1:0], ctl_t};
        if (rst_a) begin
            fresh <= 1'b1; ack_t <= ~ctl_s[2];                     //Шина ждёт, пока сброс не кончится
            {st_a, en_a, csinv_a, css_a, quiet_a, div_a, per_a} <=
                {1'b0, 1'b0, CSINV_INIT, CSS_INIT, QUIET_INIT, DIV_INIT, 24'd0};
            pend <= 1'b0;
        end else begin
            //Пачка стоит не меньше двух тактов АЦП к моменту, когда переключатель прошёл синхронизатор
            if (ctl_new) begin
                {st_a, en_a, csinv_a, css_a, quiet_a, div_a, per_a} <= ctl_b;
                if (!fresh && st_new != st_a) pend <= 1'b1;
                fresh <= 1'b0;
            end
            if (go) pend <= 1'b0;
            ack_t <= ctl_s[2];
        end
    end

    //Период запуска: счётчик тактов вниз от PER - 1 до 0 (проверка на 0 короче сравнения с PER - на
    //GW1NR-9 при 96 МГц); при EN запуск сразу и далее каждые PER тактов (при PER = 0 - кадр за кадром)
    logic [23:0] pcnt, per_m1;
    logic        per0;                   //PER = 0
    logic        due;                    //Пора начать следующее преобразование
    always_ff @(posedge adc_clk) begin
        per_m1 <= per_a - 1'b1;          //PER меняется только с пачкой - вычитание вне пути счётчика
        per0   <= (per_a == '0);
    end
    always_ff @(posedge adc_clk)
        if (rst_a | ~en_a) begin
            pcnt <= '0; due <= 1'b0;
        end else if (pcnt == '0) begin
            pcnt <= per_m1; due <= 1'b1;
        end else begin
            pcnt <= pcnt - 1'b1;
            if (go) due <= 1'b0;
        end

    logic [15:0] rx_a, res_a;
    //Переключатель «кадр принят» (такт АЦП -> такт шины) и его синхронизатор не сбрасываются: сброс
    //одной стороны (захват rPLL пропал, сброс отладчиком) не должен давать ложный кадр
    logic        res_t = 1'b0;
    logic        cs_n_i, sclk_i;
    adc121_frame frame_i (.clk(adc_clk), .rst(rst_a), .div(div_a), .quiet(quiet_a), .css(css_a), .go(go),
                          .busy(busy_a), .done(done_a), .rx(rx_a), .cs_n(cs_n_i), .sclk(sclk_i), .sdo(adc_sdo));
    assign go = ~busy_a & (pend | (en_a & (due | per0)));
    //Выводы - через регистр (в IOB): CS# и SCLK с одинаковой задержкой, без «иголок» при смене CSINV.
    //Бит DOUT забирается в такт внутреннего спада SCLK - за такт до спада на выводе
    always_ff @(posedge adc_clk)
        if (rst_a) begin adc_cs_n <= ~CSINV_INIT; adc_sclk <= 1'b0; end
        else       begin adc_cs_n <= cs_n_i ^ csinv_a; adc_sclk <= sclk_i; end
    always_ff @(posedge adc_clk)
        if (!rst_a && done_a) begin res_a <= rx_a; res_t <= ~res_t; end

    //#3b Кадр -> такт шины: done - такт после смены переключателя, кадр shreg держится до следующего
    logic [2:0] res_s = '0;
    logic [1:0] busy_s;
    logic       done;
    wire  [15:0] shreg = res_a;
    always_ff @(posedge clk)
        res_s <= {res_s[1:0], res_t};
    always_ff @(posedge clk)
        if (rst) busy_s <= '0;
        else     busy_s <= {busy_s[0], busy_a};
    assign done = res_s[2] ^ res_s[1];
    assign busy = busy_s[1];

    //#4 Результат: отсчёт, среднее по 2^AVGSH, счётчик, флаги
    wire        fr_err  = |shreg[15:12];
    wire [11:0] fr_data = shreg[11:0];
    logic [23:0] acc;
    logic [12:0] nacc;                   //Отсчётов в acc
    wire  [12:0] navg = 13'd1 << avgsh;
    always_ff @(posedge clk)
        if (rst) begin
            data <= '0; mean <= '0; sum_q <= '0; frame <= '0; cnt <= '0;
            acc <= '0; nacc <= '0; drdy <= 1'b0; ardy <= 1'b0; err <= 1'b0; cmpf <= 1'b0;
        end else begin
            if (cmp_rise)                         cmpf <= 1'b1;
            else if (we[7][0] && wdata[3])        cmpf <= 1'b0;
            if (done) begin
                frame <= shreg;
                if (fr_err) err <= 1'b1;
                else begin
                    data <= fr_data; drdy <= 1'b1; cnt <= cnt + 1'b1;
                    if (nacc + 1'b1 >= navg) begin                  //Набрали 2^AVGSH - среднее
                        sum_q <= acc + 24'(fr_data);
                        mean  <= 12'((acc + 24'(fr_data)) >> avgsh);
                        ardy  <= 1'b1;
                        acc   <= '0; nacc <= '0;
                    end else begin
                        acc <= acc + 24'(fr_data); nacc <= nacc + 1'b1;
                    end
                end
            end
            //Сброс флагов записью 1 (установка важнее)
            if (we[7][0]) begin
                if (wdata[0] && !(done && !fr_err)) drdy <= 1'b0;
                if (wdata[1] && !(done && !fr_err && nacc + 1'b1 >= navg)) ardy <= 1'b0;
                if (wdata[2] && !(done && fr_err)) err <= 1'b0;
            end
            //Смена AVGSH - усреднение заново
            if (we[2][0]) begin acc <= '0; nacc <= '0; end
        end

    always_ff @(posedge clk)
        if (rst) irq <= 1'b0;
        else     irq <= (drdy & die) | (ardy & aie) | (err & eie) | (cmpf & cie);
endmodule

//==============================================================================================
// adc121_frame - один кадр ADC121S051: CS#, 16 тактов SCLK, приём 16 бит DOUT
//==============================================================================================
//Полупериод SCLK - div + 1 тактов clk. По go: CS# = 0, css полупериодов ожидания, затем 16 раз: SCLK = 1
//на полупериод, бит DOUT в сдвиговый регистр, SCLK = 0 на полупериод. Бит берётся из синхронизатора
//(2 триггера) в такт спада SCLK. Через полупериод после 16-го спада CS# = 1 (подъём CS# раньше 16-го
//спада прерывает преобразование), затем пауза quiet полупериодов; done - один такт в конце паузы,
//rx - принятые 16 бит (старший - первый ведущий ноль).
module adc121_frame
   (input  logic        clk, rst,
    input  logic [ 7:0] div,
    input  logic [ 3:0] quiet,
    input  logic [ 3:0] css,             //Полупериодов от спада CS# до первого подъёма SCLK
    input  logic        go,
    output logic        busy,
    output logic        done,
    output logic [15:0] rx,
    output logic        cs_n, sclk,
    input  logic        sdo
);
    logic [1:0] sdo_s;                   //Синхронизатор DOUT
    always_ff @(posedge clk) sdo_s <= {sdo_s[0], sdo};

    typedef enum logic [2:0] {IDLE, SETUP, SHIFT, HOLD, QUIET} state_t;
    state_t     st;
    logic [7:0] hc;                      //Такты в полупериоде
    logic [4:0] bits;                    //Принятые биты 0..16
    logic [3:0] qc;                      //Полупериоды паузы
    wire        half = (hc == div);      //Конец полупериода

    always_ff @(posedge clk)
        if (rst) begin
            st <= IDLE; cs_n <= 1'b1; sclk <= 1'b0; hc <= '0; bits <= '0; qc <= '0; rx <= '0; done <= 1'b0;
        end else begin
            done <= 1'b0;
            hc   <= (st == IDLE || half) ? 8'd0 : hc + 1'b1;
            case (st)
                IDLE: if (go) begin
                    st <= SETUP; cs_n <= 1'b0; bits <= '0; qc <= '0;
                end
                SETUP: if (half) begin                  //CS# -> первый подъём SCLK: CSS полупериодов
                    qc <= qc + 1'b1;
                    if (qc + 1'b1 >= css) begin st <= SHIFT; sclk <= 1'b1; end
                end
                SHIFT: if (half) begin
                    if (sclk) begin                     //Конец высокого полупериода: бит и спад
                        rx <= {rx[14:0], sdo_s[1]};
                        sclk <= 1'b0;
                        bits <= bits + 1'b1;
                        if (bits == 5'd15) st <= HOLD;  //16-й спад - кадр принят
                    end else
                        sclk <= 1'b1;
                end
                HOLD: if (half) begin                   //CS# - через полупериод после 16-го спада
                    st <= QUIET; cs_n <= 1'b1; qc <= '0;
                end
                QUIET: if (half) begin
                    qc <= qc + 1'b1;
                    if (qc + 1'b1 >= quiet) begin
                        st <= IDLE; done <= 1'b1;
                    end
                end
            endcase
        end
    assign busy = (st != IDLE);
endmodule
