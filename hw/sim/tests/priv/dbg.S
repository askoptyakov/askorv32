// dbg.S - программа для сценария отладки tb_debug.svh (run_tests.py запускает её с +dbgtest)
//
// Цикл ждёт, пока отладчик не запишет 1 в flag; в цикле - точка останова bp_here (обычная
// инструкция, не переход). После выхода из цикла проверяется, что отладчик записал x12 и
// слово tdata.
#include "riscv_test.h"
#include "priv_test.h"

RVTEST_CODE_BEGIN
    li x10, 0
    li x12, 0
    LA_ABS(x1, flag)
    .globl bp_here
loop:
    addi x10, x10, 1
bp_here:
    addi x11, x10, 0
    lw x2, 0(x1)
    beqz x2, loop

    TEST_CASE(1, x12, 0x00001234, ("debugger-wrote-x12"), nop)
    TEST_CASE(2, x3,  0xCAFEBABE, ("debugger-wrote-tdata"), LA_ABS(x4, tdata); lw x3, 0(x4))
    j pass
RVTEST_CODE_END

RVTEST_DATA_BEGIN
    .globl flag, tdata
flag:  .word 0
tdata: .word 0
