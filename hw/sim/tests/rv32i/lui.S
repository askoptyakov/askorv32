// lui.S - тесты инструкции LUI: загрузка старших 20 бит
// Сгенерировано gen_rv32i.py - не редактировать вручную.
#include "riscv_test.h"

RVTEST_CODE_BEGIN

    //Значения
    TEST_LUI(1, 0x00000000, 0x00000000)
    TEST_LUI(2, 0x00001000, 0x00000001)
    TEST_LUI(3, 0x7ffff000, 0x0007ffff)
    TEST_LUI(4, 0x80000000, 0x00080000)
    TEST_LUI(5, 0xfffff000, 0x000fffff)
    TEST_LUI(6, 0x12345000, 0x00012345)
    TEST_LUI(7, 0xabcde000, 0x000abcde)

    //Байпас (конвейер)
    TEST_LUI_DEST_BYPASS(8, 0, 0x12345000, 0x00012345)
    TEST_LUI_DEST_BYPASS(9, 1, 0x12345000, 0x00012345)
    TEST_LUI_DEST_BYPASS(10, 2, 0x12345000, 0x00012345)

    //Регистр x0
    TEST_LUI_ZERODEST(11, 0x00012345)

    j pass
RVTEST_CODE_END
