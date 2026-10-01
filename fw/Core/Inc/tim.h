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

/* Регистры таймера STIM */
typedef struct
{
  __IO uint32_t PR;    				//0x00: Регистр предделителя системной частоты таймера (PRESCALER), 16 бит
  union {
	  __IO uint32_t CR;  			//0x04: Регистр управления счетчика (CONTROL REG)
	  struct {
		  __IO uint32_t CR_CM	: 2;	// counter mode - выбора напрвление счёта
		  __IO uint32_t CR_ARP 	: 1;    // autoReloadPreload
		  __IO uint32_t CR_EN  	: 1;	// enable - включение таймера
		  __IO uint32_t CR_UIE 	: 1;	// update interrupt enable - разрешение прерывания по событию обновления
	  };
  };
  __IO uint32_t PER;   	  			//0x08: Регистр данных значения переполнения таймера (PERIOD), 16 бит
  __IO uint32_t PUL;         		//0x0C: Регистр значения сравнения (PULSE), 16 бит
  __I  uint32_t CNT;  	      		//0x10: Регистр значения текущего счетчика таймера (COUNT), 16 бит
  __IO uint32_t SR;  	      		//0x14: Регистр состояния (STATUS REG): бит 0 - UIF, сброс записью 1
} STIM_TypeDef;

/* Биты регистров таймера STIM */
#define STIM_SR_UIF					(1U << 0)

/* Настройки таймера при инициализации */
#define STIM_PRESCALER 				(SYSCLK_HZ / 1000U - 1U)	//Тик счётчика - 1 мс (значение не больше 65535)
#define STIM_PERIOD 				100;
#define STIM_COUNTER_MODE 			STIM_COUNTER_MODE_DOWN;
#define STIM_AUTO_RELOAD_PRELOAD 	1;

#if STIM_PRESENT	//Блок есть в ПЛИС (soc.h)

typedef enum
{
  TIM_DISABLE = 0,
  TIM_ENABLE
} STIM_State;

/*  Настройки режима таймера  */
#define STIM_COUNTER_MODE_UP          0x00000000U
#define STIM_COUNTER_MODE_DOWN        0x00000001U
#define STIM_COUNTER_MODE_UP_DOWN     0x00000002U

/*  Прототипы функций  */
void STIM_Init(void);
void STIM_InitPeriodic(uint32_t Prescaler, uint32_t Period);


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

__INLINE void STIM_SET_PULSE(uint32_t Pulse) {
	STIM->PUL = Pulse;
}

/*  Прерывание по событию обновления (переполнение/перезагрузка счётчика)  */
__INLINE void STIM_IT_STATE(STIM_State ItState) {
	STIM->CR_UIE = ItState;
}

__INLINE uint32_t STIM_GET_FLAG_UPDATE(void) {
	return STIM->SR & STIM_SR_UIF;
}

/* Сброс флага записью 1. В обработчике прерывания флаг нужно сбросить, иначе после выхода
   прерывание сразу возникнет снова */
__INLINE void STIM_CLEAR_FLAG_UPDATE(void) {
	STIM->SR = STIM_SR_UIF;
}


#endif /* STIM_PRESENT */
#endif /* __TIM_H */
