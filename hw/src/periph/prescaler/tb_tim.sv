
module tb_tim;

    //------------------------------------------------------------------------
    logic       clk;
    logic       rst;
    logic       enable;
    logic[15:0] prescaler;
    logic       auto_reload_preload;

    logic[1:0]  counter_mode;
    logic[15:0] counter_period;
    logic[15:0] pulse;
    logic out_1;
    logic out_2;
    //------------------------------------------------------------------------
    // Экземпляр тестируемого модуля
/*    
    div_clk div_clk 
    (
        .clk      ( clk ),
        .rst      ( rst ),
        .prescaler(prescaler),
        .clk_pre  (enable)     
    );
*/
    tim tim
    (
      .clk(clk),
      .rst(rst),
      .prescaler(prescaler),
      .counter_mode(counter_mode),
      .counter_period(counter_period),
      .pulse(pulse),
      .auto_reload_preload(auto_reload_preload),
      .out_p_1(out_1),
      .out_n_1(out_2)
    );

    //------------------------------------------------------------------------
    // Генерация тактового сигнала
    initial
    begin
        clk = 1'b0;
        forever
            # 5 clk = ~ clk;
    end

    //------------------------------------------------------------------------
    // Инициализация
    initial
    begin
        rst <= 1'bx;
        repeat (2) @ (posedge clk);
        rst <= 1'b1;
        repeat (2) @ (posedge clk);
        rst <= 1'b0;
    end

  initial
  begin
    `ifdef __ICARUS__
      // Uncomment the following line
      // to generate a VCD file and analyze it using GTKwave or Surfer

      $dumpvars;
    `endif
    prescaler <= 2;

    auto_reload_preload <= 0;
    counter_mode <= 2'b00;
    counter_period <= 10;
    pulse <= 5;
    #1000; // Длительность теста
    rst <= 1'b1;
    counter_mode <= 2'b01;
    #5
    rst <= 1'b0;
    #1000
    rst <= 1'b1;
    counter_mode <= 2'b10;
    auto_reload_preload <= 0;
    #5
    rst <= 1'b0;
    #500
    counter_period <= 15;
    #500
    $finish;
  end

endmodule
