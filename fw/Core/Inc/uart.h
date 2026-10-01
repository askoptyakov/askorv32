/*
 ******************************************************************************
 * @file        uart.h
 * @author      Alexander Koptyakov
 * @device      AskoRV32
 * @brief       Драйвер UART (регистры как у SiFive FE310 + чётность и флаги ошибок).
 *
 *  Кадр: 8 бит данных, чётность none/even/odd, 1 или 2 стоп-бита. Скорость, чётность и стоп-биты
 *  после сброса ПЛИС задаёт конфигуратор (soc.h: UART_BAUD, UART_PARITY_DEFAULT, UART_STOP_DEFAULT),
 *  программа может сменить их функцией UART_Init. У приёма и передачи - FIFO глубиной UART_FIFO_DEPTH.
 *
 *  Два способа работы:
 *  1) Опрос: UART_PutChar/UART_GetChar/UART_ReadLine... - ждут места в FIFO передачи или байта.
 *  2) Прерывания по заполнению FIFO (watermark): приём - когда в FIFO приёма больше rx_threshold
 *     байт, передача - когда в FIFO передачи меньше половины. Байты копятся в кольцевых буферах
 *     в ОЗУ (UART_RING_SIZE): UART_IT_Start, UART_IT_Write/UART_IT_Read. Обработчик прерывания
 *     пишет программа (имя из soc.h - PLIC_UART_IRQHandler) и вызывает в нём UART_IRQ_Service:
 *
 *       __IRQ void PLIC_UART_IRQHandler(void) {
 *           UART_IRQ_Service();                 //FIFO <-> кольцевые буферы
 *           PLIC_Complete(PLIC_SRC_UART);
 *       }
 *
 *  Текст: прошивка хранит строки в cp1251 (кодировка проекта Eclipse), а терминал на ПК обычно
 *  работает в UTF-8. UART_PutText переводит cp1251 -> UTF-8 (при UART_TEXT_UTF8 = 1), функция
 *  UART_Utf8ToCp1251 - принятый текст обратно (например, для вывода кириллицы на TM1638).
 *****************************************************************************************
 */

#ifndef __UART_H
#define __UART_H

#include "periphery.h"

/* Регистры UART */
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

#if UART_PRESENT	//Блок есть в ПЛИС (soc.h)

#include "core_riscv.h"
#include "plic.h"

#ifndef UART_TEXT_UTF8
#define UART_TEXT_UTF8		1		//1 - терминал на ПК в UTF-8, 0 - в cp1251
#endif
#ifndef UART_RING_SIZE
#define UART_RING_SIZE		64U		//Кольцевые буферы режима прерываний, степень двойки
#endif

typedef enum
{
  UART_PARITY_NONE = 0,
  UART_PARITY_EVEN = 1,
  UART_PARITY_ODD  = 2
} UART_Parity;

/* Настройка: скорость, чётность, стоп-биты (1 или 2). Включает приём и передачу, прерывания
   выключены, FIFO приёма очищен. UART_InitDefault - значения из конфигуратора (soc.h) */
void UART_Init(uint32_t baud, UART_Parity parity, uint32_t stop);
#define UART_InitDefault()	UART_Init(UART_BAUD, (UART_Parity)UART_PARITY_DEFAULT, UART_STOP_DEFAULT)

/* --- Опрос --- */
__INLINE uint32_t UART_TxFull(void)  { return (UART->TXDATA & UART_TXDATA_FULL) != 0; }
void UART_PutChar(char c);                         //Ждёт места в FIFO передачи
int  UART_GetChar(void);                           //Байт или -1, если FIFO приёма пуст (не ждёт)
char UART_ReadChar(void);                          //Ждёт байт
void UART_PutString(const char *s);                //Строка как есть (байты)
void UART_PutText(const char *s);                  //Строка cp1251, на терминал - в UTF-8 (UART_TEXT_UTF8)
void UART_PutDec(int32_t v);                       //Десятичное число со знаком
void UART_PutHex(uint32_t v, uint32_t digits);     //Шестнадцатеричное, digits цифр (1..8)
/* Строка до Enter (CR или LF): эхо, Backspace. В buf - без конца строки, с завершающим 0;
   возвращает длину. Не больше size - 1 байт, лишнее отбрасывается */
int  UART_ReadLine(char *buf, int size, int echo);
/* Ошибки приёма (UART_ERR_FRAME/PARITY/OVERRUN) и их сброс */
__INLINE uint32_t UART_GetErrors(void)            { return UART->ERR; }
__INLINE void     UART_ClearErrors(uint32_t mask) { UART->ERR = mask; }

/* --- Текст --- */
/* UTF-8 -> cp1251: латиница, кириллица (А..я, Ё, ё), °, « », №; прочие символы - '?'. Возвращает длину */
int  UART_Utf8ToCp1251(const char *in, char *out, int size);

/* --- Прерывания по заполнению FIFO --- */
typedef struct
{
  volatile uint8_t  buf[UART_RING_SIZE];
  volatile uint32_t head;                          //Пишет производитель
  volatile uint32_t tail;                          //Читает потребитель
  volatile uint32_t lost;                          //Байты, не поместившиеся в буфер
} UART_Ring;
extern UART_Ring uart_rx_ring, uart_tx_ring;

/* Запуск: прерывание приёма, когда в FIFO приёма больше rx_threshold байт (0 - на каждый байт,
   UART_FIFO_DEPTH/2 - 1 - при половине FIFO), передачи - когда в FIFO меньше половины. Разрешает
   источник UART в PLIC (PLIC_Init должен быть вызван раньше) или его локальную линию и MEI;
   глобальное разрешение __enable_irq - за программой */
void UART_IT_Start(uint32_t rx_threshold);
int  UART_IT_Write(const char *data, int len);     //В буфер передачи; возвращает, сколько поместилось
void UART_IT_PutText(const char *s);               //Строка cp1251 (UTF-8 на терминал), ждёт места
int  UART_IT_Read(char *data, int len);            //Из буфера приёма; возвращает, сколько прочитано
__INLINE uint32_t UART_IT_Available(void) { return uart_rx_ring.head - uart_rx_ring.tail; }

/* Обслуживание FIFO в обработчике прерывания: принятое - в буфер приёма, из буфера передачи -
   в FIFO передачи; когда передавать нечего, прерывание передачи выключается. Встраиваемая функция:
   обработчик __IRQ сохраняет только свои регистры (вызов функции заставил бы сохранять все) */
__INLINE void UART_IRQ_Service(void) {
	uint32_t d;
	while (!((d = UART->RXDATA) & UART_RXDATA_EMPTY)) {
		if (uart_rx_ring.head - uart_rx_ring.tail < UART_RING_SIZE) {
			uart_rx_ring.buf[uart_rx_ring.head & (UART_RING_SIZE - 1U)] = (uint8_t)d;
			uart_rx_ring.head++;
		} else uart_rx_ring.lost++;
	}
	while (uart_tx_ring.tail != uart_tx_ring.head && !(UART->TXDATA & UART_TXDATA_FULL)) {
		UART->TXDATA = uart_tx_ring.buf[uart_tx_ring.tail & (UART_RING_SIZE - 1U)];
		uart_tx_ring.tail++;
	}
	if (uart_tx_ring.tail == uart_tx_ring.head)
		UART->IE &= ~UART_IT_TXWM;
}

#endif /* UART_PRESENT */
#endif /* __UART_H */
