module mem_mux
  #(parameter                      MEMORY_TYPE = 0, 
    parameter                      SLAVES      = 2, //Количество подчинённых устройств
    parameter    [(SLAVES*32)-1:0] MATCH_ADDR  = 0,
    parameter    [(SLAVES*32)-1:0] MATCH_MASK  = 0)
   (input  logic                   clk, rst,
    // Интерфейс мастера
    input  logic            [ 3:0] mWrite,
    input  logic            [31:0] mAddr, mWData, 
    output logic            [31:0] mRData,
    // Интерфейс подчинённых
    output logic [(SLAVES* 4)-1:0] sWrite,
    output logic [(SLAVES*32)-1:0] sAddr, sWData,
    input  logic [(SLAVES*32)-1:0] sRData
); 
    
    logic [SLAVES-1:0] match;
    generate
        for(genvar i=0; i<SLAVES ; i=i+1) begin : addr_match
            assign match[i] = (mAddr & MATCH_MASK[i*32+:32]) == MATCH_ADDR[i*32+:32];//rvfpga
            //assign match[i] = ~|((mAddr ^ MATCH_ADDR[i*32+:32]) & MATCH_MASK[i*32+:32]);//picotiny
            assign sWrite[i*4+:4] = mWrite & {4{match[i]}}; 
        end
    endgenerate

    localparam SSEL_WIDTH  = $clog2(SLAVES);
    logic [SSEL_WIDTH-1:0] ssel;
    always_comb begin
        ssel = '0;
        for (int i = 0; i < SLAVES; i++) begin
            if (match[i]) begin
                ssel = i;
                break;
            end
        end
    end
 
    assign sAddr  = {SLAVES{mAddr }};
    assign sWData = {SLAVES{mWData}};
    
    //Для памяти BSRAM сигнал выбора устройства должен быть регистровым,
    //а для синтезированной памяти сигнал выбора устройства должен быть комбинационным.
    generate if (MEMORY_TYPE) begin   //#1 - Память BSRAM
        logic [SSEL_WIDTH-1:0] ssel_r;
        always_ff @(posedge clk, posedge rst)
            if (rst) ssel_r <= SSEL_WIDTH'('0);
            else     ssel_r <= ssel;
        assign mRData = sRData[ssel_r*32+:32];
    end else begin                    //#0 - Синтезированная память
        assign mRData = sRData[ssel*32+:32];
    end
    endgenerate
endmodule

/*============================================================================
LED&KEY TM1638 board controller

Copyright 2023 Alexander Kirichenko

Based on https://github.com/alangarf/tm1638-verilog
Copyright 2017 Alan Garfield
==============================================================================*/

