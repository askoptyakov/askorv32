// xori.S - тесты инструкции XORI: регистр-константа
// Сгенерировано gen_rv32i.py - не редактировать вручную.
#include "riscv_test.h"

RVTEST_CODE_BEGIN

    //Значения
    TEST_IMM_OP(1, xori, 0x00000000, 0x00000000, 0)
    TEST_IMM_OP(2, xori, 0x00000000, 0x00000001, 1)
    TEST_IMM_OP(3, xori, 0x00000004, 0x00000003, 7)
    TEST_IMM_OP(4, xori, 0xfffff800, 0x00000000, -2048)
    TEST_IMM_OP(5, xori, 0x80000000, 0x80000000, 0)
    TEST_IMM_OP(6, xori, 0x7ffff800, 0x80000000, -2048)
    TEST_IMM_OP(7, xori, 0x000007ff, 0x00000000, 2047)
    TEST_IMM_OP(8, xori, 0x7fffffff, 0x7fffffff, 0)
    TEST_IMM_OP(9, xori, 0x7ffff800, 0x7fffffff, 2047)
    TEST_IMM_OP(10, xori, 0x800007ff, 0x80000000, 2047)
    TEST_IMM_OP(11, xori, 0x800007ff, 0x7fffffff, -2048)
    TEST_IMM_OP(12, xori, 0xffffffff, 0x00000000, -1)
    TEST_IMM_OP(13, xori, 0xfffffffe, 0xffffffff, 1)
    TEST_IMM_OP(14, xori, 0x00000000, 0xffffffff, -1)
    TEST_IMM_OP(15, xori, 0x00ff000f, 0x00ff00ff, 240)
    TEST_IMM_OP(16, xori, 0x00ff000f, 0xff00ff00, -241)
    TEST_IMM_OP(17, xori, 0x12345278, 0x12345678, 1024)
    TEST_IMM_OP(18, xori, 0xedcbaa78, 0x12345678, -1024)
    TEST_IMM_OP(19, xori, 0x00000155, 0x00000400, 1365)
    TEST_IMM_OP(20, xori, 0x555557ff, 0xaaaaaaaa, -683)

    //Совпадение регистров
    TEST_IMM_SRC1_EQ_DEST(21, xori, 0x8765432a, 0x87654321, 11)

    //Байпас (конвейер)
    TEST_IMM_DEST_BYPASS(22, 0, xori, 0x8765432a, 0x87654321, 11)
    TEST_IMM_DEST_BYPASS(23, 1, xori, 0x8765432a, 0x87654321, 11)
    TEST_IMM_DEST_BYPASS(24, 2, xori, 0x8765432a, 0x87654321, 11)
    TEST_IMM_SRC1_BYPASS(25, 0, xori, 0x8765432a, 0x87654321, 11)
    TEST_IMM_SRC1_BYPASS(26, 1, xori, 0x8765432a, 0x87654321, 11)
    TEST_IMM_SRC1_BYPASS(27, 2, xori, 0x8765432a, 0x87654321, 11)

    //Регистр x0
    TEST_IMM_ZEROSRC1(28, xori, 0x0000000b, 11)
    TEST_IMM_ZERODEST(29, xori, 0x87654321, 11)

    j pass
RVTEST_CODE_END
