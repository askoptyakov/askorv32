Пульт выпрямителя (плагин Eclipse и отдельная программа)
=======================================================

Панель «Пульт выпрямителя» — в Eclipse (плагин) или отдельной программой `RectPult.exe` без Eclipse.

**Готовая программа:** архив `RectPult-<версия>.zip` на [Яндекс Диске](https://disk.yandex.ru/d/RUoj9YPl-qn_gw) (папка `_distr-askorv32`) — распаковать и запустить `RectPult/RectPult.exe`; установка, Eclipse и Java не нужны. Через неё по UART выпрямителем askoRV32 (ветки `hw_rect`, `fw_rect`) управляют так:
- режим и импульсы;
- задание и коэффициенты регуляторов;
- контроль измерений и битов ошибок;
- осциллограмма U и I с запуском по фронту.

Описание панели, протокол и проверка — [hw/info/rectifier_gui.md](../../hw/info/rectifier_gui.md).

## Сборка и установка

```
py sw/rectgui/build.py
```

- **Что нужно для сборки.** Только установленный Eclipse с CDT:
  - javac — встроенная Java Eclipse (JustJ);
  - библиотеки — пул пакетов `~/.p2/pool/plugins`;
  - COM-порт — пакет `org.eclipse.cdt.native.serial`.

  Общие части сборки берутся из [sw/socgen/eclipse/build.py](../socgen/eclipse/build.py).
- **Результат** — `build/askorv32-rectgui-repo.zip`.
- **Установка в Eclipse:** Help > Install New Software > Add > Archive… > архив > категория «askoRV32 - пульт выпрямителя» > Next > Finish, затем перезапуск. Уже установленный пульт обновляют через Help > Check for Updates.
- **Где открыть:** кнопка на панели инструментов или Window > Show View > Other > askoRV32 > Пульт выпрямителя.

## Отдельная программа RectPult.exe

Готовый архив — на [Яндекс Диске](https://disk.yandex.ru/d/RUoj9YPl-qn_gw); собрать самому:

```
py sw/rectgui/build_exe.py
```

- **Что нужно для сборки:**
  - Eclipse с CDT — как для плагина: Java JustJ, SWT, пакет COM-порта;
  - MSYS2 UCRT64 (`C:\msys64\ucrt64\bin`, пакет `mingw-w64-ucrt-x86_64-gcc`) — `gcc` и `windres` для запускателя со значком; другой каталог — ключ `--gcc`;
  - Python с Pillow — значок.
- **Результат** — `dist/RectPult/` и архив `dist/RectPult-<версия>.zip` (около 140 МБ; `dist/` в git не хранится):
  - `RectPult.exe` — запускатель (`launcher/rectpult.c`): запускает `runtime\bin\javaw.exe` с классом `RectApp` и выходит;
  - `lib` — `rectgui.jar` (панель без классов вида Eclipse), SWT, пакет COM-порта CDT и `serial.dll`;
  - `runtime` — Java JustJ из Eclipse, около 180 МБ (копируется заново, только если версия сменилась);
  - `ВЕРСИЯ.txt` — версия сборки и пакетов.
- **Установка не нужна:** каталог переносится как есть (или распаковывается архив), Eclipse и Java на другом ПК не нужны. Окно — «Пульт выпрямителя askoRV32», размер и положение запоминаются. Настройки панели (порт, осциллограмма) — общие с плагином (реестр Windows, `ru/askorv32/rectgui`).
- **Список COM-портов.** `SerialPort.list()` CDT берёт его из реестра через платформу Eclipse; без неё `RectLink` читает `HKLM\HARDWARE\DEVICEMAP\SERIALCOMM` командой `reg query`.

## Файлы

| Файл | Назначение |
|---|---|
| `src/.../RectPanel.java` | панель: порт, управление, задание, коэффициенты, измерения, ошибки, осциллограмма (точки, единицы, масштаб), журнал; без зависимостей от верстака Eclipse |
| `src/.../RectView.java` | вид Eclipse — обёртка над `RectPanel` |
| `src/.../RectApp.java` | отдельная программа: окно с `RectPanel` |
| `src/.../RectLink.java` | связь: COM-порт (CDT `SerialPort`), очередь команд с ожиданием ответа, опрос `@S`, разбор `#S`, `#I`, `#E`, `#W`/`#D` |
| `src/.../ScopeCanvas.java` | осциллограмма: шкалы U (слева) и I (справа), время от точки запуска, линии уровня и положения запуска (перетаскиваются мышью) |
| `src/.../OpenViewHandler.java` | кнопка панели инструментов |
| `plugin.xml`, `META-INF/MANIFEST.MF`, `plugin.properties` | описание плагина (строки — в UTF-8, при сборке переводятся в `\uXXXX`) |
| `build.py` | сборка плагина и p2-репозитория |
| `build_exe.py`, `launcher/rectpult.c` | сборка отдельной программы `RectPult.exe` |

Прошивка со стороны стенда — раздел «Пульт на ПК» в `fw/Core/Src/main.c`: строки `@...`, захват кадра `scope_capture()`, отправка `scope_line()`.
