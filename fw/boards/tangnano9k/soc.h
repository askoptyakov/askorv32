/*
 *****************************************************************************************
 * @file        soc.h
 * @device      AskoRV32
 * @brief       ФАЙЛ СОЗДАН КОНФИГУРАТОРОМ ПЛИС (sw/socgen/socgen.py) из fw/boards/tangnano9k/tangnano9k.gwsoc - не редактируйте вручную.
 *              Частота, устройства (адреса, указатели, настройки), прерывания периферии и имена
 *              выводов GPIO собранной ПЛИС. Типы регистров - в заголовках драйверов (gpio.h, uart.h, plic.h...).
 *****************************************************************************************
 */
#ifndef __SOC_H
#define __SOC_H

/* Плата и ПЛИС */
#define SOC_BOARD						"Tang Nano 9K"
#define SOC_FPGA						"GW1NR-LV9QN88PC6/I5"		//GW1NR-9
#define SOC_FPGA_EMBEDDED_FLASH			1		//Есть встроенная flash конфигурации

/* Ядро и память */
#define SOC_CORE_PIPELINE				1		//1 - конвейерное, 0 - однотактное
#define SOC_M_EXT						1		//Расширение M (mul/div)
#define SOC_DEBUG						1		//Отладчик JTAG
#define SOC_IMEM_BYTES					32768U
#define SOC_DMEM_BYTES					8192U

/* Частота шины периферии (clk_per), Гц: от неё считают таймер STIM, UART и mtime в CLINT */
#define SYSCLK_HZ						40500000U

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
#define STIM_PRESENT					0
#define STIM_COUNT						0U
#define UART_PRESENT					1
#define UART_COUNT						1U
#define SPIFLASH_PRESENT				0
#define SPIFLASH_COUNT					0U
#define SIFU_PRESENT					1
#define SIFU_COUNT						1U
#define ADC_PRESENT						1
#define ADC_COUNT						1U
#define RECT_PRESENT					1
#define RECT_COUNT						1U

/* GPIO */
#define GPIO_BASE						(0x11000000U)
#define GPIO							((GPIO_TypeDef*) GPIO_BASE)
#define GPIO_WIDTH						6U		//Число линий

/* TM1638 */
#define TM1638_BASE						(0x12000000U)
#define TM1638							((TM1638_TypeDef*) TM1638_BASE)

/* UART */
#define UART_BASE						(0x14000000U)
#define UART							((UART_TypeDef*) UART_BASE)
#define UART_BAUD						115200U		//Скорость по умолчанию, бит/с (div 351, ошибка 0.12 %)
#define UART_PARITY_DEFAULT				0		//0 - нет, 1 - even, 2 - odd
#define UART_STOP_DEFAULT				1		//Стоп-битов
#define UART_FIFO_DEPTH					16U		//Глубина FIFO приёма и передачи

/* RECT */
#define RECT_BASE						(0x18000000U)
#define RECT							((RECT_TypeDef*) RECT_BASE)
#define RECT_ADC						ADC		//Блок АЦП обратных связей
#define RECT_FB_U						ADC_V		//Канал напряжения (указатель ADC121_TypeDef)
#define RECT_FB_I						ADC_C		//Канал тока
#define RECT_LINKED						1		//Связь с блоком АЦП задана

/* RECT: СИФУ (+0x00) - драйвер sifu.h, регуляторы PI_U (+0x40), PI_I (+0x80) - драйвер pireg.h */
#define SIFU_BASE						(RECT_BASE + 0x00U)
#define SIFU							((SIFU_TypeDef*) SIFU_BASE)
#define SIFU_DIV_DEFAULT				80U		//Делитель тика ГПН после сброса: SYSCLK_HZ / (DIV + 1)
#define SIFU_SAW_HZ						500000U		//Частота тиков ГПН при DIV_DEFAULT, Гц
#define SIFU_DELAY_DEFAULT				400U		//DELAY_RC_COMPENSATION после сброса, тиков
#define SIFU_WIDTH_DEFAULT				150U		//Длительность импульса после сброса, тиков
#define SIFU_SIM						1		//Есть имитатор сети (CR.SIM, SIMCFG)
#define SIFU_AMAX_DEFAULT				3333U		//Наибольший угол при CR.UEXT после сброса, тиков (120 эл. град.)
#define SIFU_LINK_U						1		//Вход u - выход регулятора напряжения PI_U (CR.UEXT)
#define PIREG_PRESENT					1		//Регуляторы - в блоке выпрямителя
#define PI_U_BASE						(RECT_BASE + 0x40U)
#define PI_U							((PIREG_TypeDef*) PI_U_BASE)
#define PI_U_FRAC						12U		//Дробных бит KP, KI: коэффициент = K / 2^FRAC
#define PI_U_OMAX_DEFAULT				3333U		//Предел выхода после сброса = AMAX
#define PI_I_BASE						(RECT_BASE + 0x80U)
#define PI_I							((PIREG_TypeDef*) PI_I_BASE)
#define PI_I_FRAC						12U		//Дробных бит KP, KI: коэффициент = K / 2^FRAC
#define PI_I_OMAX_DEFAULT				3333U		//Предел выхода после сброса = AMAX

