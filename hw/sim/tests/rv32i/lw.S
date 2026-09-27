// lw.S - тесты инструкции LW: загрузка из памяти
// Сгенерировано gen_rv32i.py - не редактировать вручную.
#include "riscv_test.h"

RVTEST_CODE_BEGIN

    //Значения: все допустимые смещения внутри слов, положительные и отрицательные
    TEST_LD_OP(1, lw, 0x00ff80ff, 0, tdat)
    TEST_LD_OP(2, lw, 0xff007f00, 4, tdat)
    TEST_LD_OP(3, lw, 0x0ff00ff0, 8, tdat)
    TEST_LD_OP(4, lw, 0xf00ff00f, 12, tdat)
    TEST_LD_OP(5, lw, 0x00ff80ff, -16, tdat16)
    TEST_LD_OP(6, lw, 0xff007f00, -12, tdat16)
    TEST_LD_OP(7, lw, 0x0ff00ff0, -8, tdat16)
    TEST_LD_OP(8, lw, 0xf00ff00f, -4, tdat16)
    TEST_LD_OP(9, lw, 0x7f7e7d7c, 4, tdat16)

    //Совпадение регистров
    TEST_LD_RD_EQ_RS1(10, lw, 0xff007f00, 4, tdat)

    //Байпас и приостановка конвейера (load-use)
    TEST_LD_DEST_BYPASS(11, 0, lw, 0xff007f00, 4, tdat)
    TEST_LD_DEST_BYPASS(12, 1, lw, 0xff007f00, 4, tdat)
    TEST_LD_DEST_BYPASS(13, 2, lw, 0xff007f00, 4, tdat)
    TEST_LD_DEST_BYPASS2(14, 0, lw, 0x0ff00ff0, 8, tdat)
    TEST_LD_DEST_BYPASS2(15, 1, lw, 0x0ff00ff0, 8, tdat)
    TEST_LD_DEST_BYPASS2(16, 2, lw, 0x0ff00ff0, 8, tdat)
    TEST_LD_SRC1_BYPASS(17, 0, lw, 0xf00ff00f, 12, tdat)
    TEST_LD_SRC1_BYPASS(18, 1, lw, 0xf00ff00f, 12, tdat)
    TEST_LD_SRC1_BYPASS(19, 2, lw, 0xf00ff00f, 12, tdat)

    //Регистр x0
    TEST_LD_ZERODEST(20, lw, 0, tdat)

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
