// lhu.S - тесты инструкции LHU: загрузка из памяти
// Сгенерировано gen_rv32i.py - не редактировать вручную.
#include "riscv_test.h"

RVTEST_CODE_BEGIN

    //Значения: все допустимые смещения внутри слов, положительные и отрицательные
    TEST_LD_OP(1, lhu, 0x000080ff, 0, tdat)
    TEST_LD_OP(2, lhu, 0x000000ff, 2, tdat)
    TEST_LD_OP(3, lhu, 0x00007f00, 4, tdat)
    TEST_LD_OP(4, lhu, 0x0000ff00, 6, tdat)
    TEST_LD_OP(5, lhu, 0x00000ff0, 8, tdat)
    TEST_LD_OP(6, lhu, 0x00000ff0, 10, tdat)
    TEST_LD_OP(7, lhu, 0x0000f00f, 12, tdat)
    TEST_LD_OP(8, lhu, 0x0000f00f, 14, tdat)
    TEST_LD_OP(9, lhu, 0x000080ff, -16, tdat16)
    TEST_LD_OP(10, lhu, 0x000000ff, -14, tdat16)
    TEST_LD_OP(11, lhu, 0x00007f00, -12, tdat16)
    TEST_LD_OP(12, lhu, 0x0000ff00, -10, tdat16)
    TEST_LD_OP(13, lhu, 0x00000ff0, -8, tdat16)
    TEST_LD_OP(14, lhu, 0x00000ff0, -6, tdat16)
    TEST_LD_OP(15, lhu, 0x0000f00f, -4, tdat16)
    TEST_LD_OP(16, lhu, 0x0000f00f, -2, tdat16)
    TEST_LD_OP(17, lhu, 0x00007d7c, 4, tdat16)

    //Совпадение регистров
    TEST_LD_RD_EQ_RS1(18, lhu, 0x00007f00, 4, tdat)

    //Байпас и приостановка конвейера (load-use)
    TEST_LD_DEST_BYPASS(19, 0, lhu, 0x00007f00, 4, tdat)
    TEST_LD_DEST_BYPASS(20, 1, lhu, 0x00007f00, 4, tdat)
    TEST_LD_DEST_BYPASS(21, 2, lhu, 0x00007f00, 4, tdat)
    TEST_LD_DEST_BYPASS2(22, 0, lhu, 0x00000ff0, 8, tdat)
    TEST_LD_DEST_BYPASS2(23, 1, lhu, 0x00000ff0, 8, tdat)
    TEST_LD_DEST_BYPASS2(24, 2, lhu, 0x00000ff0, 8, tdat)
    TEST_LD_SRC1_BYPASS(25, 0, lhu, 0x0000f00f, 12, tdat)
    TEST_LD_SRC1_BYPASS(26, 1, lhu, 0x0000f00f, 12, tdat)
    TEST_LD_SRC1_BYPASS(27, 2, lhu, 0x0000f00f, 12, tdat)

    //Регистр x0
    TEST_LD_ZERODEST(28, lhu, 0, tdat)

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
