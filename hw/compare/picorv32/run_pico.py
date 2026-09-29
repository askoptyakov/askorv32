"""
PicoRV32 на ПЛИС Tang Nano 9K (GW1NR-9): эталон для сравнения с askoRV32.

    py hw/compare/picorv32/run_pico.py                    # CoreMark и сборка Gowin, обе конфигурации
    py hw/compare/picorv32/run_pico.py --config min       # только RV32I
    py hw/compare/picorv32/run_pico.py --no-synth         # только CoreMark (Icarus Verilog)
    py hw/compare/picorv32/run_pico.py --no-coremark      # только сборка Gowin

Конфигурации:
    min  - RV32I, параметры PicoRV32 по умолчанию;
    full - RV32IMC: IRQ, быстрый умножитель (DSP), деление, barrel shifter.

CoreMark собирается из тех же файлов, что для askoRV32 (hw/sim/bench/coremark), только
такты читаются из CSR cycle: mcycle у PicoRV32 нет. Сборка Gowin: pico_top.v + pico_top.cst +
pico_top.sdc (цель 100 МГц), результат - ресурсы и Fmax из отчётов P&R.
Промежуточные файлы - в hw/sim/build/picorv32/.
"""
import argparse
import glob
import html
import os
import re
import shutil
import sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent.parent / "sim"))
import run_tests as rt  # noqa: E402  (поиск тулчейна и Icarus, запуск команд)

CM_DIR = rt.SIM_DIR / "bench" / "coremark"
EEMBC = ["core_list_join.c", "core_main.c", "core_matrix.c", "core_state.c", "core_util.c"]
PORT = ["crt0.S", "core_portme.c", "ee_printf.c"]
OUT = rt.BUILD_DIR / "picorv32"
CONFIGS = {"min": {"full": 0, "march": "rv32i_zicsr"},
           "full": {"full": 1, "march": "rv32imc_zicsr"}}
PART = "GW1NR-LV9QN88PC6/I5"


def find_gw_sh():
    env = os.environ.get("GOWIN_GW_SH")
    if env:
        return env
    hits = sorted(glob.glob(r"C:\Program Files\Gowin\*\IDE\bin\gw_sh.exe") + glob.glob(r"C:\Gowin\*\IDE\bin\gw_sh.exe"))
    if hits:
        return hits[-1]
    sys.exit("Не найден gw_sh.exe из GOWIN EDA: задайте GOWIN_GW_SH")


# ----------------------------------------------------------------------------------------
# CoreMark в Icarus Verilog
# ----------------------------------------------------------------------------------------
def coremark(cfg, prefix, iterations):
    c = CONFIGS[cfg]
    out = OUT / cfg
    port = out / "port"
    port.mkdir(parents=True, exist_ok=True)
    for f in (CM_DIR / "askorv32").iterdir():
        shutil.copy(f, port)
    h = port / "core_portme.h"
    h.write_bytes(h.read_bytes().replace(b"csrr %0, mcycle", b"csrr %0, cycle"))

    flags = f"-O2 -march={c['march']} -mabi=ilp32"
    elf = out / "coremark.elf"
    r = rt.run([prefix + "gcc", *flags.split(), f"-I{port}", f"-I{CM_DIR / 'eembc'}",
                f"-DITERATIONS={iterations}", "-DPERFORMANCE_RUN=1", f'-DFLAGS_STR="{flags}"',
                "-nostartfiles", "-T", port / "link.ld", "-o", elf,
                *[port / f for f in PORT], *[CM_DIR / "eembc" / f for f in EEMBC]])
    if r.returncode:
        return {"error": "сборка CoreMark: " + r.stderr[-500:]}
    for sect, name in ((".text", "imem"), (".data", "dmem")):
        rt.run([prefix + "objcopy", "-O", "binary", "-j", sect, elf, out / f"{name}.bin"])
        (out / f"{name}.hex").write_text(rt.to_hex_words((out / f"{name}.bin").read_bytes()))

    vvp = out / "tb_pico.vvp"
    r = rt.run([rt.need("iverilog"), "-g2012", "-o", vvp, f"-Ptb_pico.FULL={c['full']}",
                HERE / "tb_pico.v", HERE / "rtl" / "picorv32.v"])
    if r.returncode:
        return {"error": "iverilog: " + r.stderr[-500:]}
    r = rt.run([rt.need("vvp"), "-n", vvp, f"+imem={(out / 'imem.hex').as_posix()}",
                f"+dmem={(out / 'dmem.hex').as_posix()}"], timeout=24 * 3600)
    (out / "console.txt").write_text(r.stdout, encoding="utf-8")
    get = lambda key: (re.search(rf"^{key}\s*:\s*(\S+)", r.stdout, re.M) or [None, None])[1]
    ticks, iters = int(get("Total ticks") or 0), int(get("Iterations") or 0)
    ok = ("RESULT PASS" in r.stdout and get("seedcrc") == "0xe9f5"
          and not re.search(r"ERROR! (?:list|matrix|state) crc", r.stdout) and ticks > 0)
    return {"ok": ok, "ticks": ticks, "cm_mhz": iters * 1e6 / ticks if ticks else 0, "flags": flags}


