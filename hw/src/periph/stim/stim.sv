module stim_top 
  #(parameter                      MEMORY_TYPE = 0,
    parameter int                  WIDTH       = 16)  //Разрядность предделителя, периода, сравнения и счётчика (Р2)
   (input  logic                   clk, rst,
    // Интерфейс обмена
    input  logic            [ 3:0] Write,
    input  logic            [31:0] Addr, WData, 
    output logic            [31:0] RData,
    // Физические подключения
    output  logic                   tim_out,
    // Запрос прерывания (SR.UIF & CR.UIE)
    output  logic                   irq
);
    //Карта регистров:
    //>>0x00 - Установка предделителя частоты таймера
    //>>0x04 - Установка управления счетчиком(направление счета, вкл/выкл, режим arp, разрешение прерывания)
    //         [1:0] CM - режим счёта; [2] ARP; [3] EN; [4] UIE - разрешение прерывания по событию обновления
    //>>0x08 - Установка значения переполнения таймера
    //>>0x0c - Установка значение сравнения
    //<<0x10 - Текущее значение счетчика таймера
    //<>0x14 - Регистр состояния: [0] UIF - событие обновления (переполнение счёта вверх, достижение 0
    //         при счёте вниз, смена направления в режиме вверх-вниз); сбрасывается записью 1
    //Р2: предделитель, период, сравнение и счётчик - WIDTH бит (по умолчанию 16, как у базовых таймеров
    //STM32), CR - 5 бит. Старшие биты при записи отбрасываются, при чтении - нули.

    logic [WIDTH-1:0] tim_presclaer, tim_counter_period, tim_pulse, tim_counter;
    logic [      4:0] tim_counter_mode;
    logic             tim_update, tim_uif;

    //Регистровый интерфейс по шаблону periph_regs (periph/periph_regs.sv): стробы по регистрам и
    //данные чтения. Строб чтения таймеру не нужен - регистров с побочным действием при чтении нет
    logic [5:0][ 3:0] we;
    logic      [31:0] wdata;
    periph_regs #(.N(6), .MEMORY_TYPE(MEMORY_TYPE)) regs
        (.clk(clk), .Write(Write), .Read(1'b0), .Addr(Addr), .WData(WData), .RData(RData),
         .we(we), .re(), .wdata(wdata),
         .rdata({32'(tim_uif),                                   //0x14 SR
                 32'(tim_counter),                               //0x10 CNT (только чтение)
                 32'(tim_pulse),                                 //0x0C PUL
                 32'(tim_counter_period),                        //0x08 PER
                 32'(tim_counter_mode),                          //0x04 CR
                 32'(tim_presclaer)}));                          //0x00 PR

    //Регистры настройки - обычные регистры чтения/записи. У CR 5 бит, пишется байт 0
    periph_reg #(.W(WIDTH)) r_pr  (.clk(clk), .rst(rst), .we(we[0]), .wdata(wdata), .q(tim_presclaer));
    periph_reg #(.W(5))     r_cr  (.clk(clk), .rst(rst), .we(we[1]), .wdata(wdata), .q(tim_counter_mode));
    periph_reg #(.W(WIDTH)) r_per (.clk(clk), .rst(rst), .we(we[2]), .wdata(wdata), .q(tim_counter_period));
    periph_reg #(.W(WIDTH)) r_pul (.clk(clk), .rst(rst), .we(we[3]), .wdata(wdata), .q(tim_pulse));

    //SR.UIF - флаг события обновления: ставит таймер, сбрасывает запись 1 в бит 0 (установка важнее
    //одновременного сброса)
    always_ff @(posedge clk)
        if (rst)                         tim_uif <= 1'b0;
        else if (tim_update)             tim_uif <= 1'b1;
        else if (we[5][0] && wdata[0])   tim_uif <= 1'b0;

    //Ч14: запрос на ядро - через регистр (как у PLIC): иначе путь «регистры таймера -> запрос ->
    //решение о ловушке -> адрес PC» ограничивал частоту ядра. Прерывание приходит на такт позже
    always_ff @(posedge clk)
        if (rst) irq <= 1'b0;
        else     irq <= tim_uif & tim_counter_mode[4];

    //wire auto_reload_preload = 1'b1; 
    reg out_p_1,out_n_1;

    simple_tim #(WIDTH) simple_tim  (.clk(clk), .rst(rst),
                            .prescaler(tim_presclaer),       .counter_mode(tim_counter_mode[1:0]),      .counter_period(tim_counter_period),
                            .pulse(tim_pulse),               .auto_reload_preload(tim_counter_mode[2]), .enable_disable_timer(tim_counter_mode[3]), 
                            .out_p_1(out_p_1),               .out_n_1(out_n_1), .out_counter(tim_counter),
                            .update(tim_update));
    assign tim_out = out_p_1;

endmodule

    
module simple_tim #(parameter int WIDTH = 16) (
	input logic clk,
	input logic rst,
	input logic[WIDTH-1:0] prescaler,
	input logic[1:0] counter_mode,
	input logic[WIDTH-1:0] counter_period,
	input logic[WIDTH-1:0] pulse,
    input logic auto_reload_preload,
    input logic enable_disable_timer,
    
	output logic out_p_1,
	output logic out_n_1,
	output logic[WIDTH-1:0] out_counter,
	output logic update            //Событие обновления: один такт clk
);

	logic[WIDTH-1:0] counter_tim;
    logic[WIDTH-1:0] counter_period_tim; // теневой(основной) регистр переполнения
	logic enable;
    logic[WIDTH-1:0] counter;

   	always @(posedge clk or posedge rst)
		if (rst) counter <= '0;
		else begin
			if (prescaler == counter || !enable_disable_timer) counter <= '0; //Выключенный таймер: первый тик через полный период предделителя
			else counter <= counter + 1'b1;
		end

	assign enable = (counter == prescaler);

    logic load;                    //переполнение  
    logic direction;               // 0 - вверх, 1 - вниз
    
    always_ff @(posedge clk or posedge rst) begin        
        if (rst) begin
            counter_tim <= '0;
            direction <= 0; // Начинаем с счета вверх
            counter_period_tim <= '0;
        end 
        else begin
          //Теневой регистр периода: без предзагрузки и при выключенном таймере сразу повторяет PER,
          //с предзагрузкой - обновляется при перезагрузке счётчика
          if (~auto_reload_preload | ~enable_disable_timer) counter_period_tim <= counter_period;
          else if (enable & load)                          counter_period_tim <= counter_period;
          if (enable & enable_disable_timer) begin   
            case (counter_mode)
                2'b00: begin // Счет вверх
                   if (load) counter_tim <= '0;
                   else counter_tim <= counter_tim + 1'b1;
                end
                2'b01: begin // Счет вниз
                   if (load) counter_tim <= counter_period_tim;
                   else counter_tim <= counter_tim - 1'b1;
                end
                2'b10: begin // Счет вверх-вниз                    
                    if (direction == 0) begin // Счет вверх
                        if (counter_tim == counter_period_tim) begin
                            direction <= 1; // Меняем направление на вниз
                            counter_tim <= counter_tim - 1'b1;
                        end
                        else counter_tim <= counter_tim + 1'b1;
                    end  
                    else begin // Счет вниз
                        if (counter_tim == 0) begin
                            direction <= 0; // Меняем направление на вверх
                            counter_tim <= counter_tim + 1'b1;
                        end 
                        else counter_tim <= counter_tim - 1'b1;
                    end
                end
            endcase
          end
        end
    end

    assign load = (counter_mode == 2'b00 && counter_tim >= counter_period_tim) || //>=: период можно уменьшить на ходу
                  (counter_mode == 2'b01 && counter_tim == 0);

    assign out_counter = counter_tim;
    //Событие обновления - на том же такте предделителя, на котором счётчик перезагружается
    //или меняет направление
    assign update = enable & enable_disable_timer &
                    (load | (counter_mode == 2'b10 && ((direction == 1'b0 && counter_tim == counter_period_tim) ||
                                                       (direction == 1'b1 && counter_tim == '0))));
    assign out_n_1 = counter_tim >= pulse;
    assign out_p_1 = ~out_n_1;

endmodule

