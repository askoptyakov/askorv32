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
#define ADC121_PRESENT					1
#define ADC121_COUNT					2U
#define PIREG_PRESENT					1
#define PIREG_COUNT						2U

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

/* SIFU */
#define SIFU_BASE						(0x16000000U)
#define SIFU							((SIFU_TypeDef*) SIFU_BASE)
#define SIFU_DIV_DEFAULT				80U		//Делитель тика ГПН после сброса: SYSCLK_HZ / (DIV + 1)
#define SIFU_SAW_HZ						500000U		//Частота тиков ГПН при DIV_DEFAULT, Гц
#define SIFU_DELAY_DEFAULT				400U		//DELAY_RC_COMPENSATION после сброса, тиков
#define SIFU_WIDTH_DEFAULT				150U		//Длительность импульса после сброса, тиков
#define SIFU_SIM						1		//Есть имитатор сети (CR.SIM, SIMCFG)
#define SIFU_AMAX_DEFAULT				3333U		//Наибольший угол при CR.UEXT после сброса, тиков (120 эл. град.)
#define SIFU_LINK_U						1		//Вход u (управление: угол = AMAX - u): прямая связь от PI_U.out

/* ADC_V (ADC121) */
#define ADC_V_BASE						(0x17000000U)
#define ADC_V							((ADC121_TypeDef*) ADC_V_BASE)
#define ADC_V_CLK_HZ					54000000U		//Такт блока, Гц: свой rPLL (он же - регистр FCLK)
#define ADC_V_DIV_DEFAULT				3U		//Делитель SCLK после сброса: SCLK = CLK_HZ / (2 * (DIV + 1))
#define ADC_V_CSS_DEFAULT				1U		//От CS до SCLK после сброса, полупериодов SCLK
#define ADC_V_QUIET_DEFAULT				1U		//Пауза между кадрами после сброса, полупериодов SCLK
#define ADC_V_SCLK_HZ					6750000U		//Частота SCLK при DIV_DEFAULT, Гц
#define ADC_V_RATE_HZ					394161U		//Отсчётов в секунду при непрерывной работе (PER = 0)
#define ADC_V_AVGSH_DEFAULT				8U		//Среднее по 2^AVGSH отсчётам
#define ADC_V_BOARD						"ADC_V"		//Плата
#define ADC_V_MODE_AC					0		//Режим платы: 1 - AC (смещение), 0 - DC
#define ADC_V_SCALE_U					222181		//Мк-единиц (V) на код: величина = (код - OFFSET) * SCALE_U / 1e6
#define ADC_V_OFFSET					0		//Код при нулевом входе (округлённый)
#define ADC_V_OFFSET_M					0		//Код при нулевом входе, тысячные доли кода
#define ADC_V_UNIT						"V"		//Единица величины
#define ADC_V_CMP						1		//Есть вход компаратора (SR.CMP, CMPF)
#define ADC_V_WIN						1		//Есть среднее за окно (WMEAN, CR.WCLOSE)
#define ADC_V_LINK_WIN					1		//Вход win (закрыть окно усреднения): прямая связь от SIFU.tick
#define ADC121_BASE						ADC_V_BASE		//Драйверы: первый блок типа
#define ADC121							ADC_V
#define ADC121_CLK_HZ					ADC_V_CLK_HZ
#define ADC121_DIV_DEFAULT				ADC_V_DIV_DEFAULT
#define ADC121_CSS_DEFAULT				ADC_V_CSS_DEFAULT
#define ADC121_QUIET_DEFAULT			ADC_V_QUIET_DEFAULT
#define ADC121_SCLK_HZ					ADC_V_SCLK_HZ
#define ADC121_RATE_HZ					ADC_V_RATE_HZ
#define ADC121_AVGSH_DEFAULT			ADC_V_AVGSH_DEFAULT
#define ADC121_BOARD					ADC_V_BOARD
#define ADC121_MODE_AC					ADC_V_MODE_AC
#define ADC121_SCALE_U					ADC_V_SCALE_U
#define ADC121_OFFSET					ADC_V_OFFSET
#define ADC121_OFFSET_M					ADC_V_OFFSET_M
#define ADC121_UNIT						ADC_V_UNIT
#define ADC121_CMP						ADC_V_CMP
#define ADC121_WIN						ADC_V_WIN
#define ADC121_LINK_WIN					ADC_V_LINK_WIN

