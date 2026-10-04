//==============================================================================================
// pireg_top - ПИ-регулятор (типовой блок): один контур, вход обратной связи, выход управления
//==============================================================================================
//DESCRIPTION: ПИ-регулятор в фиксированной точке на шине регистров askoRV32. Работает от процессора
//(обратная связь пишется в регистр FB, шаг - командой CR.STEP) или от прямых связей с другими
//блоками, которые настраивает конфигуратор: обратная связь fb_i со стробом fb_stb (например,
//среднее за окно блока ADC121), выход out_o со стробом out_stb (например, на вход u блока SIFU).
//Перевода в физические величины в блоке нет: задание SP - в единицах обратной связи (для ADC121 -
//код АЦП * 16), выход - в единицах управляемого блока (для SIFU - тики угла).
//Описание - README.md в этой папке, тест - tb_pireg.sv, библиотека - fw/Core/Inc/pireg.h.
//
//Шаг (по стробу fb_stb при CR.EN или по CR.STEP):
//  e   = SP - FB                                   (17 бит со знаком)
//  HI  = min(OMAX, lim_i)                          (lim_i - при LIM_EN: внешний предел, например
//                                                   выход регулятора тока для регулятора напряжения)
//  IHI = min(HI, trk_i)                            (trk_i - при TRK_EN: предел интегратора, например
//                                                   выход регулятора напряжения для регулятора тока)
//  INT = clamp(INT + KI * e, 0, IHI << FRAC)        (антинасыщение: интегратор не уходит за пределы)
//  OUT = clamp((KP * e + INT) >>> FRAC, 0, HI)
//Коэффициенты KP, KI - 16 бит без знака, дробных бит FRAC (по умолчанию 12: 4096 = 1.0).
//Вход run_i (при RUN_EN): 0 - регулятор остановлен, INT = 0, OUT = 0 (например, импульсы СИФУ
//сняты - интегратор не копит ошибку); шаги не выполняются.
//
//Карта регистров (по шаблону periph_regs, hw/src/periph/periph_regs.sv):
//<>0x00 CR   - [0] EN - шаг по стробу прямой связи fb_stb; [1] STEP - шаг с FB (запись 1, сам
//              сбрасывается); [2] IE - прерывание по новому выходу (SR.RDY); [3] CLR - INT = 0,
//              OUT = 0 (запись 1)
//<>0x04 SP   - [15:0] задание, единицы обратной связи
//<>0x08 KP   - [15:0] пропорциональный коэффициент, KP / 2^FRAC
//<>0x0C KI   - [15:0] интегральный коэффициент за шаг, KI / 2^FRAC
//<>0x10 OMAX - [15:0] верхний предел выхода (нижний - 0); после сброса - OMAX_INIT
//<>0x14 FB   - [15:0] обратная связь: пишет процессор (для CR.STEP), при шаге по прямой связи -
//              значение fb_i этого шага
//<<0x18 OUT  - [15:0] выход; [31:16] ошибка e последнего шага (16 бит со знаком, с насыщением)
//<>0x1C SR   - [0] RDY - новый выход (сброс записью 1); [1] LIM - выход на верхнем пределе;
//              [2] LOW - выход на нуле; [3] RUN - регулятор работает (run_i или 1); [8] BUSY
//<>0x20 INT  - [31:0] интегратор (со знаком, единицы выхода * 2^FRAC): чтение, предустановка
//Запрос прерывания irq = RDY & IE, через регистр.
module pireg_top
  #(parameter bit          MEMORY_TYPE = 0,
    parameter int          FRAC        = 12,          //Дробных бит KP, KI
    parameter logic [15:0] OMAX_INIT   = 16'hFFFF,
    parameter bit          LIM_EN      = 1'b0,        //Вход lim_i подключён
    parameter bit          TRK_EN      = 1'b0,        //Вход trk_i подключён
    parameter bit          RUN_EN      = 1'b0)        //Вход run_i подключён
   (input  logic        clk, rst,
    // Интерфейс обмена
    input  logic [ 3:0] Write,
    input  logic [31:0] Addr, WData,
    output logic [31:0] RData,
    // Прямые связи
    input  logic [15:0] fb_i,            //Обратная связь
    input  logic        fb_stb,          //Новое значение fb_i - шаг (при CR.EN)
    input  logic [15:0] lim_i,           //Внешний верхний предел выхода и интегратора (LIM_EN)
    input  logic [15:0] trk_i,           //Верхний предел интегратора (TRK_EN)
    input  logic        run_i,           //1 - работать, 0 - стоп и сброс интегратора (RUN_EN)
    output logic [15:0] out_o,
    output logic        out_stb,         //Новый выход
    output logic        irq
);
    localparam int IW = FRAC + 22;       //Произведения 17 x 17 бит и суммы - с запасом на знак

    //#1 Регистры
    localparam int N = 9;
    logic [N-1:0][3:0] we;
    logic [31:0] wdata;

    logic [ 3:0] cr;                     //{-, IE, -, EN}: STEP и CLR - стробы
    logic [15:0] sp, kp, ki, omax, fb, out;
    logic signed [15:0] e_rd;
    logic        rdy, lim_f, low_f, busy;
    logic signed [IW-1:0] intg;
    wire         run = RUN_EN ? run_i : 1'b1;

    periph_regs #(.N(N), .MEMORY_TYPE(MEMORY_TYPE)) regs
        (.clk(clk), .Write(Write), .Read(1'b0), .Addr(Addr), .WData(WData), .RData(RData),
         .we(we), .re(), .wdata(wdata),
         .rdata({32'(intg),                                               //0x20 INT
                 32'({busy, 4'd0, run, low_f, lim_f, rdy}),               //0x1C SR (BUSY - бит 8)
                 {e_rd, out},                                             //0x18 OUT
                 32'(fb), 32'(omax), 32'(ki), 32'(kp), 32'(sp),           //0x14..0x04
                 32'({cr[2], 1'b0, cr[0]})}));                            //0x00 CR

    periph_reg #(.W(4))  r_cr   (.clk(clk), .rst(rst), .we(we[0]), .wdata(wdata), .q(cr));
    periph_reg #(.W(16)) r_sp   (.clk(clk), .rst(rst), .we(we[1]), .wdata(wdata), .q(sp));
    periph_reg #(.W(16)) r_kp   (.clk(clk), .rst(rst), .we(we[2]), .wdata(wdata), .q(kp));
    periph_reg #(.W(16)) r_ki   (.clk(clk), .rst(rst), .we(we[3]), .wdata(wdata), .q(ki));
    periph_reg #(.W(16), .INIT(OMAX_INIT)) r_omax (.clk(clk), .rst(rst), .we(we[4]), .wdata(wdata), .q(omax));
    wire en       = cr[0];
    wire ie       = cr[2];
    wire step_cmd = we[0][0] & wdata[1];
    wire clr_cmd  = we[0][0] & wdata[3];

    //#2 Шаг: 4 такта (ошибка и пределы -> произведения -> интегратор -> выход), строб out_stb - на 5-м
    typedef enum logic [1:0] {IDLE, S_MUL, S_INT, S_OUT} st_t;
    st_t st;
    logic signed [16:0]   e;             //SP - FB
    logic        [15:0]   hi, ihi;
    logic signed [IW-1:0] pk, ik;        //KP * e, KI * e
    wire go_link = en & fb_stb;
    wire go      = run & (st == IDLE) & (go_link | step_cmd);
    assign busy  = (st != IDLE);

    //Пределы: внешний lim_i и trk_i - текущие значения (выход другого регулятора с прошлого шага)
    wire [15:0] hi_c  = (LIM_EN && lim_i < omax) ? lim_i : omax;
    wire [15:0] ihi_c = (TRK_EN && trk_i < hi_c) ? trk_i : hi_c;

    wire signed [IW-1:0] int_sum = intg + ik;
    wire signed [IW-1:0] int_max = $signed(IW'(ihi)) <<< FRAC;
    wire signed [IW-1:0] out_sum = pk + intg;
    wire signed [IW-1:0] out_shr = out_sum >>> FRAC;

    always_ff @(posedge clk)
        if (rst) begin
            st <= IDLE; fb <= '0; e <= '0; hi <= '0; ihi <= '0; pk <= '0; ik <= '0;
            intg <= '0; out <= '0; e_rd <= '0; rdy <= 1'b0; lim_f <= 1'b0; low_f <= 1'b1; out_stb <= 1'b0;
        end else begin
            out_stb <= 1'b0;
            //FB: запись процессора; при шаге по прямой связи - значение fb_i
            if (|we[5]) fb <= wdata[15:0];
            if (!run || clr_cmd) begin                              //Стоп или CR.CLR: выход 0
                st <= IDLE; intg <= '0; out <= '0; lim_f <= 1'b0; low_f <= 1'b1;
            end else begin
                if (|we[8]) intg <= IW'($signed(wdata));            //Предустановка интегратора
                case (st)
                    IDLE: if (go) begin
                        e   <= $signed({1'b0, sp}) - $signed({1'b0, go_link ? fb_i : fb});
                        if (go_link) fb <= fb_i;
                        hi  <= hi_c; ihi <= ihi_c;
                        st  <= S_MUL;
                    end
                    S_MUL: begin
                        pk <= IW'($signed({1'b0, kp}) * e);
                        ik <= IW'($signed({1'b0, ki}) * e);
                        e_rd <= (e > 17'sd32767) ? 16'sh7FFF : (e < -17'sd32768) ? -16'sh8000 : 16'(e);
                        st <= S_INT;
                    end
                    S_INT: begin                                    //Интегратор в [0, IHI << FRAC]
                        intg <= (int_sum < 0) ? '0 : (int_sum > int_max) ? int_max : int_sum;
                        st <= S_OUT;
                    end
                    S_OUT: begin                                    //Выход в [0, HI]
                        if (out_shr <= 0)                    begin out <= '0; low_f <= 1'b1; lim_f <= (hi == 0); end
                        else if (out_shr >= IW'({1'b0, hi})) begin out <= hi; low_f <= (hi == 0); lim_f <= 1'b1; end
                        else begin out <= out_shr[15:0]; low_f <= 1'b0; lim_f <= 1'b0; end
                        out_stb <= 1'b1;
                        st <= IDLE;
                    end
                    default: st <= IDLE;
                endcase
            end
            //Флаг RDY: установка по новому выходу важнее сброса записью 1
            if (st == S_OUT && run && !clr_cmd) rdy <= 1'b1;
            else if (we[7][0] && wdata[0])      rdy <= 1'b0;
        end
    assign out_o = out;

    always_ff @(posedge clk)
        if (rst) irq <= 1'b0;
        else     irq <= rdy & ie;
endmodule
