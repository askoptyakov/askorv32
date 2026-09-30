`timescale 1ns/1ps
//==============================================================================================
// tb_tm1638 - тест контроллера платы TM1638 (tm1638.sv) через шину регистров
//==============================================================================================
//DESCRIPTION: Регистры SEGS/LEDS/KEYS; последовательный интерфейс с моделью микросхемы TM1638:
//  - посылки (STB = 0) декодируются по фронту CLK, младший бит первым;
//  - проверяются команды чтения кнопок (0x42), записи (0x40), адреса (0xC0) и включения
//    индикатора (0x8F), а после адреса - 16 байт: цифры 8..1 в семисегментном коде и светодиоды;
//  - в фазе чтения модель выдаёт состояние кнопок, контроллер должен собрать его в KEYS.
//Запуск: py hw/sim/run_periph_tests.py tm1638
module tb_tm1638;
    localparam string DEV = "tm1638";
    `include "periph_tb.svh"

    localparam logic [31:0] SEGS = 32'h00, LEDS = 32'h04, KEYS = 32'h08;

    wire  tm_clk, tm_stb, tm_dio;
    tm1638_top #(.MEMORY_TYPE(1'b1), .CLK_MHZ(50)) dut
        (.clk(clk), .rst(rst), .Write(Write), .Addr(Addr), .WData(WData), .RData(RData),
         .tm_clk(tm_clk), .tm_stb(tm_stb), .tm_dio(tm_dio));

    //#1 Модель TM1638: посылки и ответ кнопками
    localparam int MAXT = 256, MAXB = 20;
    logic [7:0] tr_byte [0:MAXT-1][0:MAXB-1];     //Байты посылок
    int         tr_len  [0:MAXT-1];
    longint     tr_time [0:MAXT-1];              //Такт начала посылки
    int         n_tr = 0, bit_cnt = 0;
    logic [7:0] sh = 8'h00;

    wire dut_drives = dut.tm1638_board_controller.tm_rw;    //1 - DIO ведёт контроллер
    logic [7:0] key_state = 8'h00;
    logic [7:0] key_bytes [0:3];                  //Байты ответа: байт n - кнопки 7-n (бит 0) и 3-n (бит 4)
    always_comb for (int n = 0; n < 4; n++) key_bytes[n] = {3'b000, key_state[3-n], 3'b000, key_state[7-n]};
    int rd_bit = 0;
    assign tm_dio = dut_drives ? 1'bz : key_bytes[(rd_bit / 8) % 4][rd_bit % 8];

    always @(negedge tm_stb) begin
        tr_len[n_tr]  = 0;
        tr_time[n_tr] = cycles;
        bit_cnt = 0;
        rd_bit  = 0;
    end
    always @(posedge tm_stb) if (n_tr < MAXT - 1) n_tr++;
    always @(posedge tm_clk)
        if (!tm_stb) begin
            if (dut_drives) begin                   //Запись в микросхему: младший бит первым
                sh = {tm_dio, sh[7:1]};
                bit_cnt++;
                if (bit_cnt == 8) begin
                    if (tr_len[n_tr] < MAXB) tr_byte[n_tr][tr_len[n_tr]] = sh;
                    tr_len[n_tr]++;
                    bit_cnt = 0;
                end
            end else
                rd_bit++;                           //Чтение: следующий бит ответа
        end

    //Номер первой посылки с командой cmd, начатой не раньше такта t0 (или -1)
    function automatic int find_tr(input logic [7:0] cmd, input longint t0);
        for (int i = 0; i < n_tr; i++)
            if (tr_len[i] > 0 && tr_byte[i][0] == cmd && tr_time[i] >= t0) return i;
        return -1;
    endfunction

    //Ожидание посылки с командой cmd после такта t0
    task automatic wait_tr(input logic [7:0] cmd, input longint t0, output int idx);
        idx = -1;
        while (idx < 0) begin
            @(posedge tm_stb);
            #1;
            idx = find_tr(cmd, t0);
        end
    endtask

    //Семисегментный код цифры (как в контроллере)
    function automatic logic [7:0] seg(input logic [3:0] d);
        case (d)
            4'h0: return 8'h3F; 4'h1: return 8'h06; 4'h2: return 8'h5B; 4'h3: return 8'h4F;
            4'h4: return 8'h66; 4'h5: return 8'h6D; 4'h6: return 8'h7D; 4'h7: return 8'h07;
            4'h8: return 8'h7F; 4'h9: return 8'h67; 4'hA: return 8'h77; 4'hB: return 8'h7C;
            4'hC: return 8'h39; 4'hD: return 8'h5E; 4'hE: return 8'h79; default: return 8'h71;
        endcase
    endfunction

    int i, k;
    longint t0;
    logic [31:0] v;
    logic [7:0] exp;

    initial begin
        reset_dut();

        //#2 Регистры
        check_rd(SEGS, 0, "сброс: SEGS");
        check_rd(LEDS, 0, "сброс: LEDS");
        bus_wr(SEGS, 32'h1234_5678);  check_rd(SEGS, 32'h1234_5678, "SEGS 32 бита");
        bus_wr(LEDS, 32'hFFFF_FFA5);  check_rd(LEDS, 32'h0000_00A5, "LEDS 8 бит");
        bus_wrb(SEGS, 32'h00AB_0000, 4'b0100); check_rd(SEGS, 32'h12AB_5678, "SEGS: байт 2");
        bus_wr(SEGS, 32'h1234_5678);
        bus_wr(KEYS, 32'hFFFF_FFFF);  check_rd(KEYS, 0, "KEYS только для чтения");
        t0 = cycles;

        //#3 Посылки полного кадра после записи регистров (первый кадр мог начаться раньше)
        wait_tr(8'h42, t0, i); check(i >= 0, "команда чтения кнопок 0x42", i, 0);
        wait_tr(8'h40, t0, i); check(tr_len[i] == 1, "команда записи 0x40", tr_len[i], 1);
        wait_tr(8'hC0, tr_time[i], i);
        check(tr_len[i] == 17, "адрес 0xC0 + 16 байт", tr_len[i], 17);
        for (k = 0; k < 8; k++) begin
            exp = seg(4'(32'h1234_5678 >> (4 * (7 - k))));
            check(tr_byte[i][1 + 2*k] == exp, $sformatf("цифра %0d", k + 1), tr_byte[i][1 + 2*k], exp);
            exp = {7'd0, 8'hA5 >> (7 - k)};
            exp = exp & 8'h01;
            check(tr_byte[i][2 + 2*k] == exp, $sformatf("светодиод %0d", 8 - k), tr_byte[i][2 + 2*k], exp);
        end
        wait_tr(8'h8F, tr_time[i], i); check(tr_len[i] == 1, "включение индикатора 0x8F", tr_len[i], 1);

        //#4 Кнопки: модель нажимает 8 и 1, после очередного чтения они в KEYS
        key_state = 8'h81;
        t0 = cycles;
        wait_tr(8'h42, t0, i);
        tick(20);
        check_rd(KEYS, 32'h0000_0081, "KEYS после чтения кнопок");
        key_state = 8'h3C;
        t0 = cycles;
        wait_tr(8'h42, t0, i);
        tick(20);
        check_rd(KEYS, 32'h0000_003C, "KEYS: другая комбинация");

        finish_tests();
    end
endmodule
