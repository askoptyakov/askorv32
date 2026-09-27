// lb.S - тесты инструкции LB: загрузка из памяти
// Сгенерировано gen_rv32i.py - не редактировать вручную.
#include "riscv_test.h"

RVTEST_CODE_BEGIN

    //Значения: все допустимые смещения внутри слов, положительные и отрицательные
    TEST_LD_OP(1, lb, 0xffffffff, 0, tdat)
    TEST_LD_OP(2, lb, 0xffffff80, 1, tdat)
    TEST_LD_OP(3, lb, 0xffffffff, 2, tdat)
    TEST_LD_OP(4, lb, 0x00000000, 3, tdat)
    TEST_LD_OP(5, lb, 0x00000000, 4, tdat)
    TEST_LD_OP(6, lb, 0x0000007f, 5, tdat)
    TEST_LD_OP(7, lb, 0x00000000, 6, tdat)
    TEST_LD_OP(8, lb, 0xffffffff, 7, tdat)
    TEST_LD_OP(9, lb, 0xfffffff0, 8, tdat)
    TEST_LD_OP(10, lb, 0x0000000f, 9, tdat)
    TEST_LD_OP(11, lb, 0xfffffff0, 10, tdat)
    TEST_LD_OP(12, lb, 0x0000000f, 11, tdat)
    TEST_LD_OP(13, lb, 0x0000000f, 12, tdat)
    TEST_LD_OP(14, lb, 0xfffffff0, 13, tdat)
    TEST_LD_OP(15, lb, 0x0000000f, 14, tdat)
    TEST_LD_OP(16, lb, 0xfffffff0, 15, tdat)
    TEST_LD_OP(17, lb, 0xffffffff, -16, tdat16)
    TEST_LD_OP(18, lb, 0xffffff80, -15, tdat16)
    TEST_LD_OP(19, lb, 0xffffffff, -14, tdat16)
    TEST_LD_OP(20, lb, 0x00000000, -13, tdat16)
    TEST_LD_OP(21, lb, 0x00000000, -12, tdat16)
    TEST_LD_OP(22, lb, 0x0000007f, -11, tdat16)
    TEST_LD_OP(23, lb, 0x00000000, -10, tdat16)
    TEST_LD_OP(24, lb, 0xffffffff, -9, tdat16)
    TEST_LD_OP(25, lb, 0xfffffff0, -8, tdat16)
    TEST_LD_OP(26, lb, 0x0000000f, -7, tdat16)
    TEST_LD_OP(27, lb, 0xfffffff0, -6, tdat16)
    TEST_LD_OP(28, lb, 0x0000000f, -5, tdat16)
    TEST_LD_OP(29, lb, 0x0000000f, -4, tdat16)
    TEST_LD_OP(30, lb, 0xfffffff0, -3, tdat16)
    TEST_LD_OP(31, lb, 0x0000000f, -2, tdat16)
    TEST_LD_OP(32, lb, 0xfffffff0, -1, tdat16)
    TEST_LD_OP(33, lb, 0x0000007c, 4, tdat16)

    //Совпадение регистров
    TEST_LD_RD_EQ_RS1(34, lb, 0x00000000, 4, tdat)

    //Байпас и приостановка конвейера (load-use)
    TEST_LD_DEST_BYPASS(35, 0, lb, 0x00000000, 4, tdat)
    TEST_LD_DEST_BYPASS(36, 1, lb, 0x00000000, 4, tdat)
    TEST_LD_DEST_BYPASS(37, 2, lb, 0x00000000, 4, tdat)
    TEST_LD_DEST_BYPASS2(38, 0, lb, 0xfffffff0, 8, tdat)
    TEST_LD_DEST_BYPASS2(39, 1, lb, 0xfffffff0, 8, tdat)
    TEST_LD_DEST_BYPASS2(40, 2, lb, 0xfffffff0, 8, tdat)
    TEST_LD_SRC1_BYPASS(41, 0, lb, 0x0000000f, 12, tdat)
    TEST_LD_SRC1_BYPASS(42, 1, lb, 0x0000000f, 12, tdat)
    TEST_LD_SRC1_BYPASS(43, 2, lb, 0x0000000f, 12, tdat)

    //Регистр x0
    TEST_LD_ZERODEST(44, lb, 0, tdat)

    j pass
RVTEST_CODE_END

RVTEST_DATA_BEGIN
tdat:
    .word 0x00ff80ff
    .word 0xff007f00
    .word 0x0ff00ff0
    .word 0xf00ff00f
tdat16:
    .word 0x80818283
    .word 0x7f7e7d7c
