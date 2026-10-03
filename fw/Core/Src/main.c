/*
 ******************************************************************************
 * @file        main.c
 * @author		Alexander Koptyakov
 * @device		AskoRV32
 * @brief       Примеры. Пример выбирается макросом EXAMPLE:
 *                0 - счётчик таймера STIM на индикаторе TM1638 (без прерываний);
 *                1 - светодиод LED0 мигает раз в секунду по прерыванию таймера STIM (PLIC);
 *                2 - светодиод LED0 мигает раз в секунду по прерыванию машинного таймера CLINT;
 *                3 - UART, опрос: обмен значениями с ПК в обе стороны, вывод на TM1638;
 *                4 - UART на прерываниях (кольцевые буферы) и счётчик секунд по прерыванию STIM;
 *                5 - прерывание UART по наполнению FIFO приёма: пакеты по 8 байт;
 *                6 - TM1638: бегущая строка на кириллице, номер нажатой кнопки;
 *                7 - внешняя SPI-флеш: откуда загружена программа, ID флеш, счётчик запусков во флеш;
 *                8 - СИФУ тиристорного выпрямителя (блок SIFU) с имитатором сети: самопроверка, угол с терминала;
 *                9 - аналоговые измерения: АЦП ADC121S051 на платах ADC_V и ADC_C (напряжение и ток) в UART и на TM1638.
 *              Прерывания периферии идут через PLIC в векторном режиме: номера источников и имена
 *              обработчиков (PLIC_STIM_IRQHandler, PLIC_UART_IRQHandler) - в soc.h от конфигуратора.
 *              UART: терминал на ПК - 115200 8-N-1 (по умолчанию из конфигуратора), кодировка UTF-8.
 *****************************************************************************************
 */

#include "main.h"
#include "core_riscv.h"
#include "gpio.h"
#include "tm1638.h"
#include "tim.h"
#include "clint.h"
#include "plic.h"
#include "uart.h"
#include "spiflash.h"
#include "sifu.h"
#include "adc121.h"

/* Пример по умолчанию - по составу ПЛИС (soc.h): стенд выпрямителя (Tang Nano 9K: СИФУ и дискретные
   входы) - 8, платы АЦП без стенда (Tang Primer 20K) - 9, иначе - 3. Другой - -DEXAMPLE=N в настройках проекта */
#ifndef EXAMPLE
#if defined(SIFU) && defined(DI1_PIN)
#define EXAMPLE 8
#elif defined(ADC_V) || defined(ADC_C)
#define EXAMPLE 9
#else
#define EXAMPLE 3
#endif
#endif

/* Полупериод мигания, мс */
#define BLINK_HALF_PERIOD_MS 	500U

/*Прототипы функций*/
unsigned int dig_transform(unsigned int digit);

#if EXAMPLE != 0
volatile unsigned int blink_count = 0;	//Число переключений светодиода

__attribute__((unused)) static void LED_Toggle(void) {
#ifdef LED0_PIN						//На стенде выпрямителя (Tang Nano 9K) светодиодов нет
	GPIO->OUT ^= (1U << LED0_PIN);
#endif
	blink_count++;
}

/* Задержка по счётчику тактов mcycle (он же mtime) */
__attribute__((unused)) static void delay_ms(uint32_t ms) {
	uint64_t end = CORE_GetCycles() + (uint64_t)ms * (MTIME_HZ / 1000U);
	while (CORE_GetCycles() < end) ;
}

/* Разбор десятичного числа со знаком: 1 - строка целиком число */
__attribute__((unused)) static int parse_int(const char *s, int32_t *v) {
	int32_t r = 0;
	int neg = 0, digits = 0;
	while (*s == ' ') s++;
	if (*s == '-' || *s == '+') neg = (*s++ == '-');
	while (*s >= '0' && *s <= '9') { r = r * 10 + (*s++ - '0'); digits++; }
	while (*s == ' ') s++;
	*v = neg ? -r : r;
	return digits > 0 && *s == '\0';
}
#endif

#if EXAMPLE == 1
volatile unsigned int global_count = 0;	//Глобальный счётчик
/*
 * Пример 1: прерывание таймера STIM через контроллер PLIC (источник PLIC_SRC_STIM, MEI, mcause = 0x8000000B).
 * Так подключается любая периферия: приоритет и разрешение источника в PLIC, MEI в ядре.
 * PLIC в векторном режиме (PLIC_Init): ядро переходит сразу на вход таблицы векторов источника,
 * PLIC сам захватывает источник (claim). Обработчик - с __IRQ, как у любого прерывания; в конце
 * complete, после сброса флага в таймере. Предделитель делит SYSCLK_HZ до 1 кГц, счётчик
 * считает до 499: событие обновления каждые 500 мс.
 */
__IRQ void PLIC_STIM_IRQHandler(void) {
	STIM_CLEAR_FLAG_UPDATE();
	LED_Toggle();
	global_count++;
	PLIC_Complete(PLIC_SRC_STIM);
}

static void Example_Init(void) {
	STIM_InitPeriodic(SYSCLK_HZ / 1000U - 1U, BLINK_HALF_PERIOD_MS - 1U);
	STIM_IT_STATE(TIM_ENABLE);
	PLIC_Init();
	PLIC_SetPriority(PLIC_SRC_STIM, 1);
	PLIC_Enable(PLIC_SRC_STIM);
	IRQ_Enable(MEI_IRQn);
	__enable_irq();
	STIM_STATE(TIM_ENABLE);
}
#endif

#if EXAMPLE == 2
/*
 * Пример 2: прерывание машинного таймера CLINT (MTI, mcause = 0x80000007).
 * Прерывание активно, пока mtime >= mtimecmp. Обработчик сдвигает порог на полпериода
 * от предыдущего значения (а не от текущего mtime) - так период не накапливает ошибку
 * из-за задержки входа в обработчик.
 */
#define MTIME_HALF_PERIOD 	((uint64_t)MTIME_HZ / 1000U * BLINK_HALF_PERIOD_MS)

__IRQ void MTI_IRQHandler(void) {
	CLINT_SetCompare(CLINT_GetCompare() + MTIME_HALF_PERIOD);
	LED_Toggle();
}

static void Example_Init(void) {
	CLINT_SetTimeout(MTIME_HALF_PERIOD);
	IRQ_Enable(MTI_IRQn);
	__enable_irq();
}
#endif

#if EXAMPLE == 3
/*
 * Пример 3: UART опросом, обмен значениями в обе стороны. Плата печатает приглашение и ждёт строку:
 *  - число: отвечает удвоенным значением и показывает число на TM1638;
 *  - текст: отвечает длиной и показывает первые 8 символов на TM1638 (кириллица - тоже:
 *    UTF-8 от терминала переводится в cp1251 для знакогенератора индикатора).
 * Нажатая кнопка TM1638 передаётся на ПК строкой «Кнопка N». Есть ли байт в FIFO приёма, программа
 * узнаёт по IP.rxwm (порог rxcnt = 0: «в FIFO больше 0 байт») - чтение RXDATA выбрало бы байт.
 */
static void Example_Run(void) {
	char line[64], text[64];
	int32_t v;
	uint32_t keys_old = 0;

	UART_InitDefault();
	TM1638_Init();
	TM1638_WriteText("UART");
	UART_PutText("\r\naskoRV32: пример 3, UART опросом. Введите число или текст:\r\n> ");
	while (1) {
		/* Кнопки TM1638 -> ПК */
		uint32_t keys = TM1638_ReadKeys();
		for (int k = 0; k < 8; k++)
			if ((keys & ~keys_old) & (1U << k)) {
				UART_PutText("\r\nКнопка ");
				UART_PutDec(k + 1);
				UART_PutText("\r\n> ");
			}
		keys_old = keys;
		TM1638_WriteLeds(keys);
		if (!(UART->IP & UART_IT_RXWM)) continue;			//Байтов нет - снова кнопки

		/* Строка с ПК */
		if (UART_GetErrors()) UART_ClearErrors(UART_GetErrors());
		int n = UART_ReadLine(line, sizeof line, 1);
		if (n == 0) { UART_PutText("> "); continue; }
		if (parse_int(line, &v)) {
			UART_PutText("Число ");
			UART_PutDec(v);
			UART_PutText(", удвоенное: ");
			UART_PutDec(2 * v);
			TM1638_WriteNumber(v);
		} else {
			int len = UART_Utf8ToCp1251(line, text, sizeof text);
			UART_PutText("Текст «");
			UART_PutString(line);								//Как пришёл (UTF-8)
			UART_PutText("», символов: ");
			UART_PutDec(len);
			TM1638_WriteText(text);
		}
		UART_PutText("\r\n> ");
	}
}
#endif

#if EXAMPLE == 4
/*
 * Пример 4: UART на прерываниях и таймер STIM - два источника PLIC.
 *  - STIM раз в секунду увеличивает счётчик секунд, основной цикл передаёт его на ПК;
 *  - UART: прерывание приёма - на каждый байт (порог 0), передачи - когда в FIFO меньше половины;
 *    байты копятся в кольцевых буферах драйвера, основной цикл не ждёт UART;
 *  - принятая строка показывается на TM1638 и возвращается на ПК.
 */
