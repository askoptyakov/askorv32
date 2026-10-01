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
#include "soc.h"	//Создаёт конфигуратор ПЛИС: SYSCLK_HZ, адреса устройств, источники PLIC, настройки UART

/* Терминология */
#define __INLINE				__attribute__((always_inline)) inline
#define __I                     volatile const	//Только для чтения
#define __O                     volatile        //Только для записи
#define __IO                    volatile        //Чтение и запись

/* Частота тактирования периферии (clk_dmem) SYSCLK_HZ - в soc.h (от неё считают STIM, UART и mtime) */
#define MTIME_HZ				SYSCLK_HZ	//mtime увеличивается на каждом такте clk_dmem

/* Системные устройства процессора (cpu.sv); адреса пользовательской периферии - в soc.h */
#define  CLINT_BASE		(0x02000000U)
#define   PLIC_BASE		(0x0C000000U)

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
  __IO uint32_t CTRL;  	//0x0C: [1:0] режим (0 - HEX, 1 - текст, 2 - сегменты), [15:8] точки (бит i - позиция i слева)
  __IO uint32_t TEXT0; 	//0x10: Символы 0..3 (байт 0 - левый символ), коды cp1251
  __IO uint32_t TEXT1; 	//0x14: Символы 4..7
} TM1638_TypeDef;

typedef struct
{
  __IO uint32_t TXDATA;	//0x00: Запись - байт в FIFO передачи; чтение - бит 31: FIFO передачи полон
  __I  uint32_t RXDATA;	//0x04: Чтение - байт из FIFO приёма (выбирается из FIFO); бит 31: FIFO был пуст
  __IO uint32_t TXCTRL;	//0x08: [0] txen, [1] nstop (1 - два стоп-бита), [20:16] txcnt - порог txwm
  __IO uint32_t RXCTRL;	//0x0C: [0] rxen, [20:16] rxcnt - порог rxwm
  __IO uint32_t IE;		//0x10: Разрешение прерываний: [0] txwm, [1] rxwm, [2] err
  __I  uint32_t IP;		//0x14: Ожидающие прерывания: [0] txwm (в FIFO tx меньше txcnt), [1] rxwm (в FIFO rx больше rxcnt), [2] err
  __IO uint32_t DIV;		//0x18: Делитель скорости: скорость = SYSCLK_HZ / (DIV + 1)
  __IO uint32_t CFG;		//0x1C: [0] бит чётности есть, [1] 1 - odd, 0 - even
  __IO uint32_t ERR;		//0x20: Ошибки приёма, сброс записью 1: [0] кадр, [1] чётность, [2] переполнение FIFO приёма
} UART_TypeDef;

typedef struct
{
  __IO uint32_t PR;    				//0x00: Регистр предделителя системной частоты таймера (PRESCALER), 16 бит
  union {
	  __IO uint32_t CR;  			//0x04: Регистр управления счетчика (CONTROL REG)
	  struct {
		  __IO uint32_t CR_CM	: 2;	// counter mode - выбора напрвление счёта
		  __IO uint32_t CR_ARP 	: 1;    // autoReloadPreload
		  __IO uint32_t CR_EN  	: 1;	// enable - включение таймера
		  __IO uint32_t CR_UIE 	: 1;	// update interrupt enable - разрешение прерывания по событию обновления
	  };
  };
  __IO uint32_t PER;   	  			//0x08: Регистр данных значения переполнения таймера (PERIOD), 16 бит
  __IO uint32_t PUL;         		//0x0C: Регистр значения сравнения (PULSE), 16 бит
  __I  uint32_t CNT;  	      		//0x10: Регистр значения текущего счетчика таймера (COUNT), 16 бит
  __IO uint32_t SR;  	      		//0x14: Регистр состояния (STATUS REG): бит 0 - UIF, сброс записью 1
} STIM_TypeDef;

typedef struct
{
  __IO uint32_t MSIP;				//0x0000: Бит 0 - запрос программного прерывания
  uint32_t      RESERVED0[4095];
  __IO uint32_t MTIMECMP_LO;		//0x4000: Порог машинного таймера, младшее слово
  __IO uint32_t MTIMECMP_HI;		//0x4004: Порог машинного таймера, старшее слово
  uint32_t      RESERVED1[8188];
  __IO uint32_t MTIME_LO;			//0xBFF8: Машинный таймер, младшее слово
  __IO uint32_t MTIME_HI;			//0xBFFC: Машинный таймер, старшее слово
} CLINT_TypeDef;

typedef struct
{
  __IO uint32_t PRIORITY[1024];		//0x000000 + 4*N: Приоритет источника N (0 - запрещён)
  __I  uint32_t PENDING;			//0x001000: Бит N - источник N ожидает обработки
  uint32_t      RESERVED0[1023];
  __IO uint32_t ENABLE;				//0x002000: Бит N - разрешение источника N
  uint32_t      RESERVED1[522239];
  __IO uint32_t THRESHOLD;			//0x200000: Порог приоритета
  __IO uint32_t CLAIM;				//0x200004: Чтение - claim, запись - complete
  __IO uint32_t VECTOR;			//0x200008: Бит 0 - векторный режим (расширение askoRV32)
} PLIC_TypeDef;

/* Источники PLIC (PLIC_SRC_Type, PLIC_NUM_SOURCES) назначает конфигуратор ПЛИС - см. soc.h */
#define PLIC_MAX_PRIORITY			7U		//PRIO_BITS = 3

/* Биты регистров таймера STIM */
#define STIM_SR_UIF					(1U << 0)

/* Настройки таймера при инициализации */
#define STIM_PRESCALER 				(SYSCLK_HZ / 1000U - 1U)	//Тик счётчика - 1 мс (значение не больше 65535)
#define STIM_PERIOD 				100;
#define STIM_COUNTER_MODE 			STIM_COUNTER_MODE_DOWN;
#define STIM_AUTO_RELOAD_PRELOAD 	1;

/* Биты регистров UART */
#define UART_TXDATA_FULL			(1U << 31)
#define UART_RXDATA_EMPTY			(1U << 31)
#define UART_CTRL_EN				(1U << 0)	//txen / rxen
#define UART_TXCTRL_NSTOP			(1U << 1)
#define UART_CTRL_CNT_POS			16U			//Поле txcnt / rxcnt
#define UART_IT_TXWM				(1U << 0)
#define UART_IT_RXWM				(1U << 1)
#define UART_IT_ERR					(1U << 2)
#define UART_CFG_PE					(1U << 0)
#define UART_CFG_PO					(1U << 1)
#define UART_ERR_FRAME				(1U << 0)
#define UART_ERR_PARITY				(1U << 1)
#define UART_ERR_OVERRUN			(1U << 2)

/* Объявление указателей на структуры данных: пользовательская периферия - только та, что есть в ПЛИС */
#define CLINT 	((CLINT_TypeDef*) 	CLINT_BASE)
#define PLIC 	((PLIC_TypeDef*) 	PLIC_BASE)
#if GPIO_PRESENT
#define GPIO 	((GPIO_TypeDef*) 	GPIO_BASE)
#endif
#if TM1638_PRESENT
#define TM1638 	((TM1638_TypeDef*) 	TM1638_BASE)
#endif
#if STIM_PRESENT
#define STIM 	((STIM_TypeDef*) 	STIM_BASE)
#endif
#if UART_PRESENT
#define UART 	((UART_TypeDef*) 	UART_BASE)
#endif

#endif /* __PERIPHERY_H */