///////////////////////////////////////////////////////////////////////////////////
//                            TM1638 Controller
///////////////////////////////////////////////////////////////////////////////////
module tm1638_board_controller
# (
    parameter clk_mhz = 50
)
(
    input  logic        clk,
    input  logic        rst,
    input  logic [31:0] digit_in,
    input  logic [ 7:0] ledr,
    output logic [ 7:0] keys,
    //Внешний интерфейс
    output logic        sio_clk,
    output logic        sio_stb,
    inout  logic        sio_dio
);
    //#1 Decoder
    logic [2:0] count;
    always_ff @(posedge clk, posedge rst) begin
        if (rst) count <=0;
        else count <= count + 1'b1;
    end
    
    logic [31:0] digit_shift;
    assign digit_shift = digit_in >> (count * 4);
    
    logic [7:0] digit_seg;
    always_comb
        case(digit_shift[3:0])
            8'h0: digit_seg = 8'b00111111;//8'b11111100;  // h g f e d c b a
            8'h1: digit_seg = 8'b00000110;//8'b01100000;
            8'h2: digit_seg = 8'b01011011;//8'b11011010;  //   --a--
            8'h3: digit_seg = 8'b01001111;//8'b11110010;  //  |   |
            8'h4: digit_seg = 8'b01100110;//8'b01100110;  //  f   b
            8'h5: digit_seg = 8'b01101101;//8'b10110110;  //  |   |
            8'h6: digit_seg = 8'b01111101;//8'b10111110;  //   --g--
            8'h7: digit_seg = 8'b00000111;//8'b11100000;  //  |   |
            8'h8: digit_seg = 8'b01111111;//8'b11111110;  //  e   c
            8'h9: digit_seg = 8'b01100111;//8'b11100110;  //  |   |
            8'ha: digit_seg = 8'b01110111;//8'b11101110;  //   --d--  h
            8'hb: digit_seg = 8'b01111100;//8'b00111110;
            8'hc: digit_seg = 8'b00111001;//8'b10011100;
            8'hd: digit_seg = 8'b01011110;//8'b01111010;
            8'he: digit_seg = 8'b01111001;//8'b10011110;
            8'hf: digit_seg = 8'b01110001;//8'b10001110;
        endcase

    logic [7:0] digits [0:7];
    always @(posedge clk, posedge rst)
        if (rst) begin
            digits[0] <= 8'd0;
            digits[1] <= 8'd0;
            digits[2] <= 8'd0;
            digits[3] <= 8'd0;
            digits[4] <= 8'd0;
            digits[5] <= 8'd0;
            digits[6] <= 8'd0;
            digits[7] <= 8'd0;
        end
        else
            digits[count] <= digit_seg;
    
    //#2 Controller
    localparam
        HIGH    = 1'b1,
        LOW     = 1'b0;

    localparam [7:0]
        C_READ   = 8'b01000010,
        C_WRITE  = 8'b01000000,
        C_ADDR  = 8'b11000000,
        C_DISP  = 8'b10001111;

    localparam CLK_DIV = 4;//19; // speed of FSM scanner
    logic  [CLK_DIV:0] counter;

    // TM1632 requires at least 1us strobe duration
    // we can generate this by adding delay at the end of
    // each transfer. For that we define a flag indicating
    // completion of 1us delay loop.
    logic stb_delay_complete;
    assign stb_delay_complete = (counter > clk_mhz ? 1 : 0);

    logic  [5:0] instruction_step;
    logic  [7:0] led_on;

    logic        tm_rw;
    logic        dio_in, dio_out;

    // setup tm1638 module with it's tristate IO
    //   tm_in      is written to module
    //   tm_out     is read from module
    //   tm_latch   triggers the module to read/write display
    //   tm_rw      selects read or write mode to display
    //   busy       indicates when module is busy
    //                (another latch will interrupt)
    //   tm_clk     is the data clk
    //   dio_in     for reading from display
    //   dio_out    for sending to display
    //
    logic        tm_latch;
    logic        busy;
    logic  [7:0] tm_in, tm_out;

    ///////////// RESET synhronizer ////////////
    logic             reset_syn1;
    logic             reset_syn2 = 0;
    always_ff @(posedge clk) begin
        reset_syn1 <= rst;
        reset_syn2 <= reset_syn1;
    end

    ////////////// TM1563 dio //////////////////
    assign sio_dio = tm_rw ? dio_out : 'z;
    assign dio_in   = sio_dio;

    tm1638_sio
    # (
        .clk_mhz ( clk_mhz )
    )
    tm1638_sio
    (
        .clk        ( clk        ),
        .rst        ( reset_syn2 ),

        .data_latch ( tm_latch   ),
        .data_in    ( tm_in      ),
        .data_out   ( tm_out     ),
        .rw         ( tm_rw      ),

        .busy       ( busy       ),

        .sclk       ( sio_clk    ),
        .dio_in     ( dio_in     ),
        .dio_out    ( dio_out    )
    );

    // handles displaying 1-8 on a hex display
    task display_digit (input logic [7:0] segs);
        tm_latch <= HIGH;
        tm_in    <= segs;
    endtask

    // handles the LEDs 1-8
    task display_led   (input logic [2:0] led);
        tm_latch <= HIGH;
        tm_in <= {7'b0, led_on[led]};
    endtask

    // controller FSM
    always_ff @(posedge clk or posedge reset_syn2)
    begin
        if (reset_syn2) begin
            instruction_step <= 'b0;
            sio_stb          <= HIGH;
            tm_rw            <= HIGH;
            counter          <= 'd0;
            keys             <= 'b0;
            led_on           <= 'b0;
        end else begin
            counter <= counter + 1'b1;
            if (counter[0] && ~busy) begin
                instruction_step <= instruction_step + 1'b1;
                case (instruction_step)
                    // *** KEYS ***
                    1:  {sio_stb, tm_rw}   <= {LOW, HIGH};
                    2:  {tm_latch, tm_in}  <= {HIGH, C_READ}; // read mode
                    3:  {tm_latch, tm_rw}  <= {HIGH, LOW};
                    //  read back keys S1 - S8
                    4:  {keys[7], keys[3]} <= {tm_out[0], tm_out[4]};
                    5:  tm_latch           <= HIGH;
                    6:  {keys[6], keys[2]} <= {tm_out[0], tm_out[4]};
                    7:  tm_latch           <= HIGH;
                    8:  {keys[5], keys[1]} <= {tm_out[0], tm_out[4]};
                    9:  tm_latch           <= HIGH;
                    10: {keys[4], keys[0]} <= {tm_out[0], tm_out[4]};
                    11: {sio_stb}          <= {HIGH};
                    // *** DISPLAY ***
                    12: {sio_stb, tm_rw}   <= {LOW, HIGH};
                    13: {tm_latch, tm_in}  <= {HIGH, C_WRITE}; // write mode
                    14: {sio_stb}          <= {HIGH};
                    15: {sio_stb, tm_rw}   <= {LOW, HIGH};
                    16: {tm_latch, tm_in}  <= {HIGH, C_ADDR}; // set addr 0 pos
                    17: display_digit(digits[7]); // Digit 1
                    18: display_led(3'd7);        // LED 8
                    19: display_digit(digits[6]); // Digit 2
                    20: display_led(3'd6);        // LED 7
                    21: display_digit(digits[5]); // Digit 3
                    22: display_led(3'd5);        // LED 6
                    23: display_digit(digits[4]); // Digit 4
                    24: display_led(3'd4);        // LED 5
                    25: display_digit(digits[3]); // Digit 5
                    26: display_led(3'd3);        // LED 4
                    27: display_digit(digits[2]); // Digit 6
                    28: display_led(3'd2);        // LED 3
                    29: display_digit(digits[1]); // Digit 7
                    30: display_led(3'd1);        // LED 2
                    31: display_digit(digits[0]); // Digit 8
                    32: display_led(3'd0);        // LED 1
                    33: {sio_stb}          <= {HIGH};
                    34: {sio_stb, tm_rw}   <= {LOW, HIGH};
                    35: {tm_latch, tm_in}  <= {HIGH, C_DISP}; // display on, full bright
                    40: {sio_stb, instruction_step} <= {HIGH, 6'b0};
                endcase
                led_on           <= ledr;
            end else if (busy) begin
                // pull latch low next clock cycle after module has been
                // latched
                tm_latch <= LOW;
            end
        end
    end
endmodule


///////////////////////////////////////////////////////////////////////////////////
//           TM1638 SIO driver for tm1638_board_controller top module
///////////////////////////////////////////////////////////////////////////////////
module tm1638_sio
# (
    parameter clk_mhz = 50
)
(
    input  logic       clk,
    input  logic       rst,

    input  logic       data_latch,
    input  logic [7:0] data_in,
    output logic [7:0] data_out,
    input  logic       rw,

    output logic       busy,

    output logic       sclk,
    input  logic       dio_in,
    output logic       dio_out
);

    localparam CLK_DIV1 = 4;//$clog2 (clk_mhz*1000/2/700) - 1; // 700 kHz is recommended SIO clock
    localparam [1:0]
        S_IDLE      = 2'h0,
        S_WAIT      = 2'h1,
        S_TRANSFER  = 2'h2;

    logic [       1:0] cur_state, next_state;
    logic [CLK_DIV1:0] sclk_d, sclk_q;
    logic [       7:0] data_d, data_q, data_out_d, data_out_q;
    logic              dio_out_d;
    logic [       2:0] ctr_d, ctr_q;

    // output read data
    assign data_out = data_out_q;

    // we're busy if we're not idle
    assign busy = cur_state != S_IDLE;

    // tick the clock if we're transfering data
    assign sclk = ~((~sclk_q[CLK_DIV1]) & (cur_state == S_TRANSFER));

    always_comb
    begin
        sclk_d = sclk_q;
        data_d = data_q;
        dio_out_d = dio_out;
        ctr_d = ctr_q;
        data_out_d = data_out_q;
        next_state = cur_state;

        case(cur_state)
            S_IDLE: begin
                sclk_d = 0;
                if (data_latch) begin
                    // if we're reading, set to zero, otherwise latch in
                    // data to send
                    data_d = data_in;
                    next_state = S_WAIT;
                end
            end

            S_WAIT: begin
                sclk_d = sclk_q + 1'd1;
                // wait till we're halfway into clock pulse
                if (sclk_q == {1'b0, {CLK_DIV1{1'b1}}}) begin
                    sclk_d = 0;
                    next_state = S_TRANSFER;
                end
            end

            S_TRANSFER: begin
                sclk_d = sclk_q + 1'd1;
                if (sclk_q == 0) begin
                    // start of clock pulse, output MSB
                    dio_out_d = data_q[0];

                end else if (sclk_q == {1'b0, {CLK_DIV1{1'b1}}}) begin
                    // halfway through pulse, read from device
                    data_d = {dio_in, data_q[7:1]};

                end else if (&sclk_q) begin
                    // end of pulse, tick the counter
                    ctr_d = ctr_q + 1'd1;

                    if (&ctr_q) begin
                        // last bit sent, switch back to idle
                        // and output any data recieved
                        next_state = S_IDLE;
                        data_out_d = data_q;

                        dio_out_d = '0;
                    end
                end
            end

            default:
                next_state = S_IDLE;
        endcase
    end

    always_ff @(posedge clk)
    begin
        if (rst)
        begin
            cur_state <= S_IDLE;
            sclk_q <= 0;
            ctr_q <= 0;
            dio_out <= 0;
            data_q <= 0;
            data_out_q <= 0;
        end
        else
        begin
            cur_state <= next_state;
            sclk_q <= sclk_d;
            ctr_q <= ctr_d;
            dio_out <= dio_out_d;
            data_q <= data_d;
            data_out_q <= data_out_d;
        end
    end
endmodule