volatile uint32_t seconds = 0;

__IRQ void PLIC_STIM_IRQHandler(void) {
	STIM_CLEAR_FLAG_UPDATE();
	seconds++;
	LED_Toggle();
	PLIC_Complete(PLIC_SRC_STIM);
}

__IRQ void PLIC_UART_IRQHandler(void) {
	UART_IRQ_Service();									//FIFO <-> кольцевые буферы
	PLIC_Complete(PLIC_SRC_UART);
}

/* Передать всё: UART_IT_Write кладёт в буфер сколько поместится, остальное дописываем по мере
   освобождения места (буфер опустошает обработчик прерывания) */
static void it_write_all(const char *data, int len) {
	for (int i = 0; i < len; ) i += UART_IT_Write(&data[i], len - i);
}

/* Число в строку: возвращает длину */
static int utoa10(uint32_t u, char *out) {
	char d[10];
	int m = 0, k = 0;
	do { d[m++] = (char)('0' + u % 10U); u /= 10U; } while (u);
	while (m) out[k++] = d[--m];
	return k;
}

static void Example_Run(void) {
	char line[64], text[64], msg[16];
	int  n = 0;
	uint32_t shown = 0;

	UART_InitDefault();
	TM1638_Init();
	PLIC_Init();
	STIM_InitPeriodic(SYSCLK_HZ / 1000U - 1U, 1000U - 1U);	//Событие раз в 1 с
	STIM_IT_STATE(TIM_ENABLE);
	PLIC_SetPriority(PLIC_SRC_STIM, 1);
	PLIC_Enable(PLIC_SRC_STIM);
	UART_IT_Start(0);									//Прерывание приёма на каждый байт
	__enable_irq();
	STIM_STATE(TIM_ENABLE);
	UART_IT_PutText("\r\naskoRV32: пример 4, UART на прерываниях. Каждую секунду - счётчик, введите строку:\r\n");

	while (1) {
		if (seconds != shown) {							//Секунда прошла
			shown = seconds;
			int k = 0;
			msg[k++] = '[';
			k += utoa10(shown, &msg[k]);
			msg[k++] = ']'; msg[k++] = ' ';
			it_write_all(msg, k);
			if (n == 0) TM1638_WriteNumber((int32_t)shown);
		}
		char c;
		while (UART_IT_Read(&c, 1)) {					//Принятое - из буфера, без ожидания
			if (c == '\r' || c == '\n') {
				if (n == 0) continue;
				line[n] = '\0';
				UART_Utf8ToCp1251(line, text, sizeof text);
				TM1638_WriteText(text);
				UART_IT_PutText("\r\nПринято: ");
				it_write_all(line, n);
				UART_IT_PutText("\r\n");
				n = 0;
			} else if (n < (int)sizeof line - 1) {
				line[n++] = c;
				it_write_all(&c, 1);					//Эхо
			}
		}
	}
}
#endif

#if EXAMPLE == 5
/*
 * Пример 5: прерывание по наполнению FIFO приёма. Порог rxcnt = 7: прерывание приходит, когда в FIFO
 * больше 7 байт, то есть накопился пакет из 8 байт. Обработчик сам забирает 8 байт из FIFO (без
 * кольцевых буферов) и отдаёт пакет основному циклу, тот отвечает суммой байтов. Пока пакет не
 * набран, прерываний нет - программа не отвлекается на каждый байт.
 * Проверка: отправить с ПК 8 символов, например «12345678» (сумма кодов 420).
 */
volatile uint8_t  packet[8];
volatile uint32_t packets = 0;

__IRQ void PLIC_UART_IRQHandler(void) {
	for (int i = 0; i < 8; i++) packet[i] = (uint8_t)UART->RXDATA;	//В FIFO заведомо больше 7 байт
	packets++;
	PLIC_Complete(PLIC_SRC_UART);
}

static void Example_Run(void) {
	uint32_t done = 0;
	UART_InitDefault();
	TM1638_Init();
	TM1638_WriteText("ПАКЕТ 8");
	PLIC_Init();
	UART->RXCTRL = UART_CTRL_EN | (7U << UART_CTRL_CNT_POS);			//Порог: больше 7 байт
	UART->IE = UART_IT_RXWM;
	PLIC_SetPriority(PLIC_SRC_UART, 1);
	PLIC_Enable(PLIC_SRC_UART);
	IRQ_Enable(MEI_IRQn);
	__enable_irq();
	UART_PutText("\r\naskoRV32: пример 5, прерывание по наполнению FIFO. Отправьте 8 символов:\r\n");
	while (1) {
		if (packets == done) continue;
		uint8_t  pkt[8];
		__disable_irq();									//Копия пакета: следующий может прийти во время вывода
		for (int i = 0; i < 8; i++) pkt[i] = packet[i];
		done = packets;
		__enable_irq();
		uint32_t sum = 0;
		for (int i = 0; i < 8; i++) sum += pkt[i];
		UART_PutText("Пакет ");
		UART_PutDec((int32_t)done);
		UART_PutText(": ");
		for (int i = 0; i < 8; i++) { UART_PutHex(pkt[i], 2); UART_PutChar(' '); }
		UART_PutText(" сумма ");
		UART_PutDec((int32_t)sum);
		UART_PutText("\r\n");
		TM1638_WriteNumber((int32_t)sum);
		LED_Toggle();
	}
}
#endif

#if EXAMPLE == 6
/*
 * Пример 6: текст на TM1638. Бегущая строка на кириллице (строки в cp1251 - кодировка проекта),
 * нажатая кнопка - надпись «КНОП. N» на 1 с. Точка после символа не занимает позицию.
 */
static void Example_Run(void) {
	static const char msg[] = "        ПРИВЕТ. ЭТО askoRV32 НА ПЛИС GW1NR-9. 3.14159        ";
	int pos = 0;
	uint32_t keys_old = 0;
	TM1638_Init();
	while (1) {
		uint32_t keys = TM1638_ReadKeys();
		TM1638_WriteLeds(keys);
		uint32_t pressed = keys & ~keys_old;
		keys_old = keys;
		if (pressed) {
			char t[] = "КНОП.  0";
			for (int k = 0; k < 8; k++) if (pressed & (1U << k)) t[7] = (char)('1' + k);
			TM1638_WriteText(t);
			delay_ms(1000);
			continue;
		}
		/* Окно из 8 символов строки, начиная с pos (точка не считается позицией) */
		TM1638_WriteText(&msg[pos]);
		delay_ms(300);
		if (msg[++pos] == '.') pos++;
		if (msg[pos + 8] == '\0') pos = 0;
	}
}
#endif

#if EXAMPLE == 7
/*
 * Пример 7: внешняя SPI-флеш (блок SPIFLASH). В UART - итог загрузчика (программа из флеш или из
 * битового потока ПЛИС), JEDEC ID флеш и счётчик запусков. Счётчик - образец хранения параметров:
 * лежит в свободной области флеш (SPIFLASH_USER_ADDR из soc.h) с признаком и контрольным словом;
 * при каждом старте (питание, кнопка S2, сброс отладчиком) читается, увеличивается и записывается:
 * стирание сектора 4 кБайт, затем запись. Светодиод LED0 мигает.
 */
typedef struct
{
	uint32_t magic;			//PARAMS_MAGIC - запись есть
	uint32_t boots;			//Число запусков
	uint32_t check;			//~boots - запись цела
} Params;
#define PARAMS_MAGIC	0x314D5250U		//"PRM1"

static void Example_Run(void) {
	static const char *const boot_txt[] = {"загрузчик выключен", "программа из флеш",
		"образа во флеш нет - программа из битового потока ПЛИС", "образ испорчен (контрольная сумма)",
		"образ испорчен (разметка)"};
	Params p;
	SPIFLASH_Status st;
	SPIFLASH_BootResult b;

	UART_InitDefault();
	SPIFLASH_InitDefault();
	UART_PutText("\r\n== askoRV32: внешняя SPI-флеш ==\r\nЗагрузка: ");
	b = SPIFLASH_BootStatus();
	UART_PutText(b <= SPIFLASH_BOOT_FORMAT ? boot_txt[b] : "?");
	if (b == SPIFLASH_BOOT_OK) {
		UART_PutText(", образ ");
		UART_PutDec((int32_t)(SPIFLASH_BootWords() * 4U));
		UART_PutText(" Байт");
	}
	UART_PutText("\r\nJEDEC ID: 0x");
	UART_PutHex(SPIFLASH_ReadID(), 6);

	/* Счётчик запусков в свободной области флеш */
	SPIFLASH_Read(SPIFLASH_USER_ADDR, &p, sizeof p);
	if (p.magic != PARAMS_MAGIC || p.check != ~p.boots) {	//Флеш стёрта или запись испорчена
		p.magic = PARAMS_MAGIC;
		p.boots = 0U;
	}
	p.boots++;
	p.check = ~p.boots;
	st = SPIFLASH_EraseSector(SPIFLASH_USER_ADDR);
	if (st == SPIFLASH_OK) st = SPIFLASH_Write(SPIFLASH_USER_ADDR, &p, sizeof p);
	UART_PutText("\r\nЗапусков: ");
	UART_PutDec((int32_t)p.boots);
	UART_PutText(st == SPIFLASH_OK ? " (записано во флеш)\r\n" : " (ошибка записи во флеш)\r\n");

	while (1) {
		LED_Toggle();
		delay_ms(500);
	}
}
#endif

