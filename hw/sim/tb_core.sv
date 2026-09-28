`timescale 1ns/1ps
//==============================================================================================
// tb_core - тестбенч процессора askoRV32: модуль top.sv целиком с памятью BSRAM
//==============================================================================================
//DESCRIPTION: Моделируется вся система из top.sv: ядро, память инструкций и данных (модели
//SP из библиотеки GOWIN prim_sim.v), мультиплексор шины memmux, GPIO, TM1638, таймер STIM,
//CLINT, тактирование (clk_div2, для однотактного ядра - divideby3) и сброс с кнопки.
//Программа загружается в модели BSRAM до снятия сброса, затем тестбенч ждёт записи по
//адресу TOHOST (протокол описан в tests/riscv_test.h).
//
//Параметры запуска vvp (подставляют run_tests.py и run_bench.py):
//  +imem=<файл>   - образ памяти инструкций, 32-битные слова в hex (обязательно)
//  +dmem=<файл>   - образ памяти данных (необязательно)
//  +names=<файл>  - имена тестов: "<номер> <имя>" в каждой строке (необязательно)
//  +prog=<имя>    - имя программы для отчёта
//  +vcd=<файл>    - записать временные диаграммы для GTKWave
//  +timeout=<N>   - предельное число тактов ядра (по умолчанию TIMEOUT)
//  +trace=<файл>  - трасса записей в регистры и память
//  +pctrace=<файл>- PC на каждом такте ядра (профилирование однотактного ядра)
//  +leds=<файл>   - журнал переключений выходов GPIO (такт ядра и значение)
//
//Устройства моделирования (адреса вне карты памяти top.sv, запись никуда не попадает, её
//перехватывает тестбенч):
//  0x1F000000..08 - TOHOST: код завершения и аргументы
//  0x1F00000C     - консоль: младший байт записи выводится как символ
//  0x1F000014     - уровни источников PLIC 2..8 (бит N - источник N)
//+dbgtest - сценарий отладки через JTAG (tb_debug.svh) параллельно с программой
//
//Результат - одна строка "RESULT PASS|FAIL|INCOMPLETE|TIMEOUT ..." для run_tests.py.
//==============================================================================================
module tb_core;
    parameter bit CORE_TYPE = 0;      //1 - однотактное ядро; 0 - конвейерное (как в top.sv)
    parameter int TIMEOUT   = 200000; //Предельное число тактов ядра на одну программу
    parameter int IMEM_KB   = 8;      //Размер памяти инструкций: 8/16/32 кБайт (BSRAM_IMEM_SIZE)
    parameter int DMEM_KB   = 8;      //Размер памяти данных: 8/16/32 кБайт (BSRAM_DMEM_SIZE)

    localparam int          CLUSTER_W   = 2048;        //Слов в кластере (4 блока SP по 2 кБайт)
    localparam int          IMEM_WORDS  = IMEM_KB * 1024 / 4;
    localparam int          DMEM_WORDS  = DMEM_KB * 1024 / 4;
    localparam logic [31:0] TOHOST      = 32'h1F00_0000;

    //#1 Система top.sv: тактовый генератор 27 МГц и кнопка сброса
    logic clk   = 1'b0;
    logic rst_n = 1'b0;
    always #18.519 clk = ~clk;

    wire [5:0] led, GMB_GPIO;
    wire [1:0] GMB_DRIVER_E, GMB_DRIVER_D;
    wire [2:0] GPIO;
    logic      tck = 1'b0, tms = 1'b1, tdi = 1'b0;    //JTAG: управляет сценарий отладки (tb_debug.svh)
    wire       tdo;

    top #(.CORE_TYPE(CORE_TYPE),
          .IMEM_TYPE(1'b1), .BSRAM_IMEM_SIZE(IMEM_KB),
          .DMEM_TYPE(1'b1), .BSRAM_DMEM_SIZE(DMEM_KB))
        dut (.clk(clk), .rst_n(rst_n), .led(led), .GMB_GPIO(GMB_GPIO),
             .GMB_DRIVER_E(GMB_DRIVER_E), .GMB_DRIVER_D(GMB_DRIVER_D), .GPIO(GPIO),
             .tck_pad_i(tck), .tms_pad_i(tms), .tdi_pad_i(tdi), .tdo_pad_o(tdo));

    //Источники PLIC 2..8 выставляет программа записью по адресу 0x1F000014 (бит N - источник N),
    //источник 1 - таймер STIM, как в top.sv
    logic [31:0] sim_plic_src = 32'd0;
    wire [8:2] sim_irq_ext = sim_plic_src[8:2];      //Icarus: force от part-select переменной не отслеживается
    initial force dut.irq_ext = sim_irq_ext;

    //Внутренние сигналы top.sv, на которые опирается тестбенч
    wire        clk_core = dut.clk_core;
    wire        clk_dmem = dut.clk_dmem;
    wire        rst      = dut.rst_sync;
    wire [ 3:0] dmem_Write     = dut.dmem_Write;
    wire [31:0] dmem_Addr      = dut.dmem_Addr;
    wire [31:0] dmem_WriteData = dut.dmem_WriteData;

    //#2 Загрузка программы в модели BSRAM
    //Слово w кластера c: байт j лежит в блоке cluster[c].sector[j] по битам ram_MEM[w*8 +: 8].
    //Промежуточный регистр чтения модели (mem_t) пересчитывается только при смене адреса или
    //бита mc - поэтому после загрузки mc инвертируется.
    logic [31:0] imem_img [0:IMEM_WORDS-1];
    logic [31:0] dmem_img [0:DMEM_WORDS-1];

    //Icarus Verilog не допускает иерархических ссылок в generate-области других модулей из
    //generate-блоков, поэтому загрузка развёрнута по кластерам, а их число задаётся макросами
    //TB_IMEM_16K/TB_IMEM_32K и TB_DMEM_16K/TB_DMEM_32K (их вместе с IMEM_KB/DMEM_KB передаёт run_tests.py)
    `define LOAD_LANE(M, IMG, C, J) \
        for (int w = 0; w < CLUSTER_W; w++) \
            M.genblk1.cluster[C].sector[J].bsram.ram_MEM[w*8 +: 8] = IMG[C*CLUSTER_W + w][J*8 +: 8]; \
        M.genblk1.cluster[C].sector[J].bsram.mc = ~M.genblk1.cluster[C].sector[J].bsram.mc;
    `define LOAD_CLUSTER(M, IMG, C) `LOAD_LANE(M, IMG, C, 0) `LOAD_LANE(M, IMG, C, 1) `LOAD_LANE(M, IMG, C, 2) `LOAD_LANE(M, IMG, C, 3)

    //#3 Имена тестов
    logic [8*96-1:0] tname [0:4095];
    int              max_test = 0;
    logic [8*64-1:0] prog = "?";
    string           core_name;

    task automatic load_names(input logic [8*256-1:0] file);
        int fd, n, r;
        logic [8*96-1:0] s;
        fd = $fopen(file, "r");
        if (fd == 0) begin
            $display("RESULT ERROR %0s: не открыт файл имён %0s", prog, file);
            $finish;
        end
        while (!$feof(fd)) begin
            r = $fscanf(fd, "%d %s\n", n, s);
            if (r == 2 && n >= 0 && n < 4096) begin
                tname[n] = s;
                if (n > max_test) max_test = n;
            end
        end
        $fclose(fd);
    endtask

    //#4 Запуск
    logic [8*256-1:0] file;
    int               timeout = TIMEOUT;
    longint           cycles  = 0;

    initial begin
        core_name = CORE_TYPE ? "single-cycle" : "pipeline";
        for (int i = 0; i < 4096; i++) tname[i] = "?";
        tname[0] = "startup"; //Номер 0 - код до первого теста
        for (int w = 0; w < IMEM_WORDS; w++) imem_img[w] = 32'd0;
        for (int w = 0; w < DMEM_WORDS; w++) dmem_img[w] = 32'd0;
        if ($value$plusargs("timeout=%d", timeout)) ;

        if ($value$plusargs("prog=%s", prog)) ;
        if (!$value$plusargs("imem=%s", file)) begin
            $display("RESULT ERROR %0s: не задан +imem=<файл>", prog);
            $finish;
        end
        $readmemh(file, imem_img);
        if ($value$plusargs("dmem=%s", file)) $readmemh(file, dmem_img);
        if ($value$plusargs("names=%s", file)) load_names(file);
        if ($value$plusargs("vcd=%s", file)) begin
            $dumpfile(file);
            $dumpvars(0, tb_core);
        end

        #1;
        `LOAD_CLUSTER(dut.imem, imem_img, 0)
