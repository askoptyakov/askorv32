Общий установщик askoRV32 SDK
=============================

Один файл `askorv32-sdk-setup-<дата>.exe` ставит все инструменты из [sdk/SETUP.md](../SETUP.md), прописывает переменные среды и настраивает Eclipse. Вручную остаётся только драйвер WinUSB (Zadig, SETUP.md п. 8.2): он ставится под конкретную плату.

## Что ставится

Каталог по умолчанию — `C:\riscv-sdk`, его можно сменить на странице выбора папки. Путь должен быть коротким (не длиннее 57 символов: иначе часть файлов Eclipse не уложится в ограничение Windows на длину пути), без пробелов и кириллицы. При выборе другой папки кнопкой «Обзор» к ней добавляется `riscv-sdk`. Внутри каталога:

| Папка | Инструмент | Примечание |
|-------|-----------|------------|
| `eclipse\` | Eclipse IDE for Embedded C/C++ | плагины askoRV32 (конфигуратор и программатор ПЛИС, пульт выпрямителя) уже установлены; пути MCU заданы |
| `riscv-toolchain\xpack-riscv-none-elf-gcc-*` | xPack RISC-V GCC | обязательный |
| `riscv-toolchain\xpack-windows-build-tools-*` | `make`, `rm` | обязательный |
| `riscv-toolchain\xpack-openocd-*` | OpenOCD | |
| `openfpgaloader\bin` | openFPGALoader с исправлениями ([sdk/openfpgaloader](../openfpgaloader/README.md)) | |
| `oss-cad-suite\` | Yosys, nextpnr, apicula | |
| `iverilog\` | Icarus Verilog + GTKWave | |
| `zadig\` | Zadig | ярлык в меню «Пуск» |
| `Gowin\` | Gowin EDA, если ставится отсюда | каталог по умолчанию в окне установщика Gowin |
| `workspace\` | рабочее пространство Eclipse по умолчанию | при удалении остаётся |
| `uninstall\` | деинсталлятор | |

Сторонние программы ставятся их собственными установщиками, запущенными из общего:
- **Python** (python.org, тихая установка, с командой `py`);
- **Gowin EDA Education** — открывается окно установщика Gowin;
- **GitHub Desktop** (тихая установка в профиль пользователя).

### Окно «Выбор инструментов»

После выбора каталога установщик ищет уже установленное и показывает список с флажками:
- **серая галочка и «✓ установлено»** — инструмент уже есть и заново не ставится; где он найден, видно под списком, если выделить строку;
- **обычная галочка** — будет установлен (галочку можно снять); справа — размер;
- GCC и Build Tools обязательны: если их нет, галочку снять нельзя.

Под списком — сколько места займут отмеченные инструменты и сколько свободно на диске; если не хватает, дальше установщик не пустит. Для Python, Gowin EDA и GitHub Desktop учитывается примерный размер установленной программы и копия их установщика во временной папке.

Флажок **«Разрешить установить заново уже установленные»** делает серые строки доступными: отмеченные ставятся заново в каталог установки. На последней странице перед установкой — итог: что будет установлено и что уже есть.

Где ищется уже установленное:

| Инструмент | Где |
|------------|-----|
| Eclipse | `<каталог>\eclipse` с тем же пакетом Eclipse и теми же версиями плагинов askoRV32 (в установщике плагины новее — предложит обновить) |
| GCC, Build Tools, OpenOCD | `<каталог>\riscv-toolchain` (та же версия), `C:\Program Files\Eclipse\riscv-toolchain\xpack-*` (как в SETUP.md); OpenOCD ещё по переменной `OPENOCD` |
| openFPGALoader, Zadig | только `<каталог>` |
| OSS CAD Suite | `<каталог>\oss-cad-suite`, `OSS_CAD_SUITE`, `C:\oss-cad-suite` |
| Icarus Verilog + GTKWave | `<каталог>\iverilog`, `C:\iverilog`, `PATH` |
| Python | команда `py` (`PATH`, `C:\Windows`, менеджер Python) |
| Gowin EDA | `GOWIN_HOME`, `<каталог>\Gowin`, `C:\Program Files\Gowin`, `C:\Gowin`, `D:\Gowin`; из найденных берётся самая новая версия, и она должна быть не старше той, что в установщике (1.9.11.03) |
| GitHub Desktop | профиль пользователя |

**Версия Gowin EDA.** В программах Gowin номера версии нет, поэтому он берётся из имени каталога (`Gowin_V1.9.9.03_Education_x64`) или из записи Gowin в списке установленных программ. Gowin старше 1.9.11.03 считается не установленным: в его `gw_sh` нет команды `open_project`, и сборка из конфигуратора падает с `invalid command name "open_project"`. В окне такая строка выглядит как «устарел V1.9.9.03» с галочкой «установить». Новый Gowin ставится в `<каталог>\Gowin\Gowin_V1.9.11.03_Education_x64`, и на него указывает `GOWIN_HOME`. Старый остаётся (удаляется своим деинсталлятором). Если номер версии узнать нельзя, найденный Gowin принимается как есть.

Инструменты, найденные в другом месте, используются оттуда: на них указывают пути MCU в Eclipse, `PATH` и переменные среды.

### Переменные среды

Без прав администратора — переменные пользователя; при выборе «Установить для всех пользователей» — системные.

| Переменная | Значение | Кто читает |
|------------|----------|------------|
| `PATH` (+) | `bin` компилятора, Build Tools, OpenOCD, openFPGALoader, Icarus Verilog | терминал |
| `ASKORV32_SDK` | каталог установки | |
| `OPENOCD` | `...\openocd.exe` | `sw/fpgaload/fpgaload.py` |
| `OSS_CAD_SUITE` | каталог OSS CAD Suite | `sw/socgen/socgen.py`, `fpgaload.py` |
| `GOWIN_HOME` | каталог `IDE` Gowin EDA (если найден) | `socgen.py` |

OSS CAD Suite в `PATH` не добавляется: в нём свой Python и библиотеки, которые мешали бы другим программам. Скрипты сами добавляют его `bin` и `lib`, для ручной работы — ярлык «OSS CAD Suite (командная строка)».

При удалении из `PATH` убираются только каталоги, которые добавил установщик, а переменные — только если их значение не меняли. `GOWIN_HOME` остаётся, пока установлен сам Gowin EDA (у него свой деинсталлятор).

### Eclipse

- Пути **Window → Preferences → MCU** (*Global*: RISC-V Toolchain, Build Tools, OpenOCD) записаны в `eclipse\configuration\.settings` и действуют в любом рабочем пространстве. Пути, заданные раньше на уровне рабочего пространства (*Workspace*), главнее — в старом рабочем пространстве проверьте их.
- Консоль: включены *Interpret ASCII control characters* и *Interpret Carriage Return (\r) as control character* (полоса хода openFPGALoader, SETUP.md п. 8.5).
- Проект `fw/` импортируется как обычно: **File → Import → Existing Projects into Workspace**.

## Тихая установка и удаление

- `askorv32-sdk-setup-<дата>.exe /VERYSILENT` — ставится всё, чего нет, в `C:\riscv-sdk` (другой каталог — `/DIR=...`).
- `/TOOLS=id,id,...` — ставить (в том числе заново) только перечисленное: `eclipse`, `gcc`, `buildtools`, `openocd`, `openfpgaloader`, `oss`, `iverilog`, `zadig`, `python`, `gowin`, `github`.
- Удаление — «Удалить askoRV32 SDK» в меню «Пуск» или `<каталог>\uninstall\unins000.exe`.

## Сборка установщика

Нужны:
- Inno Setup 6 (<https://jrsoftware.org/isdl.php> или выпуски на GitHub `jrsoftware/issrc`; проверено на 6.7.2);
- дистрибутивы — в `sdk/`, `%USERPROFILE%\Downloads` или `C:\Distr` (или ключ `--distr`); берётся самая новая версия по маске:

| Маска | Откуда |
|-------|--------|
| `eclipse-embedcpp-*-win32-x86_64.zip` | <https://www.eclipse.org/downloads/packages/> → *Eclipse IDE for Embedded C/C++ Developers* |
| `xpack-riscv-none-elf-gcc-*-win32-x64.zip`, `xpack-windows-build-tools-*-win32-x64.zip`, `xpack-openocd-*-win32-x64.zip` | GitHub, xpack-dev-tools |
| `oss-cad-suite-windows-x64-*.tgz` | GitHub, YosysHQ/oss-cad-suite-build |
| `zadig-*.exe` | <https://zadig.akeo.ie> |
| `python-3.*-amd64.exe` | <https://www.python.org/downloads/windows/> |
| `Gowin_V*_Education_x64_win.zip` | <https://www.gowinsemi.com/en/support/download_eda/> |
| `GitHubDesktopSetup-x64.exe` | <https://desktop.github.com/> |

- Icarus Verilog с GTKWave — установленный (по умолчанию `C:\iverilog`, ключ `--iverilog`): его каталог копируется целиком;
- p2-архивы плагинов `sw/socgen/eclipse/build/askorv32-gwsoc-repo.zip` и `sw/rectgui/build/askorv32-rectgui-repo.zip` (собираются их `build.py`).

```
py sdk/installer/build.py
```

Результат — `sdk/installer/out/askorv32-sdk-setup-<дата>.exe` (около 1,6 ГБ). Промежуточный каталог `sdk/installer/stage/` (~5 ГБ) остаётся; `--keep-stage` пропускает его подготовку, если менялся только `askorv32-sdk.iss`. Оба каталога в git не попадают.

Как устроено:
1. `build.py` распаковывает архивы в `stage/` системным `tar.exe`;
2. в распакованный Eclipse плагины askoRV32 ставятся p2 director (`eclipsec -application org.eclipse.equinox.p2.director`), в `plugin_customization.ini` пакета дописываются настройки консоли;
3. `ISCC` упаковывает `stage/` (LZMA2, у каждого инструмента свой сжатый поток); версии, размеры и имена плагинов передаются через `/D`;
4. при установке `[Code]` в `askorv32-sdk.iss` ищет установленное, показывает окно выбора, запускает сторонние установщики, пишет настройки Eclipse и переменные среды.
