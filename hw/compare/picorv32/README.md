PicoRV32 — эталон для сравнения
===============================

[PicoRV32](https://github.com/YosysHQ/picorv32) (Claire Xenia Wolf, лицензия ISC) — компактное многотактное ядро RISC-V, одно из самых распространённых в ПЛИС. Здесь оно собрано на той же ПЛИС и прогоняется тем же CoreMark, что и askoRV32, чтобы сравнивать ядра по ресурсам, частоте и скорости после каждого изменения askoRV32.

## Запуск

```
py hw/compare/picorv32/run_pico.py                 # CoreMark и сборка Gowin, обе конфигурации (~10 мин)
py hw/compare/picorv32/run_pico.py --config min    # только RV32I
py hw/compare/picorv32/run_pico.py --no-synth      # только CoreMark
py hw/compare/picorv32/run_pico.py --no-coremark   # только сборка Gowin
```

Нужны Icarus Verilog, xPack RISC-V GCC и GOWIN EDA (`gw_sh.exe` ищется в `C:\Program Files\Gowin\*`, иначе — переменная `GOWIN_GW_SH`). Промежуточные файлы — в `hw/sim/build/picorv32/`.

| Конфигурация | Параметры PicoRV32 | CoreMark собирается с |
|---|---|---|
| `min` | по умолчанию: RV32I, счётчики, 32 регистра | `-march=rv32i_zicsr` |
| `full` | `ENABLE_IRQ`, `ENABLE_FAST_MUL` (DSP), `ENABLE_DIV`, `BARREL_SHIFTER`, `COMPRESSED_ISA` | `-march=rv32imc_zicsr` |

## Файлы

| Файл | Назначение |
|------|-----------|
| `rtl/picorv32.v`, `rtl/COPYING` | ядро без изменений, коммит `ef203c2` (2026-09-07), лицензия ISC |
| `pico_top.v` | система для синтеза: ядро + 16 кБайт BSRAM (8 + 8, как у askoRV32) + регистр светодиодов |
| `pico_top.cst`, `pico_top.sdc` | выводы Tang Nano 9K; такт с целью 100 МГц, чтобы P&R показал достижимую Fmax |
| `tb_pico.v` | тестбенч CoreMark: карта памяти как у `tb_core` askoRV32, память отвечает через такт (как BSRAM) |
| `run_pico.py` | сборка CoreMark, моделирование, проект Gowin, сводная таблица |

CoreMark берётся из `hw/sim/bench/coremark` без изменений, кроме одного: такты читаются из CSR `cycle`, потому что `mcycle` у PicoRV32 нет. Результат неофициальный, как и для askoRV32: измеряемое время меньше 10 с.

## Как сравнивать с askoRV32 честно

- **Одинаковая цель по частоте.** Для PicoRV32 это 100 МГц (`pico_top.sdc`). В копии проекта askoRV32 нужно поставить в `hw/boards/tangnano9k/riscv.sdc` период `clk_core` 10 нс вместо 74.074: при цели 13.5 МГц P&R останавливается, как только цель достигнута, и Fmax выходит заниженной.
- **Периферия.** В askoRV32 входят TM1638, таймер STIM, CLINT, PLIC и отладчик, у `pico_top` — только регистр светодиодов. Ресурсы процессорной части askoRV32 отдельно — в отчёте `hw/boards/<плата>/impl/gwsynthesis/riscv_syn_resource.html`.
- **Итоговая скорость** = CoreMark/МГц × Fmax. PicoRV32 работает на большей частоте, но тратит на инструкцию 3–4 такта.

## Результаты (2026-09-29, Gowin 1.9.11, GW1NR-LV9QN88PC6/I5, цель 100 МГц)

| Система | LUT | Рег | CLS | BSRAM | DSP | Fmax, МГц | CoreMark/МГц | CoreMark на Fmax |
|---|--:|--:|--:|--:|--:|--:|--:|--:|
| askoRV32 RV32I, до прерываний (`473bad3`) | 3454 | 2046 | 71 % | 8 | — | 25.5 | 0.961 | **24.5** |
| askoRV32 текущая: прерывания, CLINT, PLIC, отладчик (`1b0d83e`) | 5538 | 2879 | 88 % | 8 | — | 16.5 | 0.961 | 15.8 |
| askoRV32 + регистровый файл в SSRAM (Р1; эксперимент до атрибута `distributed_ram`) | 4552 | 1824 | 71 % | 9 | — | 22.0 | 0.961 | 21.1 |
| PicoRV32 `min` | 1558 | 585 | 21 % | 10 | — | 55.6 | 0.270 | 15.0 |
| PicoRV32 `full` | 3217 | 979 | 45 % | 9 | 2 | 41.2 | 0.680 | 28.0 |
| NEORV32 rv32i + CLINT (для справки) | 2540 | 1039 | 38 % | 7 | — | 46.0 | 0.33 ¹ | ≈15 |
| NEORV32 rv32imc, быстрые mul/shift, отладчик (для справки) | 3792 | 1642 | 59 % | 7 | 2 | 45.9 | ≈0.95 ¹ | ≈44 |

Fmax между сборками одной и той же схемы плавает на ±5 % (размещение). Строки PicoRV32 — результат `run_pico.py`.

¹ Из datasheet NEORV32: он написан на VHDL, в Icarus его не промоделировать. NEORV32 собирался один раз для этого сравнения, в репозиторий не добавлен.

**Выводы.**
- На RV32I конвейер askoRV32 выполняет CoreMark в 3,5 раза быстрее на такт (0,961 против 0,270). Даже при вдвое меньшей Fmax он опережает PicoRV32 в 1,6 раза.
- Прерывания и отладчик опустили Fmax askoRV32 с 25,5 до 16,5 МГц. Главный резерв и по ресурсам, и по частоте — регистровый файл: у PicoRV32 и NEORV32 он в памяти (BSRAM или SSRAM), у askoRV32 — на 1024 триггерах. См. [performance_roadmap.md](../../info/performance_roadmap.md#ресурсы-плис).
- С аппаратным умножением PicoRV32 `full` сейчас быстрее (28,0 против 15,8). Оценка для askoRV32 с регистровым файлом в SSRAM и Zmmul — около 50 CoreMark (2,61 CoreMark/МГц × ~20 МГц).