/*
 * Платы АЦП (блоки ADC121: ADC_V - напряжение, ADC_C - ток) для примеров 8 и 9: какие есть в
 * конфигурации ПЛИС (soc.h), пересчёт кода из конфигуратора, вывод в UART и на TM1638.
 */
#if (EXAMPLE == 8 || EXAMPLE == 9) && (defined(ADC_V) || defined(ADC_C))
#define ADC_ON				1
#define ADC_SHOW_MS			2000U		//Смена показания на индикаторе
#define ADC_DISP_MS			500U		//Обновление индикатора: 2 раза в секунду
#define KEY_SHOW_I			(1U << 1)	//Кнопка 7 TM1638 (вторая справа, бит 1 KEYS): только ток
#define KEY_SHOW_U			(1U << 0)	//Кнопка 8 (крайняя правая, бит 0): только напряжение

typedef struct
{
	ADC121_TypeDef *adc;
	ADC121_Cal      cal;
	const char     *name;
	char            sym;				//'U' - напряжение, 'I' - ток
	uint32_t        has_cmp;
	uint32_t        errs, cmps, cnt_old, rate;
} AdcBoard;

static AdcBoard boards[] = {
#ifdef ADC_V
	{ ADC_V, { ADC_V_SCALE_U, ADC_V_OFFSET_M }, "ADC_V", 'U', ADC_V_CMP, 0, 0, 0, 0 },
#endif
#ifdef ADC_C
	{ ADC_C, { ADC_C_SCALE_U, ADC_C_OFFSET_M }, "ADC_C", 'I', ADC_C_CMP, 0, 0, 0, 0 },
#endif
};
#define ADC_BOARDS		(sizeof boards / sizeof boards[0])

/* Тысячные доли - текстом «-12.345» (digits знаков после точки: 1..3) */
static int fmt_milli(char *s, int32_t v, int digits) {
	int n = 0;
	uint32_t u, div = 1000U;
	if (v < 0) { s[n++] = '-'; u = (uint32_t)(-v); } else u = (uint32_t)v;
	for (int i = digits; i < 3; i++) { u = (u + 5U) / 10U; div /= 10U; }	//Округление до digits знаков
	uint32_t ip = u / div, fp = u % div;
	char d[10];
	int m = 0;
	do { d[m++] = (char)('0' + ip % 10U); ip /= 10U; } while (ip);
	while (m) s[n++] = d[--m];
	s[n++] = '.';
	for (uint32_t k = div / 10U; k; k /= 10U) { s[n++] = (char)('0' + fp / k % 10U); }
	s[n] = '\0';
	return n;
}

__attribute__((unused)) static void put_k(uint32_t v) {						//Тысячные - «12.345»
	UART_PutDec((int32_t)(v / 1000U)); UART_PutChar('.');
	UART_PutChar((char)('0' + v / 100U % 10U)); UART_PutChar((char)('0' + v / 10U % 10U)); UART_PutChar((char)('0' + v % 10U));
}

static void adc_status(AdcBoard *b) {
	char t[16];
	uint32_t sh = b->adc->AVG & 0xFU, sum = ADC121_GetSum(b->adc);
	int32_t mv = ADC121_MeanMilli(b->adc, b->cal);
	UART_PutText(b->name);
	UART_PutText(": код ");
	fmt_milli(t, (int32_t)(((uint64_t)sum * 1000U) >> sh), 1);			//Среднее с десятыми
	UART_PutText(t);
	UART_PutText(" (среднее по ");
	UART_PutDec((int32_t)(1U << sh));
	UART_PutText(", последний ");
	UART_PutDec((int32_t)ADC121_GetRaw(b->adc));
	UART_PutText(", кадр 0x");
	UART_PutHex(ADC121_GetFrame(b->adc), 4);
	UART_PutText("), ");
	UART_PutChar(b->sym);
	UART_PutText(" = ");
	fmt_milli(t, mv, b->sym == 'U' ? 2 : 3);
	UART_PutText(t);
	UART_PutText(b->sym == 'U' ? " В, " : " А, ");
	UART_PutDec((int32_t)b->rate);
	UART_PutText(" отсч./с, ошибок кадра ");
	UART_PutDec((int32_t)b->errs);
	if (b->has_cmp) {
		UART_PutText(ADC121_CmpActive(b->adc) ? ", CMP: СРАБОТАЛ" : ", CMP: норма");
		UART_PutText(", срабатываний ");
		UART_PutDec((int32_t)b->cmps);
	}
	UART_PutText("\r\n");
}

/* TM1638: «U 59.99» или «I 0.999» */
static void adc_show(AdcBoard *b) {
	char d[12];
	int32_t mv = ADC121_MeanMilli(b->adc, b->cal);
	d[0] = b->sym;
	d[1] = ' ';
	if (b->sym == 'U') fmt_milli(&d[2], mv, (mv > -100000 && mv < 1000000) ? 2 : 1);
	else               fmt_milli(&d[2], mv, (mv > -10000 && mv < 100000) ? 3 : 2);
	TM1638_WriteText(d);
}

/* Плата по символу: 'U' или 'I' (нет такой - NULL) */
static AdcBoard *adc_by_sym(char sym) {
	for (uint32_t i = 0; i < ADC_BOARDS; i++)
		if (boards[i].sym == sym) return &boards[i];
	return 0;
}

/* Пуск: значения конфигуратора (после сброса), непрерывные преобразования */
static void adc_boards_start(void) {
	for (uint32_t i = 0; i < ADC_BOARDS; i++) {
		AdcBoard *b = &boards[i];
		ADC121_Init(b->adc, b->adc->DIV & ADC121_DIV_MSK, b->adc->AVG & 0xFU);
		ADC121_Start(b->adc);
		b->cnt_old = ADC121_GetCount(b->adc);
	}
}

/* Флаги: ошибки кадра и срабатывания компаратора (зовётся в цикле) */
static void adc_poll(void) {
	for (uint32_t i = 0; i < ADC_BOARDS; i++) {
		AdcBoard *b = &boards[i];
		uint32_t f = ADC121_GetFlags(b->adc) & (ADC121_SR_ERR | ADC121_SR_CMPF);
		if (f) {
			ADC121_ClearFlags(b->adc, f);
			if (f & ADC121_SR_ERR)  b->errs++;
			if (f & ADC121_SR_CMPF) b->cmps++;
		}
	}
}

/* Частота отсчётов: отсчётов с прошлого вызова * mult (вызовы раз в 1/mult с) */
static void adc_rate_update(uint32_t mult) {
	for (uint32_t i = 0; i < ADC_BOARDS; i++) {
		AdcBoard *b = &boards[i];
		uint32_t c = ADC121_GetCount(b->adc);
		b->rate = (c - b->cnt_old) * mult;
		b->cnt_old = c;
	}
}

/* Кратко для строки состояния: «, U = 49.98 В, I = 0.930 А» (кадр с ошибкой - «нет связи») */
__attribute__((unused)) static void adc_brief(void) {
	char s[16];
	for (uint32_t i = 0; i < ADC_BOARDS; i++) {
		AdcBoard *b = &boards[i];
		UART_PutText(", ");
		UART_PutChar(b->sym);
		UART_PutText(" = ");
		if (ADC121_GetFrame(b->adc) & 0xF000U) { UART_PutText("нет связи"); continue; }
		fmt_milli(s, ADC121_MeanMilli(b->adc, b->cal), b->sym == 'U' ? 2 : 3);
		UART_PutText(s);
		UART_PutText(b->sym == 'U' ? " В" : " А");
		if (b->has_cmp && ADC121_CmpActive(b->adc)) UART_PutText(" (CMP!)");
	}
}
#endif

