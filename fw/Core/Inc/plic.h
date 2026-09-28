/*
 ******************************************************************************
 * @file        plic.h
 * @author      Alexander Koptyakov
 * @device      AskoRV32
 * @brief       Драйвер контроллера прерываний периферии PLIC (как у SiFive, один контекст M-mode).
 *
 *  Все источники PLIC сводятся в одно прерывание ядра MEI (mcause 11). Его обработчик
 *  MEI_IRQHandler (plic.c) забирает номер источника (claim), вызывает обработчик источника
 *  и сообщает о завершении (complete). Обработчики источников - обычные функции (без __IRQ)
 *  с именами из таблицы plic.c; по умолчанию - слабые ссылки на PLIC_Default_Handler,
 *  который запрещает источник, чтобы он не вызывал прерывание бесконечно.
 *
 *  Порядок подключения источника:
 *    PLIC_SetPriority(PLIC_SRC_x, 1..7);   //0 - источник запрещён
 *    PLIC_Enable(PLIC_SRC_x);
 *    IRQ_Enable(MEI_IRQn); __enable_irq();
 *  В обработчике источника нужно сбросить флаг прерывания в самой периферии: запрос - по
 *  уровню, и после complete активный источник снова выставит ожидание.
 *****************************************************************************************
 */

#ifndef __PLIC_H
#define __PLIC_H

#include "periphery.h"

/* Приоритет источника: 0 - запрещён, 1..PLIC_MAX_PRIORITY. При равных приоритетах первым
   обслуживается источник с меньшим номером */
static inline void PLIC_SetPriority(PLIC_SRC_Type src, uint32_t prio) { PLIC->PRIORITY[src] = prio; }
static inline uint32_t PLIC_GetPriority(PLIC_SRC_Type src)          { return PLIC->PRIORITY[src]; }

/* Разрешение и запрет источника */
static inline void PLIC_Enable(PLIC_SRC_Type src)  { PLIC->ENABLE |=  (1U << src); }
static inline void PLIC_Disable(PLIC_SRC_Type src) { PLIC->ENABLE &= ~(1U << src); }

/* Ожидание источника (бит pending), не зависит от разрешения */
static inline uint32_t PLIC_IsPending(PLIC_SRC_Type src) { return (PLIC->PENDING >> src) & 1U; }

/* Порог: прерывание выдаётся только от источников с приоритетом больше порога */
static inline void PLIC_SetThreshold(uint32_t thr) { PLIC->THRESHOLD = thr; }

/* Claim: номер ожидающего источника с наибольшим приоритетом (0 - нет) и снятие ожидания.
   Complete: источник обслужен, можно принимать от него новый запрос */
static inline uint32_t PLIC_Claim(void)           { return PLIC->CLAIM; }
static inline void     PLIC_Complete(uint32_t id) { PLIC->CLAIM = id; }

/* Начальное состояние: все источники запрещены, приоритеты 0, порог 0 */
void PLIC_Init(void);

/* Обработчики источников (вызываются из MEI_IRQHandler) */
void PLIC_STIM_IRQHandler(void);
void PLIC_SRC2_IRQHandler(void);
void PLIC_SRC3_IRQHandler(void);
void PLIC_SRC4_IRQHandler(void);
void PLIC_SRC5_IRQHandler(void);
void PLIC_SRC6_IRQHandler(void);
void PLIC_SRC7_IRQHandler(void);
void PLIC_SRC8_IRQHandler(void);

#endif /* __PLIC_H */
