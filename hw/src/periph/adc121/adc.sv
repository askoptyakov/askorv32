//==============================================================================================
// adc_top - блок АЦП: несколько каналов измерения (платы ADC_V - напряжение, ADC_C - ток) в одном окне
//==============================================================================================
//DESCRIPTION: Один блок периферии на все платы измерения. Каждый канал - экземпляр adc121_top (кадр
//АЦП ADC121S051, проверка кадра, период, усреднение 2^N, среднее за окно, вход компаратора): свои
//выводы CS, SCLK, SDO, CMP и свои регистры. Общее у каналов: такт АЦП (adc_clk, свой rPLL), вход
//закрытия окна усреднения win_i (например, начало полуволны СИФУ - окна всех каналов закрываются в
//один такт), запрос прерывания (ИЛИ каналов). Описание - README.md в этой папке, тест - tb_adc.sv,
//библиотека - fw/Core/Inc/adc121.h (функции получают указатель на канал).
//
//Карта: канал k - регистры adc121_top со смещения k * 0x40 (k = 0..NCH-1; 0x40 - запас под рост
//регистров канала). Остальное окно читается как 0.
//Параметры канала - векторы по каналам (бит k / поле k): CSINV_INIT, CMP_EN, CPOL_INIT; общие -
//DIV_INIT, AVGSH_INIT, CSS_INIT, QUIET_INIT, CLK_HZ, WIN_EN.
module adc_top
  #(parameter bit          MEMORY_TYPE = 0,
    parameter int          NCH         = 2,          //Число каналов: 1..4
    parameter logic [7:0]  DIV_INIT    = 8'd5,
    parameter logic [3:0]  AVGSH_INIT  = 4'd8,
    parameter logic [3:0]  CSS_INIT    = 4'd1,
    parameter logic [3:0]  QUIET_INIT  = 4'd1,
    parameter logic [3:0]  CSINV_INIT  = 4'b0000,   //Бит k - вывод CS канала k инвертирован
    parameter logic [3:0]  CMP_EN      = 4'b0000,   //Бит k - вход компаратора канала k подключён
    parameter logic [3:0]  CPOL_INIT   = 4'b0000,   //Бит k - активный уровень CMP канала k
    parameter logic [31:0] CLK_HZ      = 32'd0,
    parameter bit          WIN_EN      = 1'b1)
   (input  logic                clk, rst,
    input  logic                adc_clk, adc_lock,
    // Интерфейс обмена
    input  logic [ 3:0]         Write,
    input  logic [31:0]         Addr, WData,
    output logic [31:0]         RData,
    // Каналы: выводы плат измерения
    output logic [NCH-1:0]      adc_cs_n,
    output logic [NCH-1:0]      adc_sclk,
    input  logic [NCH-1:0]      adc_sdo,
    input  logic [NCH-1:0]      adc_cmp,
    // Общее закрытие окна и средние за окно каналов (код * 16) со стробами
    input  logic                win_i,
    output logic [NCH-1:0][15:0] wmean_o,
    output logic [NCH-1:0]      wstb_o,
    output logic                irq
);
    logic [1:0] ch, ch_q;                //Канал обращения: Addr[7:6]
    logic [NCH-1:0][31:0] rd;
    logic [NCH-1:0] irq_ch;
    assign ch = Addr[7:6];
    always_ff @(posedge clk) ch_q <= ch;

    for (genvar k = 0; k < NCH; k++) begin : g_ch
        adc121_top #(.MEMORY_TYPE(MEMORY_TYPE), .DIV_INIT(DIV_INIT), .AVGSH_INIT(AVGSH_INIT),
                     .CSS_INIT(CSS_INIT), .QUIET_INIT(QUIET_INIT), .CSINV_INIT(CSINV_INIT[k]),
                     .CMP_EN(CMP_EN[k]), .CPOL_INIT(CPOL_INIT[k]), .CLK_HZ(CLK_HZ), .WIN_EN(WIN_EN)) chan
            (.clk(clk), .rst(rst), .adc_clk(adc_clk), .adc_lock(adc_lock),
             .Write(ch == 2'(k) ? Write : 4'b0000), .Addr(Addr), .WData(WData), .RData(rd[k]),
             .adc_cs_n(adc_cs_n[k]), .adc_sclk(adc_sclk[k]), .adc_sdo(adc_sdo[k]), .adc_cmp(adc_cmp[k]),
             .win_i(win_i), .wmean_o(wmean_o[k]), .wstb_o(wstb_o[k]), .irq(irq_ch[k]));
    end

    //Данные чтения канала: при MEMORY_TYPE = 1 канал выдаёт их на следующем такте - выбор по ch_q
    wire [1:0] sel = MEMORY_TYPE ? ch_q : ch;
    assign RData = (int'(sel) < NCH) ? rd[sel] : 32'd0;
    assign irq   = |irq_ch;
endmodule
