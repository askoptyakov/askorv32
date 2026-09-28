/*
 ******************************************************************************
 * @file        plic.c
 * @author      Alexander Koptyakov
 * @device      AskoRV32
 * @brief       Драйвер PLIC: инициализация и диспетчер внешнего прерывания MEI
 *****************************************************************************************
 */

#include "core_riscv.h"
#include "plic.h"

/* Обработчик по умолчанию: источник без обработчика запрещается, иначе запрос по уровню
   вызывал бы прерывание снова и снова */
static uint32_t plic_current_id;

void PLIC_Default_Handler(void) {
	PLIC_Disable((PLIC_SRC_Type)plic_current_id);
}

#define PLIC_WEAK	__attribute__((weak, alias("PLIC_Default_Handler")))
void PLIC_STIM_IRQHandler(void) PLIC_WEAK;
void PLIC_SRC2_IRQHandler(void) PLIC_WEAK;
void PLIC_SRC3_IRQHandler(void) PLIC_WEAK;
void PLIC_SRC4_IRQHandler(void) PLIC_WEAK;
void PLIC_SRC5_IRQHandler(void) PLIC_WEAK;
void PLIC_SRC6_IRQHandler(void) PLIC_WEAK;
void PLIC_SRC7_IRQHandler(void) PLIC_WEAK;
void PLIC_SRC8_IRQHandler(void) PLIC_WEAK;

/* Таблица обработчиков: индекс - номер источника (0 не используется) */
static void (* const plic_handlers[PLIC_NUM_SOURCES + 1])(void) = {
	0,
	PLIC_STIM_IRQHandler,	//1 - таймер STIM
	PLIC_SRC2_IRQHandler,	//2..8 - для новой периферии (UART, SPI...)
	PLIC_SRC3_IRQHandler,
	PLIC_SRC4_IRQHandler,
	PLIC_SRC5_IRQHandler,
	PLIC_SRC6_IRQHandler,
	PLIC_SRC7_IRQHandler,
	PLIC_SRC8_IRQHandler,
};

void PLIC_Init(void) {
	PLIC->ENABLE = 0;
	PLIC->THRESHOLD = 0;
	for (uint32_t i = 1; i <= PLIC_NUM_SOURCES; i++)
		PLIC->PRIORITY[i] = 0;
}

/* Внешнее прерывание: обслужить все ожидающие источники по порядку приоритета */
__IRQ void MEI_IRQHandler(void) {
	uint32_t id;
	while ((id = PLIC_Claim()) != 0) {
		plic_current_id = id;
		if (id <= PLIC_NUM_SOURCES)
			plic_handlers[id]();
		PLIC_Complete(id);
	}
}
