// lbu.S - тесты инструкции LBU: загрузка из памяти
// Сгенерировано gen_rv32i.py - не редактировать вручную.
#include "riscv_test.h"

RVTEST_CODE_BEGIN

    //Значения: все допустимые смещения внутри слов, положительные и отрицательные
    TEST_LD_OP(1, lbu, 0x000000ff, 0, tdat)
    TEST_LD_OP(2, lbu, 0x00000080, 1, tdat)
    TEST_LD_OP(3, lbu, 0x000000ff, 2, tdat)
    TEST_LD_OP(4, lbu, 0x00000000, 3, tdat)
    TEST_LD_OP(5, lbu, 0x00000000, 4, tdat)
    TEST_LD_OP(6, lbu, 0x0000007f, 5, tdat)
    TEST_LD_OP(7, lbu, 0x00000000, 6, tdat)
    TEST_LD_OP(8, lbu, 0x000000ff, 7, tdat)
    TEST_LD_OP(9, lbu, 0x000000f0, 8, tdat)
    TEST_LD_OP(10, lbu, 0x0000000f, 9, tdat)
    TEST_LD_OP(11, lbu, 0x000000f0, 10, tdat)
    TEST_LD_OP(12, lbu, 0x0000000f, 11, tdat)
    TEST_LD_OP(13, lbu, 0x0000000f, 12, tdat)
    TEST_LD_OP(14, lbu, 0x000000f0, 13, tdat)
    TEST_LD_OP(15, lbu, 0x0000000f, 14, tdat)
    TEST_LD_OP(16, lbu, 0x000000f0, 15, tdat)
    TEST_LD_OP(17, lbu, 0x000000ff, -16, tdat16)
    TEST_LD_OP(18, lbu, 0x00000080, -15, tdat16)
    TEST_LD_OP(19, lbu, 0x000000ff, -14, tdat16)
    TEST_LD_OP(20, lbu, 0x00000000, -13, tdat16)
    TEST_LD_OP(21, lbu, 0x00000000, -12, tdat16)
    TEST_LD_OP(22, lbu, 0x0000007f, -11, tdat16)
    TEST_LD_OP(23, lbu, 0x00000000, -10, tdat16)
    TEST_LD_OP(24, lbu, 0x000000ff, -9, tdat16)
    TEST_LD_OP(25, lbu, 0x000000f0, -8, tdat16)
    TEST_LD_OP(26, lbu, 0x0000000f, -7, tdat16)
    TEST_LD_OP(27, lbu, 0x000000f0, -6, tdat16)
    TEST_LD_OP(28, lbu, 0x0000000f, -5, tdat16)
    TEST_LD_OP(29, lbu, 0x0000000f, -4, tdat16)
    TEST_LD_OP(30, lbu, 0x000000f0, -3, tdat16)
    TEST_LD_OP(31, lbu, 0x0000000f, -2, tdat16)
    TEST_LD_OP(32, lbu, 0x000000f0, -1, tdat16)
    TEST_LD_OP(33, lbu, 0x0000007c, 4, tdat16)

    //Совпадение регистров
    TEST_LD_RD_EQ_RS1(34, lbu, 0x00000000, 4, tdat)

    //Байпас и приостановка конвейера (load-use)
    TEST_LD_DEST_BYPASS(35, 0, lbu, 0x00000000, 4, tdat)
    TEST_LD_DEST_BYPASS(36, 1, lbu, 0x00000000, 4, tdat)
    TEST_LD_DEST_BYPASS(37, 2, lbu, 0x00000000, 4, tdat)
    TEST_LD_DEST_BYPASS2(38, 0, lbu, 0x000000f0, 8, tdat)
    TEST_LD_DEST_BYPASS2(39, 1, lbu, 0x000000f0, 8, tdat)
    TEST_LD_DEST_BYPASS2(40, 2, lbu, 0x000000f0, 8, tdat)
    TEST_LD_SRC1_BYPASS(41, 0, lbu, 0x0000000f, 12, tdat)
    TEST_LD_SRC1_BYPASS(42, 1, lbu, 0x0000000f, 12, tdat)
    TEST_LD_SRC1_BYPASS(43, 2, lbu, 0x0000000f, 12, tdat)

    //Регистр x0
    TEST_LD_ZERODEST(44, lbu, 0, tdat)

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
