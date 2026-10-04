/*
 ******************************************************************************
 * @file        adc121.h
 * @author		Alexander Koptyakov
 * @device		AskoRV32
 * @brief       Драйвер АЦП ADC121S051 (блок ADC121, hw/src/periph/adc121): платы ADC_V (напряжение)
 *              и ADC_C (ток). У каждой платы свой блок: функции получают указатель на регистры
 *              блока (ADC_V, ADC_C - имена из конфигуратора, soc.h). Пересчёт кода в величину:
 *              (код - OFFSET) * SCALE_U / 1e6, где SCALE_U - мк-единиц (мкВ, мкА) на код, OFFSET -
 *              код при нулевом входе (с дробью: <ИМЯ>_OFFSET_M - тысячные доли кода); оба - из
 *              конфигуратора (<ИМЯ>_SCALE_U, <ИМЯ>_OFFSET_M).
 *              Описание модуля - hw/src/periph/adc121/README.md.
 *
 *              Пример: напряжение платы ADC_V, среднее по 256 отсчётам
 *                ADC121_INIT_DEFAULT(ADC_V);                      //SCLK, усреднение - из soc.h
 *                ADC121_Start(ADC_V);                             //Непрерывные преобразования
 *                int32_t mv = ADC121_MeanMilli(ADC_V, ADC121_CAL(ADC_V));   //мВ
 *****************************************************************************************
 */

#ifndef __ADC121_H
#define __ADC121_H

#include "periphery.h"

/* Регистры блока ADC121 */
typedef struct
{
  __IO uint32_t CR;					//0x00: EN, START, DIE, AIE, EIE, CSINV, CPOL, CIE
  __IO uint32_t DIV;				//0x04: [7:0] DIV (SCLK), [11:8] QUIET, [15:12] CSS
  __IO uint32_t AVG;				//0x08: [3:0] AVGSH - среднее по 2^AVGSH отсчётам
  __IO uint32_t PER;				//0x0C: [23:0] период запуска, тактов блока (FCLK; 0 - непрерывно)
  __I  uint32_t DATA;				//0x10: [11:0] последний отсчёт, [31:16] номер отсчёта
  __I  uint32_t MEAN;				//0x14: [11:0] последнее среднее
  __I  uint32_t SUM;				//0x18: [23:0] сумма 2^AVGSH отсчётов последнего среднего
  __IO uint32_t SR;					//0x1C: DRDY, ARDY, ERR, CMPF (сброс записью 1), BUSY, CMP, [31:16] сырой кадр
  __I  uint32_t CNT;				//0x20: отсчётов без ошибок
  __I  uint32_t FCLK;				//0x24: частота такта блока, Гц (свой rPLL или такт шины; 0 - не задана)
  __I  uint32_t WMEAN;				//0x28: [15:0] среднее за окно, код * 16; [27:16] отсчётов в окне
} ADC121_TypeDef;

/* Биты CR */
#define ADC121_CR_EN				(1U << 0)	//Непрерывные преобразования
#define ADC121_CR_START				(1U << 1)	//Одно преобразование (запись 1)
#define ADC121_CR_DIE				(1U << 2)	//Прерывание по новому отсчёту
#define ADC121_CR_AIE				(1U << 3)	//Прерывание по новому среднему
#define ADC121_CR_EIE				(1U << 4)	//Прерывание по ошибке кадра
#define ADC121_CR_CSINV				(1U << 5)	//Вывод CS инвертирован
#define ADC121_CR_CPOL				(1U << 6)	//Активный уровень входа CMP: 0 - низкий, 1 - высокий
#define ADC121_CR_CIE				(1U << 7)	//Прерывание по срабатыванию CMP
#define ADC121_CR_WIE				(1U << 8)	//Прерывание по новому среднему за окно
#define ADC121_CR_WCLOSE			(1U << 9)	//Закрыть окно усреднения (запись 1)

/* Поля DIV */
#define ADC121_DIV_MSK				0xFFU
#define ADC121_DIV_QUIET_POS		8U
#define ADC121_DIV_CSS_POS			12U

