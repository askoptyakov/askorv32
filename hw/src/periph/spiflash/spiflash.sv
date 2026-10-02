//==============================================================================================
// spiflash_top - контроллер внешней флеш-памяти SPI с загрузчиком программы
//==============================================================================================
//DESCRIPTION: Две задачи:
//  1. Загрузчик. После сброса системы (кнопка, PLL, ndmreset отладчика) держит ядро в сбросе
//     (boot_hold), читает из флеш образ программы с адреса BOOT_ADDR и копирует его в IMEM/DMEM
//     через порт ведущего boot_* процессора (cpu.sv). Образ читается дважды: сначала проверка
//     (признак, разметка, контрольная сумма) без записи, затем копирование. Если образа нет или
//     он испорчен, память не трогается и ядро стартует с тем, что в ней было (программа из
//     битового потока ПЛИС). Итог - в регистре BOOT.
//  2. Обмен с флеш по командам программы: кадр SPI режима 0 (CS, байты старшим битом вперёд),
//     1, 2 или 4 байта за одну запись регистра DATA. Из этого собираются любые команды флеш
//     (чтение, запись страницы, стирание, ID, состояние) - библиотека fw/Core/Inc/spiflash.h.
//     Образ программы и битовый поток во флеш записывает openFPGALoader (sw/fpgaload/fpgaload.py spiflash).
//Описание, формат образа и примеры - README.md в этой папке, тест - tb_spiflash.sv.
//Образец - PicoSoC (spimemio.v, YosysHQ/picorv32): пробуждение флеш при старте (0xFF, 0xAB),
//слово из 4 байт младшим байтом вперёд. В отличие от PicoSoC код не исполняется из флеш (XIP):
//у IMEM нет ожидания, поэтому программа копируется в BSRAM до старта ядра.
//
//Карта регистров (регистровая часть - по шаблону periph_regs):
//<>0x00 CTRL - [0] cs - удерживать CS (кадр из нескольких обменов); [1] rdauto - чтение DATA
//              запускает следующий обмен 4 байтами (на MOSI - что угодно, флеш их не смотрит)
//<>0x04 STAT - [0] busy - идёт обмен или пауза CS (только чтение); [1] ovr - запуск обмена при
//              busy = 1, обмен не выполнен (сброс записью 1)
//<>0x08 DIV  - [7:0] делитель: SCK = f_clk / (2 * (DIV + 1))
//<>0x0C DATA - запись байта (sb), полуслова (sh) или слова (sw) по адресу DATA - обмен 1, 2 или 4
//              байтами, младший байт первым; чтение - принятые байты на тех же местах (байт,
//              принятый при передаче байта k, - в байте k; остальные - 0)
//<<0x10 BOOT - [2:0] итог загрузки: 0 - загрузчик выключен, 1 - программа загружена, 2 - образа нет,
//              3 - ошибка контрольной суммы, 4 - ошибка разметки; [31:16] - размер образа, слов
//<>0x100..0x1FC - окно DATA (64 слова = страница флеш): копирование блоком (memcpy, System Bus
//              отладчика) идёт через тот же регистр DATA
//Если CTRL.cs = 0, каждый обмен - отдельный кадр: CS опускается на время обмена. После подъёма CS
//держится пауза (3 такта, busy = 1) - время tSHSL флеш.
module spiflash_top
  #(parameter bit          MEMORY_TYPE = 0,
    parameter int          DIV_INIT    = 1,          //DIV после сброса: SCK = f_clk / (2 * (DIV + 1))
    parameter bit          BOOT_EN     = 1,          //1 - загрузка программы после сброса
    parameter logic [23:0] BOOT_ADDR   = 24'h00_0000,//Адрес образа во флеш
    parameter int          BOOT_WORDS  = 16384,      //Предел образа, слов (64 кБайт)
    parameter int          WAKE_CLKS   = 2048)       //Пауза после 0xAB (tRES1 флеш), тактов
   (input  logic        clk, rst,
    // Интерфейс обмена
    input  logic [ 3:0] Write,
    input  logic        Read,
    input  logic [31:0] Addr, WData,
    output logic [31:0] RData,
    // Линии SPI (режим 0)
    output logic        spi_sck,
    output logic        spi_cs_n,
    output logic        spi_mosi,
    input  logic        spi_miso,
    // Загрузчик: ведущий шин памяти процессора, пока ядро в сбросе
    output logic        boot_hold,                   //1 - держать ядро в сбросе
    output logic [ 3:0] boot_Write,
    output logic [31:0] boot_Addr, boot_WData
);
    localparam logic [31:0] MAGIC = 32'h3156_5241;   //Байты "ARV1"

    //#1 Регистры
    logic [4:0][3:0] we;
    logic [4:0]      re;
    logic     [31:0] wdata;

    logic        ctrl_cs, ctrl_rdauto, ovr;
    logic [ 7:0] div;
    logic [31:0] racc;                               //Принятые байты (DATA для чтения)
    logic [ 2:0] boot_st;
    logic [15:0] total;                              //Слов образа прочитано
    logic        busy;                               //Обмен идёт или пауза CS

    //Окно 0x100..0x1FF - тот же регистр DATA
    periph_regs #(.N(5), .MEMORY_TYPE(MEMORY_TYPE)) regs
        (.clk(clk), .Write(Write), .Read(Read), .Addr(Addr[8] ? 32'h0000_000C : Addr), .WData(WData), .RData(RData),
         .we(we), .re(re), .wdata(wdata),
         .rdata({{total, 13'd0, boot_st},                //0x10 BOOT
                 racc,                                   //0x0C DATA
                 32'(div),                               //0x08 DIV
                 {30'd0, ovr, busy},                     //0x04 STAT
                 {30'd0, ctrl_rdauto, ctrl_cs}}));       //0x00 CTRL

    always_ff @(posedge clk)
        if (rst) begin ctrl_cs <= 1'b0; ctrl_rdauto <= 1'b0; end
        else if (we[0][0]) begin ctrl_cs <= wdata[0]; ctrl_rdauto <= wdata[1]; end
    periph_reg #(.W(8), .INIT(8'(DIV_INIT))) r_div (.clk(clk), .rst(rst), .we(we[2]), .wdata(wdata), .q(div));

    //#2 Обмен: запуск, сдвиг, приём
    //Запуск: запись DATA (sb/sh/sw - 1/2/4 байта) или чтение DATA в режиме rdauto; во время загрузки - автомат.
    //Байты всегда с младшего: стробы задают только их число (сдвигателей по позиции байта нет)
    logic        st_req, st_boot;                    //Запрос запуска от программы / от загрузчика
    logic [31:0] boot_tx;
    logic [ 2:0] boot_nb;
    logic        avail;                              //Можно запускать
    logic        load;                               //Приём запуска: байты - в tx, обмен - со следующего такта
    logic        pend;                               //Обмен принят, сдвиг начинается в этом такте
    logic [31:0] load_data;
    logic [ 2:0] load_nb;
    assign st_req = (|we[3]) | (re[3] & ctrl_rdauto);

    logic        sh_busy;                            //Идёт обмен
    logic        high;                               //Фаза SCK = 1
    logic [ 7:0] cnt;                                //Счёт тактов фазы
    logic [31:0] tx;                                 //Байты на передачу: текущий - tx[7:0]
    logic [ 7:0] cur;                                //Текущий байт, cur[7] - на MOSI
    logic [ 2:0] bitn;                               //Осталось бит в байте - 1
    logic [ 2:0] left;                               //Осталось байт, считая текущий
    logic        smp, smp_last;                      //Отсчёт MISO (такт после спада SCK) и он же последний
    logic [ 7:0] rb;                                 //Принимаемый байт
    logic [ 2:0] rbit;                               //Принято бит текущего байта
    logic [ 1:0] rbyte;                              //Номер принимаемого байта
    logic        miso_q;
    logic        fin;                                //Обмен завершён (один такт)
    logic [ 1:0] guard;                              //Пауза CS после кадра
    logic        cs_act, cs_act_q, boot_cs;

    always_ff @(posedge clk) miso_q <= spi_miso;

    //Новый обмен можно начать: сдвиг закончен; кадр продолжается (CS удерживается) или CS поднят и пауза
    //выдержана. Такт между концом кадра и подъёмом CS (cs_act_q = 1 без удержания) - тоже занят:
    //иначе обмен, запущенный в этом такте, слился бы с предыдущим кадром
    //Запуск принимается в tx регистром, а сдвиг начинается тактом позже (pend): путь от шины (адрес и данные
    //записи из стадии M ядра) заканчивается на регистрах tx и не идёт в выходы SPI
    assign avail = ~pend & ~sh_busy & (guard == 2'd0) & ~(cs_act_q & ~ctrl_cs & ~boot_cs);
    assign busy  = ~avail;
    assign load      = st_boot | (st_req & avail & ~boot_hold);
    assign load_data = st_boot ? boot_tx : wdata;      //rdauto: на MOSI - что угодно (флеш их не смотрит)
    assign load_nb   = st_boot ? boot_nb : (~|we[3] | we[3][3]) ? 3'd4 : we[3][1] ? 3'd2 : 3'd1;

    always_ff @(posedge clk)
        if (rst) begin
            sh_busy <= 1'b0; high <= 1'b0; cnt <= '0; spi_sck <= 1'b0; spi_mosi <= 1'b0;
            smp <= 1'b0; smp_last <= 1'b0; fin <= 1'b0; racc <= '0; pend <= 1'b0;
        end else begin
            smp <= 1'b0; smp_last <= 1'b0; fin <= 1'b0;
            pend <= load;
            if (load) begin
                tx   <= load_data;
                left <= load_nb;
            end
            if (pend) begin
                //CS опускается в этом же такте (cs_act учитывает pend), первый фронт SCK - не раньше следующего
                sh_busy  <= 1'b1;
                high     <= 1'b0;
                cnt      <= div;
                cur      <= tx[7:0];
                spi_mosi <= tx[7];
                bitn     <= 3'd7;
                rbit     <= 3'd0;
                rbyte    <= 2'd0;
                racc     <= '0;
            end else if (sh_busy) begin
                if (cnt != '0) cnt <= cnt - 1'b1;
                else if (!high) begin                            //Конец фазы 0: фронт SCK
                    if (left != 3'd0) begin
                        spi_sck <= 1'b1;
                        high    <= 1'b1;
                        cnt     <= div;
                    end
                end else begin                                   //Конец фазы 1: спад SCK, отсчёт MISO
                    spi_sck <= 1'b0;
                    high    <= 1'b0;
                    cnt     <= div;
                    smp     <= 1'b1;
                    if (bitn != 3'd0) begin
                        bitn     <= bitn - 1'b1;
                        cur      <= {cur[6:0], 1'b0};
                        spi_mosi <= cur[6];
                    end else begin                               //Байт передан
                        bitn     <= 3'd7;
                        left     <= left - 1'b1;
                        tx       <= {8'hFF, tx[31:8]};
                        cur      <= tx[15:8];
                        spi_mosi <= tx[15];
                        if (left == 3'd1) smp_last <= 1'b1;
                    end
                end
            end
            //Приём: отсчёт MISO, снятый в такте спада SCK; байт - на своё место в racc
            if (smp) begin
                rb   <= {rb[6:0], miso_q};
                rbit <= rbit + 1'b1;
                if (rbit == 3'd7) begin
                    racc[{rbyte, 3'b000} +: 8] <= {rb[6:0], miso_q};
                    rbyte <= rbyte + 1'b1;
                end
                if (smp_last) begin
                    fin     <= 1'b1;
                    sh_busy <= 1'b0;
                end
            end
        end

    //Кадр CS: удержание программой или загрузчиком, иначе - на время обмена. После подъёма - пауза
    assign cs_act = ctrl_cs | boot_cs | sh_busy | pend;
    always_ff @(posedge clk)
        if (rst) begin spi_cs_n <= 1'b1; cs_act_q <= 1'b0; guard <= '0; end
        else begin
            spi_cs_n <= ~cs_act;
            cs_act_q <= cs_act;
            if (cs_act_q & ~cs_act) guard <= 2'd3;
            else if (guard != 2'd0) guard <= guard - 1'b1;
        end

    //Флаг пропущенного запуска
    always_ff @(posedge clk)
        if (rst)                              ovr <= 1'b0;
        else if (st_req & ~avail & ~boot_hold) ovr <= 1'b1;
        else if (we[1][0] & wdata[1])          ovr <= 1'b0;

    //#3 Загрузчик
    //Образ (слова младшим байтом вперёд): MAGIC, затем сегменты {адрес, число слов, слова...},
    //конец - сегмент с числом слов 0, за ним контрольное слово: сумма всех слов образа = 0.
    //Слово обмена берётся из racc на такт позже конца обмена (fin_q): так короче путь к состоянию.
    //Запись в память: адрес - счётчик seg_addr, данные - racc (до следующего обмена он не меняется)
    typedef enum logic [3:0] {B_FF, B_AB, B_WAKE, B_CMD, B_CMDW, B_RD, B_RDW, B_CHK, B_GAP, B_DONE} bstate_t;
    localparam int TW = $clog2(BOOT_WORDS + 6);     //Разрядность счётчика слов образа
    typedef enum logic [2:0] {P_MAGIC, P_ADDR, P_LEN, P_DATA, P_CHECK} pstate_t;
    bstate_t     bs;
    pstate_t     ps;
    logic        copy;                               //0 - проверка, 1 - копирование
    logic [31:0] sum;
    logic        seg_dmem;                           //Сегмент: 0 - IMEM (0x00xx_xxxx), 1 - DMEM (0x10xx_xxxx)
    logic [13:0] seg_off;                            //Адрес слова в памяти (смещение до 64 кБайт)
    logic        seg_bad;                            //Адрес сегмента недопустим
    logic [TW-1:0] seg_left, total_c;                //total_c - и таймер паузы после пробуждения флеш
    logic        fin_q;
    always_ff @(posedge clk) fin_q <= fin;

    assign boot_Addr  = {3'b000, seg_dmem, 12'h000, seg_off, 2'b00};
    assign boot_WData = racc;
    assign total      = 16'(total_c);

    //Адрес сегмента допустим: IMEM или DMEM, выровнен, в пределах 64 кБайт
    function automatic logic bad_addr(input logic [31:0] a);
        return (a[1:0] != 2'b00) || (a[23:16] != 8'h00) || !(a[31:24] == 8'h00 || a[31:24] == 8'h10);
    endfunction

    always_comb begin
        st_boot = 1'b0;
        boot_tx = 32'hFFFF_FFFF;
        boot_nb = 3'd4;
        case (bs)
            B_FF:  begin st_boot = avail; boot_tx = 32'h0000_00FF; boot_nb = 3'd1; end
            B_AB:  begin st_boot = avail; boot_tx = 32'h0000_00AB; boot_nb = 3'd1; end
            B_CMD: begin st_boot = avail; boot_tx = {BOOT_ADDR[7:0], BOOT_ADDR[15:8], BOOT_ADDR[23:16], 8'h03}; end
            B_RD:  st_boot = avail;
            default: ;
        endcase
    end

    //BOOT_EN = 0: автомат всегда в исходном состоянии - синтез убирает загрузчик целиком
    always_ff @(posedge clk)
        if (rst || !BOOT_EN) begin
            bs <= BOOT_EN ? B_FF : B_DONE;
            boot_hold <= BOOT_EN;
            boot_st <= 3'd0; boot_cs <= 1'b0; boot_Write <= 4'b0000;
            copy <= 1'b0; ps <= P_MAGIC; sum <= '0; total_c <= '0;
        end else begin
            boot_Write <= 4'b0000;
            if (|boot_Write) seg_off <= seg_off + 1'b1;               //Слово записано - следующий адрес
            case (bs)
                B_FF:   if (avail) bs <= B_AB;                        //Выход из непрерывного чтения (как PicoSoC)
                B_AB:   if (avail) begin bs <= B_WAKE; total_c <= TW'(WAKE_CLKS); end   //Выход из глубокого сна
                B_WAKE: if (!sh_busy) begin
                            if (total_c != '0) total_c <= total_c - 1'b1;
                            else bs <= B_CMD;
                        end
                B_CMD:  if (avail) begin
                            bs <= B_CMDW; boot_cs <= 1'b1;
                            ps <= P_MAGIC; sum <= '0; total_c <= '0;
                        end
                B_CMDW: if (fin) bs <= B_RD;
                B_RD:   if (avail) bs <= B_RDW;
                B_RDW:  if (fin_q) begin
                            sum     <= sum + racc;
                            total_c <= total_c + 1'b1;
                            bs      <= B_RD;
                            if (total_c == TW'(BOOT_WORDS + 4)) begin         //Разметка не сходится
                                boot_st <= 3'd4; bs <= B_DONE;
                            end else
                            case (ps)
                                P_MAGIC: if (racc == MAGIC) ps <= P_ADDR;
                                         else begin boot_st <= 3'd2; bs <= B_DONE; end
                                P_ADDR:  begin
                                             seg_bad <= bad_addr(racc); seg_dmem <= racc[28]; seg_off <= racc[15:2];
                                             ps <= P_LEN;
                                         end
                                P_LEN:   if (racc == '0) ps <= P_CHECK;
                                         else if (seg_bad || racc > 32'(BOOT_WORDS)) begin boot_st <= 3'd4; bs <= B_DONE; end
                                         else begin seg_left <= TW'(racc); ps <= P_DATA; end
                                P_DATA:  begin
                                             if (copy) boot_Write <= 4'b1111;
                                             seg_left <= seg_left - 1'b1;
                                             if (seg_left == TW'(1)) ps <= P_ADDR;
                                         end
                                P_CHECK: begin boot_cs <= 1'b0; bs <= B_CHK; end    //Контрольное слово прибавлено к sum
                                default: ;
                            endcase
                        end
                B_CHK:  if (sum != '0)  begin boot_st <= 3'd3; bs <= B_DONE; end
                        else if (!copy) begin copy <= 1'b1; bs <= B_GAP; end
                        else            begin boot_st <= 3'd1; bs <= B_DONE; end
                B_GAP:  if (avail) bs <= B_CMD;                       //CS поднят - новое чтение с начала
                B_DONE: begin boot_cs <= 1'b0; boot_hold <= 1'b0; end
                default: bs <= B_DONE;
            endcase
        end
endmodule
