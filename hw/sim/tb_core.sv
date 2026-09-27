`timescale 1ns/1ps
//==============================================================================================
// tb_core - тестбенч ядра askoRV32 с памятью BSRAM (модель SP из библиотеки GOWIN prim_sim.v)
//==============================================================================================
//DESCRIPTION: Ядро core, память инструкций и память данных подключаются так же, как в top.sv,
//включая схему тактирования (clk_div2, для однотактного ядра - divideby3). Программа
//загружается в модели BSRAM перед снятием сброса, затем тестбенч ждёт записи по адресу
//TOHOST (протокол описан в tests/riscv_test.h).
//
//Параметры запуска vvp (подставляет run_tests.py):
//  +imem=<файл>   - образ памяти инструкций, 32-битные слова в hex (обязательно)
//  +dmem=<файл>   - образ памяти данных (необязательно)
//  +names=<файл>  - имена тестов: "<номер> <имя>" в каждой строке (необязательно)
//  +prog=<имя>    - имя программы для отчёта
//  +vcd=<файл>    - записать временные диаграммы для GTKWave
//
//Результат - одна строка "RESULT PASS|FAIL|INCOMPLETE|TIMEOUT ..." для run_tests.py.
//==============================================================================================
module tb_core;
    parameter bit CORE_TYPE = 0;      //1 - однотактное ядро; 0 - конвейерное (как в top.sv)
    parameter int TIMEOUT   = 200000; //Предельное число тактов ядра на одну программу

    localparam bit          MEM_TYPE = 1;              //BSRAM
    localparam int          MEM_KB   = 8;              //8 кБайт = 1 кластер из 4 блоков SP
    localparam int          WORDS    = MEM_KB * 1024 / 4;
    localparam logic [31:0] TOHOST   = 32'h1F00_0000;

    //#1 Тактирование как в top.sv: clk 27 МГц -> clk_div2 -> (однотактное ядро) divideby3
    logic clk = 1'b0;
    always #18.519 clk = ~clk;

    logic clk_div2 = 1'b0;
    always @(posedge clk) clk_div2 <= ~clk_div2;

    logic clk_core, clk_imem, clk_dmem;
    generate if (CORE_TYPE) begin : g_clk_div3
        divideby3 divideby3(.clk(clk_div2), .clk_div3(clk_core), .clk_imem(clk_imem), .clk_dmem(clk_dmem));
    end else begin : g_clk_div1
        assign clk_core = clk_div2;
        assign clk_imem = clk_div2;
        assign clk_dmem = clk_div2;
    end
    endgenerate

    logic rst = 1'b1;

    //#2 Ядро и память
    logic [31:0] imem_data, imem_addr;
    logic        imem_re, imem_rst;
    logic [31:0] dmem_ReadData, dmem_Addr, dmem_WriteData;
    logic [ 3:0] dmem_Write;

    core #(CORE_TYPE, MEM_TYPE, MEM_TYPE) dut
          (.clk(clk_core), .rst(rst),
           .imem_data(imem_data), .imem_re(imem_re), .imem_rst(imem_rst), .imem_addr(imem_addr),
           .dmem_ReadData(dmem_ReadData), .dmem_Write(dmem_Write),
           .dmem_Addr(dmem_Addr), .dmem_WriteData(dmem_WriteData));

    mem #(MEM_TYPE, 256, MEM_KB, "") imem
          (.clk(clk_imem), .reset(rst | imem_rst), .re(imem_re), .wstrb(4'b0000),
           .a(imem_addr), .wd(32'd0), .rd(imem_data));

    //Выбор памяти данных по адресу - как MATCH_ADDR/MATCH_MASK в memmux (0x10xxxxxx)
    logic dmem_sel;
    assign dmem_sel = (dmem_Addr[31:24] == 8'h10);

    mem #(MEM_TYPE, 256, MEM_KB, "") dmem
          (.clk(clk_dmem), .reset(rst), .re(1'b1), .wstrb(dmem_sel ? dmem_Write : 4'b0000),
           .a(dmem_Addr), .wd(dmem_WriteData), .rd(dmem_ReadData));

    //#3 Загрузка программы в модели BSRAM
    //Байт j слова w лежит в блоке sector[j] по битам ram_MEM[w*8 +: 8]. Промежуточный регистр
    //чтения модели (mem_t) пересчитывается только при смене адреса или бита mc - поэтому после
    //загрузки mc инвертируется.
    logic [31:0] imem_img [0:WORDS-1];
    logic [31:0] dmem_img [0:WORDS-1];

    `define LOAD_BSRAM(M, IMG) \
        for (int w = 0; w < WORDS; w++) begin \
            M.genblk1.cluster[0].sector[0].bsram.ram_MEM[w*8 +: 8] = IMG[w][ 7: 0]; \
            M.genblk1.cluster[0].sector[1].bsram.ram_MEM[w*8 +: 8] = IMG[w][15: 8]; \
            M.genblk1.cluster[0].sector[2].bsram.ram_MEM[w*8 +: 8] = IMG[w][23:16]; \
            M.genblk1.cluster[0].sector[3].bsram.ram_MEM[w*8 +: 8] = IMG[w][31:24]; \
        end \
        M.genblk1.cluster[0].sector[0].bsram.mc = ~M.genblk1.cluster[0].sector[0].bsram.mc; \
        M.genblk1.cluster[0].sector[1].bsram.mc = ~M.genblk1.cluster[0].sector[1].bsram.mc; \
        M.genblk1.cluster[0].sector[2].bsram.mc = ~M.genblk1.cluster[0].sector[2].bsram.mc; \
        M.genblk1.cluster[0].sector[3].bsram.mc = ~M.genblk1.cluster[0].sector[3].bsram.mc;

    //#4 Имена тестов
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

    //#5 Запуск
    logic [8*256-1:0] file;
    longint           cycles = 0;

    initial begin
        core_name = CORE_TYPE ? "single-cycle" : "pipeline";
        for (int i = 0; i < 4096; i++) tname[i] = "?";
        tname[0] = "startup"; //Номер 0 - код до первого теста
        for (int w = 0; w < WORDS; w++) begin imem_img[w] = 32'd0; dmem_img[w] = 32'd0; end

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
        `LOAD_BSRAM(imem, imem_img)
        `LOAD_BSRAM(dmem, dmem_img)

        repeat (8) @(posedge clk_core);
        rst <= 1'b0;
    end

    always @(posedge clk_core) if (!rst) cycles <= cycles + 1;

    //#6 Перехват записи по адресу TOHOST
    logic [31:0] arg_actual = 32'd0, arg_expected = 32'd0;

    always @(posedge clk_dmem)
        if (!rst && (|dmem_Write) && (dmem_Addr[31:4] == TOHOST[31:4]))
            case (dmem_Addr[3:0])
                4'h4: arg_actual   = dmem_WriteData;
                4'h8: arg_expected = dmem_WriteData;
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
            if (cycles >= TIMEOUT) begin
                $display("RESULT TIMEOUT %0s %0s test=%0d name=%0s pc=0x%08h cycles=%0d",
                         prog, core_name, dut.decode.rf[28], tname[dut.decode.rf[28] & 12'hFFF], dut.PCF, cycles);
                $finish;
            end
            if ($isunknown(dut.PCF)) begin
                $display("RESULT FAIL %0s %0s test=%0d name=%0s got=PC=X expected=PC cycles=%0d",
                         prog, core_name, dut.decode.rf[28], tname[dut.decode.rf[28] & 12'hFFF], cycles);
                $finish;
            end
        end
endmodule
