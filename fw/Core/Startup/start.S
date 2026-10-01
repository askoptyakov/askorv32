/*
 *****************************************************************************************
 * @file		start.S
 * @author		Alexander Koptyakov
 * @device		AskoRV32
 * @brief		Ассемблерный код инициализации процессора и таблица векторов прерываний
 *****************************************************************************************
 */

	.option arch, +zicsr

	.section .text.init, "ax", @progbits
	.globl start
	.global main

start:
	.option push
	.option norelax
	la gp, __global_pointer$
	.option pop
	la sp, _estack

	/* Ловушки: векторный режим (mtvec.MODE = 1). Прерывание с кодом N -> __vector_table + 4*N,
	   исключения -> __vector_table. Прерывания разрешает программа (mie, mstatus.MIE) */
	la t0, __vector_table
	ori t0, t0, 1
	csrw mtvec, t0

	/* Инициализация секции bss нулевыми значениями */
	la a0, _sbss
	la a1, _ebss
	bge a0, a1, end_init_bss
loop_init_bss:
	sw zero, 0(a0)
	addi a0, a0, 4
	blt a0, a1, loop_init_bss
end_init_bss:

	/* Переход в функцию main */
	call main
1:	j 1b

/*
 *****************************************************************************************
 * Таблица векторов: 64 входа по 4 байта (инструкция перехода), выравнивание 256 байт.
 * Вход 0 - все исключения, вход N (1..31) - прерывание с кодом mcause N,
 * вход 32 + S - источник S контроллера PLIC в векторном режиме (mcause 11, см. plic.h).
 *****************************************************************************************
 */
	.section .text.vectors, "ax", @progbits
	/* Выравнивание без relaxation: иначе ассемблер вставляет 124 байта nop под удаление компоновщиком,
	   а диапазон модуля в отладочной информации (.debug_rnglists) остаётся с этой длиной и накрывает
	   начало main - GDB теряет строки main и падает (hw/info/debug.md) */
	.option push
	.option norelax
	.balign 256
	.option pop
	.globl __vector_table
__vector_table:
	j Exception_Handler		/*  0 Исключения */
	j Default_Handler		/*  1 */
	j Default_Handler		/*  2 */
	j MSI_IRQHandler		/*  3 Программное прерывание (CLINT) */
	j Default_Handler		/*  4 */
	j Default_Handler		/*  5 */
	j Default_Handler		/*  6 */
	j MTI_IRQHandler		/*  7 Машинный таймер (CLINT) */
	j Default_Handler		/*  8 */
	j Default_Handler		/*  9 */
	j Default_Handler		/* 10 */
	j MEI_IRQHandler		/* 11 Внешнее прерывание PLIC - только без векторного режима PLIC */
	j Default_Handler		/* 12 */
	j Default_Handler		/* 13 */
	j Default_Handler		/* 14 */
	j Default_Handler		/* 15 */
	j LI0_IRQHandler		/* 16..31 LI0..LI15 - локальные линии (какое устройство на какой - soc.h) */
	j LI1_IRQHandler
	j LI2_IRQHandler
	j LI3_IRQHandler
	j LI4_IRQHandler
	j LI5_IRQHandler
	j LI6_IRQHandler
	j LI7_IRQHandler
	j LI8_IRQHandler
	j LI9_IRQHandler
	j LI10_IRQHandler
	j LI11_IRQHandler
	j LI12_IRQHandler
	j LI13_IRQHandler
	j LI14_IRQHandler
	j LI15_IRQHandler		/* 31 */
	/* 32..63 - источники PLIC в векторном режиме (PLIC_Init): MEI от источника S -> вход 32 + S */
	j Default_Handler		/* 32 Источник 0 не существует */
	.irp n, 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31
	j PLIC_SRC\n\()_IRQHandler	/* 33..63 Источники 1..31 (какое устройство на каком - soc.h) */
	.endr

/*
 * Обработчики по умолчанию. Имена - слабые ссылки: чтобы подключить свой обработчик,
 * достаточно определить функцию с тем же именем (в Си - с атрибутом __IRQ из core_riscv.h).
 * Default_Handler и Default_Exception_Handler останавливают программу в бесконечном цикле:
 * причину можно посмотреть отладчиком в mcause, адрес инструкции - в mepc.
 */
	.section .text
	.balign 4
Default_Handler:
	j Default_Handler
Default_Exception_Handler:
	j Default_Exception_Handler

	.weak Exception_Handler
	.set  Exception_Handler, Default_Exception_Handler

	.macro WEAK_IRQ name
	.weak \name
	.set  \name, Default_Handler
	.endm

	WEAK_IRQ MSI_IRQHandler
	WEAK_IRQ MTI_IRQHandler
	WEAK_IRQ MEI_IRQHandler
	WEAK_IRQ LI0_IRQHandler
	WEAK_IRQ LI1_IRQHandler
	WEAK_IRQ LI2_IRQHandler
	WEAK_IRQ LI3_IRQHandler
	WEAK_IRQ LI4_IRQHandler
	WEAK_IRQ LI5_IRQHandler
	WEAK_IRQ LI6_IRQHandler
	WEAK_IRQ LI7_IRQHandler
	WEAK_IRQ LI8_IRQHandler
	WEAK_IRQ LI9_IRQHandler
	WEAK_IRQ LI10_IRQHandler
	WEAK_IRQ LI11_IRQHandler
	WEAK_IRQ LI12_IRQHandler
	WEAK_IRQ LI13_IRQHandler
	WEAK_IRQ LI14_IRQHandler
	WEAK_IRQ LI15_IRQHandler
	.irp n, 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31
	WEAK_IRQ PLIC_SRC\n\()_IRQHandler
	.endr

.end
