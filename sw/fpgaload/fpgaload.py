"""
Загрузка ПЛИС с программой через openFPGALoader (драйвер WinUSB), для конфигураций Eclipse
fw/riscv FPGA SRAM.launch и fw/riscv FPGA Flash.launch (SETUP.md п. 8.5, hw/info/debug.md).

1. Если запущен OpenOCD (идёт отладка), программатор занят: сообщение и выход без обращения к плате.
   Одновременный доступ сбивает USB-соединение OpenOCD (LIBUSB_ERROR_IO) и загрузку.
2. mergetool вливает программу fw/Debug/riscv.bin в последний битстрим Gowin hw/impl/pnr/riscv.fs
   (сборка Eclipse запускает mergetool только при изменении riscv.elf) -> fw/Debug/riscv.fs.
3. openFPGALoader -b tangnano9k [-f] fw/Debug/riscv.fs; полоса прогресса - через conprogress.

Запуск:  py -u sw/fpgaload/fpgaload.py sram|flash [--oss C:/oss-cad-suite]
"""
import argparse
import os
import subprocess
import sys
from pathlib import Path

sys.stdout.reconfigure(encoding="utf-8")    #Вывод в UTF-8: консоль Eclipse настроена на UTF-8
sys.stderr.reconfigure(encoding="utf-8")

ROOT = Path(__file__).resolve().parents[2]
sys.dont_write_bytecode = True              #Без __pycache__ в sw/conprogress
sys.path.insert(0, str(ROOT / "sw" / "conprogress"))
import conprogress                          # noqa: E402

BUSY = ["openocd.exe"]                      #Программы, которые держат программатор


def running(image):
    """Запущен ли процесс с таким именем (tasklist Windows)."""
    res = subprocess.run(["tasklist", "/FI", f"IMAGENAME eq {image}", "/NH"],
                         capture_output=True, text=True, encoding="cp866", errors="replace")
    return image.lower() in res.stdout.lower()


def find_oss(arg):
    for cand in [arg, os.environ.get("OSS_CAD_SUITE"), "C:/oss-cad-suite"]:
        if cand and (Path(cand) / "bin" / "openFPGALoader.exe").is_file():
            return Path(cand)
    return None


def main():
    ap = argparse.ArgumentParser(description="Загрузка ПЛИС с программой через openFPGALoader")
    ap.add_argument("target", choices=["sram", "flash"], help="sram - до выключения питания, flash - встроенная flash")
    ap.add_argument("--oss", help="каталог OSS CAD Suite (по умолчанию OSS_CAD_SUITE или C:/oss-cad-suite)")
    a = ap.parse_args()

    #1 Программатор занят отладкой
    busy = [p for p in BUSY if running(p)]
    if busy:
        print(f"Программатор занят: запущен {', '.join(busy)} (идёт отладка).\n"
              "Остановите отладку в Eclipse (Terminate) и запустите загрузку ещё раз.", file=sys.stderr)
        return 1

    oss = find_oss(a.oss)
    if not oss:
        print("Не найден openFPGALoader: OSS CAD Suite в C:/oss-cad-suite или переменная OSS_CAD_SUITE "
              "(SETUP.md п. 10)", file=sys.stderr)
        return 1

    #2 Программа в свежий битстрим
    debug = ROOT / "fw" / "Debug"
    pnr = ROOT / "hw" / "impl" / "pnr"
    sys.stdout.flush()
    rc = subprocess.run([str(ROOT / "sw" / "mergetool" / "mergetool.exe"), "riscv.bin",
                         str(pnr / "riscv.posp"), str(pnr / "riscv.fs"), "riscv.fs"], cwd=debug).returncode
    if rc:
        print(f"mergetool завершился с ошибкой ({rc}), ПЛИС не загружалась", file=sys.stderr)
        return rc

    #3 Загрузка
    env = dict(os.environ)
    env["PATH"] = os.pathsep.join([str(oss / "bin"), str(oss / "lib"), env.get("PATH", "")])
    cmd = [str(oss / "bin" / "openFPGALoader.exe"), "-b", "tangnano9k"] + (["-f"] if a.target == "flash" else []) + ["riscv.fs"]
    proc = subprocess.Popen(cmd, cwd=debug, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    conprogress.filter_stream(proc.stdout, sys.stdout.buffer)
    return proc.wait()


if __name__ == "__main__":
    sys.exit(main())
