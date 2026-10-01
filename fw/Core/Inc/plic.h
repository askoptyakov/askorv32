/*
 ******************************************************************************
 * @file        plic.h
 * @author      Alexander Koptyakov
 * @device      AskoRV32
 * @brief       Драйвер контроллера прерываний периферии PLIC (как у SiFive, один контекст M-mode)
 *              в векторном режиме askoRV32.
 *
 *  Источники PLIC дают ядру прерывание MEI (mcause 11). В векторном режиме (его включает
 *  PLIC_Init) ядро переходит сразу на вход 32 + S таблицы векторов (start.S), а PLIC сам
 *  захватывает источник S (claim). Обработчик источника - функция с атрибутом __IRQ,
 *  как у любого прерывания: он сохраняет только свои регистры. Имена в start.S -
 *  PLIC_SRC1_IRQHandler..PLIC_SRC31_IRQHandler (по умолчанию - слабые ссылки на Default_Handler);
 *  номера источников и понятные имена (PLIC_SRC_UART, PLIC_UART_IRQHandler) задаёт soc.h.
 *
 *  Порядок подключения источника:
 *    PLIC_Init();                            //один раз: всё запрещено, векторный режим
 *    PLIC_SetPriority(PLIC_SRC_x, 1..7);     //0 - источник запрещён
 *    PLIC_Enable(PLIC_SRC_x);
 *    IRQ_Enable(MEI_IRQn); __enable_irq();
 *
 *  Обработчик источника:
 *    __IRQ void PLIC_UART_IRQHandler(void) {
 *        <сбросить флаг прерывания в периферии>   //запрос - по уровню
 *        <работа>
 *        PLIC_Complete(PLIC_SRC_UART);           //только после сброса флага
 *    }
 *  Если complete записать, пока флаг в периферии ещё не сброшен, источник снова выставит
 *  ожидание, и обработчик вызовется повторно.
 *****************************************************************************************
 */

#ifndef __PLIC_H
#define __PLIC_H

#include "core_riscv.h"
#include "periphery.h"

/* Функции встраиваются и при -O0: вызов функции из обработчика __IRQ заставил бы его сохранять
   все регистры, которые может испортить вызов (при -O0 вдвое дольше вход в обработчик) */
#define __PLIC_INLINE		static inline __attribute__((always_inline))

/* Приоритет источника: 0 - запрещён, 1..PLIC_MAX_PRIORITY. При равных приоритетах первым
   обслуживается источник с меньшим номером */
__PLIC_INLINE void PLIC_SetPriority(PLIC_SRC_Type src, uint32_t prio) { PLIC->PRIORITY[src] = prio; }
__PLIC_INLINE uint32_t PLIC_GetPriority(PLIC_SRC_Type src)          { return PLIC->PRIORITY[src]; }

/* Разрешение и запрет источника */
__PLIC_INLINE void PLIC_Enable(PLIC_SRC_Type src)  { PLIC->ENABLE |=  (1U << src); }
__PLIC_INLINE void PLIC_Disable(PLIC_SRC_Type src) { PLIC->ENABLE &= ~(1U << src); }

/* Ожидание источника (бит pending), не зависит от разрешения */
__PLIC_INLINE uint32_t PLIC_IsPending(PLIC_SRC_Type src) { return (PLIC->PENDING >> src) & 1U; }

/* Порог: прерывание выдаётся только от источников с приоритетом больше порога */
__PLIC_INLINE void PLIC_SetThreshold(uint32_t thr) { PLIC->THRESHOLD = thr; }

/* Complete: источник обслужен, можно принимать от него новый запрос.
   Claim (номер ожидающего источника с наибольшим приоритетом и снятие ожидания) в векторном
   режиме выполняет сам PLIC; чтение нужно только без векторного режима */
__PLIC_INLINE void     PLIC_Complete(PLIC_SRC_Type src) { PLIC->CLAIM = src; }
__PLIC_INLINE uint32_t PLIC_Claim(void)                 { return PLIC->CLAIM; }

/* Начальное состояние: все источники запрещены, приоритеты 0, порог 0, векторный режим */
void PLIC_Init(void);

/* Обработчики источников: PLIC_SRCn_IRQHandler (входы 32 + n таблицы векторов, start.S), понятные
   имена устройств (PLIC_UART_IRQHandler...) - макросы в soc.h */

#endif /* __PLIC_H */
