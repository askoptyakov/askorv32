#### Платы
Проект один для двух плат: **Tang Nano 9K** (GW1NR-9) и **Tang Primer 20K** (GW2A-18). Плата выбирается активной конфигурацией сборки Eclipse — **Project → Build Configurations → Set Active → TangNano9K / TangPrimer20K**. Общий код — `Core/`; у платы свои `boards/<плата>/<плата>.gwsoc` (конфигуратор ПЛИС), `boards/<плата>/soc.h` (его подключает только своя конфигурация) и `boards/<плата>/openocd.cfg`; сборка — в `TangNano9K/` или `TangPrimer20K/`. Запуски `riscv FPGA SRAM`, `riscv SPI-FLASH`, `riscv Debug OpenOCD` и другие общие — работают с платой активной конфигурации. Подробно — [hw/boards/README.md](../hw/boards/README.md).

#### Прерывания
Описание аппаратной части: [hw/info/interrupts.md](../hw/info/interrupts.md).

- **Сборка:** `-march=rv32im_zicsr`. В Eclipse: *C/C++ Build → Settings → Target Processor*: *Multiply extension (RVM)* включено, *Other extensions* = `_zicsr`, уже задано в `.cproject`. Если ядро собрано без расширения M (`M_EXT = 0` в `top.sv`), галочку RVM нужно снять: иначе `mul`/`div` вызовут исключение «недопустимая инструкция».
- **Стартовый код** `start.S`:
  - `mtvec` = `__vector_table | 1` (векторный режим);
  - таблица из 64 переходов, выравнивание 256 байт: вход 0 — исключения, вход N (1…31) — прерывание с кодом N, вход 32 + S — источник S контроллера PLIC в векторном режиме;
  - все обработчики — слабые ссылки. `Default_Handler` и `Default_Exception_Handler` останавливают программу в бесконечном цикле, причину можно посмотреть в `mcause`, адрес — в `mepc`.
- **Свой обработчик** — функция с именем из таблицы векторов и атрибутом `__IRQ` (`core_riscv.h`). Компилятор сам сохраняет регистры и выходит по `mret`. **Флаг источника нужно сбросить в обработчике**, иначе прерывание сразу повторится.

| Обработчик | Код | Источник |
|------------|:---:|----------|
| `Exception_Handler` | — | все исключения (`mcause` < 0x80000000) |
| `MSI_IRQHandler` | 3 | программное прерывание CLINT |
| `MTI_IRQHandler` | 7 | машинный таймер CLINT |
| `MEI_IRQHandler` | 11 | PLIC без векторного режима (по умолчанию не используется: `PLIC_Init()` включает векторный режим) |
| `LI0_IRQHandler`…`LI15_IRQHandler` | 16…31 | локальные линии: периферия, которой конфигуратор дал `"irq": "local"` (по умолчанию — никто) |
| `PLIC_SRC1_IRQHandler`…`PLIC_SRC31_IRQHandler` | 32 + 1…31 | источники PLIC в векторном режиме |

Номера источников и понятные имена обработчиков даёт `soc.h` (его создаёт конфигуратор ПЛИС). В текущей конфигурации:

| Имя в `soc.h` | Источник | Номер |
|---|---|---|
| `PLIC_STIM_IRQHandler` → `PLIC_SRC1_IRQHandler` | таймер STIM | `PLIC_SRC_STIM` = 1 |
| `PLIC_UART_IRQHandler` → `PLIC_SRC2_IRQHandler` | UART | `PLIC_SRC_UART` = 2 |

- **Функции** (`core_riscv.h`, `clint.h`, `tim.h`, `plic.h`):
  - `__enable_irq()`/`__disable_irq()` — `mstatus.MIE`;
  - `IRQ_Enable(IRQn)`/`IRQ_Disable(IRQn)` — `mie`;
  - `CLINT_SetTimeout(ticks)`/`CLINT_SetCompare(time)`/`CLINT_GetTime()`;
  - `STIM_IT_STATE()`/`STIM_CLEAR_FLAG_UPDATE()`;
  - `CORE_GetCycles()` — `mcycle`;
  - `PLIC_Init()`, `PLIC_SetPriority(src, 1..7)`/`PLIC_Enable(src)`/`PLIC_SetThreshold()`, `PLIC_Complete(src)`.
