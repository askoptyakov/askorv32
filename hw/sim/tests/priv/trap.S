// trap.S - тесты синхронных исключений, mret и точности ловушек (mtvec в прямом режиме)
//
// Обработчик trap_handler запоминает mcause (x20), mepc (x21), mtval (x22), mstatus (x24),
// считает ловушки (x23) и возвращается на инструкцию после вызвавшей исключение.
#include "riscv_test.h"
#include "priv_test.h"

//Ловушка на инструкции inst: проверяются mcause (тест n1), mepc = адрес inst (n2), число ловушек (n3).
//setup и inst передаются в скобках, т.к. содержат запятые
#define EXPAND(...) __VA_ARGS__
#define TEST_EXC(n1, n2, n3, cause, name, setup, inst)     TEST_CASE(n1, x20, cause, name, li x23, 0; li x20, -1; EXPAND setup; exc_##n1: EXPAND inst)     TEST_CASE(n2, x21, 0, ("mepc"), LA_ABS(x1, exc_##n1); sub x21, x21, x1)     TEST_CASE(n3, x23, 1, ("count"), nop)

RVTEST_CODE_BEGIN
    LA_ABS(x1, trap_handler); csrw mtvec, x1

    //Исключения и их коды
    TEST_EXC( 1,  2,  3, 11, ("ecall"), (nop), (ecall))
    TEST_EXC( 4,  5,  6,  3, ("ebreak"), (nop), (ebreak))
    TEST_EXC( 7,  8,  9,  2, ("illegal[0x00000000]"), (nop), (.word 0x00000000))
    TEST_EXC(10, 11, 12,  2, ("illegal[0xffffffff]"), (nop), (.word 0xffffffff))
    TEST_EXC(13, 14, 15,  2, ("illegal[custom-0]"), (nop), (.word 0x0000000b))
    TEST_EXC(16, 17, 18,  2, ("illegal[system-f3=100]"), (nop), (.word 0x00004073))
    TEST_EXC(19, 20, 21,  2, ("illegal[dret]"), (nop), (.word 0x7b200073))
    TEST_EXC(22, 23, 24,  4, ("lw[misaligned+1]"), (LA_ABS(x1, tdat); li x7, 0x55), (lw x7, 1(x1)))
    TEST_EXC(25, 26, 27,  4, ("lw[misaligned+2]"), (LA_ABS(x1, tdat)), (lw x7, 2(x1)))
    TEST_EXC(28, 29, 30,  4, ("lh[misaligned+1]"), (LA_ABS(x1, tdat)), (lh x7, 1(x1)))
    TEST_EXC(31, 32, 33,  4, ("lhu[misaligned+3]"), (LA_ABS(x1, tdat)), (lhu x7, 3(x1)))
    TEST_EXC(34, 35, 36,  6, ("sw[misaligned+2]"), (LA_ABS(x1, tdat)), (sw x0, 2(x1)))
    TEST_EXC(37, 38, 39,  6, ("sh[misaligned+1]"), (LA_ABS(x1, tdat)), (sh x0, 1(x1)))
    TEST_EXC(40, 41, 42,  0, ("jalr[target+2]"), (LA_ABS(x1, jtgt + 2)), (jalr x0, 0(x1)))
    TEST_EXC(43, 44, 45,  0, ("beq[target+6]"), (nop), (beq x0, x0, .+6))
    TEST_EXC(46, 47, 48,  0, ("jal[target+6]"), (nop), (jal x0, .+6))

    //mtval: адрес невыровненного обращения и перехода, 0 для остальных
    TEST_CASE(49, x22, 0, ("mtval[ecall=0]"),   ecall)
    TEST_CASE(50, x22, 0, ("mtval[lw-addr]"),   LA_ABS(x1, tdat); lw x7, 5(x1); LA_ABS(x3, tdat + 5); sub x22, x22, x3)
    TEST_CASE(51, x22, 0, ("mtval[jalr-target]"), LA_ABS(x1, jtgt + 2); jalr x0, 0(x1); LA_ABS(x3, jtgt + 2); sub x22, x22, x3)

    //Выровненные обращения не вызывают исключений
    TEST_CASE(52, x23, 0, ("lh/lb/sb[aligned:no-trap]"), li x23, 0; LA_ABS(x1, tdat); lh x7, 2(x1); lb x7, 3(x1); lbu x7, 1(x1); sb x0, 3(x1); sh x0, 0(x1))

    //Гашение: инструкция с исключением не пишет в регистр и в память
    TEST_CASE(53, x7, 0x55, ("squash[lw-rd-unchanged]"), LA_ABS(x1, tdat); li x7, 0x55; lw x7, 1(x1))
    TEST_CASE(54, x7, 0x11223344, ("squash[sw-mem-unchanged]"), LA_ABS(x1, tdat2); li x2, -1; sw x2, 2(x1); lw x7, 0(x1))
    //Инструкции после ecall выполняются ровно один раз (после возврата)
    TEST_CASE(55, x7, 1, ("ecall[next-executes-once]"), li x7, 0; ecall; addi x7, x7, 1)
    //Приостановка load-use и ловушка на зависимой загрузке
    TEST_CASE(56, x20, 4, ("lw[load-use+misaligned]"), li x20, -1; LA_ABS(x3, tptr); lw x1, 0(x3); lw x7, 1(x1))
    //Ловушка на инструкции сразу после выполненного перехода
    TEST_CASE(57, x20, 11, ("ecall[after-taken-branch]"), li x20, -1; beq x0, x0, 1f; nop; 1: ecall)

    //mstatus при ловушке: MPIE = MIE, MIE = 0; mret возвращает MIE = MPIE
    TEST_CASE(58, x24, 0x1880, ("mstatus[trap:MPIE=1,MIE=0]"), csrsi mstatus, 8; ecall)
    TEST_CASE(59, x14, 0x1888, ("mstatus[mret:MIE=MPIE]"), csrr x14, mstatus)
    TEST_CASE(60, x24, 0x1800, ("mstatus[trap:MPIE=0]"), csrci mstatus, 8; ecall)

    //mret без ловушки: переход на mepc, MIE = MPIE, MPIE = 1
    TEST_CASE(61, x7, 1, ("mret[jump-to-mepc]"), li x7, 0; LA_ABS(x1, 2f); csrw mepc, x1; li x1, 0x80; csrs mstatus, x1; mret; li x7, 99; 2: addi x7, x7, 1)
    TEST_CASE(62, x14, 0x1888, ("mret[MIE=MPIE,MPIE=1]"), csrr x14, mstatus)
    TEST_CASE(63, x14, 0, ("mret[fwd:csrw-mepc-then-mret]"), li x14, 1; LA_ABS(x1, 3f); csrw mepc, x1; mret; nop; nop; 3: li x14, 0)
    csrw mstatus, x0

    csrw mtvec, x0
    j pass

    .balign 4
trap_handler:
    csrr x20, mcause
    csrr x21, mepc
    csrr x22, mtval
    csrr x24, mstatus
    addi x23, x23, 1
    addi x25, x21, 4
    csrw mepc, x25
    mret

jtgt:
    nop
    nop
RVTEST_CODE_END

RVTEST_DATA_BEGIN
tdat:  .word 0x11223344
tdat2: .word 0x11223344
tptr:  .word tdat
