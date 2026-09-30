`timescale 1ns/1ps
//==============================================================================================
// tb_gpio - тест GPIO (gpio.sv) через шину регистров
//==============================================================================================
//DESCRIPTION: 8 линий: после сброса все - входы; выходы выдают OUT только там, где MODE = 1;
//IN читает выводы (и чужие уровни на входах, и свои выходы); разряды выше WIDTH не пишутся и
//читаются как 0; байтовые стробы; сброс во время работы возвращает линии во входы.
//Запуск: py hw/sim/run_periph_tests.py gpio
module tb_gpio;
    localparam string DEV = "gpio";
    `include "periph_tb.svh"

    localparam logic [31:0] MODE = 32'h00, OUT = 32'h04, IN = 32'h08;

    //Выводы: внешний источник (тестбенч) ведёт линии, где ext_en = 1
    logic [7:0] ext_en = 8'h00, ext_val = 8'h00;
    wire  [7:0] pins;
    for (genvar i = 0; i < 8; i++) begin : g_ext
        assign pins[i] = ext_en[i] ? ext_val[i] : 1'bz;
    end

    gpio_top #(.MEMORY_TYPE(1'b1), .WIDTH(8)) dut
        (.clk(clk), .rst(rst), .Write(Write), .Addr(Addr), .WData(WData), .RData(RData), .io_ports(pins));

    initial begin
        reset_dut();

        //#1 После сброса: все линии - входы, выводы не ведутся
        check_rd(MODE, 0, "сброс: MODE");
        check_rd(OUT,  0, "сброс: OUT");
        check(pins === 8'bzzzz_zzzz, "сброс: выводы отпущены", pins, 32'hz);

        //#2 Выходы - только там, где MODE = 1
        bus_wr(OUT, 32'h0000_00A5);
        check(pins === 8'bzzzz_zzzz, "OUT без MODE не выводится", pins, 32'hz);
        bus_wr(MODE, 32'h0000_000F);
        tick(1);
        check(pins[3:0] === 4'b0101, "выходы 0..3 = OUT", pins[3:0], 4'b0101);
        check(pins[7:4] === 4'bzzzz, "линии 4..7 - входы", pins[7:4], 32'hz);

        //#3 IN: входы от внешнего источника и собственные выходы
        ext_en = 8'hF0; ext_val = 8'h30;
        tick(1);
        check_rd(IN, 32'h0000_0035, "IN = внешние входы + выходы");
        ext_val = 8'hC0;
        tick(1);
        check_rd(IN, 32'h0000_00C5, "IN следит за входами");

        //#4 Разряды выше WIDTH не пишутся и читаются как 0
        bus_wr(MODE, 32'hFFFF_FF0F); check_rd(MODE, 32'h0000_000F, "MODE: 8 разрядов");
        bus_wr(OUT,  32'h1234_5605); check_rd(OUT,  32'h0000_0005, "OUT: 8 разрядов");

        //#5 Байтовые стробы: байт 1 у 8-разрядного GPIO ни на что не влияет
        bus_wrb(OUT, 32'h0000_FF00, 4'b0010); check_rd(OUT, 32'h0000_0005, "строб байта 1 не меняет OUT");
        bus_wrb(OUT, 32'h0000_000A, 4'b0001); check_rd(OUT, 32'h0000_000A, "строб байта 0");
        tick(1);
        check(pins[3:0] === 4'b1010, "выходы после записи байта", pins[3:0], 4'b1010);

        //#6 Сброс во время работы: линии снова входы
        reset_dut(2);
        tick(1);
        check(pins[3:0] === 4'bzzzz, "сброс отпускает выходы", pins[3:0], 32'hz);
        check_rd(MODE, 0, "сброс: MODE = 0");
        ext_en = 8'hFF; ext_val = 8'hC3;                     //Теперь все линии ведёт внешний источник
        tick(1);
        check_rd(IN, 32'h0000_00C3, "после сброса IN = внешние входы");

        finish_tests();
    end
endmodule
