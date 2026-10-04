/*
 ******************************************************************************
 * @file        sifu.h
 * @author		Alexander Koptyakov
 * @device		AskoRV32
 * @brief       Драйвер СИФУ - системы импульсно-фазового управления трёхфазным мостовым
 *              тиристорным выпрямителем (блок SIFU, hw/src/periph/sifu). Синхронизация - плата
 *              NSB (шесть оптронов на линейных напряжениях), выходы - импульсы на тиристоры VS1..VS6.
 *              Угол управления - в тиках ГПН (ALPHA) или в десятых долях эл. градуса
 *              (SIFU_SetAlphaDeg10). Описание модуля - hw/src/periph/sifu/README.md.
 *
 *              Пример: выпрямитель с углом 30 град.
 *                SIFU_Init();                    //DIV, DELAY, WIDTH - из конфигуратора (soc.h)
 *                SIFU_SetAlphaDeg10(300);        //30.0 эл. град.
 *                SIFU_Enable();                  //Импульсы разрешены
 *****************************************************************************************
 */

#ifndef __SIFU_H
#define __SIFU_H

#include "periphery.h"

/* Регистры СИФУ */
typedef struct
{
  __IO uint32_t CR;					//0x00: управление: EN, DBL, SIM, FLT, SIE, LIE, UEXT
  __IO uint32_t ALPHA;				//0x04: угол управления, тиков ГПН (12 бит); 4095 - импульсов нет
  __IO uint32_t WIDTH;				//0x08: длительность импульса, тиков ГПН (12 бит)
  __IO uint32_t DELAY;				//0x0C: DELAY_RC_COMPENSATION, тиков ГПН (12 бит)
  __IO uint32_t DIV;				//0x10: тик ГПН раз в DIV + 1 тактов SYSCLK_HZ (16 бит)
  __IO uint32_t SR;					//0x14: состояние: SYNC, GRID, SYNCF, LOSSF, LOST, CH
  __I  uint32_t HPER;				//0x18: полупериод сети, тиков ГПН (16 бит)
  __I  uint32_t CNT[3];				//0x1C, 0x20, 0x24: пилы пар AB/BA, BC/CB, CA/AC (12 бит)
  __I  uint32_t GATE;				//0x28: [5:0] выходы VS1..VS6, [13:8] импульсы пар до сдваивания
  __IO uint32_t SIMCFG;				//0x2C: имитатор сети: [15:0] SECT, [27:16] DZ
  __IO uint32_t AMAX;				//0x30: [11:0] наибольший угол при UEXT, тиков; [27:16] AEFF - действующий угол
} SIFU_TypeDef;

/* Биты CR */
#define SIFU_CR_EN					(1U << 0)	//Импульсы разрешены
#define SIFU_CR_DBL					(1U << 1)	//Сдвоенные (подтверждающие) импульсы
#define SIFU_CR_SIM					(1U << 2)	//Имитатор сети вместо входов NSB
#define SIFU_CR_FLT					(1U << 3)	//Фильтр входов по тикам ГПН (иначе - по тактам)
#define SIFU_CR_SIE					(1U << 4)	//Прерывание по началу полуволны (SYNCF)
#define SIFU_CR_LIE					(1U << 5)	//Прерывание по потере синхронизации (LOSSF)
#define SIFU_CR_UEXT				(1U << 6)	//Угол от прямой связи u: AMAX - u (вход подключён в конфигураторе)

/* Биты SR */
#define SIFU_SR_SYNC_MSK			0x3FU		//Входы после фильтра (1 - оптрон закрыт): AB, BA, BC, CB, CA, AC
#define SIFU_SR_GRID				(1U << 8)	//Сеть есть
#define SIFU_SR_SYNCF				(1U << 9)	//Началась полуволна; сброс записью 1
#define SIFU_SR_LOSSF				(1U << 10)	//Пропала синхронизация; сброс записью 1
#define SIFU_SR_LOST				(1U << 11)	//Сейчас нет синхронизации
#define SIFU_SR_CH_POS				16U			//Номер тиристора (1..6), чья полуволна началась последней
#define SIFU_SR_CH_MSK				(7U << SIFU_SR_CH_POS)

