"""
Загрузка ПЛИС и программы через openFPGALoader (драйвер WinUSB) - три способа хранения, для конфигураций
Eclipse fw/riscv FPGA SRAM.launch, fw/riscv FPGA Flash.launch и fw/riscv SPI-FLASH.launch (SETUP.md п. 8.5,
hw/info/debug.md, hw/src/periph/spiflash/README.md):

  sram      конфигурация и программа - в SRAM ПЛИС, до выключения питания. Программа вливается в
            битовый поток (BSRAM). Работает при любых выводах MODE.
  flash     конфигурация и программа - во встроенной flash ПЛИС (режим AUTO BOOT: MODE1 = MODE0 = 0,
            как на заводской Tang Nano 9K). Программа вливается в битовый поток.
  spiflash  конфигурация и программа - во внешней SPI-флеш (режим MSPI: MODE1 = 1, на Tang Nano 9K -
            подтяжка вывода 87 к 1.8 В). Битовый поток Gowin - с адреса 0x000000, программа - образом для
            загрузчика контроллера SPIFLASH (sw/bootimage) с адреса из конфигуратора (0x100000), затем
            перезапуск ПЛИС из внешней флеш (-r). Битовый поток пропускается, если не менялся с прошлой
            записи (хеш в fw/Debug/riscv_extflash_cfg.sha256; --force - писать всё равно).

Очистка (окно «Программатор ПЛИС» в Eclipse):

  erase-flash     стереть встроенную flash ПЛИС. При AUTO BOOT ПЛИС после этого пуста до следующей
                  загрузки; при MSPI (MODE1 = 1) ПЛИС перезапускается из внешней флеш - как обычно.
  erase-spiflash  стереть всю внешнюю SPI-флеш (4 МБайт): битовый поток, образ программы и данные
                  программы (рабочие параметры). При MSPI ПЛИС после этого пуста до записи spiflash.

Какой режим собран, решает конфигуратор: блок SPIFLASH с "fpgaConfig": true - ПЛИС для внешней флеш
(загрузчик программы включён), иначе - для SRAM и встроенной flash (программа в битовом потоке).

Порядок:
1. Если запущен OpenOCD (идёт отладка), программатор занят: сообщение и выход без обращения к плате.
   Одновременный доступ сбивает USB-соединение OpenOCD (LIBUSB_ERROR_IO) и загрузку.
2. sram, flash: mergetool вливает программу fw/Debug/riscv.bin в последний битстрим Gowin
   hw/impl/pnr/riscv.fs -> fw/Debug/riscv.fs; spiflash: образ программы fw/Debug/riscv_flash.bin.
3. openFPGALoader -b tangnano9k ...; полоса прогресса - через conprogress.

openFPGALoader - исправленный из sdk/openfpgaloader/bin (запись внешней флеш GW1N в ~3.5 раза быстрее,
sdk/openfpgaloader/README.md), если его нет - из OSS CAD Suite.

Запуск:  py -u sw/fpgaload/fpgaload.py sram|flash|spiflash|erase-flash|erase-spiflash [--elf <программа>] [--force]
                                         [--oss C:/oss-cad-suite]
"""
import argparse
import hashlib
import json
import os
import subprocess
import sys
from pathlib import Path

sys.stdout.reconfigure(encoding="utf-8")    #Вывод в UTF-8: консоль Eclipse настроена на UTF-8
sys.stderr.reconfigure(encoding="utf-8")

ROOT = Path(__file__).resolve().parents[2]
sys.dont_write_bytecode = True              #Без __pycache__ в sw/conprogress
sys.path.insert(0, str(ROOT / "sw" / "conprogress"))
sys.path.insert(0, str(ROOT / "sw" / "bootimage"))
import conprogress                          # noqa: E402
import bootimage                            # noqa: E402

BUSY = ["openocd.exe"]                      #Программы, которые держат программатор
DEBUG = ROOT / "fw" / "Debug"
PNR = ROOT / "hw" / "impl" / "pnr"


def running(image):
    """Запущен ли процесс с таким именем (tasklist Windows)."""
    res = subprocess.run(["tasklist", "/FI", f"IMAGENAME eq {image}", "/NH"],
                         capture_output=True, text=True, encoding="cp866", errors="replace")
    return image.lower() in res.stdout.lower()


