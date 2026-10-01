/*
 * Задержка прерывания: локальная линия LI0, PLIC с программным диспетчером и PLIC в векторном режиме.
 * Запускается из hw/sim/run_irqlat.py.
 *
 * Код ловушек - настоящий из прошивки: start.S (таблица векторов, mtvec), plic.c (PLIC_Init включает
 * векторный режим), обработчики с атрибутом __IRQ. Программный диспетчер MEI (прежний вариант plic.c,
 * до векторного режима) повторён здесь для сравнения. Источник - таймер тестбенча (0x1F000100,
 * регистры как у STIM), он подключён и к LI0, и к источнику 1 PLIC - как STIM в top.sv.
 *
 * Метки li_body / sw_body / vec_body отмечают первую команду полезного кода обработчика (после
 * сохранения регистров), функция idle - прерываемую программу. Такты считает run_irqlat.py по трассе
 * +irqtrace тестбенча: подъём запроса таймера, PC выборки и PC команды в стадии E на каждом такте.
 */
#include "core_riscv.h"
#include "plic.h"

#define TBTIM           ((STIM_TypeDef *)0x1F000100U)   //Таймер тестбенча
#define SRC_TBTIM       ((PLIC_SRC_Type)1)              //Он же - источник 1 PLIC и LI0 (tb_core.sv)
#define TBTIM_CR_EN     (1U << 3)
#define TBTIM_CR_UIE    (1U << 4)
#define TOHOST          (*(volatile uint32_t *)0x1F000000U)
#define TOHOST_ACTUAL   (*(volatile uint32_t *)0x1F000004U)

#define N_IRQ           8U      //Прерываний на каждый путь
#define PERIOD          400U    //Период таймера, тактов: обработчик успевает закончиться

#define MARK(name)      __asm__ volatile (".globl " #name "\n" #name ":")

volatile uint32_t n_li, n_sw, n_vec;

/* Путь 1: локальная линия LI0 (mcause 16) - вектор сразу на обработчик устройства */
__IRQ void LI0_IRQHandler(void) {
	MARK(li_body);
	TBTIM->SR = STIM_SR_UIF;
	n_li++;
}

/* Путь 2: PLIC без векторного режима - вход 11 и программный диспетчер (прежний plic.c):
   claim, вызов обычной функции по таблице, complete, повторный claim */
static void stim_sw_handler(void) {
	MARK(sw_body);
	TBTIM->SR = STIM_SR_UIF;
	n_sw++;
}
static uint32_t plic_current_id;
static void sw_default(void) { PLIC_Disable((PLIC_SRC_Type)plic_current_id); }
static void (* const sw_handlers[PLIC_NUM_SOURCES + 1])(void) = {
	0, stim_sw_handler, sw_default, sw_default, sw_default, sw_default, sw_default, sw_default, sw_default
};
__IRQ void MEI_IRQHandler(void) {
	uint32_t id;
	while ((id = PLIC_Claim()) != 0) {
		plic_current_id = id;
		if (id <= PLIC_NUM_SOURCES)
			sw_handlers[id]();
		PLIC_Complete((PLIC_SRC_Type)id);
	}
}

/* Путь 3: PLIC в векторном режиме - вход 32 + 1, PLIC сам делает claim */
__IRQ void PLIC_SRC1_IRQHandler(void) {
	MARK(vec_body);
	TBTIM->SR = STIM_SR_UIF;
	n_vec++;
	PLIC_Complete(SRC_TBTIM);
}

/* Прерываемая программа: ждёт n прерываний */
__attribute__((noinline)) void idle(volatile uint32_t *cnt, uint32_t n) {
	while (*cnt < n) ;
}

static void run(volatile uint32_t *cnt) {
	TBTIM->CR = TBTIM_CR_EN | TBTIM_CR_UIE;
	idle(cnt, N_IRQ);
	TBTIM->CR = 0;
	TBTIM->SR = STIM_SR_UIF;
}

int main(void) {
	TBTIM->PER = PERIOD;
	__enable_irq();

	IRQ_Enable(LI0_IRQn);
	run(&n_li);
	IRQ_Disable(LI0_IRQn);

	PLIC_Init();
	PLIC->VECTOR = 0;                       //Путь 2: без векторного режима
	PLIC_SetPriority(SRC_TBTIM, 1);
	PLIC_Enable(SRC_TBTIM);
	IRQ_Enable(MEI_IRQn);
	run(&n_sw);

	PLIC->VECTOR = 1;                       //Путь 3: векторный режим
	run(&n_vec);

	TOHOST_ACTUAL = 0;
	TOHOST = 1;
	for (;;) ;
}