/* Поля GATE и SIMCFG */
#define SIFU_GATE_VS_MSK			0x3FU		//Выходы VS1..VS6 (бит 0 - VS1)
#define SIFU_GATE_DIRECT_POS		8U			//Импульсы пар до сдваивания и EN
#define SIFU_SIM_SECT_MSK			0xFFFFU		//Тиков на 60 эл. град.
#define SIFU_SIM_DZ_POS				16U			//Мёртвая зона, тиков
#define SIFU_SIM_DZ_MSK				(0xFFFU << SIFU_SIM_DZ_POS)
#define SIFU_AMAX_MSK				0xFFFU		//AMAX: наибольший угол при UEXT
#define SIFU_AEFF_POS				16U			//AEFF: действующий угол (ALPHA или AMAX - u)

#define SIFU_SAW_MAX				4095U		//Пила 12 бит: на 4095 останавливается, импульса там нет
#define SIFU_ALPHA_OFF				4095U		//ALPHA «импульсов нет» (значение после сброса)
#define SIFU_LOST_TICKS				8192U		//Без начала полуволны дольше - LOST
#ifndef SIFU_ALPHA_LIMIT_DEG10
#define SIFU_ALPHA_LIMIT_DEG10		1200U		//Наибольший угол для SIFU_SetAlphaDeg10: 120.0 эл. град.
#endif

#if SIFU_PRESENT	//Блок есть в ПЛИС (soc.h)

#define __SIFU_INLINE		static inline __attribute__((always_inline))

/* Инициализация: DIV, DELAY, WIDTH - значения конфигуратора (SIFU_DIV_DEFAULT...), ALPHA = 4095
   (импульсов нет), CR = DBL | FLT (выключено), флаги сброшены */
void SIFU_Init(void);

/* Разрешение импульсов (CR.EN). Выходы - только при EN и наличии сети (SR.GRID) */
__SIFU_INLINE void SIFU_Enable(void)  { SIFU->CR |=  SIFU_CR_EN; }
__SIFU_INLINE void SIFU_Disable(void) { SIFU->CR &= ~SIFU_CR_EN; }

/* Угол в тиках ГПН от точки естественной коммутации. Пары берут его в начале своей полуволны.
   Значение больше SIFU_AlphaMax() ограничивается им (импульс целиком внутри пилы) */
void SIFU_SetAlpha(uint32_t ticks);
__SIFU_INLINE uint32_t SIFU_GetAlpha(void) { return SIFU->ALPHA; }
/* Снять импульсы, не трогая EN: ALPHA = 4095 */
__SIFU_INLINE void SIFU_AlphaOff(void) { SIFU->ALPHA = SIFU_ALPHA_OFF; }
/* Наибольший угол, тиков: 4094 - DELAY - WIDTH (импульс заканчивается до конца пилы) */
uint32_t SIFU_AlphaMax(void);

/* Угол в десятых долях эл. градуса (300 = 30.0 град.): пересчёт по полупериоду сети SIFU_HalfPeriod().
   Ограничивается SIFU_AlphaMaxDeg10() */
void     SIFU_SetAlphaDeg10(uint32_t deg10);
uint32_t SIFU_GetAlphaDeg10(void);
/* Наибольший угол, десятые доли градуса: SIFU_ALPHA_LIMIT_DEG10 (120 град.), если пила позволяет,
   иначе SIFU_AlphaMax() в градусах */
uint32_t SIFU_AlphaMaxDeg10(void);
/* Тики <-> десятые доли градуса по текущему полупериоду */
uint32_t SIFU_TicksToDeg10(uint32_t ticks);
uint32_t SIFU_Deg10ToTicks(uint32_t deg10);

/* Сдвиг DELAY_RC_COMPENSATION и длительность импульса, тиков ГПН */
__SIFU_INLINE void SIFU_SetDelay(uint32_t ticks) { SIFU->DELAY = ticks & SIFU_SAW_MAX; }
__SIFU_INLINE void SIFU_SetWidth(uint32_t ticks) { SIFU->WIDTH = ticks & SIFU_SAW_MAX; }
/* Сдвоенные импульсы (по умолчанию включены) */
__SIFU_INLINE void SIFU_DoublePulse(uint32_t on) { if (on) SIFU->CR |= SIFU_CR_DBL; else SIFU->CR &= ~SIFU_CR_DBL; }

