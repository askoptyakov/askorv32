// slli.S - тесты инструкции SLLI: регистр-константа
// Сгенерировано gen_rv32i.py - не редактировать вручную.
#include "riscv_test.h"

RVTEST_CODE_BEGIN

    //Значения
    TEST_IMM_OP(1, slli, 0x00000001, 0x00000001, 0)
    TEST_IMM_OP(2, slli, 0x00000002, 0x00000001, 1)
    TEST_IMM_OP(3, slli, 0x00000080, 0x00000001, 7)
    TEST_IMM_OP(4, slli, 0x00004000, 0x00000001, 14)
    TEST_IMM_OP(5, slli, 0x00100000, 0x00000001, 20)
    TEST_IMM_OP(6, slli, 0x80000000, 0x00000001, 31)
    TEST_IMM_OP(7, slli, 0xffffffff, 0xffffffff, 0)
    TEST_IMM_OP(8, slli, 0xfffffffe, 0xffffffff, 1)
    TEST_IMM_OP(9, slli, 0xffffff80, 0xffffffff, 7)
    TEST_IMM_OP(10, slli, 0xffffc000, 0xffffffff, 14)
    TEST_IMM_OP(11, slli, 0xfff00000, 0xffffffff, 20)
    TEST_IMM_OP(12, slli, 0x80000000, 0xffffffff, 31)
    TEST_IMM_OP(13, slli, 0x21212121, 0x21212121, 0)
    TEST_IMM_OP(14, slli, 0x42424242, 0x21212121, 1)
    TEST_IMM_OP(15, slli, 0x90909080, 0x21212121, 7)
    TEST_IMM_OP(16, slli, 0x48484000, 0x21212121, 14)
    TEST_IMM_OP(17, slli, 0x12100000, 0x21212121, 20)
    TEST_IMM_OP(18, slli, 0x80000000, 0x21212121, 31)
    TEST_IMM_OP(19, slli, 0x80000000, 0x80000000, 0)
    TEST_IMM_OP(20, slli, 0x00000000, 0x80000000, 1)
    TEST_IMM_OP(21, slli, 0x00000000, 0x80000000, 7)
    TEST_IMM_OP(22, slli, 0x00000000, 0x80000000, 14)
    TEST_IMM_OP(23, slli, 0x00000000, 0x80000000, 20)
    TEST_IMM_OP(24, slli, 0x00000000, 0x80000000, 31)
    TEST_IMM_OP(25, slli, 0x12345678, 0x12345678, 0)
    TEST_IMM_OP(26, slli, 0x2468acf0, 0x12345678, 1)
    TEST_IMM_OP(27, slli, 0x1a2b3c00, 0x12345678, 7)
    TEST_IMM_OP(28, slli, 0x159e0000, 0x12345678, 14)
    TEST_IMM_OP(29, slli, 0x67800000, 0x12345678, 20)
    TEST_IMM_OP(30, slli, 0x00000000, 0x12345678, 31)

    //Совпадение регистров
    TEST_IMM_SRC1_EQ_DEST(31, slli, 0xb2a19080, 0x87654321, 7)

    //Байпас (конвейер)
    TEST_IMM_DEST_BYPASS(32, 0, slli, 0xb2a19080, 0x87654321, 7)
    TEST_IMM_DEST_BYPASS(33, 1, slli, 0xb2a19080, 0x87654321, 7)
    TEST_IMM_DEST_BYPASS(34, 2, slli, 0xb2a19080, 0x87654321, 7)
    TEST_IMM_SRC1_BYPASS(35, 0, slli, 0xb2a19080, 0x87654321, 7)
    TEST_IMM_SRC1_BYPASS(36, 1, slli, 0xb2a19080, 0x87654321, 7)
    TEST_IMM_SRC1_BYPASS(37, 2, slli, 0xb2a19080, 0x87654321, 7)

    //Регистр x0
    TEST_IMM_ZEROSRC1(38, slli, 0x00000000, 7)
    TEST_IMM_ZERODEST(39, slli, 0x87654321, 7)

    j pass
RVTEST_CODE_END
