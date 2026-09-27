// jal.S - тесты инструкции JAL: безусловный переход
// Сгенерировано gen_rv32i.py - не редактировать вручную.
#include "riscv_test.h"

RVTEST_CODE_BEGIN
    TEST_JAL_LINK(1)
    TEST_JAL_BACKWARD(2)
    TEST_JAL_FLUSH(3)

    //Байпас (конвейер)
    TEST_JAL_DEST_BYPASS(4, 0)
    TEST_JAL_DEST_BYPASS(5, 1)
    TEST_JAL_DEST_BYPASS(6, 2)

    //Регистр x0
    TEST_JAL_ZERODEST(7)

    j pass
RVTEST_CODE_END
