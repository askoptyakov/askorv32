// srai.S - тесты инструкции SRAI: регистр-константа
// Сгенерировано gen_rv32i.py - не редактировать вручную.
#include "riscv_test.h"

RVTEST_CODE_BEGIN

    //Значения
    TEST_IMM_OP(1, srai, 0x00000001, 0x00000001, 0)
    TEST_IMM_OP(2, srai, 0x00000000, 0x00000001, 1)
    TEST_IMM_OP(3, srai, 0x00000000, 0x00000001, 7)
    TEST_IMM_OP(4, srai, 0x00000000, 0x00000001, 14)
    TEST_IMM_OP(5, srai, 0x00000000, 0x00000001, 20)
    TEST_IMM_OP(6, srai, 0x00000000, 0x00000001, 31)
    TEST_IMM_OP(7, srai, 0xffffffff, 0xffffffff, 0)
    TEST_IMM_OP(8, srai, 0xffffffff, 0xffffffff, 1)
    TEST_IMM_OP(9, srai, 0xffffffff, 0xffffffff, 7)
    TEST_IMM_OP(10, srai, 0xffffffff, 0xffffffff, 14)
    TEST_IMM_OP(11, srai, 0xffffffff, 0xffffffff, 20)
    TEST_IMM_OP(12, srai, 0xffffffff, 0xffffffff, 31)
    TEST_IMM_OP(13, srai, 0x21212121, 0x21212121, 0)
    TEST_IMM_OP(14, srai, 0x10909090, 0x21212121, 1)
    TEST_IMM_OP(15, srai, 0x00424242, 0x21212121, 7)
    TEST_IMM_OP(16, srai, 0x00008484, 0x21212121, 14)
    TEST_IMM_OP(17, srai, 0x00000212, 0x21212121, 20)
    TEST_IMM_OP(18, srai, 0x00000000, 0x21212121, 31)
    TEST_IMM_OP(19, srai, 0x80000000, 0x80000000, 0)
    TEST_IMM_OP(20, srai, 0xc0000000, 0x80000000, 1)
    TEST_IMM_OP(21, srai, 0xff000000, 0x80000000, 7)
    TEST_IMM_OP(22, srai, 0xfffe0000, 0x80000000, 14)
    TEST_IMM_OP(23, srai, 0xfffff800, 0x80000000, 20)
    TEST_IMM_OP(24, srai, 0xffffffff, 0x80000000, 31)
    TEST_IMM_OP(25, srai, 0x12345678, 0x12345678, 0)
    TEST_IMM_OP(26, srai, 0x091a2b3c, 0x12345678, 1)
    TEST_IMM_OP(27, srai, 0x002468ac, 0x12345678, 7)
    TEST_IMM_OP(28, srai, 0x000048d1, 0x12345678, 14)
    TEST_IMM_OP(29, srai, 0x00000123, 0x12345678, 20)
    TEST_IMM_OP(30, srai, 0x00000000, 0x12345678, 31)

    //Совпадение регистров
    TEST_IMM_SRC1_EQ_DEST(31, srai, 0xff0eca86, 0x87654321, 7)

    //Байпас (конвейер)
    TEST_IMM_DEST_BYPASS(32, 0, srai, 0xff0eca86, 0x87654321, 7)
    TEST_IMM_DEST_BYPASS(33, 1, srai, 0xff0eca86, 0x87654321, 7)
    TEST_IMM_DEST_BYPASS(34, 2, srai, 0xff0eca86, 0x87654321, 7)
    TEST_IMM_SRC1_BYPASS(35, 0, srai, 0xff0eca86, 0x87654321, 7)
    TEST_IMM_SRC1_BYPASS(36, 1, srai, 0xff0eca86, 0x87654321, 7)
    TEST_IMM_SRC1_BYPASS(37, 2, srai, 0xff0eca86, 0x87654321, 7)

    //Регистр x0
    TEST_IMM_ZEROSRC1(38, srai, 0x00000000, 7)
    TEST_IMM_ZERODEST(39, srai, 0x87654321, 7)

    j pass
RVTEST_CODE_END
