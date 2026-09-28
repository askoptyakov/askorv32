//==============================================================================================
// dtm_gowin - Debug Transport Module (RISC-V Debug 0.13) через пользовательский JTAG GOWIN
//==============================================================================================
//DESCRIPTION: Регистры DTM на пользовательских регистрах данных примитива GW_JTAG:
//  ER1 (IR = 0x42) - dtmcs, 32 бит;
//  ER2 (IR = 0x43) - dmi, 41 бит: [40:34] адрес, [33:2] данные, [1:0] op.
//OpenOCD: "riscv set_ir dtmcs 0x42", "riscv set_ir dmi 0x43" (длина IR ПЛИС - 8 бит).
//
//Сигналы JTAG выбираются тактом clk (обёртка jtag_tap_gowin из fpgacapZero), поэтому частота TCK
//должна быть заметно ниже clk: при clk = 27 МГц - не выше ~2 МГц (adapter speed 1000 в OpenOCD).
//Сдвиговые регистры устроены как в проверенном на GW1NR-9 jtag_reg_iface_gowin (fpgacapZero):
//отдельные регистры для приёма (shift_in) и выдачи (capture/shift_out).
//
//Обмен с DM (другой тактовый домен): запрос выставляется вместе с переключением dmi_req_tgl и
//не меняется до ответа - переключения dmi_ack_tgl. Пока ответа нет, операция занята: DMI-скан
//в это время возвращает op = 3 (busy) и ставит залипающую ошибку dmistat, которую OpenOCD
//сбрасывает записью dtmcs.dmireset и повторяет операцию с большей паузой.
module dtm_gowin (
    input  logic        clk,
    //Выводы JTAG ПЛИС (подключаются к GW_JTAG без назначения в .cst)
    input  logic        tck_pad_i, tms_pad_i, tdi_pad_i,
    output logic        tdo_pad_o,
    //DMI к модулю отладки
    output logic        dmi_req_tgl,
    output logic [ 6:0] dmi_addr,
    output logic [31:0] dmi_wdata,
    output logic [ 1:0] dmi_op,
    input  logic        dmi_ack_tgl,
    input  logic [31:0] dmi_rdata
);
    //Регистры запроса (начальные значения - через внутренние переменные: у выходного порта
    //инициализацию синтезатор не принимает)
    logic        req_tgl = 1'b0;
    logic [ 6:0] req_addr = 7'd0;
    logic [31:0] req_wdata = 32'd0;
    logic [ 1:0] req_op = 2'd0;
    assign dmi_req_tgl = req_tgl;
    assign dmi_addr    = req_addr;
    assign dmi_wdata   = req_wdata;
    assign dmi_op      = req_op;

    localparam logic [5:0] ABITS = 6'd7;
    localparam logic [2:0] IDLE  = 3'd1;   //Рекомендуемое число тактов Run-Test/Idle после DMI-скана

    //#1 TAP GOWIN: стробы в домене clk, индекс 0 - ER1, 1 - ER2
    logic       tdi;
    logic [1:0] tdo, capture, shift_in, shift_out, update, sel;
    jtag_tap_gowin tap (.sysclk(clk), .activity(), .tdi(tdi), .tdo(tdo),
                        .capture(capture), .shift_in(shift_in), .shift_out(shift_out),
                        .update(update), .sel(sel),
                        .tms_pad_i(tms_pad_i), .tck_pad_i(tck_pad_i), .tdi_pad_i(tdi_pad_i), .tdo_pad_o(tdo_pad_o));

    //#2 Ответ DM
    logic [2:0]  ack_s = 3'd0;
    logic        busy;
    logic [31:0] resp_data = 32'd0;
    always_ff @(posedge clk) begin
        ack_s <= {ack_s[1:0], dmi_ack_tgl};
        if (ack_s[2] != ack_s[1]) resp_data <= dmi_rdata;   //Данные стабильны: DM держит их до следующего запроса
    end
    assign busy = (req_tgl != ack_s[2]);

    //#3 dtmcs (ER1)
    logic [ 1:0] dmistat = 2'd0;
    logic [31:0] dtmcs_in = 32'd0, dtmcs_out = 32'd0;
    logic [31:0] dtmcs;
    assign dtmcs = {14'd0, 1'b0, 1'b0, 1'b0, IDLE, dmistat, ABITS, 4'd1};   //version 1 = Debug 0.13

    //#4 dmi (ER2)
    logic [40:0] dmi_in = 41'd0, dmi_out = 41'd0;
    logic [ 6:0] last_addr = 7'd0;
    logic        cap_busy = 1'b0, scanning = 1'b0;

    always_ff @(posedge clk) begin
        //dtmcs
        if (capture[0])        dtmcs_out <= dtmcs;
        else if (shift_out[0]) dtmcs_out <= {1'b0, dtmcs_out[31:1]};
        if (shift_in[0])       dtmcs_in  <= {tdi, dtmcs_in[31:1]};
        if (update[0] && (dtmcs_in[16] || dtmcs_in[17])) dmistat <= 2'd0;   //dmireset / dmihardreset

        //dmi: при захвате - результат последней операции
        if (capture[1]) begin
            dmi_out  <= {last_addr, resp_data, busy ? 2'd3 : dmistat};
            cap_busy <= busy;
            scanning <= 1'b0;
        end else if (shift_out[1]) begin
            dmi_out <= {1'b0, dmi_out[40:1]};
            if (!scanning) begin                          //Начало скана при незавершённой операции
                scanning <= 1'b1;
                if (cap_busy) dmistat <= 2'd3;
            end
        end
        if (shift_in[1]) dmi_in <= {tdi, dmi_in[40:1]};
        if (update[1]) begin
            scanning <= 1'b0;
            if (dmistat == 2'd0 && !cap_busy && !busy && (dmi_in[1:0] == 2'd1 || dmi_in[1:0] == 2'd2)) begin
                req_addr    <= dmi_in[40:34];
                req_wdata   <= dmi_in[33:2];
                req_op      <= dmi_in[1:0];
                last_addr   <= dmi_in[40:34];
                req_tgl <= ~req_tgl;
            end
        end
    end

    assign tdo = {dmi_out[0], dtmcs_out[0]};
endmodule