#if EXAMPLE == 8
/*
 * Пример 8: СИФУ трёхфазного мостового тиристорного выпрямителя (блок SIFU) без силовой части:
 * сигналы шести оптронов платы NSB даёт имитатор сети в самом блоке (50 Гц, мёртвая зона 2 град.).
 * Имитатор выдаёт сигналы так же, как NSB, поэтому DELAY (компенсация RC-фильтра NSB) остаётся
 * значением из конфигуратора: при ALPHA = 0 импульс - через DELAY тиков от начала окна оптрона.
 *
 * При старте - самопроверка: для углов 0, 30, 60, 90, 120 эл. град. программа по счётчику тактов
 * (mcycle) измеряет у каждого тиристора VS1..VS6 задержку фронта импульса от начала его полуволны и
 * длительность импульса (в тиках ГПН) и сравнивает с ожидаемыми. Меряются импульсы пар до
 * разрешения (GATE[13:8]): EN при этом 0, на драйверы тиристоров импульсы не идут. Ожидается:
 * ALPHA + DELAY и WIDTH (начало полуволны модуль видит после фильтра входов, импульс отсчитывается от
 * того же момента). Угол меняется двумя левыми кнопками TM1638 (крайняя левая - угол больше, вторая
 * слева - меньше, шаг 0.5 град. по сетке 0.5, удержание - автоповтор) или с терминала (115200 8-N-1,
 * cp1251):
 *   число 0..127 (можно с десятыми: 32.5) - угол управления, эл. град.;
 *   e - импульсы вкл./выкл. (EN); d - сдвоенные импульсы вкл./выкл.;
 *   n - входы платы NSB (настоящая сеть); s - снова имитатор; t - повторить самопроверку;
 *   g - синхронизация: смены шести входов (после фильтра) за два периода сети с длительностями.
 * Угол - до 120 эл. град. (SIFU_ALPHA_LIMIT_DEG10).
 * Строка состояния (Enter или команда) - частота сети, полупериод, угол, состояние; с платами АЦП
 * (блоки ADC_V, ADC_C в конфигурации ПЛИС) - ещё напряжение и ток, команда u - подробно по платам.
 * TM1638: по кругу через 2 с угол, ток, напряжение (какие платы есть), обновление 2 раза в секунду;
 * пока зажата кнопка 6 - угол, 7 - ток, 8 - напряжение; угол, изменённый кнопками 1, 2 (или с
 * терминала), показывается сразу, и круг начинается с него. Светодиоды: 1 - сеть есть,
 * 2 - нет синхронизации, 3 - EN, 4 - имитатор. Импульсы VS1..VS6 - на выводах ПЛИС (Tang Nano 9K:
 * 28..33, Tang Primer 20K: разъём PMOD J5) - их можно смотреть осциллографом.
 * Стенд выпрямителя (Tang Nano 9K, цепи DI1..DI3 и RO1..RO3 в конфигураторе): дискретные входы
 * повторяются на выходах программой - DI1 -> RO1, DI2 -> RO2, DI3 -> RO3 (в основном цикле; на время
 * самопроверки и ввода строки с терминала выходы не обновляются). Состояние - в строке состояния.
 * Импульсы на драйверы тиристоров на стенде включают входы: DI1 = 1 - синхронизация от сети (входы
 * NSB), DI2 = 1 - от имитатора сети; оба 0 или оба 1 - импульсов нет. При смене источника импульсы
 * снимаются на 40 мс (пары заново находят полярность). Команды e, n, s на стенде при включённом DI1
 * или DI2 не действуют. Индикатор показывает заданный угол; тики ALPHA раз в секунду пересчитываются
 * по полупериоду сети, усреднённому за секунду (угол в градусах держится при уходе частоты).
 */
#define SIFU_SIM_FREQ100	5000U		//Частота имитатора: 50.00 Гц
#define SIFU_SIM_DZ10		20U			//Мёртвая зона имитатора: 2.0 град.
#define KEY_ALPHA_UP		(1U << 7)	//Крайняя левая кнопка TM1638 (на плате стенда - бит 7 KEYS): угол больше
#define KEY_ALPHA_DOWN		(1U << 6)	//Вторая слева: угол меньше
#define KEY_STEP_DEG10		5U			//Шаг угла кнопкой: 0.5 град.
#define KEY_SHOW_ALPHA		(1U << 2)	//Кнопка 6 (третья справа, бит 2): только угол
#define KEY_DELAY_MS		500U		//Удержание: автоповтор через 0.5 с...
#define KEY_REPEAT_MS		100U		//...каждые 0.1 с
#ifndef ADC_SHOW_MS
#define ADC_SHOW_MS			2000U		//Смена показания на индикаторе
#define ADC_DISP_MS			500U		//Обновление индикатора
#endif

/* Дискретные входы и выходы стенда - если цепи DI1..DI3, RO1..RO3 есть в конфигурации ПЛИС (soc.h) */
#if defined(DI1_PIN) && defined(DI2_PIN) && defined(DI3_PIN) && defined(RO1_PIN) && defined(RO2_PIN) && defined(RO3_PIN)
#define STAND_IO	1
static void stand_io_init(void) {
	GPIO_MODE(DI1, GPIO_MODE_INPUT);
	GPIO_MODE(DI2, GPIO_MODE_INPUT);
	GPIO_MODE(DI3, GPIO_MODE_INPUT);
	GPIO_WRITE(RO1, GPIO_PIN_RESET);
	GPIO_WRITE(RO2, GPIO_PIN_RESET);
	GPIO_WRITE(RO3, GPIO_PIN_RESET);
	GPIO_MODE(RO1, GPIO_MODE_OUTPUT);
	GPIO_MODE(RO2, GPIO_MODE_OUTPUT);
	GPIO_MODE(RO3, GPIO_MODE_OUTPUT);
}
/* Входы -> выходы: DIn -> ROn. Импульсы на драйверы (CR.EN) и источник синхронизации - по DI1, DI2:
   DI1 - сеть (входы NSB), DI2 - имитатор; оба 0 или оба 1 - импульсов нет. Возвращает 1, если
   источник задан входами (команды n, s не действуют) */
#define STAND_SRC_HOLD_MS	40U			//После смены источника импульсы сняты: 2 периода сети
static uint64_t stand_hold = 0U;
static int stand_io_copy(void) {
	uint32_t di1 = GPIO_READ(DI1), di2 = GPIO_READ(DI2);
	uint64_t now = CORE_GetCycles();
	GPIO_WRITE(RO1, di1);
	GPIO_WRITE(RO2, di2);
	GPIO_WRITE(RO3, GPIO_READ(DI3));
	if (di1 == di2) {									//Ни одного или оба - импульсов нет
		SIFU_Disable();
		return di1;
	}
	uint32_t sim = (SIFU->CR & SIFU_CR_SIM) != 0U;
	if (di2 != sim) {									//Смена источника
		SIFU_Disable();
		if (di2) SIFU_SimStart(SIFU_SIM_FREQ100, SIFU_SIM_DZ10);
		else     SIFU_SimStop();
		stand_hold = now + (uint64_t)MTIME_HZ / 1000U * STAND_SRC_HOLD_MS;
	}
	if (now >= stand_hold) SIFU_Enable();
	else                   SIFU_Disable();
	return 1;
}
#else
#define STAND_IO	0
#endif

/* Измерение тиристора k (1..6): начало его полуволны (SR.SYNCF с CH = k) -> фронт и спад импульса
   пары до сдваивания и разрешения EN (GATE[13:8]) - выводы не нужны. Результат - в тиках ГПН;
   0 - не дождались (100 мс) */
static int sifu_measure(uint32_t k, uint32_t *lag, uint32_t *width) {
	uint32_t div1 = SIFU->DIV + 1U, bit = 1U << (SIFU_GATE_DIRECT_POS + k - 1U);
	uint32_t t0, t1, t2, start = (uint32_t)CORE_GetCycles(), tout = SYSCLK_HZ / 10U;

	SIFU_ClearFlags(SIFU_SR_SYNCF);
	for (;;) {											//Начало полуволны тиристора k
		uint32_t sr = SIFU->SR;
		if (sr & SIFU_SR_SYNCF) {
			if (((sr & SIFU_SR_CH_MSK) >> SIFU_SR_CH_POS) == k) break;
			SIFU_ClearFlags(SIFU_SR_SYNCF);				//Началась полуволна другого тиристора
		}
		if ((uint32_t)CORE_GetCycles() - start > tout) return 0;
	}
	t0 = (uint32_t)CORE_GetCycles();
	while (!(SIFU->GATE & bit)) if ((uint32_t)CORE_GetCycles() - start > tout) return 0;
	t1 = (uint32_t)CORE_GetCycles();
	while (SIFU->GATE & bit) if ((uint32_t)CORE_GetCycles() - start > tout) return 0;
	t2 = (uint32_t)CORE_GetCycles();
	*lag   = (t1 - t0 + div1 / 2U) / div1;
	*width = (t2 - t1 + div1 / 2U) / div1;
	return 1;
}

/* Угол в десятых долях градуса - текстом «30.0» */
static void put_deg10(uint32_t d10) {
	UART_PutDec((int32_t)(d10 / 10U));
	UART_PutChar('.');
	UART_PutChar((char)('0' + d10 % 10U));
}

/* Самопроверка: углы 0..120 град., у каждого тиристора - задержка и длительность импульса.
   Возвращает число ошибок */
