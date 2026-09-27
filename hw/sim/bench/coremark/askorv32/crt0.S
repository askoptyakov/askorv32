/*
 *****************************************************************************************
 * @file        crt0.S
 * @device      AskoRV32 (моделирование tb_core)
 * @brief       Стартовый код бенчмарков: стек, обнуление .bss, main, код завершения
 *****************************************************************************************
 */
#define TOHOST 0x1F000000

    .section .text.init, "ax", @progbits
    .globl _start
_start:
    .option push
    .option norelax
    la   gp, __global_pointer$
    .option pop
    la   sp, _estack
    la   a0, _sbss
    la   a1, _ebss
1:  bgeu a0, a1, 2f
    sw   zero, 0(a0)
    addi a0, a0, 4
    j    1b
2:  call main
    //Код завершения для тестбенча: 1 - программа завершилась (результат проверяет run_bench.py)
    li   t0, TOHOST
    sw   a0, 4(t0)
    li   t1, 1
    sw   t1, 0(t0)
3:  j    3b
