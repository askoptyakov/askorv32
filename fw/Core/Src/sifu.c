/*
 ******************************************************************************
 * @file        sifu.c
 * @author		Alexander Koptyakov
 * @device		AskoRV32
 * @brief       Драйвер СИФУ трёхфазного мостового тиристорного выпрямителя (блок SIFU)
 *****************************************************************************************
 */

#include "sifu.h"

#if SIFU_PRESENT

void SIFU_Init(void) {
	SIFU->CR     = SIFU_CR_DBL | SIFU_CR_FLT;		//Импульсы выключены, имитатор выключен
	SIFU->ALPHA  = SIFU_ALPHA_OFF;
	SIFU->DIV    = SIFU_DIV_DEFAULT;
	SIFU->DELAY  = SIFU_DELAY_DEFAULT;
	SIFU->WIDTH  = SIFU_WIDTH_DEFAULT;
	SIFU_ClearFlags(SIFU_SR_SYNCF | SIFU_SR_LOSSF);
}

uint32_t SIFU_AlphaMax(void) {
	uint32_t used = SIFU->DELAY + SIFU->WIDTH;
	return (used < SIFU_SAW_MAX) ? SIFU_SAW_MAX - 1U - used : 0U;
}

void SIFU_SetAlpha(uint32_t ticks) {
	uint32_t max = SIFU_AlphaMax();
	SIFU->ALPHA = (ticks > max) ? max : ticks;
}

uint32_t SIFU_SawHz(void) {
	return SYSCLK_HZ / (SIFU->DIV + 1U);
}

uint32_t SIFU_HalfPeriod(void) {
	uint32_t h = SIFU->HPER;
	/* Измерение годно, когда синхронизация есть и полупериод в разумных пределах (после сброса
	   и при пропадании сети HPER - 65535) */
	if (!SIFU_SyncLost() && h > 0U && h < SIFU_LOST_TICKS) return h;
	return SIFU_SawHz() / 100U;							//Полупериод 50 Гц - 10 мс
}

uint32_t SIFU_GridFreq100(void) {
	uint32_t h = SIFU->HPER;
	if (SIFU_SyncLost() || h == 0U || h >= SIFU_LOST_TICKS) return 0U;
	/* f = SawHz / (2 * h); сотые доли Гц: SawHz * 50 / h, с округлением */
	return (uint32_t)(((uint64_t)SIFU_SawHz() * 50U + h / 2U) / h);
}

uint32_t SIFU_Deg10ToTicks(uint32_t deg10) {
	/* 180 град. = полупериод: ticks = deg10 * h / 1800 */
	return (deg10 * SIFU_HalfPeriod() + 900U) / 1800U;
}

uint32_t SIFU_TicksToDeg10(uint32_t ticks) {
	uint32_t h = SIFU_HalfPeriod();
	return (ticks * 1800U + h / 2U) / h;
}

void SIFU_SetAlphaDeg10(uint32_t deg10) {
	SIFU_SetAlpha(SIFU_Deg10ToTicks(deg10));
}

uint32_t SIFU_GetAlphaDeg10(void) {
	return SIFU_TicksToDeg10(SIFU->ALPHA);
}

void SIFU_SimStart(uint32_t freq100, uint32_t dz_deg10) {
	/* Сектор 60 град. = период / 6: SawHz / (6 * f) = SawHz * 100 / (6 * freq100) тиков */
	uint32_t sect = (uint32_t)(((uint64_t)SIFU_SawHz() * 100U + 3U * freq100) / (6U * freq100));
	uint32_t dz;
	if (sect > SIFU_SIM_SECT_MSK) sect = SIFU_SIM_SECT_MSK;
	if (sect < 2U) sect = 2U;
	dz = (dz_deg10 * sect + 300U) / 600U;				//Сектор - 600 десятых долей градуса
	if (dz >= sect / 2U) dz = sect / 2U - 1U;
	SIFU->CR    &= ~SIFU_CR_SIM;						//Имитатор с начала периода
	SIFU->SIMCFG = (dz << SIFU_SIM_DZ_POS) | sect;
	SIFU->CR    |= SIFU_CR_SIM;
}

#endif /* SIFU_PRESENT */
