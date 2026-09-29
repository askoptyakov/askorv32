"""
Прогон тестов RV32I на ядре askoRV32 (Icarus Verilog, память BSRAM).

    py hw/sim/run_tests.py                     # все инструкции, оба ядра
    py hw/sim/run_tests.py add sub lw          # выбранные инструкции
    py hw/sim/run_tests.py --core pipeline     # только конвейерное ядро
    py hw/sim/run_tests.py sra --core single --vcd   # + временные диаграммы для GTKWave
    py hw/sim/run_tests.py --rf-garbage              # регистры при старте - мусор, как на плате
    py hw/sim/run_tests.py --gen               # сначала перегенерировать tests/rv32i/*.S

Инструменты ищутся в PATH, затем в стандартных папках установки (см. sdk/SETUP.md).
Пути можно задать переменными окружения RISCV_PREFIX (например
C:/.../bin/riscv-none-elf-) и GOWIN_PRIM_SIM (путь к prim_sim.v).
"""
import argparse
import glob
import os
import re
import shutil
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

sys.stdout.reconfigure(encoding="utf-8")

SIM_DIR = Path(__file__).resolve().parent
HW_DIR = SIM_DIR.parent
TESTS_DIR = SIM_DIR / "tests"
PROG_DIR = TESTS_DIR / "rv32i"
PRIV_DIR = TESTS_DIR / "priv"          # CSR, исключения, прерывания (пишутся вручную)
PRIV_ORDER = ["csr", "trap", "irq", "plic", "dbg"]
BUILD_DIR = SIM_DIR / "build"

RTL = [HW_DIR / "src" / f for f in ("top.sv", "core.sv", "mdu.sv", "mem.sv", "clock.sv", "periph/mux.sv", "periph/gpio.sv",
                                     "periph/tm1638.sv", "periph/simple_timer/tim.sv", "periph/clint.sv",
                                     "periph/plic.sv", "debug/dm.sv", "debug/dtm_gowin.sv",
                                     "debug/fpgacapzero/jtag_tap_gowin.v", "debug/fpgacapzero/dff_reg_sync.v",
                                     "debug/fpgacapzero/dff_sync.v")] + [SIM_DIR / "gw_jtag_model.sv"]
TB = SIM_DIR / "tb_core.sv"
MEM_BYTES = 8 * 1024
CORES = {"single": 1, "pipeline": 0}  # значение параметра CORE_TYPE


# ----------------------------------------------------------------------------------------
# Поиск инструментов
# ----------------------------------------------------------------------------------------
def find_riscv_prefix():
    env = os.environ.get("RISCV_PREFIX")
    if env:
        return env
    exe = shutil.which("riscv-none-elf-gcc")
    if exe:
        return exe[:-len("gcc.exe")] if exe.lower().endswith(".exe") else exe[:-len("gcc")]
    hits = sorted(glob.glob(r"C:\Program Files\Eclipse\riscv-toolchain\xpack-riscv-none-elf-gcc-*\bin\riscv-none-elf-gcc.exe")
                  + glob.glob(r"C:\xpack\**\bin\riscv-none-elf-gcc.exe", recursive=True))
    if hits:
        return hits[-1][:-len("gcc.exe")]
    sys.exit("Не найден riscv-none-elf-gcc: добавьте его в PATH или задайте RISCV_PREFIX")


def find_prim_sim():
    env = os.environ.get("GOWIN_PRIM_SIM")
    if env:
        return env
    hits = sorted(glob.glob(r"C:\Program Files\Gowin\*\IDE\simlib\gw1n\prim_sim.v")
                  + glob.glob(r"C:\Gowin\*\IDE\simlib\gw1n\prim_sim.v"))
    if hits:
        return hits[-1]
    sys.exit("Не найдена библиотека GOWIN prim_sim.v: задайте GOWIN_PRIM_SIM")


def need(tool):
    if not shutil.which(tool):
        sys.exit(f"Не найден {tool}: установите Icarus Verilog и добавьте C:\\iverilog\\bin в PATH")
    return tool


def run(cmd, **kw):
    return subprocess.run([str(c) for c in cmd], capture_output=True, text=True,
                          encoding="utf-8", errors="replace", **kw)


# ----------------------------------------------------------------------------------------
# Сборка тестовой программы: ELF -> образы памяти и имена тестов
# ----------------------------------------------------------------------------------------
def to_hex_words(data):
    data += b"\0" * (-len(data) % 4)
    return "".join(f"{int.from_bytes(data[i:i + 4], 'little'):08x}\n" for i in range(0, len(data), 4))


