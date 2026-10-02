`timescale 1ns/1ps
//==============================================================================================
// spiflash_model - модель флеш-памяти SPI (режим 0, однобитный SPI) для тестов
//==============================================================================================
//DESCRIPTION: Поведенческая модель микросхемы вроде PUYA P25Q32U (Tang Nano 9K, U3) для тестов
//контроллера spiflash_top (tb_spiflash.sv) и загрузки программы в тестах ядра (hw/sim, --boot).
//Только для моделирования, в проект ПЛИС не входит. Образец - spiflash.v из PicoSoC (YosysHQ/picorv32),
//здесь добавлены запись страницы, стирание, регистр состояния и проверки протокола.
//
//Команды: 03 чтение, 0B быстрое чтение (1 байт ожидания), 05 регистр состояния ([0] WIP, [1] WEL),
//06/04 разрешение/запрет записи, 02 запись страницы (до 256 байт, адрес по кругу в странице,
//биты только сбрасываются в 0), 20/52/D8 стирание 4/32/64 кБайт, 60/C7 стирание всей памяти,
//9F JEDEC ID (85 60 16 - PUYA, 32 Мбит), B9 глубокий сон, AB выход из сна, FF - выход из
//непрерывного чтения (ничего не делает).
//Данные: MOSI берётся по фронту SCK, MISO меняется после спада SCK с задержкой T_CLQV.
//Проверки (счётчик errors, текст - в журнале): SCK = 1 при опускании CS (не режим 0), подъём CS
//не на границе байта, команда во время записи/стирания (кроме 05), запись без WEL.
module spiflash_model
  #(parameter int  MEM_BYTES = 1 << 20,     //Объём модели (адрес берётся по модулю)
    parameter real T_CLQV    = 7.0,         //Задержка MISO после спада SCK, нс
    parameter real T_PP      = 3000.0,      //Запись страницы, нс (в микросхеме - до 3 мс)
    parameter real T_SE      = 10000.0,     //Стирание 4 кБайт
    parameter real T_BE      = 20000.0,     //Стирание 32/64 кБайт
    parameter real T_CE      = 40000.0,     //Стирание всей памяти
    parameter bit  VERBOSE   = 0)
   (input  logic cs_n, sck, mosi,
    output wire  miso);

    logic [7:0] mem [0:MEM_BYTES-1];
    initial for (int i = 0; i < MEM_BYTES; i++) mem[i] = 8'hFF;

    //Счётчики для тестов
    int errors = 0, n_cmd = 0, n_read = 0, n_prog = 0, n_erase = 0, n_wake = 0;
    logic [7:0] last_cmd = 8'h00;
    logic wel = 1'b0, wip = 1'b0, deep = 1'b0;

    logic [7:0]  sr = 8'h00, cmd = 8'h00, out_byte = 8'hFF;
    int          bitc = 0, bytec = 0;
    logic [23:0] addr = '0;
    logic        out_en = 1'b0, out_bit = 1'b1, drive = 1'b0;
    logic [7:0]  page [0:255];
    int          pp_n = 0;
    logic        ignore = 1'b0;                     //Команда в глубоком сне - пропускается
    int          n_pp, first_pp, sz, base_e;        //Рабочие переменные команд записи

    assign #(T_CLQV) miso = out_en ? out_bit : 1'bz;

    task automatic error(input string s);
        errors++;
        $display("FLASH ERROR (%0t): %0s", $time, s);
    endtask

    function automatic logic [7:0] status();
        return {6'd0, wel, wip};
    endfunction

    function automatic int a(input logic [23:0] x);
        return int'(x) % MEM_BYTES;
    endfunction

    //Начало кадра
    always @(negedge cs_n) begin
        if (sck !== 1'b0) error("SCK != 0 при опускании CS (нужен режим 0)");
        bitc = 0; bytec = 0; out_en = 1'b0; drive = 1'b0; ignore = 1'b0; pp_n = 0;
    end

    //Приём байта
    task automatic byte_in(input logic [7:0] b);
        bytec++;
        if (bytec == 1) begin
            cmd = b; last_cmd = b; n_cmd++;
            if (VERBOSE) $display("FLASH (%0t): команда %02h", $time, b);
            if (deep && b != 8'hAB) begin ignore = 1'b1; return; end
            if (wip && b != 8'h05) error($sformatf("команда %02h во время записи/стирания", b));
            case (b)
                8'h05: begin out_byte = status(); drive = 1'b1; end
                8'h9F: begin out_byte = 8'h85;    drive = 1'b1; end
                default: ;
            endcase
            return;
        end
        if (ignore) return;
        case (cmd)
            8'h03, 8'h0B: begin
                if (bytec == 2) addr[23:16] = b;
                if (bytec == 3) addr[15:8]  = b;
                if (bytec == 4) begin addr[7:0] = b; n_read++; end
                if (bytec >= (cmd == 8'h03 ? 4 : 5)) begin
                    out_byte = mem[a(addr)]; addr++; drive = 1'b1;
                end
            end
            8'h05: out_byte = status();
            8'h9F: out_byte = (bytec == 2) ? 8'h60 : (bytec == 3) ? 8'h16 : 8'h00;
            8'h02: begin
                if (bytec == 2) addr[23:16] = b;
                if (bytec == 3) addr[15:8]  = b;
                if (bytec == 4) addr[7:0]   = b;
                if (bytec >= 5) begin page[pp_n % 256] = b; pp_n++; end
            end
            8'h20, 8'h52, 8'hD8: begin
                if (bytec == 2) addr[23:16] = b;
                if (bytec == 3) addr[15:8]  = b;
                if (bytec == 4) addr[7:0]   = b;
            end
            default: ;
        endcase
    endtask

    always @(posedge sck) if (!cs_n) begin
        sr = {sr[6:0], mosi};
        if (mosi !== 1'b0 && mosi !== 1'b1) error("MOSI не определён на фронте SCK");
        bitc++;
        if (bitc == 8) begin bitc = 0; byte_in(sr); end
    end

    //MISO включается со спада SCK после байта команды/адреса (до него - третье состояние)
    always @(negedge sck) if (!cs_n && drive) begin
        out_en   = 1'b1;
        out_bit  = out_byte[7];
        out_byte = {out_byte[6:0], 1'b1};
    end

    //Запись/стирание: WIP = 1 на время t (отдельный процесс - fork в задаче Icarus не любит)
    real  wip_t = 0;
    event wip_ev;
    task automatic busy_for(input real t);
        wip = 1'b1;
        wip_t = t;
        -> wip_ev;
    endtask
    always @(wip_ev) begin
        #(wip_t);
        wip = 1'b0; wel = 1'b0;
    end

    //Конец кадра: команды записи выполняются по подъёму CS
    always @(posedge cs_n) begin
        out_en = 1'b0; drive = 1'b0;
        if (bitc != 0 && bytec != 0) error($sformatf("подъём CS не на границе байта (команда %02h, бит %0d)", cmd, bitc));
        if (!ignore && bytec > 0 && !(wip && cmd != 8'h05))
            case (cmd)
                8'h06: if (bytec == 1) wel = 1'b1;
                8'h04: if (bytec == 1) wel = 1'b0;
                8'hB9: if (bytec == 1) deep = 1'b1;
                8'hAB: begin deep = 1'b0; n_wake++; end
                8'h02: if (bytec >= 5) begin
                           if (!wel) error("запись страницы без WEL");
                           else begin
                               n_pp = (pp_n > 256) ? 256 : pp_n;
                               first_pp = (pp_n > 256) ? pp_n - 256 : 0;
                               for (int k = 0; k < n_pp; k++)
                                   mem[a({addr[23:8], 8'(addr[7:0] + k)})] &= page[(first_pp + k) % 256];
                               n_prog++;
                               busy_for(T_PP);
                           end
                       end
                8'h20, 8'h52, 8'hD8: if (bytec == 4) begin
                           if (!wel) error("стирание без WEL");
                           else begin
                               sz = (cmd == 8'h20) ? 4096 : (cmd == 8'h52) ? 32768 : 65536;
                               base_e = a(addr) & ~(sz - 1);
                               for (int k = 0; k < sz; k++) mem[(base_e + k) % MEM_BYTES] = 8'hFF;
                               n_erase++;
                               busy_for(cmd == 8'h20 ? T_SE : T_BE);
                           end
                       end
                8'h60, 8'hC7: if (bytec == 1) begin
                           if (!wel) error("стирание без WEL");
                           else begin
                               for (int k = 0; k < MEM_BYTES; k++) mem[k] = 8'hFF;
                               n_erase++;
                               busy_for(T_CE);
                           end
                       end
                default: ;
            endcase
    end

    //Загрузка содержимого: файл $readmemh по байтам с адреса offset
    task automatic load(input string file, input int offset);
        $readmemh(file, mem, offset);
    endtask
endmodule
