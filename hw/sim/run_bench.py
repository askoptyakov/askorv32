"""
CoreMark (EEMBC) на ядре askoRV32: моделирование в Icarus Verilog с памятью BSRAM.

    py hw/sim/run_bench.py                         # оба ядра, 1 итерация, -O2
    py hw/sim/run_bench.py --iterations 3 --opt -O3
    py hw/sim/run_bench.py --core pipeline

Такты считает CSR mcycle ядра. Однотактное ядро выполняет
одну инструкцию за такт ядра, поэтому число его тактов равно числу выполненных
инструкций, а CPI конвейерного ядра = такты конвейера / такты однотактного ядра.

Результат неофициальный: правила EEMBC требуют не менее 10 с измеряемого времени,
в моделировании это недостижимо. Корректность проверяется полностью - по CRC.
"""
import argparse
import re
import sys
import time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import run_tests as rt  # noqa: E402  (поиск инструментов, компиляция тестбенча)

CM_DIR = rt.SIM_DIR / "bench" / "coremark"
EEMBC = ["core_list_join.c", "core_main.c", "core_matrix.c", "core_state.c", "core_util.c"]
PORT = ["crt0.S", "core_portme.c", "ee_printf.c"]
IMEM_KB = 32
# Частота ядра на плате: clk 27 МГц -> clk_div2; однотактному ядру с BSRAM нужно 3 такта clk_div2
CORE_MHZ = {"single": 27 / 2 / 3, "pipeline": 27 / 2}


def check_eembc_md5():
    """Официальные файлы не должны меняться (правила CoreMark). Сравнение без учёта CRLF."""
    import hashlib
    bad = []
    for line in (CM_DIR / "eembc" / "coremark.md5").read_text().split("\n"):
        if not line.strip():
            continue
        md5, name = line.split()
        data = (CM_DIR / "eembc" / name).read_bytes().replace(b"\r\n", b"\n")
        if hashlib.md5(data).hexdigest() != md5:
            bad.append(name)
    # coremark.h: в репозитории EEMBC после обновления md5 исправлена опечатка в комментарии
    # (коммит 4ee6eca, 2023-10-06), код не изменился
    return [b for b in bad if b != "coremark.h"]


def build(prefix, opt, iterations):
    out = rt.BUILD_DIR / "coremark"
    out.mkdir(parents=True, exist_ok=True)
    flags = f"{opt} -march=rv32i_zicsr -mabi=ilp32"
    elf = out / "coremark.elf"
    r = rt.run([prefix + "gcc", *flags.split(), f"-I{CM_DIR / 'askorv32'}", f"-I{CM_DIR / 'eembc'}",
                f"-DITERATIONS={iterations}", "-DPERFORMANCE_RUN=1", f'-DFLAGS_STR="{flags}"',
                "-nostartfiles", "-T", CM_DIR / "askorv32" / "link.ld", "-o", elf,
                *[CM_DIR / "askorv32" / f for f in PORT], *[CM_DIR / "eembc" / f for f in EEMBC]])
    if r.returncode:
        sys.exit("Ошибка сборки CoreMark:\n" + r.stderr)
    for sect, name in ((".text", "imem"), (".data", "dmem")):
        rt.run([prefix + "objcopy", "-O", "binary", "-j", sect, elf, out / f"{name}.bin"])
        (out / f"{name}.hex").write_text(rt.to_hex_words((out / f"{name}.bin").read_bytes()))
    size = rt.run([prefix + "size", elf]).stdout.split("\n")[1].split()
    return out, flags, {"text": int(size[0]), "data": int(size[1]), "bss": int(size[2])}


def simulate(vvp, out, core, timeout):
    t0 = time.time()
    r = rt.run([rt.need("vvp"), "-n", vvp, "+prog=coremark", f"+imem={(out / 'imem.hex').as_posix()}",
                f"+dmem={(out / 'dmem.hex').as_posix()}", f"+timeout={timeout}"], timeout=24 * 3600)
    console = "\n".join(l for l in r.stdout.splitlines()
                        if not l.startswith(("RESULT", "WARNING")) and "$finish" not in l)
    (out / f"console_{core}.txt").write_text(console, encoding="utf-8")
    result = next((l for l in r.stdout.splitlines() if l.startswith("RESULT")), "RESULT ERROR")
    get = lambda key: (re.search(rf"^{key}\s*:\s*(\S+)", console, re.M) or [None, None])[1]
    return {
        "status": result.split()[1],
        "ticks": int(get("Total ticks") or 0),
        "iterations": int(get("Iterations") or 0),
        "seedcrc": get("seedcrc"),
        "crc_errors": re.findall(r"ERROR! (?:list|matrix|state) crc.*", console),
        "sim_s": time.time() - t0,
        "console": console,
    }


def main():
    ap = argparse.ArgumentParser(description="CoreMark на ядре askoRV32 (Icarus Verilog)")
    ap.add_argument("--core", choices=["single", "pipeline", "both"], default="both")
    ap.add_argument("--iterations", type=int, default=1)
    ap.add_argument("--opt", default="-O2", help="оптимизация GCC: -O2 (по умолчанию), -O3, -Os")
    a = ap.parse_args()
    cores = ["single", "pipeline"] if a.core == "both" else [a.core]

    bad = check_eembc_md5()
    if bad:
        sys.exit(f"Изменены официальные файлы CoreMark: {', '.join(bad)}")
    prefix, prim_sim = rt.find_riscv_prefix(), rt.find_prim_sim()
    rt.BUILD_DIR.mkdir(exist_ok=True)
    out, flags, size = build(prefix, a.opt, a.iterations)
    print(f"CoreMark: {flags}, ITERATIONS={a.iterations}; .text {size['text']} Б, "
          f".data {size['data']} Б, .bss {size['bss']} Б. Моделирование идёт долго (~10 тыс. тактов/с)...")
    vvps = {c: rt.compile_tb(c, prim_sim, IMEM_KB) for c in cores}
    timeout = 2_000_000 + 2_500_000 * a.iterations
    with ThreadPoolExecutor(len(cores)) as ex:
        res = dict(zip(cores, ex.map(lambda c: simulate(vvps[c], out, c, timeout), cores)))

    print(f"\n{'Ядро':<14}{'Такты':>12}{'CoreMark/МГц':>14}{'CPI':>7}{'F ядра':>10}{'CoreMark':>10}  Проверка CRC")
    ok = True
    for c in cores:
        r = res[c]
        valid = r["status"] == "PASS" and r["seedcrc"] == "0xe9f5" and not r["crc_errors"] and r["ticks"] > 0
        ok &= valid
        cm_mhz = r["iterations"] * 1e6 / r["ticks"] if r["ticks"] else 0
        cpi = r["ticks"] / res["single"]["ticks"] if "single" in res and res["single"]["ticks"] else None
        print(f"{c:<14}{r['ticks']:>12}{cm_mhz:>14.4f}{(f'{cpi:.3f}' if cpi else '-'):>7}"
              f"{CORE_MHZ[c]:>7.2f} МГц{cm_mhz * CORE_MHZ[c]:>10.2f}  "
              + ("OK" if valid else f"ОШИБКА ({r['status']}, seedcrc={r['seedcrc']}, {r['crc_errors']})")
              + f"   [моделирование {r['sim_s']:.0f} с]")
    print(f"\nВывод CoreMark: {out}\\console_<ядро>.txt")
    print("Результат неофициальный: измеряемое время меньше 10 с, требуемых правилами EEMBC.")
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