# ----------------------------------------------------------------------------------------
# Сборка Gowin
# ----------------------------------------------------------------------------------------
def synth(cfg, gw_sh):
    out = OUT / cfg / "gowin"
    out.mkdir(parents=True, exist_ok=True)
    top = out / "pico_sys.v"
    top.write_text("module pico_sys (input wire clk, rst_n, output wire [5:0] led);\n"
                   f"    pico_top #(.FULL({CONFIGS[cfg]['full']})) sys (.clk(clk), .rst_n(rst_n), .led(led));\n"
                   "endmodule\n")
    p = lambda f: Path(f).as_posix()
    tcl = [f"create_project -name pico -dir {{{p(out)}}} -pn {PART} -device_version C -force",
           f"add_file {{{p(HERE / 'rtl' / 'picorv32.v')}}}", f"add_file {{{p(HERE / 'pico_top.v')}}}",
           f"add_file {{{p(top)}}}", f"add_file {{{p(HERE / 'pico_top.cst')}}}", f"add_file {{{p(HERE / 'pico_top.sdc')}}}",
           "set_option -top_module pico_sys", "set_option -verilog_std sysv2017",
           "set_option -use_sspi_as_gpio 1", "set_option -use_mspi_as_gpio 1", "run all"]
    (out / "build.tcl").write_text("\n".join(tcl) + "\n")
    r = rt.run([gw_sh, out / "build.tcl"], cwd=out, timeout=3600)
    (out / "gw.log").write_text(r.stdout + r.stderr, encoding="utf-8")
    rpt = next(out.rglob("pnr/*.rpt.txt"), None)
    if not rpt:
        return {"error": "Gowin: нет отчёта P&R, см. " + str(out / "gw.log")}
    t = rpt.read_text(errors="replace")
    g = lambda k: re.search(rf"^\s*{k}\s*\|\s*(\d+)/(\d+)", t, re.M)
    cls = g("CLS")
    dsp = re.search(r"^\s*DSP\s*\|\s*(\d+)/", t, re.M)
    h = html.unescape(re.sub(r"<[^>]+>", "|", next(out.rglob("pnr/*_tr_content.html")).read_text(errors="replace")))
    h = re.sub(r"\|\s*(\|\s*)+", "|", h)
    fm = re.search(r"\|clk\|[\d.]+\(MHz\)\|([\d.]+)\(MHz\)", h)
    return {"logic": int(g("Logic")[1]), "reg": int(g("Register")[1]), "cls": int(cls[1]),
            "cls_pct": 100 * int(cls[1]) / int(cls[2]), "bsram": int(g("BSRAM")[1]),
            "dsp": int(dsp[1]) if dsp else 0, "fmax": float(fm[1]) if fm else 0.0}


def main():
    ap = argparse.ArgumentParser(description="PicoRV32 на GW1NR-9: CoreMark и ресурсы для сравнения с askoRV32")
    ap.add_argument("--config", choices=["min", "full", "both"], default="both")
    ap.add_argument("--iterations", type=int, default=1)
    ap.add_argument("--no-synth", action="store_true", help="не собирать проект Gowin")
    ap.add_argument("--no-coremark", action="store_true", help="не запускать CoreMark")
    a = ap.parse_args()
    cfgs = ["min", "full"] if a.config == "both" else [a.config]
    prefix = None if a.no_coremark else rt.find_riscv_prefix()
    gw_sh = None if a.no_synth else find_gw_sh()

    jobs = [(k, c) for c in cfgs for k in (["cm"] if not a.no_coremark else []) + (["syn"] if not a.no_synth else [])]
    print(f"PicoRV32: {', '.join(cfgs)}; {len(jobs)} задач(и). CoreMark моделируется несколько минут...")
    run = lambda j: coremark(j[1], prefix, a.iterations) if j[0] == "cm" else synth(j[1], gw_sh)
    with ThreadPoolExecutor(len(jobs)) as ex:
        res = dict(zip(jobs, ex.map(run, jobs)))

    ok = True
    print(f"\n{'Конфигурация':<14}{'LUT':>6}{'Рег':>6}{'CLS':>12}{'BSRAM':>6}{'DSP':>4}{'Fmax':>9}"
          f"{'CoreMark/МГц':>14}{'CoreMark на Fmax':>18}")
    for c in cfgs:
        s, m = res.get(("syn", c), {}), res.get(("cm", c), {})
        for r in (s, m):
            if "error" in r:
                ok = False
                print(f"{c}: ОШИБКА {r['error']}")
        if m and "error" not in m and not m["ok"]:
            ok = False
            print(f"{c}: CoreMark не прошёл проверку CRC, см. {OUT / c / 'console.txt'}")
        syn_ok, cm_ok = s and "error" not in s, m and "error" not in m
        print(f"{c:<14}"
              + (f"{s['logic']:>6}{s['reg']:>6}{s['cls']:>6} ({s['cls_pct']:.0f}%){s['bsram']:>6}{s['dsp']:>4}{s['fmax']:>5.1f} МГц"
                 if syn_ok else f"{'-':>47}")
              + (f"{m['cm_mhz']:>14.3f}" if cm_ok else f"{'-':>14}")
              + (f"{m['cm_mhz'] * s['fmax']:>18.1f}" if syn_ok and cm_ok else f"{'-':>18}"))
    print(f"\nФайлы: {OUT}")
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
