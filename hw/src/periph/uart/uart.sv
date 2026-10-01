//==============================================================================================
// uart_top - приёмопередатчик UART с FIFO и прерываниями по заполнению FIFO
//==============================================================================================
//DESCRIPTION: Регистры устроены как у UART SiFive (FE310-G002, глава 18): txdata, rxdata, txctrl,
//rxctrl, ie, ip, div - и расширены чётностью и флагами ошибок (регистры cfg и err). Описание и
//примеры - README.md в этой папке, тест - tb_uart.sv.
//
//Кадр: старт-бит 0, 8 бит данных младшим битом вперёд, бит чётности (если включён), 1 или 2
//стоп-бита 1. Скорость: f_clk / (div + 1) бит/с для передачи и приёма. Приёмник ловит спад старт-бита
//и берёт каждый бит в середине как большинство из трёх соседних отсчётов; div должен быть не меньше 7.
//
//Карта регистров (регистровая часть - по шаблону periph_regs, hw/src/periph/periph_regs.sv):
//<>0x00 txdata - запись: байт [7:0] в FIFO передачи (если FIFO полон, байт отбрасывается);
//                чтение: [31] full - FIFO передачи полон
//<<0x04 rxdata - чтение: [7:0] байт из FIFO приёма и выборка его из FIFO; [31] empty - FIFO был
//                пуст, данные 0
//<>0x08 txctrl - [0] txen - передача разрешена; [1] nstop - 0: один стоп-бит, 1: два;
//                [20:16] txcnt - порог: прерывание txwm, пока в FIFO передачи меньше txcnt байт
//<>0x0C rxctrl - [0] rxen - приём разрешён; [20:16] rxcnt - порог: прерывание rxwm, пока в FIFO
//                приёма больше rxcnt байт
//<>0x10 ie     - разрешение прерываний: [0] txwm, [1] rxwm, [2] err
//<<0x14 ip     - ожидающие прерывания: [0] txwm, [1] rxwm, [2] err (есть флаг в err)
//<>0x18 div    - делитель скорости (16 бит)
//<>0x1C cfg    - (askoRV32) [0] pe - бит чётности есть; [1] po - 1: нечётность (odd), 0: чётность (even)
//<>0x20 err    - (askoRV32) флаги ошибок приёма, сброс записью 1: [0] frame - стоп-бит 0;
//                [1] parity - чётность не сошлась; [2] overrun - байт потерян, FIFO приёма был полон
//Поля txcnt/rxcnt у SiFive - биты [18:16] (FIFO на 8 байт); здесь [20:16], чтобы порог доходил до
//глубины FIFO 16 и 32. Прерывание irq = |(ie & ip), выдаётся через регистр (как у STIM и PLIC).
//После сброса: txen = rxen = 0, ie = 0, err = 0; div, nstop и cfg - из параметров (их задаёт
//конфигуратор ПЛИС: скорость, чётность и стоп-биты по умолчанию).
module uart_top
  #(parameter                      MEMORY_TYPE = 0,
    parameter int                  DEPTH       = 16,       //Глубина FIFO приёма и передачи: 8, 16, 32
    parameter int                  DIV_INIT    = 390,      //div после сброса: f_clk / скорость - 1 (45 МГц, 115200)
    parameter int                  STOP_INIT   = 1,        //Стоп-битов после сброса: 1 или 2
    parameter int                  PARITY_INIT = 0)        //Чётность после сброса: 0 - нет, 1 - even, 2 - odd
   (input  logic                   clk, rst,
    // Интерфейс обмена
    input  logic            [ 3:0] Write,
    input  logic                   Read,
    input  logic            [31:0] Addr, WData,
    output logic            [31:0] RData,
    // Линии UART
    output logic                   tx,
    input  logic                   rx,
    // Запрос прерывания
    output logic                   irq
);
    localparam int AW = $clog2(DEPTH);       //Разрядность указателя FIFO

    //#1 Регистры
    logic [8:0][ 3:0] we;
    logic [8:0]       re;
    logic      [31:0] wdata;

    logic        txen, nstop, rxen;
    logic [ 4:0] txcnt, rxcnt;
    logic [ 2:0] ie, ip;
    logic [15:0] div;
    logic [ 1:0] cfg;                        //{po, pe}
    logic [ 2:0] err;                        //{overrun, parity, frame}
    logic        tx_full, rx_empty;
    logic [ 7:0] rx_head;

    periph_regs #(.N(9), .MEMORY_TYPE(MEMORY_TYPE)) regs
        (.clk(clk), .Write(Write), .Read(Read), .Addr(Addr), .WData(WData), .RData(RData),
         .we(we), .re(re), .wdata(wdata),
         .rdata({32'(err),                                       //0x20 err
                 32'(cfg),                                       //0x1C cfg
                 32'(div),                                       //0x18 div
                 32'(ip),                                        //0x14 ip
                 32'(ie),                                        //0x10 ie
                 {11'd0, rxcnt, 15'd0, rxen},                    //0x0C rxctrl
                 {11'd0, txcnt, 14'd0, nstop, txen},             //0x08 txctrl
                 {rx_empty, 23'd0, rx_empty ? 8'd0 : rx_head},   //0x04 rxdata (пустой FIFO - данные 0)
                 {tx_full, 31'd0}}));                            //0x00 txdata

    //Байтовые стробы: txen/nstop/rxen - байт 0, txcnt/rxcnt - байт 2
    always_ff @(posedge clk)
        if (rst) begin
            txen <= 1'b0; nstop <= 1'(STOP_INIT == 2); rxen <= 1'b0;
            txcnt <= '0; rxcnt <= '0; ie <= '0;
        end else begin
            if (we[2][0]) begin txen <= wdata[0]; nstop <= wdata[1]; end
            if (we[2][2]) txcnt <= wdata[20:16];
            if (we[3][0]) rxen <= wdata[0];
            if (we[3][2]) rxcnt <= wdata[20:16];
            if (we[4][0]) ie <= wdata[2:0];
        end
    periph_reg #(.W(16), .INIT(16'(DIV_INIT)))                          r_div (.clk(clk), .rst(rst), .we(we[6]), .wdata(wdata), .q(div));
    periph_reg #(.W(2),  .INIT({1'(PARITY_INIT == 2), 1'(PARITY_INIT != 0)})) r_cfg (.clk(clk), .rst(rst), .we(we[7]), .wdata(wdata), .q(cfg));

    //#2 FIFO передачи и приёма: память без сброса (распределённая SSRAM), указатели на бит длиннее
    logic [7:0]    tx_mem [DEPTH];
    logic [7:0]    rx_mem [DEPTH];
    logic [AW:0]   tx_wp, tx_rp, rx_wp, rx_rp;
    logic [AW:0]   tx_level, rx_level;
    logic          tx_push, tx_pop, rx_push, rx_pop;
    logic [7:0]    rx_byte;

    assign tx_level = tx_wp - tx_rp;
    assign rx_level = rx_wp - rx_rp;
    assign tx_full  = tx_level == (AW+1)'(DEPTH);
    assign rx_empty = rx_level == '0;
    assign rx_head  = rx_mem[rx_rp[AW-1:0]];
    assign tx_push  = we[0][0] & ~tx_full;
    assign rx_pop   = re[1] & ~rx_empty;

    always_ff @(posedge clk) begin
        if (tx_push) tx_mem[tx_wp[AW-1:0]] <= wdata[7:0];
        if (rx_push) rx_mem[rx_wp[AW-1:0]] <= rx_byte;
    end
    always_ff @(posedge clk)
        if (rst) begin
            tx_wp <= '0; tx_rp <= '0; rx_wp <= '0; rx_rp <= '0;
        end else begin
            if (tx_push) tx_wp <= tx_wp + 1'b1;
            if (tx_pop)  tx_rp <= tx_rp + 1'b1;
            if (rx_push) rx_wp <= rx_wp + 1'b1;
            if (rx_pop)  rx_rp <= rx_rp + 1'b1;
        end

    //#3 Передатчик: сдвиговый регистр {стоп-биты, чётность, данные, старт}, бит - div + 1 тактов
    logic [15:0] tx_cnt;
    logic [ 3:0] tx_bits;                    //Осталось бит кадра
    logic [11:0] tx_shift;
    logic        tx_busy;
    logic [ 7:0] tx_byte;
    assign tx_byte = tx_mem[tx_rp[AW-1:0]];
    assign tx_pop  = txen & ~tx_busy & (tx_level != '0);

    always_ff @(posedge clk)
        if (rst) begin
            tx_busy <= 1'b0; tx_shift <= '1; tx_cnt <= '0; tx_bits <= '0;
        end else if (tx_pop) begin
            tx_busy  <= 1'b1;
            tx_cnt   <= div;
            //Порядок выдачи: старт, данные 0..7, [чётность], стоп(ы); лишние старшие биты - 1 (линия покоя)
            if (cfg[0]) begin
                tx_shift <= {2'b11, ^tx_byte ^ cfg[1], tx_byte, 1'b0};
                tx_bits  <= nstop ? 4'd12 : 4'd11;
            end else begin
                tx_shift <= {3'b111, tx_byte, 1'b0};
                tx_bits  <= nstop ? 4'd11 : 4'd10;
            end
        end else if (tx_busy) begin
            if (tx_cnt != '0) tx_cnt <= tx_cnt - 1'b1;
            else begin
                tx_cnt   <= div;
                tx_shift <= {1'b1, tx_shift[11:1]};
                tx_bits  <= tx_bits - 1'b1;
                if (tx_bits == 4'd1) tx_busy <= 1'b0;
            end
        end
    always_ff @(posedge clk)
        if (rst) tx <= 1'b1;
        else     tx <= tx_busy ? tx_shift[0] : 1'b1;

    //#4 Приёмник: синхронизация, спад старт-бита, отсчёты в середине бита (большинство из трёх)
    logic [2:0] rx_sync;                     //Два триггера синхронизации и предыдущее значение
    always_ff @(posedge clk)
        if (rst) rx_sync <= 3'b111;
        else     rx_sync <= {rx_sync[1:0], rx};
    logic rx_s, rx_fall;
    assign rx_s    = rx_sync[1];
    assign rx_fall = rx_sync[2] & ~rx_sync[1];

    typedef enum logic [1:0] {R_IDLE, R_START, R_BITS, R_STOP} rx_state_t;
    rx_state_t   rx_st;
    logic [15:0] rx_cnt, half;
    logic [ 3:0] rx_n;                       //Номер бита: 0..7 данные, 8 - чётность
    logic [ 8:0] rx_data;                    //{чётность, данные}
    logic [ 2:0] vote;
    logic        bit_v, at_end;
    assign half   = {1'b0, div[15:1]};
    assign bit_v  = (vote[0] & vote[1]) | (vote[0] & vote[2]) | (vote[1] & vote[2]);
    assign at_end = rx_cnt == div;           //Конец бита
    assign rx_byte = rx_data[7:0];

    logic frame_err, parity_err, overrun;
    always_ff @(posedge clk)
        if (rst) begin
            rx_st <= R_IDLE; rx_cnt <= '0; rx_n <= '0; rx_data <= '0; vote <= '0;
            rx_push <= 1'b0; frame_err <= 1'b0; parity_err <= 1'b0; overrun <= 1'b0;
        end else begin
            rx_push <= 1'b0; frame_err <= 1'b0; parity_err <= 1'b0; overrun <= 1'b0;
            //Три отсчёта вокруг середины бита
            if (rx_st != R_IDLE && (rx_cnt == half - 1'b1 || rx_cnt == half || rx_cnt == half + 1'b1))
                vote <= {vote[1:0], rx_s};
            case (rx_st)
                R_IDLE:
                    if (rxen & rx_fall) begin rx_st <= R_START; rx_cnt <= 16'd1; end
                R_START:                                     //Середина старт-бита: помеха - назад в покой
                    if (rx_cnt == half + 16'd2 && bit_v) rx_st <= R_IDLE;
                    else if (at_end) begin rx_st <= R_BITS; rx_cnt <= '0; rx_n <= '0; end
                    else rx_cnt <= rx_cnt + 1'b1;
                R_BITS:
                    if (at_end) begin
                        rx_cnt  <= '0;
                        rx_data <= {bit_v, rx_data[8:1]};
                        rx_n    <= rx_n + 1'b1;
                        if (rx_n == (cfg[0] ? 4'd8 : 4'd7)) rx_st <= R_STOP;
                    end else rx_cnt <= rx_cnt + 1'b1;
                R_STOP:                                      //Середина стоп-бита: байт готов
                    if (rx_cnt == half + 16'd2) begin
                        rx_st <= R_IDLE;
                        //Без чётности 8 сдвигов оставили байт в rx_data[8:1]
                        rx_data    <= cfg[0] ? rx_data : {1'b0, rx_data[8:1]};
                        frame_err  <= ~bit_v;
                        parity_err <= cfg[0] & (^rx_data ^ cfg[1]);
                        if (rx_level == (AW+1)'(DEPTH)) overrun <= 1'b1;
                        else                            rx_push <= 1'b1;
                    end else rx_cnt <= rx_cnt + 1'b1;
            endcase
        end

    //#5 Флаги ошибок (сброс записью 1) и прерывания
    always_ff @(posedge clk)
        if (rst) err <= '0;
        else     err <= (err & ~(we[8][0] ? wdata[2:0] : 3'b000)) | {overrun, parity_err, frame_err};

    assign ip[0] = tx_level < 6'(txcnt);
    assign ip[1] = rx_level > 6'(rxcnt);
    assign ip[2] = |err;
    always_ff @(posedge clk)
        if (rst) irq <= 1'b0;
        else     irq <= |(ie & ip);
endmodule
