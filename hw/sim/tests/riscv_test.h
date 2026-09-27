/*
 *****************************************************************************************
 * @file        riscv_test.h
 * @device      AskoRV32
 * @brief       Макросы самопроверяющихся тестов RV32I (по мотивам riscv-tests).
 *
 * Протокол обмена с тестбенчем (адрес TOHOST вне карты памяти, запись никуда не идёт,
 * её перехватывает тестбенч):
 *   TOHOST+4 <- фактическое значение (ACTUAL)  | номер последнего теста (при PASS)
 *   TOHOST+8 <- ожидаемое значение (EXPECTED)
 *   TOHOST+0 <- 1 - все тесты пройдены; (N<<1)|1 - не пройден тест N
 *
 * Имена тестов складываются в неразмещаемую секцию .testnames (в память не грузится),
 * run_tests.py извлекает её из ELF и передаёт тестбенчу.
 *
 * Зарезервированные регистры: x5, x6 - обработчики fail/pass; x28 - номер теста;
 * x29 - ожидаемое значение; x30 - фактическое значение.
 *****************************************************************************************
 */
#ifndef RISCV_TEST_H
#define RISCV_TEST_H

#define TOHOST   0x1F000000
#define TESTNUM  x28
#define EXPECTED x29
#define ACTUAL   x30

//Пустые инструкции между зависимыми командами: 0, 1 или 2 шт.
#define NOPS_0
#define NOPS_1 nop;
#define NOPS_2 nop; nop;
#define NOPS(k) NOPS_##k

//Абсолютный адрес метки без auipc (чтобы тесты не зависели от проверяемой auipc)
#define LA_ABS(reg, sym) lui reg, %hi(sym); addi reg, reg, %lo(sym)

//Обнуление рабочих регистров перед тестами байпаса: устаревшее значение в регистровом
//файле не должно совпасть с правильным и замаскировать ошибку байпасирования
#define SCRUB li x1, 0; li x2, 0; li x3, 0; li x6, 0; li x14, 0; nop; nop; nop;

//Имя теста: TEST_NAME(n, ("add(", "0x1", ")")) -> .word n; .ascii "add(","0x1",")"; .byte 0
#define NAME_PARTS(...) __VA_ARGS__
#define TEST_NAME(n, name) \
    .pushsection .testnames, "", @progbits; .balign 4; .word n; .ascii NAME_PARTS name; .byte 0; .popsection;

//-----------------------------------------------------------------------------------------
// Начало и конец программы
//-----------------------------------------------------------------------------------------
#define RVTEST_CODE_BEGIN \
    .section .reset, "ax", @progbits; \
    j _start; \
    .section .text.init, "ax", @progbits; \
    .globl _start; \
_start: \
    li TESTNUM, 0; \
    j test_start; \
fail: \
    li x5, TOHOST; \
    sw ACTUAL, 4(x5); \
    sw EXPECTED, 8(x5); \
    slli x6, TESTNUM, 1; \
    ori x6, x6, 1; \
    sw x6, 0(x5); \
1:  j 1b; \
test_start:

#define RVTEST_CODE_END \
pass: \
    li x5, TOHOST; \
    sw TESTNUM, 4(x5); \
    li x6, 1; \
    sw x6, 0(x5); \
1:  j 1b;

#define RVTEST_DATA_BEGIN .data; .balign 16;

//-----------------------------------------------------------------------------------------
// Базовый тест: выполнить code, сравнить testreg с correctval
//-----------------------------------------------------------------------------------------
#define TEST_CASE(n, testreg, correctval, name, code...) \
test_##n: \
    TEST_NAME(n, name) \
    li TESTNUM, n; \
    code; \
    li EXPECTED, correctval; \
    mv ACTUAL, testreg; \
    bne ACTUAL, EXPECTED, fail;

