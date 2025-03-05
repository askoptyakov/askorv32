/*
 ******************************************************************************
 * @file        gpio.h
 * @author		Alexander Koptyakov
 * @device		AskoRV32
 * @brief       Драйвер модуля дискретного входа/выхода
 *****************************************************************************************
 */

#ifndef __GPIO_H
#define __GPIO_H

#include "periphery.h"

typedef enum
{
  GPIO_MODE_INPUT = 0,
  GPIO_MODE_OUTPUT
} GPIO_PinDirection;

typedef enum
{
  GPIO_PIN_RESET = 0,
  GPIO_PIN_SET
} GPIO_PinState;

typedef enum
{
  GPIO_LED0 = 0,
  GPIO_LED1,
  GPIO_LED2,
  GPIO_LED3,
  GPIO_LED4,
  GPIO_LED5,
  GPIO_GMB_DI1,
  GPIO_GMB_DI2,
  GPIO_GMB_DI3,
  GPIO_GMB_DO1,
  GPIO_GMB_DO2,
  GPIO_GMB_DO3,
  GPIO_GMB_DRE_G1,
  GPIO_GMB_DRE_G2
} GPIO_PinName;

void GPIO_Init(void);

__INLINE void GPIO_PinMode(GPIO_PinName GPIO_Pin, GPIO_PinDirection PinDir) {
	if (PinDir) GPIO->MODE |=  (1 << GPIO_Pin);
	else		GPIO->MODE &= ~(1 << GPIO_Pin);
}

__INLINE void GPIO_WritePin(GPIO_PinName GPIO_Pin, GPIO_PinState PinState) {
	if (PinState) GPIO->OUT |=  (1 << GPIO_Pin);
	else		  GPIO->OUT &= ~(1 << GPIO_Pin);
}

__INLINE GPIO_PinState GPIO_ReadPin(GPIO_PinName GPIO_Pin) {
	return (GPIO->IN >> GPIO_Pin) & 0x1;
}

__INLINE void GPIO_PinsMode(uint32_t PinsDir) {
	GPIO->MODE = PinsDir;
}

__INLINE void GPIO_WritePins(uint32_t PinsState) {
	GPIO->OUT = PinsState;
}

__INLINE uint32_t GPIO_ReadPins(void) {
	return GPIO->IN;
}

#endif /* __GPIO_H */
