// jalr.S - тесты инструкции JALR: переход по регистру
// Сгенерировано gen_rv32i.py - не редактировать вручную.
#include "riscv_test.h"

RVTEST_CODE_BEGIN
    TEST_JALR(1, 0)
    TEST_JALR(2, 8)
    TEST_JALR(3, -8)
    TEST_JALR(4, 2047)
    TEST_JALR(5, -2048)
    TEST_JALR_RD_EQ_RS1(6)
    TEST_JALR_FLUSH(7)

    //Байпас (конвейер)
    TEST_JALR_SRC1_BYPASS(8, 0)
    TEST_JALR_SRC1_BYPASS(9, 1)
    TEST_JALR_SRC1_BYPASS(10, 2)
    TEST_JALR_LOAD_BYPASS(11, 0)
    TEST_JALR_LOAD_BYPASS(12, 1)
    TEST_JALR_LOAD_BYPASS(13, 2)

    //Младший бит адреса перехода обнуляется: (rs1 + imm) & ~1
    TEST_JALR_LSB(14, 1, 0)
    TEST_JALR_LSB(15, 0, 1)

    //Регистр x0
    TEST_JALR_ZERODEST(16)

    j pass
RVTEST_CODE_END
