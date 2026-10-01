"""
Задержка прерывания askoRV32: локальная линия LI0, PLIC с программным диспетчером и PLIC в векторном
режиме, моделирование в Icarus Verilog.

    py hw/sim/run_irqlat.py                       # конвейерное ядро, -O0 и -O2
    py hw/sim/run_irqlat.py --core both --opt -O0

Программа bench/irqlat/irqlat.c собирается с кодом прошивки (fw/Core/Startup/start.S, fw/Core/Src/plic.c)
и флагами проекта Eclipse. Тестбенч пишет трассу +irqtrace: такт, запрос таймера тестбенча, PC выборки.
Для каждого прерывания считаются такты от подъёма запроса (выход регистра таймера, как у STIM) до
первой выборки:
  vec   - входа таблицы векторов (аппаратная задержка, как "interrupt latency" в документации SiFive);
  isr   - обработчика: для LI0 и векторного PLIC это обработчик устройства, для PLIC без векторного
          режима - диспетчер MEI_IRQHandler;
  body  - первой команды полезного кода обработчика устройства (после сохранения регистров, а для
          диспетчера - и claim с вызовом по таблице);
  ret   - прерванной программы после mret (полное время обслуживания).
Такты - такты ядра (clk_core).
"""
import argparse
import re
import statistics
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import run_tests as rt  # noqa: E402

REPO = rt.HW_DIR.parent
FW = REPO / "fw"
SRC = rt.SIM_DIR / "bench" / "irqlat"
#Флаги проекта Eclipse (fw/Debug/makefile), кроме -O
FLAGS = ("-march=rv32im_zicsr -mabi=ilp32 -mtune=size -mcmodel=medany -msmall-data-limit=8 -mstrict-align "
         "-msave-restore -fmessage-length=0 -ffunction-sections -fdata-sections -fno-builtin -g").split()
#Путь: вход таблицы векторов, точка входа, функция устройства (для диспетчера), метка полезного кода
PATHS = {"LI0":   (16, "LI0_IRQHandler", None, "li_body"),
         "PLIC":  (11, "MEI_IRQHandler", "stim_sw_handler", "sw_body"),
         "PLICv": (32 + 1, "PLIC_SRC1_IRQHandler", None, "vec_body")}


def build(prefix, opt):
    out = rt.BUILD_DIR / f"irqlat{opt}"
    out.mkdir(parents=True, exist_ok=True)
    elf = out / "irqlat.elf"
    r = rt.run([prefix + "gcc", *FLAGS, opt, f"-I{FW / 'Core' / 'Inc'}", "-nostartfiles",
                "-T", FW / "GW1NR9.lds", "-Wl,--gc-sections", "-o", elf,
                FW / "Core" / "Startup" / "start.S", FW / "Core" / "Src" / "plic.c", SRC / "irqlat.c"])
    if r.returncode:
        sys.exit(f"Ошибка сборки ({opt}):\n" + r.stderr)
    for sect, name in ((".text", "imem"), (".data", "dmem")):
        rt.run([prefix + "objcopy", "-O", "binary", "-j", sect, elf, out / f"{name}.bin"])
        (out / f"{name}.hex").write_text(rt.to_hex_words((out / f"{name}.bin").read_bytes()))
    syms = {}
    for line in rt.run([prefix + "nm", "-S", elf]).stdout.splitlines():
        f = line.split()
        if len(f) >= 3:
            syms[f[-1]] = (int(f[0], 16), int(f[1], 16) if len(f) == 4 else 0)
    return out, syms


def simulate(vvp, out, core):
    trace = out / f"irqtrace_{core}.txt"
    r = rt.run([rt.need("vvp"), "-n", vvp, "+prog=irqlat", f"+imem={(out / 'imem.hex').as_posix()}",
                f"+dmem={(out / 'dmem.hex').as_posix()}", f"+irqtrace={trace.as_posix()}",
                "+timeout=200000"], timeout=600)
    result = next((l for l in r.stdout.splitlines() if l.startswith("RESULT")), "RESULT ERROR " + r.stdout[-300:])
    rows = []
    num = lambda s: int(s, 16) if s != "-" and "x" not in s else -1
    for line in trace.read_text().splitlines():
        c, irq, pcf, pce = line.split()
        rows.append((int(c), irq == "1", num(pcf), num(pce)))
    return result, rows


