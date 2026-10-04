/*
 ******************************************************************************
 * @file        pireg.c
 * @author		Alexander Koptyakov
 * @device		AskoRV32
 * @brief       Драйвер ПИ-регулятора (блок PIREG)
 *****************************************************************************************
 */

#include "pireg.h"

#if PIREG_PRESENT

void PIREG_Init(PIREG_TypeDef *pi, uint32_t kp, uint32_t ki, uint32_t omax) {
	pi->CR   = 0U;											//Стоп: шагов по прямой связи нет
	while (pi->SR & PIREG_SR_BUSY) ;
	pi->CR   = PIREG_CR_CLR;									//INT = 0, OUT = 0
	pi->KP   = kp & 0xFFFFU;
	pi->KI   = ki & 0xFFFFU;
	pi->OMAX = omax & 0xFFFFU;
	pi->SR   = PIREG_SR_RDY;
}

uint32_t PIREG_Step(PIREG_TypeDef *pi, uint32_t fb) {
	while (pi->SR & PIREG_SR_BUSY) ;
	pi->SR = PIREG_SR_RDY;
	pi->FB = fb & 0xFFFFU;
	pi->CR |= PIREG_CR_STEP;
	if (!(pi->SR & PIREG_SR_RUN)) return 0U;				//Вход run = 0: регулятор стоит
	while (!(pi->SR & PIREG_SR_RDY)) ;						//Шаг - 5 тактов
	return pi->OUT & 0xFFFFU;
}

#endif /* PIREG_PRESENT */
