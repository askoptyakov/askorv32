
module adc_v_top 
  #(parameter                      MEMORY_TYPE = 0)
   (input  logic                   clk, rst,
    input  logic                   clk_pll,
    // Интерфейс обмена
    input  logic            [ 3:0] Write,
    input  logic            [31:0] Addr, WData, 
    output logic            [31:0] RData,
    // Физические подключения
    output  logic                   adc_v_clk,
    input   logic                   adc_v_miso,
    output  logic                   adc_v_cs
);
    //Карта регистров:
    //>>0x00 - включение измерений
    //>>0x04 - даннные полученные с модуля

    logic [31:0] adc_v_enable; 
    logic [31:0] adc_v_data;

    always_ff @(posedge clk)
    if(rst) begin
        adc_v_enable <= 32'd0;
    end
    else
        case (Addr[2])
            0 : begin
                    if (Write[0]) adc_v_enable[7:0]            <= WData[7:0];
                    if (Write[1]) adc_v_enable[15:8]           <= WData[15:8];
                    if (Write[2]) adc_v_enable[23:16]          <= WData[23:16];
                    if (Write[3]) adc_v_enable[31:24]          <= WData[31:24];
                end
    //default :
        endcase

    generate if (MEMORY_TYPE) begin   //#1 - Память BSRAM
        always_ff @(posedge clk)
            case (Addr[2])
                0 : RData <= adc_v_enable[31:0];
                1 : RData <= adc_v_data[31:0];
          default : RData <= 32'd0;
            endcase
    end else begin                    //#0 - Синтезированная память
        always_comb
            case (Addr[4:2])
                0 : RData = adc_v_enable[31:0];
                1 : RData = adc_v_data[31:0];
          default : RData = 32'd0;
            endcase
    end
    endgenerate

    adc121s051_interface adc_v  (.clk(clk_pll), .rst(rst),
                                .enable(adc_v_enable[0]),      .miso(adc_v_miso),
                                .cs_n(adc_v_cs), .sclk(adc_v_clk), .adc_data(adc_v_data));

endmodule


module adc121s051_interface (

    input logic enable,
    input logic clk,            // Системная тактовая частота
    input logic rst,            // Сброс (активный низкий)

    input logic miso,           // Master In Slave Out
    output logic cs_n,          // Chip Select (активный низкий)
    output logic sclk,          // тактовая частота на модуль
    
    output logic [31:0] adc_data // Прочитанные данные с АЦП

);

    // Параметры для SPI
    logic sclk_en;

    // Состояния конечного автомата
    typedef enum logic [1:0] {
        IDLE,
        START,
        READ,
        DONE
    } state_t;

    state_t state, next_state;
    logic [5:0] bit_counter;
    logic [14:0] shift_reg;

    // Генерация SCLK   
    assign sclk = sclk_en ? clk : 0;

    // Основной конечный автомат 
    always_ff @(negedge clk or posedge rst) begin
        if (rst) begin
            state <= IDLE;
            cs_n <= 1;
            bit_counter <= 0;
            shift_reg <= 0;
            sclk_en <= 0;
        end else begin
            state <= next_state;
            case (state)
                IDLE: begin
                    cs_n <= 1;
                    sclk_en <= 0;
                    bit_counter <= 0;
                    shift_reg <= 0;
                    adc_data <= { 20'd0, shift_reg[11:0]};
                end
                START: begin
                    cs_n <= 0;
                    sclk_en <= 1;
                end
                READ: begin                
                    cs_n <= 0;
                    shift_reg <= {shift_reg[13:0], miso};
                    bit_counter <= bit_counter + 1'b1;
                    
                end
                DONE: begin
                    shift_reg <= {shift_reg[13:0], miso};
                    cs_n <= 1;
                    sclk_en <= 0;
                end
            endcase
        end
    end

    // Логика переходов между состояниями
    always_comb begin
        next_state = state;
        case (state) 
            IDLE: if (enable) next_state = START; //условие начала чтения
            START: next_state = READ;
            READ: if (bit_counter == 14) next_state = DONE;
            DONE: next_state = IDLE;
        endcase
    end

endmodule
