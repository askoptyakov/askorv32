
module div_clk (
input logic clk,     // Входной тактовый сигнал
input logic rst,    // Сигнал сброса
input logic[31:0] prescaler, // Коэффициент деления
output logic clk_pre // Выходной деленный тактовый сигнал
);

  logic[31:0] counter = 0;

	always @(posedge clk or posedge rst)
		if (rst) begin
			counter <= 0;
			clk_pre <= 0;
		end
		else begin
			if ((prescaler - 1) == counter) begin
				clk_pre <= ~clk_pre;
				counter <= 0;
			end
			else counter <= counter + 1;
		end

endmodule



