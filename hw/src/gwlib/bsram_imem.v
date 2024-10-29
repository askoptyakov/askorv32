//Copyright (C)2014-2024 Gowin Semiconductor Corporation.
//All rights reserved.
//File Title: IP file
//Tool Version: V1.9.9.03 Education (64-bit)
//Part Number: GW1NR-LV9QN88PC6/I5
//Device: GW1NR-9
//Device Version: C
//Created Time: Tue Oct 29 11:41:52 2024

module bsram_imem8k (dout, clk, oce, ce, reset, wre, ad, din);

output [31:0] dout;
input clk;
input oce;
input ce;
input reset;
input wre;
input [10:0] ad;
input [31:0] din;

wire [23:0] sp_inst_0_dout_w;
wire [23:0] sp_inst_1_dout_w;
wire [23:0] sp_inst_2_dout_w;
wire [23:0] sp_inst_3_dout_w;
wire gw_gnd;

assign gw_gnd = 1'b0;

SP sp_inst_0 (
    .DO({sp_inst_0_dout_w[23:0],dout[7:0]}),
    .CLK(clk),
    .OCE(oce),
    .CE(ce),
    .RESET(reset),
    .WRE(wre),
    .BLKSEL({gw_gnd,gw_gnd,gw_gnd}),
    .AD({ad[10:0],gw_gnd,gw_gnd,gw_gnd}),
    .DI({gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,din[7:0]})
);

defparam sp_inst_0.READ_MODE = 1'b0;
defparam sp_inst_0.WRITE_MODE = 2'b00;
defparam sp_inst_0.BIT_WIDTH = 8;
defparam sp_inst_0.BLK_SEL = 3'b000;
defparam sp_inst_0.RESET_MODE = "SYNC";
defparam sp_inst_0.INIT_RAM_00 = 256'h13E333E313E313E313B39313131313133333939393130383A30383B723131337;
defparam sp_inst_0.INIT_RAM_01 = 256'h3363B3B33313B393133313B3933363939313939313B3139393131337E33313E3;
defparam sp_inst_0.INIT_RAM_02 = 256'h0000000000000000000000000000000000000063233313EFB30323B3B3339363;

SP sp_inst_1 (
    .DO({sp_inst_1_dout_w[23:0],dout[15:8]}),
    .CLK(clk),
    .OCE(oce),
    .CE(ce),
    .RESET(reset),
    .WRE(wre),
    .BLKSEL({gw_gnd,gw_gnd,gw_gnd}),
    .AD({ad[10:0],gw_gnd,gw_gnd,gw_gnd}),
    .DI({gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,din[15:8]})
);

defparam sp_inst_1.READ_MODE = 1'b0;
defparam sp_inst_1.WRITE_MODE = 2'b00;
defparam sp_inst_1.BIT_WIDTH = 8;
defparam sp_inst_1.BLK_SEL = 3'b000;
defparam sp_inst_1.RESET_MODE = "SYNC";
defparam sp_inst_1.INIT_RAM_00 = 256'h015E014E011E010E01040202B2A2B2A2B2A20403010152131342038101010101;
defparam sp_inst_1.INIT_RAM_01 = 256'hA28882F2E281830151D1929341C192F46222830181D101D3010101017E01016E;
defparam sp_inst_1.INIT_RAM_02 = 256'h0000000000000000000000000000000000000000A00101010421AA8303A20204;

SP sp_inst_2 (
    .DO({sp_inst_2_dout_w[23:0],dout[23:16]}),
    .CLK(clk),
    .OCE(oce),
    .CE(ce),
    .RESET(reset),
    .WRE(wre),
    .BLKSEL({gw_gnd,gw_gnd,gw_gnd}),
    .AD({ad[10:0],gw_gnd,gw_gnd,gw_gnd}),
    .DI({gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,din[23:16]})
);

defparam sp_inst_2.READ_MODE = 1'b0;
defparam sp_inst_2.WRITE_MODE = 2'b00;
defparam sp_inst_2.BIT_WIDTH = 8;
defparam sp_inst_2.BLK_SEL = 3'b000;
defparam sp_inst_2.RESET_MODE = "SYNC";
defparam sp_inst_2.INIT_RAM_00 = 256'hD1713141217121311131F0B02424E4E43434B07020107070302020002000A100;
defparam sp_inst_2.INIT_RAM_01 = 256'h417242412323518121931371C1544472821171C08123C121F050A10071714191;
defparam sp_inst_2.INIT_RAM_02 = 256'h0000000000000000000000000000000000000021219110805100712352230002;

SP sp_inst_3 (
    .DO({sp_inst_3_dout_w[23:0],dout[31:24]}),
    .CLK(clk),
    .OCE(oce),
    .CE(ce),
    .RESET(reset),
    .WRE(wre),
    .BLKSEL({gw_gnd,gw_gnd,gw_gnd}),
    .AD({ad[10:0],gw_gnd,gw_gnd,gw_gnd}),
    .DI({gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,din[31:24]})
);

defparam sp_inst_3.READ_MODE = 1'b0;
defparam sp_inst_3.WRITE_MODE = 2'b00;
defparam sp_inst_3.BIT_WIDTH = 8;
defparam sp_inst_3.BLK_SEL = 3'b000;
defparam sp_inst_3.RESET_MODE = "SYNC";
defparam sp_inst_3.INIT_RAM_00 = 256'hFFFE40FE00FE00FE000000000000FFFF0000FF0000000000000000000008AA10;
defparam sp_inst_3.INIT_RAM_01 = 256'h000200000000400000000000000004000002FF000040FF40FE00AA10FE00FFFE;
defparam sp_inst_3.INIT_RAM_02 = 256'h0000000000000000000000000000000000000000FC0000000000FE4000000000;

endmodule //bsram_imem8k
