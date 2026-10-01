/*
 *****************************************************************************************
 * @file        soc.h
 * @device      AskoRV32
 * @brief       ФАЙЛ СОЗДАН КОНФИГУРАТОРОМ ПЛИС (sw/socgen/socgen.py) из fw/riscv.gwsoc - не редактируйте вручную.
 *              Частота, адреса устройств, прерывания периферии и настройки UART собранной ПЛИС.
 *****************************************************************************************
 */
#ifndef __SOC_H
#define __SOC_H

/* Ядро и память */
#define SOC_CORE_PIPELINE		1			//1 - конвейерное, 0 - однотактное
#define SOC_M_EXT				1			//Расширение M (mul/div)
#define SOC_DEBUG				1			//Отладчик JTAG
#define SOC_IMEM_BYTES			16384U
#define SOC_DMEM_BYTES			8192U

/* Частота шины периферии (clk_dmem), Гц: от неё считают таймер STIM, UART и mtime в CLINT */
#define SYSCLK_HZ				45000000U

/* Устройства: XXX_PRESENT - блок есть в ПЛИС, XXX_BASE - адрес регистров */
#define GPIO_PRESENT			1
#define GPIO_BASE				(0x11000000U)
#define TM1638_PRESENT			1
#define TM1638_BASE				(0x12000000U)
#define STIM_PRESENT			1
#define STIM_BASE				(0x13000000U)
#define UART_PRESENT			1
#define UART_BASE				(0x14000000U)
#define GPIO_WIDTH				6U			//Число линий
#define STIM_WIDTH				16U			//Разрядность PR, PER, PUL, CNT
#define UART_BAUD				115200U		//Скорость по умолчанию, бит/с (div 390, ошибка 0.10 %)
#define UART_PARITY_DEFAULT		0			//0 - нет, 1 - even, 2 - odd
#define UART_STOP_DEFAULT		1			//Стоп-битов
#define UART_FIFO_DEPTH			16U			//Глубина FIFO приёма и передачи

/* Прерывания периферии. Источники PLIC (векторный режим, start.S): обработчик источника S -
   PLIC_SRCS_IRQHandler; ниже - понятные имена. Локальные линии: LIn_IRQHandler, номер LIn_IRQn */
#define PLIC_NUM_SOURCES		8U
typedef enum
{
  PLIC_SRC_STIM = 1,		//STIM
  PLIC_SRC_UART = 2		//UART
} PLIC_SRC_Type;
#define PLIC_STIM_IRQHandler	PLIC_SRC1_IRQHandler
#define PLIC_UART_IRQHandler	PLIC_SRC2_IRQHandler

#endif /* __SOC_H */
