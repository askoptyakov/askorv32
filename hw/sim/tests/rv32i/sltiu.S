// sltiu.S - тесты инструкции SLTIU: регистр-константа
// Сгенерировано gen_rv32i.py - не редактировать вручную.
#include "riscv_test.h"

RVTEST_CODE_BEGIN

    //Значения
    TEST_IMM_OP(1, sltiu, 0x00000000, 0x00000000, 0)
    TEST_IMM_OP(2, sltiu, 0x00000000, 0x00000001, 1)
    TEST_IMM_OP(3, sltiu, 0x00000001, 0x00000003, 7)
    TEST_IMM_OP(4, sltiu, 0x00000001, 0x00000000, -2048)
    TEST_IMM_OP(5, sltiu, 0x00000000, 0x80000000, 0)
    TEST_IMM_OP(6, sltiu, 0x00000001, 0x80000000, -2048)
    TEST_IMM_OP(7, sltiu, 0x00000001, 0x00000000, 2047)
    TEST_IMM_OP(8, sltiu, 0x00000000, 0x7fffffff, 0)
    TEST_IMM_OP(9, sltiu, 0x00000000, 0x7fffffff, 2047)
    TEST_IMM_OP(10, sltiu, 0x00000000, 0x80000000, 2047)
    TEST_IMM_OP(11, sltiu, 0x00000001, 0x7fffffff, -2048)
    TEST_IMM_OP(12, sltiu, 0x00000001, 0x00000000, -1)
    TEST_IMM_OP(13, sltiu, 0x00000000, 0xffffffff, 1)
    TEST_IMM_OP(14, sltiu, 0x00000000, 0xffffffff, -1)
    TEST_IMM_OP(15, sltiu, 0x00000000, 0x00ff00ff, 240)
    TEST_IMM_OP(16, sltiu, 0x00000001, 0xff00ff00, -241)
    TEST_IMM_OP(17, sltiu, 0x00000000, 0x12345678, 1024)
    TEST_IMM_OP(18, sltiu, 0x00000001, 0x12345678, -1024)
    TEST_IMM_OP(19, sltiu, 0x00000001, 0x00000400, 1365)
    TEST_IMM_OP(20, sltiu, 0x00000001, 0xaaaaaaaa, -683)

    //Совпадение регистров
    TEST_IMM_SRC1_EQ_DEST(21, sltiu, 0x00000001, 0x0000000b, -1)

    //Байпас (конвейер)
    TEST_IMM_DEST_BYPASS(22, 0, sltiu, 0x00000001, 0x0000000b, -1)
    TEST_IMM_DEST_BYPASS(23, 1, sltiu, 0x00000001, 0x0000000b, -1)
    TEST_IMM_DEST_BYPASS(24, 2, sltiu, 0x00000001, 0x0000000b, -1)
    TEST_IMM_SRC1_BYPASS(25, 0, sltiu, 0x00000001, 0x0000000b, -1)
    TEST_IMM_SRC1_BYPASS(26, 1, sltiu, 0x00000001, 0x0000000b, -1)
    TEST_IMM_SRC1_BYPASS(27, 2, sltiu, 0x00000001, 0x0000000b, -1)

    //Регистр x0
    TEST_IMM_ZEROSRC1(28, sltiu, 0x00000001, -1)
    TEST_IMM_ZERODEST(29, sltiu, 0x0000000b, -1)

    j pass
RVTEST_CODE_END
