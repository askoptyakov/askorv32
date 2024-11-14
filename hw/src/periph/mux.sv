module memmux
  #(parameter                      MEMORY_TYPE = 0, 
    parameter                      SLAVES      = 2, //Количество подчинённых устройств
    parameter    [(SLAVES*32)-1:0] MATCH_ADDR  = 0,
    parameter    [(SLAVES*32)-1:0] MATCH_MASK  = 0)
   (input  logic                   clk, rst,
    // Интерфейс мастера
    input  logic            [ 3:0] mWrite,
    input  logic            [31:0] mAddr, mWData, 
    output logic            [31:0] mRData,
    // Интерфейс подчинённых
    output logic [(SLAVES* 4)-1:0] sWrite,
    output logic [(SLAVES*32)-1:0] sAddr, sWData,
    input  logic [(SLAVES*32)-1:0] sRData
); 
    
    logic [SLAVES-1:0] match;
    generate
        for(genvar i=0; i<SLAVES ; i=i+1) begin : addr_match
            assign match[i] = (mAddr & MATCH_MASK[i*32+:32]) == MATCH_ADDR[i*32+:32];//rvfpga
            //assign match[i] = ~|((mAddr ^ MATCH_ADDR[i*32+:32]) & MATCH_MASK[i*32+:32]);//picotiny
            assign sWrite[i*4+:4] = mWrite & {4{match[i]}}; 
        end
    endgenerate

    localparam SSEL_WIDTH  = $clog2(SLAVES);
    logic [SSEL_WIDTH-1:0] ssel;
    always_comb begin
        ssel = '0;
        for (int i = 0; i < SLAVES; i++) begin
            if (match[i]) begin
                ssel = i;
                break;
            end
        end
    end
 
    assign sAddr  = {SLAVES{mAddr }};
    assign sWData = {SLAVES{mWData}};
    
    //Для памяти BSRAM сигнал выбора устройства должен быть регистровым,
    //а для синтезированной памяти сигнал выбора устройства должен быть комбинационным.
    generate if (MEMORY_TYPE) begin   //#1 - Память BSRAM
        logic [SSEL_WIDTH-1:0] ssel_r;
        always_ff @(posedge clk, posedge rst)
            if (rst) ssel_r <= SSEL_WIDTH'('0);
            else     ssel_r <= ssel;
        assign mRData = sRData[ssel_r*32+:32];
    end else begin                    //#0 - Синтезированная память
        assign mRData = sRData[ssel*32+:32];
    end
    endgenerate
endmodule