/* ADC */
#define ADC_BASE						(0x17000000U)
#define ADC								((ADC_TypeDef*) ADC_BASE)
#define ADC_CLK_HZ						54000000U		//Такт блока, Гц: свой rPLL (он же - регистр FCLK каналов)
#define ADC_DIV_DEFAULT					7U		//Делитель SCLK после сброса: SCLK = CLK_HZ / (2 * (DIV + 1))
#define ADC_CSS_DEFAULT					1U		//От CS до SCLK после сброса, полупериодов SCLK
#define ADC_QUIET_DEFAULT				1U		//Пауза между кадрами после сброса, полупериодов SCLK
#define ADC_SCLK_HZ						3375000U		//Частота SCLK при DIV_DEFAULT, Гц
#define ADC_RATE_HZ						197802U		//Отсчётов в секунду на канал при непрерывной работе
#define ADC_AVGSH_DEFAULT				8U		//Среднее по 2^AVGSH отсчётам
#define ADC_WIN							1		//Есть среднее за окно (WMEAN, CR.WCLOSE)
#define ADC_CHANNELS					2U		//Каналов (плат измерения)

/* ADC: канал 0 V - плата ADC_V */
#define ADC_V_BASE						(ADC_BASE + 0x00U)
#define ADC_V							((ADC121_TypeDef*) ADC_V_BASE)
#define ADC_V_BOARD						"ADC_V"		//Плата
#define ADC_V_MODE_AC					0		//Режим платы: 1 - AC (смещение), 0 - DC
#define ADC_V_SCALE_U					222181		//Мк-единиц (V) на код: величина = (код - OFFSET) * SCALE_U / 1e6
#define ADC_V_OFFSET					0		//Код при нулевом входе (округлённый)
#define ADC_V_OFFSET_M					0		//Код при нулевом входе, тысячные доли кода
#define ADC_V_UNIT						"V"		//Единица величины
#define ADC_V_CMP						1		//Есть вход компаратора (SR.CMP, CMPF)
#define ADC_V_INDEX						0U		//Номер канала в блоке

/* ADC: канал 1 C - плата ADC_C */
#define ADC_C_BASE						(ADC_BASE + 0x40U)
#define ADC_C							((ADC121_TypeDef*) ADC_C_BASE)
#define ADC_C_BOARD						"ADC_C"		//Плата
#define ADC_C_MODE_AC					0		//Режим платы: 1 - AC (смещение), 0 - DC
#define ADC_C_SCALE_U					45662		//Мк-единиц (A) на код: величина = (код - OFFSET) * SCALE_U / 1e6
#define ADC_C_OFFSET					2049		//Код при нулевом входе (округлённый)
#define ADC_C_OFFSET_M					2049300		//Код при нулевом входе, тысячные доли кода
#define ADC_C_UNIT						"A"		//Единица величины
#define ADC_C_CMP						1		//Есть вход компаратора (SR.CMP, CMPF)
#define ADC_C_INDEX						1U		//Номер канала в блоке

/* Прерывания периферии. Источники PLIC (векторный режим, start.S): обработчик источника S -
   PLIC_SRCS_IRQHandler; ниже - понятные имена. Локальные линии: LIn_IRQHandler, номер LIn_IRQn */
#define PLIC_NUM_SOURCES				8U
typedef enum
{
  PLIC_SRC_UART = 1,		//UART
  PLIC_SRC_RECT = 2,		//RECT
  PLIC_SRC_ADC = 3		//ADC
} PLIC_SRC_Type;
#define PLIC_UART_IRQHandler			PLIC_SRC1_IRQHandler
#define PLIC_RECT_IRQHandler			PLIC_SRC2_IRQHandler
#define PLIC_ADC_IRQHandler				PLIC_SRC3_IRQHandler

/* Выводы GPIO: имя цепи из конфигуратора -> <ИМЯ>_PIN (номер линии) и <ИМЯ>_PORT (блок GPIO);
   цепь LED[3] даёт имя LED3. Шина (LED[0], LED[1]...) на одном блоке: <ИМЯ>_MSK, <ИМЯ>_POS, <ИМЯ>_PORT.
   Работа по имени - макросы GPIO_WRITE(LED3, GPIO_PIN_SET), GPIO_READ(...), GPIO_MODE(...) в gpio.h */
#define DI1_PIN							0U		//вывод 75, цепь DI1
#define DI1_PORT						GPIO
#define DI2_PIN							1U		//вывод 77, цепь DI2
#define DI2_PORT						GPIO
#define DI3_PIN							2U		//вывод 36, цепь DI3
#define DI3_PORT						GPIO
#define RO1_PIN							3U		//вывод 74, цепь RO1
#define RO1_PORT						GPIO
#define RO2_PIN							4U		//вывод 76, цепь RO2
#define RO2_PORT						GPIO
#define RO3_PIN							5U		//вывод 39, цепь RO3
#define RO3_PORT						GPIO

#endif /* __SOC_H */