static int sifu_selftest(void) {
	static const uint16_t angles[] = {0U, 300U, 600U, 900U, 1200U};
	uint32_t keep_cr = SIFU->CR, keep_alpha = SIFU->ALPHA;
	int errors = 0;

	SIFU_Disable();										//На выводы импульсы не идут: меряются GATE[13:8]
	UART_PutText("Самопроверка: задержка фронта VSk от начала его полуволны / длительность, тиков ГПН\r\n");
	UART_PutText("  угол   ALPHA  ожид.     VS1       VS2       VS3       VS4       VS5       VS6\r\n");
	for (uint32_t a = 0; a < sizeof angles / sizeof angles[0]; a++) {
		SIFU_SetAlphaDeg10(angles[a]);
		delay_ms(50);									//Новый угол - с новой полуволны каждой пары
		uint32_t alpha = SIFU->ALPHA, exp_lag = alpha + SIFU->DELAY, exp_w = SIFU->WIDTH;
		UART_PutText("  ");
		put_deg10(angles[a]);
		UART_PutText("\t ");
		UART_PutDec((int32_t)alpha);
		UART_PutText("\t");
		UART_PutDec((int32_t)exp_lag);
		UART_PutText("/");
		UART_PutDec((int32_t)exp_w);
		for (uint32_t k = 1; k <= 6; k++) {
			uint32_t lag = 0, w = 0;
			int ok = sifu_measure(k, &lag, &w);
			UART_PutText("  ");
			if (!ok) { UART_PutText("нет!    "); errors++; continue; }
			UART_PutDec((int32_t)lag);
			UART_PutChar('/');
			UART_PutDec((int32_t)w);
			/* Допуск: опрос регистров программой - около тика */
			if (lag + 2U < exp_lag || lag > exp_lag + 2U || w + 2U < exp_w || w > exp_w + 2U) {
				UART_PutChar('!');
				errors++;
			}
		}
		UART_PutText("\r\n");
	}
	SIFU->CR = keep_cr;
	SIFU->ALPHA = keep_alpha;
	UART_PutText(errors ? "Самопроверка: ОШИБКИ - " : "Самопроверка пройдена, ошибок ");
	UART_PutDec(errors);
	UART_PutText("\r\n");
	return errors;
}

/* Синхронизация за два периода сети: каждое состояние шести входов после фильтра (1 - оптрон закрыт,
   порядок AB BA BC CB CA AC) и его длительность в микросекундах и градусах */
static void sifu_sync_trace(void) {
	uint32_t st[40], dt[40], n = 0;
	uint32_t prev = SIFU->SR & SIFU_SR_SYNC_MSK, t0 = (uint32_t)CORE_GetCycles(), tl = t0;
	uint32_t per = SIFU_HalfPeriod() * (SIFU->DIV + 1U);	//Полупериод, тактов
	while ((uint32_t)CORE_GetCycles() - t0 < SYSCLK_HZ / 25U && n < 40U) {	//40 мс
		uint32_t s = SIFU->SR & SIFU_SR_SYNC_MSK;
		if (s != prev) {
			uint32_t now = (uint32_t)CORE_GetCycles();
			st[n] = prev; dt[n] = now - tl; n++;
			tl = now; prev = s;
		}
	}
	UART_PutText("Входы NSB за 40 мс (AB BA BC CB CA AC, 1 - оптрон закрыт): длительность, мкс / эл. град.\r\n");
	for (uint32_t i = 0; i < n; i++) {
		UART_PutText("  ");
		for (uint32_t b = 0; b < 6U; b++) { UART_PutChar((st[i] >> b) & 1U ? '1' : '0'); UART_PutChar(' '); }
		UART_PutText(i == 0 ? " (с начала записи) " : " ");
		UART_PutDec((int32_t)(dt[i] / (SYSCLK_HZ / 1000000U)));
		UART_PutText(" мкс / ");
		put_deg10((uint32_t)(((uint64_t)dt[i] * 1800U + per / 2U) / per));
		UART_PutText("\r\n");
	}
	if (n == 0) UART_PutText("  смен нет - сигналы стоят\r\n");
}

/* Разбор угла «32» или «32.5» в десятые доли градуса; -1 - не число */
static int32_t parse_deg10(const char *s) {
	int32_t v = 0, frac = 0, digits = 0;
	while (*s == ' ') s++;
	while (*s >= '0' && *s <= '9') { v = v * 10 + (*s++ - '0'); digits++; }
	if (*s == '.' || *s == ',') {
		s++;
		if (*s >= '0' && *s <= '9') frac = *s++ - '0';
		while (*s >= '0' && *s <= '9') s++;
	}
	while (*s == ' ') s++;
	return (digits && *s == '\0') ? v * 10 + frac : -1;
}

/* Заданный угол (десятые доли градуса) и полупериод сети, усреднённый за секунду (0 - ещё нет) */
static uint32_t sifu_alpha10 = 300U;
static uint32_t sifu_hper_avg = 0U;
static uint32_t hper_sum = 0U, hper_n = 0U;

/* Угол в тики ALPHA: по усреднённому полупериоду, пока его нет - по последнему измеренному */
static void sifu_apply_alpha(void) {
	uint32_t max10 = SIFU_AlphaMaxDeg10();
	if (sifu_alpha10 > max10) sifu_alpha10 = max10;
	if (sifu_hper_avg) SIFU_SetAlpha((sifu_alpha10 * sifu_hper_avg + 900U) / 1800U);
	else               SIFU_SetAlphaDeg10(sifu_alpha10);
}

/* Отсчёт полупериода (зовётся в цикле, берёт раз в 10 мс) и итог раз в секунду */
static void sifu_hper_sample(void) {
	static uint64_t next = 0U;
	uint64_t now = CORE_GetCycles();
	if (now < next) return;
	next = now + (uint64_t)MTIME_HZ / 100U;
	uint32_t h = SIFU->HPER;
	if (SIFU_GridPresent() && h >= 1000U && h < SIFU_LOST_TICKS) { hper_sum += h; hper_n++; }
}
static void sifu_hper_update(void) {
	sifu_hper_avg = hper_n ? (hper_sum + hper_n / 2U) / hper_n : 0U;
	hper_sum = hper_n = 0U;
	sifu_apply_alpha();
}

static void sifu_status(void) {
	uint32_t sr = SIFU->SR, f = SIFU_GridFreq100();
	UART_PutText("f = ");
	if (f) { UART_PutDec((int32_t)(f / 100U)); UART_PutChar('.'); UART_PutDec((int32_t)(f % 100U / 10U)); UART_PutDec((int32_t)(f % 10U)); UART_PutText(" Гц"); }
	else UART_PutText("нет");
	UART_PutText(", HPER ");
	UART_PutDec((int32_t)SIFU->HPER);
	UART_PutText(", угол ");
	put_deg10(sifu_alpha10);
	UART_PutText(" (ALPHA ");
	UART_PutDec((int32_t)SIFU->ALPHA);
	UART_PutText(", макс. ");
	put_deg10(SIFU_AlphaMaxDeg10());
	UART_PutText("), EN ");
	UART_PutDec((SIFU->CR & SIFU_CR_EN) ? 1 : 0);
	UART_PutText(", DBL ");
	UART_PutDec((SIFU->CR & SIFU_CR_DBL) ? 1 : 0);
	UART_PutText((SIFU->CR & SIFU_CR_SIM) ? ", имитатор" : ", входы NSB");
	UART_PutText(", SR 0x");
	UART_PutHex(sr, 5);
	UART_PutText((sr & SIFU_SR_GRID) ? " сеть есть" : " сети нет");
	if (sr & SIFU_SR_LOST) UART_PutText(", нет синхронизации");
#ifdef ADC_ON
	adc_brief();
#endif
#if STAND_IO
	UART_PutText(", DI ");
	UART_PutDec(GPIO_READ(DI1)); UART_PutDec(GPIO_READ(DI2)); UART_PutDec(GPIO_READ(DI3));
	UART_PutText(" RO ");
	UART_PutDec(GPIO_READ(RO1)); UART_PutDec(GPIO_READ(RO2)); UART_PutDec(GPIO_READ(RO3));
#endif
	UART_PutText("\r\n");
}

/* Светодиоды TM1638: 1 - сеть есть, 2 - нет синхронизации, 3 - EN, 4 - имитатор */
static void sifu_leds(void) {
	uint32_t sr = SIFU->SR, cr = SIFU->CR;
	TM1638_WriteLeds(((sr & SIFU_SR_GRID) ? 1U : 0U) | ((sr & SIFU_SR_LOST) ? 2U : 0U) |
	                 ((cr & SIFU_CR_EN) ? 4U : 0U) | ((cr & SIFU_CR_SIM) ? 8U : 0U));
}

/* Угол на индикаторе: «УГОЛ 30.0» */
static void sifu_show_alpha(void) {
	char t[12];
	uint32_t d10 = sifu_alpha10;					//Заданный угол
	int n = 0;
	t[n++] = 'У'; t[n++] = 'Г'; t[n++] = 'О'; t[n++] = 'Л';
	if (d10 < 1000U) t[n++] = ' ';
	if (d10 >= 1000U) t[n++] = (char)('0' + d10 / 1000U);
	if (d10 >= 100U) t[n++] = (char)('0' + d10 / 100U % 10U); else t[n++] = ' ';
	t[n++] = (char)('0' + d10 / 10U % 10U);
	t[n++] = '.';
	t[n++] = (char)('0' + d10 % 10U);
	t[n] = '\0';
	TM1638_WriteText(t);
}

/* Индикатор: показания по кругу - угол, ток, напряжение (каких плат нет - пропускаются), смена
   через 2 с, обновление 2 раза в секунду; зажата кнопка 6 - угол, 7 - ток, 8 - напряжение */
enum { SHOW_ALPHA = 0, SHOW_I, SHOW_U, SHOW_N };
static uint32_t disp_item = SHOW_ALPHA, disp_keys_old = 0U;
static uint64_t disp_next = 0U, disp_next_item = 0U;

static int disp_has(uint32_t item) {
#ifdef ADC_ON
	if (item == SHOW_I) return adc_by_sym('I') != 0;
	if (item == SHOW_U) return adc_by_sym('U') != 0;
#endif
	return item == SHOW_ALPHA;
}

