
module div_clk (
input logic clk,     // Входной тактовый сигнал
input logic rst,    // Сигнал сброса
input logic[15:0] prescaler, // Коэффициент деления
output logic clk_pre // Выходной деленный тактовый сигнал
);

  logic[15:0] counter = 0;

	always @(posedge clk or posedge rst)
		if (rst) begin
			counter <= 0;
		end
		else begin
			if (prescaler == counter) begin
				counter <= 0;
			end
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
	output logic out_n_1
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

	always @(posedge clk or posedge rst)
		if (rst) begin
			counter_tim <= 0;
		end
		else if (enable) begin
			if(counter_mode == 0) begin
				if (counter_period == counter_tim) counter_tim <= 0;
				else counter_tim <= counter_tim + 1;
			end
		end

	assign out_p_1 = (counter_tim == counter_period);
	assign out_n_1 = ~out_p_1;

endmodule