/* Частота тиков ГПН, Гц: SYSCLK_HZ / (DIV + 1) */
uint32_t SIFU_SawHz(void);
/* Полупериод сети, тиков ГПН: измеренный (HPER), а пока синхронизации нет - 50 Гц по частоте ГПН */
uint32_t SIFU_HalfPeriod(void);
/* Частота сети по паре AB, сотые доли Гц (5000 = 50.00 Гц); 0 - сети нет */
uint32_t SIFU_GridFreq100(void);

/* Состояние */
__SIFU_INLINE uint32_t SIFU_GridPresent(void) { return (SIFU->SR & SIFU_SR_GRID) != 0U; }
__SIFU_INLINE uint32_t SIFU_SyncLost(void)    { return (SIFU->SR & SIFU_SR_LOST) != 0U; }
__SIFU_INLINE uint32_t SIFU_LastChannel(void) { return (SIFU->SR & SIFU_SR_CH_MSK) >> SIFU_SR_CH_POS; }
__SIFU_INLINE uint32_t SIFU_GetFlags(void)    { return SIFU->SR & (SIFU_SR_SYNCF | SIFU_SR_LOSSF); }
/* Сброс флагов SYNCF, LOSSF записью 1 */
__SIFU_INLINE void SIFU_ClearFlags(uint32_t flags) { SIFU->SR = flags & (SIFU_SR_SYNCF | SIFU_SR_LOSSF); }
/* Выходы VS1..VS6 (бит 0 - VS1) */
__SIFU_INLINE uint32_t SIFU_GetGates(void) { return SIFU->GATE & SIFU_GATE_VS_MSK; }

/* Прерывания: SIFU_CR_SIE (начало полуволны), SIFU_CR_LIE (потеря синхронизации). Источник PLIC -
   PLIC_SRC_SIFU, обработчик PLIC_SIFU_IRQHandler (soc.h); в обработчике сбросить флаг */
__SIFU_INLINE void SIFU_IT_Enable(uint32_t it)  { SIFU->CR |=  (it & (SIFU_CR_SIE | SIFU_CR_LIE)); }
__SIFU_INLINE void SIFU_IT_Disable(uint32_t it) { SIFU->CR &= ~(it & (SIFU_CR_SIE | SIFU_CR_LIE)); }

/* Угол от прямой связи u (например, выход блока PIREG): ALPHA = AMAX - min(u, AMAX), регистр ALPHA
   не действует. Есть, если вход u подключён в конфигураторе (SIFU_LINK_U) */
__SIFU_INLINE void SIFU_ExtEnable(void)  { SIFU->CR |=  SIFU_CR_UEXT; }
__SIFU_INLINE void SIFU_ExtDisable(void) { SIFU->CR &= ~SIFU_CR_UEXT; }
__SIFU_INLINE void SIFU_SetAlphaMaxExt(uint32_t ticks) { SIFU->AMAX = ticks & SIFU_AMAX_MSK; }
__SIFU_INLINE uint32_t SIFU_GetAlphaMaxExt(void) { return SIFU->AMAX & SIFU_AMAX_MSK; }
/* Действующий угол, тиков: ALPHA или AMAX - u */
__SIFU_INLINE uint32_t SIFU_GetAlphaEff(void) { return (SIFU->AMAX >> SIFU_AEFF_POS) & SIFU_AMAX_MSK; }

/* Имитатор сети (проверка без силовой части): частота в сотых долях Гц, мёртвая зона в десятых
   долях градуса. Входы NSB не используются. Имитатор даёт сигналы оптронов так, как их выдаёт NSB:
   полуволна начинается с началом окна оптрона, точка естественной коммутации - через DELAY тиков
   (DELAY и угол не меняются) */
void SIFU_SimStart(uint32_t freq100, uint32_t dz_deg10);
__SIFU_INLINE void SIFU_SimStop(void) { SIFU->CR &= ~SIFU_CR_SIM; }

#endif /* SIFU_PRESENT */
#endif /* __SIFU_H */