/* Угол изменён - показать его сразу, круг - с него */
static void sifu_show(void) {
	uint64_t now = CORE_GetCycles();
	disp_item = SHOW_ALPHA;
	disp_next_item = now + (uint64_t)MTIME_HZ / 1000U * ADC_SHOW_MS;
	disp_next = now;
}

static void disp_update(void) {
	uint64_t now = CORE_GetCycles();
	uint32_t keys = TM1638_ReadKeys() & (KEY_SHOW_ALPHA | KEY_SHOW_I | KEY_SHOW_U);
	int held = (keys == KEY_SHOW_ALPHA) ? SHOW_ALPHA : (keys == KEY_SHOW_I) ? SHOW_I : (keys == KEY_SHOW_U) ? SHOW_U : -1;
	if (held >= 0 && !disp_has((uint32_t)held)) held = -1;
	if (keys != disp_keys_old) {						//Нажали или отпустили - показать сразу
		disp_keys_old = keys;
		disp_next = now;
		disp_next_item = now + (uint64_t)MTIME_HZ / 1000U * ADC_SHOW_MS;	//Отпустили - круг дальше через 2 с
	}
	if (held >= 0) {
		disp_item = (uint32_t)held;
	} else if (now >= disp_next_item) {					//Следующее показание
		disp_next_item = now + (uint64_t)MTIME_HZ / 1000U * ADC_SHOW_MS;
		do disp_item = (disp_item + 1U) % SHOW_N; while (!disp_has(disp_item));
		disp_next = now;
	}
	if (now < disp_next) return;
	disp_next = now + (uint64_t)MTIME_HZ / 1000U * ADC_DISP_MS;
#ifdef ADC_ON
	if (disp_item == SHOW_I) adc_show(adc_by_sym('I'));
	else if (disp_item == SHOW_U) adc_show(adc_by_sym('U'));
	else
#endif
	sifu_show_alpha();
	sifu_leds();
}

/* Угол двумя левыми кнопками (больше, меньше): шаг 0.5 град. по сетке 0.5 (32.3 -> 32.5 или 32.0),
   по нажатию, при удержании - автоповтор. Возвращает 1, если угол изменился */
static int sifu_keys(void) {
	uint32_t *alpha10 = &sifu_alpha10;
	static uint32_t old = 0U;
	static uint64_t repeat = 0U;
	uint32_t keys = TM1638_ReadKeys() & (KEY_ALPHA_UP | KEY_ALPHA_DOWN);
	uint64_t now = CORE_GetCycles();
	uint32_t max10 = SIFU_AlphaMaxDeg10(), a = *alpha10;
	int step = 0;

	if (keys != old) {									//Нажатие (или смена кнопки) - сразу шаг
		old = keys;
		repeat = now + (uint64_t)MTIME_HZ / 1000U * KEY_DELAY_MS;
		step = (keys != 0U);
	} else if (keys && now >= repeat) {					//Удержание - автоповтор
		repeat = now + (uint64_t)MTIME_HZ / 1000U * KEY_REPEAT_MS;
		step = 1;
	}
	if (!step || keys == (KEY_ALPHA_UP | KEY_ALPHA_DOWN)) return 0;
	if (keys & KEY_ALPHA_UP) {
		a = (a / KEY_STEP_DEG10 + 1U) * KEY_STEP_DEG10;			//Следующее значение сетки
		if (a > max10) a = max10;
	} else if (a % KEY_STEP_DEG10) {
		a -= a % KEY_STEP_DEG10;								//Вниз до сетки
	} else {
		a = (a > KEY_STEP_DEG10) ? a - KEY_STEP_DEG10 : 0U;
	}
	if (a == *alpha10) return 0;
	*alpha10 = a;
	sifu_apply_alpha();
	return 1;
}

static void Example_Run(void) {
	char line[32];
	uint64_t next = 0;
	int stand_src = 0;									//Источник задан входами DI1/DI2
#if STAND_IO
	uint32_t di_old = 0xFFU;							//Прошлое состояние DI1, DI2 - сообщение при смене
	uint64_t di_msg = 0U;								//Когда печатать сообщение (после паузы смены источника)
#endif

	UART_InitDefault();
	TM1638_Init();
#if STAND_IO
	stand_io_init();
#endif
	SIFU_Init();
	SIFU_SimStart(SIFU_SIM_FREQ100, SIFU_SIM_DZ10);
	delay_ms(100);										//Синхронизация и полупериод HPER
	UART_PutText("\r\n== askoRV32: СИФУ, имитатор сети 50 Гц ==\r\nТик ГПН ");
	UART_PutDec((int32_t)SIFU_SawHz());
	UART_PutText(" Гц, DELAY ");
	UART_PutDec((int32_t)SIFU->DELAY);
	UART_PutText(", импульс ");
	UART_PutDec((int32_t)SIFU->WIDTH);
	UART_PutText(" тиков\r\n");
#ifdef ADC_ON
	adc_boards_start();
	for (uint32_t i = 0; i < ADC_BOARDS; i++) {
		UART_PutText(boards[i].name);
		UART_PutText(boards[i].sym == 'U' ? ": напряжение, до " : ": ток, до ");
		UART_PutDec((int32_t)ADC121_GetRate(boards[i].adc));
		UART_PutText(" отсчётов/с\r\n");
	}
#endif
	sifu_status();
	sifu_selftest();
	sifu_apply_alpha();									//30 град., импульсы выключены - 'e'
#if STAND_IO
	SIFU_SimStop();										//Стенд: источник дальше задают DI1 (сеть) и DI2 (имитатор)
	UART_PutText("Стенд: импульсы на драйверы - DI1 = 1 от сети, DI2 = 1 от имитатора (оба 0 или оба 1 - нет)\r\n");
#endif
	sifu_show();
	UART_PutText("Кнопки TM1638: 1 (крайняя левая) - угол больше, 2 - меньше (шаг 0.5 град.); индикатор по кругу,\r\n"
	             "зажать 6 - угол, 7 - ток, 8 - напряжение\r\n");
	UART_PutText("Команды: угол 0..120, e - EN, d - сдвоенные, n - входы NSB, s - имитатор, t - самопроверка, g - синхронизация"
#ifdef ADC_ON
	             ", u - АЦП"
#endif
	             "\r\n> ");
	while (1) {
#if STAND_IO
		stand_src = stand_io_copy();					//DI1..DI3 -> RO1..RO3, источник и EN по DI1, DI2
		uint32_t di = GPIO_READ(DI1) | (GPIO_READ(DI2) << 1);
		if (di != di_old) {								//Сменились DI1, DI2 - сообщение через 0.1 с
			di_old = di;
			di_msg = CORE_GetCycles() + MTIME_HZ / 10U;
		}
		if (di_msg && CORE_GetCycles() >= di_msg) {
			di_msg = 0U;
			UART_PutText(di == 1U ? "\r\nDI1: импульсы на драйверы, синхронизация от сети\r\n" :
			             di == 2U ? "\r\nDI2: импульсы на драйверы, синхронизация от имитатора сети\r\n" :
			             di == 3U ? "\r\nDI1 и DI2 вместе - импульсы сняты\r\n" :
			                        "\r\nDI1 и DI2 выключены - импульсы сняты\r\n");
			sifu_status();
			UART_PutText("> ");
		}
#endif
		sifu_hper_sample();
		if (sifu_keys()) sifu_show();					//Угол кнопками TM1638 - на индикатор сразу
		disp_update();									//Индикатор: угол, ток, напряжение по кругу
#ifdef ADC_ON
		adc_poll();
#endif
		if (CORE_GetCycles() >= next) {					//Раз в секунду: угол по среднему полупериоду
			next = CORE_GetCycles() + MTIME_HZ;
			sifu_hper_update();
#ifdef ADC_ON
			adc_rate_update(1U);
#endif
			LED_Toggle();
		}
		if (!(UART->IP & UART_IT_RXWM)) continue;
		if (UART_GetErrors()) UART_ClearErrors(UART_GetErrors());
		if (UART_ReadLine(line, sizeof line, 1) == 0) { sifu_status(); UART_PutText("> "); continue; }
		int32_t d10 = parse_deg10(line);
		if (d10 >= 0) {
			sifu_alpha10 = (uint32_t)d10;
			sifu_apply_alpha();
			sifu_show();
		} else if (line[0] == 'e' && line[1] == '\0') {
#if STAND_IO
			UART_PutText("Импульсы на стенде включают входы: DI1 - от сети, DI2 - от имитатора\r\n");
#else
			SIFU->CR ^= SIFU_CR_EN;
#endif
		} else if (line[0] == 'd' && line[1] == '\0') {
			SIFU->CR ^= SIFU_CR_DBL;
		} else if ((line[0] == 'n' || line[0] == 's') && line[1] == '\0' && stand_src) {
			UART_PutText("Источник синхронизации задают входы DI1 (сеть) и DI2 (имитатор)\r\n");
		} else if (line[0] == 'n' && line[1] == '\0') {
			SIFU_SimStop();
		} else if (line[0] == 's' && line[1] == '\0') {
#if STAND_IO
			SIFU_Disable();								//Стенд: без DI2 импульсы имитатора на драйверы не выдаются
#endif
			SIFU_SimStart(SIFU_SIM_FREQ100, SIFU_SIM_DZ10);
		} else if (line[0] == 't' && line[1] == '\0') {
			sifu_selftest();
		} else if (line[0] == 'g' && line[1] == '\0') {
			sifu_sync_trace();
#ifdef ADC_ON
		} else if (line[0] == 'u' && line[1] == '\0') {
			for (uint32_t i = 0; i < ADC_BOARDS; i++) adc_status(&boards[i]);
#endif
		} else {
			UART_PutText("Не понял: угол 0..120, e, d, n, s, t, g, u\r\n");
		}
		sifu_status();
		UART_PutText("> ");
	}
}
#endif

