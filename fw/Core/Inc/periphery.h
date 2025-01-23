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
#define   STIM_BASE		(0x13000000U)

/* Объявление структур регистров */
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

typedef struct
{
  __IO uint32_t PR;    				//0x00: Регистр предделителя системной частоты таймера (PRESCALER)
  union {
	  __IO uint32_t CR;  			//0x04: Регистр управления счетчика (CONTROL REG)
	  struct {
		  uint32_t CR_CM	: 2;	// counter mode - выбора напрвление счёта
		  uint32_t CR_ARP 	: 1;    // autoReloadPreload
		  uint32_t CR_EN  	: 1;	// enable - включение таймера
	  };
  };
  __IO uint32_t PER;   	  			//0x08: Регистр данных значения переполнения таймера (PERIOD)
  __IO uint32_t PUL;         		//0x0C: Регистр значения сравнения (PULSE)
  __IO uint32_t CNT;  	      		//0x10: Регистр значения текущего счетчика таймера (COUNT)
} STIM_TypeDef;

/* Настройки таймера при инициализации */
#define STIM_PRESCALER 				1000000;
#define STIM_PERIOD 				100;
#define STIM_COUNTER_MODE 			STIM_COUNTER_MODE_DOWN;
#define STIM_AUTO_RELOAD_PRELOAD 	1;

/* Объявление указателей на структуры данных */
#define GPIO 	((GPIO_TypeDef*) 	GPIO_BASE)
#define TM1638 	((TM1638_TypeDef*) 	TM1638_BASE)
#define STIM 	((STIM_TypeDef*) 	STIM_BASE)

#endif /* __PERIPHERY_H */
