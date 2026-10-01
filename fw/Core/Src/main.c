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
 *                6 - TM1638: бегущая строка на кириллице, номер нажатой кнопки.
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

#ifndef EXAMPLE
#define EXAMPLE 1
#endif

/* Полупериод мигания, мс */
#define BLINK_HALF_PERIOD_MS 	500U

/*Прототипы функций*/
unsigned int dig_transform(unsigned int digit);

#if EXAMPLE != 0
volatile unsigned int blink_count = 0;	//Число переключений светодиода

__attribute__((unused)) static void LED_Toggle(void) {
	GPIO->OUT ^= (1U << GPIO_LED0);
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
	GPIO_PinMode(GPIO_LED0, GPIO_MODE_OUTPUT);
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
	GPIO_PinMode(GPIO_LED0, GPIO_MODE_OUTPUT);
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
