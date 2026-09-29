// csr.S - тесты инструкций Zicsr и реализованных CSR машинного режима
#include "riscv_test.h"
#include "priv_test.h"

RVTEST_CODE_BEGIN
    //Любая ловушка в этом тесте - ошибка: mcause попадает в ACTUAL
    LA_ABS(x1, trap_catch); csrw mtvec, x1

    //csrrw / csrrs / csrrc
    TEST_CASE( 1, x14, 0x12345678, ("csrrw[write-read]"),      li x1, 0x12345678; csrw mscratch, x1; csrrw x14, mscratch, x0)
    TEST_CASE( 2, x14, 0x00000000, ("csrrw[new-value]"),       csrr x14, mscratch)
    TEST_CASE( 3, x14, 0x000000f0, ("csrrs[returns-old]"),     li x1, 0xf0; csrw mscratch, x1; li x2, 0x0f; csrrs x14, mscratch, x2)
    TEST_CASE( 4, x14, 0x000000ff, ("csrrs[sets-bits]"),       csrr x14, mscratch)
    TEST_CASE( 5, x14, 0x000000ff, ("csrrc[returns-old]"),     li x2, 0x0f; csrrc x14, mscratch, x2)
    TEST_CASE( 6, x14, 0x000000f0, ("csrrc[clears-bits]"),     csrr x14, mscratch)
    TEST_CASE( 7, x14, 0x000000f0, ("csrrwi[returns-old]"),    csrrwi x14, mscratch, 31)
    TEST_CASE( 8, x14, 0x0000001f, ("csrrwi[writes-zimm]"),    csrr x14, mscratch)
    TEST_CASE( 9, x14, 0x00000015, ("csrrsi"),                 csrw mscratch, x0; csrrsi x0, mscratch, 0x15; csrr x14, mscratch)
    TEST_CASE(10, x14, 0x00000010, ("csrrci"),                 csrrci x0, mscratch, 0x05; csrr x14, mscratch)
    TEST_CASE(11, x0,  0x00000000, ("csrrw[rd=x0]"),           li x1, 7; csrrw x0, mscratch, x1)

    //Байпас: результат CSR-инструкции сразу используется, операнд CSR только что вычислен/загружен
    TEST_CASE(12, x6, 0x00000101, ("csrr[fwd:rd->rs1,nop=0]"), li x1, 0x100; csrw mscratch, x1; nop; nop; nop; csrr x14, mscratch; addi x6, x14, 1)
    TEST_CASE(13, x6, 0x00000101, ("csrr[fwd:rd->rs1,nop=1]"), csrr x14, mscratch; nop; addi x6, x14, 1)
    TEST_CASE(14, x6, 0x00000101, ("csrr[fwd:rd->rs1,nop=2]"), csrr x14, mscratch; nop; nop; addi x6, x14, 1)
    TEST_CASE(15, x14, 0xcafe0001, ("csrw[load-use:rs1]"),     LA_ABS(x3, tdat); lw x1, 0(x3); csrw mscratch, x1; csrr x14, mscratch)

    //mcycle: +1 за такт ядра; csrrs с rs1 = x0 не пишет; запись и перенос в mcycleh
    TEST_CASE(16, x14, 4,          ("mcycle[+4-cycles]"),      csrr x1, mcycle; nop; nop; nop; csrr x14, mcycle; sub x14, x14, x1)
    TEST_CASE(17, x14, 100,        ("mcycle[write]"),          li x1, 100; csrw mcycle, x1; csrr x14, mcycle)
    TEST_CASE(18, x14, 1,          ("mcycleh[carry]"),         li x1, -2; csrw mcycle, x1; csrw mcycleh, x0; nop; nop; csrr x14, mcycleh)
    TEST_CASE(19, x14, 1,          ("cycle[alias]"),           csrr x1, mcycle; csrr x14, cycle; sub x14, x14, x1)

    //Регистры только для чтения и нереализованные CSR
    TEST_CASE(20, x14, 0x40001100, ("misa[RV32IM]"),           csrr x14, misa)
    TEST_CASE(21, x14, 0,          ("mhartid"),                csrr x14, mhartid)
    TEST_CASE(22, x14, 0,          ("mvendorid"),              csrr x14, mvendorid)
    TEST_CASE(23, x14, 0,          ("tdata1[type=0:no-triggers]"), csrr x14, tdata1)
    TEST_CASE(24, x14, 0,          ("tselect[not-implemented]"),   li x1, 5; csrw tselect, x1; csrr x14, tselect)
    TEST_CASE(25, x14, 0,          ("mip[read-only]"),         li x1, -1; csrw mip, x1; csrr x14, mip)

    //Реализованные поля
    TEST_CASE(26, x14, 0x00001888, ("mstatus[MIE,MPIE,MPP=11]"), li x1, -1; csrw mstatus, x1; csrr x14, mstatus)
    TEST_CASE(27, x14, 0x00001800, ("mstatus[clear]"),         csrw mstatus, x0; csrr x14, mstatus)
    TEST_CASE(28, x14, 0xffff0888, ("mie[fields]"),            li x1, -1; csrw mie, x1; csrr x14, mie)
    TEST_CASE(29, x14, 0,          ("mie[clear]"),             csrw mie, x0; csrr x14, mie)
    TEST_CASE(30, x14, 0x00000201, ("mtvec[mode-bit1=0]"),     li x1, 0x203; csrw mtvec, x1; csrr x14, mtvec)
    LA_ABS(x1, trap_catch); csrw mtvec, x1
    TEST_CASE(31, x14, 0x00001000, ("mepc[bits1:0=0]"),        li x1, 0x1003; csrw mepc, x1; csrr x14, mepc)
    TEST_CASE(32, x14, 0x8000001f, ("mcause[int+code]"),       li x1, 0x8000001f; csrw mcause, x1; csrr x14, mcause)
    TEST_CASE(33, x14, 0x0000001f, ("mcause[code-5bit]"),      li x1, 0x7fffffff; csrw mcause, x1; csrr x14, mcause)
    TEST_CASE(34, x14, 0x87654321, ("mtval"),                  li x1, 0x87654321; csrw mtval, x1; csrr x14, mtval)
    TEST_CASE(35, x14, 0,          ("wfi[nop]"),               li x14, 0; wfi; nop)
    TEST_CASE(36, x14, 0,          ("fence[nop]"),             li x14, 0; fence)

    csrw mtvec, x0
    j pass

    .balign 4
trap_catch:
    csrr ACTUAL, mcause
    li EXPECTED, -1
    j fail
RVTEST_CODE_END

RVTEST_DATA_BEGIN
tdat: .word 0xcafe0001
