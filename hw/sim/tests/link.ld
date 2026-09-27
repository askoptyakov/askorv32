/*
 *****************************************************************************************
 * @file        link.ld
 * @device      AskoRV32
 * @brief       Компоновка тестовых программ. По адресу 0 (вектор сброса) - переход на
 *              _start, код тестов начинается с TEXT_BASE: так тесты можно разместить на
 *              границе кластеров BSRAM (run_tests.py --text-base). Размеры IMEM/DMEM
 *              задаются через --defsym (по умолчанию 8 кБайт, как в top.sv).
 *****************************************************************************************
 */
OUTPUT_ARCH(riscv)
ENTRY(_start)

TEXT_BASE = DEFINED(TEXT_BASE) ? TEXT_BASE : 0;
IMEM_LEN  = DEFINED(IMEM_LEN)  ? IMEM_LEN  : 8K;

MEMORY
{
    IMEM (rx) : ORIGIN = 0x00000000, LENGTH = 32K
    DMEM (rw) : ORIGIN = 0x10000000, LENGTH = 8K
}

SECTIONS
{
    .text : {
        KEEP(*(.reset))
        . = MAX(., TEXT_BASE);
        *(.text.init) *(.text*)
    } > IMEM
    ASSERT(SIZEOF(.text) <= IMEM_LEN, "Программа не помещается в IMEM")
    .data : { *(.data*) *(.sdata*) *(.rodata*) *(.srodata*) } > DMEM
    .bss (NOLOAD) : { *(.bss*) *(.sbss*) *(COMMON) } > DMEM
    /* .testnames - неразмещаемая секция с именами тестов, остаётся в ELF как есть */
}
