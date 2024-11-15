/*
 ******************************************************************************
 * @file        tm1638.h
 * @author		Alexander Koptyakov
 * @device		AskoRV32
 * @brief       Драйвер модуля связи с контроллером TM1638
 *****************************************************************************************
 */

#ifndef __TM1638_H
#define __TM1638_H

#include "periphery.h"

typedef enum
{
  TM1638_PIN_RESET = 0,
  TM1638_PIN_SET
} TM1638_LedState;

typedef enum
{
  TM1638_LED0 = 0,
  TM1638_LED1,
  TM1638_LED2,
  TM1638_LED3,
  TM1638_LED4,
  TM1638_LED5,
  TM1638_LED6,
  TM1638_LED7
} TM1638_LedName;

typedef enum
{
  TM1638_KEY0 = 0,
  TM1638_KEY1,
  TM1638_KEY2,
  TM1638_KEY3,
  TM1638_KEY4,
  TM1638_KEY5,
  TM1638_KEY6,
  TM1638_KEY7,
} TM1638_KeyName;

void TM1638_Init(void);

__INLINE void TM1638_WriteSegs(uint32_t data) {
	TM1638->SEGS = data;
}

__INLINE void TM1638_WriteLeds(uint32_t data) {
	TM1638->LEDS = data;
}

__INLINE uint32_t TM1638_ReadKeys(void) {
	return TM1638->KEYS;
}

__INLINE void TM1638_WriteLed(TM1638_LedName led, TM1638_LedState state) {
	if (state) TM1638->LEDS |=  (1 << led);
	else	   TM1638->LEDS &= ~(1 << led);
}

__INLINE uint32_t TM1638_ReadKey(TM1638_KeyName key) {
	return (TM1638->KEYS >> key) & 0x1;
}

#endif /* __TM1638_H */
