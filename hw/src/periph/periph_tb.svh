//==============================================================================================
// periph_tb.svh - общая часть тестов периферии: такт, сброс, ведущий шины регистров, проверки
//==============================================================================================
//DESCRIPTION: Подключается в тестбенч устройства (`include "periph_tb.svh" внутри модуля).
//Моделирует ведущего шины регистров askoRV32 по её правилам (hw/info/architecture.md, «Шина
//данных и периферии»): запись - за один такт, строб чтения - на такт обращения, данные чтения
//берутся на следующем такте (устройства собираются с MEMORY_TYPE = 1, как в ПЛИС с BSRAM).
//Сигналы шины: Write, Read, Addr, WData -> устройство; RData <- устройство.
//
//Задачи:
//  bus_wr(addr, data)          - запись слова;
//  bus_wrb(addr, data, strobe) - запись с байтовыми стробами;
//  bus_rd(addr, data)          - чтение (с выдачей строба Read);
//  check(ok, what, got, exp)   - проверка: при ошибке печатает строку FAIL;
//  tick(n)                     - подождать n тактов;
//  finish_tests()              - итог: одна строка "RESULT PASS|FAIL <устройство> ..." для
//                                hw/sim/run_periph_tests.py и завершение моделирования.
//Перед включением задать строку DEV (имя устройства для отчёта):
//  localparam string DEV = "stim";
//==============================================================================================
    localparam real CLK_HALF = 10.0;          //Такт шины 50 МГц (значение для тестов не важно)

    logic        clk = 1'b0;
    logic        rst = 1'b1;
    always #(CLK_HALF) clk = ~clk;

    logic [ 3:0] Write = 4'b0000;
    logic        Read  = 1'b0;
    logic [31:0] Addr  = 32'd0;
    logic [31:0] WData = 32'd0;
    wire  [31:0] RData;

    int n_checks = 0, n_fail = 0;
    longint cycles = 0;
    always @(posedge clk) cycles <= cycles + 1;

    //Сброс: несколько тактов, снимается по спаду такта
    task automatic reset_dut(input int n = 4);
        rst = 1'b1;
        repeat (n) @(negedge clk);
        rst = 1'b0;
    endtask

    task automatic tick(input int n = 1);
        repeat (n) @(negedge clk);
    endtask

    //Запись: адрес, данные и стробы выставляются по спаду, устройство принимает их по фронту
    task automatic bus_wrb(input logic [31:0] a, input logic [31:0] d, input logic [3:0] strobe);
        @(negedge clk);
        Addr = a; WData = d; Write = strobe;
        @(negedge clk);
        Write = 4'b0000;
    endtask

    task automatic bus_wr(input logic [31:0] a, input logic [31:0] d);
        bus_wrb(a, d, 4'b1111);
    endtask

    //Чтение: такт обращения (адрес и Read), данные - из регистра устройства на следующем такте
    task automatic bus_rd(input logic [31:0] a, output logic [31:0] d);
        @(negedge clk);
        Addr = a; Read = 1'b1;
        @(negedge clk);
        Read = 1'b0;
        d = RData;
    endtask

    task automatic check(input bit ok, input string what, input logic [31:0] got, input logic [31:0] exp);
        n_checks++;
        if (!ok) begin
            n_fail++;
            $display("FAIL %0s: %0s  получено 0x%08h, ожидалось 0x%08h (такт %0d)", DEV, what, got, exp, cycles);
        end
    endtask

    //Чтение регистра и сравнение с ожидаемым значением
    task automatic check_rd(input logic [31:0] a, input logic [31:0] exp, input string what);
        logic [31:0] v;
        bus_rd(a, v);
        check(v === exp, what, v, exp);
    endtask

    task automatic finish_tests();
        if (n_fail == 0) $display("RESULT PASS %0s checks=%0d cycles=%0d", DEV, n_checks, cycles);
        else             $display("RESULT FAIL %0s failed=%0d of %0d cycles=%0d", DEV, n_fail, n_checks, cycles);
        $finish;
    endtask

    //Временные диаграммы: +vcd=<файл> (run_periph_tests.py --vcd)
    initial begin
        string vcd_file;
        if ($value$plusargs("vcd=%s", vcd_file)) begin
            $dumpfile(vcd_file);
            $dumpvars(0);
        end
    end

    //Защита от зависания теста
    initial begin
        #(CLK_HALF * 2 * 2_000_000);
        $display("RESULT TIMEOUT %0s checks=%0d", DEV, n_checks);
        $finish;
    end
