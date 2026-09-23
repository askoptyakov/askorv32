module top (
    input  clk,      // Тактовый сигнал 27 МГц

    input  button,
    input  sig_ntb_AB,
    input  sig_ntb_BA,
    input  sig_ntb_BC,
    input  sig_ntb_CB,
    input  sig_ntb_CA,
    input  sig_ntb_AC,
    output user_pin,
    output G1_DifD1, G2_DifD1, G1_DifD2, G2_DifD2, G1_DifD3, G2_DifD3

);


    wire sync_ba_filter;
    wire sync_ab_filter;
    wire sync_bc_filter;
    wire sync_cb_filter;
    wire sync_ac_filter;
    wire sync_ca_filter;
    wire clk_500kHz;
    wire ENABLE;

	assign user_pin = !(sig_ntb_AB && sig_ntb_BA && sig_ntb_BC && sig_ntb_CB && sig_ntb_CA && sig_ntb_AC);
    assign ENABLE = !(sig_ntb_AB && sig_ntb_BA && sig_ntb_BC && sig_ntb_CB && sig_ntb_CA && sig_ntb_AC);

    //assign ENABLE = (button) ? 0 : 1;
    // Регистры приема данных от MK
	reg [11:0] REG_DATA = 1000;             

	localparam DELAY_RC_COMPENSATION = 12'd400; 	//Сдвиг угла выпрямителя (альфа) для компенсации
																   //	фазового сдвига из-за RC цепочки для фильтрации
																   //	лин. напр.
	reg [11:0] alpha = DELAY_RC_COMPENSATION;
	reg [11:0] pulse = DELAY_RC_COMPENSATION + 150;
	
	always @(posedge clk) 
		begin 
			alpha <= REG_DATA[11:0] + DELAY_RC_COMPENSATION;
			pulse <= REG_DATA[11:0] + DELAY_RC_COMPENSATION + 150;
		end
                               
    //reg [11:0] alpha = 12'd400;                     //12'd400 - Сдвиг угла выпрямителя (альфа) для компенсации
   //reg [11:0] pulse = 12'd400 + 150;               //	фазового сдвига из-за RC цепочки для фильтрации
                                                    //	лин. напр.

    wire gate_thyr1_direct;
    wire gate_thyr2_direct;
    wire gate_thyr3_direct;
    wire gate_thyr4_direct;
    wire gate_thyr5_direct;
    wire gate_thyr6_direct;
	
    filter_2bit filter_2bit_ba(.in(sig_ntb_AB), .clock(clk), .out(sync_ab_filter));
    filter_2bit filter_2bit_ab(.in(sig_ntb_BA), .clock(clk), .out(sync_ba_filter));
    filter_2bit filter_2bit_cb(.in(sig_ntb_BC), .clock(clk), .out(sync_bc_filter));
    filter_2bit filter_2bit_bc(.in(sig_ntb_CB), .clock(clk), .out(sync_cb_filter));
    filter_2bit filter_2bit_ac(.in(sig_ntb_CA), .clock(clk), .out(sync_ca_filter));
    filter_2bit filter_2bit_ca(.in(sig_ntb_AC), .clock(clk), .out(sync_ac_filter));


	

	my_divider my_divider_1(.clock(clk), .out(clk_500kHz));

	OnePulse_3 OnePulse_3_1(
			.clock(clk_500kHz), .alfa(alpha), .pulse(pulse), 
			.sync1(sync_ab_filter), .sync2(sync_ba_filter),
			.thyr_out1(gate_thyr1_direct), .thyr_out2(gate_thyr4_direct)
	);

	OnePulse_3 OnePulse_3_2(
			.clock(clk_500kHz), .alfa(alpha), .pulse(pulse), 
			.sync1(sync_bc_filter), .sync2(sync_cb_filter),
			.thyr_out1(gate_thyr3_direct), .thyr_out2(gate_thyr6_direct)
	);
	
	OnePulse_3 OnePulse_3_3(
			.clock(clk_500kHz), .alfa(alpha), .pulse(pulse), 
			.sync1(sync_ca_filter), .sync2(sync_ac_filter),
			.thyr_out1(gate_thyr5_direct), .thyr_out2(gate_thyr2_direct)
	);
	
	// Добавление подтверждающего импульса на каждый тиристор для стабильной работы в режиме
	//прерывистого тока
	assign G2_DifD1 = (ENABLE)? (gate_thyr1_direct | gate_thyr2_direct) : 0;  //GATE_THYR1
	assign G1_DifD3 = (ENABLE)? (gate_thyr2_direct | gate_thyr3_direct) : 0;  //GATE_THYR2
	assign G2_DifD2 = (ENABLE)? (gate_thyr3_direct | gate_thyr4_direct) : 0;  //GATE_THYR3
	assign G1_DifD1 = (ENABLE)? (gate_thyr4_direct | gate_thyr5_direct) : 0;  //GATE_THYR4
	assign G2_DifD3 = (ENABLE)? (gate_thyr5_direct | gate_thyr6_direct) : 0;  //GATE_THYR5
	assign G1_DifD2 = (ENABLE)? (gate_thyr6_direct | gate_thyr1_direct) : 0;  //GATE_THYR6

endmodule


module filter_2bit(
	input in,
	input clock,
	output reg out
	);
	
	integer direction;
	reg condition;
	reg [1:0] cnt;
	wire a, b;
	wire c, d;
	
	//Счетчик с направлением счета (вверх, вниз)
	always @(posedge clock)
		begin
			if (in) direction = 1;
			else direction = -1;
			if (condition) cnt = cnt + direction;
		end
	
	//Меняем условие при помощи мультиплексора
	always @(a or b or in)
		begin
			condition = in? a: b;//b:a;
		end
	
	assign a = cnt < 3;
	assign b = cnt > 0;
	
	//Компаратор с гистерезисом
	always @(c, d) 
		begin
			if (d) 			out = 0;
			else 	if (c) 	out = 1;
	end
	
	assign c = (cnt == 3);
	assign d = (cnt == 0);
	
endmodule

module my_divider #(
    parameter integer ClkFrequency     = 27_000_000,
    parameter integer DesiredFrequency = 500_000
)(
    input  wire clock,
    output reg  out = 0  
);

    // 1. Расчет делителя для полупериода (меандр)
    localparam integer divisor = (ClkFrequency / DesiredFrequency) / 2;

    // 2. Правильный расчет ширины регистра через логарифм по основанию 2
    localparam integer bit_depth = $clog2(divisor);

    // 3. Объявление счетчика нужной ширины с инициализацией
    reg [bit_depth-1:0] count = 0;

    // 4. Единый синхронный процесс
    always @(posedge clock) begin
        if (count == divisor - 1) begin
            count <= 0;      
            out <= ~out;     
        end else begin
            count <= count + 1;
        end
    end

endmodule

module OnePulse_3(
	input clock,
	input [11:0] alfa,
	input [11:0] pulse,
	input sync1,
	input sync2,
	output thyr_out1,
	output thyr_out2
	);
	
	wire cn_t, cn_p;
	wire thyr_cond;
	reg [11:0] cnt;
	
	always @(posedge clock)
		if (sync1 & sync2) cnt <= 0;
		else cnt <= cnt + 1;
	
	assign cn_t = (cnt >= alfa);
   assign cn_p = (cnt <= pulse); 
	
	assign {thyr_out1, thyr_out2} = (cn_t & cn_p) ? {~sync1,~sync2} : {1'b0,1'b0}; 
endmodule
