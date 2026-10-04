//==============================================================================================
// rect_top - выпрямитель: СИФУ и регулятор CC/CV (напряжение с ограничением тока) в одном блоке
//==============================================================================================
//DESCRIPTION: Законченный блок управления трёхфазным мостовым тиристорным выпрямителем. Внутри:
//  - sifu_top (hw/src/periph/sifu): синхронизация от платы NSB или имитатора, импульсы VS1..VS6;
//    угол - от регулятора (CR.UEXT: угол = AMAX - u) или из регистра ALPHA (ручной режим);
//  - pireg_top PI_U - регулятор напряжения: обратная связь fb_u (среднее за окно канала
//    напряжения блока ADC), выход u - на СИФУ; верхний предел - выход PI_I (LIM_EN);
//  - pireg_top PI_I - регулятор тока: обратная связь fb_i (канал тока); предел интегратора -
//    выход PI_U (TRK_EN).
//  Оба регулятора стоят (интегратор 0, выход 0 - угол 120 град.), пока импульсы не идут (EN, сеть,
//  синхронизация - выход run СИФУ). Выход tick_o - начало полуволны любой пары (раз в 60 эл. град.):
//  на вход закрытия окна блока ADC, чтобы средние были за интервал между коммутациями.
//Процессор пишет только задание (PI_U.SP - напряжение, PI_I.SP - ограничение тока, в кодах АЦП
//* 16), коэффициенты, пределы и режим СИФУ; перевод в вольты и амперы - программой.
//Описание - README.md в этой папке, тест - tb_rect.sv, библиотеки - fw/Core/Inc/sifu.h, pireg.h.
//
//Карта (окно блока): 0x00 - регистры SIFU (sifu_top), 0x40 - PI_U, 0x80 - PI_I (pireg_top);
//выбор - Addr[7:6], остальное читается как 0.
module rect_top
  #(parameter bit          MEMORY_TYPE = 0,
    parameter logic [15:0] DIV_INIT    = 16'd89,
    parameter logic [11:0] DELAY_INIT  = 12'd400,
    parameter logic [11:0] WIDTH_INIT  = 12'd150,
    parameter bit          SIM_EN      = 1'b1,
    parameter logic [11:0] AMAX_INIT   = 12'd3333,
    parameter int          FRAC        = 12)
   (input  logic        clk, rst,
    // Интерфейс обмена
    input  logic [ 3:0] Write,
    input  logic [31:0] Addr, WData,
    output logic [31:0] RData,
    // Плата синхронизации NSB и тиристоры
    input  logic        sync_ab, sync_ba, sync_bc, sync_cb, sync_ca, sync_ac,
    output logic        vs1, vs2, vs3, vs4, vs5, vs6,
    output logic        grid_o,
    // Обратные связи от блока ADC (средние за окно, код * 16) и закрытие окна
    input  logic [15:0] fb_u, fb_i,
    input  logic        fb_u_stb, fb_i_stb,
    output logic        tick_o,
    output logic        irq
);
    logic [1:0]  sub, sub_q;
    logic [2:0][31:0] rd;
    logic [2:0]  irq_s;
    assign sub = Addr[7:6];
    always_ff @(posedge clk) sub_q <= sub;
    wire [1:0] sel = MEMORY_TYPE ? sub_q : sub;
    assign RData = (sel == 2'd3) ? 32'd0 : rd[sel];
    assign irq   = |irq_s;

    logic        run;
    logic [15:0] u_out, i_out;

    sifu_top #(.MEMORY_TYPE(MEMORY_TYPE), .DIV_INIT(DIV_INIT), .DELAY_INIT(DELAY_INIT), .WIDTH_INIT(WIDTH_INIT),
               .SIM_EN(SIM_EN), .AMAX_INIT(AMAX_INIT), .UEXT_EN(1'b1)) sifu
        (.clk(clk), .rst(rst), .Write(sub == 2'd0 ? Write : 4'b0000), .Addr(Addr), .WData(WData), .RData(rd[0]),
         .sync_ab(sync_ab), .sync_ba(sync_ba), .sync_bc(sync_bc), .sync_cb(sync_cb), .sync_ca(sync_ca), .sync_ac(sync_ac),
         .vs1(vs1), .vs2(vs2), .vs3(vs3), .vs4(vs4), .vs5(vs5), .vs6(vs6), .grid_o(grid_o),
         .tick_o(tick_o), .run_o(run), .u_i(u_out), .irq(irq_s[0]));

    pireg_top #(.MEMORY_TYPE(MEMORY_TYPE), .FRAC(FRAC), .OMAX_INIT(16'(AMAX_INIT)),
                .LIM_EN(1'b1), .TRK_EN(1'b0), .RUN_EN(1'b1)) pi_u
        (.clk(clk), .rst(rst), .Write(sub == 2'd1 ? Write : 4'b0000), .Addr(Addr), .WData(WData), .RData(rd[1]),
         .fb_i(fb_u), .fb_stb(fb_u_stb), .lim_i(i_out), .trk_i(16'd0), .run_i(run),
         .out_o(u_out), .out_stb(), .irq(irq_s[1]));

    pireg_top #(.MEMORY_TYPE(MEMORY_TYPE), .FRAC(FRAC), .OMAX_INIT(16'(AMAX_INIT)),
                .LIM_EN(1'b0), .TRK_EN(1'b1), .RUN_EN(1'b1)) pi_i
        (.clk(clk), .rst(rst), .Write(sub == 2'd2 ? Write : 4'b0000), .Addr(Addr), .WData(WData), .RData(rd[2]),
         .fb_i(fb_i), .fb_stb(fb_i_stb), .lim_i(16'd0), .trk_i(u_out), .run_i(run),
         .out_o(i_out), .out_stb(), .irq(irq_s[2]));
endmodule