def measure(rows, syms):
    """Для каждого подъёма запроса - такты до событий. Путь определяется по вектору.
    vec - первая выборка входа таблицы векторов (так задержку считает SiFive; эта выборка не
    спекулятивная - на неё переходит ловушка); остальные события - по командам, выполненным в
    стадии E (выборка за переходом бывает на неверном пути)."""
    vt = syms["__vector_table"][0]
    idle_lo, idle_sz = syms["idle"]
    res = {p: [] for p in PATHS}
    rises = [i for i in range(1, len(rows)) if rows[i][1] and not rows[i - 1][1]]
    for i in rises:
        c0 = rows[i][0]
        seen = {}
        for c, _, pcf, pce in rows[i:]:
            if "vec" not in seen:
                for name, (code, *_r) in PATHS.items():
                    if pcf == vt + 4 * code:
                        seen["vec"], seen["path"] = c - c0, name
            if "path" not in seen:
                continue
            code, isr, disp, body = PATHS[seen["path"]]
            if "isr" not in seen and pce == syms[isr][0]:
                seen["isr"] = c - c0
            if disp and "disp" not in seen and pce == syms[disp][0]:
                seen["disp"] = c - c0
            if "body" not in seen and pce == syms[body][0]:
                seen["body"] = c - c0
            if "body" in seen and idle_lo <= pce < idle_lo + idle_sz:
                seen["ret"] = c - c0
                break
        if "ret" in seen:
            res[seen["path"]].append(seen)
    return res


def calls(rows, syms, name):
    """Сколько раз выполнена первая команда функции (вызовов обработчика)."""
    a = syms[name][0]
    return sum(1 for i, r in enumerate(rows) if r[3] == a and (i == 0 or rows[i - 1][3] != a))


def main():
    ap = argparse.ArgumentParser(description="Задержка прерывания: LI0 против PLIC")
    ap.add_argument("--core", choices=["single", "pipeline", "both"], default="pipeline")
    ap.add_argument("--opt", nargs="+", default=["-O0", "-O2"], help="оптимизация GCC (по умолчанию -O0 -O2)")
    a = ap.parse_args()

    prefix = rt.find_riscv_prefix()
    prim_sim = rt.find_prim_sim()
    rt.BUILD_DIR.mkdir(exist_ok=True)
    cores = ["single", "pipeline"] if a.core == "both" else [a.core]
    vvps = {c: rt.compile_tb(c, prim_sim) for c in cores}

    print(f"{'ядро':9} {'опт.':4} {'путь':5} {'vec':>4} {'isr':>4} {'disp':>5} {'body':>5} {'ret':>5}   (такты от запроса, медиана)")
    for opt in a.opt:
        out, syms = build(prefix, opt)
        for core in cores:
            result, rows = simulate(vvps[core], out, core)
            if not result.startswith("RESULT PASS"):
                print(f"{core:9} {opt:4} {result}")
                continue
            res = measure(rows, syms)
            rises = sum(1 for i in range(1, len(rows)) if rows[i][1] and not rows[i - 1][1])
            print(f"{core:9} {opt:4} запросов {rises}, вызовов: " +
                  ", ".join(f"{p} {calls(rows, syms, PATHS[p][2] or PATHS[p][1])}" for p in PATHS))
            for path, evs in res.items():
                if not evs:
                    print(f"{core:9} {opt:4} {path:5} нет измерений")
                    continue
                med = lambda k: (str(int(statistics.median(e[k] for e in evs))) if k in evs[0] else "-")
                spread = {k: (min(e[k] for e in evs), max(e[k] for e in evs)) for k in ("vec", "body", "ret")}
                note = "  разброс " + ", ".join(f"{k} {lo}-{hi}" for k, (lo, hi) in spread.items() if lo != hi)
                print(f"{core:9} {opt:4} {path:5} {med('vec'):>4} {med('isr'):>4} {med('disp'):>5} "
                      f"{med('body'):>5} {med('ret'):>5}   n={len(evs)}" + (note if "-" in note else ""))


if __name__ == "__main__":
    main()
