// auipc.S - тесты инструкции AUIPC: PC + старшие 20 бит
// Сгенерировано gen_rv32i.py - не редактировать вручную.
#include "riscv_test.h"

RVTEST_CODE_BEGIN

    //Значения (ожидаемое значение считает компоновщик от адреса auipc)
    TEST_AUIPC(1, 0x00000000, 0)
    TEST_AUIPC(2, 0x00000001, 4096)
    TEST_AUIPC(3, 0x0007ffff, 2147479552)
    TEST_AUIPC(4, 0x00080000, -2147483648)
    TEST_AUIPC(5, 0x000fffff, -4096)
    TEST_AUIPC(6, 0x00012345, 305418240)
    TEST_AUIPC(7, 0x000ffff0, -65536)

    //Байпас (конвейер)
    TEST_AUIPC_DEST_BYPASS(8, 0, 0x00000001, 4096)
    TEST_AUIPC_DEST_BYPASS(9, 1, 0x00000001, 4096)
    TEST_AUIPC_DEST_BYPASS(10, 2, 0x00000001, 4096)

    j pass
RVTEST_CODE_END
