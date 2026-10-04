/*
 ******************************************************************************
 * @file        main.c
 * @author		Alexander Koptyakov
 * @device		AskoRV32
 * @brief       Управляемый выпрямитель: стабилизация напряжения с ограничением тока (CV/CC),
 *              РЕГУЛЯТОР - В ПЛИС (ветка hw_rect). Блоки ПЛИС: RECT - выпрямитель (СИФУ и регулятор
 *              CC/CV: PI_U - напряжение, PI_I - ток) и ADC (каналы V - плата напряжения ADC_V,
 *              C - плата тока ADC_C). Связь RECT - ADC задана в конфигураторе: выпрямитель закрывает
 *              окна усреднения АЦП в начале каждой полуволны и берёт средние напряжения и тока как
 *              обратные связи; выход PI_U - угол СИФУ. Программа пишет только задание (напряжение,
 *              ограничение тока - в кодах АЦП по калибровке каналов), коэффициенты, предел угла и
 *              режим, и показывает результат. Описание - hw/info/rectifier.md.
 *
 *              Режимы (стенд Tang Nano 9K - дискретные входы; без них - команда терминала m):
 *                DI1 - синхронизация от имитатора сети, угол вручную;
 *                DI2 - синхронизация от сети, угол вручную;
 *                DI3 - синхронизация от сети, регулирование напряжения с ограничением тока.
 *              Ни один DI не включён или включено несколько - импульсов нет. Состояние входов
 *              принимается, если держится 50 мс. При смене режима импульсы снимаются на 40 мс,
 *              регулятор начинает с нуля (угол 120 град.). DI1..DI3 повторяются на RO1..RO3.
 *
 *              Кнопки TM1638 (1 - крайняя левая): 1, 2 - больше / меньше (выбранный параметр;
 *              без выбора - угол в ручных режимах или задание напряжения в DI3); 3 - коэффициенты
 *              регуляторов по кругу («ПU», «ИU», «ПI», «ИI», K * 4096 / 4096); 4 - ограничение тока
 *              («ЗI»); 5 - задание напряжения («ЗU»); 6 - угол; 7 - напряжение («U»), 8 - ток («I»)
 *              обратной связи. Выбранный параметр мигает - его можно менять; через 5 с без нажатий -
 *              ток и напряжение по очереди через 2 с. Ток и напряжение - среднее окон за 0.5 с.
 *              Светодиоды: 1 - сеть, 2 - нет синхронизации, 3 - импульсы (EN), 4 - имитатор,
 *              5 - ограничение тока, 6 - регулирование.
 *              Терминал (115200 8-N-1, cp1251; Enter - состояние): u <В>, i <А>, a <град.>,
 *              ku <KP> <KI>, ki <KP> <KI> (K * 4096), d - платы АЦП подробно, m <0..3> - режим (без DI).
 *****************************************************************************************
 */

#include "main.h"
#include "core_riscv.h"
#include "clint.h"
#include "gpio.h"
#include "tm1638.h"
#include "uart.h"
#include "sifu.h"
#include "adc121.h"
#include "pireg.h"
#include "rect.h"

#if !defined(RECT) || !defined(ADC_V) || !defined(ADC_C)
#error "Выпрямитель: в конфигурации ПЛИС нужны блоки RECT и ADC с каналами V (напряжение) и C (ток)"
#endif
#if !RECT_LINKED
#error "Выпрямитель: у блока RECT не задана связь с блоком АЦП (настройки «АЦП», «Канал U», «Канал I»)"
#endif
#if !ADC_WIN
#error "Выпрямитель: у блока ADC нужно среднее за окно (настройка «Среднее за окно»)"
#endif
#if defined(DI1_PIN) && defined(DI2_PIN) && defined(DI3_PIN) && defined(RO1_PIN) && defined(RO2_PIN) && defined(RO3_PIN)
#define STAND_IO			1			//Стенд: режим по дискретным входам
#else
#define STAND_IO			0			//Без входов: режим - командой m
#endif

/* ---------------------------------------------------------------------------------------------
 * Общее: время, текст
 * --------------------------------------------------------------------------------------------- */
static uint64_t ms_ticks(uint32_t ms) { return (uint64_t)MTIME_HZ / 1000U * ms; }

