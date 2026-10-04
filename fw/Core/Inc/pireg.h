/*
 ******************************************************************************
 * @file        pireg.h
 * @author		Alexander Koptyakov
 * @device		AskoRV32
 * @brief       Драйвер ПИ-регулятора (блок PIREG, hw/src/periph/pireg): типовой блок, один контур.
 *              Работает от процессора (PIREG_Step: обратная связь пишется в FB, шаг командой) или по
 *              прямым связям с другими блоками, настроенным в конфигураторе (обратная связь - среднее
 *              за окно блока ADC121, выход - на угол блока SIFU): тогда процессор только задаёт
 *              уставку, коэффициенты и пределы. Перевода в физические величины в блоке нет: задание -
 *              в единицах обратной связи, выход - в единицах управляемого блока.
 *              Шаг: e = SP - FB; INT = clamp(INT + KI * e, 0, предел << FRAC);
 *              OUT = clamp((KP * e + INT) >> FRAC, 0, предел). Коэффициенты K / 2^FRAC
 *              (<ИМЯ>_FRAC в soc.h, обычно 12: 4096 = 1.0). Описание - hw/src/periph/pireg/README.md.
 *
 *              Пример: регулятор от процессора
 *                PIREG_Init(PI_U, PIREG_GAIN(PI_U, 0.05), PIREG_GAIN(PI_U, 0.02), 3333);
 *                PIREG_SetPoint(PI_U, 1000);
 *                uint32_t u = PIREG_Step(PI_U, fb);     //Шаг с обратной связью fb
 *****************************************************************************************
 */

#ifndef __PIREG_H
#define __PIREG_H

#include "periphery.h"

/* Регистры блока PIREG */
typedef struct
{
  __IO uint32_t CR;					//0x00: EN, STEP, IE, CLR
  __IO uint32_t SP;					//0x04: [15:0] задание, единицы обратной связи
  __IO uint32_t KP;					//0x08: [15:0] KP / 2^FRAC
  __IO uint32_t KI;					//0x0C: [15:0] KI / 2^FRAC (за шаг)
  __IO uint32_t OMAX;				//0x10: [15:0] верхний предел выхода
  __IO uint32_t FB;					//0x14: [15:0] обратная связь (процессор; при прямой связи - fb_i шага)
  __I  uint32_t OUT;				//0x18: [15:0] выход, [31:16] ошибка e последнего шага (со знаком)
  __IO uint32_t SR;					//0x1C: RDY (сброс записью 1), LIM, LOW, RUN, BUSY
  __IO uint32_t INT;				//0x20: интегратор (со знаком), единицы выхода * 2^FRAC
} PIREG_TypeDef;

/* Биты CR */
#define PIREG_CR_EN					(1U << 0)	//Шаг по стробу прямой связи (обратная связь fb)
#define PIREG_CR_STEP				(1U << 1)	//Шаг с FB (запись 1)
#define PIREG_CR_IE					(1U << 2)	//Прерывание по новому выходу (SR.RDY)
#define PIREG_CR_CLR				(1U << 3)	//INT = 0, OUT = 0 (запись 1)

/* Биты SR */
#define PIREG_SR_RDY				(1U << 0)	//Новый выход; сброс записью 1
#define PIREG_SR_LIM				(1U << 1)	//Выход на верхнем пределе (OMAX или вход lim)
#define PIREG_SR_LOW				(1U << 2)	//Выход на нуле
#define PIREG_SR_RUN				(1U << 3)	//Регулятор работает (вход run = 1 или не подключён)
#define PIREG_SR_BUSY				(1U << 8)	//Идёт шаг

#if PIREG_PRESENT	//Блоки есть в ПЛИС (soc.h)

#define __PIREG_INLINE		static inline __attribute__((always_inline))

/* Коэффициент k (число с дробью, константа) в единицах блока name: k * 2^FRAC */
#define PIREG_GAIN(name, k)			((uint32_t)((k) * (double)(1UL << name##_FRAC) + 0.5))

/* Инициализация: стоп (CR = 0), INT = 0, OUT = 0, коэффициенты и предел выхода, флаги сброшены */
void PIREG_Init(PIREG_TypeDef *pi, uint32_t kp, uint32_t ki, uint32_t omax);
__PIREG_INLINE void PIREG_SetPoint(PIREG_TypeDef *pi, uint32_t sp) { pi->SP = sp & 0xFFFFU; }
__PIREG_INLINE void PIREG_SetGains(PIREG_TypeDef *pi, uint32_t kp, uint32_t ki) { pi->KP = kp & 0xFFFFU; pi->KI = ki & 0xFFFFU; }
__PIREG_INLINE void PIREG_SetMax(PIREG_TypeDef *pi, uint32_t omax) { pi->OMAX = omax & 0xFFFFU; }
/* Работа по прямой связи (шаг по каждому новому значению обратной связи) и стоп */
__PIREG_INLINE void PIREG_Enable(PIREG_TypeDef *pi)  { pi->CR |=  PIREG_CR_EN; }
__PIREG_INLINE void PIREG_Disable(PIREG_TypeDef *pi) { pi->CR &= ~PIREG_CR_EN; }
/* Сброс интегратора и выхода */
__PIREG_INLINE void PIREG_Clear(PIREG_TypeDef *pi) { pi->CR |= PIREG_CR_CLR; }
/* Шаг от процессора с обратной связью fb: возвращает новый выход */
uint32_t PIREG_Step(PIREG_TypeDef *pi, uint32_t fb);
/* Выход, ошибка последнего шага, обратная связь последнего шага */
__PIREG_INLINE uint32_t PIREG_GetOut(PIREG_TypeDef *pi)   { return pi->OUT & 0xFFFFU; }
__PIREG_INLINE int32_t  PIREG_GetError(PIREG_TypeDef *pi) { return (int32_t)pi->OUT >> 16; }
__PIREG_INLINE uint32_t PIREG_GetFb(PIREG_TypeDef *pi)    { return pi->FB & 0xFFFFU; }
/* Состояние: на верхнем пределе (например, регулятор напряжения ограничен регулятором тока) */
__PIREG_INLINE uint32_t PIREG_AtLimit(PIREG_TypeDef *pi)  { return (pi->SR & PIREG_SR_LIM) != 0U; }
__PIREG_INLINE uint32_t PIREG_Running(PIREG_TypeDef *pi)  { return (pi->SR & PIREG_SR_RUN) != 0U; }
/* Флаг RDY и его сброс; прерывание: источник PLIC_SRC_<ИМЯ>, обработчик PLIC_<ИМЯ>_IRQHandler */
__PIREG_INLINE uint32_t PIREG_Ready(PIREG_TypeDef *pi)    { return (pi->SR & PIREG_SR_RDY) != 0U; }
__PIREG_INLINE void PIREG_ClearReady(PIREG_TypeDef *pi)   { pi->SR = PIREG_SR_RDY; }
__PIREG_INLINE void PIREG_IT_Enable(PIREG_TypeDef *pi)    { pi->CR |=  PIREG_CR_IE; }
__PIREG_INLINE void PIREG_IT_Disable(PIREG_TypeDef *pi)   { pi->CR &= ~PIREG_CR_IE; }

#endif /* PIREG_PRESENT */
#endif /* __PIREG_H */
