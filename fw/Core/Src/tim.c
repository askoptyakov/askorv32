/*
 ******************************************************************************
 * @file        tim.c
 * @author		nagaeff
 * @device		AskoRV32
 * @brief       Драйвер модуля простого таймера
 *****************************************************************************************
 */

#include "tim.h"

#if STIM_PRESENT

void STIM_Init(void) {

	STIM->CR_EN = 0;

	/* Set the Prescaler value */
	STIM->PR = STIM_PRESCALER;

	/* Set the Period value */
	STIM->PER = STIM_PERIOD;

	/* Set the Autoreload value */
	STIM->CR_ARP = STIM_AUTO_RELOAD_PRELOAD;

	/* Select the Counter Mode */
	STIM->CR_CM = STIM_COUNTER_MODE;

}

/* Периодический режим: счёт вверх, событие обновления каждые (Prescaler + 1) * (Period + 1)
   тактов SYSCLK_HZ. Таймер не запускается - см. STIM_STATE(TIM_ENABLE) */
void STIM_InitPeriodic(uint32_t Prescaler, uint32_t Period) {

	STIM->CR  = 0;
	STIM->PR  = Prescaler;
	STIM->PER = Period;
	STIM->CR_CM = STIM_COUNTER_MODE_UP;
	STIM_CLEAR_FLAG_UPDATE();

}

#endif /* STIM_PRESENT */
