/*
 ******************************************************************************
 * @file        tim.c
 * @author		nagaeff
 * @device		AskoRV32
 * @brief       Драйвер модуля простого таймера
 *****************************************************************************************
 */

#include "tim.h"

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


