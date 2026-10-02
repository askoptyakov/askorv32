`timescale 1ns/1ps
//==============================================================================================
// tb_spiflash - тест контроллера SPI-флеш (spiflash.sv) через шину регистров и модель флеш
//==============================================================================================
//DESCRIPTION: Ручной режим: значения после сброса, кадры CS (один обмен и удержание CTRL.cs),
//обмен 1, 2 и 4 байтами (sb/sh/sw), JEDEC ID, регистр состояния, WREN/WRDI, флаг ovr,
//стирание сектора, запись страницы через окно 0x100, чтение с автозапуском (rdauto), делитель SCK.
//Временные проверки линий SPI (монитор): режим 0, MOSI выставлен не меньше чем за такт до фронта
//SCK, CS опускается раньше первого фронта SCK, пауза CS не меньше 3 тактов.
//Загрузчик: пробуждение флеш (AB), образ из двух сегментов (проверка, затем копирование - запись
//в память только во втором чтении), образа нет, испорченная контрольная сумма, неверный адрес
//сегмента, слишком длинный образ - во всех ошибочных случаях записей в память нет; флеш в глубоком
//сне перед сбросом; обращения программы во время загрузки игнорируются; BOOT_EN = 0.
//Модель флеш - sim/spiflash_model.sv. Запуск: py hw/sim/run_periph_tests.py spiflash
module tb_spiflash;
    localparam string DEV = "spiflash";
    `include "periph_tb.svh"

    localparam logic [31:0] CTRL = 32'h00, STAT = 32'h04, DIV = 32'h08, DATA = 32'h0C, BOOT = 32'h10, WIN = 32'h100;
    localparam logic [31:0] DUT2 = 32'h1000;               //Второй экземпляр (BOOT_EN = 0)
    localparam logic [31:0] MAGIC = 32'h3156_5241;
    localparam logic [23:0] BADDR = 24'h01_0000;           //Адрес образа во флеш
    localparam int          BW    = 64;                    //Предел образа, слов

    //#1 Два контроллера на одной шине (бит 12 адреса - второй) и две модели флеш
    wire        sck, cs_n, mosi, miso, sck2, cs2_n, mosi2, miso2;
    wire        hold, hold2;
    wire [ 3:0] bW, bW2;
    wire [31:0] bA, bD, bA2, bD2, RData1, RData2;
    wire        sel2 = Addr[12];
    pullup (miso);
    pullup (miso2);
    spiflash_top #(.MEMORY_TYPE(1'b1), .DIV_INIT(1), .BOOT_EN(1'b1), .BOOT_ADDR(BADDR), .BOOT_WORDS(BW), .WAKE_CLKS(20)) dut
        (.clk(clk), .rst(rst), .Write(sel2 ? 4'b0 : Write), .Read(Read & ~sel2), .Addr(Addr), .WData(WData), .RData(RData1),
         .spi_sck(sck), .spi_cs_n(cs_n), .spi_mosi(mosi), .spi_miso(miso),
         .boot_hold(hold), .boot_Write(bW), .boot_Addr(bA), .boot_WData(bD));
    spiflash_top #(.MEMORY_TYPE(1'b1), .DIV_INIT(5), .BOOT_EN(1'b0)) dut2
        (.clk(clk), .rst(rst), .Write(sel2 ? Write : 4'b0), .Read(Read & sel2), .Addr(Addr), .WData(WData), .RData(RData2),
         .spi_sck(sck2), .spi_cs_n(cs2_n), .spi_mosi(mosi2), .spi_miso(miso2),
         .boot_hold(hold2), .boot_Write(bW2), .boot_Addr(bA2), .boot_WData(bD2));
    assign RData = sel2 ? RData2 : RData1;
    spiflash_model #(.MEM_BYTES(1 << 18)) flash  (.cs_n(cs_n),  .sck(sck),  .mosi(mosi),  .miso(miso));
    spiflash_model #(.MEM_BYTES(1 << 12)) flash2 (.cs_n(cs2_n), .sck(sck2), .mosi(mosi2), .miso(miso2));

    //#2 Записи загрузчика в память
    logic [31:0] wr_a [0:255], wr_d [0:255];
    int          nw = 0, first_wr_reads = -1, bad_strobe = 0;
    always @(posedge clk) begin
        if (|bW) begin
            if (bW != 4'b1111) bad_strobe++;
            if (nw == 0) first_wr_reads = flash.n_read;
            if (nw < 256) begin wr_a[nw] = bA; wr_d[nw] = bD; end
            nw++;
        end
        if (|bW2) bad_strobe++;
    end

    //#3 Монитор линий SPI: режим 0 и времена (в тактах шины 2 * CLK_HALF)
    localparam real TCLK = 2 * CLK_HALF;
    realtime t_mosi = 0, t_cs_fall = 0, t_cs_rise = -1000, t_sck_rise = 0;
    real     sck_period = 0;
    int      mon_err = 0;
    always @(mosi) t_mosi = $realtime;
    always @(negedge cs_n) begin
        if ($realtime - t_cs_rise < 3 * TCLK - 0.1) begin
            mon_err++; $display("FAIL spiflash: CS высокий %0.1f нс < 3 тактов (%0t)", $realtime - t_cs_rise, $time);
        end
        t_cs_fall = $realtime;
    end
    always @(posedge cs_n) t_cs_rise = $realtime;
    always @(posedge sck) begin
        if (cs_n) begin mon_err++; $display("FAIL spiflash: фронт SCK при CS = 1 (%0t)", $time); end
        if ($realtime - t_mosi < TCLK - 0.1) begin
            mon_err++; $display("FAIL spiflash: MOSI сменился за %0.1f нс до фронта SCK (%0t)", $realtime - t_mosi, $time);
        end
        if ($realtime - t_cs_fall < TCLK - 0.1) begin
            mon_err++; $display("FAIL spiflash: фронт SCK через %0.1f нс после опускания CS (%0t)", $realtime - t_cs_fall, $time);
        end
        sck_period = $realtime - t_sck_rise;
        t_sck_rise = $realtime;
    end

    //#4 Операции с флеш через регистры (как библиотека spiflash.c)
    function automatic logic [31:0] cmd_addr(input logic [7:0] c, input logic [23:0] a);
        return {a[7:0], a[15:8], a[23:16], c};
    endfunction
    task automatic wait_ready();
        logic [31:0] v;
        do bus_rd(STAT, v); while (v[0]);
    endtask
    task automatic wait_boot();
        @(negedge clk);
        while (hold) @(negedge clk);
    endtask
    task automatic xfer(input logic [31:0] d, input logic [3:0] s, output logic [31:0] r);
        wait_ready();
        bus_wrb(DATA, d, s);
        wait_ready();
        bus_rd(DATA, r);
    endtask
    task automatic rd_status(output logic [7:0] st);
        logic [31:0] r;
        xfer(32'h05, 4'b0011, r);
        st = r[15:8];
    endtask
    task automatic wait_wip();
        logic [7:0] st;
        do rd_status(st); while (st[0]);
    endtask
    task automatic wren();
        logic [31:0] r;
        xfer(32'h06, 4'b0001, r);
    endtask
    task automatic erase4k(input logic [23:0] a);
        logic [31:0] r;
        wren();
        xfer(cmd_addr(8'h20, a), 4'b1111, r);
        wait_wip();
    endtask

    logic [31:0] buf_w [0:127];
    logic [31:0] buf_r [0:127];
    //Запись n слов из buf_w (в пределах страницы): кадр CTRL.cs, команда 02, слова через окно
    task automatic prog_page(input logic [23:0] a, input int n);
        wren();
        wait_ready();
        bus_wr(CTRL, 32'h1);
        bus_wr(DATA, cmd_addr(8'h02, a));
        for (int i = 0; i < n; i++) begin
            wait_ready();
            bus_wr(WIN + 4 * (i % 64), buf_w[i]);
        end
        bus_wr(CTRL, 32'h0);
        wait_wip();
    endtask
    //Чтение n слов в buf_r: кадр с автозапуском; первое чтение DATA - ответ на команду (отбрасывается)
    task automatic read_words(input logic [23:0] a, input int n);
        logic [31:0] v;
        wait_ready();
        bus_wr(CTRL, 32'h3);
        bus_wr(DATA, cmd_addr(8'h03, a));
        wait_ready();
        bus_rd(WIN, v);
        for (int i = 0; i < n; i++) begin
            wait_ready();
            bus_rd(WIN + 4 * ((i + 1) % 64), v);
            buf_r[i] = v;                                   //Через переменную: элемент массива как output задачи роняет Icarus
        end
        bus_wr(CTRL, 32'h0);
    endtask

    //#5 Образ для загрузчика: собирается в img, ожидаемые записи - в exp_a/exp_d
    logic [31:0] img [0:255], exp_a [0:255], exp_d [0:255];
    int          img_n = 0, exp_n = 0;
    task automatic img_start();
        img_n = 0; exp_n = 0;
        img[img_n] = MAGIC; img_n++;
    endtask
    task automatic img_seg(input logic [31:0] a, input int n, input logic [31:0] seed);
        img[img_n] = a; img_n++;
        img[img_n] = n; img_n++;
        for (int k = 0; k < n; k++) begin
            img[img_n] = seed ^ (k * 32'h0101_0101) ^ (k << 28); img_n++;
            exp_a[exp_n] = a + 4 * k; exp_d[exp_n] = img[img_n - 1]; exp_n++;
        end
    endtask
    task automatic img_end();
        logic [31:0] s = 0;
        img[img_n] = 0; img_n++;
        img[img_n] = 0; img_n++;
        for (int i = 0; i < img_n; i++) s += img[i];
        img[img_n] = -s; img_n++;
    endtask
    //Образ - в модель флеш напрямую (после него - стёртая память)
    task automatic img_store();
        for (int i = 0; i < 4096; i++) flash.mem[BADDR + i] = 8'hFF;
        for (int i = 0; i < img_n; i++)
            for (int b = 0; b < 4; b++) flash.mem[BADDR + 4 * i + b] = img[i][8 * b +: 8];
    endtask

    //Итог загрузки - BOOT[2:0] (в [31:16] - сколько слов прочитано до ошибки)
    task automatic check_boot(input logic [2:0] st, input string what);
        logic [31:0] v;
        bus_rd(BOOT, v);
        check(v[2:0] == st, what, v, st);
    endtask

    //Сброс и загрузка: число чтений флеш и записей в память - от начала загрузки
    int reads0;
    task automatic reboot();
        nw = 0; first_wr_reads = -1;
        reads0 = flash.n_read;
        reset_dut();
        check(hold == 1'b1, "загрузчик: ядро держится в сбросе после снятия rst", hold, 1);
        wait_boot();
    endtask
    task automatic check_writes(input string what);
        int bad = 0;
        check(nw == exp_n, {what, ": число записей в память"}, nw, exp_n);
        for (int i = 0; i < exp_n && i < nw; i++)
            if (wr_a[i] !== exp_a[i] || wr_d[i] !== exp_d[i]) begin
                if (bad == 0) check(1'b0, $sformatf("%0s: запись %0d (адрес %08h)", what, i, wr_a[i]), wr_d[i], exp_d[i]);
                bad++;
            end
    endtask

    logic [31:0] v, r;
    logic [ 7:0] st;
    int          n0;

    initial begin
        //#1 Сброс: флеш пуста - образа нет, ядро отпущено; значения регистров
        reboot();
        check_boot(2, "загрузка: образа нет (BOOT = 2)");
        check(nw == 0, "образа нет: записей в память нет", nw, 0);
        check(flash.n_wake == 1, "загрузка: флеш разбужена командой AB", flash.n_wake, 1);
        check_rd(CTRL, 0, "сброс: CTRL");
        check_rd(STAT, 0, "сброс: STAT");
        check_rd(DIV,  1, "сброс: DIV = DIV_INIT");
        check_rd(DUT2 + DIV,  5, "второй: DIV = 5");
        check_rd(DUT2 + BOOT, 0, "второй: BOOT_EN = 0 (BOOT = 0)");
        check(hold2 == 1'b0, "второй: BOOT_EN = 0 - ядро не держится", hold2, 0);

        //#2 Обмен 1, 2, 4 байтами
        xfer(32'h0000_009F, 4'b1111, r);
        check(r == 32'h1660_85FF, "JEDEC ID: 85 60 16 в байтах 1..3", r, 32'h1660_85FF);
        xfer(32'hAAAA_AA06, 4'b0001, r);                   //Байт: обмен одним младшим байтом
        check(flash.wel == 1'b1, "WREN байтом: WEL = 1", flash.wel, 1);
        check(r == 32'h0000_00FF, "байт: принятый байт - в младшем, остальные 0", r, 32'h0000_00FF);
        xfer(32'hAAAA_0005, 4'b0011, r);                   //Полуслово: два байта
        check(r == 32'h0000_02FF, "состояние полусловом: WEL в байте 1", r, 32'h0000_02FF);
        xfer(32'h0000_0004, 4'b0001, r);
        rd_status(st);
        check(st == 8'h00, "WRDI: WEL = 0", st, 0);
        check(flash.last_cmd == 8'h05, "последняя команда флеш - 05", flash.last_cmd, 8'h05);

        //#3 Запуск во время обмена: ovr, обмен не выполнен; сброс записью 1
        wait_ready();
        n0 = flash.n_cmd;
        bus_wr(DATA, 32'h05);
        bus_wr(DATA, 32'h9F);
        wait_ready();
        check_rd(STAT, 32'h2, "ovr: второй запуск при busy");
        check(flash.n_cmd == n0 + 1, "ovr: флеш получила одну команду", flash.n_cmd, n0 + 1);
        bus_wr(STAT, 32'h2);
        check_rd(STAT, 32'h0, "ovr сброшен записью 1");
        //Запуск сразу после кадра (в паузе CS): не выполняется и не сливается с прошлым кадром
        wait_ready();
        n0 = flash.n_cmd;
        bus_wrb(DATA, 32'h06, 4'b0001);
        wait (!dut.sh_busy);
        bus_wrb(DATA, 32'h04, 4'b0001);
        wait_ready();
        check_rd(STAT, 32'h2, "запуск в паузе CS: ovr");
        check(flash.n_cmd == n0 + 1 && flash.wel == 1'b1, "запуск в паузе CS: флеш получила только WREN", flash.n_cmd - n0, 1);
        bus_wr(STAT, 32'h2);
        xfer(32'h04, 4'b0001, r);

        //#4 Стирание, запись страницы через окно, чтение с автозапуском
        for (int i = 0; i < 64; i++) buf_w[i] = 32'hC0DE_0000 + i * 32'h0001_0101;
        erase4k(24'h00_2000);
        check(flash.mem[24'h2000] == 8'hFF && flash.mem[24'h2FFF] == 8'hFF, "стирание сектора 0x2000", flash.mem[24'h2000], 8'hFF);
        prog_page(24'h00_2000, 64);
        check({flash.mem[24'h2003], flash.mem[24'h2002], flash.mem[24'h2001], flash.mem[24'h2000]} == buf_w[0],
              "запись страницы: слово 0 во флеш (младший байт - по младшему адресу)",
              {flash.mem[24'h2003], flash.mem[24'h2002], flash.mem[24'h2001], flash.mem[24'h2000]}, buf_w[0]);
        read_words(24'h00_2000, 64);
        n0 = 0;
        for (int i = 0; i < 64; i++) if (buf_r[i] !== buf_w[i]) n0++;
        check(n0 == 0, "чтение страницы (rdauto) = записанному, слов с ошибкой", n0, 0);
        check(buf_r[63] == buf_w[63], "чтение: последнее слово", buf_r[63], buf_w[63]);
        //Неполная страница со смещением; запись только сбрасывает биты
        for (int i = 0; i < 8; i++) buf_w[i] = 32'hFFFF_FF00 | i;
        prog_page(24'h00_2100, 8);
        buf_w[0] = 32'h0F0F_0F0F;
        prog_page(24'h00_2100, 1);
        read_words(24'h00_20FC, 3);
        check(buf_r[0] == 32'hC0DE_0000 + 63 * 32'h0001_0101, "чтение через границу страниц: 0x20FC", buf_r[0], 32'hC0DE_0000 + 63 * 32'h0001_0101);
        check(buf_r[1] == 32'h0F0F_0F00, "повторная запись - И со старым содержимым", buf_r[1], 32'h0F0F_0F00);
        check(buf_r[2] == 32'hFFFF_FF01, "неполная страница: слово 1", buf_r[2], 32'hFFFF_FF01);

        //#5 Делитель SCK: период 2 * (DIV + 1) тактов; чтение на наибольшей частоте
        bus_wr(DIV, 0);
        xfer(32'h9F, 4'b1111, r);
        check(sck_period == 2 * TCLK, "DIV = 0: период SCK 2 такта", sck_period, 2 * TCLK);
        read_words(24'h00_2000, 16);
        n0 = 0;
        for (int i = 0; i < 16; i++) if (buf_r[i] !== 32'hC0DE_0000 + i * 32'h0001_0101) n0++;
        check(n0 == 0, "DIV = 0: чтение без ошибок", n0, 0);
        bus_wr(DIV, 3);
        xfer(32'h9F, 4'b1111, r);
        check(sck_period == 8 * TCLK, "DIV = 3: период SCK 8 тактов", sck_period, 8 * TCLK);
        check(r == 32'h1660_85FF, "DIV = 3: JEDEC ID", r, 32'h1660_85FF);

        //#6 Загрузчик: образ из двух сегментов (IMEM и DMEM)
        img_start();
        img_seg(32'h0000_0000, 5, 32'h1300_0093);
        img_seg(32'h1000_0100, 3, 32'hA5A5_0000);
        img_end();
        img_store();
        fork begin                                              //Обращения программы во время загрузки игнорируются
            repeat (40) @(negedge clk);
            bus_wr(DATA, 32'h9F);
        end join_none
        reboot();
        check_rd(BOOT, {16'd16, 16'd1}, "загрузка: образ 16 слов, BOOT = 1");
        check_writes("загрузка");
        check(flash.n_read - reads0 == 2, "загрузка: два чтения образа (проверка и копирование)", flash.n_read - reads0, 2);
        check(first_wr_reads - reads0 == 2, "загрузка: запись в память только во втором чтении", first_wr_reads - reads0, 2);
        wait_ready();                                           //Пауза CS после загрузки
        check_rd(STAT, 0, "загрузка: запись программы во время загрузки не выполнена (ovr = 0)");
        check_rd(DIV, 1, "загрузка: DIV после сброса");

        //Испорченная контрольная сумма: в память ничего не пишется
        img[4] = img[4] ^ 32'h0000_0100;
        img_store();
        reboot();
        check_boot(3, "контрольная сумма: BOOT = 3");
        check(nw == 0, "контрольная сумма: записей нет", nw, 0);
        check(flash.n_read - reads0 == 1, "контрольная сумма: одно чтение (проверка)", flash.n_read - reads0, 1);
        //Неверный признак
        img[4] = img[4] ^ 32'h0000_0100;
        img[0] = 32'h3156_5242;
        img_store();
        reboot();
        check_boot(2, "признак не совпал: BOOT = 2");
        check(nw == 0, "признак не совпал: записей нет", nw, 0);
        //Сегмент вне IMEM/DMEM
        img_start();
        img_seg(32'h0000_0000, 2, 32'h1);
        img_seg(32'h0200_0000, 2, 32'h2);
        img_end();
        img_store();
        reboot();
        check_rd(BOOT, {16'd7, 16'd4}, "сегмент вне памяти: BOOT = 4, ошибка в 7-м слове (число слов сегмента)");
        check(nw == 0, "сегмент вне памяти: записей нет", nw, 0);
        //Невыровненный адрес сегмента
        img_start();
        img_seg(32'h1000_0002, 2, 32'h1);
        img_end();
        img_store();
        reboot();
        check_boot(4, "невыровненный сегмент: BOOT = 4");
        //Сегмент длиннее предела и образ длиннее предела из коротких сегментов
        img_start();
        img_seg(32'h0000_0000, BW + 1, 32'h3);
        img_end();
        img_store();
        reboot();
        check_boot(4, "сегмент длиннее BOOT_WORDS: BOOT = 4");
        img_start();
        img_seg(32'h0000_0000, 40, 32'h4);
        img_seg(32'h1000_0000, 40, 32'h5);
        img_end();
        img_store();
        reboot();
        check_boot(4, "образ длиннее BOOT_WORDS: BOOT = 4");
        check(nw == 0, "длинный образ: записей нет", nw, 0);

        //Флеш в глубоком сне перед сбросом: загрузчик будит её
        img_start();
        img_seg(32'h0000_0040, 4, 32'h0000_0013);
        img_end();
        img_store();
        xfer(32'hB9, 4'b0001, r);
        check(flash.deep == 1'b1, "глубокий сон (B9)", flash.deep, 1);
        reboot();
        check(flash.deep == 1'b0, "загрузчик разбудил флеш (AB)", flash.deep, 0);
        check_rd(BOOT, {16'd10, 16'd1}, "после сна: образ 10 слов, BOOT = 1");
        check_writes("после сна");

        //#7 Итог: протокол SPI и строб записи загрузчика
        check(flash.errors == 0, "модель флеш: нарушений протокола", flash.errors, 0);
        check(flash2.errors == 0, "модель флеш 2: нарушений протокола", flash2.errors, 0);
        check(mon_err == 0, "монитор линий SPI: нарушений", mon_err, 0);
        check(bad_strobe == 0, "записи загрузчика - словами", bad_strobe, 0);
        finish_tests();
    end
endmodule
