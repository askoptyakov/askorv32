/*
 *****************************************************************************************
 * @file        soc.h
 * @device      AskoRV32
 * @brief       ФАЙЛ СОЗДАН КОНФИГУРАТОРОМ ПЛИС (sw/socgen/socgen.py) из fw/boards/tangprimer20k/tangprimer20k.gwsoc - не редактируйте вручную.
 *              Частота, устройства (адреса, указатели, настройки), прерывания периферии и имена
 *              выводов GPIO собранной ПЛИС. Типы регистров - в заголовках драйверов (gpio.h, uart.h, plic.h...).
 *****************************************************************************************
 */
#ifndef __SOC_H
#define __SOC_H

/* Плата и ПЛИС */
#define SOC_BOARD						"Tang Primer 20K"
#define SOC_FPGA						"GW2A-LV18PG256C8/I7"		//GW2A-18
#define SOC_FPGA_EMBEDDED_FLASH			0		//Есть встроенная flash конфигурации

/* Ядро и память */
#define SOC_CORE_PIPELINE				1		//1 - конвейерное, 0 - однотактное
#define SOC_M_EXT						1		//Расширение M (mul/div)
#define SOC_DEBUG						1		//Отладчик JTAG
#define SOC_IMEM_BYTES					16384U
#define SOC_DMEM_BYTES					8192U

/* Частота шины периферии (clk_per), Гц: от неё считают таймер STIM, UART и mtime в CLINT */
#define SYSCLK_HZ						45000000U

/* Системные устройства процессора (cpu.sv): адреса и указатели; типы регистров - в clint.h и plic.h */
#define CLINT_BASE						(0x02000000U)
#define CLINT							((CLINT_TypeDef*) CLINT_BASE)
#define PLIC_BASE						(0x0C000000U)
#define PLIC							((PLIC_TypeDef*) PLIC_BASE)

/* Устройства. <ТИП>_PRESENT - есть ли в ПЛИС блоки типа, <ТИП>_COUNT - сколько их.
   Для каждого блока: <ИМЯ>_BASE - адрес регистров, <ИМЯ> - указатель на регистры, настройки <ИМЯ>_xxx.
   Драйверы (gpio.c, uart.c...) работают с первым блоком типа под именем типа (GPIO, UART...) */
#define GPIO_PRESENT					1
#define GPIO_COUNT						1U
#define TM1638_PRESENT					1
#define TM1638_COUNT					1U
#define STIM_PRESENT					1
#define STIM_COUNT						1U
#define UART_PRESENT					1
#define UART_COUNT						1U
#define SPIFLASH_PRESENT				1
#define SPIFLASH_COUNT					1U
#define SIFU_PRESENT					1
#define SIFU_COUNT						1U
#define ADC121_PRESENT					1
#define ADC121_COUNT					1U

/* GPIO */
#define GPIO_BASE						(0x11000000U)
#define GPIO							((GPIO_TypeDef*) GPIO_BASE)
#define GPIO_WIDTH						6U		//Число линий

/* STIM */
#define STIM_BASE						(0x13000000U)
#define STIM							((STIM_TypeDef*) STIM_BASE)
#define STIM_WIDTH						16U		//Разрядность PR, PER, PUL, CNT

/* UART */
#define UART_BASE						(0x14000000U)
#define UART							((UART_TypeDef*) UART_BASE)
#define UART_BAUD						115200U		//Скорость по умолчанию, бит/с (div 390, ошибка 0.10 %)
#define UART_PARITY_DEFAULT				0		//0 - нет, 1 - even, 2 - odd
#define UART_STOP_DEFAULT				1		//Стоп-битов
#define UART_FIFO_DEPTH					16U		//Глубина FIFO приёма и передачи

/* SPIFLASH */
#define SPIFLASH_BASE					(0x15000000U)
#define SPIFLASH						((SPIFLASH_TypeDef*) SPIFLASH_BASE)
#define SPIFLASH_SIZE					0x00800000U		//Объём флеш, Байт
#define SPIFLASH_DIV_DEFAULT			1U		//Делитель SCK после сброса
#define SPIFLASH_SCK_HZ					11250000U		//Частота SCK при DIV_DEFAULT, Гц
#define SPIFLASH_FPGA_CONFIG			1		//Флеш хранит конфигурацию ПЛИС с адреса 0 (MSPI)
#define SPIFLASH_BOOT					1		//Загрузчик программы (= FPGA_CONFIG)
#define SPIFLASH_BOOT_ADDR				0x00100000U		//Образ программы во флеш
#define SPIFLASH_BOOT_SIZE				0x00010000U		//Область образа (параметры туда не писать)
#define SPIFLASH_USER_ADDR				0x00110000U		//Свободная область флеш: начало (ниже - конфигурация ПЛИС и образ)
#define SPIFLASH_USER_SIZE				0x006F0000U		//Свободная область флеш: размер

