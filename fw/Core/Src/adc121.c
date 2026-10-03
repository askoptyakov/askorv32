/*
 ******************************************************************************
 * @file        adc121.c
 * @author		Alexander Koptyakov
 * @device		AskoRV32
 * @brief       Драйвер АЦП ADC121S051 (блок ADC121): платы ADC_V и ADC_C
 *****************************************************************************************
 */

#include "adc121.h"
#include "core_riscv.h"

#if ADC121_PRESENT

void ADC121_Init(ADC121_TypeDef *adc, uint32_t div, uint32_t avgsh) {
	adc->CR  &= ADC121_CR_CSINV;									//Остановить, прерывания выключить
	while (adc->SR & ADC121_SR_BUSY) ;								//Дождаться конца кадра
	adc->DIV  = (adc->DIV & ~ADC121_DIV_MSK) | (div & ADC121_DIV_MSK);
	adc->AVG  = avgsh;
	adc->PER  = 0U;
	ADC121_ClearFlags(adc, ADC121_SR_DRDY | ADC121_SR_ARDY | ADC121_SR_ERR);
}

void ADC121_SetRate(ADC121_TypeDef *adc, uint32_t hz) {
	uint32_t per = hz ? (SYSCLK_HZ + hz / 2U) / hz : 0U;
	if (per > 0xFFFFFFU) per = 0xFFFFFFU;
	adc->PER = per;
}

uint32_t ADC121_GetRate(ADC121_TypeDef *adc) {
	uint32_t per = adc->PER, d = adc->DIV;
	/* Кадр: 32 + CSS + QUIET полупериодов SCLK по DIV + 1 тактов и такт запуска */
	uint32_t half = (d & ADC121_DIV_MSK) + 1U;
	uint32_t frame = (32U + ((d >> ADC121_DIV_CSS_POS) & 0xFU) + ((d >> ADC121_DIV_QUIET_POS) & 0xFU)) * half + 1U;
	return SYSCLK_HZ / (per > frame ? per : frame);
}

uint32_t ADC121_ReadSingle(ADC121_TypeDef *adc) {
	uint64_t end = CORE_GetCycles() + SYSCLK_HZ / 1000U;		//Тайм-аут 1 мс (кадр - около 3 мкс)
	uint32_t sr;
	ADC121_ClearFlags(adc, ADC121_SR_DRDY | ADC121_SR_ERR);
	adc->CR |= ADC121_CR_START;
	do {
		sr = adc->SR;
		if (CORE_GetCycles() > end) return ADC121_ERROR;
	} while (!(sr & (ADC121_SR_DRDY | ADC121_SR_ERR)));
	return (sr & ADC121_SR_ERR) ? ADC121_ERROR : ADC121_GetRaw(adc);
}

int32_t ADC121_ToMilli(ADC121_Cal cal, uint32_t code) {
	return (int32_t)(((int64_t)((int32_t)code - cal.offset) * cal.scale_u) / 1000);
}

int32_t ADC121_MeanMilli(ADC121_TypeDef *adc, ADC121_Cal cal) {
	uint32_t sh = adc->AVG & 0xFU;
	int64_t sum = (int64_t)adc->SUM - ((int64_t)cal.offset << sh);	//Сумма за вычетом смещения
	return (int32_t)((sum * cal.scale_u / 1000) >> sh);
}

uint32_t ADC121_Capture(ADC121_TypeDef *adc, uint16_t *buf, uint32_t n) {
	uint64_t end = CORE_GetCycles() + SYSCLK_HZ;					//Тайм-аут 1 с
	uint32_t i = 0;
	ADC121_ClearFlags(adc, ADC121_SR_DRDY);
	while (i < n) {
		uint32_t sr = adc->SR;
		if (sr & ADC121_SR_DRDY) {
			adc->SR = ADC121_SR_DRDY;
			buf[i++] = (uint16_t)ADC121_GetRaw(adc);
		} else if (CORE_GetCycles() > end) break;
	}
	return i;
}

#endif /* ADC121_PRESENT */