#if EXAMPLE == 9
#if !defined(ADC_V) && !defined(ADC_C)
#error "Пример 9: в конфигурации ПЛИС нет блоков ADC121 (платы ADC_V, ADC_C - Tang Primer 20K)"
#endif
/*
 * Пример 9: аналоговые измерения - АЦП ADC121S051 на платах ADC_V (напряжение, блок ADC_V) и ADC_C
 * (ток, блок ADC_C; какие есть - из конфигуратора, soc.h). Непрерывные преобразования (на своём такте
 * блока 96 МГц - 468 тыс. отсчётов в секунду), блок сам усредняет 2^AVGSH отсчётов. Раз в 0.5 с в UART
 * по каждой плате:
 * средний код (с дробью - по сумме SUM), последний отсчёт, сырой кадр, величина
 * ((код - OFFSET) * SCALE_U - коэффициенты из конфигуратора), частота отсчётов, ошибки кадра;
 * у ADC_C - вход компаратора защиты (CMP) и число срабатываний. На TM1638 - напряжение «U 59.99» и ток
 * «I 0.999», обновление 2 раза в секунду; при двух платах - по очереди через 2 с, а пока зажата кнопка 7
 * (вторая справа) - только ток, кнопка 8 (крайняя правая) - только напряжение.
 * Команды с терминала (115200 8-N-1, cp1251):
 *   v, c - выбрать плату ADC_V или ADC_C для команд ниже;
 *   w - запись 250 отсчётов с частотой 12.5 кГц (5 периодов 50 Гц) и вывод их кодов;
 *   r N - частота отсчётов N Гц (0 - максимальная); a N - усреднение по 2^N отсчётам (0..12);
 *   b - возможности тракта: для разных делителей SCLK и пауз кадра - частота отсчётов, доля кадров
 *       с ошибкой, разброс 1000 отсчётов (мин., макс., среднее, СКО) - SCLK за пределами листа данных
 *       АЦП тоже, чтобы увидеть запас;
 *   p - приём программой: при каких частотах опрос флага DRDY успевает забрать каждый отсчёт.
 * ADC_V: ниже ~40 В плата нелинейна (выход ОУ не доходит до 0). ADC_C: ток в обе стороны, ноль -
 * код около 2048 (опора 1.65 В), компаратор U2 срабатывает только на положительный ток.
 */
#define ADC_PRINT_MS		500U
#define ADC_CAPTURE_N		250U
#define ADC_CAPTURE_HZ		12500U
#define ADC_BENCH_N			1000U

static AdcBoard *sel = &boards[0];		//Плата для команд w, r, a, b, p

static uint16_t adc_big[ADC_BENCH_N];

/* Разбор «r 25000» / «a 8»: число после буквы; -1 - нет числа */
static int32_t cmd_num(const char *s) {
	int32_t v = 0, digits = 0;
	s++;
	while (*s == ' ') s++;
	while (*s >= '0' && *s <= '9') { v = v * 10 + (*s++ - '0'); digits++; }
	return digits ? v : -1;
}

/* Разброс отсчётов: мин., макс., среднее и СКО в тысячных долях кода */
static uint32_t isqrt64(uint64_t v) {
	uint64_t r = 0, b = (uint64_t)1 << 62;
	while (b > v) b >>= 2;
	while (b) {
		if (v >= r + b) { v -= r + b; r = (r >> 1) + b; } else r >>= 1;
		b >>= 2;
	}
	return (uint32_t)r;
}
static void adc_stats(const uint16_t *b, uint32_t n, uint32_t *mn, uint32_t *mx, uint32_t *mean1000, uint32_t *sd1000) {
	uint64_t s = 0, s2 = 0;
	*mn = 4095U; *mx = 0U;
	for (uint32_t i = 0; i < n; i++) {
		s += b[i]; s2 += (uint64_t)b[i] * b[i];
		if (b[i] < *mn) *mn = b[i];
		if (b[i] > *mx) *mx = b[i];
	}
	/* Дисперсия в миллионных долях кода^2: (n*s2 - s^2) * 1e6 / n^2 */
	uint64_t var = ((uint64_t)n * s2 - s * s) * 1000000ULL / ((uint64_t)n * n);
	*mean1000 = (uint32_t)(s * 1000U / n);
	*sd1000 = isqrt64(var);
}

/* w: запись 250 отсчётов при 12.5 кГц */
static void adc_capture(ADC121_TypeDef *adc) {
	uint32_t keep = adc->PER;
	ADC121_SetRate(adc, ADC_CAPTURE_HZ);
	uint32_t n = ADC121_Capture(adc, adc_big, ADC_CAPTURE_N);
	adc->PER = keep;
	UART_PutText("Запись: ");
	UART_PutDec((int32_t)n);
	UART_PutText(" отсчётов, ");
	UART_PutDec((int32_t)ADC_CAPTURE_HZ);
	UART_PutText(" Гц, коды:\r\n");
	for (uint32_t i = 0; i < n; i++) {
		UART_PutDec(adc_big[i]);
		UART_PutText((i % 16U == 15U) ? "\r\n" : " ");
	}
	UART_PutText("\r\n");
}

/* b: делитель SCLK, CSS, QUIET -> частота отсчётов, ошибки кадра, разброс отсчётов. Такт блока f -
   регистр FCLK (свой rPLL 96 МГц: DIV 5 - SCLK 8 МГц, предел листа данных АЦП; DIV 4..2 - за пределом) */
static void adc_bench(ADC121_TypeDef *adc) {
	static const uint8_t cfg[][3] = {	//DIV, CSS, QUIET
		{7, 2, 2}, {6, 2, 2}, {5, 2, 2}, {5, 1, 1}, {4, 2, 2}, {4, 1, 1}, {3, 1, 1}, {2, 1, 1}, {1, 1, 1}};
	uint32_t f = ADC121_GetClock(adc);
	uint32_t keep_div = adc->DIV, keep_per = adc->PER, keep_avg = adc->AVG;
	UART_PutText("DIV CSS QUIET  SCLK,кГц  теор.отсч/с  факт.отсч/с  ошибок,%  мин  макс  среднее  СКО (по 1000 отсчётам)\r\n");
	for (uint32_t c = 0; c < sizeof cfg / sizeof cfg[0]; c++) {
		uint32_t div = cfg[c][0], css = cfg[c][1], quiet = cfg[c][2];
		ADC121_Stop(adc);
		while (adc->SR & ADC121_SR_BUSY) ;
		adc->DIV = (css << ADC121_DIV_CSS_POS) | (quiet << ADC121_DIV_QUIET_POS) | div;
		adc->PER = 0U;
		adc->AVG = 0U;
		/* Кадр, тактов блока: CSS + 32 + QUIET полупериодов (16 подъёмов и 15 спадов SCLK, удержание CS) и такт запуска */
		uint32_t frame = (css + 32U + quiet) * (div + 1U) + 1U;
		uint32_t theo = f / frame;
		ADC121_ClearFlags(adc, ADC121_SR_FLAGS);
		uint32_t c0 = ADC121_GetCount(adc);
		uint64_t t0 = CORE_GetCycles();
		ADC121_Start(adc);
		while (CORE_GetCycles() - t0 < SYSCLK_HZ / 10U) ;			//100 мс
		uint32_t got = ADC121_GetCount(adc) - c0;
		uint32_t dt = (uint32_t)(CORE_GetCycles() - t0);
		uint32_t fact = (uint32_t)((uint64_t)got * SYSCLK_HZ / dt);
		uint32_t frames = (uint32_t)((uint64_t)dt * (f / 1000U) / (SYSCLK_HZ / 1000U) / frame);	//Кадров за время (с ошибкой тоже)
		uint32_t err100 = (frames > got) ? (uint32_t)((uint64_t)(frames - got) * 100000U / frames) : 0U;
		/* Разброс: каждый отсчёт по DRDY (при больших частотах программа пропускает часть - не важно) */
		ADC121_Capture(adc, adc_big, ADC_BENCH_N);
		uint32_t mn, mx, mean, sd;
		adc_stats(adc_big, ADC_BENCH_N, &mn, &mx, &mean, &sd);
		UART_PutDec((int32_t)div); UART_PutText("    "); UART_PutDec((int32_t)css); UART_PutText("    ");
		UART_PutDec((int32_t)quiet); UART_PutText("     ");
		UART_PutDec((int32_t)(f / (2U * (div + 1U)) / 1000U)); UART_PutText("\t   ");
		UART_PutDec((int32_t)theo); UART_PutText("\t   ");
		UART_PutDec((int32_t)fact); UART_PutText("\t");
		put_k(err100); UART_PutText("\t");
		UART_PutDec((int32_t)mn); UART_PutText("  "); UART_PutDec((int32_t)mx); UART_PutText("  ");
		put_k(mean); UART_PutText("  "); put_k(sd);
		UART_PutText("\r\n");
	}
	ADC121_Stop(adc);
	while (adc->SR & ADC121_SR_BUSY) ;
	adc->DIV = keep_div; adc->PER = keep_per; adc->AVG = keep_avg;
	ADC121_ClearFlags(adc, ADC121_SR_DRDY | ADC121_SR_ARDY | ADC121_SR_ERR);
	ADC121_Start(adc);
}