def find_loader(oss_arg):
    """openFPGALoader и каталоги для PATH: исправленный из sdk/openfpgaloader/bin, иначе из OSS CAD Suite."""
    own = ROOT / "sdk" / "openfpgaloader" / "bin"
    if (own / "openFPGALoader.exe").is_file() and not oss_arg:
        return own / "openFPGALoader.exe", [own]
    for cand in [oss_arg, os.environ.get("OSS_CAD_SUITE"), "C:/oss-cad-suite"]:
        if cand and (Path(cand) / "bin" / "openFPGALoader.exe").is_file():
            return Path(cand) / "bin" / "openFPGALoader.exe", [Path(cand) / "bin", Path(cand) / "lib"]
    return None, []


def gwsoc():
    """Из fw/riscv.gwsoc: внешняя флеш хранит конфигурацию (fpgaConfig), адрес образа, размеры IMEM/DMEM."""
    m = json.loads((ROOT / "fw" / "riscv.gwsoc").read_text(encoding="utf-8"))
    cfg = [p for p in m.get("periph", []) if p.get("type") == "spiflash" and p.get("fpgaConfig", False)]
    core = m.get("core", {})
    mem = {}
    for region, key in ((0x00, "imem"), (0x10, "dmem")):
        c = core.get(key) or {}
        mem[region] = int(c.get("kb", 8)) * 1024 if c.get("type", "bsram") == "bsram" else int(c.get("synthWords", 256)) * 4
    addr = int(str(cfg[0].get("bootAddr", "0x100000")).replace("_", ""), 16) if cfg else None
    return bool(cfg), addr, mem


