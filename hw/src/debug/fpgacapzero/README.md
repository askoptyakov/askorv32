Файлы из проекта [fpgacapZero](https://github.com/lcapossio/fpgacapZero) (Apache License 2.0, см. LICENSE), без изменений.
Коммит: 1d6574127f9d0c465921b428c1e1f5a4229079c9 (2026-09-24).

| Файл | Назначение |
|------|-----------|
| `jtag_tap_gowin.v` | Обёртка примитива GW_JTAG: стробы capture/shift/update пользовательских регистров ER1/ER2 в системном тактовом домене. Проверена авторами на GW1NR-9 с OpenOCD |
| `dff_reg_sync.v`, `dff_sync.v` | Синхронизаторы |
| `gw_jtag.v` | Объявление примитива GW_JTAG для синтеза (вместо модели - в моделировании используется hw/sim/gw_jtag_model.sv) |
