/*
 ******************************************************************************
 * @file        tim.h
 * @author		nagaeff
 * @device		AskoRV32
 * @brief       Драйвер модуля простого таймера
 *****************************************************************************************
 */

#ifndef __TIM_H
#define __TIM_H

#include "periphery.h"

typedef enum
{
  TIM_DISABLE = 0,
  TIM_ENABLE
} STIM_State;

/*  Настройки режима таймера  */
#define STIM_COUNTER_MODE_UP          0x00000000U
#define STIM_COUNTER_MODE_DOWN        0x00000001U
#define STIM_COUNTER_MODE_UP_DOWN     0x00000010U

/*  Прототипы функций  */
void STIM_Init(void);


__INLINE void STIM_STATE(STIM_State TimState) {
	STIM->CR_EN = TimState;
}

__INLINE uint32_t STIM_GET_COUNT(void) {
	return STIM->CNT;
}

__INLINE void STIM_SET_PRESCALER(uint32_t Prescaler) {
	STIM->PR = Prescaler;
}

__INLINE void STIM_SET_PERIOD(uint32_t Period) {
	STIM->PER = Period;
}

__INLINE void STIM_SET_COUNTER_MODE(uint32_t Mode) {
	STIM->CR_CM = Mode;
}

#endif /* __TIM_H */
