/*
 *****************************************************************************************
 * @file        priv_test.h
 * @device      AskoRV32
 * @brief       Общие определения тестов привилегированной части: адреса CLINT и таймера тестбенча,
 *              проверки диапазона. Регистры x20..x27 зарезервированы за обработчиками
 *              ловушек, тесты их не используют.
 *****************************************************************************************
 */
#ifndef PRIV_TEST_H
#define PRIV_TEST_H

#define CLINT_MSIP      0x02000000
#define CLINT_MTIMECMP  0x02004000
#define CLINT_MTIME     0x0200BFF8

//Таймер тестбенча (tb_core.sv, порт периферии cpu): модель таймера STIM без предделителя и режимов.
//Тесты ядра не зависят от периферии платы, поэтому прерывание LI0 и источник 1 PLIC даёт он
#define TBTIM_BASE      0x1F000100
#define TBTIM_PR         0x00
#define TBTIM_CR         0x04
#define TBTIM_PER        0x08
#define TBTIM_CNT        0x10
#define TBTIM_SR         0x14
#define TBTIM_CR_EN      (1 << 3)
#define TBTIM_CR_UIE     (1 << 4)

#define MIP_MSIP        (1 << 3)
#define MIP_MTIP        (1 << 7)
#define MIP_LI0         (1 << 16)

//Проверка reg <= max (без знака)
#define TEST_LEU(n, reg, max, name) \
test_##n: \
    TEST_NAME(n, name) \
    li TESTNUM, n; \
    li EXPECTED, max; \
    mv ACTUAL, reg; \
    bgtu ACTUAL, EXPECTED, fail;

//Проверка reg >= min (без знака)
#define TEST_GEU(n, reg, min, name) \
test_##n: \
    TEST_NAME(n, name) \
    li TESTNUM, n; \
    li EXPECTED, min; \
    mv ACTUAL, reg; \
    bltu ACTUAL, EXPECTED, fail;

//Проверка регистров на равенство
#define TEST_EQ_REG(n, reg, refreg, name) \
test_##n: \
    TEST_NAME(n, name) \
    li TESTNUM, n; \
    mv EXPECTED, refreg; \
    mv ACTUAL, reg; \
    bne ACTUAL, EXPECTED, fail;

#endif /* PRIV_TEST_H */