class Loader:
    def __init__(self, exe, path):
        self.exe, self.path = exe, path

    def run(self, args, cwd=DEBUG):
        env = dict(os.environ)
        env["PATH"] = os.pathsep.join([str(p) for p in self.path] + [env.get("PATH", "")])
        cmd = [str(self.exe), "-b", "tangnano9k"] + args
        sys.stdout.flush()
        proc = subprocess.Popen(cmd, cwd=cwd, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        conprogress.filter_stream(proc.stdout, sys.stdout.buffer)
        return proc.wait()


def flat_bin(elf):
    """Программа для mergetool из ELF: память по адресам загрузки (LMA) с 0 - как riscv.bin сборки Eclipse."""
    segs = bootimage.segments_from_elf(elf, lma=True)
    end = max(a + len(b) for a, b in segs)
    img = bytearray(end)
    for a, b in segs:
        img[a:a + len(b)] = b
    out = Path(elf).with_suffix(".bin")
    out.write_bytes(bytes(img))
    return out


def bitstream_mode(ld, target, elf, cfg):
    """sram/flash: программа в битовом потоке."""
    if target == "flash" and cfg:
        print("В конфигураторе выбрано хранение во внешней SPI-флеш (SPIFLASH: «Конфигурация и программа - во "
              "внешней флеш»): битовый поток собран для режима MSPI. Запись во встроенную flash не нужна - "
              "используйте spiflash (Eclipse: riscv SPI-FLASH) или смените режим в конфигураторе и пересоберите ПЛИС.",
              file=sys.stderr)
        return 1
    if cfg:
        print("Примечание: ПЛИС собрана для внешней флеш - после сброса загрузчик возьмёт программу из образа "
              "во внешней флеш, если он там есть")
    prog = flat_bin(elf) if elf else DEBUG / "riscv.bin"
    sys.stdout.flush()
    rc = subprocess.run([str(ROOT / "sw" / "mergetool" / "mergetool.exe"), str(prog),
                         str(PNR / "riscv.posp"), str(PNR / "riscv.fs"), str(DEBUG / "riscv.fs")], cwd=DEBUG).returncode
    if rc:
        print(f"mergetool завершился с ошибкой ({rc}), ПЛИС не загружалась", file=sys.stderr)
        return rc
    return ld.run((["-f"] if target == "flash" else []) + [str(DEBUG / "riscv.fs")])


def spiflash_mode(ld, elf, force, cfg, addr, mem):
    """spiflash: битовый поток (если изменился) и образ программы во внешнюю флеш, затем перезапуск ПЛИС."""
    if not cfg:
        print("В конфигураторе не выбрано хранение во внешней SPI-флеш: битовый поток собран без загрузчика "
              "программы. Включите в блоке SPIFLASH «Конфигурация и программа - во внешней флеш (MSPI)», "
              "пересоберите ПЛИС - или используйте sram/flash.", file=sys.stderr)
        return 1
    elf = Path(elf).resolve() if elf else DEBUG / "riscv.elf"
    try:
        segs = bootimage.segments_from_elf(elf)
        img = bootimage.build(segs, mem)
    except (bootimage.ImageError, OSError) as e:
        print("Образ программы: " + str(e), file=sys.stderr)
        return 1
    fs = PNR / "riscv.fs"
    stamp = DEBUG / "riscv_extflash_cfg.sha256"
    digest = hashlib.sha256(fs.read_bytes()).hexdigest()
    if not force and stamp.exists() and stamp.read_text().strip() == digest:
        print("Конфигурация ПЛИС во внешней флеш не менялась - пропуск (записать заново: --force)")
    else:
        print("Конфигурация ПЛИС hw/impl/pnr/riscv.fs -> внешняя флеш с адреса 0x000000 (около 3 мин)")
        stamp.unlink(missing_ok=True)
        rc = ld.run(["--external-flash", "-o", "0", str(fs)])
        if rc:
            return rc
        stamp.write_text(digest + "\n")
    out = elf.with_name(elf.stem + "_flash.bin")
    out.write_bytes(img)
    print(f"Образ {out.name}: {len(img)} Байт ({bootimage.describe(segs)}) -> внешняя флеш с адреса 0x{addr:06X}")
    rc = ld.run(["--external-flash", "-o", str(addr), str(out)])
    if rc:
        return rc
    #Запись внешней флеш стирает конфигурацию ПЛИС: перезапуск - из внешней флеш (MSPI), загрузчик возьмёт программу
    print("Перезапуск ПЛИС из внешней флеш (MSPI)")
    return ld.run(["-r"])


def erase_mode(ld, target, cfg):
    """erase-flash / erase-spiflash: стирание встроенной flash или всей внешней флеш (--bulk-erase)."""
    if target == "erase-flash":
        print("Стирание встроенной flash ПЛИС")
        rc = ld.run(["--bulk-erase"])
        if not rc and cfg:
            print("ПЛИС собрана для внешней флеш (MSPI): после перезапуска она снова загружается из внешней флеш")
        return rc
    print("Стирание всей внешней SPI-флеш: битовый поток, образ программы, данные программы")
    (DEBUG / "riscv_extflash_cfg.sha256").unlink(missing_ok=True)   #Следующая запись spiflash пишет и битовый поток
    rc = ld.run(["--external-flash", "--bulk-erase"])
    if not rc and cfg:
        print("Внешняя флеш пуста: при MSPI ПЛИС не загрузится, пока не записать spiflash")
    return rc


def main():
    ap = argparse.ArgumentParser(description="Загрузка ПЛИС и программы через openFPGALoader")
    ap.add_argument("target", choices=["sram", "flash", "spiflash", "erase-flash", "erase-spiflash"],
                    help="sram - SRAM ПЛИС (до выключения питания), flash - встроенная flash (AUTO BOOT), "
                         "spiflash - внешняя SPI-флеш (MSPI); erase-flash, erase-spiflash - стереть встроенную "
                         "flash или всю внешнюю флеш")
    ap.add_argument("--elf", help="программа (по умолчанию fw/Debug/riscv.elf и riscv.bin сборки Eclipse)")
    ap.add_argument("--force", action="store_true", help="spiflash: писать битовый поток, даже если он не менялся")
    ap.add_argument("--oss", help="openFPGALoader из OSS CAD Suite в этом каталоге (вместо sdk/openfpgaloader/bin)")
    a = ap.parse_args()

    #1 Программатор занят отладкой
    busy = [p for p in BUSY if running(p)]
    if busy:
        print(f"Программатор занят: запущен {', '.join(busy)} (идёт отладка).\n"
              "Остановите отладку в Eclipse (Terminate) и запустите загрузку ещё раз.", file=sys.stderr)
        return 1

    exe, path = find_loader(a.oss)
    if not exe:
        print("Не найден openFPGALoader: sdk/openfpgaloader/bin или OSS CAD Suite (C:/oss-cad-suite, OSS_CAD_SUITE; "
              "SETUP.md п. 10)", file=sys.stderr)
        return 1
    ld = Loader(exe, path)
    cfg, addr, mem = gwsoc()
    if a.target.startswith("erase-"):
        return erase_mode(ld, a.target, cfg)
    if a.target == "spiflash":
        return spiflash_mode(ld, a.elf, a.force, cfg, addr, mem)
    return bitstream_mode(ld, a.target, a.elf, cfg)


if __name__ == "__main__":
    sys.exit(main())
