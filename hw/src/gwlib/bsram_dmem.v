//Copyright (C)2014-2024 Gowin Semiconductor Corporation.
//All rights reserved.
//File Title: IP file
//Tool Version: V1.9.9.03 Education (64-bit)
//Part Number: GW1NR-LV9QN88PC6/I5
//Device: GW1NR-9
//Device Version: C
//Created Time: Wed Oct  9 14:36:10 2024

module bsram_dmem8k (dout, clk, oce, ce, reset, wre, ad, din);

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
defparam sp_inst_0.INIT_RAM_00 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_0.INIT_RAM_01 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_0.INIT_RAM_02 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_0.INIT_RAM_03 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_0.INIT_RAM_04 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_0.INIT_RAM_05 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_0.INIT_RAM_06 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_0.INIT_RAM_07 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_0.INIT_RAM_08 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_0.INIT_RAM_09 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_0.INIT_RAM_0A = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_0.INIT_RAM_0B = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_0.INIT_RAM_0C = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_0.INIT_RAM_0D = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_0.INIT_RAM_0E = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_0.INIT_RAM_0F = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_0.INIT_RAM_10 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_0.INIT_RAM_11 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_0.INIT_RAM_12 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_0.INIT_RAM_13 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_0.INIT_RAM_14 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_0.INIT_RAM_15 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_0.INIT_RAM_16 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_0.INIT_RAM_17 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_0.INIT_RAM_18 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_0.INIT_RAM_19 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_0.INIT_RAM_1A = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_0.INIT_RAM_1B = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_0.INIT_RAM_1C = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_0.INIT_RAM_1D = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_0.INIT_RAM_1E = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_0.INIT_RAM_1F = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_0.INIT_RAM_20 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_0.INIT_RAM_21 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_0.INIT_RAM_22 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_0.INIT_RAM_23 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_0.INIT_RAM_24 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_0.INIT_RAM_25 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_0.INIT_RAM_26 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_0.INIT_RAM_27 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_0.INIT_RAM_28 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_0.INIT_RAM_29 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_0.INIT_RAM_2A = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_0.INIT_RAM_2B = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_0.INIT_RAM_2C = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_0.INIT_RAM_2D = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_0.INIT_RAM_2E = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_0.INIT_RAM_2F = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_0.INIT_RAM_30 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_0.INIT_RAM_31 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_0.INIT_RAM_32 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_0.INIT_RAM_33 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_0.INIT_RAM_34 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_0.INIT_RAM_35 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_0.INIT_RAM_36 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_0.INIT_RAM_37 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_0.INIT_RAM_38 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_0.INIT_RAM_39 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_0.INIT_RAM_3A = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_0.INIT_RAM_3B = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_0.INIT_RAM_3C = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_0.INIT_RAM_3D = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_0.INIT_RAM_3E = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_0.INIT_RAM_3F = 256'h0000000000000000000000000000000000000000000000000000000000000000;

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
defparam sp_inst_1.INIT_RAM_00 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_1.INIT_RAM_01 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_1.INIT_RAM_02 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_1.INIT_RAM_03 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_1.INIT_RAM_04 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_1.INIT_RAM_05 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_1.INIT_RAM_06 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_1.INIT_RAM_07 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_1.INIT_RAM_08 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_1.INIT_RAM_09 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_1.INIT_RAM_0A = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_1.INIT_RAM_0B = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_1.INIT_RAM_0C = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_1.INIT_RAM_0D = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_1.INIT_RAM_0E = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_1.INIT_RAM_0F = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_1.INIT_RAM_10 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_1.INIT_RAM_11 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_1.INIT_RAM_12 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_1.INIT_RAM_13 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_1.INIT_RAM_14 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_1.INIT_RAM_15 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_1.INIT_RAM_16 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_1.INIT_RAM_17 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_1.INIT_RAM_18 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_1.INIT_RAM_19 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_1.INIT_RAM_1A = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_1.INIT_RAM_1B = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_1.INIT_RAM_1C = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_1.INIT_RAM_1D = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_1.INIT_RAM_1E = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_1.INIT_RAM_1F = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_1.INIT_RAM_20 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_1.INIT_RAM_21 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_1.INIT_RAM_22 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_1.INIT_RAM_23 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_1.INIT_RAM_24 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_1.INIT_RAM_25 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_1.INIT_RAM_26 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_1.INIT_RAM_27 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_1.INIT_RAM_28 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_1.INIT_RAM_29 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_1.INIT_RAM_2A = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_1.INIT_RAM_2B = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_1.INIT_RAM_2C = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_1.INIT_RAM_2D = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_1.INIT_RAM_2E = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_1.INIT_RAM_2F = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_1.INIT_RAM_30 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_1.INIT_RAM_31 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_1.INIT_RAM_32 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_1.INIT_RAM_33 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_1.INIT_RAM_34 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_1.INIT_RAM_35 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_1.INIT_RAM_36 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_1.INIT_RAM_37 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_1.INIT_RAM_38 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_1.INIT_RAM_39 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_1.INIT_RAM_3A = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_1.INIT_RAM_3B = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_1.INIT_RAM_3C = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_1.INIT_RAM_3D = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_1.INIT_RAM_3E = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_1.INIT_RAM_3F = 256'h0000000000000000000000000000000000000000000000000000000000000000;

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
defparam sp_inst_2.INIT_RAM_00 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_2.INIT_RAM_01 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_2.INIT_RAM_02 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_2.INIT_RAM_03 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_2.INIT_RAM_04 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_2.INIT_RAM_05 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_2.INIT_RAM_06 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_2.INIT_RAM_07 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_2.INIT_RAM_08 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_2.INIT_RAM_09 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_2.INIT_RAM_0A = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_2.INIT_RAM_0B = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_2.INIT_RAM_0C = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_2.INIT_RAM_0D = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_2.INIT_RAM_0E = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_2.INIT_RAM_0F = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_2.INIT_RAM_10 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_2.INIT_RAM_11 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_2.INIT_RAM_12 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_2.INIT_RAM_13 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_2.INIT_RAM_14 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_2.INIT_RAM_15 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_2.INIT_RAM_16 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_2.INIT_RAM_17 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_2.INIT_RAM_18 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_2.INIT_RAM_19 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_2.INIT_RAM_1A = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_2.INIT_RAM_1B = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_2.INIT_RAM_1C = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_2.INIT_RAM_1D = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_2.INIT_RAM_1E = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_2.INIT_RAM_1F = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_2.INIT_RAM_20 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_2.INIT_RAM_21 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_2.INIT_RAM_22 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_2.INIT_RAM_23 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_2.INIT_RAM_24 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_2.INIT_RAM_25 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_2.INIT_RAM_26 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_2.INIT_RAM_27 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_2.INIT_RAM_28 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_2.INIT_RAM_29 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_2.INIT_RAM_2A = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_2.INIT_RAM_2B = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_2.INIT_RAM_2C = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_2.INIT_RAM_2D = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_2.INIT_RAM_2E = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_2.INIT_RAM_2F = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_2.INIT_RAM_30 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_2.INIT_RAM_31 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_2.INIT_RAM_32 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_2.INIT_RAM_33 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_2.INIT_RAM_34 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_2.INIT_RAM_35 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_2.INIT_RAM_36 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_2.INIT_RAM_37 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_2.INIT_RAM_38 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_2.INIT_RAM_39 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_2.INIT_RAM_3A = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_2.INIT_RAM_3B = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_2.INIT_RAM_3C = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_2.INIT_RAM_3D = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_2.INIT_RAM_3E = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_2.INIT_RAM_3F = 256'h0000000000000000000000000000000000000000000000000000000000000000;

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
defparam sp_inst_3.INIT_RAM_00 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_3.INIT_RAM_01 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_3.INIT_RAM_02 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_3.INIT_RAM_03 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_3.INIT_RAM_04 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_3.INIT_RAM_05 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_3.INIT_RAM_06 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_3.INIT_RAM_07 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_3.INIT_RAM_08 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_3.INIT_RAM_09 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_3.INIT_RAM_0A = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_3.INIT_RAM_0B = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_3.INIT_RAM_0C = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_3.INIT_RAM_0D = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_3.INIT_RAM_0E = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_3.INIT_RAM_0F = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_3.INIT_RAM_10 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_3.INIT_RAM_11 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_3.INIT_RAM_12 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_3.INIT_RAM_13 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_3.INIT_RAM_14 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_3.INIT_RAM_15 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_3.INIT_RAM_16 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_3.INIT_RAM_17 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_3.INIT_RAM_18 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_3.INIT_RAM_19 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_3.INIT_RAM_1A = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_3.INIT_RAM_1B = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_3.INIT_RAM_1C = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_3.INIT_RAM_1D = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_3.INIT_RAM_1E = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_3.INIT_RAM_1F = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_3.INIT_RAM_20 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_3.INIT_RAM_21 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_3.INIT_RAM_22 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_3.INIT_RAM_23 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_3.INIT_RAM_24 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_3.INIT_RAM_25 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_3.INIT_RAM_26 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_3.INIT_RAM_27 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_3.INIT_RAM_28 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_3.INIT_RAM_29 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_3.INIT_RAM_2A = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_3.INIT_RAM_2B = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_3.INIT_RAM_2C = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_3.INIT_RAM_2D = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_3.INIT_RAM_2E = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_3.INIT_RAM_2F = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_3.INIT_RAM_30 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_3.INIT_RAM_31 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_3.INIT_RAM_32 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_3.INIT_RAM_33 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_3.INIT_RAM_34 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_3.INIT_RAM_35 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_3.INIT_RAM_36 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_3.INIT_RAM_37 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_3.INIT_RAM_38 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_3.INIT_RAM_39 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_3.INIT_RAM_3A = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_3.INIT_RAM_3B = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_3.INIT_RAM_3C = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_3.INIT_RAM_3D = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_3.INIT_RAM_3E = 256'h0000000000000000000000000000000000000000000000000000000000000000;
defparam sp_inst_3.INIT_RAM_3F = 256'h0000000000000000000000000000000000000000000000000000000000000000;

endmodule //bsram_dmem8k