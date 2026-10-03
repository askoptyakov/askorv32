//==============================================================================================
// adc121_top - сбор аналоговых сигналов с АЦП ADC121S051 (TI): платы ADC_V (напряжение) и ADC_C (ток)
//==============================================================================================
//DESCRIPTION: Контроллер одного АЦП ADC121S051 (12 бит, последовательный интерфейс: CS#, SCLK, DOUT)
//на шине регистров askoRV32. Плата измерения - ADC_V (делитель ±600 В, дифференциальный усилитель,
//цифровые изоляторы CA-IS3722HS) или ADC_C (ток, та же микросхема АЦП): у каждой платы свой экземпляр
//блока, отличаются только пересчёт кода в единицы (библиотека на Си) и настройки. Описание -
//README.md в этой папке, тест - tb_adc121.sv, библиотека - fw/Core/Inc/adc121.h.
//
//Кадр АЦП (ADC121S051, лист данных TI): спад CS# запускает преобразование, на DOUT выходит первый
//из четырёх ведущих нулей; каждый спад SCLK выдаёт следующий бит: 4 нуля, затем 12 бит данных
//старшим вперёд - 16 бит за 16 тактов SCLK. Модуль держит SCLK в 0, опускает CS#, через полпериода
//поднимает SCLK и далее 16 раз: полпериода SCLK = 1, затем бит DOUT забирается (через синхронизатор)
//и SCLK опускается. Бит берётся в конце высокого полупериода, за полпериода до того, как АЦП его
//сменит: так есть запас на задержки изоляторов и выхода АЦП - бит выходит после спада SCLK и
//забирается перед следующим спадом, сумма задержек должна быть меньше периода SCLK минус 3 такта
//(синхронизатор и выходной регистр; при 45 МГц и SCLK 5.6 МГц - около 110 нс; CA-IS3722 и АЦП
//дают ~60 нс). Через полупериод после 16-го спада CS# поднимается, пауза QUIET полупериодов - и
//следующий кадр.
//Ведущие нули проверяются: не нули (DOUT висит в 1 - платы нет) - флаг ERR, отсчёт не учитывается.
//SCLK = f_clk / (2 * (DIV + 1)); ADC121S051 - 3.2..8 МГц (по умолчанию ~5.6 МГц). Кадр - 32 + CSS +
//QUIET полупериодов SCLK и такт запуска: при 5.6 МГц, CSS = QUIET = 2 - 310 тыс. отсчётов в секунду.
//
//Карта регистров (по шаблону periph_regs, hw/src/periph/periph_regs.sv):
//<>0x00 CR    - [0] EN - непрерывные преобразования (с периодом PER); [1] START - одно преобразование
//               (запись 1, сам сбрасывается); [2] DIE - прерывание по новому отсчёту (SR.DRDY);
//               [3] AIE - прерывание по новому среднему (SR.ARDY); [4] EIE - по ошибке кадра (SR.ERR);
//               [5] CSINV - вывод CS инвертирован (на плате CS через инвертирующий оптрон/изолятор)
//<>0x04 DIV   - [7:0] делитель SCLK (после сброса - DIV_INIT); [11:8] QUIET - пауза между кадрами,
//               полупериодов SCLK (1..15, после сброса 2); [15:12] CSS - от спада CS# до первого
//               подъёма SCLK, полупериодов (1..15, после сброса 2: запас на медленный оптрон CS)
//<>0x08 AVG   - [3:0] AVGSH: среднее по 2^AVGSH отсчётам (0..12; после сброса - AVGSH_INIT)
//<>0x0C PER   - [23:0] период запуска преобразований, тактов clk; 0 - сразу за предыдущим
//<<0x10 DATA  - [11:0] последний отсчёт АЦП (код); [31:16] номер отсчёта (младшие 16 бит CNT)
//<<0x14 MEAN  - [11:0] последнее среднее (SUM >> AVGSH)
//<<0x18 SUM   - [23:0] сумма 2^AVGSH отсчётов последнего усреднения (для разрешения лучше 1 кода)
//<>0x1C SR    - [0] DRDY - новый отсчёт; [1] ARDY - новое среднее; [2] ERR - ошибка кадра (ведущие
//               нули не нули); сброс записью 1; [8] BUSY - идёт кадр; [31:16] FRAME - сырой кадр
//               последнего преобразования [15:0] (диагностика: в норме 0x0xxx)
//<<0x20 CNT   - [31:0] число отсчётов без ошибок с начала работы
//Запрос прерывания irq = (DRDY & DIE) | (ARDY & AIE) | (ERR & EIE), через регистр.
module adc121_top
  #(parameter bit         MEMORY_TYPE = 0,
    parameter logic [7:0] DIV_INIT    = 8'd3,       //SCLK = f_clk / 8: 45 МГц -> 5.6 МГц
    parameter logic [3:0] AVGSH_INIT  = 4'd8,       //Среднее по 256 отсчётам
    parameter logic [3:0] CSS_INIT    = 4'd2,       //От CS# до SCLK, полупериодов
    parameter bit         CSINV_INIT  = 1'b0)       //Вывод CS инвертирован
   (input  logic        clk, rst,
    // Интерфейс обмена
    input  logic [ 3:0] Write,
    input  logic [31:0] Addr, WData,
    output logic [31:0] RData,
    // АЦП
    output logic        adc_cs_n,
    output logic        adc_sclk,
    input  logic        adc_sdo,
    output logic        irq
);
    //#1 Регистры
    localparam int N = 9;
    logic [N-1:0][3:0] we;
    logic [31:0] wdata;

    logic [ 5:0] cr;                     //{CSINV, EIE, AIE, DIE, -, EN}; START - строб
    logic [ 7:0] div;
    logic [ 3:0] quiet, css;
    logic [ 3:0] avgsh;
    logic [23:0] per;
    logic [11:0] data, mean;
    logic [23:0] sum_q;
    logic        drdy, ardy, err, busy;
    logic [15:0] frame;
    logic [31:0] cnt;

    periph_regs #(.N(N), .MEMORY_TYPE(MEMORY_TYPE)) regs
        (.clk(clk), .Write(Write), .Read(1'b0), .Addr(Addr), .WData(WData), .RData(RData),
         .we(we), .re(), .wdata(wdata),
         .rdata({cnt,                                                     //0x20 CNT
                 {frame, 7'd0, busy, 5'd0, err, ardy, drdy},              //0x1C SR
                 32'(sum_q),                                              //0x18 SUM
                 32'(mean),                                               //0x14 MEAN
                 {cnt[15:0], 4'd0, data},                                 //0x10 DATA
                 32'(per),                                                //0x0C PER
                 32'(avgsh),                                              //0x08 AVG
                 {16'd0, css, quiet, div},                                //0x04 DIV
                 {26'd0, cr[5:2], 1'b0, cr[0]}}));                        //0x00 CR

    logic [5:0] cr_q;
    periph_reg #(.W(6), .INIT({CSINV_INIT, 5'd0})) r_cr (.clk(clk), .rst(rst), .we(we[0]), .wdata(wdata), .q(cr_q));
    assign cr = {cr_q[5:2], 1'b0, cr_q[0]};
    wire start_cmd = we[0][0] & wdata[1];                   //CR.START - запуск одного кадра

    periph_reg #(.W(16), .INIT({CSS_INIT, 4'd2, DIV_INIT})) r_div
        (.clk(clk), .rst(rst), .we(we[1]), .wdata(wdata), .q({css, quiet, div}));
    periph_reg #(.W(4),  .INIT(AVGSH_INIT)) r_avg (.clk(clk), .rst(rst), .we(we[2]), .wdata(wdata), .q(avgsh));
    periph_reg #(.W(24)) r_per (.clk(clk), .rst(rst), .we(we[3]), .wdata(wdata), .q(per));

    wire en  = cr[0];
    wire die = cr[2];
    wire aie = cr[3];
    wire eie = cr[4];
    wire csinv = cr[5];

    logic go, done;                      //Запуск кадра, кадр принят

    //#2 Период запуска: счётчик тактов; при EN запуск, когда он дошёл до PER (или сразу при PER = 0)
    logic [23:0] pcnt;
    logic        due;                    //Пора начать следующее преобразование
    always_ff @(posedge clk)
        if (rst | ~en) begin
            pcnt <= '0; due <= 1'b0;
        end else if (pcnt + 1'b1 >= per) begin
            pcnt <= '0; due <= 1'b1;
        end else begin
            pcnt <= pcnt + 1'b1;
            if (go) due <= 1'b0;
        end

    //#3 Кадр АЦП
    logic [15:0] shreg;
    logic cs_n_i, sclk_i;
    adc121_frame frame_i (.clk(clk), .rst(rst), .div(div), .quiet(quiet), .css(css), .go(go), .busy(busy),
                          .done(done), .rx(shreg), .cs_n(cs_n_i), .sclk(sclk_i), .sdo(adc_sdo));
    //Выводы - через регистр (в IOB): CS# и SCLK с одинаковой задержкой, без «иголок» при смене CSINV.
    //Бит DOUT забирается в такт внутреннего спада SCLK - за такт до спада на выводе
    always_ff @(posedge clk)
        if (rst) begin adc_cs_n <= ~CSINV_INIT; adc_sclk <= 1'b0; end
        else     begin adc_cs_n <= cs_n_i ^ csinv; adc_sclk <= sclk_i; end
    logic pend;                          //CR.START, ждёт конца текущего кадра
    always_ff @(posedge clk)
        if (rst)            pend <= 1'b0;
        else if (start_cmd) pend <= 1'b1;
        else if (go)        pend <= 1'b0;
    assign go = ~busy & (pend | (en & (due | per == '0)));

    //#4 Результат: отсчёт, среднее по 2^AVGSH, счётчик, флаги
    wire        fr_err  = |shreg[15:12];
    wire [11:0] fr_data = shreg[11:0];
    logic [23:0] acc;
    logic [12:0] nacc;                   //Отсчётов в acc
    wire  [12:0] navg = 13'd1 << avgsh;
    always_ff @(posedge clk)
        if (rst) begin
            data <= '0; mean <= '0; sum_q <= '0; frame <= '0; cnt <= '0;
            acc <= '0; nacc <= '0; drdy <= 1'b0; ardy <= 1'b0; err <= 1'b0;
        end else begin
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
        else     irq <= (drdy & die) | (ardy & aie) | (err & eie);
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
