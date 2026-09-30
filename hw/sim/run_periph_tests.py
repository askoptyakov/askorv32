"""
Тесты периферии askoRV32: каждое устройство - отдельно от ядра, через шину регистров.

Устройство лежит в своей папке hw/src/periph/<устройство>/ вместе с тестом tb_<имя>.sv и описанием
README.md. Тест собирается из всех .sv-файлов папки устройства, шаблона hw/src/periph/periph_regs.sv
и общей части hw/src/periph/periph_tb.svh (ведущий шины, проверки) и печатает одну строку
"RESULT PASS|FAIL <устройство> ...".

Запуск:
    py hw/sim/run_periph_tests.py            # все устройства
    py hw/sim/run_periph_tests.py stim gpio  # выбранные
    py hw/sim/run_periph_tests.py --vcd stim # с временными диаграммами (hw/sim/build/periph_<имя>.vcd)

Тесты ядра - отдельно: py hw/sim/run_tests.py (процессор cpu.sv без периферии платы).
"""
import argparse
import subprocess
import sys
from pathlib import Path

from run_tests import need   # поиск iverilog/vvp - общий с тестами ядра

SIM_DIR = Path(__file__).resolve().parent
HW_DIR = SIM_DIR.parent
PERIPH_DIR = HW_DIR / "src" / "periph"
BUILD_DIR = SIM_DIR / "build"
COMMON = [PERIPH_DIR / "periph_regs.sv"]


def devices():
    """Папки устройств, в которых есть тест tb_*.sv."""
    return {d.name: d for d in sorted(PERIPH_DIR.iterdir()) if d.is_dir() and list(d.glob("tb_*.sv"))}


def run_device(name, d, vcd):
    tbs = sorted(d.glob("tb_*.sv"))
    srcs = [f for f in sorted(d.glob("*.sv")) if not f.name.startswith("tb_")]
    BUILD_DIR.mkdir(exist_ok=True)
    results = []
    for tb in tbs:
        top = tb.stem
        vvp = BUILD_DIR / f"periph_{top}.vvp"
        r = subprocess.run([need("iverilog"), "-g2012", "-o", str(vvp), "-s", top, f"-I{PERIPH_DIR}",
                            str(tb), *map(str, srcs), *map(str, COMMON)],
                           capture_output=True, text=True, encoding="utf-8", errors="replace")
        errors = [l for l in r.stderr.splitlines() if "constant selects in always_" not in l]
        if r.returncode:
            results.append((top, "ERROR", "\n".join(errors[-15:])))
            continue
        args = [need("vvp"), "-n", str(vvp)]
        if vcd:
            args.append(f"+vcd={(BUILD_DIR / f'periph_{top}.vcd').as_posix()}")
        r = subprocess.run(args, capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=600)
        fails = [l for l in r.stdout.splitlines() if l.startswith("FAIL ")]
        line = next((l for l in r.stdout.splitlines() if l.startswith("RESULT ")), None)
        if line is None:
            results.append((top, "ERROR", (r.stdout + r.stderr).strip()[-500:]))
        else:
            results.append((top, line.split()[1], "\n".join(fails + [line])))
    return results


def main():
    ap = argparse.ArgumentParser(description="Тесты периферии askoRV32")
    ap.add_argument("devices", nargs="*", help="устройства (папки hw/src/periph/<имя>); по умолчанию - все")
    ap.add_argument("--vcd", action="store_true", help="сохранить .vcd в hw/sim/build")
    a = ap.parse_args()
    try:
        sys.stdout.reconfigure(encoding="utf-8")
    except Exception:
        pass

    all_dev = devices()
    names = a.devices or list(all_dev)
    unknown = [n for n in names if n not in all_dev]
    if unknown:
        sys.exit(f"Нет теста для устройств: {', '.join(unknown)} (есть: {', '.join(all_dev)})")

    ok = total = 0
    failed = []
    print(f"{'Тест':<16}{'Результат':<10}Подробности")
    print("-" * 64)
    for n in names:
        for top, status, text in run_device(n, all_dev[n], a.vcd):
            total += 1
            last = text.splitlines()[-1] if text else ""
            info = " ".join(f for f in last.split()[3:]) if status in ("PASS", "FAIL") else ""
            print(f"{top:<16}{status:<10}{info}")
            if status == "PASS":
                ok += 1
            else:
                failed.append((top, text))
    print(f"\nИтого: {ok} из {total} тестов периферии успешно.")
    for top, text in failed:
        print(f"\n{top}:\n{text}")
    return 0 if ok == total else 1


if __name__ == "__main__":
    sys.exit(main())
