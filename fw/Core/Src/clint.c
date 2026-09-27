/*
 ******************************************************************************
 * @file        clint.c
 * @author      Alexander Koptyakov
 * @device      AskoRV32
 * @brief       Драйвер CLINT: машинный таймер и программное прерывание
 *****************************************************************************************
 */

#include "clint.h"

void CLINT_Delay(uint64_t ticks) {
	uint64_t start = CLINT_GetTime();
	while ((CLINT_GetTime() - start) < ticks);
}