/* Биты SR */
#define ADC121_SR_DRDY				(1U << 0)	//Новый отсчёт
#define ADC121_SR_ARDY				(1U << 1)	//Новое среднее
#define ADC121_SR_ERR				(1U << 2)	//Ошибка кадра: ведущие нули не нули (платы нет, обрыв)
#define ADC121_SR_CMPF				(1U << 3)	//Вход CMP (ADC_C: компаратор защиты) перешёл в активный уровень
#define ADC121_SR_WRDY				(1U << 4)	//Новое среднее за окно
#define ADC121_SR_BUSY				(1U << 8)	//Идёт кадр
#define ADC121_SR_CMP				(1U << 9)	//Вход CMP сейчас активен
#define ADC121_SR_FRAME_POS			16U			//Сырой кадр последнего преобразования

#define ADC121_CODE_MAX				4095U
#define ADC121_ERROR				0xFFFFFFFFU	//ADC121_ReadSingle: ошибка кадра или тайм-аут

#if ADC121_PRESENT	//Блоки есть в ПЛИС (soc.h)

#define __ADC121_INLINE		static inline __attribute__((always_inline))

/* Пересчёт кода: масштаб (мк-единиц на код) и смещение (код при нулевом входе, тысячные доли кода) */
typedef struct
{
  int32_t scale_u;
  int32_t offset_m;
} ADC121_Cal;
/* Пересчёт блока из конфигуратора: ADC121_CAL(ADC_V) -> {ADC_V_SCALE_U, ADC_V_OFFSET_M} */
#define ADC121_CAL(name)			((ADC121_Cal){ name##_SCALE_U, name##_OFFSET_M })

/* Инициализация: преобразования остановлены, делитель SCLK div, среднее по 2^avgsh, PER = 0, флаги
   сброшены; CSINV, CSS и QUIET остаются из конфигуратора (значения после сброса) */
void ADC121_Init(ADC121_TypeDef *adc, uint32_t div, uint32_t avgsh);
/* Инициализация значениями конфигуратора: ADC121_INIT_DEFAULT(ADC_V) */
#define ADC121_INIT_DEFAULT(name)	ADC121_Init(name, name##_DIV_DEFAULT, name##_AVGSH_DEFAULT)

/* Непрерывные преобразования (CR.EN) и их остановка */
__ADC121_INLINE void ADC121_Start(ADC121_TypeDef *adc) { adc->CR |=  ADC121_CR_EN; }
__ADC121_INLINE void ADC121_Stop(ADC121_TypeDef *adc)  { adc->CR &= ~ADC121_CR_EN; }
/* Частота такта блока, Гц: регистр FCLK (свой rPLL, например 96 МГц), если он 0 - такт шины SYSCLK_HZ.
   От неё SCLK = f / (2 * (DIV + 1)) и период запуска PER */
__ADC121_INLINE uint32_t ADC121_GetClock(ADC121_TypeDef *adc) { uint32_t f = adc->FCLK; return f ? f : SYSCLK_HZ; }
/* Частота отсчётов, Гц (0 - максимальная): период запуска PER = ADC121_GetClock / hz */
void ADC121_SetRate(ADC121_TypeDef *adc, uint32_t hz);
/* Отсчётов в секунду: при rate 0 - сколько успевает кадр */
uint32_t ADC121_GetRate(ADC121_TypeDef *adc);
/* Среднее по 2^avgsh отсчётам (0..12); усреднение начинается заново */
__ADC121_INLINE void ADC121_SetAverage(ADC121_TypeDef *adc, uint32_t avgsh) { adc->AVG = avgsh; }

/* Одно преобразование (преобразования должны быть остановлены): код 0..4095 или ADC121_ERROR */
uint32_t ADC121_ReadSingle(ADC121_TypeDef *adc);

