// andi.S - тесты инструкции ANDI: регистр-константа
// Сгенерировано gen_rv32i.py - не редактировать вручную.
#include "riscv_test.h"

RVTEST_CODE_BEGIN

    //Значения
    TEST_IMM_OP(1, andi, 0x00000000, 0x00000000, 0)
    TEST_IMM_OP(2, andi, 0x00000001, 0x00000001, 1)
    TEST_IMM_OP(3, andi, 0x00000003, 0x00000003, 7)
    TEST_IMM_OP(4, andi, 0x00000000, 0x00000000, -2048)
    TEST_IMM_OP(5, andi, 0x00000000, 0x80000000, 0)
    TEST_IMM_OP(6, andi, 0x80000000, 0x80000000, -2048)
    TEST_IMM_OP(7, andi, 0x00000000, 0x00000000, 2047)
    TEST_IMM_OP(8, andi, 0x00000000, 0x7fffffff, 0)
    TEST_IMM_OP(9, andi, 0x000007ff, 0x7fffffff, 2047)
    TEST_IMM_OP(10, andi, 0x00000000, 0x80000000, 2047)
    TEST_IMM_OP(11, andi, 0x7ffff800, 0x7fffffff, -2048)
    TEST_IMM_OP(12, andi, 0x00000000, 0x00000000, -1)
    TEST_IMM_OP(13, andi, 0x00000001, 0xffffffff, 1)
    TEST_IMM_OP(14, andi, 0xffffffff, 0xffffffff, -1)
    TEST_IMM_OP(15, andi, 0x000000f0, 0x00ff00ff, 240)
    TEST_IMM_OP(16, andi, 0xff00ff00, 0xff00ff00, -241)
    TEST_IMM_OP(17, andi, 0x00000400, 0x12345678, 1024)
    TEST_IMM_OP(18, andi, 0x12345400, 0x12345678, -1024)
    TEST_IMM_OP(19, andi, 0x00000400, 0x00000400, 1365)
    TEST_IMM_OP(20, andi, 0xaaaaa800, 0xaaaaaaaa, -683)

    //Совпадение регистров
    TEST_IMM_SRC1_EQ_DEST(21, andi, 0x00000001, 0x87654321, 11)

    //Байпас (конвейер)
    TEST_IMM_DEST_BYPASS(22, 0, andi, 0x00000001, 0x87654321, 11)
    TEST_IMM_DEST_BYPASS(23, 1, andi, 0x00000001, 0x87654321, 11)
    TEST_IMM_DEST_BYPASS(24, 2, andi, 0x00000001, 0x87654321, 11)
    TEST_IMM_SRC1_BYPASS(25, 0, andi, 0x00000001, 0x87654321, 11)
    TEST_IMM_SRC1_BYPASS(26, 1, andi, 0x00000001, 0x87654321, 11)
    TEST_IMM_SRC1_BYPASS(27, 2, andi, 0x00000001, 0x87654321, 11)

    //Регистр x0
    TEST_IMM_ZEROSRC1(28, andi, 0x00000000, 11)
    TEST_IMM_ZERODEST(29, andi, 0x87654321, 11)

    j pass
RVTEST_CODE_END
