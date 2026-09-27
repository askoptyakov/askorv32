// slti.S - тесты инструкции SLTI: регистр-константа
// Сгенерировано gen_rv32i.py - не редактировать вручную.
#include "riscv_test.h"

RVTEST_CODE_BEGIN

    //Значения
    TEST_IMM_OP(1, slti, 0x00000000, 0x00000000, 0)
    TEST_IMM_OP(2, slti, 0x00000000, 0x00000001, 1)
    TEST_IMM_OP(3, slti, 0x00000001, 0x00000003, 7)
    TEST_IMM_OP(4, slti, 0x00000000, 0x00000000, -2048)
    TEST_IMM_OP(5, slti, 0x00000001, 0x80000000, 0)
    TEST_IMM_OP(6, slti, 0x00000001, 0x80000000, -2048)
    TEST_IMM_OP(7, slti, 0x00000001, 0x00000000, 2047)
    TEST_IMM_OP(8, slti, 0x00000000, 0x7fffffff, 0)
    TEST_IMM_OP(9, slti, 0x00000000, 0x7fffffff, 2047)
    TEST_IMM_OP(10, slti, 0x00000001, 0x80000000, 2047)
    TEST_IMM_OP(11, slti, 0x00000000, 0x7fffffff, -2048)
    TEST_IMM_OP(12, slti, 0x00000000, 0x00000000, -1)
    TEST_IMM_OP(13, slti, 0x00000001, 0xffffffff, 1)
    TEST_IMM_OP(14, slti, 0x00000000, 0xffffffff, -1)
    TEST_IMM_OP(15, slti, 0x00000000, 0x00ff00ff, 240)
    TEST_IMM_OP(16, slti, 0x00000001, 0xff00ff00, -241)
    TEST_IMM_OP(17, slti, 0x00000000, 0x12345678, 1024)
    TEST_IMM_OP(18, slti, 0x00000000, 0x12345678, -1024)
    TEST_IMM_OP(19, slti, 0x00000001, 0x00000400, 1365)
    TEST_IMM_OP(20, slti, 0x00000001, 0xaaaaaaaa, -683)

    //Совпадение регистров
    TEST_IMM_SRC1_EQ_DEST(21, slti, 0x00000001, 0x87654321, 11)

    //Байпас (конвейер)
    TEST_IMM_DEST_BYPASS(22, 0, slti, 0x00000001, 0x87654321, 11)
    TEST_IMM_DEST_BYPASS(23, 1, slti, 0x00000001, 0x87654321, 11)
    TEST_IMM_DEST_BYPASS(24, 2, slti, 0x00000001, 0x87654321, 11)
    TEST_IMM_SRC1_BYPASS(25, 0, slti, 0x00000001, 0x87654321, 11)
    TEST_IMM_SRC1_BYPASS(26, 1, slti, 0x00000001, 0x87654321, 11)
    TEST_IMM_SRC1_BYPASS(27, 2, slti, 0x00000001, 0x87654321, 11)

    //Регистр x0
    TEST_IMM_ZEROSRC1(28, slti, 0x00000001, 11)
    TEST_IMM_ZERODEST(29, slti, 0x87654321, 11)

    j pass
RVTEST_CODE_END
