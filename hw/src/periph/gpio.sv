module gpio_top 
  #(parameter                      MEMORY_TYPE = 0)
   (input  logic                   clk, rst,
    // Интерфейс обмена
    input  logic            [ 3:0] Write,
    input  logic            [31:0] Addr, WData, 
    output logic            [31:0] RData,
    // Физические подключения
    inout                   [31:0] io_ports
);
    //Карта регистров:
    //>>0x00 - Установка типа порта: 1(Выход), 0(Вход)
    //>>0x04 - Установка уровня порта: 1(Вкл), 0(Выкл)
    //<<0x08 - Состояние порта
    logic [31:0] out_r, oe_r;

    always_ff @(posedge clk)
        case (Addr[3:2])
            0 : begin
                    if (Write[0]) oe_r[7:0]   <= WData[7:0];
                    if (Write[1]) oe_r[15:8]  <= WData[15:8];
                    if (Write[2]) oe_r[23:16] <= WData[23:16];
                    if (Write[3]) oe_r[31:24] <= WData[31:24];
                end
            1 : begin
                    if (Write[0]) out_r[7:0]   <= WData[7:0];
                    if (Write[1]) out_r[15:8]  <= WData[15:8];
                    if (Write[2]) out_r[23:16] <= WData[23:16];
                    if (Write[3]) out_r[31:24] <= WData[31:24];
                end
        endcase

    generate if (MEMORY_TYPE) begin   //#1 - Память BSRAM
        always_ff @(posedge clk)
            case (Addr[3:2])
                0 : RData <= oe_r;
                1 : RData <= out_r;
                2 : RData <= io_ports;
          default : RData <= 32'd0;
            endcase
    end else begin                    //#0 - Синтезированная память
        always_comb
            case (Addr[3:2])
                0 : RData = oe_r;
                1 : RData = out_r;
                2 : RData = io_ports;
          default : RData = 32'd0;
            endcase
    end
    endgenerate

    generate
        for (genvar i = 0; i < 32; i = i + 1) begin
            assign io_ports[i] = oe_r[i] ? out_r[i] : 1'bz;
        end
    endgenerate
 
endmodule