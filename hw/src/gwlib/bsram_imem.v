//Copyright (C)2014-2024 Gowin Semiconductor Corporation.
//All rights reserved.
//File Title: IP file
//Tool Version: V1.9.9.03 Education (64-bit)
//Part Number: GW1NR-LV9QN88PC6/I5
//Device: GW1NR-9
//Device Version: C
//Created Time: Tue Oct 22 12:52:24 2024

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
defparam sp_inst_0.INIT_RAM_00 = 256'h939313939313B3139393131337E33313E313E333E313E313E313B39313939313;
defparam sp_inst_0.INIT_RAM_01 = 256'h0000000063233313EFB30323B3B33393633363B3B33313B393133313B3933363;

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
defparam sp_inst_1.INIT_RAM_00 = 256'hF46222830181D101D3010101017E01016E015E014E011E010E01040202030101;
defparam sp_inst_1.INIT_RAM_01 = 256'h0000000000A00101010421AA8303A20204A28882F2E281830151D1929341C192;

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
defparam sp_inst_2.INIT_RAM_00 = 256'h72821171C08123C121F050A10071714191D1713141217121311131F0B0702010;
defparam sp_inst_2.INIT_RAM_01 = 256'h0000000021219110805100712352230002417242412323518121931371C15444;

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
defparam sp_inst_3.INIT_RAM_00 = 256'h000002FF000040FF40FE00AA10FE00FFFEFFFE40FE00FE00FE00000000000000;
defparam sp_inst_3.INIT_RAM_01 = 256'h0000000000FC0000000000FE4000000000000200000000400000000000000004;

endmodule //bsram_imem8k
