// Bus-side adapter for HDL Coder output. One enable step is one 500 kHz sample.
module sifu_matlab (
    input  logic        clk, rst, tick,
    input  logic [5:0]  sync_n,
    input  logic [12:0] t_on,
    input  logic [13:0] t_off,
    output logic [6:1]  gates
);
    logic [5:0] pin_meta, pin_sync;
    always_ff @(posedge clk)
        if (rst) begin
            pin_meta <= '1;
            pin_sync <= '1;
        end else begin
            pin_meta <= sync_n;
            pin_sync <= pin_meta;
        end

    wire [11:0] first_tick = t_on  >= 13'd4095 ? 12'd4095 : t_on[11:0];
    wire [11:0] last_tick  = t_off >= 14'd4095 ? 12'd4095 : t_off[11:0];

    HDL_DUT generated_from_simulink (
        .clk(clk), .reset(rst), .clk_enable(tick),
        .alpha(first_tick), .end_tick(last_tick), .enable(1'b1),
        .AB(~pin_sync[0]), .BA(~pin_sync[1]),
        .BC(~pin_sync[2]), .CB(~pin_sync[3]),
        .CA(~pin_sync[4]), .AC(~pin_sync[5]),
        .VS1(gates[1]), .VS2(gates[2]), .VS3(gates[3]),
        .VS4(gates[4]), .VS5(gates[5]), .VS6(gates[6]),
        .ce_out()
    );
endmodule
