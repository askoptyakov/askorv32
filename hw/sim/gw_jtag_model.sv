`timescale 1ns/1ps
//==============================================================================================
// GW_JTAG - поведенческая модель примитива GOWIN для моделирования (только тестбенч)
//==============================================================================================
//DESCRIPTION: В библиотеке GOWIN примитив GW_JTAG - "чёрный ящик" без модели. Здесь - TAP
//IEEE 1149.1 с IR 8 бит, IDCODE GW1NR-9 (0x1100481B, IR 0x11), BYPASS и двумя пользовательскими
//регистрами ER1 (IR 0x42) и ER2 (IR 0x43).
//
//Допущения о поведении выходов (документации GOWIN нет; выбраны так, чтобы обёртка
//jtag_tap_gowin из fpgacapZero, проверенная на GW1NR-9 с OpenOCD, давала стандартную для хоста
//семантику регистров данных):
//  - tdi_o - TDI, защёлкнутый по фронту TCK;
//  - shift_dr_capture_dr_o = 1 в состояниях Capture-DR и Shift-DR, update_dr_o - в Update-DR;
//  - enable_erN_o = 1, пока в IR код ERN;
//  - TDO пользовательского регистра: tdo_erN_i защёлкивается по каждому спаду TCK и выдаётся
//    на вывод по следующему спаду (одна дополнительная ступень).
//Если на плате семантика окажется иной, это проявится при чтении dtmcs (hw/info/debug.md).
module GW_JTAG (
    input  wire tck_pad_i, tms_pad_i, tdi_pad_i,
    output wire tdo_pad_o,
    output wire tck_o, tdi_o, test_logic_reset_o, run_test_idle_er1_o, run_test_idle_er2_o,
    output wire shift_dr_capture_dr_o, pause_dr_o, update_dr_o, enable_er1_o, enable_er2_o,
    input  wire tdo_er1_i, tdo_er2_i
);
    localparam logic [3:0] TLR = 4'd0, RTI = 4'd1, SEL_DR = 4'd2, CAP_DR = 4'd3, SH_DR = 4'd4, EX1_DR = 4'd5,
                           PA_DR = 4'd6, EX2_DR = 4'd7, UPD_DR = 4'd8, SEL_IR = 4'd9, CAP_IR = 4'd10,
                           SH_IR = 4'd11, EX1_IR = 4'd12, PA_IR = 4'd13, EX2_IR = 4'd14, UPD_IR = 4'd15;
    logic [3:0] state = TLR;
    logic [7:0]  ir = 8'h11, ir_sr = 8'h00;
    logic [31:0] dr_sr = 32'd0;
    logic        tdi_r = 1'b0, tdo_q = 1'b0, tdo_stage = 1'b0;

    localparam logic [7:0]  IR_IDCODE = 8'h11, IR_ER1 = 8'h42, IR_ER2 = 8'h43;
    localparam logic [31:0] IDCODE    = 32'h1100481B;

    always @(posedge tck_pad_i) begin
        tdi_r <= tdi_pad_i;
        case (state)
            TLR:    state <= tms_pad_i ? TLR    : RTI;
            RTI:    state <= tms_pad_i ? SEL_DR : RTI;
            SEL_DR: state <= tms_pad_i ? SEL_IR : CAP_DR;
            CAP_DR: state <= tms_pad_i ? EX1_DR : SH_DR;
            SH_DR:  state <= tms_pad_i ? EX1_DR : SH_DR;
            EX1_DR: state <= tms_pad_i ? UPD_DR : PA_DR;
            PA_DR:  state <= tms_pad_i ? EX2_DR : PA_DR;
            EX2_DR: state <= tms_pad_i ? UPD_DR : SH_DR;
            UPD_DR: state <= tms_pad_i ? SEL_DR : RTI;
            SEL_IR: state <= tms_pad_i ? TLR    : CAP_IR;
            CAP_IR: state <= tms_pad_i ? EX1_IR : SH_IR;
            SH_IR:  state <= tms_pad_i ? EX1_IR : SH_IR;
            EX1_IR: state <= tms_pad_i ? UPD_IR : PA_IR;
            PA_IR:  state <= tms_pad_i ? EX2_IR : PA_IR;
            EX2_IR: state <= tms_pad_i ? UPD_IR : SH_IR;
            UPD_IR: state <= tms_pad_i ? SEL_DR : RTI;
        endcase
        case (state)
            TLR:    ir    <= IR_IDCODE;
            CAP_IR: ir_sr <= 8'b0000_0001;
            SH_IR:  ir_sr <= {tdi_pad_i, ir_sr[7:1]};
            UPD_IR: ir    <= ir_sr;
            CAP_DR: dr_sr <= (ir == IR_IDCODE) ? IDCODE : 32'd0;
            SH_DR:  dr_sr <= (ir == IR_IDCODE) ? {tdi_pad_i, dr_sr[31:1]} : {31'd0, tdi_pad_i};
            default: ;
        endcase
    end

    wire user = (ir == IR_ER1) || (ir == IR_ER2);
    always @(negedge tck_pad_i) begin
        tdo_stage <= (ir == IR_ER1) ? tdo_er1_i : tdo_er2_i;
        if (state == SH_IR)                tdo_q <= ir_sr[0];
        else if (state == SH_DR && user)   tdo_q <= tdo_stage;
        else if (state == SH_DR)           tdo_q <= dr_sr[0];
    end

    assign tdo_pad_o             = tdo_q;
    assign tck_o                 = tck_pad_i;
    assign tdi_o                 = tdi_r;
    assign test_logic_reset_o    = (state == TLR);
    assign run_test_idle_er1_o   = (state == RTI) && (ir == IR_ER1);
    assign run_test_idle_er2_o   = (state == RTI) && (ir == IR_ER2);
    assign shift_dr_capture_dr_o = (state == CAP_DR) || (state == SH_DR);
    assign pause_dr_o            = (state == PA_DR);
    assign update_dr_o           = (state == UPD_DR);
    assign enable_er1_o          = (ir == IR_ER1);
    assign enable_er2_o          = (ir == IR_ER2);
endmodule
