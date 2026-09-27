// ori.S - тесты инструкции ORI: регистр-константа
// Сгенерировано gen_rv32i.py - не редактировать вручную.
#include "riscv_test.h"

RVTEST_CODE_BEGIN

    //Значения
    TEST_IMM_OP(1, ori, 0x00000000, 0x00000000, 0)
    TEST_IMM_OP(2, ori, 0x00000001, 0x00000001, 1)
    TEST_IMM_OP(3, ori, 0x00000007, 0x00000003, 7)
    TEST_IMM_OP(4, ori, 0xfffff800, 0x00000000, -2048)
    TEST_IMM_OP(5, ori, 0x80000000, 0x80000000, 0)
    TEST_IMM_OP(6, ori, 0xfffff800, 0x80000000, -2048)
    TEST_IMM_OP(7, ori, 0x000007ff, 0x00000000, 2047)
    TEST_IMM_OP(8, ori, 0x7fffffff, 0x7fffffff, 0)
    TEST_IMM_OP(9, ori, 0x7fffffff, 0x7fffffff, 2047)
    TEST_IMM_OP(10, ori, 0x800007ff, 0x80000000, 2047)
    TEST_IMM_OP(11, ori, 0xffffffff, 0x7fffffff, -2048)
    TEST_IMM_OP(12, ori, 0xffffffff, 0x00000000, -1)
    TEST_IMM_OP(13, ori, 0xffffffff, 0xffffffff, 1)
    TEST_IMM_OP(14, ori, 0xffffffff, 0xffffffff, -1)
    TEST_IMM_OP(15, ori, 0x00ff00ff, 0x00ff00ff, 240)
    TEST_IMM_OP(16, ori, 0xffffff0f, 0xff00ff00, -241)
    TEST_IMM_OP(17, ori, 0x12345678, 0x12345678, 1024)
    TEST_IMM_OP(18, ori, 0xfffffe78, 0x12345678, -1024)
    TEST_IMM_OP(19, ori, 0x00000555, 0x00000400, 1365)
    TEST_IMM_OP(20, ori, 0xffffffff, 0xaaaaaaaa, -683)

    //Совпадение регистров
    TEST_IMM_SRC1_EQ_DEST(21, ori, 0x8765432b, 0x87654321, 11)

    //Байпас (конвейер)
    TEST_IMM_DEST_BYPASS(22, 0, ori, 0x8765432b, 0x87654321, 11)
    TEST_IMM_DEST_BYPASS(23, 1, ori, 0x8765432b, 0x87654321, 11)
    TEST_IMM_DEST_BYPASS(24, 2, ori, 0x8765432b, 0x87654321, 11)
    TEST_IMM_SRC1_BYPASS(25, 0, ori, 0x8765432b, 0x87654321, 11)
    TEST_IMM_SRC1_BYPASS(26, 1, ori, 0x8765432b, 0x87654321, 11)
    TEST_IMM_SRC1_BYPASS(27, 2, ori, 0x8765432b, 0x87654321, 11)

    //Регистр x0
    TEST_IMM_ZEROSRC1(28, ori, 0x0000000b, 11)
    TEST_IMM_ZERODEST(29, ori, 0x87654321, 11)

    j pass
RVTEST_CODE_END