- **PLIC** (`plic.h`, `plic.c`) собирает прерывания периферии. `PLIC_Init()` включает векторный режим: MEI от источника S сразу переходит на свой вход таблицы векторов, PLIC сам захватывает источник (`claim`). Обработчик источника — функция с `__IRQ`, как у любого прерывания:

  ```c
  __IRQ void PLIC_STIM_IRQHandler(void) {   //имя из soc.h
      STIM_CLEAR_FLAG_UPDATE();             //сбросить флаг прерывания в периферии
      <работа>
      PLIC_Complete(PLIC_SRC_STIM);         //последним: после сброса флага
  }
  ```

  Если записать `complete`, пока флаг в периферии не сброшен, запрос по уровню снова выставит ожидание, и обработчик вызовется повторно. Необъявленный обработчик — слабая ссылка на `Default_Handler` (бесконечный цикл).
- **Частота** `SYSCLK_HZ` — такт периферии, от него считают STIM, UART и `mtime`: 45 МГц для конвейерного ядра, 15 МГц для однотактного. Значение пишет конфигуратор в `soc.h` по настройкам rPLL и ядра — вручную менять не нужно.

#### `soc.h` — описание собранной ПЛИС
Файл `boards/<плата>/soc.h` (у каждой платы свой, см. [hw/boards/README.md](../hw/boards/README.md)) создаёт конфигуратор ПЛИС (`sw/socgen`) из `boards/<плата>/<плата>.gwsoc`, вручную его не правят. В нём: `SYSCLK_HZ`, параметры ядра и памяти, адреса и указатели системных `CLINT`, `PLIC` и каждого блока периферии (`UART_BASE`, `UART`…), `XXX_PRESENT`/`XXX_COUNT`, разрядности, настройки UART после сброса (`UART_BAUD`, `UART_PARITY_DEFAULT`, `UART_STOP_DEFAULT`, `UART_FIFO_DEPTH`), число источников PLIC, `PLIC_SRC_Type` и имена обработчиков, имена выводов GPIO (`LED3_PIN`, `LED3_PORT`). `periphery.h` — общие определения (`__IO`, `__INLINE`) и подключение `soc.h`; типы регистров и биты устройства — в заголовке его драйвера (`gpio.h`, `uart.h`, `tim.h`, `tm1638.h`, `clint.h`, `plic.h`). Драйвер устройства, которого нет в ПЛИС, собирается пустым (`#if XXX_PRESENT`), поэтому выключенный в конфигураторе блок не ломает сборку — ошибку даст только обращение к нему из своей программы.

#### UART (`uart.h`)
Подключён к UART программатора BL702: на ПК это второй COM-порт платы (у первого интерфейса — JTAG), по умолчанию 115200 8-N-1. Строки в прошивке — в cp1251, и по умолчанию (`UART_TEXT_UTF8 = 0` в `uart.h`) текст идёт в терминал как есть: терминал нужен в cp1251 (Termite и другие терминалы Windows без UTF-8). Для терминала в UTF-8 (PuTTY, Tera Term, монитор порта Arduino/VS Code) — `UART_TEXT_UTF8 = 1` (в `uart.h` или `-DUART_TEXT_UTF8=1`): тогда `UART_PutText` перекодирует строки в UTF-8, а `UART_Utf8ToCp1251` — принятый текст обратно. Регистры и функции — [hw/src/periph/uart/README.md](../hw/src/periph/uart/README.md).

- опрос: `UART_InitDefault()`, `UART_PutText`, `UART_PutDec`, `UART_PutHex`, `UART_ReadLine`, `UART_GetChar`;
- прерывания: `UART_IT_Start(порог)`, `UART_IT_PutText`, `UART_IT_Write`, `UART_IT_Read`; обработчик — `UART_IRQ_Service()` + `PLIC_Complete(PLIC_SRC_UART)`.

