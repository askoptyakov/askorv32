module stim_top 
  #(parameter                      MEMORY_TYPE = 0)
   (input  logic                   clk, rst,
    // Интерфейс обмена
    input  logic            [ 3:0] Write,
    input  logic            [31:0] Addr, WData, 
    output logic            [31:0] RData,
    // Физические подключения
    output  logic                   tim_out
);
    //Карта регистров:
    //>>0x00 - Установка предделителя частоты таймера
    //>>0x04 - Установка напрвление счёта
    //>>0x08 - Установка значения переполнения таймера
    //>>0x0c - Установка значение сравнения
    //<<0x10 - Текущее значение счетчика таймера

    logic [31:0] tim_presclaer, tim_counter_mode, tim_counter_period, tim_pulse;
    logic [31:0] tim_counter;

    always_ff @(posedge clk)
        case (Addr[4:2])
            0 : begin
                    if (Write[0]) tim_presclaer[7:0]            <= WData[7:0];
                    if (Write[1]) tim_presclaer[15:8]           <= WData[15:8];
                    if (Write[2]) tim_presclaer[23:16]          <= WData[23:16];
                    if (Write[3]) tim_presclaer[31:24]          <= WData[31:24];
                end
            1 : begin
                    if (Write[0]) tim_counter_mode[7:0]         <= WData[7:0];
                    if (Write[1]) tim_counter_mode[15:8]        <= WData[15:8];
                    if (Write[2]) tim_counter_mode[23:16]       <= WData[23:16];
                    if (Write[3]) tim_counter_mode[31:24]       <= WData[31:24];
                end
            2 : begin
                    if (Write[0]) tim_counter_period[7:0]       <= WData[7:0];
                    if (Write[1]) tim_counter_period[15:8]      <= WData[15:8];
                    if (Write[2]) tim_counter_period[23:16]     <= WData[23:16];
                    if (Write[3]) tim_counter_period[31:24]     <= WData[31:24];
                end
            3 : begin
                    if (Write[0]) tim_pulse[7:0]                <= WData[7:0];
                    if (Write[1]) tim_pulse[15:8]               <= WData[15:8];
                    if (Write[2]) tim_pulse[23:16]              <= WData[23:16];
                    if (Write[3]) tim_pulse[31:24]              <= WData[31:24];
                end
        endcase

    generate if (MEMORY_TYPE) begin   //#1 - Память BSRAM
        always_ff @(posedge clk)
            case (Addr[4:2])
                0 : RData <= {16'd0, tim_presclaer[15:0]};
                1 : RData <= {16'd0, tim_counter_mode[15:0]};
                2 : RData <= {16'd0, tim_counter_period[15:0]};
                3 : RData <= {16'd0, tim_pulse[15:0]};
                4 : RData <= {16'd0, tim_counter[15:0]};
          default : RData <= 32'd0;
            endcase
    end else begin                    //#0 - Синтезированная память
        always_comb
            case (Addr[4:2])
                0 : RData <= {16'd0, tim_presclaer[15:0]};
                1 : RData <= {16'd0, tim_counter_mode[15:0]};
                2 : RData <= {16'd0, tim_counter_period[15:0]};
                3 : RData <= {16'd0, tim_pulse[15:0]};
                4 : RData <= {16'd0, tim_counter[15:0]};
          default : RData = 32'd0;
            endcase
    end
    endgenerate

    simple_tim simple_tim  (.clk(clk), .rst(rst),
                            .prescaler(tim_presclaer), .counter_mode(tim_counter_mode), .counter_period(tim_counter_period),
                            .pulse(tim_pulse), .out_counter(tim_counter));

endmodule


module simple_tim (
	input logic clk,
	input logic rst,
	input logic[15:0] prescaler,
	input logic[1:0] counter_mode,
	input logic[15:0] counter_period,
	input logic[15:0] pulse,
    input logic auto_reload_preload,

	output logic out_p_1,
	output logic out_n_1,
	output logic[15:0] out_counter
);

	logic[15:0] counter_tim = 0;
    logic[15:0] counter_period_tim = 0; // теневой(основной) регистр переполнения
	logic enable;

   div_clk div_tim 
    (
        .clk      ( clk ),
        .rst      ( rst ),
        .prescaler( prescaler ),
        .clk_pre  ( enable )     
    );
   
   logic load;                    //переполнение  
   logic direction;               // 0 - вверх, 1 - вниз
 
   always_ff @(posedge clk or posedge rst) begin
      if (rst) begin
         counter_tim <= 0;
         direction <= 0; // Начинаем с счета вверх
         counter_period_tim <= counter_period;
      end 
      else if (enable) begin
         if(~auto_reload_preload) counter_period_tim <= counter_period;
         else if(load) counter_period_tim <= counter_period;
         case (counter_mode)
            2'b00: begin // Счет вверх
               if (load) counter_tim <= 0;
               else counter_tim <= counter_tim + 1;
            end
            2'b01: begin // Счет вниз
               if (load) counter_tim <= counter_period_tim;
               else counter_tim <= counter_tim - 1;
            end
            2'b10: begin // Счет вверх-вниз
               if (direction == 0) begin // Счет вверх
                  if (counter_tim == counter_period_tim) begin
                     direction <= 1; // Меняем направление на вниз
                     counter_tim <= counter_tim - 1;
                  end 
                  else counter_tim <= counter_tim + 1;
               end
               else begin // Счет вниз
                  if (counter_tim == 0) begin
                     direction <= 0; // Меняем направление на вверх
                     counter_tim <= counter_tim + 1;
                  end 
                  else counter_tim <= counter_tim - 1;
               end
            end
         endcase
      end
   end

assign load = (counter_mode == 2'b00 && counter_tim == counter_period_tim) ||
              (counter_mode == 2'b01 && counter_tim == 0);

assign out_counter = counter_tim;
assign out_n_1 = counter_tim >= pulse;
assign out_p_1 = ~out_n_1;

endmodule

module div_clk (
input logic clk,     // Входной тактовый сигнал
input logic rst,    // Сигнал сброса
input logic[15:0] prescaler, // Коэффициент деления
output logic clk_pre // Выходной деленный тактовый сигнал
);

   logic[15:0] counter = 0;

	always @(posedge clk or posedge rst)
		if (rst) counter <= 0;
		else begin
			if (prescaler == counter) counter <= 0;
			else counter <= counter + 1;
		end

	assign clk_pre = (counter == prescaler);

endmodule

