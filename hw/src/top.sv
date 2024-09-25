module top   
   (input  logic       clk,     //Вход тактирования
    input  logic       rst_n,     //Вход сброса (кнопка S2)
    output logic [5:0] led      //Выход на 6 светодиодов
);
    logic clk_p = 0;
    always_ff @(posedge clk) clk_p <= ~clk_p;
    
    //#0 Устранение дребезжания с кнопки S2 (rst_n)
    logic [15:0] btn_sync = 0;
    logic rst_sync_n = 0;
    logic rst_sync;
    
    always_ff @(posedge clk_p)
        if (rst_n)
            btn_sync <= {btn_sync[14:0], 1'b1};
        else
            btn_sync <= {1'b0, btn_sync[15:1]};
    
    always_ff @(posedge clk_p) 
        if (btn_sync == 16'b1111_1111_1111_1111) rst_sync_n <= 1'b1;
        else    if (btn_sync == 16'b0000_0000_0000_0000) rst_sync_n <= 1'b0;
                else rst_sync_n <= rst_sync_n;

    assign rst_sync = ~rst_sync_n;

    //#1 Подключаем ядро процессора
        //Интерфейс памяти команд
    logic [31:0] imem_data;
    logic [10:0]  imem_addr;
        //Интерфейс памяти данных
    logic [31:0] dmem_ReadData;
    logic        dmem_Write;
    logic [31:0] dmem_Addr, dmem_WriteData;
        //Ядро
    core riscv(.clk(clk_p), .rst(rst_sync), .out(led), //Системные
               .imem_data(imem_data), .imem_addr(imem_addr),           //Память команд
               .dmem_ReadData(dmem_ReadData), .dmem_Write(dmem_Write),      //Память данных
               .dmem_Addr(dmem_Addr), .dmem_WriteData(dmem_WriteData));
   
    //#2 Подключаем память
    //imem imem(.addr(imem_addr), .instr(imem_data));
    
    bsram8k imem(
        .dout(imem_data), //output [31:0] dout
        .clk(clk), //input clk
        .oce(1'b0), //input oce
        .ce(1'b1), //input ce
        .reset(1'b0), //input reset
        .wre(1'b0), //input wre
        .ad(imem_addr), //input [10:0] ad
        .din(32'b0000_0000_0000_0000_0000_0000_0000_0000) //input [31:0] din
    );

    dmem dmem(.clk(clk_p), .we(dmem_Write), .reset(rst_sync),
              .a(dmem_Addr), .wd(dmem_WriteData),
              .rd(dmem_ReadData));
endmodule