// sw.S - тесты инструкции SW: запись в память (проверка обратным чтением)
// Сгенерировано gen_rv32i.py - не редактировать вручную.
#include "riscv_test.h"

RVTEST_CODE_BEGIN

    //Значения: разные смещения, положительные и отрицательные
    TEST_ST_OP(1, lw, sw, 0xffffffaa, 0, tscratch)
    TEST_ST_OP(2, lw, sw, 0x0000000a, 4, tscratch)
    TEST_ST_OP(3, lw, sw, 0xffffaa00, 8, tscratch)
    TEST_ST_OP(4, lw, sw, 0x0000a00a, 12, tscratch)
    TEST_ST_OP(5, lw, sw, 0xaa00aa00, 0, tscratch)
    TEST_ST_OP(6, lw, sw, 0x00aa00aa, 4, tscratch)
    TEST_ST_OP(7, lw, sw, 0x0aa00aa0, 8, tscratch)
    TEST_ST_OP(8, lw, sw, 0xa00aa00a, 12, tscratch)
    TEST_ST_OP(9, lw, sw, 0xffffffaa, -16, tscratch32)
    TEST_ST_OP(10, lw, sw, 0x0000000a, -8, tscratch32)
    TEST_ST_OP(11, lw, sw, 0xffffaa00, 0, tscratch32)
    TEST_ST_OP(12, lw, sw, 0x0000a00a, 8, tscratch32)

    //Байтовые стробы: соседние байты слова не меняются
    TEST_ST_MERGE(13, sw, 0x12345678, 0, tscratch48, 0xa5a5a5a5, 0x12345678)

    //Байпас (конвейер)
    TEST_ST_SRC12_BYPASS(14, 0, 0, lw, sw, 0x87654321, 4, tscratch)
    TEST_ST_SRC12_BYPASS(15, 0, 1, lw, sw, 0x87654321, 4, tscratch)
    TEST_ST_SRC12_BYPASS(16, 0, 2, lw, sw, 0x87654321, 4, tscratch)
    TEST_ST_SRC12_BYPASS(17, 1, 0, lw, sw, 0x87654321, 4, tscratch)
    TEST_ST_SRC12_BYPASS(18, 1, 1, lw, sw, 0x87654321, 4, tscratch)
    TEST_ST_SRC12_BYPASS(19, 2, 0, lw, sw, 0x87654321, 4, tscratch)
    TEST_ST_SRC21_BYPASS(20, 0, 0, lw, sw, 0x87654321, 8, tscratch)
    TEST_ST_SRC21_BYPASS(21, 0, 1, lw, sw, 0x87654321, 8, tscratch)
    TEST_ST_SRC21_BYPASS(22, 0, 2, lw, sw, 0x87654321, 8, tscratch)
    TEST_ST_SRC21_BYPASS(23, 1, 0, lw, sw, 0x87654321, 8, tscratch)
    TEST_ST_SRC21_BYPASS(24, 1, 1, lw, sw, 0x87654321, 8, tscratch)
    TEST_ST_SRC21_BYPASS(25, 2, 0, lw, sw, 0x87654321, 8, tscratch)
    TEST_ST_LOAD_DATA(26, 0, lw, sw, 0x87654321, 12, tscratch, tsrc)
    TEST_ST_LOAD_DATA(27, 1, lw, sw, 0x87654321, 12, tscratch, tsrc)
    TEST_ST_LOAD_DATA(28, 2, lw, sw, 0x87654321, 12, tscratch, tsrc)

    j pass
RVTEST_CODE_END

RVTEST_DATA_BEGIN
tsrc: .word 0
tscratch: .zero 32
tscratch32: .zero 16
tscratch48: .zero 16
