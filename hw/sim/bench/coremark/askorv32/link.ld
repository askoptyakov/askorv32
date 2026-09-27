/*
 *****************************************************************************************
 * @file        link.ld
 * @device      AskoRV32 (моделирование tb_core)
 * @brief       Компоновка бенчмарков. Ядро гарвардское: загрузки читают только DMEM,
 *              поэтому константы (.rodata) размещаются в DMEM, а не рядом с кодом.
 *****************************************************************************************
 */
OUTPUT_ARCH(riscv)
ENTRY(_start)

MEMORY
{
    IMEM (rx) : ORIGIN = 0x00000000, LENGTH = 32K
    DMEM (rw) : ORIGIN = 0x10000000, LENGTH = 8K
}

SECTIONS
{
    .text : { *(.text.init) *(.text*) } > IMEM
    .data : {
        *(.rodata*) *(.data*)
        /* Малые данные рядом: доступ одной инструкцией относительно gp (linker relaxation) */
        __global_pointer$ = . + 0x800;
        *(.srodata*) *(.sdata*)
    } > DMEM
    .bss (NOLOAD) : {
        . = ALIGN(4); _sbss = .;
        *(.sbss*) *(.bss*) *(COMMON)
        . = ALIGN(4); _ebss = .;
    } > DMEM
    _estack = ORIGIN(DMEM) + LENGTH(DMEM);
    ASSERT(_estack - _ebss >= 1024, "DMEM: на стек остаётся меньше 1 кБайт")
}