`ifdef TB_IMEM_16K
        `LOAD_CLUSTER(dut.imem, imem_img, 1)
`endif
`ifdef TB_IMEM_32K
        `LOAD_CLUSTER(dut.imem, imem_img, 1) `LOAD_CLUSTER(dut.imem, imem_img, 2) `LOAD_CLUSTER(dut.imem, imem_img, 3)
`endif
        `LOAD_CLUSTER(dut.dmem, dmem_img, 0)
`ifdef TB_DMEM_16K
        `LOAD_CLUSTER(dut.dmem, dmem_img, 1)
`endif
`ifdef TB_DMEM_32K
        `LOAD_CLUSTER(dut.dmem, dmem_img, 1) `LOAD_CLUSTER(dut.dmem, dmem_img, 2) `LOAD_CLUSTER(dut.dmem, dmem_img, 3)
`endif
        #1;

        //Кнопка сброса отпущена; сброс снимает устранитель дребезга top.sv через 16 тактов ядра
        repeat (4) @(posedge clk);
        rst_n = 1'b1;
    end

    always @(posedge clk_core) if (!rst) cycles <= cycles + 1;

    //#5 Трассы. Трасса записей в регистры и память (+trace) одинакова для обоих ядер, поэтому
    //первое расхождение трасс однотактного и конвейерного ядра указывает на ошибку
    int trace_fd = 0, pctrace_fd = 0, leds_fd = 0;
    initial if ($value$plusargs("trace=%s", file))   trace_fd   = $fopen(file, "w");
    initial if ($value$plusargs("pctrace=%s", file)) pctrace_fd = $fopen(file, "w");
    initial if ($value$plusargs("leds=%s", file))    leds_fd    = $fopen(file, "w");

    always @(posedge clk_core)
        if (trace_fd && !rst && dut.riscv.RegWriteW && dut.riscv.RdW != 5'd0)
            $fdisplay(trace_fd, "%08h x%0d=%08h", dut.riscv.PCPlus4W - 32'd4, dut.riscv.RdW, dut.riscv.ResultW);

    always @(posedge clk_dmem)
        if (trace_fd && !rst && (|dmem_Write))
            $fdisplay(trace_fd, "mem[%08h]%b=%08h", dmem_Addr, dmem_Write, dmem_WriteData);

    always @(posedge clk_core)
        if (pctrace_fd && !rst) $fdisplay(pctrace_fd, "%h", dut.riscv.PCF);

    //Журнал GPIO: такт ядра и новое значение регистра выходов
    logic [31:0] gpio_out_q = 32'd0;
    always @(posedge clk_core)
        if (leds_fd && !rst && dut.gpio.out_r !== gpio_out_q) begin
            $fdisplay(leds_fd, "%0d %08h", cycles, dut.gpio.out_r);
            gpio_out_q <= dut.gpio.out_r;
        end

    //#5.1 Сценарий отладки через JTAG
    `include "tb_debug.svh"
    initial if ($test$plusargs("dbgtest")) begin
        wait (!rst);
        repeat (20) @(posedge clk_core);
        dbg_scenario();
    end

    //#6 Перехват записи по адресу TOHOST
    logic [31:0] arg_actual = 32'd0, arg_expected = 32'd0;

    always @(posedge clk_dmem)
        if (!rst && (|dmem_Write) && (dmem_Addr[31:4] == TOHOST[31:4]))
            case (dmem_Addr[3:0])
                4'h4: arg_actual   = dmem_WriteData;
                4'h8: arg_expected = dmem_WriteData;
                4'hC: begin $write("%c", dmem_WriteData[7:0]); $fflush; end
                4'h0: finish_test(dmem_WriteData);
                default: ;
            endcase

    always @(posedge clk_dmem)
        if (!rst && (|dmem_Write) && dmem_Addr == 32'h1F00_0014) sim_plic_src <= dmem_WriteData;

    task automatic finish_test(input logic [31:0] code);
        int n;
        if (code == 32'd1) begin
            if (arg_actual == max_test)
                $display("RESULT PASS %0s %0s tests=%0d cycles=%0d", prog, core_name, arg_actual, cycles);
            else
                $display("RESULT INCOMPLETE %0s %0s last=%0d of %0d cycles=%0d",
                         prog, core_name, arg_actual, max_test, cycles);
        end else begin
            n = code >> 1;
            $display("RESULT FAIL %0s %0s test=%0d name=%0s got=0x%08h expected=0x%08h cycles=%0d",
                     prog, core_name, n, tname[n], arg_actual, arg_expected, cycles);
        end
        if (leds_fd) $fclose(leds_fd);
        $finish;
    endtask

    //#7 Аварийные ситуации: зависание и неопределённый PC
    always @(posedge clk_core)
        if (!rst) begin
            if (cycles >= timeout) begin
                $display("RESULT TIMEOUT %0s %0s test=%0d name=%0s pc=0x%08h cycles=%0d",
                         prog, core_name, dut.riscv.decode.rf[28], tname[dut.riscv.decode.rf[28] & 12'hFFF],
                         dut.riscv.PCF, cycles);
                if (leds_fd) $fclose(leds_fd);
                $finish;
            end
            if ($isunknown(dut.riscv.PCF)) begin
                $display("RESULT FAIL %0s %0s test=%0d name=%0s got=PC=X expected=PC cycles=%0d",
                         prog, core_name, dut.riscv.decode.rf[28], tname[dut.riscv.decode.rf[28] & 12'hFFF], cycles);
                $finish;
            end
        end
endmodule