/* Последний отсчёт, среднее, сумма, число отсчётов */
__ADC121_INLINE uint32_t ADC121_GetRaw(ADC121_TypeDef *adc)  { return adc->DATA & ADC121_CODE_MAX; }
__ADC121_INLINE uint32_t ADC121_GetMean(ADC121_TypeDef *adc) { return adc->MEAN & ADC121_CODE_MAX; }
__ADC121_INLINE uint32_t ADC121_GetSum(ADC121_TypeDef *adc)  { return adc->SUM; }
__ADC121_INLINE uint32_t ADC121_GetCount(ADC121_TypeDef *adc) { return adc->CNT; }
/* Флаги DRDY, ARDY, ERR и их сброс записью 1 */
#define ADC121_SR_FLAGS				(ADC121_SR_DRDY | ADC121_SR_ARDY | ADC121_SR_ERR | ADC121_SR_CMPF | ADC121_SR_WRDY)
__ADC121_INLINE uint32_t ADC121_GetFlags(ADC121_TypeDef *adc) { return adc->SR & ADC121_SR_FLAGS; }
__ADC121_INLINE void ADC121_ClearFlags(ADC121_TypeDef *adc, uint32_t f) { adc->SR = f & ADC121_SR_FLAGS; }
/* Вход CMP (плата ADC_C - компаратор защиты по мгновенному току): активен сейчас */
__ADC121_INLINE uint32_t ADC121_CmpActive(ADC121_TypeDef *adc) { return (adc->SR & ADC121_SR_CMP) != 0U; }
/* Сырой кадр последнего преобразования (16 бит: 4 ведущих нуля и код) - диагностика */
__ADC121_INLINE uint32_t ADC121_GetFrame(ADC121_TypeDef *adc) { return adc->SR >> ADC121_SR_FRAME_POS; }

/* Прерывания: ADC121_CR_DIE, ADC121_CR_AIE, ADC121_CR_EIE, ADC121_CR_CIE. Источник PLIC - PLIC_SRC_<ИМЯ>,
   обработчик PLIC_<ИМЯ>_IRQHandler (soc.h); в обработчике сбросить флаги */
#define ADC121_CR_IT				(ADC121_CR_DIE | ADC121_CR_AIE | ADC121_CR_EIE | ADC121_CR_CIE | ADC121_CR_WIE)
__ADC121_INLINE void ADC121_IT_Enable(ADC121_TypeDef *adc, uint32_t it)  { adc->CR |=  (it & ADC121_CR_IT); }
__ADC121_INLINE void ADC121_IT_Disable(ADC121_TypeDef *adc, uint32_t it) { adc->CR &= ~(it & ADC121_CR_IT); }

/* Среднее за окно (блок с <ИМЯ>_WIN): отсчёты между закрытиями окна - стробом прямой связи (например,
   начало полуволны СИФУ, SIFU.tick) или ADC121_WindowClose. Значение - код * 16 (4 дробных бита) */
__ADC121_INLINE void ADC121_WindowClose(ADC121_TypeDef *adc) { adc->CR |= ADC121_CR_WCLOSE; }
__ADC121_INLINE uint32_t ADC121_GetWMean(ADC121_TypeDef *adc)  { return adc->WMEAN & 0xFFFFU; }
__ADC121_INLINE uint32_t ADC121_GetWCount(ADC121_TypeDef *adc) { return (adc->WMEAN >> 16) & 0xFFFU; }
/* Код * 16 (среднее за окно, задание регулятора PIREG) <-> тысячные доли единицы (мВ, мА) */
int32_t  ADC121_Code16ToMilli(ADC121_Cal cal, uint32_t code16);
uint32_t ADC121_MilliToCode16(ADC121_Cal cal, int32_t milli);

/* Пересчёт в тысячные доли единицы (мВ, мА): код -> (код - смещение) * scale_u / 1000 */
int32_t ADC121_ToMilli(ADC121_Cal cal, uint32_t code);
/* Среднее в тысячных долях единицы по сумме SUM (точнее одного кода) */
int32_t ADC121_MeanMilli(ADC121_TypeDef *adc, ADC121_Cal cal);
/* Запись n отсчётов подряд в буфер (по флагу DRDY; частота - ADC121_SetRate, не больше ~150 тыс./с при
   опросе программой). Возвращает число записанных отсчётов (меньше n - тайм-аут) */
uint32_t ADC121_Capture(ADC121_TypeDef *adc, uint16_t *buf, uint32_t n);

#endif /* ADC121_PRESENT */
#endif /* __ADC121_H */
