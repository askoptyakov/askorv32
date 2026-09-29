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
//Р4: один сдвиговый регистр sr на оба регистра данных (выбран всегда только один из них). Обёртка
//выдаёт стробы по спаду TCK: shift_out - в состоянии Capture/Shift-DR, shift_in - тем же стробом тактом
//позже. Поэтому регистр сдвигается по любому из них, а TDI вдвигается только по shift_in: выдаваемые
//биты (младшие) уходят в TDO в том же порядке, что из отдельного регистра выдачи в jtag_reg_iface_gowin
//(fpgacapZero), а принятые оказываются в младших 32 (dtmcs) или 41 (dmi) битах, как в регистре приёма.
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

    //#2 Ответ DM. Р4: данные ответа не копируются - DM держит dmi_rdata от ответа до следующего запроса,
    //а новый запрос возможен только после ответа (busy = 0). Пока busy = 1, данные при захвате могут
    //меняться, но тогда op = 3 (busy) и отладчик данные не берёт
    logic [2:0]  ack_s = 3'd0;
    logic        busy;
    always_ff @(posedge clk) ack_s <= {ack_s[1:0], dmi_ack_tgl};
    assign busy = (req_tgl != ack_s[2]);

    //#3 dtmcs (ER1) и dmi (ER2): [40:34] адрес, [33:2] данные, [1:0] op
    logic [ 1:0] dmistat = 2'd0;
    logic [31:0] dtmcs;
    assign dtmcs = {14'd0, 1'b0, 1'b0, 1'b0, IDLE, dmistat, ABITS, 4'd1};   //version 1 = Debug 0.13

    logic [40:0] sr = 41'd0;                //Р4: общий сдвиговый регистр ER1 (биты [31:0]) и ER2 ([40:0])
    logic        cap_busy = 1'b0, scanning = 1'b0;

    always_ff @(posedge clk) begin
        //Захват: dtmcs или результат последней операции DMI (адрес - это адрес запроса req_addr)
        if (capture[0])      sr <= {9'd0, dtmcs};
        else if (capture[1]) sr <= {req_addr, dmi_rdata, busy ? 2'd3 : dmistat};
        else if (shift_out[0] | shift_out[1] | shift_in[0] | shift_in[1]) begin
            sr[39:0] <= sr[40:1];
            sr[40]   <= tdi;                                     //dmi: TDI вдвигается в бит 40
            sr[31]   <= shift_in[0] ? tdi : sr[32];              //dtmcs: в бит 31
        end
        if (update[0] && (sr[16] || sr[17])) dmistat <= 2'd0;   //dmireset / dmihardreset

        //dmi: состояние скана
        if (capture[1]) begin
            cap_busy <= busy;
            scanning <= 1'b0;
        end else if (shift_out[1] && !scanning) begin           //Начало скана при незавершённой операции
            scanning <= 1'b1;
            if (cap_busy) dmistat <= 2'd3;
        end
        if (update[1]) begin
            scanning <= 1'b0;
            if (dmistat == 2'd0 && !cap_busy && !busy && (sr[1:0] == 2'd1 || sr[1:0] == 2'd2)) begin
                req_addr    <= sr[40:34];
                req_wdata   <= sr[33:2];
                req_op      <= sr[1:0];
                req_tgl <= ~req_tgl;
            end
        end
    end

    assign tdo = {sr[0], sr[0]};
endmodule
