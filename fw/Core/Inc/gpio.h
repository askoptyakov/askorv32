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

/* Регистры GPIO */
typedef struct
{
  __IO uint32_t MODE;  	//0x00: Регистр выбора режима вход/выход порта
  __IO uint32_t  OUT;   //0x04: Регистр выходных данных порта
  __IO uint32_t   IN;  	//0x08: Регистр входных данных порта
} GPIO_TypeDef;

#if GPIO_PRESENT	//Блок есть в ПЛИС (soc.h)

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

//Номер линии GPIO. Имена линий (<ЦЕПЬ>_PIN, <ЦЕПЬ>_PORT) создаёт конфигуратор ПЛИС в soc.h
//по именам цепей: цепь LED3 - LED3_PIN и LED3_PORT
typedef uint32_t GPIO_PinName;

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

/* Любой блок GPIO: порт (указатель на блок) и номер линии */
__INLINE void GPIO_PortPinMode(GPIO_TypeDef *Port, GPIO_PinName Pin, GPIO_PinDirection PinDir) {
	if (PinDir) Port->MODE |=  (1U << Pin);
	else		Port->MODE &= ~(1U << Pin);
}

__INLINE void GPIO_PortWritePin(GPIO_TypeDef *Port, GPIO_PinName Pin, GPIO_PinState PinState) {
	if (PinState) Port->OUT |=  (1U << Pin);
	else		  Port->OUT &= ~(1U << Pin);
}

__INLINE GPIO_PinState GPIO_PortReadPin(GPIO_TypeDef *Port, GPIO_PinName Pin) {
	return (Port->IN >> Pin) & 0x1;
}

__INLINE void GPIO_PortTogglePin(GPIO_TypeDef *Port, GPIO_PinName Pin) {
	Port->OUT ^= (1U << Pin);
}

/* По имени цепи из конфигуратора ПЛИС (soc.h): GPIO_WRITE(LED3, GPIO_PIN_SET), GPIO_TOGGLE(LED3).
   Шина (цепи LED[0], LED[1]...): GPIO_WRITE_BUS(LED, 0x15) - значение в разряды шины, остальные
   линии блока не меняются; GPIO_READ_BUS(LED); GPIO_MODE_BUS(LED, GPIO_MODE_OUTPUT) */
#define GPIO_MODE(name, dir)		GPIO_PortPinMode(name##_PORT, name##_PIN, dir)
#define GPIO_WRITE(name, state)		GPIO_PortWritePin(name##_PORT, name##_PIN, state)
#define GPIO_READ(name)				GPIO_PortReadPin(name##_PORT, name##_PIN)
#define GPIO_TOGGLE(name)			GPIO_PortTogglePin(name##_PORT, name##_PIN)
#define GPIO_WRITE_BUS(name, value)	((name##_PORT)->OUT = ((name##_PORT)->OUT & ~name##_MSK) | \
									 (((uint32_t)(value) << name##_POS) & name##_MSK))
#define GPIO_READ_BUS(name)			(((name##_PORT)->IN & name##_MSK) >> name##_POS)
#define GPIO_MODE_BUS(name, dir)	((name##_PORT)->MODE = (dir) ? ((name##_PORT)->MODE | name##_MSK) : \
															((name##_PORT)->MODE & ~name##_MSK))


#endif /* GPIO_PRESENT */
#endif /* __GPIO_H */
