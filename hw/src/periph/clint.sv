//==============================================================================================
// clint_top - Core-Local Interruptor (CLINT): машинный таймер и программное прерывание
//==============================================================================================
//DESCRIPTION: Регистры и адреса как у SiFive CLINT (FE310-G002, глава 9), один hart.
//Карта регистров (смещение от базового адреса, доступ только словами по 32 бит):
//  0x0000 - msip          : бит 0 - запрос программного прерывания (MSI, mcause 3)
//  0x4000 - mtimecmp[31:0] : порог машинного таймера
//  0x4004 - mtimecmp[63:32]
//  0xBFF8 - mtime[31:0]    : 64-битный счётчик, +1 на каждом такте clk
//  0xBFFC - mtime[63:32]
//Прерывание машинного таймера (MTI, mcause 7) активно, пока mtime >= mtimecmp.
//Флаг сравнения регистровый (короткий путь к ядру); запись в mtimecmp сбрасывает его сразу,
//чтобы после выхода из обработчика (mret) прерывание не пришло повторно из-за задержки флага.
//После сброса mtimecmp = 0xFFFF_FFFF_FFFF_FFFF - прерывание таймера не возникает.
module clint_top
  #(parameter                      MEMORY_TYPE = 0)
   (input  logic                   clk, rst,
    // Интерфейс обмена
    input  logic            [ 3:0] Write,
    input  logic            [31:0] Addr, WData,
    output logic            [31:0] RData,
    // Запросы прерываний
    output logic                   irq_msi, irq_mti
);
    localparam logic [15:0] MSIP        = 16'h0000,
                            MTIMECMP_LO = 16'h4000, MTIMECMP_HI = 16'h4004,
                            MTIME_LO    = 16'hBFF8, MTIME_HI    = 16'hBFFC;

    logic        msip;
    logic [63:0] mtime, mtimecmp;
    logic        mtip;
    logic        we;
    assign we = |Write;

    always_ff @(posedge clk)
        if (rst) begin
            msip     <= 1'b0;
            mtime    <= 64'd0;
            mtimecmp <= '1;
            mtip     <= 1'b0;
        end else begin
            mtime <= mtime + 64'd1;
            mtip  <= (mtime >= mtimecmp);
            if (we)
                case (Addr[15:0])
                    MSIP:        msip            <= WData[0];
                    MTIMECMP_LO: begin mtimecmp[31:0]  <= WData; mtip <= 1'b0; end
                    MTIMECMP_HI: begin mtimecmp[63:32] <= WData; mtip <= 1'b0; end
                    MTIME_LO:    mtime[31:0]     <= WData;
                    MTIME_HI:    mtime[63:32]    <= WData;
                    default: ;
                endcase
        end

    assign irq_msi = msip;
    assign irq_mti = mtip;

    logic [31:0] rdata;
    always_comb
        case (Addr[15:0])
            MSIP:        rdata = {31'd0, msip};
            MTIMECMP_LO: rdata = mtimecmp[31:0];
            MTIMECMP_HI: rdata = mtimecmp[63:32];
            MTIME_LO:    rdata = mtime[31:0];
            MTIME_HI:    rdata = mtime[63:32];
            default:     rdata = 32'd0;
        endcase

    generate if (MEMORY_TYPE) begin   //#1 - Память BSRAM: чтение с задержкой на такт, как у блоков памяти
        always_ff @(posedge clk) RData <= rdata;
    end else begin                    //#0 - Синтезированная память
        assign RData = rdata;
    end
    endgenerate
endmodule
