// addi.S - тесты инструкции ADDI: регистр-константа
// Сгенерировано gen_rv32i.py - не редактировать вручную.
#include "riscv_test.h"

RVTEST_CODE_BEGIN

    //Значения
    TEST_IMM_OP(1, addi, 0x00000000, 0x00000000, 0)
    TEST_IMM_OP(2, addi, 0x00000002, 0x00000001, 1)
    TEST_IMM_OP(3, addi, 0x0000000a, 0x00000003, 7)
    TEST_IMM_OP(4, addi, 0xfffff800, 0x00000000, -2048)
    TEST_IMM_OP(5, addi, 0x80000000, 0x80000000, 0)
    TEST_IMM_OP(6, addi, 0x7ffff800, 0x80000000, -2048)
    TEST_IMM_OP(7, addi, 0x000007ff, 0x00000000, 2047)
    TEST_IMM_OP(8, addi, 0x7fffffff, 0x7fffffff, 0)
    TEST_IMM_OP(9, addi, 0x800007fe, 0x7fffffff, 2047)
    TEST_IMM_OP(10, addi, 0x800007ff, 0x80000000, 2047)
    TEST_IMM_OP(11, addi, 0x7ffff7ff, 0x7fffffff, -2048)
    TEST_IMM_OP(12, addi, 0xffffffff, 0x00000000, -1)
    TEST_IMM_OP(13, addi, 0x00000000, 0xffffffff, 1)
    TEST_IMM_OP(14, addi, 0xfffffffe, 0xffffffff, -1)
    TEST_IMM_OP(15, addi, 0x00ff01ef, 0x00ff00ff, 240)
    TEST_IMM_OP(16, addi, 0xff00fe0f, 0xff00ff00, -241)
    TEST_IMM_OP(17, addi, 0x12345a78, 0x12345678, 1024)
    TEST_IMM_OP(18, addi, 0x12345278, 0x12345678, -1024)
    TEST_IMM_OP(19, addi, 0x00000955, 0x00000400, 1365)
    TEST_IMM_OP(20, addi, 0xaaaaa7ff, 0xaaaaaaaa, -683)

    //Совпадение регистров
    TEST_IMM_SRC1_EQ_DEST(21, addi, 0x8765432c, 0x87654321, 11)

    //Байпас (конвейер)
    TEST_IMM_DEST_BYPASS(22, 0, addi, 0x8765432c, 0x87654321, 11)
    TEST_IMM_DEST_BYPASS(23, 1, addi, 0x8765432c, 0x87654321, 11)
    TEST_IMM_DEST_BYPASS(24, 2, addi, 0x8765432c, 0x87654321, 11)
    TEST_IMM_SRC1_BYPASS(25, 0, addi, 0x8765432c, 0x87654321, 11)
    TEST_IMM_SRC1_BYPASS(26, 1, addi, 0x8765432c, 0x87654321, 11)
    TEST_IMM_SRC1_BYPASS(27, 2, addi, 0x8765432c, 0x87654321, 11)

    //Регистр x0
    TEST_IMM_ZEROSRC1(28, addi, 0x0000000b, 11)
    TEST_IMM_ZERODEST(29, addi, 0x87654321, 11)

    j pass
RVTEST_CODE_END
