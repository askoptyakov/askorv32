
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


module tim (
	input logic clk,
	input logic rst,
	input logic[15:0] prescaler,
	input logic[1:0] counter_mode,
	input logic[15:0] counter_period,
	input logic[15:0] pulse,

	output logic out_p_1,
	output logic out_n_1,
	output logic[15:0] out_counter
);

	logic[15:0] counter_tim = 0;
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
   wire up_down = counter_mode;   // 0 - счёт вверх, 1 - счёт вниз
 
   always_ff @(posedge clk or posedge rst) begin
      if (rst) begin
         counter_tim <= 0;
         direction <= 0; // Начинаем с счета вверх
      end 
      else if (enable) begin
         case (counter_mode)
            2'b00: begin // Счет вверх
               if (load) counter_tim <= 0;
               else counter_tim <= counter_tim + 1;
            end
            2'b01: begin // Счет вниз
               if (load) counter_tim <= counter_period;
               else counter_tim <= counter_tim - 1;
            end
            2'b10: begin // Счет вверх-вниз
               if (direction == 0) begin // Счет вверх
                  if (counter_tim == counter_period) begin
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

assign load = (counter_mode == 2'b00 && counter_tim == counter_period) ||
              (counter_mode == 2'b01 && counter_tim == 0);

assign out_counter = counter_tim;
assign out_n_1 = counter_tim >= pulse;
assign out_p_1 = ~out_n_1;

endmodule

