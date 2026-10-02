Установка ПО (Windows)
======================

Что нужно для работы с askoRV32 и в каком порядке ставить. Версии в таблице — те, на которых проект проверен; более новые, как правило, тоже подходят.

**Установщики всех программ из таблицы:** [Яндекс Диск](https://disk.yandex.ru/d/RUoj9YPl-qn_gw). Ссылки на официальные сайты — в разделах ниже, если нужна более свежая версия.

| # | Программа | Зачем | Установщик | Версия | Статус |
|:-:|-----------|-------|---------------|--------|:------:|
| 1 | GitHub Desktop + Git | работа с репозиторием | `GitHubDesktopSetup-x64.exe` | Git 2.55 | ✅ |
| 2 | Python | утилиты из `sw/` (`.py`-версии) | `python-manager-26.3.msix` | 3.14.6 | ✅ |
| 3 | Icarus Verilog + GTKWave | симуляция и просмотр диаграмм | `iverilog-v14-20260804-x64_setup.exe` | 14.0 / GTKWave 3.3.128 | ✅ |
| 4 | GOWIN EDA (Education) | синтез ПЛИС и прошивка платы | `Gowin_V1.9.11.03_Education_x64_win.exe` | 1.9.11.03 | ✅ |
| 5 | xPack RISC-V GCC | компилятор прошивки | `xpack-riscv-none-elf-gcc-15.2.0-1-win32-x64.zip` | 15.2.0-1 | ✅ |
| 6 | xPack Windows Build Tools | `make`, `rm` для сборки в Eclipse | `xpack-windows-build-tools-4.4.1-3-win32-x64.zip` | 4.4.1-3 | ✅ |
| 7 | Eclipse IDE + Embedded CDT | среда для прошивки `fw/` | `eclipse-inst-jre-win64.exe` | 4.41, Embedded CDT 6.8.0 | ✅ |
| 8 | xPack OpenOCD | отладка через JTAG платы | `xpack-openocd-0.12.0-7-win32-x64.zip` | 0.12.0-7 | ✅ |
| 9 | Zadig | драйвер WinUSB для OpenOCD | `zadig-2.9.exe` | 2.9.788 | ✅ |
| 10 | OSS CAD Suite (Yosys, nextpnr, apicula) | сборка ПЛИС открытым маршрутом (кнопка «Собрать» конфигуратора) | `oss-cad-suite-windows-x64-<дата>.tgz` | 2026-09-29 (Yosys 0.69, apicula 0.34) | ✅ |
| 11 | Плагин «Конфигуратор ПЛИС» | визуальная настройка ПЛИС из проекта `fw/` в Eclipse | `sw/socgen/eclipse/build/askorv32-gwsoc-repo.zip` | 1.0.0 | ⬜ |

Ставьте программы в пути **без кириллицы**, а лучше и без пробелов.

> **«Файл занят другой программой» при запуске установщика.** Обычно это антивирус (например, Kaspersky), который проверяет только что скачанный файл. Подождите минуту и запустите снова. Если не помогло, посмотрите в отчётах антивируса, не попал ли файл в карантин.

---

## 1. GitHub Desktop и Git

1. Установить `GitHubDesktopSetup-x64.exe` (свежая версия: <https://desktop.github.com/>).
2. Войти в свой аккаунт GitHub и клонировать репозиторий `askorv32`.
3. **Git для командной строки ставится отдельно.** GitHub Desktop использует свой встроенный Git и не добавляет его в `PATH`. Для терминала и скриптов нужен **Git for Windows**: <https://git-scm.com/download/win>, настройки по умолчанию.
4. Проверка: в новом окне терминала выполнить `git --version`.

## 2. Python

1. Установить `python-manager-26.3.msix`. Это новый менеджер установок Python (команда `py`).
2. Поставить интерпретатор: `py install 3.14`.
3. Проверка: `py list` и `python --version`.

> Утилиты используют только стандартную библиотеку. В `sw/` лежат готовые `.exe`, поэтому Python нужен только для правки утилит.

**Пересборка `.exe` утилит** (после правки `.py`):
1. Один раз поставить PyInstaller: `py -m pip install pyinstaller` (проверено на 6.22.3).
2. Из корня репозитория, для каждой утилиты (`mergetool`, `instrtosynthmem`, `instrtobsram`):
   ```
   py -m PyInstaller --onefile --noconfirm --distpath sw/mergetool --workpath %TEMP%\pyi --specpath %TEMP%\pyi sw/mergetool/mergetool.py
   ```
   - Ключ `--noconsole` не нужен: утилиты печатают статистику в консоль сборки Eclipse.
   - Утилиты выводят текст в **UTF-8** (`sys.stdout.reconfigure`), потому что консоль сборки Eclipse на Java 18+ читает вывод как UTF-8.
   - Антивирус может проверять только что собранный `.exe`. При ошибке «файл занят» подождать минуту.

## 3. Icarus Verilog и GTKWave (симулятор)

1. Установить `iverilog-v14-20260804-x64_setup.exe` (свежие сборки для Windows: <https://bleyer.org/icarus/>). Путь — без пробелов, например `C:\iverilog`.
2. В установщике отметить компонент **GTKWave** — просмотр временных диаграмм (`.vcd`). Он ставится в ту же папку `bin`.
3. Добавить `C:\iverilog\bin` в `PATH`: установщик версии 14 этого не предлагает.
   1. **Win + R** → `rundll32 sysdm.cpl,EditEnvironmentVariables`.
   2. В блоке «Переменные среды пользователя» выбрать `Path` → **Изменить…** → **Создать** → `C:\iverilog\bin` → **ОК**.
   3. Перезапустить терминал.
4. Проверка в новом окне терминала: `iverilog -V` и `gtkwave --version`.

> SystemVerilog включается ключом `-g2012`: `iverilog -g2012 -o sim.out <файлы>.sv`, затем `vvp sim.out`. Поддержка SystemVerilog у Icarus неполная, поэтому часть конструкций `core.sv` может потребовать упрощения. Это выясним на шаге 0.

## 4. GOWIN EDA

1. Скачать **Gowin EDA Education** (Windows x64): <https://www.gowinsemi.com/en/support/download_eda/>. Нужна бесплатная регистрация.
2. Установить. Лицензия для Education не нужна, GW1NR-9 поддерживается.
3. В установщике оставить отмеченным **Programmer**.
4. Драйвер USB-JTAG: если плата не видна в Programmer, установите его из `<Gowin>\Programmer\driver`.
5. Проверка:
   1. Открыть `hw/riscv.gprj`.
   2. Запустить **Run All**: синтез и P&R должны пройти без ошибок.
   3. В Programmer должно определяться устройство **GW1NR-9C**.

### 4.1. Сборка из конфигуратора и минимальный набор файлов

Кнопка «Собрать» конфигуратора ПЛИС (маршрут **Gowin EDA**) вызывает командную строку IDE `IDE\bin\gw_sh.exe`; окно Gowin EDA при этом не открывается. Путь к IDE находится сам (`C:\Program Files\Gowin\*`), другой каталог задаётся переменной окружения `GOWIN_HOME`.

Для одной только сборки полная установка (1,5 ГБ) не нужна. Проверено на 1.9.11.03: достаточно скопировать из установленной IDE около 310 МБ, и битовый поток получается тем же, что и у полной установки (отличается только время создания в заголовке):

| Из `IDE\` | Размер | Примечание |
|------------|-------:|------------|
| `bin\` | 260 МБ | без `Qt5WebEngine*`, `QtWebEngineProcess.exe`, `opengl32sw.dll`, `d3dcompiler_47.dll`, `libEGL.dll`, `libGLESv2.dll`, `translations\` (−155 МБ); **`vhdl_packages\` нужен** — синтез требует его и для SystemVerilog |
| `lib\` | 16 МБ | Tcl для `gw_sh` |
| `plugins\` | 14 МБ | **обязателен**: без него `gw_sh` молча завершается с кодом 127 |
| `data\` | 17 МБ | можно оставить только `data\device\GW1NR-9C` и CSV-файлы |
| `share\config`, `share\firmcore`, `share\device\GW1NR-9C`, `share\device\*.csv` | 6 МБ | данные кристалла; остальные семейства и `share\ibis` не нужны |

Не нужны для сборки: `doc`, `ipcore`, `simlib` (модели для симулятора — они нужны `hw/sim`, `prim_sim.v`), `Programmer` (прошивка платы), а также графические программы IDE.

Урезанную копию можно положить в любую папку и указать её в `GOWIN_HOME`. Сначала всё равно нужна обычная установка, из которой берутся файлы. Распространять такую копию нельзя, её условия те же, что у лицензии Gowin EDA.

## 5. xPack RISC-V GCC

1. Скачать архив `xpack-riscv-none-elf-gcc-<версия>-win32-x64.zip`: <https://github.com/xpack-dev-tools/riscv-none-elf-gcc-xpack/releases>.
2. Распаковать в `C:\Program Files\Eclipse\riscv-toolchain\` — рядом с Eclipse, чтобы всё лежало в одном месте.
3. Проверка: `"C:\Program Files\Eclipse\riscv-toolchain\xpack-riscv-none-elf-gcc-15.2.0-1\bin\riscv-none-elf-gcc" --version`.

## 6. xPack Windows Build Tools

1. Скачать `xpack-windows-build-tools-<версия>-win32-x64.zip`: <https://github.com/xpack-dev-tools/windows-build-tools-xpack/releases>.
2. Распаковать туда же, в `C:\Program Files\Eclipse\riscv-toolchain\`.
3. Проверка: `"C:\Program Files\Eclipse\riscv-toolchain\xpack-windows-build-tools-4.4.1-3\bin\make" --version`.

## 7. Eclipse IDE и расширение Embedded CDT

### 7.1. Установка Eclipse через установщик

1. Скачать **Eclipse Installer** (`eclipse-inst-jre-win64.exe`) по кнопке *Download x86_64* на <https://www.eclipse.org/downloads/>. Java входит в состав.
2. Запустить установщик и выбрать **Eclipse IDE for C/C++ Developers**.
3. В поле *Installation Folder* указать путь без пробелов, например `C:\eclipse`. Путь по умолчанию лежит в профиле пользователя, а в нём есть пробел (`Koptyakov A`).
4. Оставить галочки *create start menu entry* и *create desktop shortcut* → **INSTALL** → принять лицензии → **LAUNCH**.
   - Окно **Trust Artifacts** с сертификатом *Eclipse.org Foundation — Expired* — это нормально: старые пакеты (например, `javax.xml` 2010 года) подписаны сертификатом, срок которого уже истёк. Отметить строку **Eclipse.org Foundation Inc.**, оставить *Remember selected signers* → **Trust Selected**. Галочку *Always trust all content* не ставить.
   - Установка в `C:\Program Files\...` возможна, но расширения (п. 7.2) может понадобиться ставить, запустив Eclipse **от имени администратора**.
5. При первом запуске выбрать папку рабочего пространства (workspace) без пробелов, например `C:\eclipse-workspace`.

> В списке установщика есть и готовый пакет **Eclipse IDE for Embedded C/C++ Developers**. Если выбрать его, пункт 7.2 можно пропустить. Проверка та же: в **Window → Preferences** есть раздел **MCU**.
>
> Установщик кладёт сами плагины не в папку Eclipse, а в общий пул `%USERPROFILE%\.p2\pool`. При полном удалении Eclipse нужно удалить и `%USERPROFILE%\.p2`.

### 7.2. Установка расширения Embedded CDT (RISC-V)

1. **Help → Install New Software…**
2. В поле *Work with* вставить адрес `https://download.eclipse.org/embed-cdt/updates/v6/` и нажать **Enter**.
3. Раскрыть категорию **Embedded C/C++ Cross Development Tools** и отметить **Embedded C/C++ RISC-V Cross Compiler** — под него настроен проект `fw/`.
   - Если в категории написано **All items are installed** — всё уже стоит, нажать **Cancel**.
   - Категорию **…Developer Resources** не ставить: это исходники самих плагинов.
4. **Next → Next** → принять лицензию → **Finish**.
5. Если Eclipse спросит про доверие к подписи (*Trust Authorities / Trust Artifacts*), отметить источник `eclipse.org` → **Trust Selected**.
6. Перезапустить Eclipse (**Restart Now**).
7. Проверка: в **Window → Preferences** появился раздел **MCU**.

### 7.3. Настройка и сборка проекта

1. Указать пути к инструментам: **Window → Preferences → MCU**.
   - **Global RISC-V Toolchains Paths** (Toolchain: *xPack GNU RISC-V Embedded GCC*): `C:\Program Files\Eclipse\riscv-toolchain\xpack-riscv-none-elf-gcc-15.2.0-1\bin`.
   - **Global Build Tools Path**: `C:\Program Files\Eclipse\riscv-toolchain\xpack-windows-build-tools-4.4.1-3\bin`.
2. Импортировать проект: **File → Import → General → Existing Projects into Workspace** → папка `fw/`.
3. Кодировка проекта. Исходники `fw/` сохранены в **Windows-1251**.
   1. Правой кнопкой на проект `riscv` → **Properties → Resource**.
   2. В блоке *Text file encoding* выбрать **Other** и **вписать вручную** `windows-1251` → **Apply and Close**.
   - Настройка сохраняется в `fw/.settings/` и попадает в репозиторий.
   - Кодировку рабочего пространства (**Preferences → General → Workspace**) не трогать. Пакет Embedded задаёт там UTF-8, и пункт *Default (windows-1251)* не сохраняется: Eclipse возвращает UTF-8.
4. **Сменить префикс компилятора.** Проект создавался под старый тулчейн `riscv-none-embed-`, а xPack называется `riscv-none-elf-`.
   1. Открыть **Project → Properties → C/C++ Build → Settings → Toolchains**.
   2. Для конфигураций *Debug* и *Release* выставить *Prefix* = `riscv-none-elf-`.
5. Проверка: **Project → Build Project** — в `fw/Debug/` должны появиться `riscv.elf`, `riscv.bin` и `riscv.lst`, а в конце лога — статистика `BSRAM IMEM / DMEM` от `mergetool`.
   - `make: *** No rule to make target 'clean'` при самом первом **Clean** — не ошибка: makefile ещё не сгенерирован.

---

## 8. Отладка: OpenOCD и драйвер JTAG

Отладка кода на плате через встроенный программатор Tang Nano 9K. Как устроен отладчик и как его проверить на плате — [hw/info/debug.md](../hw/info/debug.md).

### 8.1. xPack OpenOCD

1. Скачать `xpack-openocd-<версия>-win32-x64.zip` со страницы <https://github.com/xpack-dev-tools/openocd-xpack/releases> (или с Яндекс Диска).
2. Распаковать рядом с компилятором: `C:\Program Files\Eclipse\riscv-toolchain\xpack-openocd-<версия>` (нужны права администратора: распаковать во временную папку и скопировать в Проводнике).
3. Проверка: `"C:\Program Files\Eclipse\riscv-toolchain\xpack-openocd-<версия>\bin\openocd.exe" --version`. Разбор конфигурации проекта без платы — из папки `fw/openocd`: `openocd -f askorv32_tangnano9k.cfg -c shutdown`.

### 8.2. Драйвер WinUSB (Zadig)

OpenOCD работает с программатором через libusb, поэтому интерфейсу JTAG программатора нужен драйвер **WinUSB**. Gowin Programmer работает через драйвер FTDI и после замены драйвера может перестать видеть плату.

Драйвер WinUSB можно оставить **навсегда**: ПЛИС загружается через openFPGALoader (п. 8.5), тоже на WinUSB, и Gowin Programmer тогда не нужен. Варианты и их проверка — в [debug.md, «Прошивка и отладка без смены драйвера»](../hw/info/debug.md#прошивка-и-отладка-без-смены-драйвера).

Если нужен Gowin Programmer, порядок такой:
1. Записать прошивку ПЛИС (с `DEBUG_EN = 1`) во встроенную flash через **Gowin Programmer** в режиме *Embedded Flash Mode*. Тогда она загружается при каждом включении.
2. Заменить драйвер и отлаживать. Новая версия программы загружается отладчиком, пересобирать ПЛИС для этого не нужно.
3. Когда снова понадобится Gowin Programmer (изменилась аппаратная часть), вернуть драйвер FTDI (см. ниже).

Замена драйвера:
1. Скачать Zadig с <https://zadig.akeo.ie>, подключить плату, запустить.
2. **Options → List All Devices**.
3. Выбрать в списке интерфейс программатора с USB ID **`0403 6010`** и **Interface 0**: у Tang Nano 9K он называется **JTAG Debugger (Interface 0)**. Interface 1 — это UART, его не трогать.
4. Справа выбрать **WinUSB** → **Replace Driver**.

   Gowin Programmer (и Gowin IDE) перед заменой закрыть: пока он держит интерфейс, Zadig завершается ошибкой *Operation timed out*.

Возврат драйвера FTDI: **Диспетчер устройств** → то же устройство (Interface 0) → **Удалить устройство** с галочкой *Удалить драйвер* → отключить и снова подключить плату. Windows поставит драйвер FTDI заново.

### 8.3. Проверка подключения

Из папки `fw/openocd`:
```
openocd -c "set JTAG_ONLY 1" -f askorv32_tangnano9k.cfg -c "init; irscan gw1nr9.cpu 0x42; echo [drscan gw1nr9.cpu 32 0]; shutdown"
```
Должно быть `tap/device found: 0x1100481b` и `00001071`. Если нет — см. [debug.md, «Первый запуск на плате»](../hw/info/debug.md#первый-запуск-на-плате).

### 8.4. Отладка в Eclipse

1. **Window → Preferences → MCU → Global OpenOCD Path**: *Executable* = `openocd.exe`, *Folder* = `C:\Program Files\Eclipse\riscv-toolchain\xpack-openocd-<версия>\bin` → **Apply and Close**.
2. Обновить проект (**F5** на `riscv`): появится конфигурация `riscv Debug OpenOCD.launch` из папки `fw/`.
3. **Project → Build Project**, затем **Run → Debug Configurations → GDB OpenOCD Debugging → riscv Debug OpenOCD → Debug**.
4. Eclipse запустит OpenOCD, сбросит систему, загрузит программу и остановится на `main`. Во вкладке *Console* видны выводы OpenOCD и GDB.

- Путь к папке проекта не должен содержать пробелов: программа загружается командой GDB `restore`, которая не понимает кавычки.
- Настройки конфигурации (вкладки *Debugger* и *Startup*) и причины такого выбора — в [debug.md, «Eclipse»](../hw/info/debug.md#eclipse).

### 8.5. Загрузка ПЛИС из Eclipse (openFPGALoader, External Tools)

Загрузка ПЛИС через openFPGALoader на том же драйвере WinUSB, что и у OpenOCD: Gowin Programmer и смена драйвера не нужны. Нужен OSS CAD Suite в `C:\oss-cad-suite` (п. 10) и драйвер WinUSB (п. 8.2).

В папке `fw/` лежат две готовые конфигурации:

| Конфигурация | Что делает | Время |
|--------------|-----------|-------|
| `riscv FPGA SRAM` | загружает ПЛИС в SRAM, до выключения питания | ~3 с |
| `riscv FPGA Flash` | записывает ПЛИС во встроенную flash, ПЛИС стартует с неё при включении (выводы MODE1 = MODE0 = 0) | ~12 с |
| `riscv SPI-FLASH` | записывает битовый поток и программу во внешнюю SPI-флеш, ПЛИС стартует с неё (режим MSPI, MODE1 = 1; блок SPIFLASH «Конфигурация и программа — в этой флеш») | ~3 с, с изменённой ПЛИС ~3 мин |

Все три перед загрузкой собирают проект `riscv` и запускают `sw/fpgaload/fpgaload.py sram|flash|spiflash` (способы хранения — [hw/src/periph/spiflash/README.md](../hw/src/periph/spiflash/README.md#три-способа-хранения-конфигурации-и-программы)). openFPGALoader берётся исправленный, из `sdk/openfpgaloader/bin` (запись внешней флеш GW1N в ~3.5 раза быстрее, работает очистка `--bulk-erase`, см. [sdk/openfpgaloader/README.md](openfpgaloader/README.md)); если его нет — из OSS CAD Suite. Пересобрать его можно в MSYS2 (`C:\msys64`, пакеты и команда — в том же README). Скрипт:
1. Проверяет, что отладка остановлена. Если запущен `openocd.exe`, выводит «Программатор занят…» и выходит, не обращаясь к плате. Одновременная работа с программатором сбивает USB-соединение OpenOCD (консоль без конца заполняется `LIBUSB_ERROR_IO`) и срывает загрузку.
2. Запускает `mergetool`: программа (`Debug/riscv.bin`) вливается в последний битстрим Gowin (`hw/impl/pnr/riscv.fs`). Отдельный запуск нужен потому, что сборка Eclipse вызывает `mergetool` только при изменении `riscv.elf`, и после пересборки одной ПЛИС в `Debug/riscv.fs` остался бы старый дизайн.
3. Загружает `Debug/riscv.fs` командой `openFPGALoader -b tangnano9k [-f] riscv.fs`. OSS CAD Suite ищется в `C:\oss-cad-suite` или в переменной `OSS_CAD_SUITE`, его `bin` и `lib` скрипт сам добавляет в `PATH`.

**Окно «Программатор ПЛИС»** (плагин конфигуратора, п. 11) — то же без *External Tools*, в духе Gowin Programmer: кнопка со значком микросхемы со стрелкой на панели инструментов или команда **Программатор ПЛИС** в контекстном меню проекта. В окне:
- **Запись конфигурации и программы** — SRAM, встроенная flash или внешняя SPI-флеш (недоступный при текущей сборке ПЛИС вариант выключен: встроенная flash — при «Конфигурация и программа — в этой флеш (MSPI)», внешняя флеш — при другой настройке блока SPIFLASH); флажки «Собрать программу перед записью» и «записать битовый поток, даже если он не менялся» (`--force`); кнопка **Прошить**;
- **Очистка** — **Очистить встроенную flash** (`fpgaload.py erase-flash`, ~1 с) и **Очистить SPI-флеш** (`erase-spiflash`: вся внешняя флеш — битовый поток, образ, рабочие параметры; ~1 с) — каждая с подтверждением;
- полоса хода, состояние, время работы и кнопка **Остановить**; вывод — в консоли «askoRV32 - программатор ПЛИС».

Окно немодальное: Eclipse во время записи доступен, закрытие окна запись не прерывает.

**Подключение готовых конфигураций:**
1. Обновить проект (**F5** на `riscv`).
2. **Run → External Tools → External Tools Configurations…**: в группе **Program** появятся `riscv FPGA SRAM`, `riscv FPGA Flash` и `riscv SPI-FLASH`.
3. Они уже в избранном: запускаются из выпадающего списка кнопки **External Tools** на панели инструментов (зелёная стрелка с чемоданчиком). Если кнопки нет: **Window → Perspective → Customize Perspective… → Action Set Availability → External Tools**.
4. Вывод `mergetool` и openFPGALoader — во вкладке *Console*. Успешная загрузка заканчивается строкой `CRC check: Success`.
5. Чтобы полоса прогресса openFPGALoader обновлялась в одной строке, а не печаталась каждый раз новой: **Window → Preferences → Run/Debug → Console** → отметить **Interpret ASCII control characters** и **Interpret Carriage Return (\r) as control character**. openFPGALoader возвращается в начало строки символом `\r`, а без этих флажков консоль Eclipse считает его переводом строки. Кроме того, когда вывод идёт не в терминал, openFPGALoader сам добавляет перевод строки после каждого обновления. Поэтому `fpgaload.py` пропускает его вывод через фильтр `sw/conprogress/conprogress.py`: он убирает перевод строки между обновлениями одной полосы (строки с одной подписью до двоеточия, например `write Flash:`), остальной вывод не меняет. Нужен Python (п. 2, команда `py`).

**Создание вручную** (если конфигурации нет или нужна своя): **Run → External Tools → External Tools Configurations… → Program → New** (кнопка *New launch configuration*), затем:
- вкладка **Main**:
  - *Name*: `riscv FPGA SRAM`;
  - *Location*: `${env_var:ComSpec}` (это `cmd.exe`);
  - *Working Directory*: `${project_loc:riscv}/Debug`;
  - *Arguments*: `/c py -u ..\..\sw\fpgaload\fpgaload.py sram` (для flash — `flash` вместо `sram`);
- вкладка **Build**: отметить *Build before launch*, выбрать *Specific projects* → **Projects…** → `riscv`, снять *Include referenced projects*;
- вкладка **Common**: *Encoding* → *Other* `UTF-8` (`fpgaload.py` и `mergetool` печатают в UTF-8); *Display in favorites menu* → **External Tools**; для общего доступа — *Shared file* `\riscv` (конфигурация сохранится в `fw/` и попадёт в репозиторий);
- **Apply** → **Run**.

**Замечания:**
- Во время отладки (**Debug**) программатор занят OpenOCD, и загрузка откажется начинаться (см. выше): сначала остановить отладку (**Terminate**). Если OpenOCD всё же потерял связь с программатором и засыпает консоль ошибками `LIBUSB_ERROR_IO`, нажать **Terminate** (или завершить `openocd.exe` в Диспетчере задач), при необходимости переподключить плату.
- После загрузки ПЛИС первое чтение `dtmcs` возвращает 0. В `fw/openocd/askorv32_tangnano9k.cfg` для этого есть пустое чтение перед подключением, **Debug** сразу после загрузки работает ([debug.md](../hw/info/debug.md#вариант-а-только-winusb-плис-через-openfpgaloader)).
- То же из командной строки: `py sw/fpgaload/fpgaload.py sram` (или `flash`) из корня репозитория. Сам openFPGALoader — из окна после `C:\oss-cad-suite\environment.bat`, из `fw/Debug`: `openFPGALoader -b tangnano9k riscv.fs` (SRAM), `-f` (flash), `openFPGALoader -b tangnano9k -r` — перезагрузить ПЛИС из flash, как при включении питания.

---

## 10. OSS CAD Suite (открытый маршрут ПЛИС)

1. Скачать `oss-cad-suite-windows-x64-<дата>.tgz` со страницы выпусков <https://github.com/YosysHQ/oss-cad-suite-build/releases> (около 600 МБ).
2. Распаковать в `C:\` так, чтобы получилась папка `C:\oss-cad-suite` (в Git Bash: `tar -xzf oss-cad-suite-windows-x64-<дата>.tgz -C /c/`). Другой путь - через переменную окружения `OSS_CAD_SUITE`.
3. Проверка: `C:\oss-cad-suite\environment.bat`, затем `yosys -V` и `nextpnr-himbaechel --version`.

Генератор `sw/socgen/socgen.py` сам добавляет `bin` и `lib` набора в `PATH`, отдельно настраивать окружение не нужно.

## 11. Плагин «Конфигуратор ПЛИС» для Eclipse

1. Собрать архив (нужен только установленный Eclipse): `py sw/socgen/eclipse/build.py` → `sw/socgen/eclipse/build/askorv32-gwsoc-repo.zip`.
2. Eclipse: **Help → Install New Software → Add… → Archive…** → выбрать этот zip → отметить **askoRV32** → **снять** флажок внизу **Contact all update sites during install to find required software** (иначе p2 заодно тянет посторонние пакеты, например `jcl.over.slf4j`, и падает с «An error occurred while collecting items to be installed») → **Next** → **Finish**. На вопрос о неподписанном содержимом ответить **Install Anyway**, затем перезапустить Eclipse.
3. В проекте `riscv` появится файл `riscv.gwsoc` (двойной щелчок открывает конфигуратор), в контекстном меню проекта и на панели инструментов - команды **Конфигуратор ПЛИС** и **Программатор ПЛИС** (запись и очистка памяти ПЛИС, п. 8.5).
4. Обновление: собрать архив заново и повторить установку (**Help → Install New Software** предложит новую версию).

Подробнее - [sw/socgen/README.md](../sw/socgen/README.md).
