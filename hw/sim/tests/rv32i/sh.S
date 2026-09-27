// sh.S - тесты инструкции SH: запись в память (проверка обратным чтением)
// Сгенерировано gen_rv32i.py - не редактировать вручную.
#include "riscv_test.h"

RVTEST_CODE_BEGIN

    //Значения: разные смещения, положительные и отрицательные
    TEST_ST_OP(1, lh, sh, 0xffffffaa, 0, tscratch)
    TEST_ST_OP(2, lh, sh, 0x0000000a, 2, tscratch)
    TEST_ST_OP(3, lh, sh, 0xffffaa00, 4, tscratch)
    TEST_ST_OP(4, lh, sh, 0xffffa00a, 6, tscratch)
    TEST_ST_OP(5, lh, sh, 0xffffaa00, 8, tscratch)
    TEST_ST_OP(6, lh, sh, 0x000000aa, 10, tscratch)
    TEST_ST_OP(7, lh, sh, 0x00000aa0, 12, tscratch)
    TEST_ST_OP(8, lh, sh, 0xffffa00a, 14, tscratch)
    TEST_ST_OP(9, lh, sh, 0xffffffaa, -16, tscratch32)
    TEST_ST_OP(10, lh, sh, 0x0000000a, -12, tscratch32)
    TEST_ST_OP(11, lh, sh, 0xffffaa00, -8, tscratch32)
    TEST_ST_OP(12, lh, sh, 0xffffa00a, -4, tscratch32)

    //Байтовые стробы: соседние байты слова не меняются
    TEST_ST_MERGE(13, sh, 0x12345678, 0, tscratch48, 0xa5a5a5a5, 0xa5a55678)
    TEST_ST_MERGE(14, sh, 0x12345678, 2, tscratch48, 0xa5a5a5a5, 0x5678a5a5)

    //Байпас (конвейер)
    TEST_ST_SRC12_BYPASS(15, 0, 0, lh, sh, 0x00004321, 4, tscratch)
    TEST_ST_SRC12_BYPASS(16, 0, 1, lh, sh, 0x00004321, 4, tscratch)
    TEST_ST_SRC12_BYPASS(17, 0, 2, lh, sh, 0x00004321, 4, tscratch)
    TEST_ST_SRC12_BYPASS(18, 1, 0, lh, sh, 0x00004321, 4, tscratch)
    TEST_ST_SRC12_BYPASS(19, 1, 1, lh, sh, 0x00004321, 4, tscratch)
    TEST_ST_SRC12_BYPASS(20, 2, 0, lh, sh, 0x00004321, 4, tscratch)
    TEST_ST_SRC21_BYPASS(21, 0, 0, lh, sh, 0x00004321, 8, tscratch)
    TEST_ST_SRC21_BYPASS(22, 0, 1, lh, sh, 0x00004321, 8, tscratch)
    TEST_ST_SRC21_BYPASS(23, 0, 2, lh, sh, 0x00004321, 8, tscratch)
    TEST_ST_SRC21_BYPASS(24, 1, 0, lh, sh, 0x00004321, 8, tscratch)
    TEST_ST_SRC21_BYPASS(25, 1, 1, lh, sh, 0x00004321, 8, tscratch)
    TEST_ST_SRC21_BYPASS(26, 2, 0, lh, sh, 0x00004321, 8, tscratch)
    TEST_ST_LOAD_DATA(27, 0, lh, sh, 0x00004321, 12, tscratch, tsrc)
    TEST_ST_LOAD_DATA(28, 1, lh, sh, 0x00004321, 12, tscratch, tsrc)
    TEST_ST_LOAD_DATA(29, 2, lh, sh, 0x00004321, 12, tscratch, tsrc)

    j pass
RVTEST_CODE_END

RVTEST_DATA_BEGIN
tsrc: .word 0
tscratch: .zero 32
tscratch32: .zero 16
tscratch48: .zero 16
