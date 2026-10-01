//==============================================================================================
// plic_top - Platform-Level Interrupt Controller (PLIC) для одного hart в машинном режиме
//==============================================================================================
//DESCRIPTION: Собирает запросы периферии (UART, SPI и т.д.) в одно внешнее прерывание ядра
//MEI (mcause 11). Устроен и адресуется как PLIC SiFive (FE310-G002, глава 10), в объёме одного
//контекста (hart 0, M-mode). Источники с номерами 1..NSRC (номер 0 зарезервирован).
//
//Карта регистров (смещение от базового адреса, доступ словами по 32 бит):
//  0x000000 + 4*N - priority[N]   : приоритет источника N, 0 - источник запрещён, 1..2^PRIO_BITS-1
//  0x001000       - pending       : бит N - запрос источника N ожидает обработки (только чтение)
//  0x002000       - enable        : бит N - разрешение источника N
//  0x200000       - threshold     : прерывание выдаётся, только если приоритет > threshold
//  0x200004       - claim/complete: чтение - номер ожидающего источника с наибольшим приоритетом
//                                   (при равенстве - с меньшим номером) или 0; чтение снимает pending;
//                                   запись номера - обработка источника завершена
//
//  0x200008       - vector        : бит 0 - векторный режим (расширение askoRV32, в PLIC SiFive этого
//                                   адреса нет - он зарезервирован в области контекста)
//
//Шлюзы (gateway) по уровню: запрос источника ставит pending, после claim новый запрос этого
//источника не принимается до complete. Если источник всё ещё активен после complete, pending
//ставится снова. Поэтому обработчик: claim -> сбросить флаг в периферии -> complete.
//
//Векторный режим: вместе с irq ядру выдаётся номер лучшего источника irq_id. Ядро в векторном режиме
//mtvec переходит сразу на вход 32 + irq_id таблицы векторов и сообщает об этом (vec_claim, vec_claim_id) -
//PLIC захватывает этот источник, как при чтении claim. Обработчику источника claim не нужен: он сбрасывает
//флаг в периферии и пишет complete. Захватывается номер, по которому ушло ядро, а не лучший на момент
//захвата: если в этот такт появился более важный источник, он дождётся своей очереди.
module plic_top
  #(parameter                      MEMORY_TYPE = 0,
    parameter int                  NSRC        = 8,  //Число источников (1..31)
    parameter int                  PRIO_BITS   = 3)  //Разрядность приоритета
   (input  logic                   clk, rst,
    // Интерфейс обмена
    input  logic            [ 3:0] Write,
    input  logic                   Read,
    input  logic            [31:0] Addr, WData,
    output logic            [31:0] RData,
    // Запросы источников (уровень, активная 1) и выход на ядро
    input  logic         [NSRC:1]  src,
    output logic                   irq,          //MEI
    output logic            [ 4:0] irq_id,       //Номер лучшего источника (с регистра, вместе с irq)
    output logic                   vec_en,       //Векторный режим
    input  logic                   vec_claim,    //Ядро приняло MEI по вектору источника vec_claim_id
    input  logic            [ 4:0] vec_claim_id
);
    localparam logic [21:0] PENDING = 22'h001000, ENABLE = 22'h002000,
                            THRESHOLD = 22'h200000, CLAIM = 22'h200004, VECTOR = 22'h200008;

    logic [PRIO_BITS-1:0] prio [1:NSRC];
    logic [NSRC:1]        pending, enable, busy;
    logic [PRIO_BITS-1:0] threshold;

    //#1 Выбор источника: наибольший приоритет, при равенстве - меньший номер
    logic [4:0]           best_id;
    logic [PRIO_BITS-1:0] best_prio;
    always_comb begin
        best_id   = 5'd0;
        best_prio = threshold;
        for (int i = NSRC; i >= 1; i--)
            if (pending[i] && enable[i] && prio[i] >= best_prio && prio[i] > threshold) begin
                best_id   = i[4:0];
                best_prio = prio[i];
            end
    end
    //Ч11: запрос на ядро - через регистр. Поиск лучшего источника (цепочка сравнений приоритетов) иначе
    //шёл прямо в решение о ловушке ядра. Прерывание приходит на такт позже - для периферии это неважно
    always_ff @(posedge clk)
        if (rst) begin irq <= 1'b0; irq_id <= 5'd0; end
        else     begin irq <= (best_id != 5'd0); irq_id <= best_id; end

    //#2 Регистры
    logic we, claim_rd, complete_wr;
    assign we          = |Write;
    assign claim_rd    = Read && (Addr[21:0] == CLAIM);
    assign complete_wr = we   && (Addr[21:0] == CLAIM);

    always_ff @(posedge clk)
        if (rst) begin
            pending   <= '0;
            busy      <= '0;
            enable    <= '0;
            threshold <= '0;
            vec_en    <= 1'b0;
            for (int i = 1; i <= NSRC; i++) prio[i] <= '0;
        end else begin
            //Шлюзы: запрос принимается, пока источник не захвачен (claim)
            pending <= pending | (src & ~busy);
            if (claim_rd && best_id != 5'd0) begin
                pending[best_id] <= 1'b0;
                busy[best_id]    <= 1'b1;
            end
            if (vec_claim && vec_claim_id >= 5'd1 && vec_claim_id <= NSRC) begin
                pending[vec_claim_id] <= 1'b0;
                busy[vec_claim_id]    <= 1'b1;
            end
            if (complete_wr && WData[4:0] >= 5'd1 && WData[4:0] <= NSRC)
                busy[WData[4:0]] <= 1'b0;
            if (we) begin
                if (Addr[21:12] == 10'd0 && Addr[11:2] >= 1 && Addr[11:2] <= NSRC)
                    prio[Addr[11:2]] <= WData[PRIO_BITS-1:0];
                if (Addr[21:0] == ENABLE)    enable    <= WData[NSRC:1];
                if (Addr[21:0] == THRESHOLD) threshold <= WData[PRIO_BITS-1:0];
                if (Addr[21:0] == VECTOR)    vec_en    <= WData[0];
            end
        end

    //#3 Чтение
    logic [31:0] rdata;
    always_comb begin
        rdata = 32'd0;
        if (Addr[21:12] == 10'd0 && Addr[11:2] >= 1 && Addr[11:2] <= NSRC)
                                           rdata = {{(32-PRIO_BITS){1'b0}}, prio[Addr[11:2]]};
        else if (Addr[21:0] == PENDING)   rdata[NSRC:1] = pending;
        else if (Addr[21:0] == ENABLE)    rdata[NSRC:1] = enable;
        else if (Addr[21:0] == THRESHOLD) rdata = {{(32-PRIO_BITS){1'b0}}, threshold};
        else if (Addr[21:0] == CLAIM)     rdata = {27'd0, best_id};
        else if (Addr[21:0] == VECTOR)    rdata = {31'd0, vec_en};
    end

    generate if (MEMORY_TYPE) begin   //#1 - Память BSRAM: чтение с задержкой на такт
        always_ff @(posedge clk) RData <= rdata;
    end else begin                    //#0 - Синтезированная память
        assign RData = rdata;
    end
    endgenerate
endmodule