static void delay_ms(uint32_t ms) {
	uint64_t end = CORE_GetCycles() + ms_ticks(ms);
	while (CORE_GetCycles() < end) ;
}

/* Тысячные доли - текстом «-12.345» (digits знаков после точки: 1..3) */
static int fmt_milli(char *s, int32_t v, int digits) {
	int n = 0;
	uint32_t u, div = 1000U;
	if (v < 0) { s[n++] = '-'; u = (uint32_t)(-v); } else u = (uint32_t)v;
	for (int i = digits; i < 3; i++) { u = (u + 5U) / 10U; div /= 10U; }
	uint32_t ip = u / div, fp = u % div;
	char d[10];
	int m = 0;
	do { d[m++] = (char)('0' + ip % 10U); ip /= 10U; } while (ip);
	while (m) s[n++] = d[--m];
	s[n++] = '.';
	for (uint32_t k = div / 10U; k; k /= 10U) s[n++] = (char)('0' + fp / k % 10U);
	s[n] = '\0';
	return n;
}

/* Коэффициент (K * 4096) - «0.0125» */
static void fmt_q12(char *s, uint32_t k) {
	uint32_t v = (k * 10000U + 2048U) / 4096U, ip = v / 10000U;
	char d[8];
	int n = 0, m = 0;
	do { d[m++] = (char)('0' + ip % 10U); ip /= 10U; } while (ip);
	while (m) s[n++] = d[--m];
	s[n++] = '.';
	for (uint32_t k10 = 1000U; k10; k10 /= 10U) s[n++] = (char)('0' + v / k10 % 10U);
	s[n] = '\0';
}

static void put_milli(int32_t milli, int digits) {
	char s[16];
	fmt_milli(s, milli, digits);
	UART_PutText(s);
}

/* «50.5» -> 50500 (тысячные доли); -1 - не число */
static int32_t parse_milli(const char *s) {
	int32_t v = 0, f = 0, k = 100, digits = 0;
	while (*s == ' ') s++;
	while (*s >= '0' && *s <= '9') { v = v * 10 + (*s++ - '0'); digits++; }
	if (*s == '.' || *s == ',') {
		s++;
		while (*s >= '0' && *s <= '9') { if (k) { f += (*s - '0') * k; k /= 10; } s++; }
	}
	while (*s == ' ') s++;
	return (digits && *s == '\0') ? v * 1000 + f : -1;
}

/* «82 51» -> два числа 0..65535; 0 - нет */
static int parse_two(const char *s, uint32_t *a, uint32_t *b) {
	uint32_t x = 0, y = 0, dx = 0, dy = 0;
	while (*s == ' ') s++;
	while (*s >= '0' && *s <= '9') { x = x * 10U + (uint32_t)(*s++ - '0'); dx++; }
	while (*s == ' ') s++;
	while (*s >= '0' && *s <= '9') { y = y * 10U + (uint32_t)(*s++ - '0'); dy++; }
	if (!dx || !dy || x > 0xFFFFU || y > 0xFFFFU) return 0;
	*a = x; *b = y;
	return 1;
}

/* ---------------------------------------------------------------------------------------------
 * Платы измерения: каналы блока ADC
 * --------------------------------------------------------------------------------------------- */
#define ADC_PAUSE_MS		20U			//Пауза с поднятым CS перед пуском
#define ADC_CHECK_MS		100U		//Нет годных отсчётов столько при ошибках кадра - перезапуск

typedef struct
{
	ADC121_TypeDef *adc;
	ADC121_Cal      cal;
	const char     *name;
	uint32_t        errs, cnt_chk, restarts;
	uint64_t        t_chk, t_start;
} AdcBoard;

static AdcBoard brd_u = { ADC_V, { ADC_V_SCALE_U, ADC_V_OFFSET_M }, "ADC_V", 0, 0, 0, 0, 0 };
static AdcBoard brd_i = { ADC_C, { ADC_C_SCALE_U, ADC_C_OFFSET_M }, "ADC_C", 0, 0, 0, 0, 0 };
static AdcBoard *const brds[] = { &brd_u, &brd_i };
#define NBRD	(sizeof brds / sizeof brds[0])

