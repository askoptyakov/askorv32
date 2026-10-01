/*
 ******************************************************************************
 * @file        uart.c
 * @author      Alexander Koptyakov
 * @device      AskoRV32
 * @brief       Драйвер UART: настройка, опрос, текст, кольцевые буферы режима прерываний
 *****************************************************************************************
 */

#include "uart.h"

#if UART_PRESENT

UART_Ring uart_rx_ring, uart_tx_ring;

void UART_Init(uint32_t baud, UART_Parity parity, uint32_t stop) {
	UART->IE = 0;
	UART->TXCTRL = 0;
	UART->RXCTRL = 0;
	UART->DIV = (SYSCLK_HZ + baud / 2U) / baud - 1U;			//Скорость = SYSCLK_HZ / (DIV + 1)
	UART->CFG = (parity == UART_PARITY_NONE) ? 0U :
	            (parity == UART_PARITY_EVEN) ? UART_CFG_PE : (UART_CFG_PE | UART_CFG_PO);
	while (!(UART->RXDATA & UART_RXDATA_EMPTY)) ;			//Очистить FIFO приёма
	UART->ERR = UART_ERR_FRAME | UART_ERR_PARITY | UART_ERR_OVERRUN;
	UART->TXCTRL = UART_CTRL_EN | (stop == 2U ? UART_TXCTRL_NSTOP : 0U);
	UART->RXCTRL = UART_CTRL_EN;
}

/* --- Опрос --- */
void UART_PutChar(char c) {
	while (UART->TXDATA & UART_TXDATA_FULL) ;
	UART->TXDATA = (uint8_t)c;
}

int UART_GetChar(void) {
	uint32_t d = UART->RXDATA;								//Чтение выбирает байт из FIFO
	return (d & UART_RXDATA_EMPTY) ? -1 : (int)(d & 0xFFU);
}

char UART_ReadChar(void) {
	int c;
	while ((c = UART_GetChar()) < 0) ;
	return (char)c;
}

void UART_PutString(const char *s) {
	while (*s) UART_PutChar(*s++);
}

/* Символ cp1251 в UTF-8: 1..3 байта в out, возвращает их число */
static int cp1251_to_utf8(uint8_t c, char *out) {
	uint32_t u;
	if (c < 0x80U)                       { out[0] = (char)c; return 1; }
	if (c >= 0xC0U)                      u = 0x410U + (c - 0xC0U);	//А..я
	else if (c == 0xA8U)                 u = 0x401U;					//Ё
	else if (c == 0xB8U)                 u = 0x451U;					//ё
	else if (c == 0xB0U || c == 0xABU || c == 0xBBU) u = c;		//° « »
	else if (c == 0xB9U) {                                   //№ - три байта UTF-8
		out[0] = (char)0xE2; out[1] = (char)0x84; out[2] = (char)0x96; return 3;
	}
	else                                 { out[0] = '?'; return 1; }
	out[0] = (char)(0xC0U | (u >> 6));
	out[1] = (char)(0x80U | (u & 0x3FU));
	return 2;
}

void UART_PutText(const char *s) {
#if UART_TEXT_UTF8
	char u[3];
	while (*s) {
		int n = cp1251_to_utf8((uint8_t)*s++, u);
		for (int i = 0; i < n; i++) UART_PutChar(u[i]);
	}
#else
	UART_PutString(s);
#endif
}

void UART_PutDec(int32_t v) {
	char buf[12];
	int  n = 0;
	uint32_t u = (v < 0) ? (uint32_t)(-v) : (uint32_t)v;
	if (v < 0) UART_PutChar('-');
	do { buf[n++] = (char)('0' + u % 10U); u /= 10U; } while (u);
	while (n) UART_PutChar(buf[--n]);
}

void UART_PutHex(uint32_t v, uint32_t digits) {
	static const char hex[] = "0123456789ABCDEF";
	if (digits < 1U) digits = 1U;
	if (digits > 8U) digits = 8U;
	while (digits--) UART_PutChar(hex[(v >> (4U * digits)) & 0xFU]);
}

