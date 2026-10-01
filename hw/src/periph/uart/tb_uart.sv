`timescale 1ns/1ps
//==============================================================================================
// tb_uart - тест UART (uart.sv) через шину регистров
//==============================================================================================
//DESCRIPTION: Значения после сброса (в том числе из параметров), кадр передачи (старт, данные,
//чётность even/odd, 1 и 2 стоп-бита) - по независимому приёмнику тестбенча, приём кадров от
//передатчика тестбенча, ошибки кадра и чётности, FIFO передачи (full, порядок байт), FIFO приёма
//(empty, переполнение), пороги txwm/rxwm, прерывание irq, сброс флагов ошибок записью 1, передача
//с выхода на вход (петля). Запуск: py hw/sim/run_periph_tests.py uart
module tb_uart;
    localparam string DEV = "uart";
    `include "periph_tb.svh"

    localparam logic [31:0] TXDATA = 32'h00, RXDATA = 32'h04, TXCTRL = 32'h08, RXCTRL = 32'h0C,
                            IE = 32'h10, IP = 32'h14, DIV = 32'h18, CFG = 32'h1C, ERR = 32'h20;
    localparam logic [31:0] DUT2 = 32'h1000;            //Адреса второго экземпляра
    localparam int          D    = 15;                  //div в тестах: бит - 16 тактов
    localparam int          BIT  = D + 1;

    //Два экземпляра на одной шине: бит 12 адреса выбирает второй
    logic tb_rx = 1'b1, loop = 1'b0;
    wire  tx, tx2, irq, irq2;
    wire  [31:0] RData1, RData2;
    wire  sel2 = Addr[12];
    uart_top #(.MEMORY_TYPE(1'b1), .DEPTH(8), .DIV_INIT(D)) dut
        (.clk(clk), .rst(rst), .Write(sel2 ? 4'b0 : Write), .Read(Read & ~sel2), .Addr(Addr), .WData(WData),
         .RData(RData1), .tx(tx), .rx(loop ? tx : tb_rx), .irq(irq));
    uart_top #(.MEMORY_TYPE(1'b1), .DEPTH(16), .DIV_INIT(1234), .STOP_INIT(2), .PARITY_INIT(2)) dut2
        (.clk(clk), .rst(rst), .Write(sel2 ? Write : 4'b0), .Read(Read & sel2), .Addr(Addr), .WData(WData),
         .RData(RData2), .tx(tx2), .rx(1'b1), .irq(irq2));
    assign RData = sel2 ? RData2 : RData1;

    //Независимый приёмник тестбенча: кадр с линии tx - данные, чётность, число стоп-битов.
    //Если кадры идут вплотную, подсчёт стоп-битов заканчивается в середине следующего старт-бита
    //(rx_mid = 1) - тогда следующий кадр читается с этого места
    bit rx_mid = 0;
    task automatic tb_recv(input bit pe, output logic [7:0] data, output logic par, output int stops);
        if (!rx_mid) begin
            wait (tx == 1'b0);
            repeat (BIT / 2) @(posedge clk);
        end
        rx_mid = 0;
        if (tx !== 1'b0) $display("FAIL uart: tb_recv - старт-бит пропал");
        for (int i = 0; i < 8; i++) begin repeat (BIT) @(posedge clk); data[i] = tx; end
        par = 1'bx;
        if (pe) begin repeat (BIT) @(posedge clk); par = tx; end
        stops = 0;
        //Стоп-биты: считаем биты 1 до следующего старта или до 3 бит тишины
        for (int i = 0; i < 3; i++) begin
            repeat (BIT) @(posedge clk);
            if (tx === 1'b1) stops++; else begin rx_mid = 1; break; end
        end
    endtask

    //Передатчик тестбенча на вход rx: кадр с заданными битами чётности и стопа
    task automatic tb_send(input logic [7:0] data, input bit pe, input logic par, input logic stop);
        tb_rx = 1'b0; repeat (BIT) @(posedge clk);
        for (int i = 0; i < 8; i++) begin tb_rx = data[i]; repeat (BIT) @(posedge clk); end
        if (pe) begin tb_rx = par; repeat (BIT) @(posedge clk); end
        tb_rx = stop; repeat (BIT) @(posedge clk);
        tb_rx = 1'b1; repeat (BIT) @(posedge clk);
    endtask

    logic [31:0] v;
    logic [ 7:0] b;
    logic        p;
    int          s;

    initial begin
        reset_dut();

        //#1 Значения после сброса
        check_rd(TXCTRL, 0,  "сброс: txctrl");
        check_rd(RXCTRL, 0,  "сброс: rxctrl");
        check_rd(IE,     0,  "сброс: ie");
        check_rd(DIV,    D,  "сброс: div = DIV_INIT");
        check_rd(CFG,    0,  "сброс: cfg (без чётности)");
        check_rd(ERR,    0,  "сброс: err");
        check_rd(TXDATA, 0,  "сброс: txdata.full = 0");
        check_rd(RXDATA, 32'h8000_0000, "сброс: rxdata.empty = 1");
        check(tx == 1'b1, "сброс: линия tx в покое", tx, 1);
        check_rd(DUT2 + DIV,    1234, "параметры: div = 1234");
        check_rd(DUT2 + TXCTRL, 2,    "параметры: nstop = 1 (2 стоп-бита)");
        check_rd(DUT2 + CFG,    3,    "параметры: cfg = odd");

        //#2 Регистры и байтовая запись: txcnt/rxcnt - байт 2
        bus_wr(TXCTRL, 32'h001F_0002);
        check_rd(TXCTRL, 32'h001F_0002, "txctrl: txcnt = 31, nstop");
        bus_wrb(TXCTRL, 32'h0003_0000, 4'b0100);
        check_rd(TXCTRL, 32'h0003_0002, "txctrl: байт 2 отдельно");
        bus_wr(TXCTRL, 0);

        //#3 Кадр 8-N-1: данные младшим битом вперёд, один стоп-бит
        bus_wr(TXCTRL, 1);
        fork bus_wr(TXDATA, 8'hA5); join_none
        tb_recv(0, b, p, s);
        check(b == 8'hA5, "8N1: данные", b, 8'hA5);
        check(s == 3, "8N1: после стопа линия в покое", s, 3);

        //#4 Два стоп-бита: второй байт идёт вплотную - между кадрами ровно 2 бита 1
        bus_wr(TXCTRL, 3);
        bus_wr(TXDATA, 8'h0F); bus_wr(TXDATA, 8'hF0);
        tb_recv(0, b, p, s);
        check(b == 8'h0F, "8N2: первый байт", b, 8'h0F);
        check(s == 2, "8N2: два стоп-бита", s, 2);
        tb_recv(0, b, p, s);
        check(b == 8'hF0, "8N2: второй байт", b, 8'hF0);

        //#5 Чётность: even - бит дополняет число единиц до чётного, odd - до нечётного
        bus_wr(TXCTRL, 1);
        bus_wr(CFG, 1);                                     //even
        fork bus_wr(TXDATA, 8'h07); join_none               //3 единицы
        tb_recv(1, b, p, s);
        check(b == 8'h07 && p == 1'b1, "8E1: бит чётности = 1", {b, 7'd0, p}, {8'h07, 7'd0, 1'b1});
        check(s >= 1, "8E1: стоп-бит", s, 1);
        bus_wr(CFG, 3);                                     //odd
        fork bus_wr(TXDATA, 8'h07); join_none
        tb_recv(1, b, p, s);
        check(p == 1'b0, "8O1: бит нечётности = 0", p, 0);

        //#6 Приём кадров от тестбенча, rxdata и empty
        bus_wr(CFG, 0);
        bus_wr(RXCTRL, 1);
        tb_send(8'h3C, 0, 0, 1);
        check_rd(RXDATA, 32'h0000_003C, "приём 8N1: байт 0x3C");
        check_rd(RXDATA, 32'h8000_0000, "приём: FIFO снова пуст");
        check_rd(ERR, 0, "приём: ошибок нет");
        //Ошибка кадра: стоп-бит 0 - байт принят, флаг frame
        tb_send(8'h55, 0, 0, 0);
        check_rd(RXDATA, 32'h0000_0055, "стоп 0: байт принят");
        check_rd(ERR, 1, "стоп 0: err.frame");
        bus_wr(ERR, 1);
        check_rd(ERR, 0, "err.frame сброшен записью 1");
        //Чётность: верная и неверная
        bus_wr(CFG, 1);
        tb_send(8'h03, 1, 0, 1);                            //две единицы, even-бит 0 - верно
        check_rd(ERR, 0, "8E1 приём: верная чётность");
        tb_send(8'h03, 1, 1, 1);                            //неверный бит чётности
        check_rd(ERR, 2, "8E1 приём: err.parity");
        check_rd(RXDATA, 32'h0000_0003, "8E1 приём: первый байт");
        check_rd(RXDATA, 32'h0000_0003, "8E1 приём: второй байт (принят, хоть и с ошибкой)");
        bus_wr(ERR, 7);
        bus_wr(CFG, 0);
        //Помеха короче половины бита - не старт
        tb_rx = 1'b0; repeat (BIT / 4) @(posedge clk); tb_rx = 1'b1; repeat (3 * BIT) @(posedge clk);
        check_rd(RXDATA, 32'h8000_0000, "помеха: байт не принят");

        //#7 FIFO передачи: при txen = 0 копится, full, лишний байт отброшен, порядок сохранён
        bus_wr(TXCTRL, 0);
        for (int i = 0; i < 8; i++) bus_wr(TXDATA, 32'h10 + i);
        check_rd(TXDATA, 32'h8000_0000, "FIFO tx: full после 8 байт");
        bus_wr(TXDATA, 32'hEE);                             //отброшен
        bus_wr(TXCTRL, 1);
        for (int i = 0; i < 8; i++) begin
            tb_recv(0, b, p, s);
            check(b == 8'h10 + i, $sformatf("FIFO tx: байт %0d по порядку", i), b, 8'h10 + i);
        end
        repeat (4 * BIT) @(posedge clk);
        check(tx == 1'b1, "FIFO tx: лишний байт не передан", tx, 1);

        //#8 Порог txwm и прерывание: ip.txwm, пока в FIFO меньше txcnt байт
        bus_wr(TXCTRL, 32'h0002_0000);                      //txen = 0, txcnt = 2
        check_rd(IP, 1, "txwm: FIFO пуст < 2");
        bus_wr(IE, 1);
        tick(2);
        check(irq == 1'b1, "txwm: irq", irq, 1);
        bus_wr(TXDATA, 1); bus_wr(TXDATA, 2);
        check_rd(IP, 0, "txwm: 2 байта - порог достигнут");
        tick(2);
        check(irq == 1'b0, "txwm: irq снят", irq, 0);
        bus_wr(IE, 0);
        bus_wr(TXCTRL, 32'h0002_0001);                      //отправить и дождаться
        tb_recv(0, b, p, s); tb_recv(0, b, p, s);

        //#9 Петля tx -> rx, порог rxwm, прерывание по заполнению FIFO приёма
        loop = 1'b1;
        bus_wr(RXCTRL, 32'h0002_0001);                      //rxen, rxcnt = 2: прерывание при 3 байтах
        bus_wr(IE, 2);
        bus_wr(TXDATA, 8'hA1); bus_wr(TXDATA, 8'hA2);
        repeat (25 * BIT) @(posedge clk);
        check_rd(IP, 1, "rxwm: 2 байта - ещё не больше порога (txwm = 1)");
        check(irq == 1'b0, "rxwm: irq нет", irq, 0);
        bus_wr(TXDATA, 8'hA3);
        repeat (13 * BIT) @(posedge clk);
        check_rd(IP, 3, "rxwm: 3 байта > 2");
        check(irq == 1'b1, "rxwm: irq", irq, 1);
        check_rd(RXDATA, 8'hA1, "петля: A1");
        check_rd(RXDATA, 8'hA2, "петля: A2");
        tick(2);
        check(irq == 1'b0, "rxwm: irq снят после чтения", irq, 0);
        check_rd(RXDATA, 8'hA3, "петля: A3");

        //#10 Переполнение FIFO приёма: 9-й байт потерян, флаг overrun и прерывание err
        bus_wr(IE, 4);
        for (int i = 0; i < 9; i++) bus_wr(TXDATA, 32'h40 + i);
        repeat (9 * 11 * BIT) @(posedge clk);
        check_rd(ERR, 4, "overrun: флаг");
        tick(2);
        check(irq == 1'b1, "overrun: irq err", irq, 1);
        for (int i = 0; i < 8; i++) check_rd(RXDATA, 32'h40 + i, $sformatf("overrun: байт %0d сохранён", i));
        check_rd(RXDATA, 32'h8000_0000, "overrun: 9-й байт потерян");
        bus_wr(ERR, 4);
        tick(2);
        check(irq == 1'b0, "overrun: флаг сброшен, irq снят", irq, 0);

        finish_tests();
    end
endmodule