/* TM1638 */
#define TM1638_BASE						(0x12000000U)
#define TM1638							((TM1638_TypeDef*) TM1638_BASE)

/* SIFU */
#define SIFU_BASE						(0x16000000U)
#define SIFU							((SIFU_TypeDef*) SIFU_BASE)
#define SIFU_DIV_DEFAULT				89U		//Делитель тика ГПН после сброса: SYSCLK_HZ / (DIV + 1)
#define SIFU_SAW_HZ						500000U		//Частота тиков ГПН при DIV_DEFAULT, Гц
#define SIFU_DELAY_DEFAULT				400U		//DELAY_RC_COMPENSATION после сброса, тиков
#define SIFU_WIDTH_DEFAULT				150U		//Длительность импульса после сброса, тиков
#define SIFU_SIM						1		//Есть имитатор сети (CR.SIM, SIMCFG)

/* ADC_V (ADC121) */
#define ADC_V_BASE						(0x17000000U)
#define ADC_V							((ADC121_TypeDef*) ADC_V_BASE)
#define ADC_V_DIV_DEFAULT				3U		//Делитель SCLK после сброса: SCLK = SYSCLK_HZ / (2 * (DIV + 1))
#define ADC_V_SCLK_HZ					5625000U		//Частота SCLK при DIV_DEFAULT, Гц
#define ADC_V_RATE_HZ					310345U		//Отсчётов в секунду при непрерывной работе (PER = 0)
#define ADC_V_AVGSH_DEFAULT				8U		//Среднее по 2^AVGSH отсчётам
#define ADC_V_BOARD						"ADC_V"		//Плата
#define ADC_V_MODE_AC					0		//Режим платы: 1 - AC (смещение), 0 - DC
#define ADC_V_SCALE_U					222181		//Мк-единиц (V) на код: величина = (код - OFFSET) * SCALE_U / 1e6
#define ADC_V_OFFSET					0		//Код при нулевом входе
#define ADC_V_UNIT						"V"		//Единица величины
#define ADC121_BASE						ADC_V_BASE		//Драйверы: первый блок типа
#define ADC121							ADC_V
#define ADC121_DIV_DEFAULT				ADC_V_DIV_DEFAULT
#define ADC121_SCLK_HZ					ADC_V_SCLK_HZ
#define ADC121_RATE_HZ					ADC_V_RATE_HZ
#define ADC121_AVGSH_DEFAULT			ADC_V_AVGSH_DEFAULT
#define ADC121_BOARD					ADC_V_BOARD
#define ADC121_MODE_AC					ADC_V_MODE_AC
#define ADC121_SCALE_U					ADC_V_SCALE_U
#define ADC121_OFFSET					ADC_V_OFFSET
#define ADC121_UNIT						ADC_V_UNIT

/* Прерывания периферии. Источники PLIC (векторный режим, start.S): обработчик источника S -
   PLIC_SRCS_IRQHandler; ниже - понятные имена. Локальные линии: LIn_IRQHandler, номер LIn_IRQn */
#define PLIC_NUM_SOURCES				8U
typedef enum
{
  PLIC_SRC_STIM = 1,		//STIM
  PLIC_SRC_UART = 2,		//UART
  PLIC_SRC_SIFU = 3,		//SIFU
  PLIC_SRC_ADC_V = 4		//ADC_V
} PLIC_SRC_Type;
#define PLIC_STIM_IRQHandler			PLIC_SRC1_IRQHandler
#define PLIC_UART_IRQHandler			PLIC_SRC2_IRQHandler
#define PLIC_SIFU_IRQHandler			PLIC_SRC3_IRQHandler
#define PLIC_ADC_V_IRQHandler			PLIC_SRC4_IRQHandler

/* Выводы GPIO: имя цепи из конфигуратора -> <ИМЯ>_PIN (номер линии) и <ИМЯ>_PORT (блок GPIO);
   цепь LED[3] даёт имя LED3. Шина (LED[0], LED[1]...) на одном блоке: <ИМЯ>_MSK, <ИМЯ>_POS, <ИМЯ>_PORT.
   Работа по имени - макросы GPIO_WRITE(LED3, GPIO_PIN_SET), GPIO_READ(...), GPIO_MODE(...) в gpio.h */
#define LED0_PIN						0U		//вывод C13, цепь LED0
#define LED0_PORT						GPIO
#define LED1_PIN						1U		//вывод A13, цепь LED1
#define LED1_PORT						GPIO
#define LED2_PIN						2U		//вывод N16, цепь LED2
#define LED2_PORT						GPIO
#define LED3_PIN						3U		//вывод N14, цепь LED3
#define LED3_PORT						GPIO
#define LED4_PIN						4U		//вывод L14, цепь LED4
#define LED4_PORT						GPIO
#define LED5_PIN						5U		//вывод L16, цепь LED5
#define LED5_PORT						GPIO

#endif /* __SOC_H */