#### TM1638 (`tm1638.h`)
Индикатор показывает 8 цифр HEX (`TM1638_WriteSegs`), текст cp1251 с кириллицей (`TM1638_WriteText("ПРИВЕТ")`, точка после символа не занимает позицию), число (`TM1638_WriteNumber`) или сегменты как есть (`TM1638_WriteRaw`). Набор символов — [hw/src/periph/tm1638/font.md](../hw/src/periph/tm1638/font.md).

#### Внешняя SPI-флеш (`spiflash.h`)
Блок SPIFLASH в конфигураторе — контроллер флеш U3 платы (P25Q32U, 4 МБайт) и загрузчик программы. Конфигурация и программа хранятся одним из трёх способов: **SRAM** («riscv FPGA SRAM»), **встроенная flash** («riscv FPGA Flash») — программа в битовом потоке; **внешняя флеш с загрузкой по MSPI** («riscv SPI-FLASH», вывод MODE1 = 1) — битовый поток и образ программы из `<конфигурация>/riscv.elf` (`sw/bootimage`) пишет openFPGALoader (`sw/fpgaload/fpgaload.py spiflash`), после любого сброса загрузчик копирует программу в память. Способ выбирается в блоке SPIFLASH («Конфигурация и программа»). Отладка такой программы — **«riscv Debug SPI-FLASH»** (без загрузки, символы из `<конфигурация>/riscv.elf`). Свободная часть флеш (`SPIFLASH_USER_ADDR`, `SPIFLASH_USER_SIZE` в `soc.h`) — для параметров: `SPIFLASH_Read`, `SPIFLASH_EraseSector`, `SPIFLASH_Write`; область образа драйвер не трогает. Итог загрузки — `SPIFLASH_BootStatus()`. В режиме MSPI (`SPIFLASH_FPGA_CONFIG`) ниже `SPIFLASH_USER_ADDR` (битовый поток и образ) библиотека ничего не пишет. Записать и стереть встроенную flash и внешнюю флеш можно и из окна **Программатор ПЛИС** (панель инструментов, меню проекта; [sdk/SETUP.md, п. 8.5](../sdk/SETUP.md#85-загрузка-плис-из-eclipse-openfpgaloader-external-tools)). Подробности — [hw/src/periph/spiflash/README.md](../hw/src/periph/spiflash/README.md).

#### СИФУ тиристорного выпрямителя (`sifu.h`)
Блок SIFU — система импульсно-фазового управления трёхфазным мостовым тиристорным выпрямителем: синхронизация от платы NSB, импульсы на тиристоры VS1…VS6. Угол от прямой связи (выход регулятора PIREG) — `SIFU_ExtEnable()`, угол = AMAX − u. `SIFU_Init()` (настройки из конфигуратора), угол — `SIFU_SetAlphaDeg10(300)` (30,0°, пересчёт по измеренному полупериоду сети) или `SIFU_SetAlpha(тики)`, `SIFU_Enable()`; частота сети — `SIFU_GridFreq100()`, состояние — `SIFU_GridPresent()`, `SIFU_SyncLost()`; прерывание по началу полуволны и по потере синхронизации — `SIFU_IT_Enable(SIFU_CR_SIE | SIFU_CR_LIE)`, обработчик `PLIC_SIFU_IRQHandler`. Проверка без силовой части — имитатор сети `SIFU_SimStart(5000, 20)` (50 Гц, мёртвая зона 2°). Подробности — [hw/src/periph/sifu/README.md](../hw/src/periph/sifu/README.md).

#### Аналоговые измерения (`adc121.h`)
Блок ADC — каналы на АЦП ADC121S051: плата ADC_V (напряжение), ADC_C (ток); функции получают указатель на канал (`ADC_V`, `ADC_C` — `<блок>_<канал>` из `soc.h`, регистры канала k — со смещения k · 0x40). `ADC121_INIT_DEFAULT(ADC_V)`, `ADC121_Start(ADC_V)`; среднее в мВ — `ADC121_MeanMilli(ADC_V, ADC121_CAL(ADC_V))` (масштаб и смещение — из конфигуратора, `ADC_V_SCALE_U`, `ADC_V_OFFSET`); частота — `ADC121_SetRate`, усреднение — `ADC121_SetAverage`, форма сигнала — `ADC121_Capture`; среднее за окно (код × 16) — `ADC121_GetWMean`, пересчёт `ADC121_Code16ToMilli` / `ADC121_MilliToCode16`. Подробности — [hw/src/periph/adc121/README.md](../hw/src/periph/adc121/README.md).

#### Память
`GW1NR9.lds`: `.text` — в IMEM, `.data`, `.rodata`, `.bss`, куча и стек — в DMEM. Стек — 2 кБайт (`_stack_size`). Стек растёт вниз к данным, и при переполнении затирает их без всякой ошибки; если строки или глобальные переменные «портятся сами», первым делом увеличьте стек.

#### Программа (`main.c`): управляемый выпрямитель, регулятор в ПЛИС (ветка `hw_rect`)
Тестовых примеров в этой ветке нет: `main.c` — программа выпрямителя со стабилизацией напряжения и ограничением тока. Блоки ПЛИС — RECT (СИФУ и регулятор CC/CV: `SIFU`, `PI_U`, `PI_I`) и ADC (каналы `ADC_V`, `ADC_C`), связь между ними — в конфигураторе. В режиме регулирования программа пишет задание (`PIREG_SetPoint` в кодах АЦП · 16), коэффициенты, AMAX, включает регуляторы и угол от `PI_U` (`SIFU_ExtEnable`), дальше — только показывает. Режимы на стенде задают DI1..DI3: DI1 — имитатор сети и угол вручную, DI2 — сеть и угол вручную, DI3 — сеть и регулирование; без входов (20K) — команда `m 0..3`. Меню на кнопках TM1638: 1/2 — больше/меньше, 3 — коэффициенты, 4 — ограничение тока, 5 — задание U, 6 — угол, 7/8 — U/I обратной связи; выбранный параметр мигает, через 5 с — ток и напряжение по очереди. Терминал: `u`, `i`, `a`, `ku`, `ki`, `d`. Подробно — [hw/info/rectifier.md](../hw/info/rectifier.md). Вариант с регулятором программой — ветка `fw_rect`.

#### ПИ-регулятор (`pireg.h`) и выпрямитель (`rect.h`)
Регуляторы `PI_U`, `PI_I` — блоки PIREG внутри выпрямителя RECT: `PIREG_Init`, `PIREG_SetPoint`, `PIREG_SetGains`, `PIREG_SetMax`, `PIREG_Enable`, `PIREG_GetOut`, `PIREG_AtLimit`; `rect.h` — тип окна `RECT_TypeDef`. Подробности — [hw/src/periph/rect/README.md](../hw/src/periph/rect/README.md), [hw/src/periph/pireg/README.md](../hw/src/periph/pireg/README.md).

#### Отладка
Через JTAG платы в Eclipse (OpenOCD + GDB): готовая конфигурация `riscv Debug OpenOCD.launch`, конфиг OpenOCD — `boards/<активная конфигурация сборки>/openocd.cfg`. Установка — [sdk/SETUP.md](../sdk/SETUP.md), раздел 8, устройство отладчика — [hw/info/debug.md](../hw/info/debug.md). Программа загружается отладчиком в BSRAM, пересобирать ПЛИС не нужно. Программу из внешней SPI-флеш отлаживает `riscv Debug SPI-FLASH.launch` (без загрузки).

#### Замечания
1. Добавлен глобальный указатель gp для организации более быстрого относительного смещения в секции глобальных данных. Если адреса находятся в области +-2048 байт (+-2кБайт), то к ним осуществляется более быстрый доступ относительно глобального указателя gp, который выставлен со смещением 2048 байт от начала сегмента глобальных данных. Но в реальности, почему-то, работает смещение на 2032 байта, не совсем понимаю почему не дотягивает до 2ух кБайт.