/* Пуск: значения конфигуратора, пауза ADC_PAUSE_MS с поднятым CS (плата ADC_V на стенде после загрузки
   ПЛИС иначе иногда отвечает одними единицами), непрерывные преобразования */
static void adc_start(void) {
	for (uint32_t i = 0; i < NBRD; i++)
		ADC121_Init(brds[i]->adc, brds[i]->adc->DIV & ADC121_DIV_MSK, brds[i]->adc->AVG & 0xFU);
	delay_ms(ADC_PAUSE_MS);
	for (uint32_t i = 0; i < NBRD; i++) {
		AdcBoard *b = brds[i];
		ADC121_Start(b->adc);
		b->cnt_chk = ADC121_GetCount(b->adc);
		b->t_chk = CORE_GetCycles();
	}
}

/* Ошибки кадра и перезапуск платы, у которой ADC_CHECK_MS нет ни одного годного отсчёта (без ожидания) */
static void adc_poll(void) {
	uint64_t now = CORE_GetCycles();
	for (uint32_t i = 0; i < NBRD; i++) {
		AdcBoard *b = brds[i];
		uint32_t f = ADC121_GetFlags(b->adc) & (ADC121_SR_ERR | ADC121_SR_CMPF);
		if (f) { ADC121_ClearFlags(b->adc, f); if (f & ADC121_SR_ERR) b->errs++; }
		if (b->t_start) {
			if (now >= b->t_start) {
				b->t_start = 0U;
				ADC121_Start(b->adc);
				b->cnt_chk = ADC121_GetCount(b->adc);
				b->t_chk = now;
			}
			continue;
		}
		if (now - b->t_chk < ms_ticks(ADC_CHECK_MS)) continue;
		uint32_t c = ADC121_GetCount(b->adc);
		if (c == b->cnt_chk && (f & ADC121_SR_ERR) && (b->adc->CR & ADC121_CR_EN)) {
			ADC121_Stop(b->adc);
			b->t_start = now + ms_ticks(ADC_PAUSE_MS);
			if (b->restarts++ == 0U) {
				UART_PutText("\r\n"); UART_PutText(b->name);
				UART_PutText(": нет годных отсчётов (ошибка кадра) - перезапуск преобразований\r\n");
			}
		}
		b->cnt_chk = c;
		b->t_chk = now;
	}
}

/* d: плата подробно */
static void adc_detail(AdcBoard *b) {
	UART_PutText(b->name);
	UART_PutText(": кадр 0x");
	UART_PutHex(ADC121_GetFrame(b->adc), 4);
	UART_PutText(", среднее за окно ");
	put_milli((int32_t)(ADC121_GetWMean(b->adc) * 1000U / 16U), 2);
	UART_PutText(" кода (");
	UART_PutDec((int32_t)ADC121_GetWCount(b->adc));
	UART_PutText(" отсч.), отсчётов ");
	UART_PutDec((int32_t)ADC121_GetCount(b->adc));
	UART_PutText(", ошибок кадра ");
	UART_PutDec((int32_t)b->errs);
	UART_PutText(", перезапусков ");
	UART_PutDec((int32_t)b->restarts);
	UART_PutText(ADC121_CmpActive(b->adc) ? ", CMP: СРАБОТАЛ\r\n" : ", CMP: норма\r\n");
}

/* ---------------------------------------------------------------------------------------------
 * Регулятор CV/CC в ПЛИС (блок RECT): PI_U - напряжение (выход - угол СИФУ: AMAX - u, предел -
 * выход PI_I), PI_I - ток (предел интегратора - выход PI_U). Шаг - по каждому среднему за окно,
 * без программы. Программа пишет задание в кодах АЦП * 16 (пересчёт по калибровке каналов),
 * коэффициенты (K * 4096) и предел угла AMAX
 * --------------------------------------------------------------------------------------------- */
static int32_t  u_set_mv = 50000, i_lim_ma = 1000;		//Задание напряжения, ограничение тока
static uint32_t kp_u = 82U, ki_u = 51U, kp_i = 820U, ki_i = 500U;	//K * 4096
static uint32_t amax;									//Наибольший угол, тиков (120 эл. град.)
static uint32_t u16 = 0U, i16 = 0U;						//Средние последнего окна, код * 16
static uint32_t cc = 0U, steps = 0U, steps_s = 0U;

