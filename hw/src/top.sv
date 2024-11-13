//============================================================================================== 
// Определения настроек ядра
//============================================================================================== 
//#1 CORE_TYPE #
`define SINGLECYCLE_CORE 1
`define PIPELINE_CORE    0
//#2 MEMORY_TYPE #
`define BSRAM_MEM        1
`define SYNTH_MEM        0
//DSECRIPTION:
//1) Максимальная суммарная память BSRAM_IMEM_SIZE + BSRAM_DMEM_SIZE = 48кБ.
//============================================================================================== 
        
module top #(parameter bit CORE_TYPE       =    `PIPELINE_CORE,
                //Настройки памяти инструкций
             parameter bit IMEM_TYPE       =        `BSRAM_MEM,
             parameter int BSRAM_IMEM_SIZE =                 8, //кБайт (поддерживаемые значения 8/16/32)
             parameter int SYNTH_IMEM_SIZE =               256, //слов по 4 Байт
             parameter     IMEM_INIT_FILE  =  "mem_init/i.mem",
                //Настройки памяти данных
             parameter bit DMEM_TYPE       =        `BSRAM_MEM, 
             parameter int BSRAM_DMEM_SIZE =                 8, //кБайт (поддерживаемые значения 8/16/32)
             parameter int SYNTH_DMEM_SIZE =               256, //слов по 4 Байт
             parameter     DMEM_INIT_FILE  =  "mem_init/d.mem")   
            (input  logic       clk,     //Вход тактирования
             input  logic       rst_n,   //Вход сброса (кнопка S2)
             output logic [5:0] led,      //Выход на 6 светодиодов
             inout        [2:0] GPIO
);
    //#0 Настройка тактирования 
    //DESCRIPTION: Для однотактного ядра при использовании BSAM делаем псевдооднотактный процессор
    //с тремя тактами на одну инструкцию. Тактируем imem и dmem 2ым и 3ьим тактом.
    logic clk_div2; 
    always_ff @(posedge clk) clk_div2 <= ~clk_div2;

    logic clk_core, clk_imem, clk_dmem;
    generate if ((IMEM_TYPE | DMEM_TYPE) & CORE_TYPE) begin   //#1 - Для однотактного ядра с BSRAM
        divideby3 divideby3(.clk(clk_div2), .clk_div3(clk_core), .clk_imem(clk_imem), .clk_dmem(clk_dmem));
    end else begin                                            //#0 - Прочие конфигурации
        assign clk_core = clk_div2;
        assign clk_imem = clk_div2;
        assign clk_dmem = clk_div2;
    end
    endgenerate
    
    //#1 Устранение дребезжания с кнопки S2 (rst_n)
    logic [15:0] btn_sync = 0;
    logic rst_sync_n = 0;
    logic rst_sync;
    
    always_ff @(posedge clk_core)
        if (rst_n)
            btn_sync <= {btn_sync[14:0], 1'b1};
        else
            btn_sync <= {1'b0, btn_sync[15:1]};
    
    always_ff @(posedge clk_core) 
        if (btn_sync == 16'b1111_1111_1111_1111) rst_sync_n <= 1'b1;
        else    if (btn_sync == 16'b0000_0000_0000_0000) rst_sync_n <= 1'b0;
                else rst_sync_n <= rst_sync_n;

    assign rst_sync = ~rst_sync_n;

    //#2 Подключаем ядро процессора
        //Интерфейс памяти команд
    logic [31:0] imem_data;
    logic        imem_re, imem_rst;
    logic [31:0] imem_addr;
        //Интерфейс памяти данных
    logic [31:0] dmem_ReadData;
    logic [ 3:0] dmem_Write;
    logic [31:0] dmem_Addr, dmem_WriteData;
        //Ядро
    
    core #(CORE_TYPE, IMEM_TYPE, DMEM_TYPE)
           riscv  
          (.clk(clk_core), .rst(rst_sync),                                                       //Системные
           .imem_data(imem_data), .imem_re(imem_re), .imem_rst(imem_rst), .imem_addr(imem_addr), //Интерфейс памяти команд
           .dmem_ReadData(dmem_ReadData), .dmem_Write(dmem_Write),                               //Интерфейс памяти данных
           .dmem_Addr(dmem_Addr), .dmem_WriteData(dmem_WriteData));
   
    //#3 Подключаем память инструкций
    mem #(IMEM_TYPE, SYNTH_IMEM_SIZE, BSRAM_IMEM_SIZE, IMEM_INIT_FILE) imem
          (.clk(clk_imem), .reset(rst_sync|imem_rst), .re(imem_re), .wstrb(4'b0000),
           .a(imem_addr), .wd(32'd0),
           .rd(imem_data));

    //#4 Подключаем память данных и периферийные модули
    
    //-0- Основной мультиплексор
    logic [ 3:0] mem_Write, leds_Write, tm_Write;
    logic [31:0] mem_Addr, leds_Addr, tm_Addr;
    logic [31:0] mem_WriteData, leds_WriteData, tm_WriteData;
    logic [31:0] mem_ReadData, leds_ReadData, tm_ReadData;

    mem_mux #(.MEMORY_TYPE(DMEM_TYPE), .SLAVES(3),
              .MATCH_ADDR ({32'h10000000, 32'h11000000, 32'h12000000}),
              .MATCH_MASK ({32'hff000000, 32'hff000000, 32'hff000000}))
            mem_mux
             (.clk(clk_dmem), .rst(rst_sync),
              // Интерфейс мастера
              .mWrite(dmem_Write),
              .mAddr (dmem_Addr), .mWData(dmem_WriteData), 
              .mRData(dmem_ReadData),
              // Интерфейс подчинённых
              .sWrite({mem_Write,    leds_Write,    tm_Write}),
              .sAddr ({mem_Addr,     leds_Addr,     tm_Addr}),
              .sWData({mem_WriteData,leds_WriteData,tm_WriteData}),
              .sRData({mem_ReadData, leds_ReadData, tm_ReadData}));

    //-1- Память данных
    mem #(DMEM_TYPE, SYNTH_DMEM_SIZE, BSRAM_DMEM_SIZE, DMEM_INIT_FILE) dmem
          (.clk(clk_dmem), .reset(rst_sync), .re(1'b1), .wstrb(mem_Write),
           .a(mem_Addr), .wd(mem_WriteData),
           .rd(mem_ReadData));
    
    //-2- Встроенные светодиоды(6шт.) 
    always_ff @(posedge clk_dmem) begin
        if (&leds_Write) led <= leds_WriteData[5:0];
        //leds_ReadData <= led;
    end

    generate if (DMEM_TYPE) begin   //#1 - Память BSRAM
        always_ff @(posedge clk_dmem) begin
            leds_ReadData <= led;
    end
    end else begin                    //#0 - Синтезированная память
        assign leds_ReadData = led;
    end
    endgenerate
    //-3- Внешний модуль tm1638
    //>>0x00 - Семисегментный индикатор
    //>>0x04 - Светодиоды/Кнопки
    //<<0x08 - Кнопки
    logic [ 7:0] tm_key, tm_led;
    logic [31:0] tm_digit;
    
    always_ff @(posedge clk_dmem)
        case (tm_Addr[3:2])
            0 : begin
                    if (tm_Write[0]) tm_digit[7:0]   <= tm_WriteData[7:0];
                    if (tm_Write[1]) tm_digit[15:8]  <= tm_WriteData[15:8];
                    if (tm_Write[2]) tm_digit[23:16] <= tm_WriteData[23:16];
                    if (tm_Write[3]) tm_digit[31:24] <= tm_WriteData[31:24];
                    //tm_ReadData <= tm_digit;
                end
            1 : begin
                    if (tm_Write[0]) tm_led[7:0]   <= tm_WriteData[7:0];
                    //tm_ReadData <= {24'd0, tm_led[7:0]};
                end
            //2 :     tm_ReadData <= {24'd0, tm_key[7:0]};
      //default :     tm_ReadData <= 32'd0;
        endcase


    generate if (DMEM_TYPE) begin   //#1 - Память BSRAM
        always_ff @(posedge clk_dmem)
            case (tm_Addr[3:2])
                0 : tm_ReadData <= tm_digit;
                1 : tm_ReadData <= {24'd0, tm_led[7:0]};
                2 : tm_ReadData <= {24'd0, tm_key[7:0]};
          default : tm_ReadData <= 32'd0;
            endcase
    end else begin                    //#0 - Синтезированная память
        always_comb
            case (tm_Addr[3:2])
                0 : tm_ReadData = tm_digit;
                1 : tm_ReadData = {24'd0, tm_led[7:0]};
                2 : tm_ReadData = {24'd0, tm_key[7:0]};
          default : tm_ReadData = 32'd0;
            endcase
    end
    endgenerate

    tm1638_board_controller #(.clk_mhz(27)) tm1638
        (.clk(clk_dmem), .rst(rst_sync),
         .digit_in(tm_digit), .ledr(tm_led), .keys(tm_key),
         .sio_dio(GPIO[0]), .sio_clk(GPIO[1]), .sio_stb(GPIO[2]));

endmodule