def parse_names(blob):
    """Записи секции .testnames: выравнивание на 4, .word номер, строка с нулём в конце."""
    names, pos = {}, 0
    while pos + 4 <= len(blob):
        pos += -pos % 4
        if pos + 4 > len(blob):
            break
        n = int.from_bytes(blob[pos:pos + 4], "little")
        end = blob.index(b"\0", pos + 4)
        names[n] = blob[pos + 4:end].decode("ascii", "replace")
        pos = end + 1
    return names


def build_program(name, prefix, imem_kb=8, text_base=0):
    out = BUILD_DIR / name
    out.mkdir(parents=True, exist_ok=True)
    elf = out / f"{name}.elf"
    src = PRIV_DIR / f"{name}.S" if name in PRIV_ORDER else PROG_DIR / f"{name}.S"
    r = run([prefix + "gcc", "-march=rv32im_zicsr", "-mabi=ilp32", "-nostdlib", "-nostartfiles",
             "-Wl,--no-relax", f"-Wl,--defsym=TEXT_BASE={text_base},--defsym=IMEM_LEN={imem_kb * 1024}",
             f"-I{TESTS_DIR}", "-T", TESTS_DIR / "link.ld",
             f"-I{PRIV_DIR}", "-o", elf, src])
    if r.returncode:
        return None, r.stderr.strip()
    for sect, fname in ((".text", "imem.bin"), (".data", "dmem.bin")):
        r = run([prefix + "objcopy", "-O", "binary", "-j", sect, elf, out / fname])
        if r.returncode:
            return None, r.stderr.strip()
    r = run([prefix + "objcopy", "--dump-section", f".testnames={out / 'names.bin'}", elf, out / "tmp.elf"])
    if r.returncode:
        return None, r.stderr.strip()
    imem, dmem = (out / "imem.bin").read_bytes(), (out / "dmem.bin").read_bytes()
    for label, blob, size in (("IMEM", imem, imem_kb * 1024), ("DMEM", dmem, MEM_BYTES)):
        if len(blob) > size:
            return None, f"{label}: {len(blob)} байт больше {size}"
    (out / "imem.hex").write_text(to_hex_words(imem))
    (out / "dmem.hex").write_text(to_hex_words(dmem))
    names = parse_names((out / "names.bin").read_bytes())
    #Программа для сценария отладки: адреса меток и параметры запуска
    extra = []
    if name == "dbg":
        sym = {l.split()[2]: l.split()[0] for l in run([prefix + "nm", elf]).stdout.splitlines() if len(l.split()) == 3}
        extra = ["+dbgtest", f"+dbg_bp={sym['bp_here']}", f"+dbg_flag={sym['flag']}",
                 f"+dbg_tdata={sym['tdata']}", "+timeout=3000000"]
    (out / "args.txt").write_text(" ".join(extra))
    (out / "names.txt").write_text("".join(f"{n} {s}\n" for n, s in sorted(names.items())))
    return {"dir": out, "imem": len(imem), "tests": len(names)}, None


# ----------------------------------------------------------------------------------------
# Моделирование
# ----------------------------------------------------------------------------------------
def compile_tb(core, prim_sim, imem_kb=8, dmem_kb=8):
    vvp = BUILD_DIR / f"tb_core_{core}_i{imem_kb}_d{dmem_kb}.vvp"
    r = run([need("iverilog"), "-g2012", "-o", vvp, "-s", "tb_core", f"-I{SIM_DIR}",
             f"-Ptb_core.CORE_TYPE={CORES[core]}", f"-Ptb_core.IMEM_KB={imem_kb}",
             f"-Ptb_core.DMEM_KB={dmem_kb}", *[f"-DTB_{m}_{kb}K" for m, kb in (("IMEM", imem_kb), ("DMEM", dmem_kb)) if kb > 8],
             TB, *RTL, prim_sim])
    errors = [l for l in r.stderr.splitlines() if "constant selects in always_" not in l
              and "Not enough words" not in l and "must be automatic" not in l]
    if r.returncode:
        sys.exit(f"Ошибка компиляции тестбенча ({core}):\n" + "\n".join(errors))
    return vvp


def simulate(vvp, name, core, vcd, rf_garbage=False):
    d = BUILD_DIR / name
    args = [need("vvp"), "-n", vvp, f"+prog={name}", f"+imem={(d / 'imem.hex').as_posix()}",
            f"+dmem={(d / 'dmem.hex').as_posix()}", f"+names={(d / 'names.txt').as_posix()}"]
    args += (d / "args.txt").read_text().split()
    if rf_garbage:
        args.append("+rf_garbage")
    if vcd:
        args.append(f"+vcd={(BUILD_DIR / f'{name}_{core}.vcd').as_posix()}")
    r = run(args, timeout=600)
    line = next((l for l in r.stdout.splitlines() if l.startswith("RESULT ")), None)
    if line is None:
        return {"status": "ERROR", "text": (r.stdout + r.stderr).strip()[-500:]}
    fields = line.split()
    info = dict(f.split("=", 1) for f in fields[4:] if "=" in f)
    return {"status": fields[1], "info": info, "text": line}


