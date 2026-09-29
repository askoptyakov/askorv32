//==============================================================================================
// dm - Debug Module (RISC-V Debug 0.13) для одного hart
//==============================================================================================
//DESCRIPTION: Минимальный DM, достаточный для OpenOCD и GDB:
//  - останов, продолжение, шаг, сброс системы (ndmreset); вход в отладку по ebreak (dcsr.ebreakm);
//  - абстрактная команда Access Register (32 бит): x0..x31 (0x1000..0x101F) и все CSR
//    (0x0000..0x0FFF, в том числе dpc = PC остановленного ядра и dcsr); буфера программ нет;
//  - System Bus Access (8/16/32 бит, автоинкремент, чтение по адресу/данным) к IMEM и шине данных -
//    для загрузки программы, чтения переменных и программных точек останова (ebreak в IMEM).
//    Доступ к шине - только когда ядро остановлено (иначе sberror = 7).
//Работает в тактовом домене ядра; запросы DMI приходят из DTM через синхронизатор.
module dm (
    input  logic        clk, rst,            //rst - сброс по питанию/кнопке (ndmreset DM не сбрасывает)
    //DMI от DTM (другой тактовый домен)
    input  logic        dmi_req_tgl,
    input  logic [ 6:0] dmi_addr,
    input  logic [31:0] dmi_wdata,
    input  logic [ 1:0] dmi_op,              //1 - чтение, 2 - запись
    output logic        dmi_ack_tgl,
    output logic [31:0] dmi_rdata,
    //Система
    output logic        ndmreset,            //Сброс ядра и периферии
    input  logic        sys_rst,             //Ядро в сбросе
    //Ядро
    output logic        haltreq,
    output logic        resumereq,
    input  logic        halted,
    output logic [ 4:0] gpr_addr,
    output logic        gpr_we,
    input  logic [31:0] gpr_rdata,
    output logic [11:0] csr_addr,
    output logic        csr_we,
    input  logic [31:0] csr_rdata,
    output logic [31:0] reg_wdata,
    //Системная шина (ведущий); sb_active - DM владеет шинами IMEM и данных
    output logic        sb_active,
    output logic [31:0] sb_addr,
    output logic [31:0] sb_wdata,
    output logic [ 3:0] sb_wstrb,
    output logic        sb_read,
    input  logic [31:0] sb_rdata
);
    //#1 Адреса регистров DM
    localparam logic [6:0] DATA0 = 7'h04, DMCONTROL = 7'h10, DMSTATUS = 7'h11, HARTINFO = 7'h12,
                           ABSTRACTCS = 7'h16, COMMAND = 7'h17, ABSTRACTAUTO = 7'h18,
                           SBCS = 7'h38, SBADDRESS0 = 7'h39, SBDATA0 = 7'h3C, HALTSUM0 = 7'h40;

    //#2 Приём запросов DMI
    logic [2:0] req_s;
    logic       req_new;
    always_ff @(posedge clk) req_s <= {req_s[1:0], dmi_req_tgl};
    assign req_new = req_s[2] ^ req_s[1];

    //#3 Регистры
    logic        dmactive, havereset, resumeack, resume_pending;
    logic [31:0] data0;
    logic [ 2:0] cmderr;
    logic        sbbusyerror, sbreadonaddr, sbautoincrement, sbreadondata;
    logic [ 2:0] sbaccess, sberror;
    logic [31:0] sbaddress, sbdata;
    logic [15:0] regno;
    logic        reg_is_gpr, reg_write;

    //Ч16: адреса CSR, GPR и System Bus выставляются не меньше чем за 2 такта до использования
    //(состояния CSR_WR, REG_WAIT2, SB_WAIT), и пути от них в riscv.sdc объявлены двухтактными
    typedef enum logic [3:0] {IDLE, EXEC, REG_RD, SB_CHECK, SB_A, SB_B, ACK, REG_WAIT, REG_WAIT2, CSR_WR, SB_WAIT} state_t;
    state_t state;
    //Р4: запрос не копируется - DTM держит адрес, данные и op неизменными до ответа (dmi_ack_tgl)
    logic [6:0]  a;         //Адрес текущего запроса
    logic [31:0] w;         //Данные текущего запроса
    logic [1:0]  op;
    assign a  = dmi_addr;
    assign w  = dmi_wdata;
    assign op = dmi_op;
    logic        sb_is_read;

    assign gpr_addr  = regno[4:0];
    //Ч11: значение регистра защёлкивается сразу на выходе регистрового файла, а в data0 идёт на такт
    //позже (состояние REG_WAIT). Иначе путь «адрес порта чтения -> регистровый файл -> логика DM»
    //попадал в критический: для анализатора адрес порта идёт и от инструкции в стадии D
    logic [31:0] gpr_q;
    always_ff @(posedge clk) gpr_q <= gpr_rdata;
    //Ч13: адрес CSR - только на время команды DM (иначе 0): в ядре он объединяется с адресом
    //CSR-инструкции через ИЛИ, без выбора по halted
    logic [11:0] csr_addr_q;
    assign csr_addr  = csr_addr_q;
    assign reg_wdata = data0;

    //Байтовые стробы и выравнивание для System Bus
    logic [3:0]  sb_strb;
    logic        sb_misaligned, sb_badsize;
    always_comb begin
        case (sbaccess)
            3'd0:    sb_strb = 4'b0001 << sbaddress[1:0];
            3'd1:    sb_strb = sbaddress[1] ? 4'b1100 : 4'b0011;
            default: sb_strb = 4'b1111;
        endcase
    end
    assign sb_badsize    = (sbaccess > 3'd2);
    assign sb_misaligned = (sbaccess == 3'd1 && sbaddress[0]) || (sbaccess == 3'd2 && |sbaddress[1:0]);

    //Данные чтения выбранного размера
    logic [31:0] sb_rd_shifted;
    always_comb begin
        sb_rd_shifted = sb_rdata >> {sbaddress[1:0], 3'b000};
        case (sbaccess)
            3'd0:    sb_rd_shifted = {24'd0, sb_rd_shifted[7:0]};
            3'd1:    sb_rd_shifted = {16'd0, sb_rd_shifted[15:0]};
            default: sb_rd_shifted = sb_rdata;
        endcase
    end

    //Запуск обращения к шине: проверки и переход в SB_CHECK
    function automatic logic sb_start_ok();
        return (sberror == 3'd0) && !sbbusyerror;
    endfunction

    //#4 Чтение регистров DM
    logic [31:0] rd;
    always_comb begin
        rd = 32'd0;
        case (a)
            DATA0:      rd = data0;
            DMCONTROL:  rd = {30'd0, ndmreset, dmactive};                //hartsel не реализован (один hart)
            DMSTATUS:   rd = {9'd0, 1'b0 /*impebreak*/, 2'd0, havereset, havereset, resumeack, resumeack,
                              2'b00 /*nonexistent*/, sys_rst, sys_rst /*unavail*/,
                              ~halted & ~sys_rst, ~halted & ~sys_rst, halted, halted,
                              1'b1 /*authenticated*/, 1'b0, 1'b0, 1'b0, 4'd2 /*version 0.13*/};
            HARTINFO:   rd = 32'd0;
            ABSTRACTCS: rd = {3'd0, 5'd0 /*progbufsize*/, 11'd0, 1'b0 /*busy*/, 1'b0, cmderr, 4'd0, 4'd1 /*datacount*/};
            SBCS:       rd = {3'd1, 6'd0, sbbusyerror, 1'b0 /*sbbusy*/, sbreadonaddr, sbaccess, sbautoincrement,
                              sbreadondata, sberror, 7'd32 /*sbasize*/, 5'b00111 /*8, 16, 32 бит*/};
            SBADDRESS0: rd = sbaddress;
            SBDATA0:    rd = sbdata;
            HALTSUM0:   rd = {31'd0, halted};
            default:    rd = 32'd0;
        endcase
    end

    //#5 Автомат обработки запроса
    always_ff @(posedge clk)
        if (rst) begin
            state <= IDLE; dmi_ack_tgl <= 1'b0; dmi_rdata <= 32'd0;
            dmactive <= 1'b0; ndmreset <= 1'b0; haltreq <= 1'b0; resumereq <= 1'b0;
            gpr_we <= 1'b0; csr_we <= 1'b0; sb_read <= 1'b0; sb_wstrb <= 4'd0; havereset <= 1'b1;
            csr_addr_q <= 12'd0;
        end else begin
            gpr_we    <= 1'b0;
            csr_we    <= 1'b0;
            resumereq <= 1'b0;
            sb_read   <= 1'b0;
            sb_wstrb  <= 4'd0;
            //Состояние ядра
            if (sys_rst) havereset <= 1'b1;
            if (resume_pending && !halted) begin resumeack <= 1'b1; resume_pending <= 1'b0; end

            case (state)
                IDLE: if (req_new) state <= EXEC;
                EXEC: begin
                          dmi_rdata <= rd;
                          state     <= ACK;
                          if (op == 2'd1 && a == SBDATA0 && dmactive && sbreadondata && sb_start_ok())
                              begin sb_is_read <= 1'b1; state <= SB_WAIT; end           //Чтение sbdata0 запускает следующее чтение
                          if (op == 2'd2) begin
                              if (a == DMCONTROL) begin
                                  dmactive <= w[0];
                                  if (w[0]) begin
                                      ndmreset <= w[1];
                                      haltreq  <= w[31];
                                      if (w[28]) havereset <= 1'b0;               //ackhavereset
                                      if (w[30] && !w[31] && halted) begin        //resumereq
                                          resumereq <= 1'b1; resumeack <= 1'b0; resume_pending <= 1'b1;
                                      end
                                  end
                              end else if (dmactive)
                                  case (a)
                                      DATA0:      data0 <= w;
                                      ABSTRACTCS: cmderr <= cmderr & ~w[10:8];      //Сброс записью 1
                                      COMMAND:    if (cmderr == 3'd0) begin
                                                      regno      <= w[15:0];
                                                      reg_write  <= w[16];
                                                      reg_is_gpr <= (w[15:0] >= 16'h1000);
                                                      if (w[31:24] != 8'd0 || w[18] || w[19] ||
                                                          (w[17] && w[22:20] != 3'd2)) cmderr <= 3'd2;   //не поддерживается
                                                      else if (!halted)                 cmderr <= 3'd4;   //ядро не остановлено
                                                      else if (!w[17])                  ;                 //без передачи - ничего
                                                      else if (w[15:0] > 16'h101F || (w[15:0] > 16'h0FFF && w[15:0] < 16'h1000))
                                                                                         cmderr <= 3'd3;   //нет такого регистра
                                                      else if (w[16]) begin                               //запись: data0 -> регистр
                                                          if (w[15:0] >= 16'h1000) gpr_we <= 1'b1;
                                                          else begin csr_addr_q <= w[11:0]; state <= CSR_WR; end   //Ч16: запись тактом позже
                                                      end else begin                                      //чтение: регистр -> data0
                                                          state <= REG_WAIT;
                                                          if (w[15:0] < 16'h1000) csr_addr_q <= w[11:0];
                                                      end
                                                  end
                                      SBCS: begin
                                                if (w[22]) sbbusyerror <= 1'b0;
                                                sberror        <= sberror & ~w[14:12];
                                                sbreadonaddr   <= w[20];
                                                sbaccess       <= w[19:17];
                                                sbautoincrement<= w[16];
                                                sbreadondata   <= w[15];
                                            end
                                      SBADDRESS0: begin
                                                sbaddress <= w;
                                                if (sbreadonaddr && sb_start_ok()) begin sb_is_read <= 1'b1; state <= SB_WAIT; end
                                            end
                                      SBDATA0: begin
                                                sbdata <= w;
                                                if (sb_start_ok()) begin sb_is_read <= 1'b0; state <= SB_WAIT; end
                                            end
                                      default: ;
                                  endcase
                          end
                      end
                REG_WAIT:  state <= REG_WAIT2;                  //Ч11: значение GPR защёлкивается в gpr_q
                REG_WAIT2: state <= REG_RD;                     //Ч16: путь в gpr_q - двухтактный
                CSR_WR: begin                                   //Ч16: адрес CSR выставлен такт назад, запись - в ACK
                          csr_we <= 1'b1;
                          state  <= ACK;
                      end
                SB_WAIT: state <= SB_CHECK;                    //Ч16: пути от sbaddress - двухтактные
                REG_RD: begin                                   //Адрес регистра выставлен три такта назад
                          data0 <= reg_is_gpr ? gpr_q : csr_rdata;
                          state <= ACK;
                      end
                SB_CHECK: begin                                 //Проверки; стробы (регистровые) активны в SB_A
                          if (!halted)                          begin sberror <= 3'd7; state <= ACK; end
                          else if (sb_badsize)                  begin sberror <= 3'd4; state <= ACK; end
                          else if (sb_misaligned)               begin sberror <= 3'd3; state <= ACK; end
                          else begin
                              if (sb_is_read) sb_read  <= 1'b1;
                              else            sb_wstrb <= sb_strb;
                              state <= SB_A;
                          end
                      end
                SB_A: state <= SB_B;                            //Строб: запись/чтение по фронту в конце такта
                SB_B: state <= ACK;                             //Данные чтения (BSRAM - с задержкой на такт) готовы
                ACK: begin
                          csr_addr_q  <= 12'd0;            //Ч13: команда завершена - адрес CSR снят
                          dmi_ack_tgl <= ~dmi_ack_tgl;
                          state       <= IDLE;
                      end
                default: state <= IDLE;
            endcase

            //Завершение обращения к шине: данные чтения и автоинкремент
            if (state == SB_B) begin
                if (sb_is_read) sbdata <= sb_rd_shifted;
                if (sbautoincrement) sbaddress <= sbaddress + (32'd1 << sbaccess);
            end

            //dmactive = 0: модуль отладки в исходном состоянии
            if (!dmactive && !(state == EXEC && op == 2'd2 && a == DMCONTROL && w[0])) begin
                ndmreset <= 1'b0; haltreq <= 1'b0; data0 <= 32'd0; cmderr <= 3'd0;
                sbbusyerror <= 1'b0; sbreadonaddr <= 1'b0; sbaccess <= 3'd2; sbautoincrement <= 1'b0;
                sbreadondata <= 1'b0; sberror <= 3'd0; sbaddress <= 32'd0; sbdata <= 32'd0;
                resumeack <= 1'b0; resume_pending <= 1'b0;
                if (sys_rst) havereset <= 1'b1;
            end
        end

    //Шина: адрес и данные держатся с SB_CHECK по SB_B, стробы - только в SB_A
    assign sb_active = halted && ((state == SB_CHECK) || (state == SB_A) || (state == SB_B));
    assign sb_addr   = sbaddress;
    assign sb_wdata  = (sbaccess == 3'd0) ? {4{sbdata[7:0]}} : (sbaccess == 3'd1) ? {2{sbdata[15:0]}} : sbdata;
endmodule
