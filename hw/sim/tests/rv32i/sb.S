// sb.S - тесты инструкции SB: запись в память (проверка обратным чтением)
// Сгенерировано gen_rv32i.py - не редактировать вручную.
#include "riscv_test.h"

RVTEST_CODE_BEGIN

    //Значения: разные смещения, положительные и отрицательные
    TEST_ST_OP(1, lb, sb, 0xffffffaa, 0, tscratch)
    TEST_ST_OP(2, lb, sb, 0x0000000a, 1, tscratch)
    TEST_ST_OP(3, lb, sb, 0x00000000, 2, tscratch)
    TEST_ST_OP(4, lb, sb, 0x0000000a, 3, tscratch)
    TEST_ST_OP(5, lb, sb, 0x00000000, 4, tscratch)
    TEST_ST_OP(6, lb, sb, 0xffffffaa, 5, tscratch)
    TEST_ST_OP(7, lb, sb, 0xffffffa0, 6, tscratch)
    TEST_ST_OP(8, lb, sb, 0x0000000a, 7, tscratch)
    TEST_ST_OP(9, lb, sb, 0xffffffaa, -16, tscratch32)
    TEST_ST_OP(10, lb, sb, 0x0000000a, -14, tscratch32)
    TEST_ST_OP(11, lb, sb, 0x00000000, -12, tscratch32)
    TEST_ST_OP(12, lb, sb, 0x0000000a, -10, tscratch32)

    //Байтовые стробы: соседние байты слова не меняются
    TEST_ST_MERGE(13, sb, 0x12345678, 0, tscratch48, 0xa5a5a5a5, 0xa5a5a578)
    TEST_ST_MERGE(14, sb, 0x12345678, 1, tscratch48, 0xa5a5a5a5, 0xa5a578a5)
    TEST_ST_MERGE(15, sb, 0x12345678, 2, tscratch48, 0xa5a5a5a5, 0xa578a5a5)
    TEST_ST_MERGE(16, sb, 0x12345678, 3, tscratch48, 0xa5a5a5a5, 0x78a5a5a5)

    //Байпас (конвейер)
    TEST_ST_SRC12_BYPASS(17, 0, 0, lb, sb, 0x00000021, 4, tscratch)
    TEST_ST_SRC12_BYPASS(18, 0, 1, lb, sb, 0x00000021, 4, tscratch)
    TEST_ST_SRC12_BYPASS(19, 0, 2, lb, sb, 0x00000021, 4, tscratch)
    TEST_ST_SRC12_BYPASS(20, 1, 0, lb, sb, 0x00000021, 4, tscratch)
    TEST_ST_SRC12_BYPASS(21, 1, 1, lb, sb, 0x00000021, 4, tscratch)
    TEST_ST_SRC12_BYPASS(22, 2, 0, lb, sb, 0x00000021, 4, tscratch)
    TEST_ST_SRC21_BYPASS(23, 0, 0, lb, sb, 0x00000021, 8, tscratch)
    TEST_ST_SRC21_BYPASS(24, 0, 1, lb, sb, 0x00000021, 8, tscratch)
    TEST_ST_SRC21_BYPASS(25, 0, 2, lb, sb, 0x00000021, 8, tscratch)
    TEST_ST_SRC21_BYPASS(26, 1, 0, lb, sb, 0x00000021, 8, tscratch)
    TEST_ST_SRC21_BYPASS(27, 1, 1, lb, sb, 0x00000021, 8, tscratch)
    TEST_ST_SRC21_BYPASS(28, 2, 0, lb, sb, 0x00000021, 8, tscratch)
    TEST_ST_LOAD_DATA(29, 0, lb, sb, 0x00000021, 12, tscratch, tsrc)
    TEST_ST_LOAD_DATA(30, 1, lb, sb, 0x00000021, 12, tscratch, tsrc)
    TEST_ST_LOAD_DATA(31, 2, lb, sb, 0x00000021, 12, tscratch, tsrc)

    j pass
RVTEST_CODE_END

RVTEST_DATA_BEGIN
tsrc: .word 0
tscratch: .zero 32
tscratch32: .zero 16
tscratch48: .zero 16
