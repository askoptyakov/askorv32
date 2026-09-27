/*
 *****************************************************************************************
 * @file        link.ld
 * @device      AskoRV32
 * @brief       Компоновка тестовых программ: IMEM и DMEM по 8 кБайт (BSRAM, как в top.sv)
 *****************************************************************************************
 */
OUTPUT_ARCH(riscv)
ENTRY(_start)

MEMORY
{
    IMEM (rx) : ORIGIN = 0x00000000, LENGTH = 8K
    DMEM (rw) : ORIGIN = 0x10000000, LENGTH = 8K
}

SECTIONS
{
    .text : { *(.text.init) *(.text*) } > IMEM
    .data : { *(.data*) *(.sdata*) *(.rodata*) *(.srodata*) } > DMEM
    .bss (NOLOAD) : { *(.bss*) *(.sbss*) *(COMMON) } > DMEM
    /* .testnames - неразмещаемая секция с именами тестов, остаётся в ELF как есть */
}
