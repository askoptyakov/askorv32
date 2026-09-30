`timescale 1ns/1ps
//==============================================================================================
// tb_core - тестбенч ядра askoRV32: процессор cpu.sv с памятью BSRAM, без периферии платы
//==============================================================================================
//DESCRIPTION: Моделируется процессор cpu.sv: ядро, память инструкций и данных (модели SP из
//библиотеки GOWIN prim_sim.v), системная шина memmux, CLINT, PLIC, отладчик, тактирование
//(rPLL, для однотактного ядра - divideby3) и сброс с кнопки. Пользовательской периферии нет:
//верхний уровень платы top.sv (его создаёт конфигуратор) в тесты ядра не входит, поэтому
//конфигурация платы на них не влияет. Периферия проверяется своими тестами в папках устройств
//(hw/src/periph/<устройство>/tb_*.sv, запуск - hw/sim/run_periph_tests.py).
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
//
//Устройства тестбенча на порту пользовательской периферии cpu (per_*), по правилам шины
//регистров (данные чтения - на следующем такте):
//  0x1F000000..08 - TOHOST: код завершения и аргументы
//  0x1F00000C     - консоль: младший байт записи выводится как символ
//  0x1F000014     - уровни источников PLIC 2..8 (бит N - источник N)
//  0x1F000100     - таймер тестбенча для тестов прерываний (модель таймера STIM без предделителя
//                   и режимов): 0x04 CR ([3] EN, [4] UIE), 0x08 PER, 0x10 CNT, 0x14 SR ([0] UIF,
//                   сброс записью 1). Период - PER + 1 тактов шины; запрос - LI0 и источник 1 PLIC
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

    //#1 Процессор cpu.sv: тактовый генератор 27 МГц и кнопка сброса
    logic clk   = 1'b0;
    logic rst_n = 1'b0;
    always #18.519 clk = ~clk;

    logic        tck = 1'b0, tms = 1'b1, tdi = 1'b0;  //JTAG: управляет сценарий отладки (tb_debug.svh)
    wire         tdo;
    wire         per_clk, per_rst;
    wire  [ 3:0] per_Write;
    wire         per_Read;
    wire  [31:0] per_Addr, per_WData;
    logic [31:0] per_RData = 32'd0;
    wire  [15:0] irq_local;
    wire  [ 8:1] irq_src;

    cpu #(.CORE_TYPE(CORE_TYPE),
          .IMEM_TYPE(1'b1), .BSRAM_IMEM_SIZE(IMEM_KB),
          .DMEM_TYPE(1'b1), .BSRAM_DMEM_SIZE(DMEM_KB), .PLIC_SOURCES(8))
        dut (.clk(clk), .rst_n(rst_n),
             .tck_pad_i(tck), .tms_pad_i(tms), .tdi_pad_i(tdi), .tdo_pad_o(tdo),
             .per_clk(per_clk), .per_rst(per_rst),
             .per_Write(per_Write), .per_Read(per_Read), .per_Addr(per_Addr), .per_WData(per_WData), .per_RData(per_RData),
             .irq_local(irq_local), .irq_src(irq_src));

    //Внутренние сигналы cpu.sv, на которые опирается тестбенч
    wire        clk_core = dut.clk_core;
    wire        clk_dmem = dut.clk_dmem;
    wire        rst      = dut.rst_sync;
    wire [ 3:0] dmem_Write     = dut.dmem_Write;
    wire [31:0] dmem_Addr      = dut.dmem_Addr;
    wire [31:0] dmem_WriteData = dut.dmem_WriteData;

    //#1.1 Устройства тестбенча на порту per_*: источники PLIC 2..8 (запись 0x1F000014) и таймер
    //для тестов прерываний (0x1F000100)
    localparam logic [31:0] SIM_PLIC = 32'h1F00_0014, SIM_TIM = 32'h1F00_0100;
    logic [31:0] sim_plic_src = 32'd0;
    logic [ 4:0] tim_cr  = '0;
    logic [15:0] tim_per = '0, tim_cnt = '0;
    logic        tim_uif = 1'b0, tim_irq = 1'b0;
    wire         tim_we_sr = (|per_Write) && per_Addr == SIM_TIM + 32'h14 && per_WData[0];
    always @(posedge per_clk)
        if (per_rst) begin
            sim_plic_src <= '0; tim_cr <= '0; tim_per <= '0; tim_cnt <= '0; tim_uif <= 1'b0; tim_irq <= 1'b0;
        end else begin
            if (|per_Write)
                case (per_Addr)
                    SIM_PLIC:          sim_plic_src <= per_WData;
                    SIM_TIM + 32'h04:  tim_cr       <= per_WData[4:0];
                    SIM_TIM + 32'h08:  tim_per      <= per_WData[15:0];
                    default: ;
                endcase
            if (tim_cr[3]) begin                                //EN: счёт вверх до PER, затем событие обновления
                if (tim_cnt >= tim_per) begin tim_cnt <= '0; tim_uif <= 1'b1; end
                else begin tim_cnt <= tim_cnt + 1'b1; if (tim_we_sr) tim_uif <= 1'b0; end
            end else begin
                tim_cnt <= '0;
                if (tim_we_sr) tim_uif <= 1'b0;
            end
            tim_irq <= tim_uif & tim_cr[4];                     //Запрос через регистр, как у STIM
        end
    //Данные чтения - на следующем такте (правила шины регистров)
    always @(posedge per_clk)
        case (per_Addr)
            SIM_TIM + 32'h04: per_RData <= 32'(tim_cr);
            SIM_TIM + 32'h08: per_RData <= 32'(tim_per);
            SIM_TIM + 32'h10: per_RData <= 32'(tim_cnt);
            SIM_TIM + 32'h14: per_RData <= 32'(tim_uif);
            default:          per_RData <= 32'd0;
        endcase
    assign irq_local = {15'd0, tim_irq};                          //LI0 (mcause 16)
    assign irq_src   = {sim_plic_src[8:2], tim_irq};              //Источник 1 - таймер, 2..8 - программа

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
    int trace_fd = 0, pctrace_fd = 0;
    initial if ($value$plusargs("trace=%s", file))   trace_fd   = $fopen(file, "w");
    initial if ($value$plusargs("pctrace=%s", file)) pctrace_fd = $fopen(file, "w");

    always @(posedge clk_core)
        if (trace_fd && !rst && dut.riscv.RegWriteW && dut.riscv.RdW != 5'd0)
            $fdisplay(trace_fd, "%08h x%0d=%08h", dut.riscv.PCPlus4W - 32'd4, dut.riscv.RdW, dut.riscv.ResultW);

    always @(posedge clk_dmem)
        if (trace_fd && !rst && (|dmem_Write))
            $fdisplay(trace_fd, "mem[%08h]%b=%08h", dmem_Addr, dmem_Write, dmem_WriteData);

    always @(posedge clk_core)
        if (pctrace_fd && !rst) $fdisplay(pctrace_fd, "%h", dut.riscv.PCF);


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
        $finish;
    endtask

    //#7 Аварийные ситуации: зависание и неопределённый PC
    always @(posedge clk_core)
        if (!rst) begin
            if (cycles >= timeout) begin
                $display("RESULT TIMEOUT %0s %0s test=%0d name=%0s pc=0x%08h cycles=%0d",
                         prog, core_name, dut.riscv.decode.rf[28], tname[dut.riscv.decode.rf[28] & 12'hFFF],
                         dut.riscv.PCF, cycles);
                        $finish;
            end
            if ($isunknown(dut.riscv.PCF)) begin
                $display("RESULT FAIL %0s %0s test=%0d name=%0s got=PC=X expected=PC cycles=%0d",
                         prog, core_name, dut.riscv.decode.rf[28], tname[dut.riscv.decode.rf[28] & 12'hFFF], cycles);
                $finish;
            end
        end
endmodule
