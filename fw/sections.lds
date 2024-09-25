/*
 *****************************************************************************************************************
 * @file		sections.lds
 * @author		Alexander Koptyakov
 * @device		AskoRV32
 * @brief		Linking script for MCU boot from and run in IMEM
 ******************************************************************************************************************
 */
 
 /* Entry Point */
ENTRY(start)

/* MCU boot from and run in IMEM*/
/*
 * IMEM size : 8KB
 */
MEMORY
{
    IMEM : ORIGIN = 0x00000000, LENGTH = 8K   /* LENGTH based on hardware configuration of ITCM size */
}

SECTIONS {
    .text :
    {
        . = ALIGN(4);
        *(.text.unlikely .text.unlikely.*)
        *(.text.startup .text.startup.*)
        *(.text)           /* .text sections (code) */
        *(.text*)          /* .text* sections (code) */
        . = ALIGN(4);
    } >IMEM	
}