/* p: приём программой опросом DRDY - сколько отсчётов пропущено при разных частотах */
static void adc_cpu_bench(ADC121_TypeDef *adc) {
	static const uint32_t rates[] = {10000U, 20000U, 50000U, 100000U, 150000U, 200000U, 250000U, 0U};
	uint32_t keep_per = adc->PER;
	UART_PutText("Частота, отсч/с  принято  пропущено  время, мкс  тактов на отсчёт\r\n");
	for (uint32_t r = 0; r < sizeof rates / sizeof rates[0]; r++) {
		ADC121_SetRate(adc, rates[r]);
		uint32_t c0 = ADC121_GetCount(adc);
		uint64_t t0 = CORE_GetCycles();
		uint32_t n = ADC121_Capture(adc, adc_big, ADC_BENCH_N);
		uint32_t dt = (uint32_t)(CORE_GetCycles() - t0);
		uint32_t made = ADC121_GetCount(adc) - c0;				//Сделал АЦП за время записи
		UART_PutDec((int32_t)(rates[r] ? rates[r] : ADC121_GetRate(adc)));
		UART_PutText(rates[r] ? "\t\t" : " (макс.)\t");
		UART_PutDec((int32_t)n); UART_PutText("\t ");
		UART_PutDec((int32_t)(made > n ? made - n : 0U)); UART_PutText("\t    ");
		UART_PutDec((int32_t)(dt / (SYSCLK_HZ / 1000000U))); UART_PutText("\t");
		UART_PutDec((int32_t)(n ? dt / n : 0U));
		UART_PutText("\r\n");
	}
	adc->PER = keep_per;
}

static void Example_Run(void) {
	char line[32];
	uint64_t next = 0, next_show = 0, next_disp = 0;
	uint32_t show = 0, keys_old = 0;
	AdcBoard *shown = &boards[0];

	UART_InitDefault();
	TM1638_Init();
	UART_PutText("\r\n== askoRV32: АЦП ADC121S051 ==\r\n");
	adc_boards_start();
	for (uint32_t i = 0; i < ADC_BOARDS; i++) {
		AdcBoard *b = &boards[i];
		UART_PutText(b->name);
		UART_PutText(": до ");
		UART_PutDec((int32_t)ADC121_GetRate(b->adc));
		UART_PutText(" отсчётов/с; пересчёт: (код - ");
		put_k((uint32_t)b->cal.offset_m);
		UART_PutText(") * ");
		UART_PutDec(b->cal.scale_u);
		UART_PutText(b->sym == 'U' ? " мкВ" : " мкА");
		if (b->has_cmp) UART_PutText("; вход компаратора CMP");
		UART_PutText("\r\n");
	}
	UART_PutText("Команды: v, c - плата; w - запись 250 отсчётов, r N - частота N Гц (0 - макс.), a N - среднее по 2^N, b - тракт, p - приём программой\r\n");
	UART_PutText("TM1638: зажать кнопку 7 - только ток, кнопку 8 - только напряжение\r\n");
	while (1) {
		adc_poll();												//Ошибки кадра и срабатывания компаратора
		uint64_t now = CORE_GetCycles();
		if (now >= next) {										//Раз в 0.5 с - результат
			next = now + (uint64_t)MTIME_HZ / 1000U * ADC_PRINT_MS;
			adc_rate_update(1000U / ADC_PRINT_MS);
			for (uint32_t i = 0; i < ADC_BOARDS; i++) adc_status(&boards[i]);
			LED_Toggle();
		}
		/* Индикатор: зажата кнопка 7 - ток, 8 - напряжение, иначе платы по очереди через 2 с */
		uint32_t keys = TM1638_ReadKeys() & (KEY_SHOW_I | KEY_SHOW_U);
		AdcBoard *held = (keys == KEY_SHOW_I) ? adc_by_sym('I') : (keys == KEY_SHOW_U) ? adc_by_sym('U') : 0;
		if (keys != keys_old) {
			keys_old = keys;
			next_disp = now;									//Сразу показать
			if (held) {
				shown = held;
				UART_PutText(held->sym == 'I' ? "Индикатор: ток (кнопка 7)\r\n" : "Индикатор: напряжение (кнопка 8)\r\n");
			} else {
				next_show = now;								//Отпустили - снова по очереди
			}
		}
		if (!held && now >= next_show) {
			next_show = now + (uint64_t)MTIME_HZ / 1000U * ADC_SHOW_MS;
			shown = &boards[show];
			if (++show >= ADC_BOARDS) show = 0;
			next_disp = now;
		}
		if (now >= next_disp) {									//2 раза в секунду
			next_disp = now + (uint64_t)MTIME_HZ / 1000U * ADC_DISP_MS;
			adc_show(shown);
		}
		if (!(UART->IP & UART_IT_RXWM)) continue;
		if (UART_GetErrors()) UART_ClearErrors(UART_GetErrors());
		if (UART_ReadLine(line, sizeof line, 1) == 0) continue;
		int32_t v = cmd_num(line);
		if ((line[0] == 'v' || line[0] == 'c') && line[1] == '\0') {
			for (uint32_t i = 0; i < ADC_BOARDS; i++)
				if (boards[i].name[4] == (line[0] == 'v' ? 'V' : 'C')) sel = &boards[i];
			UART_PutText("Плата для команд: ");
			UART_PutText(sel->name);
			UART_PutText("\r\n");
		} else if (line[0] == 'w') {
			adc_capture(sel->adc);
		} else if (line[0] == 'b' && line[1] == '\0') {
			adc_bench(sel->adc);
		} else if (line[0] == 'p' && line[1] == '\0') {
			adc_cpu_bench(sel->adc);
		} else if (line[0] == 'r' && v >= 0) {
			ADC121_SetRate(sel->adc, (uint32_t)v);
		} else if (line[0] == 'a' && v >= 0 && v <= 12) {
			ADC121_SetAverage(sel->adc, (uint32_t)v);
		} else {
			UART_PutText("Команды: v, c, w, r N, a N, b, p\r\n");
		}
	}
}
#endif

int main(void) {
#if EXAMPLE == 0
	//#1 Инициализация периферийных устройств
	GPIO_Init();
	TM1638_Init();
	STIM_Init();
	GPIO_PinsMode(0xFFFFFFFF); //Все порты на выход

	STIM_InitPeriodic(45000U - 1U, 60000U - 1U);	//Тик 1 мс, событие
	STIM_STATE(TIM_ENABLE);

	unsigned int count = 0;
	unsigned int keys = 0;

	while(1) {
		//#Считывание значения таймера
		count = STIM_GET_COUNT()/1000;
		GPIO_WritePins(count);

		//#Светодиоды и кнопки tm1638
		keys = TM1638_ReadKeys();
		TM1638_WriteLeds(keys);

		//#Семисегментный индикатор tm1638
		TM1638_WriteSegs(dig_transform(count));
	}
#elif EXAMPLE <= 2
	GPIO_Init();
#ifdef LED0_PIN
	GPIO_PinMode(LED0_PIN, GPIO_MODE_OUTPUT);
#endif
	Example_Init();

	while(1) {
#if EXAMPLE == 1
		//#Семисегментный индикатор tm1638: счётчик прерываний STIM
		TM1638_WriteSegs(dig_transform(global_count));
#endif
		//Вся работа - в обработчике прерывания; здесь может выполняться основная программа
	}
#else
	GPIO_Init();
#ifdef LED0_PIN
	GPIO_PinMode(LED0_PIN, GPIO_MODE_OUTPUT);
#endif
	Example_Run();
#endif
}

unsigned int dig_transform(unsigned int digit) {
	unsigned int d_out = 0;
	unsigned int d_in  = digit;
	d_in = d_in % 100000000;
	d_out = d_out | ((d_in / 10000000) << 28);
	d_in = d_in % 10000000;
	d_out = d_out | ((d_in / 1000000)  << 24);
	d_in = d_in % 1000000;
	d_out = d_out | ((d_in / 100000)   << 20);
	d_in = d_in % 100000;
	d_out = d_out | ((d_in / 10000)    << 16);
	d_in = d_in % 10000;
	d_out = d_out | ((d_in / 1000)     << 12);
	d_in = d_in % 1000;
	d_out = d_out | ((d_in / 100)      <<  8);
	d_in = d_in % 100;
	d_out = d_out | ((d_in / 10)       <<  4);
	d_out = d_out |  (d_in % 10);
	return d_out;
}