/* ADC_C (ADC121) */
#define ADC_C_BASE						(0x13000000U)
#define ADC_C							((ADC121_TypeDef*) ADC_C_BASE)
#define ADC_C_CLK_HZ					54000000U		//Такт блока, Гц: свой rPLL (он же - регистр FCLK)
#define ADC_C_DIV_DEFAULT				3U		//Делитель SCLK после сброса: SCLK = CLK_HZ / (2 * (DIV + 1))
#define ADC_C_CSS_DEFAULT				1U		//От CS до SCLK после сброса, полупериодов SCLK
#define ADC_C_QUIET_DEFAULT				1U		//Пауза между кадрами после сброса, полупериодов SCLK
#define ADC_C_SCLK_HZ					6750000U		//Частота SCLK при DIV_DEFAULT, Гц
#define ADC_C_RATE_HZ					394161U		//Отсчётов в секунду при непрерывной работе (PER = 0)
#define ADC_C_AVGSH_DEFAULT				8U		//Среднее по 2^AVGSH отсчётам
#define ADC_C_BOARD						"ADC_C"		//Плата
#define ADC_C_MODE_AC					0		//Режим платы: 1 - AC (смещение), 0 - DC
#define ADC_C_SCALE_U					45662		//Мк-единиц (A) на код: величина = (код - OFFSET) * SCALE_U / 1e6
#define ADC_C_OFFSET					2049		//Код при нулевом входе (округлённый)
#define ADC_C_OFFSET_M					2049300		//Код при нулевом входе, тысячные доли кода
#define ADC_C_UNIT						"A"		//Единица величины
#define ADC_C_CMP						1		//Есть вход компаратора (SR.CMP, CMPF)
#define ADC_C_WIN						1		//Есть среднее за окно (WMEAN, CR.WCLOSE)
#define ADC_C_LINK_WIN					1		//Вход win (закрыть окно усреднения): прямая связь от SIFU.tick

/* PI_U (PIREG) */
#define PI_U_BASE						(0x19000000U)
#define PI_U							((PIREG_TypeDef*) PI_U_BASE)
#define PI_U_FRAC						12U		//Дробных бит KP, KI: коэффициент = K / 2^FRAC
#define PI_U_OMAX_DEFAULT				3333U		//Верхний предел выхода после сброса
#define PI_U_LINK_FB					1		//Вход fb (обратная связь: шаг по её стробу): прямая связь от ADC_V.wmean
#define PI_U_LINK_LIM					1		//Вход lim (внешний верхний предел выхода и интегратора): прямая связь от PI_I.out
#define PI_U_LINK_TRK					0		//Вход trk (верхний предел интегратора): не подключён
#define PI_U_LINK_RUN					1		//Вход run (1 - работа, 0 - стоп и сброс интегратора): прямая связь от SIFU.run
#define PIREG_BASE						PI_U_BASE		//Драйверы: первый блок типа
#define PIREG							PI_U
#define PIREG_FRAC						PI_U_FRAC
#define PIREG_OMAX_DEFAULT				PI_U_OMAX_DEFAULT
#define PIREG_LINK_FB					PI_U_LINK_FB
#define PIREG_LINK_LIM					PI_U_LINK_LIM
#define PIREG_LINK_TRK					PI_U_LINK_TRK
#define PIREG_LINK_RUN					PI_U_LINK_RUN

/* PI_I (PIREG) */
#define PI_I_BASE						(0x15000000U)
#define PI_I							((PIREG_TypeDef*) PI_I_BASE)
#define PI_I_FRAC						12U		//Дробных бит KP, KI: коэффициент = K / 2^FRAC
#define PI_I_OMAX_DEFAULT				3333U		//Верхний предел выхода после сброса
#define PI_I_LINK_FB					1		//Вход fb (обратная связь: шаг по её стробу): прямая связь от ADC_C.wmean
#define PI_I_LINK_LIM					0		//Вход lim (внешний верхний предел выхода и интегратора): не подключён
#define PI_I_LINK_TRK					1		//Вход trk (верхний предел интегратора): прямая связь от PI_U.out
#define PI_I_LINK_RUN					1		//Вход run (1 - работа, 0 - стоп и сброс интегратора): прямая связь от SIFU.run

/* Прерывания периферии. Источники PLIC (векторный режим, start.S): обработчик источника S -
   PLIC_SRCS_IRQHandler; ниже - понятные имена. Локальные линии: LIn_IRQHandler, номер LIn_IRQn */
#define PLIC_NUM_SOURCES				8U
typedef enum
{
  PLIC_SRC_UART = 1,		//UART
  PLIC_SRC_SIFU = 2,		//SIFU
  PLIC_SRC_ADC_V = 3,		//ADC_V
  PLIC_SRC_ADC_C = 4,		//ADC_C
  PLIC_SRC_PI_U = 5,		//PI_U
  PLIC_SRC_PI_I = 6		//PI_I
} PLIC_SRC_Type;
#define PLIC_UART_IRQHandler			PLIC_SRC1_IRQHandler
#define PLIC_SIFU_IRQHandler			PLIC_SRC2_IRQHandler
#define PLIC_ADC_V_IRQHandler			PLIC_SRC3_IRQHandler
#define PLIC_ADC_C_IRQHandler			PLIC_SRC4_IRQHandler
#define PLIC_PI_U_IRQHandler			PLIC_SRC5_IRQHandler
#define PLIC_PI_I_IRQHandler			PLIC_SRC6_IRQHandler

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
