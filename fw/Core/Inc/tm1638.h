/*
 ******************************************************************************
 * @file        tm1638.h
 * @author		Alexander Koptyakov
 * @device		AskoRV32
 * @brief       Драйвер модуля связи с контроллером TM1638: 8 цифр (HEX, текст cp1251 или
 *              сегменты), 8 светодиодов, 8 кнопок
 *****************************************************************************************
 */

#ifndef __TM1638_H
#define __TM1638_H

#include "periphery.h"

/* Регистры TM1638 */
typedef struct
{
  __IO uint32_t SEGS;  	//0x00: Регистр данных на семисегментном индикаторе вн. платы(HEX)
  __IO uint32_t LEDS;   //0x04: Регистр данных на светодиодах вн. платы
  __IO uint32_t KEYS;  	//0x08: Регистр данных состояния кнопок вн. платы
  __IO uint32_t CTRL;  	//0x0C: [1:0] режим (0 - HEX, 1 - текст, 2 - сегменты), [15:8] точки (бит i - позиция i слева)
  __IO uint32_t TEXT0; 	//0x10: Символы 0..3 (байт 0 - левый символ), коды cp1251
  __IO uint32_t TEXT1; 	//0x14: Символы 4..7
} TM1638_TypeDef;

#if TM1638_PRESENT	//Блок есть в ПЛИС (soc.h)

typedef enum
{
  TM1638_PIN_RESET = 0,
  TM1638_PIN_SET
} TM1638_LedState;

typedef enum
{
  TM1638_LED0 = 0,
  TM1638_LED1,
  TM1638_LED2,
  TM1638_LED3,
  TM1638_LED4,
  TM1638_LED5,
  TM1638_LED6,
  TM1638_LED7
} TM1638_LedName;

typedef enum
{
  TM1638_KEY0 = 0,
  TM1638_KEY1,
  TM1638_KEY2,
  TM1638_KEY3,
  TM1638_KEY4,
  TM1638_KEY5,
  TM1638_KEY6,
  TM1638_KEY7,
} TM1638_KeyName;

void TM1638_Init(void);

typedef enum
{
  TM1638_MODE_HEX  = 0,		//8 цифр HEX из SEGS
  TM1638_MODE_TEXT = 1,		//8 символов cp1251 из TEXT0/TEXT1 (знакогенератор в ПЛИС)
  TM1638_MODE_RAW  = 2		//8 байт TEXT0/TEXT1 - сегменты как есть (бит 0 - a, ..., 6 - g, 7 - точка)
} TM1638_Mode;

__INLINE void TM1638_SetMode(TM1638_Mode mode) {
	TM1638->CTRL = (TM1638->CTRL & ~3U) | (uint32_t)mode;
}

/* Точки: бит i - точка после символа i слева (во всех режимах) */
__INLINE void TM1638_SetDots(uint32_t mask) {
	TM1638->CTRL = (TM1638->CTRL & 3U) | ((mask & 0xFFU) << 8);
}

/* 8 цифр HEX (тетрада 0 - правая цифра); переключает индикатор в режим HEX */
__INLINE void TM1638_WriteSegs(uint32_t data) {
	TM1638->SEGS = data;
	TM1638_SetMode(TM1638_MODE_HEX);
}

/* Текст cp1251 (кодировка файлов проекта): до 8 символов слева, остаток - пробелы. Точка или
   запятая после символа не занимает позицию, а зажигает его точку: "3.14", "ПРИВЕТ.".
   Переключает индикатор в режим текста */
void TM1638_WriteText(const char *s);

/* Число со знаком десятичными цифрами, выровненное вправо (режим текста) */
void TM1638_WriteNumber(int32_t v);

/* 8 байт сегментов слева направо (режим RAW) */
void TM1638_WriteRaw(const uint8_t segs[8]);

__INLINE void TM1638_WriteLeds(uint32_t data) {
	TM1638->LEDS = data;
}

__INLINE uint32_t TM1638_ReadKeys(void) {
	return TM1638->KEYS;
}

__INLINE void TM1638_WriteLed(TM1638_LedName led, TM1638_LedState state) {
	if (state) TM1638->LEDS |=  (1 << led);
	else	   TM1638->LEDS &= ~(1 << led);
}

__INLINE uint32_t TM1638_ReadKey(TM1638_KeyName key) {
	return (TM1638->KEYS >> key) & 0x1;
}


#endif /* TM1638_PRESENT */
#endif /* __TM1638_H */