/* Коэффициент K * 4096 - в единицах блока K * 2^FRAC */
static uint32_t gain(uint32_t k) { return (PI_U_FRAC >= 12U) ? k << (PI_U_FRAC - 12U) : k >> (12U - PI_U_FRAC); }

/* Задание, коэффициенты, пределы - в регуляторы */
static void reg_apply(void) {
	PIREG_SetPoint(PI_U, ADC121_MilliToCode16(ADC121_CAL(ADC_V), u_set_mv));
	PIREG_SetPoint(PI_I, ADC121_MilliToCode16(ADC121_CAL(ADC_C), i_lim_ma));
	PIREG_SetGains(PI_U, gain(kp_u), gain(ki_u));
	PIREG_SetGains(PI_I, gain(kp_i), gain(ki_i));
	PIREG_SetMax(PI_U, amax);
	PIREG_SetMax(PI_I, amax);
	SIFU_SetAlphaMaxExt(amax);
}

static void reg_stop(void) {
	SIFU_ExtDisable();
	PIREG_Disable(PI_U); PIREG_Clear(PI_U);
	PIREG_Disable(PI_I); PIREG_Clear(PI_I);
	cc = 0U;
}

static void reg_start(void) {
	reg_apply();
	PIREG_Clear(PI_U); PIREG_Clear(PI_I);
	PIREG_Enable(PI_U); PIREG_Enable(PI_I);
	SIFU_ExtEnable();										//Угол = AMAX - выход PI_U
}

/* ---------------------------------------------------------------------------------------------
 * Режимы: источник синхронизации, импульсы, регулятор
 * --------------------------------------------------------------------------------------------- */
#define SIM_FREQ100			5000U		//Имитатор сети: 50.00 Гц
#define SIM_DZ10			20U			//Мёртвая зона имитатора: 2.0 град.
#define HOLD_MS				40U			//Импульсы сняты после смены режима
#define DEBOUNCE_MS			50U			//Состояние DI держится столько - принимается

enum { MODE_OFF = 0, MODE_SIM, MODE_GRID, MODE_REG, MODE_MANY };
static const char *const mode_txt[] = {
	"импульсы сняты", "DI1: имитатор сети, угол вручную", "DI2: сеть, угол вручную",
	"DI3: сеть, регулирование напряжения и тока (PI_U, PI_I в ПЛИС)", "включено несколько DI - импульсы сняты" };
static uint32_t mode = MODE_OFF, alpha10 = 1200U;		//Режим, угол вручную (десятые доли град.)
static uint32_t pending = 0U;
static uint32_t cmd_mode __attribute__((unused)) = MODE_OFF;	//Режим командой m (без DI)
static uint64_t hold_end = 0U;

