/*
 ******************************************************************************
 * @file        clint.h
 * @author      Alexander Koptyakov
 * @device      AskoRV32
 * @brief       Драйвер CLINT: машинный таймер (mtime/mtimecmp) и программное прерывание.
 *              Регистры и адреса - как у SiFive CLINT. Доступ только словами по 32 бит.
 *****************************************************************************************
 */

#ifndef __CLINT_H
#define __CLINT_H

#include "periphery.h"

/* Текущее значение mtime (64 бит). Старшее слово читается дважды: при переносе между
   чтениями младшее слово перечитывается */
static inline uint64_t CLINT_GetTime(void)
{
  uint32_t hi, lo;
  do {
    hi = CLINT->MTIME_HI;
    lo = CLINT->MTIME_LO;
  } while (hi != CLINT->MTIME_HI);
  return ((uint64_t)hi << 32) | lo;
}

/* Порог прерывания таймера. Сначала в старшее слово пишется максимум, чтобы на время записи
   двух половин не возникло ложное прерывание */
static inline void CLINT_SetCompare(uint64_t time)
{
  CLINT->MTIMECMP_HI = 0xFFFFFFFFU;
  CLINT->MTIMECMP_LO = (uint32_t)time;
  CLINT->MTIMECMP_HI = (uint32_t)(time >> 32);
}

static inline uint64_t CLINT_GetCompare(void)
{
  return ((uint64_t)CLINT->MTIMECMP_HI << 32) | CLINT->MTIMECMP_LO;
}

/* Прерывание через ticks тактов mtime от текущего момента */
static inline void CLINT_SetTimeout(uint64_t ticks) { CLINT_SetCompare(CLINT_GetTime() + ticks); }

/* Снять запрос прерывания таймера (порог - максимум) */
static inline void CLINT_StopTimer(void) { CLINT->MTIMECMP_HI = 0xFFFFFFFFU; }

/* Программное прерывание: выставить / снять запрос */
static inline void CLINT_SetSoftIRQ(void)   { CLINT->MSIP = 1U; }
static inline void CLINT_ClearSoftIRQ(void) { CLINT->MSIP = 0U; }

/* Задержка по mtime */
void CLINT_Delay(uint64_t ticks);

#endif /* __CLINT_H */
