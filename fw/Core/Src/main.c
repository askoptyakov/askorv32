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
 *                8 - СИФУ тиристорного выпрямителя (блок SIFU) с имитатором сети: самопроверка, угол с терминала.
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

#ifndef EXAMPLE
#define EXAMPLE 3
#endif

/* Полупериод мигания, мс */
#define BLINK_HALF_PERIOD_MS 	500U

/*Прототипы функций*/
unsigned int dig_transform(unsigned int digit);

#if EXAMPLE != 0
volatile unsigned int blink_count = 0;	//Число переключений светодиода

__attribute__((unused)) static void LED_Toggle(void) {
	GPIO->OUT ^= (1U << LED0_PIN);
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

#if EXAMPLE == 8
/*
 * Пример 8: СИФУ трёхфазного мостового тиристорного выпрямителя (блок SIFU) без силовой части:
 * сигналы шести оптронов платы NSB даёт имитатор сети в самом блоке (50 Гц, мёртвая зона 2 град.).
 * Имитатор выдаёт сигналы так же, как NSB, поэтому DELAY (компенсация RC-фильтра NSB) остаётся
 * значением из конфигуратора: при ALPHA = 0 импульс - через DELAY тиков от начала окна оптрона.
 *
 * При старте - самопроверка: для углов 0, 30, 60, 90, 120 эл. град. программа по счётчику тактов
 * (mcycle) измеряет у каждого тиристора VS1..VS6 задержку фронта импульса от начала его полуволны и
 * длительность импульса (в тиках ГПН) и сравнивает с ожидаемыми: ALPHA + DELAY и WIDTH (начало
 * полуволны модуль видит после фильтра входов, импульс отсчитывается от того же момента). Затем -
 * команды с терминала (115200 8-N-1, cp1251):
 *   число 0..127 (можно с десятыми: 32.5) - угол управления, эл. град.;
 *   e - импульсы вкл./выкл. (EN); d - сдвоенные импульсы вкл./выкл.;
 *   n - входы платы NSB (настоящая сеть); s - снова имитатор; t - повторить самопроверку.
 * Раз в секунду - частота сети, полупериод, угол и состояние. TM1638: угол; светодиоды: 1 - сеть есть,
 * 2 - нет синхронизации, 3 - EN, 4 - имитатор. Импульсы VS1..VS6 - на выводах ПЛИС (Tang Nano 9K:
 * 28..33, Tang Primer 20K: разъём PMOD J5) - их можно смотреть осциллографом.
 */
#define SIFU_SIM_FREQ100	5000U		//Частота имитатора: 50.00 Гц
#define SIFU_SIM_DZ10		20U			//Мёртвая зона имитатора: 2.0 град.

/* Измерение тиристора k (1..6): начало его полуволны (SR.SYNCF с CH = k) -> фронт и спад выхода VSk.
   Результат - в тиках ГПН; 0 - не дождались (100 мс) */
static int sifu_measure(uint32_t k, uint32_t *lag, uint32_t *width) {
	uint32_t div1 = SIFU->DIV + 1U, bit = 1U << (k - 1U);
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

	SIFU->CR = keep_cr & ~SIFU_CR_DBL;					//Без сдваивания: у каждого выхода один импульс
	SIFU_Enable();
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

static void sifu_status(void) {
	uint32_t sr = SIFU->SR, f = SIFU_GridFreq100();
	UART_PutText("f = ");
	if (f) { UART_PutDec((int32_t)(f / 100U)); UART_PutChar('.'); UART_PutDec((int32_t)(f % 100U / 10U)); UART_PutDec((int32_t)(f % 10U)); UART_PutText(" Гц"); }
	else UART_PutText("нет");
	UART_PutText(", HPER ");
	UART_PutDec((int32_t)SIFU->HPER);
	UART_PutText(", угол ");
	put_deg10(SIFU_GetAlphaDeg10());
	UART_PutText(" (ALPHA ");
	UART_PutDec((int32_t)SIFU->ALPHA);
	UART_PutText(", макс. ");
	put_deg10(SIFU_TicksToDeg10(SIFU_AlphaMax()));
	UART_PutText("), EN ");
	UART_PutDec((SIFU->CR & SIFU_CR_EN) ? 1 : 0);
	UART_PutText(", DBL ");
	UART_PutDec((SIFU->CR & SIFU_CR_DBL) ? 1 : 0);
	UART_PutText((SIFU->CR & SIFU_CR_SIM) ? ", имитатор" : ", входы NSB");
	UART_PutText(", SR 0x");
	UART_PutHex(sr, 5);
	UART_PutText((sr & SIFU_SR_GRID) ? " сеть есть" : " сети нет");
	if (sr & SIFU_SR_LOST) UART_PutText(", нет синхронизации");
	UART_PutText("\r\n");
}

static void sifu_show(void) {
	char t[12];
	uint32_t d10 = SIFU_GetAlphaDeg10(), sr = SIFU->SR, cr = SIFU->CR;
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
	TM1638_WriteLeds(((sr & SIFU_SR_GRID) ? 1U : 0U) | ((sr & SIFU_SR_LOST) ? 2U : 0U) |
	                 ((cr & SIFU_CR_EN) ? 4U : 0U) | ((cr & SIFU_CR_SIM) ? 8U : 0U));
}

static void Example_Run(void) {
	char line[32];
	uint64_t next = 0;

	UART_InitDefault();
	TM1638_Init();
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
	sifu_status();
	sifu_selftest();
	SIFU_SetAlphaDeg10(300U);							//30 град., импульсы выключены - 'e'
	UART_PutText("Команды: угол 0..127, e - EN, d - сдвоенные, n - входы NSB, s - имитатор, t - самопроверка\r\n> ");
	while (1) {
		if (CORE_GetCycles() >= next) {					//Раз в секунду - состояние
			next = CORE_GetCycles() + MTIME_HZ;
			sifu_show();
			LED_Toggle();
		}
		if (!(UART->IP & UART_IT_RXWM)) continue;
		if (UART_GetErrors()) UART_ClearErrors(UART_GetErrors());
		if (UART_ReadLine(line, sizeof line, 1) == 0) { sifu_status(); UART_PutText("> "); continue; }
		int32_t d10 = parse_deg10(line);
		if (d10 >= 0) {
			SIFU_SetAlphaDeg10((uint32_t)d10);
		} else if (line[0] == 'e' && line[1] == '\0') {
			SIFU->CR ^= SIFU_CR_EN;
		} else if (line[0] == 'd' && line[1] == '\0') {
			SIFU->CR ^= SIFU_CR_DBL;
		} else if (line[0] == 'n' && line[1] == '\0') {
			SIFU_SimStop();
		} else if (line[0] == 's' && line[1] == '\0') {
			SIFU_SimStart(SIFU_SIM_FREQ100, SIFU_SIM_DZ10);
		} else if (line[0] == 't' && line[1] == '\0') {
			sifu_selftest();
		} else {
			UART_PutText("Не понял: угол 0..127, e, d, n, s, t\r\n");
		}
		sifu_status();
		UART_PutText("> ");
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
	GPIO_PinMode(LED0_PIN, GPIO_MODE_OUTPUT);
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
	GPIO_PinMode(LED0_PIN, GPIO_MODE_OUTPUT);
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
