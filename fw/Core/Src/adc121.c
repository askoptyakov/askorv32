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

#if ADC_PRESENT

void ADC121_Init(ADC121_TypeDef *adc, uint32_t div, uint32_t avgsh) {
	adc->CR  &= (ADC121_CR_CSINV | ADC121_CR_CPOL);				//Остановить, прерывания выключить
	while (adc->SR & ADC121_SR_BUSY) ;								//Дождаться конца кадра
	adc->DIV  = (adc->DIV & ~ADC121_DIV_MSK) | (div & ADC121_DIV_MSK);
	adc->AVG  = avgsh;
	adc->PER  = 0U;
	ADC121_ClearFlags(adc, ADC121_SR_DRDY | ADC121_SR_ARDY | ADC121_SR_ERR);
}

void ADC121_SetRate(ADC121_TypeDef *adc, uint32_t hz) {
	uint32_t f = ADC121_GetClock(adc);
	uint32_t per = hz ? (f + hz / 2U) / hz : 0U;
	if (per > 0xFFFFFFU) per = 0xFFFFFFU;
	adc->PER = per;
}

uint32_t ADC121_GetRate(ADC121_TypeDef *adc) {
	uint32_t per = adc->PER, d = adc->DIV;
	/* Кадр: 32 + CSS + QUIET полупериодов SCLK по DIV + 1 тактов и такт запуска */
	uint32_t half = (d & ADC121_DIV_MSK) + 1U;
	uint32_t frame = (32U + ((d >> ADC121_DIV_CSS_POS) & 0xFU) + ((d >> ADC121_DIV_QUIET_POS) & 0xFU)) * half + 1U;
	return ADC121_GetClock(adc) / (per > frame ? per : frame);
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
	/* (код - смещение) в тысячных долях кода * мк-единиц на код / 1e6 = тысячные доли единицы */
	return (int32_t)((((int64_t)code * 1000 - cal.offset_m) * cal.scale_u) / 1000000);
}

int32_t ADC121_Code16ToMilli(ADC121_Cal cal, uint32_t code16) {
	/* (код16 / 16 - смещение) * мк-единиц на код / 1000: в тысячных долях кода * 16 */
	return (int32_t)((((int64_t)code16 * 1000 - (int64_t)cal.offset_m * 16) * cal.scale_u) / 16000000);
}

uint32_t ADC121_MilliToCode16(ADC121_Cal cal, int32_t milli) {
	/* код16 = (milli * 1e6 / scale_u + смещение_m) * 16 / 1000, в пределах 0..4095 * 16 */
	int64_t c = (((int64_t)milli * 16000000) / cal.scale_u + (int64_t)cal.offset_m * 16 + 500) / 1000;
	return (uint32_t)(c < 0 ? 0 : c > 65535 ? 65535 : c);
}

int32_t ADC121_MeanMilli(ADC121_TypeDef *adc, ADC121_Cal cal) {
	uint32_t sh = adc->AVG & 0xFU;
	/* Сумма 2^sh отсчётов в тысячных долях кода за вычетом смещения */
	int64_t sum_m = (int64_t)adc->SUM * 1000 - ((int64_t)cal.offset_m << sh);
	return (int32_t)(((sum_m * cal.scale_u) / 1000000) >> sh);
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

#endif /* ADC_PRESENT */
