// or.S - тесты инструкции OR: регистр-регистр
// Сгенерировано gen_rv32i.py - не редактировать вручную.
#include "riscv_test.h"

RVTEST_CODE_BEGIN

    //Значения
    TEST_RR_OP(1, or, 0x00000000, 0x00000000, 0x00000000)
    TEST_RR_OP(2, or, 0x00000001, 0x00000001, 0x00000001)
    TEST_RR_OP(3, or, 0x00000007, 0x00000003, 0x00000007)
    TEST_RR_OP(4, or, 0xffff8000, 0x00000000, 0xffff8000)
    TEST_RR_OP(5, or, 0x80000000, 0x80000000, 0x00000000)
    TEST_RR_OP(6, or, 0xffff8000, 0x80000000, 0xffff8000)
    TEST_RR_OP(7, or, 0x00007fff, 0x00000000, 0x00007fff)
    TEST_RR_OP(8, or, 0x7fffffff, 0x7fffffff, 0x00000000)
    TEST_RR_OP(9, or, 0x7fffffff, 0x7fffffff, 0x00007fff)
    TEST_RR_OP(10, or, 0x80007fff, 0x80000000, 0x00007fff)
    TEST_RR_OP(11, or, 0xffffffff, 0x7fffffff, 0xffff8000)
    TEST_RR_OP(12, or, 0xffffffff, 0x00000000, 0xffffffff)
    TEST_RR_OP(13, or, 0xffffffff, 0xffffffff, 0x00000001)
    TEST_RR_OP(14, or, 0xffffffff, 0xffffffff, 0xffffffff)
    TEST_RR_OP(15, or, 0x7fffffff, 0x00000001, 0x7fffffff)
    TEST_RR_OP(16, or, 0xffffffff, 0x7fffffff, 0x80000000)
    TEST_RR_OP(17, or, 0xffffffff, 0x80000000, 0x7fffffff)
    TEST_RR_OP(18, or, 0xffffffff, 0xffffffff, 0x00000000)
    TEST_RR_OP(19, or, 0xffffffff, 0x55555555, 0xaaaaaaaa)
    TEST_RR_OP(20, or, 0xfefcfef8, 0x12345678, 0xfedcba98)
    TEST_RR_OP(21, or, 0x0fff0fff, 0x0f0f0f0f, 0x00ff00ff)

    //Совпадение регистров
    TEST_RR_SRC1_EQ_DEST(22, or, 0x8765432b, 0x87654321, 0x0000000b)
    TEST_RR_SRC2_EQ_DEST(23, or, 0x8765432b, 0x87654321, 0x0000000b)
    TEST_RR_SRC12_EQ_DEST(24, or, 0x0000000d, 0x0000000d)

    //Байпас (конвейер)
    TEST_RR_DEST_BYPASS(25, 0, or, 0x8765432b, 0x87654321, 0x0000000b)
    TEST_RR_DEST_BYPASS(26, 1, or, 0x8765432b, 0x87654321, 0x0000000b)
    TEST_RR_DEST_BYPASS(27, 2, or, 0x8765432b, 0x87654321, 0x0000000b)
    TEST_RR_SRC12_BYPASS(28, 0, 0, or, 0x8765432b, 0x87654321, 0x0000000b)
    TEST_RR_SRC12_BYPASS(29, 0, 1, or, 0x8765432b, 0x87654321, 0x0000000b)
    TEST_RR_SRC12_BYPASS(30, 0, 2, or, 0x8765432b, 0x87654321, 0x0000000b)
    TEST_RR_SRC12_BYPASS(31, 1, 0, or, 0x8765432b, 0x87654321, 0x0000000b)
    TEST_RR_SRC12_BYPASS(32, 1, 1, or, 0x8765432b, 0x87654321, 0x0000000b)
    TEST_RR_SRC12_BYPASS(33, 2, 0, or, 0x8765432b, 0x87654321, 0x0000000b)
    TEST_RR_SRC21_BYPASS(34, 0, 0, or, 0x8765432b, 0x87654321, 0x0000000b)
    TEST_RR_SRC21_BYPASS(35, 0, 1, or, 0x8765432b, 0x87654321, 0x0000000b)
    TEST_RR_SRC21_BYPASS(36, 0, 2, or, 0x8765432b, 0x87654321, 0x0000000b)
    TEST_RR_SRC21_BYPASS(37, 1, 0, or, 0x8765432b, 0x87654321, 0x0000000b)
    TEST_RR_SRC21_BYPASS(38, 1, 1, or, 0x8765432b, 0x87654321, 0x0000000b)
    TEST_RR_SRC21_BYPASS(39, 2, 0, or, 0x8765432b, 0x87654321, 0x0000000b)

    //Регистр x0
    TEST_RR_ZEROSRC1(40, or, 0x0000000b, 0x0000000b)
    TEST_RR_ZEROSRC2(41, or, 0x87654321, 0x87654321)
    TEST_RR_ZEROSRC12(42, or, 0x00000000)
    TEST_RR_ZERODEST(43, or, 0x87654321, 0x0000000b)

    j pass
RVTEST_CODE_END
