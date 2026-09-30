//==============================================================================================
// gpio_top - дискретные входы/выходы (GPIO), до 32 линий
//==============================================================================================
//DESCRIPTION: Описание, регистры и примеры - README.md в этой папке. Тест - tb_gpio.sv.
//Карта регистров (разряды WIDTH..31 читаются как 0, запись в них игнорируется):
//>>0x00 MODE - тип линии: 1 - выход, 0 - вход; после сброса все линии - входы
//>>0x04 OUT  - уровень выхода: 1 - высокий, 0 - низкий; после сброса 0
//<<0x08 IN   - текущее состояние выводов (для выхода - выводимый уровень)
//Регистровая часть - по шаблону periph_regs (hw/src/periph/periph_regs.sv).
module gpio_top
  #(parameter                      MEMORY_TYPE = 0,
    parameter int                  WIDTH       = 32) //Число линий (1..32): задаёт конфигуратор ПЛИС
   (input  logic                   clk, rst,
    // Интерфейс обмена
    input  logic            [ 3:0] Write,
    input  logic            [31:0] Addr, WData,
    output logic            [31:0] RData,
    // Физические подключения
    inout                   [WIDTH-1:0] io_ports
);
    logic [WIDTH-1:0] oe_r, out_r;

    logic [2:0][ 3:0] we;
    logic      [31:0] wdata;
    periph_regs #(.N(3), .MEMORY_TYPE(MEMORY_TYPE)) regs
        (.clk(clk), .Write(Write), .Read(1'b0), .Addr(Addr), .WData(WData), .RData(RData),
         .we(we), .re(), .wdata(wdata),
         .rdata({32'(io_ports),                                  //0x08 IN
                 32'(out_r),                                     //0x04 OUT
                 32'(oe_r)}));                                   //0x00 MODE

    //Сброс (кнопка или отладчик): все линии - входы, выходной уровень 0
    periph_reg #(.W(WIDTH)) r_mode (.clk(clk), .rst(rst), .we(we[0]), .wdata(wdata), .q(oe_r));
    periph_reg #(.W(WIDTH)) r_out  (.clk(clk), .rst(rst), .we(we[1]), .wdata(wdata), .q(out_r));

    for (genvar i = 0; i < WIDTH; i++) begin : g_io
        assign io_ports[i] = oe_r[i] ? out_r[i] : 1'bz;
    end
endmodule