int UART_ReadLine(char *buf, int size, int echo) {
	int n = 0;
	for (;;) {
		char c = UART_ReadChar();
		if (c == '\r' || c == '\n') {
			if (n == 0 && c == '\n') continue;				//LF после CR предыдущей строки
			break;
		}
		if (c == '\b' || c == 0x7F) {						//Backspace: стереть последний байт
			if (n > 0) { n--; if (echo) UART_PutString("\b \b"); }
			continue;
		}
		if (n < size - 1) { buf[n++] = c; if (echo) UART_PutChar(c); }
	}
	buf[n] = '\0';
	if (echo) UART_PutString("\r\n");
	return n;
}

/* --- Текст --- */
int UART_Utf8ToCp1251(const char *in, char *out, int size) {
	int n = 0;
	const uint8_t *p = (const uint8_t *)in;
	while (*p && n < size - 1) {
		uint8_t c = *p++;
		if (c < 0x80U) { out[n++] = (char)c; continue; }
		if ((c & 0xE0U) == 0xC0U && (*p & 0xC0U) == 0x80U) {	//Двухбайтовый символ
			uint32_t u = ((c & 0x1FU) << 6) | (*p++ & 0x3FU);
			if (u >= 0x410U && u <= 0x44FU) out[n++] = (char)(0xC0U + (u - 0x410U));
			else if (u == 0x401U)            out[n++] = (char)0xA8U;
			else if (u == 0x451U)            out[n++] = (char)0xB8U;
			else if (u == 0xB0U || u == 0xABU || u == 0xBBU) out[n++] = (char)u;	//° « »
			else                             out[n++] = '?';
			continue;
		}
		if (c == 0xE2U && p[0] == 0x84U && p[1] == 0x96U) { p += 2; out[n++] = (char)0xB9U; continue; }	//№
		while ((*p & 0xC0U) == 0x80U) p++;						//Длинный символ - пропустить
		out[n++] = '?';
	}
	out[n] = '\0';
	return n;
}

/* --- Прерывания по заполнению FIFO --- */
void UART_IT_Start(uint32_t rx_threshold) {
	uart_rx_ring.head = uart_rx_ring.tail = uart_rx_ring.lost = 0;
	uart_tx_ring.head = uart_tx_ring.tail = uart_tx_ring.lost = 0;
	UART->RXCTRL = UART_CTRL_EN | (rx_threshold << UART_CTRL_CNT_POS);
	UART->TXCTRL = (UART->TXCTRL & (UART_CTRL_EN | UART_TXCTRL_NSTOP)) | ((UART_FIFO_DEPTH / 2U) << UART_CTRL_CNT_POS);
	UART->IE = UART_IT_RXWM;								//Передача - по UART_IT_Write
#if defined(PLIC_UART_IRQHandler)							//Источник PLIC (по умолчанию)
	PLIC_SetPriority(PLIC_SRC_UART, 1);
	PLIC_Enable(PLIC_SRC_UART);
	IRQ_Enable(MEI_IRQn);
#elif defined(UART_IRQn)									//Локальная линия
	IRQ_Enable(UART_IRQn);
#endif
}

int UART_IT_Write(const char *data, int len) {
	int n = 0;
	while (n < len && uart_tx_ring.head - uart_tx_ring.tail < UART_RING_SIZE) {
		uart_tx_ring.buf[uart_tx_ring.head & (UART_RING_SIZE - 1U)] = (uint8_t)data[n++];
		uart_tx_ring.head++;
	}
	if (n) UART->IE |= UART_IT_TXWM;						//Прерывание передачи заберёт байты
	return n;
}

void UART_IT_PutText(const char *s) {
	char u[3];
	while (*s) {
#if UART_TEXT_UTF8
		int k = cp1251_to_utf8((uint8_t)*s++, u);
#else
		int k = 1; u[0] = *s++;
#endif
		for (int i = 0; i < k; ) i += UART_IT_Write(&u[i], k - i);	//Ждать места в буфере
	}
}

int UART_IT_Read(char *data, int len) {
	int n = 0;
	while (n < len && uart_rx_ring.tail != uart_rx_ring.head) {
		data[n++] = (char)uart_rx_ring.buf[uart_rx_ring.tail & (UART_RING_SIZE - 1U)];
		uart_rx_ring.tail++;
	}
	return n;
}

#endif /* UART_PRESENT */
