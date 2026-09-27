// srli.S - тесты инструкции SRLI: регистр-константа
// Сгенерировано gen_rv32i.py - не редактировать вручную.
#include "riscv_test.h"

RVTEST_CODE_BEGIN

    //Значения
    TEST_IMM_OP(1, srli, 0x00000001, 0x00000001, 0)
    TEST_IMM_OP(2, srli, 0x00000000, 0x00000001, 1)
    TEST_IMM_OP(3, srli, 0x00000000, 0x00000001, 7)
    TEST_IMM_OP(4, srli, 0x00000000, 0x00000001, 14)
    TEST_IMM_OP(5, srli, 0x00000000, 0x00000001, 20)
    TEST_IMM_OP(6, srli, 0x00000000, 0x00000001, 31)
    TEST_IMM_OP(7, srli, 0xffffffff, 0xffffffff, 0)
    TEST_IMM_OP(8, srli, 0x7fffffff, 0xffffffff, 1)
    TEST_IMM_OP(9, srli, 0x01ffffff, 0xffffffff, 7)
    TEST_IMM_OP(10, srli, 0x0003ffff, 0xffffffff, 14)
    TEST_IMM_OP(11, srli, 0x00000fff, 0xffffffff, 20)
    TEST_IMM_OP(12, srli, 0x00000001, 0xffffffff, 31)
    TEST_IMM_OP(13, srli, 0x21212121, 0x21212121, 0)
    TEST_IMM_OP(14, srli, 0x10909090, 0x21212121, 1)
    TEST_IMM_OP(15, srli, 0x00424242, 0x21212121, 7)
    TEST_IMM_OP(16, srli, 0x00008484, 0x21212121, 14)
    TEST_IMM_OP(17, srli, 0x00000212, 0x21212121, 20)
    TEST_IMM_OP(18, srli, 0x00000000, 0x21212121, 31)
    TEST_IMM_OP(19, srli, 0x80000000, 0x80000000, 0)
    TEST_IMM_OP(20, srli, 0x40000000, 0x80000000, 1)
    TEST_IMM_OP(21, srli, 0x01000000, 0x80000000, 7)
    TEST_IMM_OP(22, srli, 0x00020000, 0x80000000, 14)
    TEST_IMM_OP(23, srli, 0x00000800, 0x80000000, 20)
    TEST_IMM_OP(24, srli, 0x00000001, 0x80000000, 31)
    TEST_IMM_OP(25, srli, 0x12345678, 0x12345678, 0)
    TEST_IMM_OP(26, srli, 0x091a2b3c, 0x12345678, 1)
    TEST_IMM_OP(27, srli, 0x002468ac, 0x12345678, 7)
    TEST_IMM_OP(28, srli, 0x000048d1, 0x12345678, 14)
    TEST_IMM_OP(29, srli, 0x00000123, 0x12345678, 20)
    TEST_IMM_OP(30, srli, 0x00000000, 0x12345678, 31)

    //Совпадение регистров
    TEST_IMM_SRC1_EQ_DEST(31, srli, 0x010eca86, 0x87654321, 7)

    //Байпас (конвейер)
    TEST_IMM_DEST_BYPASS(32, 0, srli, 0x010eca86, 0x87654321, 7)
    TEST_IMM_DEST_BYPASS(33, 1, srli, 0x010eca86, 0x87654321, 7)
    TEST_IMM_DEST_BYPASS(34, 2, srli, 0x010eca86, 0x87654321, 7)
    TEST_IMM_SRC1_BYPASS(35, 0, srli, 0x010eca86, 0x87654321, 7)
    TEST_IMM_SRC1_BYPASS(36, 1, srli, 0x010eca86, 0x87654321, 7)
    TEST_IMM_SRC1_BYPASS(37, 2, srli, 0x010eca86, 0x87654321, 7)

    //Регистр x0
    TEST_IMM_ZEROSRC1(38, srli, 0x00000000, 7)
    TEST_IMM_ZERODEST(39, srli, 0x87654321, 7)

    j pass
RVTEST_CODE_END
