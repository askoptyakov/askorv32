/*
 ******************************************************************************
 * @file        rect.h
 * @author		Alexander Koptyakov
 * @device		AskoRV32
 * @brief       Блок «Выпрямитель» (RECT, hw/src/periph/rect): СИФУ и регулятор CC/CV в одном окне
 *              регистров. Части блока - под именами драйверов из soc.h: SIFU (sifu.h, +0x00),
 *              PI_U - регулятор напряжения и PI_I - регулятор тока (pireg.h, +0x40 и +0x80).
 *              Обратные связи - каналы блока ADC (RECT_FB_U, RECT_FB_I в soc.h), окна закрывает
 *              сам выпрямитель. Описание - hw/info/rectifier.md.
 *****************************************************************************************
 */

#ifndef __RECT_H
#define __RECT_H

#include "sifu.h"
#include "pireg.h"

/* Окно блока: SIFU, PI_U, PI_I - по 0x40 байт */
typedef struct
{
  SIFU_TypeDef  SIFU;
  uint32_t      reserved0[(0x40U - sizeof(SIFU_TypeDef)) / 4U];
  PIREG_TypeDef PI_U;
  uint32_t      reserved1[(0x40U - sizeof(PIREG_TypeDef)) / 4U];
  PIREG_TypeDef PI_I;
} RECT_TypeDef;

#endif /* __RECT_H */
