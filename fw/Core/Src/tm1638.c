/*
 ******************************************************************************
 * @file        tm1638.с
 * @author		Alexander Koptyakov
 * @device		AskoRV32
 * @brief       Драйвер модуля связи с контроллером TM1638
 *****************************************************************************************
 */

#include "tm1638.h"

#if TM1638_PRESENT

void TM1638_Init(void) {
	TM1638->SEGS  = 0;
	TM1638->LEDS  = 0;
	TM1638->CTRL  = 0;			//Режим HEX, без точек
	TM1638->TEXT0 = 0;
	TM1638->TEXT1 = 0;
}

/* 8 кодов символов в регистры TEXT0/TEXT1: байт 0 TEXT0 - левый символ */
static void write_codes(const uint8_t c[8], uint32_t mode, uint32_t dots) {
	TM1638->TEXT0 = c[0] | ((uint32_t)c[1] << 8) | ((uint32_t)c[2] << 16) | ((uint32_t)c[3] << 24);
	TM1638->TEXT1 = c[4] | ((uint32_t)c[5] << 8) | ((uint32_t)c[6] << 16) | ((uint32_t)c[7] << 24);
	TM1638->CTRL  = mode | (dots << 8);
}

void TM1638_WriteText(const char *s) {
	uint8_t  c[8] = {' ', ' ', ' ', ' ', ' ', ' ', ' ', ' '};
	uint32_t dots = 0;
	int      n = 0;
	while (*s) {
		char ch = *s++;
		if ((ch == '.' || ch == ',') && n > 0 && !(dots & (1U << (n - 1)))) {
			dots |= 1U << (n - 1);		//Точка у предыдущего символа
			continue;
		}
		if (n == 8) break;
		c[n++] = (uint8_t)ch;
	}
	write_codes(c, TM1638_MODE_TEXT, dots);
}

void TM1638_WriteNumber(int32_t v) {
	uint8_t  c[8] = {' ', ' ', ' ', ' ', ' ', ' ', ' ', ' '};
	uint32_t u = (v < 0) ? (uint32_t)(-v) : (uint32_t)v;
	int      i = 7;
	do { c[i--] = (uint8_t)('0' + u % 10U); u /= 10U; } while (u && i >= 0);
	if (v < 0 && i >= 0) c[i] = '-';
	write_codes(c, TM1638_MODE_TEXT, 0);
}

void TM1638_WriteRaw(const uint8_t segs[8]) {
	write_codes(segs, TM1638_MODE_RAW, 0);
}

#endif /* TM1638_PRESENT */
