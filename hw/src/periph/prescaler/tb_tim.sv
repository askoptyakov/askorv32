
module tb_tim;

    //localparam clk_mhz = 1,
    //------------------------------------------------------------------------
    logic       clk;
    logic       rst;
    logic divided_clk;
    logic[31:0] presc;
    //------------------------------------------------------------------------
    // Экземпляр тестируемого модуля
    div_clk div_tim 
    (
        .clk      ( clk ),
        .rst      ( rst ),
        .prescaler(presc),
        .clk_pre  (divided_clk)     
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
    presc <= 16;
    #1000; // Длительность теста
    presc <= 8;
    #1000;
    $finish;
  end

endmodule
