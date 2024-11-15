/*
 ******************************************************************************
 * @file        periphery.h
 * @author		Alexander Koptyakov
 * @device		AskoRV32
 * @brief       Заголовочный файл доступа к периферийным устройствам.
 *****************************************************************************************
 */

#ifndef __PERIPHERY_H
#define __PERIPHERY_H

/* Подключаемые библиотеки */
#include <stdint.h>

/* Терминология */
#define __INLINE				__attribute__((always_inline)) inline
#define __I                     volatile const	//Только для чтения
#define __O                     volatile        //Только для записи
#define __IO                    volatile        //Чтение и запись

/* Карта памяти периферийных устройств */
#define   GPIO_BASE		(0x11000000U)
#define TM1638_BASE		(0x12000000U)

/* Объявление структы регистров */
typedef struct
{
  __IO uint32_t MODE;  	//0x00: Регистр выбора режима вход/выход порта
  __IO uint32_t  OUT;   //0x04: Регистр выходных данных порта
  __IO uint32_t   IN;  	//0x08: Регистр входных данных порта
} GPIO_TypeDef;

typedef struct
{
  __IO uint32_t SEGS;  	//0x00: Регистр данных на семисегментном индикаторе вн. платы(HEX)
  __IO uint32_t LEDS;   //0x04: Регистр данных на светодиодах вн. платы
  __IO uint32_t KEYS;  	//0x08: Регистр данных состояния кнопок вн. платы
} TM1638_TypeDef;

/* Объявление указатели на структуры данных */
#define GPIO 	((GPIO_TypeDef*) 	GPIO_BASE)
#define TM1638 	((TM1638_TypeDef*) 	TM1638_BASE)

#endif /* __PERIPHERY_H */
