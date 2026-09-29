//==============================================================================================
// clint_top - Core-Local Interruptor (CLINT): машинный таймер и программное прерывание
//==============================================================================================
//DESCRIPTION: Регистры и адреса как у SiFive CLINT (FE310-G002, глава 9), один hart.
//Карта регистров (смещение от базового адреса, доступ только словами по 32 бит):
//  0x0000 - msip          : бит 0 - запрос программного прерывания (MSI, mcause 3)
//  0x4000 - mtimecmp[31:0] : порог машинного таймера
//  0x4004 - mtimecmp[63:32]
//  0xBFF8 - mtime[31:0]    : 64-битный счётчик, +1 на каждом такте ядра
//  0xBFFC - mtime[63:32]
//Р3: отдельного счётчика mtime в CLINT нет - это счётчик тактов ядра mcycle (trap_unit в core.sv):
//они считают один и тот же такт. CLINT читает его и сравнивает с mtimecmp, а запись в mtime по шине
//передаёт в ядро (mtime_we, mtime_wdata). Поэтому запись в mtime меняет и mcycle, и наоборот.
//Запись передаётся через регистр и применяется тактом позже: иначе путь «адрес шины -> дешифрация
//в CLINT -> запись счётчика в ядре» становился критическим. Счётчик получает записанное значение
//на такт позже, что для таймера незаметно (запись в mtime по шине и CSR-запись mcycle следующей
//же инструкцией применятся в обратном порядке - такой код не имеет смысла).
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
    output logic                   irq_msi, irq_mti,
    // Счётчик mtime = mcycle ядра (Р3)
    input  logic            [63:0] mtime,
    output logic            [ 1:0] mtime_we,       //Запись по шине: [0] - mtime[31:0], [1] - mtime[63:32]
    output logic            [31:0] mtime_wdata
);
    localparam logic [15:0] MSIP        = 16'h0000,
                            MTIMECMP_LO = 16'h4000, MTIMECMP_HI = 16'h4004,
                            MTIME_LO    = 16'hBFF8, MTIME_HI    = 16'hBFFC;

    logic        msip;
    logic [63:0] mtimecmp;
    logic        mtip;
    logic        we;
    assign we = |Write;

    always_ff @(posedge clk)
        if (rst) begin
            msip     <= 1'b0;
            mtimecmp <= '1;
            mtip     <= 1'b0;
            mtime_we <= 2'b00;
        end else begin
            mtip  <= (mtime >= mtimecmp);
            mtime_we <= {we & (Addr[15:0] == MTIME_HI), we & (Addr[15:0] == MTIME_LO)};
            if (we)
                case (Addr[15:0])
                    MSIP:        msip            <= WData[0];
                    MTIMECMP_LO: begin mtimecmp[31:0]  <= WData; mtip <= 1'b0; end
                    MTIMECMP_HI: begin mtimecmp[63:32] <= WData; mtip <= 1'b0; end
                    default: ;
                endcase
        end

    always_ff @(posedge clk) mtime_wdata <= WData;

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
