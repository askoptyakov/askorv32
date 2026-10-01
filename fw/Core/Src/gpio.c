/*
 ******************************************************************************
 * @file        gpio.с
 * @author		Alexander Koptyakov
 * @device		AskoRV32
 * @brief       Драйвер модуля дискретного входа/выхода
 *****************************************************************************************
 */

#include "gpio.h"

#if GPIO_PRESENT

void GPIO_Init(void) {
	GPIO->MODE = 0;
	GPIO->OUT  = 0;
	GPIO->IN   = 0;
}

#endif /* GPIO_PRESENT */