# ----------------------------------------------------------------------------------------
def main():
    ap = argparse.ArgumentParser(description="Тесты RV32I для ядра askoRV32 (Icarus Verilog)")
    ap.add_argument("tests", nargs="*", help="инструкции (по умолчанию - все из tests/rv32i)")
    ap.add_argument("--core", choices=["single", "pipeline", "both"], default="both")
    ap.add_argument("--vcd", action="store_true", help="сохранить .vcd в hw/sim/build")
    ap.add_argument("--rf-garbage", action="store_true",
                    help="регистры x1..x31 при старте - мусор, как на плате (по умолчанию нули)")
    ap.add_argument("--gen", action="store_true", help="перегенерировать tests/rv32i/*.S")
    ap.add_argument("--imem-kb", type=int, choices=[8, 16, 32], default=8,
                    help="размер памяти инструкций BSRAM (как BSRAM_IMEM_SIZE в top.sv)")
    ap.add_argument("--text-base", type=lambda x: int(x, 0), default=0,
                    help="адрес начала кода тестов, например 0x1f00 - код пересекает границу кластеров BSRAM")
    ap.add_argument("-j", "--jobs", type=int, default=os.cpu_count() or 4)
    a = ap.parse_args()

    if a.gen:
        subprocess.run([sys.executable, TESTS_DIR / "gen_rv32i.py"], check=True)

    sys.path.insert(0, str(TESTS_DIR))
    from gen_rv32i import ORDER
    available = [t for t in ORDER if (PROG_DIR / f"{t}.S").exists()] +                 [t for t in PRIV_ORDER if (PRIV_DIR / f"{t}.S").exists()]
    names = a.tests or available
    unknown = [t for t in names if t not in available]
    if unknown:
        sys.exit(f"Нет тестов для: {', '.join(unknown)}. Доступны: {', '.join(available)}")
    cores = ["single", "pipeline"] if a.core == "both" else [a.core]

    prefix, prim_sim = find_riscv_prefix(), find_prim_sim()
    BUILD_DIR.mkdir(exist_ok=True)

    # 1. Сборка программ
    progs = {}
    with ThreadPoolExecutor(a.jobs) as ex:
        for name, (info, err) in zip(names, ex.map(lambda n: build_program(n, prefix, a.imem_kb, a.text_base), names)):
            if err:
                sys.exit(f"Ошибка сборки {name}.S:\n{err}")
            progs[name] = info

    # 2. Компиляция тестбенча и прогон
    vvps = {c: compile_tb(c, prim_sim, a.imem_kb) for c in cores}
    jobs = [(n, c) for n in names for c in cores]
    with ThreadPoolExecutor(a.jobs) as ex:
        results = dict(zip(jobs, ex.map(lambda j: simulate(vvps[j[1]], j[0], j[1], a.vcd, a.rf_garbage), jobs)))

    # 3. Отчёт
    print(f"\nТесты RV32I, память BSRAM (IMEM {a.imem_kb} кБайт, код с 0x{a.text_base:x}). Ядра: {', '.join(cores)}\n")
    head = f"{'Инструкция':<11}{'Тестов':>7}  " + "".join(f"{c:<22}" for c in cores)
    print(head)
    print("-" * len(head))
    failed = []
    for n in names:
        row = f"{n:<11}{progs[n]['tests']:>7}  "
        for c in cores:
            r = results[(n, c)]
            if r["status"] == "PASS":
                cell = f"PASS ({r['info'].get('cycles', '?')} такт.)"
            else:
                cell = r["status"]
                failed.append((n, c, r))
            row += f"{cell:<22}"
        print(row)

    total = len(jobs)
    print(f"\nИтого: {total - len(failed)} из {total} прогонов успешно "
          f"({sum(p['tests'] for p in progs.values())} тестов в {len(names)} программах).")
    if failed:
        print("\nНе пройдено:")
        for n, c, r in failed:
            i = r.get("info", {})
            if r["status"] in ("FAIL", "TIMEOUT"):
                print(f"  {n:<6} [{c}] тест {i.get('test', '?')}: {i.get('name', '?')}"
                      + (f"  получено {i['got']}, ожидалось {i['expected']}" if "got" in i else "")
                      + (f"  PC={i['pc']}" if "pc" in i else ""))
                folder = "priv" if n in PRIV_ORDER else "rv32i"
                print(f"         см. hw/sim/tests/{folder}/{n}.S, строка с TEST_...({i.get('test', '?')}, ...")
            else:
                print(f"  {n:<6} [{c}] {r['text']}")
    if a.vcd:
        print(f"\nВременные диаграммы: {BUILD_DIR}\\<инструкция>_<ядро>.vcd (открыть в GTKWave)")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
