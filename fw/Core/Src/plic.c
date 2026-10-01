/*
 ******************************************************************************
 * @file        plic.c
 * @author      Alexander Koptyakov
 * @device      AskoRV32
 * @brief       Драйвер PLIC: инициализация в векторном режиме (обработчики - см. plic.h)
 *****************************************************************************************
 */

#include "plic.h"

void PLIC_Init(void) {
	PLIC->ENABLE = 0;
	PLIC->THRESHOLD = 0;
	for (uint32_t i = 1; i <= PLIC_NUM_SOURCES; i++)
		PLIC->PRIORITY[i] = 0;
	PLIC->VECTOR = 1;		//MEI от источника S - сразу на вход 32 + S таблицы векторов
}
