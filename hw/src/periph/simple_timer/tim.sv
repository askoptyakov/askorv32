module stim_top 
  #(parameter                      MEMORY_TYPE = 0)
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

    logic [31:0] tim_presclaer, tim_counter_mode, tim_counter_period, tim_pulse;
    logic [31:0] tim_counter;

    always_ff @(posedge clk)
    if(rst) begin
        tim_presclaer <= 32'd0;
        tim_counter_mode <= 32'd0;
        tim_counter_period <= 32'd0;
        tim_pulse <= 32'd0;
    end
    else
        case (Addr[4:2])
            0 : begin
                    if (Write[0]) tim_presclaer[7:0]            <= WData[7:0];
                    if (Write[1]) tim_presclaer[15:8]           <= WData[15:8];
                    if (Write[2]) tim_presclaer[23:16]          <= WData[23:16];
                    if (Write[3]) tim_presclaer[31:24]          <= WData[31:24];
                end
            1 : begin
                    if (Write[0]) tim_counter_mode[7:0]         <= WData[7:0];
                    if (Write[1]) tim_counter_mode[15:8]        <= WData[15:8];
                    if (Write[2]) tim_counter_mode[23:16]       <= WData[23:16];
                    if (Write[3]) tim_counter_mode[31:24]       <= WData[31:24];
                end
            2 : begin
                    if (Write[0]) tim_counter_period[7:0]       <= WData[7:0];
                    if (Write[1]) tim_counter_period[15:8]      <= WData[15:8];
                    if (Write[2]) tim_counter_period[23:16]     <= WData[23:16];
                    if (Write[3]) tim_counter_period[31:24]     <= WData[31:24];
                end
            3 : begin
                    if (Write[0]) tim_pulse[7:0]                <= WData[7:0];
                    if (Write[1]) tim_pulse[15:8]               <= WData[15:8];
                    if (Write[2]) tim_pulse[23:16]              <= WData[23:16];
                    if (Write[3]) tim_pulse[31:24]              <= WData[31:24];
                end
            default: ;
        endcase

    //Флаг события обновления: установка важнее одновременного сброса записью 1
    logic tim_update, tim_uif;
    always_ff @(posedge clk)
        if (rst)                                           tim_uif <= 1'b0;
        else if (tim_update)                               tim_uif <= 1'b1;
        else if (Addr[4:2] == 3'd5 && Write[0] && WData[0]) tim_uif <= 1'b0;

    assign irq = tim_uif & tim_counter_mode[4];

    generate if (MEMORY_TYPE) begin   //#1 - Память BSRAM
        always_ff @(posedge clk)
            case (Addr[4:2])
                0 : RData <= tim_presclaer[31:0];
                1 : RData <= tim_counter_mode[31:0];
                2 : RData <= tim_counter_period[31:0];
                3 : RData <= tim_pulse[31:0];
                4 : RData <= tim_counter[31:0];
                5 : RData <= {31'd0, tim_uif};
          default : RData <= 32'd0;
            endcase
    end else begin                    //#0 - Синтезированная память
        always_comb
            case (Addr[4:2])
                0 : RData = tim_presclaer[31:0];
                1 : RData = tim_counter_mode[31:0];
                2 : RData = tim_counter_period[31:0];
                3 : RData = tim_pulse[31:0];
                4 : RData = tim_counter[31:0];
                5 : RData = {31'd0, tim_uif};
          default : RData = 32'd0;
            endcase
    end
    endgenerate

    //wire auto_reload_preload = 1'b1; 
    reg out_p_1,out_n_1;

    simple_tim simple_tim  (.clk(clk), .rst(rst),
                            .prescaler(tim_presclaer[31:0]), .counter_mode(tim_counter_mode[1:0]),      .counter_period(tim_counter_period[31:0]),
                            .pulse(tim_pulse[31:0]),         .auto_reload_preload(tim_counter_mode[2]), .enable_disable_timer(tim_counter_mode[3]), 
                            .out_p_1(out_p_1),               .out_n_1(out_n_1), .out_counter(tim_counter[31:0]),
                            .update(tim_update));
    assign tim_out = out_p_1;

endmodule

    
module simple_tim (
	input logic clk,
	input logic rst,
	input logic[31:0] prescaler,
	input logic[1:0] counter_mode,
	input logic[31:0] counter_period,
	input logic[31:0] pulse,
    input logic auto_reload_preload,
    input logic enable_disable_timer,
    
	output logic out_p_1,
	output logic out_n_1,
	output logic[31:0] out_counter,
	output logic update            //Событие обновления: один такт clk
);

	logic[31:0] counter_tim;
    logic[31:0] counter_period_tim; // теневой(основной) регистр переполнения
	logic enable;
    logic[31:0] counter;

   	always @(posedge clk or posedge rst)
		if (rst) counter <= 32'd0;
		else begin
			if (prescaler == counter || !enable_disable_timer) counter <= 32'd0; //Выключенный таймер: первый тик через полный период предделителя
			else counter <= counter + 1'b1;
		end

	assign enable = (counter == prescaler);

    logic load;                    //переполнение  
    logic direction;               // 0 - вверх, 1 - вниз
    
    always_ff @(posedge clk or posedge rst) begin        
        if (rst) begin
            counter_tim <= 32'd0;
            direction <= 0; // Начинаем с счета вверх
            counter_period_tim <= 32'd0;
        end 
        else begin
          //Теневой регистр периода: без предзагрузки и при выключенном таймере сразу повторяет PER,
          //с предзагрузкой - обновляется при перезагрузке счётчика
          if (~auto_reload_preload | ~enable_disable_timer) counter_period_tim <= counter_period;
          else if (enable & load)                          counter_period_tim <= counter_period;
          if (enable & enable_disable_timer) begin   
            case (counter_mode)
                2'b00: begin // Счет вверх
                   if (load) counter_tim <= 32'd0;
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
                                                       (direction == 1'b1 && counter_tim == 32'd0))));
    assign out_n_1 = counter_tim >= pulse;
    assign out_p_1 = ~out_n_1;

endmodule

