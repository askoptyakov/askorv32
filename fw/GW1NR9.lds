/*
 *****************************************************************************************************************
 * @file		sections.lds
 * @author		Alexander Koptyakov
 * @device		GOWIN GW1NR-9
 * @brief		Linking script for MCU boot from and run in IMEM
 ******************************************************************************************************************
 */
 
 
ENTRY(start) 		 /* ����� ����� */

_stack_size = 0x100; /* ��������� ����� ����� */

MEMORY 				 /* ����������� ���� � ������� ������ */
{
    IMEM : ORIGIN = 0x00000000, LENGTH = 32K   /* ������������ � ������ ������ ���������� IMEM */
    DMEM : ORIGIN = 0x10000000, LENGTH = 32K   /* ������������ � ������ ������ ������     DMEM */
}

SECTIONS {			/* �������� ������ ������ */
    .text :
    {
        . = ALIGN(4);
        *(.text)           /* .text sections (code) */
        *(.text*)          /* .text* sections (code) */
        *(.rodata)         /* .rodata sections (constants, strings, etc.) */
        *(.rodata*)        /* .rodata* sections (constants, strings, etc.) */
        *(.srodata)        /* .rodata sections (constants, strings, etc.) */
        *(.srodata*)       /* .rodata* sections (constants, strings, etc.) */
        
        . = ALIGN(4);
    	_etext = .;
    } >IMEM
    
    .data : AT (LOADADDR(.text) + LENGTH(IMEM))
    {
        . = ALIGN(4);
        _sdata = .; 
        *(.data)           /* .data sections */
        *(.data*)          /* .data* sections */
        *(.sdata)           /* .sdata sections */
        *(.sdata*)          /* .sdata* sections */
        
        . = ALIGN(4);
    	_edata = .;
    	PROVIDE(__global_pointer$ = _sdata + 0x7F0);
    } >DMEM
     
    .bss :
    {
        . = ALIGN(4);
        _sbss = .;         /* define a global symbol at bss start; used by startup code */
        *(.bss)
        *(.bss*)
        *(.sbss)
        *(.sbss*)
        *(COMMON)

        . = ALIGN(4);
        _ebss = .;         /* define a global symbol at bss end; used by startup code */
    } >DMEM
    
	.stack :
	{
	  . = ALIGN(16);
	  PROVIDE(_sstack = .);
	  . = _stack_size;
	  . = ALIGN(16);
	  PROVIDE(_estack = .);
	} >DMEM
    
}
