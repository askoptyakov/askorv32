/*
 ******************************************************************************
 * @file        main.c
 * @author		Alexander Koptyakov
 * @device		AskoRV32
 * @brief       Примеры работы с прерываниями. Пример выбирается макросом EXAMPLE:
 *                0 - прежний пример: счётчик таймера STIM на индикаторе TM1638 (без прерываний);
 *                1 - светодиод LED0 мигает раз в секунду по прерыванию таймера STIM;
 *                2 - светодиод LED0 мигает раз в секунду по прерыванию машинного таймера CLINT;
 *                3 - светодиод LED0 мигает раз в секунду по прерыванию таймера STIM через PLIC.
 *              Светодиод переключается каждые 0.5 с: 0.5 с горит, 0.5 с не горит.
 *****************************************************************************************
 */

#include "main.h"
#include "core_riscv.h"
#include "gpio.h"
#include "tm1638.h"
#include "tim.h"
#include "clint.h"
#include "plic.h"

#ifndef EXAMPLE
#define EXAMPLE 1
#endif

/* Полупериод мигания, мс */
#define BLINK_HALF_PERIOD_MS 	500U

/*Прототипы функций*/
unsigned int dig_transform(unsigned int digit);

#if EXAMPLE != 0
volatile unsigned int blink_count = 0;	//Число переключений светодиода

static void LED_Toggle(void) {
	GPIO->OUT ^= (1U << GPIO_LED0);
	blink_count++;
}
#endif

#if EXAMPLE == 1
/*
 * Пример 1: прерывание таймера STIM (локальное прерывание LI0, mcause = 0x80000010).
 * Предделитель делит SYSCLK_HZ до 1 кГц, счётчик считает вверх до 499: событие обновления
 * каждые 500 мс. В обработчике флаг UIF обязательно сбрасывается, иначе прерывание
 * возникнет снова сразу после выхода.
 */
__IRQ void STIM_IRQHandler(void) {
	STIM_CLEAR_FLAG_UPDATE();
	LED_Toggle();
}

static void Example_Init(void) {
	STIM_InitPeriodic(SYSCLK_HZ / 1000U - 1U, BLINK_HALF_PERIOD_MS - 1U);	//1 кГц, 500 тактов
	STIM_IT_STATE(TIM_ENABLE);		//Разрешение прерывания в таймере (CR.UIE)
	IRQ_Enable(STIM_IRQn);			//Разрешение прерывания в ядре (mie)
	__enable_irq();					//Глобальное разрешение (mstatus.MIE)
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
 * Пример 3: тот же таймер STIM, но через контроллер PLIC (источник 1, MEI, mcause = 0x8000000B).
 * Так подключается любая периферия: приоритет и разрешение источника в PLIC, MEI в ядре.
 * Диспетчер MEI_IRQHandler (plic.c) делает claim, вызывает PLIC_STIM_IRQHandler и complete.
 * Обработчик источника - обычная функция, без __IRQ. Прерывание LI0 (STIM_IRQn) не
 * разрешается: иначе одно событие таймера обрабатывалось бы дважды.
 */
void PLIC_STIM_IRQHandler(void) {
	STIM_CLEAR_FLAG_UPDATE();
	LED_Toggle();
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

int main(void) {
#if EXAMPLE == 0
	//#1 Инициализация периферийных устройств
	GPIO_Init();
	TM1638_Init();
	STIM_Init();
	GPIO_PinsMode(0xFFFFFFFF); //Все порты на выход

	STIM_STATE(TIM_ENABLE);

	unsigned int count = 0;
	unsigned int keys = 0;

	while(1) {
		//#Считывание значения таймера
		count = STIM_GET_COUNT();

		//#Светодиоды и кнопки tm1638
		keys = TM1638_ReadKeys();
		TM1638_WriteLeds(keys);

		//#Семисегментный индикатор tm1638
		TM1638_WriteSegs(dig_transform(count));
	}
#else
	GPIO_Init();
	GPIO_PinMode(GPIO_LED0, GPIO_MODE_OUTPUT);
	Example_Init();

	while(1) {
		//Вся работа - в обработчике прерывания; здесь может выполняться основная программа
		__wfi();
	}
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
