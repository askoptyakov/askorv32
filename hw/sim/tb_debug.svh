//==============================================================================================
// tb_debug.svh - JTAG-хост и сценарий отладки для tb_core (включается +dbgtest)
//==============================================================================================
//DESCRIPTION: Тестбенч выполняет те же операции, что OpenOCD и GDB, через выводы JTAG ПЛИС:
//IDCODE, dtmcs, активация DM, сброс с остановом (ndmreset + haltreq), останов работающей
//программы, чтение PC (dpc) и dcsr, чтение/запись регистров абстрактными командами, чтение/
//запись памяти через System Bus (DMEM и IMEM), программная точка останова (ebreak в IMEM,
//dcsr.ebreakm), шаг (dcsr.step), продолжение. Программа tests/priv/dbg.S в конце проверяет, что
//изменения отладчика (x12, память) до неё дошли, и завершается по TOHOST.
//Адреса меток программы передаёт run_tests.py: +dbg_bp=, +dbg_flag=, +dbg_tdata= (hex).

    localparam real TCK_HALF = 250.0;      //TCK = 2 МГц
    localparam logic [6:0] DM_DATA0 = 7'h04, DM_DMCONTROL = 7'h10, DM_DMSTATUS = 7'h11,
                           DM_ABSTRACTCS = 7'h16, DM_COMMAND = 7'h17, DM_SBCS = 7'h38,
                           DM_SBADDRESS0 = 7'h39, DM_SBDATA0 = 7'h3C, DM_HALTSUM0 = 7'h40;

    //Один такт TCK: TMS/TDI выставляются при низком TCK, TDO читается перед фронтом
    task automatic jtag_clk(input logic t, input logic d, output logic o);
        tms = t; tdi = d;
        #(TCK_HALF);
        o = tdo;
        tck = 1'b1;
        #(TCK_HALF);
        tck = 1'b0;
    endtask

    task automatic jtag_idle(input int n);
        logic o;
        repeat (n) jtag_clk(1'b0, 1'b0, o);
    endtask

    task automatic jtag_reset();
        logic o;
        repeat (6) jtag_clk(1'b1, 1'b0, o);
        jtag_clk(1'b0, 1'b0, o);                        //Run-Test/Idle
    endtask

    task automatic jtag_ir(input logic [7:0] v);
        logic o;
        jtag_clk(1, 0, o); jtag_clk(1, 0, o); jtag_clk(0, 0, o); jtag_clk(0, 0, o);  //-> Shift-IR
        for (int i = 0; i < 8; i++) jtag_clk(i == 7, v[i], o);
        jtag_clk(1, 0, o); jtag_clk(0, 0, o);           //Update-IR -> Run-Test/Idle
    endtask

    task automatic jtag_dr(input int n, input logic [63:0] din, output logic [63:0] dout);
        logic o;
        dout = '0;
        jtag_clk(1, 0, o); jtag_clk(0, 0, o); jtag_clk(0, 0, o);                    //-> Shift-DR
        for (int i = 0; i < n; i++) begin jtag_clk(i == n - 1, din[i], o); dout[i] = o; end
        jtag_clk(1, 0, o); jtag_clk(0, 0, o);           //Update-DR -> Run-Test/Idle
        jtag_idle(4);
    endtask

    //Проверка шага сценария
    int dbg_step = 0;
    task automatic dbg_check(input logic ok, input string what, input logic [31:0] got, input logic [31:0] exp);
        dbg_step++;
        if (!ok) begin
            $display("RESULT FAIL %0s %0s test=%0d name=dbg:%0s got=0x%08h expected=0x%08h cycles=%0d",
                     prog, core_name, dbg_step, what, got, exp, cycles);
            $finish;
        end
    endtask

    //Операция DMI: повтор при busy (op = 3) со сбросом dtmcs.dmireset, как делает OpenOCD
    task automatic dmi(input logic [1:0] op, input logic [6:0] addr, input logic [31:0] data, output logic [31:0] rdata);
        logic [63:0] r;
        for (int attempt = 0; attempt < 20; attempt++) begin
            jtag_dr(41, {23'd0, addr, data, op}, r);
            jtag_dr(41, 64'd0, r);                      //nop: результат операции
            if (r[1:0] == 2'd0) begin rdata = r[33:2]; return; end
            jtag_ir(8'h42); jtag_dr(32, 64'h1_0000, r); jtag_ir(8'h43);   //dmireset
            jtag_idle(8 * (attempt + 1));
        end
        dbg_check(1'b0, "dmi-busy", r[31:0], 0);
    endtask

    task automatic dmi_wr(input logic [6:0] addr, input logic [31:0] data);
        logic [31:0] r;
        dmi(2'd2, addr, data, r);
    endtask

    task automatic dmi_rd(input logic [6:0] addr, output logic [31:0] data);
        dmi(2'd1, addr, 32'd0, data);
    endtask

    task automatic wait_halted(input string what);
        logic [31:0] st;
        for (int i = 0; i < 50; i++) begin
            dmi_rd(DM_DMSTATUS, st);
            if (st[9]) return;
        end
        dbg_check(1'b0, what, st, 32'h200);
    endtask

    //Абстрактная команда Access Register, 32 бит
    task automatic reg_rd(input logic [15:0] regno, output logic [31:0] v);
        logic [31:0] cs;
        dmi_wr(DM_COMMAND, {8'd0, 1'b0, 3'd2, 1'b0, 1'b0, 1'b1, 1'b0, regno});
        dmi_rd(DM_ABSTRACTCS, cs);
        dbg_check(cs[10:8] == 3'd0, $sformatf("reg_rd[0x%04h]:cmderr", regno), cs[10:8], 0);
        dmi_rd(DM_DATA0, v);
    endtask

    task automatic reg_wr(input logic [15:0] regno, input logic [31:0] v);
        logic [31:0] cs;
        dmi_wr(DM_DATA0, v);
        dmi_wr(DM_COMMAND, {8'd0, 1'b0, 3'd2, 1'b0, 1'b0, 1'b1, 1'b1, regno});
        dmi_rd(DM_ABSTRACTCS, cs);
        dbg_check(cs[10:8] == 3'd0, $sformatf("reg_wr[0x%04h]:cmderr", regno), cs[10:8], 0);
    endtask

    //System Bus Access
    task automatic mem_wr(input logic [31:0] addr, input logic [31:0] v, input logic [2:0] size);
        logic [31:0] cs;
        dmi_wr(DM_SBCS, {12'd0, size, 17'd0} | 32'h0000_7000);  //sbaccess, сброс sberror
        dmi_wr(DM_SBADDRESS0, addr);
        dmi_wr(DM_SBDATA0, v);
        dmi_rd(DM_SBCS, cs);
        dbg_check(cs[14:12] == 3'd0, $sformatf("mem_wr[0x%08h]:sberror", addr), cs[14:12], 0);
    endtask

    task automatic mem_rd(input logic [31:0] addr, input logic [2:0] size, output logic [31:0] v);
        logic [31:0] cs;
        dmi_wr(DM_SBCS, {11'd0, 1'b1 /*sbreadonaddr*/, size, 17'd0} | 32'h0000_7000);
        dmi_wr(DM_SBADDRESS0, addr);
        dmi_rd(DM_SBDATA0, v);
        dmi_rd(DM_SBCS, cs);
        dbg_check(cs[14:12] == 3'd0, $sformatf("mem_rd[0x%08h]:sberror", addr), cs[14:12], 0);
    endtask

    logic [2:0] ack_hold;                   //Удерживаемый ответ DM (проверка busy, Р4)

    task automatic dbg_scenario();
        logic [63:0] r;
        logic [31:0] v, st, pc, orig, bp, flag_addr, tdata_addr;
        if (!$value$plusargs("dbg_bp=%h", bp))            bp = 0;
        if (!$value$plusargs("dbg_flag=%h", flag_addr))   flag_addr = 0;
        if (!$value$plusargs("dbg_tdata=%h", tdata_addr)) tdata_addr = 0;

        //#1 JTAG: IDCODE, dtmcs
        jtag_reset();
        jtag_dr(32, 64'd0, r);
        dbg_check(r[31:0] == 32'h1100481B, "idcode", r[31:0], 32'h1100481B);
        jtag_ir(8'h42);
        jtag_dr(32, 64'd0, r);
        dbg_check(r[3:0] == 4'd1 && r[9:4] == 6'd7, "dtmcs[version=1,abits=7]", r[31:0], 32'h00001071);
        jtag_ir(8'h43);

        //#2 Активация DM, состояние
        dmi_wr(DM_DMCONTROL, 32'h0000_0001);
        dmi_rd(DM_DMSTATUS, st);
        dbg_check(st[3:0] == 4'd2 && st[7], "dmstatus[version=2,authenticated]", st, 32'h82);
        dbg_check(st[11] && !st[9], "dmstatus[running]", st, 32'h800);
        //Р4: занятость DMI и сброс dtmcs.dmireset через общий сдвиговый регистр DTM. Ответ DM удерживается
        //(force): скан возвращает op = 3 (busy), dmistat залипает и держится и после ответа - до dmireset
        ack_hold = dut.g_debug.dtm.ack_s;
        force dut.g_debug.dtm.ack_s = ack_hold;
        jtag_dr(41, {23'd0, DM_DMSTATUS, 32'd0, 2'd1}, r);
        jtag_dr(41, 64'd0, r);
        dbg_check(r[1:0] == 2'd3, "dmi-busy[op=3]", r[1:0], 3);
        release dut.g_debug.dtm.ack_s;
        jtag_idle(16);
        jtag_dr(41, 64'd0, r);
        dbg_check(r[1:0] == 2'd3, "dmistat[sticky]", r[1:0], 3);
        jtag_ir(8'h42); jtag_dr(32, 64'd0, r);
        dbg_check(r[11:10] == 2'd3, "dtmcs.dmistat=3", r[11:10], 3);
        jtag_dr(32, 64'h1_0000, r); jtag_ir(8'h43);                     //dmireset
        jtag_dr(41, {23'd0, DM_DMSTATUS, 32'd0, 2'd1}, r);
        jtag_dr(41, 64'd0, r);
        dbg_check(r[1:0] == 2'd0 && r[33:2] == st && r[40:34] == DM_DMSTATUS, "dmireset[read-dmstatus]", r[33:2], st);
        dmi_wr(DM_COMMAND, {8'd0, 1'b0, 3'd2, 1'b0, 1'b0, 1'b1, 1'b0, 16'h1000});
        dmi_rd(DM_ABSTRACTCS, v);
        dbg_check(v[10:8] == 3'd4, "command-while-running:cmderr=4", v[10:8], 4);
        dmi_wr(DM_ABSTRACTCS, 32'h0000_0700);
        dmi_rd(DM_ABSTRACTCS, v);
        dbg_check(v[10:8] == 3'd0 && v[3:0] == 4'd1 && v[28:24] == 5'd0, "abstractcs[cmderr-cleared,datacount=1,progbufsize=0]", v, 32'h1);

        //#3 Сброс с остановом: ядро останавливается на первой инструкции (PC = 0)
        dmi_wr(DM_DMCONTROL, 32'h8000_0003);            //haltreq | ndmreset | dmactive
        dmi_wr(DM_DMCONTROL, 32'h8000_0001);            //ndmreset = 0, haltreq держится
        wait_halted("reset-halt");
        dmi_rd(DM_DMSTATUS, st);
        dbg_check(st[19], "dmstatus[havereset]", st, 32'h80000);
        dmi_wr(DM_DMCONTROL, 32'h1000_0001);            //ackhavereset, haltreq = 0
        reg_rd(16'h07B1, pc);
        dbg_check(pc == 32'd0, "reset-halt:dpc=0", pc, 0);
        reg_rd(16'h07B0, v);
        dbg_check(v[31:28] == 4'd4 && v[8:6] == 3'd3 && v[1:0] == 2'b11, "dcsr[xdebugver=4,cause=haltreq,prv=M]", v, 32'h400000c3);
        dmi_wr(DM_DMCONTROL, 32'h4000_0001);            //resumereq
        dmi_rd(DM_DMSTATUS, st);
        dbg_check(st[17] && st[11], "resume:allresumeack,running", st, 32'h20800);

        //#4 Останов работающей программы, регистры
        jtag_idle(200);
        dmi_wr(DM_DMCONTROL, 32'h8000_0001);
        wait_halted("halt");
        dmi_wr(DM_DMCONTROL, 32'h0000_0001);
        dmi_rd(DM_HALTSUM0, v);
        dbg_check(v[0], "haltsum0", v, 1);
        reg_rd(16'h07B1, pc);
        dbg_check(pc >= bp - 32'd8 && pc <= bp + 32'd8, "halt:dpc-in-loop", pc, bp);   //цикл: bp-4..bp+8
        reg_rd(16'h100A, v);                            //x10 - счётчик цикла программы
        dbg_check(v != 32'd0, "gpr-read:x10-counting", v, 1);
        reg_wr(16'h100C, 32'h0000_1234);                //x12 - проверяет программа
        reg_rd(16'h100C, v);
        dbg_check(v == 32'h0000_1234, "gpr-write-read:x12", v, 32'h1234);
        reg_rd(16'h1000, v);
        dbg_check(v == 32'd0, "gpr-read:x0=0", v, 0);
        reg_rd(16'h0301, v);
        dbg_check(v == 32'h4000_1100, "csr-read:misa", v, 32'h40001100);
        dmi_wr(DM_COMMAND, {8'd0, 1'b0, 3'd2, 1'b0, 1'b0, 1'b1, 1'b0, 16'h1020});   //f0 - нет
        dmi_rd(DM_ABSTRACTCS, v);
        dbg_check(v[10:8] == 3'd3, "reg-nonexistent:cmderr=3", v[10:8], 3);
        dmi_wr(DM_ABSTRACTCS, 32'h0000_0700);

        //#5 Память через System Bus: DMEM (32/8 бит), IMEM
        mem_wr(tdata_addr, 32'hCAFE_BABE, 3'd2);
        mem_rd(tdata_addr, 3'd2, v);
        dbg_check(v == 32'hCAFE_BABE, "sba-dmem-word", v, 32'hCAFEBABE);
        mem_wr(tdata_addr + 1, 32'h0000_0011, 3'd0);
        mem_rd(tdata_addr, 3'd2, v);
        dbg_check(v == 32'hCAFE_11BE, "sba-dmem-byte-write", v, 32'hCAFE11BE);
        mem_rd(tdata_addr + 3, 3'd0, v);
        dbg_check(v == 32'h0000_00CA, "sba-dmem-byte-read", v, 32'hCA);
        mem_wr(tdata_addr, 32'hCAFE_BABE, 3'd2);
        mem_rd(bp, 3'd2, orig);
        dbg_check(orig == imem_img[bp[31:2]], "sba-imem-read", orig, imem_img[bp[31:2]]);

        //#6 Программная точка останова: ebreak в IMEM, dcsr.ebreakm = 1
        mem_wr(bp, 32'h0010_0073, 3'd2);
        mem_rd(bp, 3'd2, v);
        dbg_check(v == 32'h0010_0073, "sba-imem-write-ebreak", v, 32'h00100073);
        reg_wr(16'h07B0, 32'h0000_8000);
        dmi_wr(DM_DMCONTROL, 32'h4000_0001);
        wait_halted("breakpoint-hit");
        reg_rd(16'h07B1, pc);
        dbg_check(pc == bp, "breakpoint:dpc=bp", pc, bp);
        reg_rd(16'h07B0, v);
        dbg_check(v[8:6] == 3'd1, "breakpoint:dcsr.cause=ebreak", v[8:6], 1);
        mem_wr(bp, orig, 3'd2);                         //Вернуть исходную инструкцию

        //#7 Шаг: одна инструкция
        reg_wr(16'h07B0, 32'h0000_8004);                //ebreakm | step
        dmi_wr(DM_DMCONTROL, 32'h4000_0001);
        wait_halted("step");
        reg_rd(16'h07B1, pc);
        dbg_check(pc == bp + 4, "step:dpc=bp+4", pc, bp + 4);
        reg_rd(16'h07B0, v);
        dbg_check(v[8:6] == 3'd4, "step:dcsr.cause=step", v[8:6], 4);
        reg_wr(16'h07B0, 32'h0000_0000);

        //#8 Разрешить программе завершиться: флаг в памяти, продолжение
        mem_wr(flag_addr, 32'd1, 3'd2);
        dmi_wr(DM_DMCONTROL, 32'h4000_0001);
        //Дальше программа проверяет x12 и память и пишет TOHOST
    endtask
