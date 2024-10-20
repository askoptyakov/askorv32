/* Заметки:
1. Для штатной работы однотактного ядра (SINGLECYCLE_CORE) необходима асинхронная память инструкций
и данных, которая может быть получена при варианте синтезируемой на ячейках памяти(SYNTH_MEM). В
таком режиме ядро практически полностью является комбинационным и может работать на общей частоте
тактирования (clk), одна инструкция выполняется за один такт. Если же использовать внутреннюю
память плис (BSRAM_MEM), которая является синхронной, то ядро становистя псевдо однотактным
поскольку данные записываются и считываются из памяти по переднему фронту тактового сигнала и для
одной инструкции необходимо уже 3 такта. Первый такт приходит на тактирования всех узлов ядра,
кроме памяти инструкций, которая тактируется от второго такта, и памяти данных, которая тактируется
от третьего такта. Думаю что реализвация однотактного ядра с синхронной памятью возможна при
2 тактах, необходима !дополнительная проработка!
2. При использовании памяти BSRAM в конвеерном ядре межстадийным регистром является сама память
поскольку она явлется синхронной и выдаёт данные на выход по такту. При использовании синтезированной
памяти в конвеерном ядре нужен дополнительный межстадийный регистр поскольку память асинхронная и
необходимо разделить стадии регистрами. Для однотактного ядра межстадийный регистр не нужен, связь
явлется проводником.
3. Связано с пунктом 2. При разработке приостановки конвейера, всвязи с конфликтом при выполнении
инструкции lw, необходимо задержать межстадийный регистр (fetch-decode) на один такт. Поскольку в
конвейерном ядре с памятью BSRAM межстадийным регистром является сама память приходится отключать
тактирование памяти на 1 такт подачей сигнала imem_re на контакт ce (clock enable) BSRAM. В текущей
конфигурации кода появилось очень длинная связь именно логическая, сложная для понимания, но не
нарушающая и не ухудшающая параметры ядра. Возможно пересмотреть.
4. Не очень нравится как реализованы интерфейсы мамяти в ядре. Может лучше достать их из модулей
стадий конвейера и поместить в главный модуль core. Подумать.
*/

//============================================================================================== 
// Определения настроек ядра
//============================================================================================== 
//#1 CORE_TYPE #
`define SINGLECYCLE_CORE 1
`define PIPELINE_CORE 0
//#2 MEMORY_TYPE #
`define BSRAM_MEM 1
`define SYNTH_MEM 0
//============================================================================================== 

module top #(parameter [0:0] CORE_TYPE   = `PIPELINE_CORE,
             parameter [0:0] MEMORY_TYPE = `SYNTH_MEM)   
            (input  logic       clk,     //Вход тактирования
             input  logic       rst_n,   //Вход сброса (кнопка S2)
             output logic [5:0] led      //Выход на 6 светодиодов
);
    //#0 Настройка тактирования
    //DESCRIPTION: Для однотактного ядра при использовании BSAM делаем псевдооднотактный процессор
    //с тремя тактами на одну инструкцию. Тактируем imem и dmem 2ым и 3ьим тактом.
    //logic clk_div2;
    //always_ff @(posedge clk) clk_div2 <= ~clk_div2;

    logic clk_core, clk_imem, clk_dmem;
    generate if (MEMORY_TYPE & CORE_TYPE) begin   //#1 - Для однотактного ядра с BSRAM
        divideby3 divideby3(.clk(clk), .clk_div3(clk_core), .clk_imem(clk_imem), .clk_dmem(clk_dmem));
    end else begin                                //#0 - Прочие конфигурации
        assign clk_core = clk;
        assign clk_imem = clk;
        assign clk_dmem = clk;
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
    logic [10:0] imem_addr;
        //Интерфейс памяти данных
    logic [31:0] dmem_ReadData;
    logic        dmem_Write;
    logic [31:0] dmem_Addr, dmem_WriteData;
        //Ядро
    core #(.CORE_TYPE(CORE_TYPE),
           .MEMORY_TYPE(MEMORY_TYPE))
           riscv  
          (.clk(clk_core), .rst(rst_sync), .out(led),                                            //Системные
           .imem_data(imem_data), .imem_re(imem_re), .imem_rst(imem_rst), .imem_addr(imem_addr), //Интерфейс памяти команд
           .dmem_ReadData(dmem_ReadData), .dmem_Write(dmem_Write),                               //Интерфейс памяти данных
           .dmem_Addr(dmem_Addr), .dmem_WriteData(dmem_WriteData));
   
    //#3 Подключаем память
    imem #(MEMORY_TYPE) imem(.clk(clk_imem), .rst(rst_sync|imem_rst), .re(imem_re), .addr(imem_addr), .data(imem_data));

    dmem #(MEMORY_TYPE) dmem(.clk(clk_dmem), .reset(rst_sync), .we(dmem_Write),
                             .a(dmem_Addr), .wd(dmem_WriteData),
                             .rd(dmem_ReadData));
endmodule