#if STAND_IO
static void stand_init(void) {
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
#endif

/* Режим по входам (с подавлением дребезга) или по команде m */
static uint32_t mode_now(void) {
#if STAND_IO
	static uint32_t raw_old = 0xFFU, stable = MODE_OFF;
	static uint64_t since = 0U;
	uint32_t d1 = GPIO_READ(DI1), d2 = GPIO_READ(DI2), d3 = GPIO_READ(DI3);
	GPIO_WRITE(RO1, d1);
	GPIO_WRITE(RO2, d2);
	GPIO_WRITE(RO3, d3);
	uint32_t n = d1 + d2 + d3;
	uint32_t raw = n == 0U ? MODE_OFF : n > 1U ? MODE_MANY : d1 ? MODE_SIM : d2 ? MODE_GRID : MODE_REG;
	uint64_t now = CORE_GetCycles();
	if (raw_old == 0xFFU) stable = raw;
	if (raw != raw_old) { raw_old = raw; since = now; }
	else if (now - since >= ms_ticks(DEBOUNCE_MS)) stable = raw;
	return stable;
#else
	return cmd_mode;
#endif
}

static void apply_alpha(void) {
	if (alpha10 > SIFU_AlphaMaxDeg10()) alpha10 = SIFU_AlphaMaxDeg10();
	if (mode != MODE_REG) SIFU_SetAlphaDeg10(alpha10);
}

static void set_mode(uint32_t m) {
	SIFU_Disable();
	reg_stop();
	if (m == MODE_SIM) SIFU_SimStart(SIM_FREQ100, SIM_DZ10);
	else               SIFU_SimStop();
	mode = m;
	apply_alpha();
	hold_end = CORE_GetCycles() + ms_ticks(HOLD_MS);
	pending = (m == MODE_SIM || m == MODE_GRID || m == MODE_REG);
	UART_PutText("\r\nРежим: ");
	UART_PutText(mode_txt[m]);
	UART_PutText("\r\n");
}

static void enable_after_hold(void) {
	if (!pending || CORE_GetCycles() < hold_end) return;
	pending = 0U;
	if (mode == MODE_REG) reg_start();						//Регуляторы с нуля: пуск с угла 120 град.
	SIFU_Enable();
}

/* Импульсы идут: EN, сеть есть, синхронизация есть */
static uint32_t running(void) {
	return (SIFU->CR & SIFU_CR_EN) && SIFU_GridPresent() && !SIFU_SyncLost();
}

/* ---------------------------------------------------------------------------------------------
 * Средние за окно: окна закрывает выпрямитель (tick, начало полуволны) - программа только читает
 * их для показа; полуволн нет (сеть отключена) - закрывает сама раз в 10 мс
 * --------------------------------------------------------------------------------------------- */
#define SHOW_AVG_MS			500U		//Показ: среднее окон за 0.5 с
static uint32_t sum_u = 0U, n_u = 0U, sum_i = 0U, n_i = 0U;
static uint32_t show_u16 = 0U, show_i16 = 0U;

static void windows(void) {
	static uint64_t last = 0U, show_next = 0U;
	uint64_t now = CORE_GetCycles();
	if (ADC_V->SR & ADC121_SR_WRDY) {
		ADC121_ClearFlags(ADC_V, ADC121_SR_WRDY);
		u16 = ADC121_GetWMean(ADC_V); sum_u += u16; n_u++;
		last = now;
	}
	if (ADC_C->SR & ADC121_SR_WRDY) {
		ADC121_ClearFlags(ADC_C, ADC121_SR_WRDY);
		i16 = ADC121_GetWMean(ADC_C); sum_i += i16; n_i++;
	}
	if (now - last >= ms_ticks(10U)) {						//Нет полуволн - окна закрывает программа
		last = now;
		ADC121_WindowClose(ADC_V);
		ADC121_WindowClose(ADC_C);
	}
	if (PIREG_Ready(PI_U)) {								//Шаг регулятора прошёл
		PIREG_ClearReady(PI_U);
		steps++;
		cc = PIREG_AtLimit(PI_U) && PIREG_GetOut(PI_I) < amax;
	}
	if (mode != MODE_REG || !running()) cc = 0U;
	if (now >= show_next) {
		show_next = now + ms_ticks(SHOW_AVG_MS);
		if (n_u) { show_u16 = (sum_u + n_u / 2U) / n_u; sum_u = n_u = 0U; }
		if (n_i) { show_i16 = (sum_i + n_i / 2U) / n_i; sum_i = n_i = 0U; }
	}
}

/* ---------------------------------------------------------------------------------------------
 * Меню на TM1638
 * --------------------------------------------------------------------------------------------- */
#define KEY_UP				(1U << 7)	//Кнопка 1
#define KEY_DOWN			(1U << 6)	//Кнопка 2
#define KEY_GAINS			(1U << 5)	//Кнопка 3
#define KEY_ILIM			(1U << 4)	//Кнопка 4
#define KEY_USET			(1U << 3)	//Кнопка 5
#define KEY_ALPHA			(1U << 2)	//Кнопка 6
#define KEY_UFB				(1U << 1)	//Кнопка 7
#define KEY_IFB				(1U << 0)	//Кнопка 8
#define EDIT_MS				5000U
#define FB_MS				2000U
#define BLINK_MS			600U
#define STEP_ALPHA10		5U
#define STEP_U_MV			1000
#define STEP_I_MA			100

enum { P_NONE = 0, P_KPU, P_KIU, P_KPI, P_KII, P_ILIM, P_USET, P_ALPHA, P_UFB, P_IFB };
static uint32_t param = P_NONE;
static uint64_t edit_end = 0U, blink0 = 0U;

static void param_text(uint32_t p, char *t) {
	int32_t v;
	switch (p) {
	case P_KPU: t[0] = 'П'; t[1] = 'U'; t[2] = ' '; fmt_q12(&t[3], kp_u); break;
	case P_KIU: t[0] = 'И'; t[1] = 'U'; t[2] = ' '; fmt_q12(&t[3], ki_u); break;
	case P_KPI: t[0] = 'П'; t[1] = 'I'; t[2] = ' '; fmt_q12(&t[3], kp_i); break;
	case P_KII: t[0] = 'И'; t[1] = 'I'; t[2] = ' '; fmt_q12(&t[3], ki_i); break;
	case P_ILIM: t[0] = 'З'; t[1] = 'I'; t[2] = ' '; fmt_milli(&t[3], i_lim_ma, 3); break;
	case P_USET: t[0] = 'З'; t[1] = 'U'; t[2] = ' '; fmt_milli(&t[3], u_set_mv, u_set_mv < 100000 ? 2 : 1); break;
	case P_ALPHA: {
		uint32_t a10 = (mode == MODE_REG) ? SIFU_TicksToDeg10(SIFU_GetAlphaEff()) : alpha10;
		int n = 4;
		t[0] = 'У'; t[1] = 'Г'; t[2] = 'О'; t[3] = 'Л';
		if (a10 < 1000U) t[n++] = ' ';						//От 100 град. - без пробела: «УГОЛ110.0»
		fmt_milli(&t[n], (int32_t)a10 * 100, 1);
		break;
	}
	case P_UFB:
		v = ADC121_Code16ToMilli(ADC121_CAL(ADC_V), show_u16);
		t[0] = 'U'; t[1] = ' '; fmt_milli(&t[2], v, (v > -100000 && v < 1000000) ? 2 : 1);
		break;
	default:
		v = ADC121_Code16ToMilli(ADC121_CAL(ADC_C), show_i16);
		t[0] = 'I'; t[1] = ' '; fmt_milli(&t[2], v, (v > -10000 && v < 100000) ? 3 : 2);
		break;
	}
}

static void param_change(uint32_t p, int dir) {
	uint32_t *k = (p == P_KPU) ? &kp_u : (p == P_KIU) ? &ki_u : (p == P_KPI) ? &kp_i : (p == P_KII) ? &ki_i : 0;
	if (k) {													//Коэффициенты: шаг 5 %, не меньше 1
		uint32_t s = *k / 20U ? *k / 20U : 1U;
		*k = (dir > 0) ? (*k + s > 0xFFFFU ? 0xFFFFU : *k + s) : (*k > s ? *k - s : 0U);
	} else if (p == P_ILIM) {
		i_lim_ma += dir * STEP_I_MA;
		if (i_lim_ma < 0) i_lim_ma = 0;
	} else if (p == P_USET) {
		u_set_mv += dir * STEP_U_MV;
		if (u_set_mv < 0) u_set_mv = 0;
	} else if (p == P_ALPHA) {
		if (dir > 0) alpha10 += STEP_ALPHA10;
		else alpha10 = alpha10 > STEP_ALPHA10 ? alpha10 - STEP_ALPHA10 : 0U;
		apply_alpha();
	}
	reg_apply();												//Задание и коэффициенты - в регуляторы
}

static void keys(void) {
	static uint32_t old = 0U;
	static uint64_t repeat = 0U;
	uint64_t now = CORE_GetCycles();
	uint32_t k = TM1638_ReadKeys(), press = k & ~old, ud = k & (KEY_UP | KEY_DOWN);
	int step = 0;
	if (ud != (old & (KEY_UP | KEY_DOWN))) { repeat = now + ms_ticks(500U); step = (ud != 0U); }
	else if (ud && now >= repeat) { repeat = now + ms_ticks(100U); step = 1; }
	old = k;
	uint32_t sel = param;
	if (press & KEY_GAINS)      sel = (param >= P_KPU && param < P_KII) ? param + 1U : P_KPU;
	else if (press & KEY_ILIM)  sel = P_ILIM;
	else if (press & KEY_USET)  sel = P_USET;
	else if (press & KEY_ALPHA) sel = P_ALPHA;
	else if (press & KEY_UFB)   sel = P_UFB;
	else if (press & KEY_IFB)   sel = P_IFB;
	if (press & (KEY_GAINS | KEY_ILIM | KEY_USET | KEY_ALPHA | KEY_UFB | KEY_IFB)) {
		param = sel;
		edit_end = now + ms_ticks(EDIT_MS);
		blink0 = now;
	}
	if (step && ud != (KEY_UP | KEY_DOWN)) {
		if (param == P_NONE || param == P_UFB || param == P_IFB)	//Без выбора: угол или задание напряжения
			param = (mode == MODE_REG) ? P_USET : P_ALPHA;
		if (!(mode == MODE_REG && param == P_ALPHA))		//В регулировании угол задаёт регулятор
			param_change(param, (ud & KEY_UP) ? 1 : -1);
		edit_end = now + ms_ticks(EDIT_MS);
		blink0 = now;
	}
	if (param != P_NONE && now >= edit_end) param = P_NONE;
}

static void display(void) {
	static uint64_t next = 0U, fb_next = 0U;
	static uint32_t fb_u = 0U;
	uint64_t now = CORE_GetCycles();
	if (now < next) return;
	next = now + ms_ticks(100U);
	char t[16];
	if (param == P_NONE) {										//Обратные связи: ток и напряжение через 2 с
		if (now >= fb_next) { fb_next = now + ms_ticks(FB_MS); fb_u ^= 1U; }
		param_text(fb_u ? P_UFB : P_IFB, t);
	} else {
		uint32_t ph = (uint32_t)((now - blink0) / ms_ticks(1U)) % BLINK_MS;
		int blink = (param != P_UFB) && (param != P_IFB) && !(mode == MODE_REG && param == P_ALPHA);
		if (blink && ph >= BLINK_MS * 2U / 3U) { for (int i = 0; i < 8; i++) t[i] = ' '; t[8] = '\0'; }
		else param_text(param, t);
	}
	TM1638_WriteText(t);
	uint32_t sr = SIFU->SR, cr = SIFU->CR;
	TM1638_WriteLeds(((sr & SIFU_SR_GRID) ? 1U : 0U) | ((sr & SIFU_SR_LOST) ? 2U : 0U) |
	                 ((cr & SIFU_CR_EN) ? 4U : 0U) | ((cr & SIFU_CR_SIM) ? 8U : 0U) |
	                 (cc ? 16U : 0U) | (mode == MODE_REG ? 32U : 0U));
}

/* ---------------------------------------------------------------------------------------------
 * Терминал
 * --------------------------------------------------------------------------------------------- */
static void status(void) {
	UART_PutText(mode_txt[mode]);
	UART_PutText("; U = ");
	put_milli(ADC121_Code16ToMilli(ADC121_CAL(ADC_V), show_u16), 2);
	UART_PutText(" В (задание ");
	put_milli(u_set_mv, 2);
	UART_PutText("), I = ");
	put_milli(ADC121_Code16ToMilli(ADC121_CAL(ADC_C), show_i16), 3);
	UART_PutText(" А (ограничение ");
	put_milli(i_lim_ma, 3);
	UART_PutText("), угол ");
	uint32_t a10 = SIFU_TicksToDeg10(SIFU_GetAlphaEff());
	UART_PutDec((int32_t)(a10 / 10U)); UART_PutChar('.'); UART_PutChar((char)('0' + a10 % 10U));
	if (mode == MODE_REG) {
		UART_PutText(!running() ? ", стоп (нет импульсов или синхронизации)" : cc ? ", ОГРАНИЧЕНИЕ ТОКА" : ", стабилизация напряжения");
		UART_PutText(", шагов ");
		UART_PutDec((int32_t)steps_s);
		UART_PutText("/с; PI_U: выход ");
		UART_PutDec((int32_t)PIREG_GetOut(PI_U));
		UART_PutText(", ошибка ");
		UART_PutDec(PIREG_GetError(PI_U));
		UART_PutText("; PI_I: выход ");
		UART_PutDec((int32_t)PIREG_GetOut(PI_I));
		UART_PutText(", ошибка ");
		UART_PutDec(PIREG_GetError(PI_I));
	}
	UART_PutText(", f = ");
	uint32_t f = SIFU_GridFreq100();
	if (f) { UART_PutDec((int32_t)(f / 100U)); UART_PutChar('.'); UART_PutDec((int32_t)(f % 100U / 10U)); UART_PutDec((int32_t)(f % 10U)); UART_PutText(" Гц"); }
	else UART_PutText("нет");
	if (SIFU_SyncLost()) UART_PutText(", НЕТ СИНХРОНИЗАЦИИ");
	UART_PutText((SIFU->CR & SIFU_CR_EN) ? ", EN 1" : ", EN 0");
	UART_PutText("\r\n");
}

static void command(const char *line) {
	int32_t v;
	if (line[0] == 'u' && line[1] == ' ' && (v = parse_milli(&line[2])) >= 0) u_set_mv = v;
	else if (line[0] == 'i' && line[1] == ' ' && (v = parse_milli(&line[2])) >= 0) i_lim_ma = v;
	else if (line[0] == 'a' && line[1] == ' ' && (v = parse_milli(&line[2])) >= 0) { alpha10 = (uint32_t)v / 100U; apply_alpha(); }
	else if (line[0] == 'k' && line[1] == 'u' && parse_two(&line[2], &kp_u, &ki_u)) { }
	else if (line[0] == 'k' && line[1] == 'i' && parse_two(&line[2], &kp_i, &ki_i)) { }
	else if (line[0] == 'd' && line[1] == '\0') { adc_detail(&brd_u); adc_detail(&brd_i); }
#if !STAND_IO
	else if (line[0] == 'm' && line[1] == ' ' && line[2] >= '0' && line[2] <= '3') cmd_mode = (uint32_t)(line[2] - '0');
#endif
	else { UART_PutText("Не понял: u <В>, i <А>, a <град.>, ku <KP> <KI>, ki <KP> <KI>, d"
#if !STAND_IO
	                  ", m <0..3>"
#endif
	                  "\r\n"); return; }
	reg_apply();
}

int main(void) {
	char line[32];
	uint64_t next = 0U;

	GPIO_Init();
	UART_InitDefault();
	TM1638_Init();
#if STAND_IO
	stand_init();
#endif
	SIFU_Init();
	adc_start();
	delay_ms(100);
	amax = SIFU_Deg10ToTicks(1200U);
	if (amax > SIFU_AlphaMax()) amax = SIFU_AlphaMax();
	PIREG_Init(PI_U, 0U, 0U, amax);
	PIREG_Init(PI_I, 0U, 0U, amax);
	reg_apply();
	UART_PutText("\r\n== askoRV32: выпрямитель, стабилизация напряжения и ограничение тока В ПЛИС (hw_rect) ==\r\n"
#if STAND_IO
	             "DI1 - имитатор, угол вручную; DI2 - сеть, угол вручную; DI3 - сеть, регулирование U и I\r\n"
#else
	             "Режим - командой m: 0 - импульсы сняты, 1 - имитатор и угол, 2 - сеть и угол, 3 - сеть и регулирование\r\n"
#endif
	             "TM1638: 1/2 - больше/меньше, 3 - коэффициенты, 4 - ограничение тока, 5 - задание U, 6 - угол, 7 - U, 8 - I\r\n"
	             "Терминал: u <В>, i <А>, a <град.>, ku <KP> <KI>, ki <KP> <KI> (K * 4096), d - платы АЦП; Enter - состояние\r\n");
	set_mode(mode_now());
	while (1) {
		uint32_t m = mode_now();
		if (m != mode) set_mode(m);
		enable_after_hold();
		windows();
		adc_poll();
		keys();
		display();
		if (CORE_GetCycles() >= next) {						//Раз в секунду: угол по измеренному полупериоду
			static uint32_t steps_old = 0U;
			next = CORE_GetCycles() + MTIME_HZ;
			steps_s = steps - steps_old;
			steps_old = steps;
			apply_alpha();
		}
		if (!(UART->IP & UART_IT_RXWM)) continue;
		if (UART_GetErrors()) UART_ClearErrors(UART_GetErrors());
		if (UART_ReadLine(line, sizeof line, 1) != 0) command(line);
		status();
		UART_PutText("> ");
	}
}