//-----------------------------------------------------------------------------------------
// Регистр-регистр (тип R)
//-----------------------------------------------------------------------------------------
#define TEST_RR_OP(n, inst, result, val1, val2) \
    TEST_CASE(n, x14, result, (#inst, "(", #val1, ",", #val2, ")"), \
        li x1, val1; li x2, val2; inst x14, x1, x2)

#define TEST_RR_SRC1_EQ_DEST(n, inst, result, val1, val2) \
    TEST_CASE(n, x1, result, (#inst, "[rd=rs1]"), \
        li x1, val1; li x2, val2; inst x1, x1, x2)

#define TEST_RR_SRC2_EQ_DEST(n, inst, result, val1, val2) \
    TEST_CASE(n, x2, result, (#inst, "[rd=rs2]"), \
        li x1, val1; li x2, val2; inst x2, x1, x2)

#define TEST_RR_SRC12_EQ_DEST(n, inst, result, val1) \
    TEST_CASE(n, x1, result, (#inst, "[rd=rs1=rs2]"), \
        li x1, val1; inst x1, x1, x1)

#define TEST_RR_DEST_BYPASS(n, k, inst, result, val1, val2) \
    TEST_CASE(n, x6, result, (#inst, "[fwd:rd->rs1,nop=", #k, "]"), \
        SCRUB li x1, val1; li x2, val2; inst x14, x1, x2; NOPS(k) addi x6, x14, 0)

#define TEST_RR_SRC12_BYPASS(n, k1, k2, inst, result, val1, val2) \
    TEST_CASE(n, x14, result, (#inst, "[fwd:rs1,rs2,nop=", #k1, ",", #k2, "]"), \
        SCRUB li x1, val1; NOPS(k1) li x2, val2; NOPS(k2) inst x14, x1, x2)

#define TEST_RR_SRC21_BYPASS(n, k1, k2, inst, result, val1, val2) \
    TEST_CASE(n, x14, result, (#inst, "[fwd:rs2,rs1,nop=", #k1, ",", #k2, "]"), \
        SCRUB li x2, val2; NOPS(k1) li x1, val1; NOPS(k2) inst x14, x1, x2)

#define TEST_RR_ZEROSRC1(n, inst, result, val2) \
    TEST_CASE(n, x14, result, (#inst, "[rs1=x0]"), \
        li x2, val2; inst x14, x0, x2)

#define TEST_RR_ZEROSRC2(n, inst, result, val1) \
    TEST_CASE(n, x14, result, (#inst, "[rs2=x0]"), \
        li x1, val1; inst x14, x1, x0)

#define TEST_RR_ZEROSRC12(n, inst, result) \
    TEST_CASE(n, x14, result, (#inst, "[rs1=rs2=x0]"), \
        inst x14, x0, x0)

#define TEST_RR_ZERODEST(n, inst, val1, val2) \
    TEST_CASE(n, x0, 0, (#inst, "[rd=x0]"), \
        li x1, val1; li x2, val2; inst x0, x1, x2)

//-----------------------------------------------------------------------------------------
// Регистр-константа (тип I)
//-----------------------------------------------------------------------------------------
#define TEST_IMM_OP(n, inst, result, val1, imm) \
    TEST_CASE(n, x14, result, (#inst, "(", #val1, ",", #imm, ")"), \
        li x1, val1; inst x14, x1, imm)

#define TEST_IMM_SRC1_EQ_DEST(n, inst, result, val1, imm) \
    TEST_CASE(n, x1, result, (#inst, "[rd=rs1]"), \
        li x1, val1; inst x1, x1, imm)

#define TEST_IMM_DEST_BYPASS(n, k, inst, result, val1, imm) \
    TEST_CASE(n, x6, result, (#inst, "[fwd:rd->rs1,nop=", #k, "]"), \
        SCRUB li x1, val1; inst x14, x1, imm; NOPS(k) addi x6, x14, 0)

#define TEST_IMM_SRC1_BYPASS(n, k, inst, result, val1, imm) \
    TEST_CASE(n, x14, result, (#inst, "[fwd:rs1,nop=", #k, "]"), \
        SCRUB li x1, val1; NOPS(k) inst x14, x1, imm)

#define TEST_IMM_ZEROSRC1(n, inst, result, imm) \
    TEST_CASE(n, x14, result, (#inst, "[rs1=x0]"), \
        inst x14, x0, imm)

#define TEST_IMM_ZERODEST(n, inst, val1, imm) \
    TEST_CASE(n, x0, 0, (#inst, "[rd=x0]"), \
        li x1, val1; inst x0, x1, imm)

//-----------------------------------------------------------------------------------------
// LUI / AUIPC
//-----------------------------------------------------------------------------------------
#define TEST_LUI(n, result, imm) \
    TEST_CASE(n, x14, result, ("lui(", #imm, ")"), \
        lui x14, imm)

#define TEST_LUI_DEST_BYPASS(n, k, result, imm) \
    TEST_CASE(n, x6, result, ("lui[fwd:rd->rs1,nop=", #k, "]"), \
        SCRUB lui x14, imm; NOPS(k) addi x6, x14, 0)

#define TEST_LUI_ZERODEST(n, imm) \
    TEST_CASE(n, x0, 0, ("lui[rd=x0]"), \
        lui x0, imm)

//Ожидаемое значение = адрес самой auipc + (imm << 12), вычисляется компоновщиком
#define TEST_AUIPC(n, imm, offset) \
test_##n: \
    TEST_NAME(n, ("auipc(", #imm, ")")) \
    li TESTNUM, n; \
auipc_##n: \
    auipc x14, imm; \
    LA_ABS(EXPECTED, auipc_##n + (offset)); \
    mv ACTUAL, x14; \
    bne ACTUAL, EXPECTED, fail;

#define TEST_AUIPC_DEST_BYPASS(n, k, imm, offset) \
test_##n: \
    TEST_NAME(n, ("auipc[fwd:rd->rs1,nop=", #k, "]")) \
    li TESTNUM, n; \
    SCRUB \
auipc_##n: \
    auipc x14, imm; \
    NOPS(k) addi x6, x14, 0; \
    LA_ABS(EXPECTED, auipc_##n + (offset)); \
    mv ACTUAL, x6; \
    bne ACTUAL, EXPECTED, fail;

//-----------------------------------------------------------------------------------------
// Условные переходы. EXPECTED/ACTUAL: 1 - переход выполнен, 0 - не выполнен
//-----------------------------------------------------------------------------------------
//Переход должен выполниться: вперёд и назад
#define TEST_BR2_OP_TAKEN(n, inst, val1, val2) \
test_##n: \
    TEST_NAME(n, (#inst, "[taken](", #val1, ",", #val2, ")")) \
    li TESTNUM, n; \
    li EXPECTED, 1; li ACTUAL, 0; \
    li x1, val1; li x2, val2; \
    inst x1, x2, 2f; \
    j fail; \
1:  j 3f; \
2:  inst x1, x2, 1b; \
    j fail; \
3:

//Переход не должен выполниться: вперёд и назад
#define TEST_BR2_OP_NOTTAKEN(n, inst, val1, val2) \
test_##n: \
    TEST_NAME(n, (#inst, "[not-taken](", #val1, ",", #val2, ")")) \
    li TESTNUM, n; \
    li EXPECTED, 0; li ACTUAL, 1; \
    li x1, val1; li x2, val2; \
    inst x1, x2, 1f; \
    j 2f; \
1:  j fail; \
2:  inst x1, x2, 1b; \
3:

//Инструкции после выполненного перехода не должны исполниться (сброс конвейера)
#define TEST_BR2_FLUSH(n, inst, val1, val2) \
    TEST_CASE(n, x7, 0, (#inst, "[flush]"), \
        li x7, 0; li x1, val1; li x2, val2; \
        inst x1, x2, 1f; addi x7, x7, 1; addi x7, x7, 1; addi x7, x7, 1; 1: )

//Операнды вычислены непосредственно перед переходом (байпас в конвейере)
#define TEST_BR2_SRC12_BYPASS(n, k1, k2, taken, inst, val1, val2) \
test_##n: \
    TEST_NAME(n, (#inst, "[fwd:rs1,rs2,nop=", #k1, ",", #k2, ",taken=", #taken, "]")) \
    li TESTNUM, n; \
    SCRUB \
    li EXPECTED, taken; li ACTUAL, 0; \
    li x1, val1; NOPS(k1) li x2, val2; NOPS(k2) \
    inst x1, x2, 1f; \
    j 2f; \
1:  li ACTUAL, 1; \
2:  bne ACTUAL, EXPECTED, fail;

#define TEST_BR2_SRC21_BYPASS(n, k1, k2, taken, inst, val1, val2) \
test_##n: \
    TEST_NAME(n, (#inst, "[fwd:rs2,rs1,nop=", #k1, ",", #k2, ",taken=", #taken, "]")) \
    li TESTNUM, n; \
    SCRUB \
    li EXPECTED, taken; li ACTUAL, 0; \
    li x2, val2; NOPS(k1) li x1, val1; NOPS(k2) \
    inst x1, x2, 1f; \
    j 2f; \
1:  li ACTUAL, 1; \
2:  bne ACTUAL, EXPECTED, fail;

//Операнд загружен из памяти непосредственно перед переходом (приостановка конвейера)
#define TEST_BR2_LOAD_BYPASS(n, k, taken, inst, val1, val2, addr) \
test_##n: \
    TEST_NAME(n, (#inst, "[load-use:rs1,nop=", #k, ",taken=", #taken, "]")) \
    li TESTNUM, n; \
    SCRUB \
    li EXPECTED, taken; li ACTUAL, 0; \
    LA_ABS(x3, addr); li x1, val1; sw x1, 0(x3); li x2, val2; li x1, 0; \
    lw x1, 0(x3); NOPS(k) \
    inst x1, x2, 1f; \
    j 2f; \
1:  li ACTUAL, 1; \
2:  bne ACTUAL, EXPECTED, fail;

//-----------------------------------------------------------------------------------------
// JAL
//-----------------------------------------------------------------------------------------
//Переход вперёд и адрес возврата в rd
#define TEST_JAL_LINK(n) \
test_##n: \
    TEST_NAME(n, ("jal[link]")) \
    li TESTNUM, n; \
    li EXPECTED, 1; li ACTUAL, 0; li x1, 0; \
    jal x1, jal_tgt_##n; \
jal_ret_##n: \
    j fail; \
jal_tgt_##n: \
    LA_ABS(EXPECTED, jal_ret_##n); \
    mv ACTUAL, x1; \
    bne ACTUAL, EXPECTED, fail;

//Переход назад
#define TEST_JAL_BACKWARD(n) \
test_##n: \
    TEST_NAME(n, ("jal[backward]")) \
    li TESTNUM, n; \
    li EXPECTED, 1; li ACTUAL, 0; li x1, 0; \
    j jal_fwd_##n; \
jal_back_##n: \
    j jal_done_##n; \
jal_fwd_##n: \
    jal x1, jal_back_##n; \
jal_ret_##n: \
    j fail; \
jal_done_##n: \
    LA_ABS(EXPECTED, jal_ret_##n); \
    mv ACTUAL, x1; \
    bne ACTUAL, EXPECTED, fail;

//Инструкции после jal не должны исполниться
#define TEST_JAL_FLUSH(n) \
    TEST_CASE(n, x7, 0, ("jal[flush]"), \
        li x7, 0; jal x0, 1f; addi x7, x7, 1; addi x7, x7, 1; addi x7, x7, 1; 1: )

//Адрес возврата используется сразу после перехода
#define TEST_JAL_DEST_BYPASS(n, k) \
test_##n: \
    TEST_NAME(n, ("jal[fwd:rd->rs1,nop=", #k, "]")) \
    li TESTNUM, n; \
    SCRUB \
    li EXPECTED, 1; li ACTUAL, 0; \
    jal x1, jal_tgt_##n; \
jal_ret_##n: \
    j fail; \
jal_tgt_##n: \
    NOPS(k) addi x6, x1, 0; \
    LA_ABS(EXPECTED, jal_ret_##n); \
    mv ACTUAL, x6; \
    bne ACTUAL, EXPECTED, fail;

#define TEST_JAL_ZERODEST(n) \
    TEST_CASE(n, x0, 0, ("jal[rd=x0]"), \
        jal x0, 1f; nop; 1: )

//-----------------------------------------------------------------------------------------
// JALR
//-----------------------------------------------------------------------------------------
//Переход по rs1 + offset, адрес возврата в rd
#define TEST_JALR(n, offset) \
test_##n: \
    TEST_NAME(n, ("jalr(", #offset, ")")) \
    li TESTNUM, n; \
    li EXPECTED, 1; li ACTUAL, 0; li x2, 0; \
    LA_ABS(x1, jalr_tgt_##n - (offset)); \
    jalr x2, offset(x1); \
jalr_ret_##n: \
    j fail; \
jalr_tgt_##n: \
    LA_ABS(EXPECTED, jalr_ret_##n); \
    mv ACTUAL, x2; \
    bne ACTUAL, EXPECTED, fail;

//rd = rs1: адрес перехода берётся из старого значения rs1
#define TEST_JALR_RD_EQ_RS1(n) \
test_##n: \
    TEST_NAME(n, ("jalr[rd=rs1]")) \
    li TESTNUM, n; \
    li EXPECTED, 1; li ACTUAL, 0; \
    LA_ABS(x1, jalr_tgt_##n); \
    jalr x1, 0(x1); \
jalr_ret_##n: \
    j fail; \
jalr_tgt_##n: \
    LA_ABS(EXPECTED, jalr_ret_##n); \
    mv ACTUAL, x1; \
    bne ACTUAL, EXPECTED, fail;

//Адрес перехода вычислен непосредственно перед jalr
#define TEST_JALR_SRC1_BYPASS(n, k) \
test_##n: \
    TEST_NAME(n, ("jalr[fwd:rs1,nop=", #k, "]")) \
    li TESTNUM, n; \
    SCRUB \
    li EXPECTED, 1; li ACTUAL, 0; \
    LA_ABS(x1, jalr_tgt_##n); NOPS(k) \
    jalr x2, 0(x1); \
jalr_ret_##n: \
    j fail; \
jalr_tgt_##n: \
    LA_ABS(EXPECTED, jalr_ret_##n); \
    mv ACTUAL, x2; \
    bne ACTUAL, EXPECTED, fail;

//Адрес перехода загружен из памяти непосредственно перед jalr
#define TEST_JALR_LOAD_BYPASS(n, k) \
    .pushsection .data; .balign 4; jalr_ptr_##n: .word jalr_tgt_##n; .popsection; \
test_##n: \
    TEST_NAME(n, ("jalr[load-use:rs1,nop=", #k, "]")) \
    li TESTNUM, n; \
    SCRUB \
    li EXPECTED, 1; li ACTUAL, 0; \
    LA_ABS(x3, jalr_ptr_##n); \
    lw x1, 0(x3); NOPS(k) \
    jalr x2, 0(x1); \
jalr_ret_##n: \
    j fail; \
jalr_tgt_##n: \
    LA_ABS(EXPECTED, jalr_ret_##n); \
    mv ACTUAL, x2; \
    bne ACTUAL, EXPECTED, fail;

//Инструкции после jalr не должны исполниться
#define TEST_JALR_FLUSH(n) \
test_##n: \
    TEST_NAME(n, ("jalr[flush]")) \
    li TESTNUM, n; \
    li x7, 0; \
    LA_ABS(x1, jalr_tgt_##n); \
    jalr x0, 0(x1); \
    addi x7, x7, 1; addi x7, x7, 1; addi x7, x7, 1; \
jalr_tgt_##n: \
    li EXPECTED, 0; \
    mv ACTUAL, x7; \
    bne ACTUAL, EXPECTED, fail;

//Спецификация: младший бит адреса перехода обнуляется, (rs1 + imm) & ~1.
//Проверка через auipc на месте перехода: PC должен быть чётным.
#define TEST_JALR_LSB(n, rs1_add, imm) \
test_##n: \
    TEST_NAME(n, ("jalr[target&~1,rs1+", #rs1_add, ",imm=", #imm, "]")) \
    li TESTNUM, n; \
    li EXPECTED, 1; li ACTUAL, 0; \
    LA_ABS(x1, jalr_tgt_##n + (rs1_add)); \
    jalr x2, imm(x1); \
    j fail; \
jalr_tgt_##n: \
    auipc x14, 0; \
    LA_ABS(EXPECTED, jalr_tgt_##n); \
    mv ACTUAL, x14; \
    bne ACTUAL, EXPECTED, fail;

#define TEST_JALR_ZERODEST(n) \
test_##n: \
    TEST_NAME(n, ("jalr[rd=x0]")) \
    li TESTNUM, n; \
    LA_ABS(x1, jalr_tgt_##n); \
    jalr x0, 0(x1); \
    nop; \
jalr_tgt_##n: \
    li EXPECTED, 0; \
    mv ACTUAL, x0; \
    bne ACTUAL, EXPECTED, fail;

//-----------------------------------------------------------------------------------------
// Загрузка из памяти
//-----------------------------------------------------------------------------------------
#define TEST_LD_OP(n, inst, result, offset, base) \
    TEST_CASE(n, x14, result, (#inst, "(", #offset, "(", #base, "))"), \
        LA_ABS(x1, base); inst x14, offset(x1))

#define TEST_LD_RD_EQ_RS1(n, inst, result, offset, base) \
    TEST_CASE(n, x1, result, (#inst, "[rd=rs1]"), \
        LA_ABS(x1, base); inst x1, offset(x1))

//Загруженное значение используется следующей инструкцией как rs1 / rs2 (load-use)
#define TEST_LD_DEST_BYPASS(n, k, inst, result, offset, base) \
    TEST_CASE(n, x6, result, (#inst, "[load-use:rd->rs1,nop=", #k, "]"), \
        SCRUB LA_ABS(x1, base); inst x14, offset(x1); NOPS(k) addi x6, x14, 0)

#define TEST_LD_DEST_BYPASS2(n, k, inst, result, offset, base) \
    TEST_CASE(n, x6, result, (#inst, "[load-use:rd->rs2,nop=", #k, "]"), \
        SCRUB LA_ABS(x1, base); inst x14, offset(x1); NOPS(k) add x6, x0, x14)

//Базовый адрес вычислен непосредственно перед загрузкой
#define TEST_LD_SRC1_BYPASS(n, k, inst, result, offset, base) \
    TEST_CASE(n, x14, result, (#inst, "[fwd:rs1,nop=", #k, "]"), \
        SCRUB LA_ABS(x1, base); NOPS(k) inst x14, offset(x1))

#define TEST_LD_ZERODEST(n, inst, offset, base) \
    TEST_CASE(n, x0, 0, (#inst, "[rd=x0]"), \
        LA_ABS(x1, base); inst x0, offset(x1))

//-----------------------------------------------------------------------------------------
// Запись в память (проверяется обратным чтением)
//-----------------------------------------------------------------------------------------
#define TEST_ST_OP(n, ldinst, stinst, result, offset, base) \
    TEST_CASE(n, x14, result, (#stinst, "(", #result, ",", #offset, "(", #base, "))"), \
        LA_ABS(x1, base); li x2, result; stinst x2, offset(x1); ldinst x14, offset(x1))

//Запись части слова не должна портить соседние байты (байтовые стробы)
#define TEST_ST_MERGE(n, stinst, val, offset, base, fill, result) \
    TEST_CASE(n, x14, result, (#stinst, "[lanes](", #val, ",", #offset, ")"), \
        LA_ABS(x1, base); li x3, fill; sw x3, 0(x1); li x2, val; stinst x2, offset(x1); lw x14, 0(x1))

//Данные и адрес вычислены непосредственно перед записью
#define TEST_ST_SRC12_BYPASS(n, k1, k2, ldinst, stinst, result, offset, base) \
    TEST_CASE(n, x14, result, (#stinst, "[fwd:data,addr,nop=", #k1, ",", #k2, "]"), \
        SCRUB li x2, result; NOPS(k1) LA_ABS(x1, base); NOPS(k2) stinst x2, offset(x1); ldinst x14, offset(x1))

#define TEST_ST_SRC21_BYPASS(n, k1, k2, ldinst, stinst, result, offset, base) \
    TEST_CASE(n, x14, result, (#stinst, "[fwd:addr,data,nop=", #k1, ",", #k2, "]"), \
        SCRUB LA_ABS(x1, base); NOPS(k1) li x2, result; NOPS(k2) stinst x2, offset(x1); ldinst x14, offset(x1))

//Записываемые данные загружены из памяти непосредственно перед записью
#define TEST_ST_LOAD_DATA(n, k, ldinst, stinst, result, offset, base, src) \
    TEST_CASE(n, x14, result, (#stinst, "[load-use:data,nop=", #k, "]"), \
        SCRUB LA_ABS(x3, src); li x2, result; sw x2, 0(x3); li x2, 0; LA_ABS(x1, base); \
        lw x2, 0(x3); NOPS(k) stinst x2, offset(x1); ldinst x14, offset(x1))

#endif /* RISCV_TEST_H */
