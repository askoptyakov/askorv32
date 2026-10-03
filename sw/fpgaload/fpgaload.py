"""
Загрузка ПЛИС и программы через openFPGALoader (драйвер WinUSB) - три способа хранения, для конфигураций
Eclipse fw/riscv FPGA SRAM.launch, fw/riscv FPGA Flash.launch и fw/riscv SPI-FLASH.launch (SETUP.md п. 8.5,
hw/info/debug.md, hw/src/periph/spiflash/README.md):

  sram      конфигурация и программа - в SRAM ПЛИС, до выключения питания. Работает при любых выводах MODE.
            Программа вливается в битовый поток (BSRAM) утилитой mergetool, если она знает раскладку битового
            потока кристалла ("mergetool" в devices.js); иначе - битовый поток в SRAM, затем программа в память
            через отладчик (OpenOCD: reset halt, запись IMEM/DMEM, запуск с адреса 0).
  flash     конфигурация и программа - во встроенную flash ПЛИС (режим AUTO BOOT: MODE1 = MODE0 = 0, как на
            заводской Tang Nano 9K). Программа вливается в битовый поток. У GW2A-18 встроенной flash нет.
  spiflash  конфигурация и программа - во внешнюю SPI-флеш (режим MSPI: на Tang Nano 9K - MODE1 = 1, подтяжка
            вывода 87 к 1.8 В; Tang Primer 20K загружается так всегда). Битовый поток Gowin - с адреса 0x000000,
            программа - образом для загрузчика контроллера SPIFLASH (sw/bootimage) с адреса из конфигуратора
            (0x100000), затем перезапуск ПЛИС из внешней флеш (-r). Битовый поток пропускается, если не менялся с
            прошлой записи (хеш в <каталог сборки>/riscv_extflash_cfg.sha256; --force - писать всё равно).

Очистка (окно «Программатор ПЛИС» в Eclipse):

  erase-flash     стереть встроенную flash ПЛИС (только у ПЛИС со встроенной flash). При AUTO BOOT ПЛИС после
                  этого пуста до следующей загрузки; при MSPI (MODE1 = 1) ПЛИС перезапускается из внешней флеш.
  erase-spiflash  стереть всю внешнюю SPI-флеш: битовый поток, образ программы и данные программы (рабочие
                  параметры). При MSPI ПЛИС после этого пуста до записи spiflash.

Сведения о плате (для окна «Программатор ПЛИС»):

  describe        одна строка JSON: плата, ПЛИС, есть ли встроенная flash, хранит ли внешняя флеш конфигурацию.

Плата - файл fw/boards/<плата>/<плата>.gwsoc: --gwsoc <файл> или --config <конфигурация сборки Eclipse>
(TangNano9K, TangPrimer20K - "board.buildConfig" в .gwsoc; запуски Eclipse передают ${config_name:riscv}).
Из него берутся: имя платы для openFPGALoader ("board.loader"), кристалл ("device"; свойства - в
sw/socgen/web/devices.js), каталог проекта ПЛИС ("paths.hw": битовый поток impl/pnr/riscv.fs), каталог сборки
программы fw/<конфигурация> и конфигурация OpenOCD fw/boards/<плата>/openocd.cfg. Какой режим собран, решает
конфигуратор: блок SPIFLASH с "fpgaConfig": true - ПЛИС для внешней флеш (загрузчик программы включён), иначе -
для SRAM и встроенной flash.

Несколько плат на одном ПК: программатор платы выбирает sw/fpgaload/boardsel.py по IDCODE ПЛИС (программаторы
Tang Nano 9K и Tang Primer 20K для ПК одинаковые), openFPGALoader получает ключ --busdev-num <шина:адрес>.

Порядок:
1. Если программатор платы занят отладкой (OpenOCD), сообщение и выход без обращения к плате. Одновременный
   доступ сбивает USB-соединение OpenOCD (LIBUSB_ERROR_IO) и загрузку. Программатор один - занят, если запущен
   любой openocd.exe; плат несколько - если запущен OpenOCD именно этой платы (номер процесса - в
   %TEMP%/askorv32_openocd_<порт>.pid, его пишет fw/boards/<плата>/openocd.cfg), с другой платой работать можно.
2. sram, flash: mergetool вливает программу <каталог сборки>/riscv.bin в последний битовый поток Gowin
   -> <каталог сборки>/riscv.fs; spiflash: образ программы <каталог сборки>/riscv_flash.bin.
3. openFPGALoader -b <плата> ...; полоса прогресса - через conprogress.

openFPGALoader - исправленный из sdk/openfpgaloader/bin (запись внешней флеш GW1N в ~3.5 раза быстрее,
sdk/openfpgaloader/README.md), если его нет - из OSS CAD Suite.

Запуск:  py -u sw/fpgaload/fpgaload.py sram|flash|spiflash|erase-flash|erase-spiflash|describe
                                         [--config TangNano9K | --gwsoc fw/boards/tangnano9k/tangnano9k.gwsoc]
                                         [--elf <программа>] [--force] [--oss C:/oss-cad-suite]
"""
import argparse
import glob
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
import boardsel                             # noqa: E402

BUSY = ["openocd.exe"]                      #Программы, которые держат программатор
BOARDS = ROOT / "fw" / "boards"


def running(image, pid=None):
    """Запущен ли процесс с таким именем (и номером, если задан) - tasklist Windows."""
    flt = ["/FI", f"IMAGENAME eq {image}"] + (["/FI", f"PID eq {pid}"] if pid else [])
    res = subprocess.run(["tasklist", *flt, "/NH"], capture_output=True, text=True, encoding="cp866", errors="replace")
    return image.lower() in res.stdout.lower()


def debugger_busy(probe):
    """Занят ли программатор отладкой: probe = None (он один) - запущен любой OpenOCD; иначе - OpenOCD,
    записавший свой номер процесса для порта этого программатора (fw/boards/<плата>/openocd.cfg)."""
    if probe is None:
        return [p for p in BUSY if running(p)]
    f = Path(os.environ.get("TEMP", ".")) / ("askorv32_openocd_" + probe["location"].replace("-", "_").replace(".", "_") + ".pid")
    try:
        pid = int(f.read_text().strip())
    except (OSError, ValueError):
        return []
    return [f"openocd.exe (PID {pid}, порт USB {probe['location']})"] if running("openocd.exe", pid) else []


def find_loader(oss_arg):
    """openFPGALoader и каталоги для PATH: исправленный из sdk/openfpgaloader/bin, иначе из OSS CAD Suite."""
    own = ROOT / "sdk" / "openfpgaloader" / "bin"
    if (own / "openFPGALoader.exe").is_file() and not oss_arg:
        return own / "openFPGALoader.exe", [own]
    for cand in [oss_arg, os.environ.get("OSS_CAD_SUITE"), "C:/oss-cad-suite"]:
        if cand and (Path(cand) / "bin" / "openFPGALoader.exe").is_file():
            return Path(cand) / "bin" / "openFPGALoader.exe", [Path(cand) / "bin", Path(cand) / "lib"]
    return None, []


def find_openocd():
    """OpenOCD (xPack, как у Eclipse): переменная OPENOCD или C:/Program Files/Eclipse/riscv-toolchain/xpack-openocd-*."""
    cands = [os.environ.get("OPENOCD")]
    cands += sorted(glob.glob("C:/Program Files/Eclipse/riscv-toolchain/xpack-openocd-*/bin/openocd.exe"), reverse=True)
    return next((Path(c) for c in cands if c and Path(c).is_file()), None)


def load_devices():
    text = (ROOT / "sw" / "socgen" / "web" / "devices.js").read_text(encoding="utf-8")
    return json.loads(text[text.index("{", text.index("GWSOC_DEVICES")):text.rindex("}") + 1])


class Board:
    """Плата из файла .gwsoc: что и куда грузить."""

    def __init__(self, gwsoc):
        self.gwsoc = Path(gwsoc).resolve()
        m = json.loads(self.gwsoc.read_text(encoding="utf-8"))
        b = m.get("board") or {}
        self.id = b.get("id") or self.gwsoc.stem
        self.title = b.get("title") or self.id
        self.config = b.get("buildConfig") or self.id
        self.loader = b.get("loader") or self.id
        self.dev = load_devices().get(m.get("device"))
        if not self.dev:
            raise SystemExit(f"{self.gwsoc.name}: кристалл «{m.get('device')}» не описан в sw/socgen/web/devices.js")
        self.hw = (self.gwsoc.parent / (m.get("paths") or {}).get("hw", ".")).resolve()
        self.pnr = self.hw / "impl" / "pnr"
        self.build = ROOT / "fw" / self.config                   #Каталог сборки конфигурации Eclipse
        self.openocd_cfg = self.gwsoc.parent / "openocd.cfg"
        cfg = [p for p in m.get("periph", []) if p.get("type") == "spiflash" and p.get("fpgaConfig", False)]
        self.ext_cfg = bool(cfg)
        self.boot_addr = int(str(cfg[0].get("bootAddr", "0x100000")).replace("_", ""), 16) if cfg else None
        core = m.get("core", {})
        self.mem = {}
        for region, key in ((0x00, "imem"), (0x10, "dmem")):
            c = core.get(key) or {}
            self.mem[region] = int(c.get("kb", 8)) * 1024 if c.get("type", "bsram") == "bsram" else int(c.get("synthWords", 256)) * 4

    @property
    def rel(self):
        return os.path.relpath(self.gwsoc, ROOT).replace("\\", "/")

    @property
    def cfg_write(self):
        """Сколько пишется битовый поток во внешнюю флеш: у GW1N - побитно через boundary scan, у GW2A - быстро."""
        return "около 3 мин" if self.dev["family"].startswith("GW1N") else "около 10 с"


def all_boards():
    return [Board(p) for p in sorted(BOARDS.glob("*/*.gwsoc"))]


def pick_board(a):
    """Плата по --gwsoc или --config (имя конфигурации Eclipse или id платы, без учёта регистра)."""
    if a.gwsoc:
        return Board(a.gwsoc)
    boards = all_boards()
    if a.config:
        key = a.config.lower()
        for b in boards:
            if key in (b.config.lower(), b.id.lower()):
                return b
        raise SystemExit(f"Нет платы для конфигурации сборки «{a.config}»: есть "
                         + ", ".join(f"{b.config} ({b.rel})" for b in boards))
    if len(boards) == 1:
        return boards[0]
    raise SystemExit("Укажите плату: --config " + " | ".join(b.config for b in boards) + " или --gwsoc <файл>")


class Loader:
    def __init__(self, exe, path, board, probe=None):
        self.exe, self.path, self.board = exe, path, board
        #Плат несколько - программатор этой платы по шине и адресу USB (boardsel)
        self.sel = ["--busdev-num", f"{probe['bus']}:{probe['addr']}"] if probe else []

    def run(self, args):
        env = dict(os.environ)
        env["PATH"] = os.pathsep.join([str(p) for p in self.path] + [env.get("PATH", "")])
        cmd = [str(self.exe), "-b", self.board.loader] + self.sel + args
        sys.stdout.flush()
        proc = subprocess.Popen(cmd, cwd=self.board.build, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
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


def load_by_debugger(board, elf):
    """Программа в IMEM/DMEM через модуль отладки (OpenOCD): reset halt (загрузчик из флеш, если он есть, успевает
    закончить), запись сегментов по адресам работы (VMA), запуск с адреса 0. Для кристаллов, раскладку битового
    потока которых mergetool не знает."""
    ocd = find_openocd()
    if not ocd:
        print("Не найден OpenOCD (C:/Program Files/Eclipse/riscv-toolchain/xpack-openocd-*, переменная OPENOCD)", file=sys.stderr)
        return 1
    segs = bootimage.segments_from_elf(elf)
    cmds = ["init", "reset halt"]
    for i, (addr, data) in enumerate(segs):
        f = board.build / f"riscv_seg{i}.bin"
        f.write_bytes(data)
        cmds.append(f"load_image {{{f.as_posix()}}} 0x{addr:08X} bin")
    cmds += ["resume 0", "shutdown"]
    print(f"Программа {Path(elf).name} -> память через отладчик ({bootimage.describe(segs)})")
    sys.stdout.flush()
    r = subprocess.run([str(ocd), "-f", str(board.openocd_cfg), "-c", "; ".join(cmds)],
                       capture_output=True, text=True, encoding="utf-8", errors="replace")
    for line in (r.stderr + r.stdout).splitlines():
        if line.startswith("Error"):
            print("  " + line)
    if r.returncode:
        print(f"OpenOCD завершился с ошибкой ({r.returncode})", file=sys.stderr)
        return r.returncode
    print("Программа запущена")
    return 0


def bitstream_mode(ld, board, target, elf):
    """sram/flash: программа в битовом потоке (mergetool) или, если mergetool кристалл не знает, через отладчик."""
    if target == "flash" and not board.dev["embeddedFlash"]:
        print(f"У ПЛИС {board.dev['part']} ({board.title}) нет встроенной flash: она загружается из внешней SPI-флеш. "
              "Используйте spiflash (Eclipse: riscv SPI-FLASH) или sram.", file=sys.stderr)
        return 1
    if target == "flash" and board.ext_cfg:
        print("В конфигураторе выбрано хранение во внешней SPI-флеш (SPIFLASH: «Конфигурация и программа - во "
              "внешней флеш»): битовый поток собран для режима MSPI. Запись во встроенную flash не нужна - "
              "используйте spiflash (Eclipse: riscv SPI-FLASH) или смените режим в конфигураторе и пересоберите ПЛИС.",
              file=sys.stderr)
        return 1
    if board.ext_cfg:
        print("Примечание: ПЛИС собрана для внешней флеш - после сброса загрузчик возьмёт программу из образа "
              "во внешней флеш, если он там есть")
    fs = board.pnr / "riscv.fs"
    if not fs.exists():
        print(f"Нет битового потока {os.path.relpath(fs, ROOT)} - соберите ПЛИС (конфигуратор, «Собрать»)", file=sys.stderr)
        return 1
    elf = Path(elf).resolve() if elf else board.build / "riscv.elf"
    if not board.dev.get("mergetool"):
        #Битовый поток как есть, программа - отладчиком
        rc = ld.run([str(fs)])
        return rc or load_by_debugger(board, elf)
    prog = board.build / "riscv.bin" if elf == board.build / "riscv.elf" else flat_bin(elf)
    out = board.build / "riscv.fs"
    sys.stdout.flush()
    rc = subprocess.run([str(ROOT / "sw" / "mergetool" / "mergetool.exe"), str(prog),
                         str(board.pnr / "riscv.posp"), str(fs), str(out)], cwd=board.build).returncode
    if rc:
        print(f"mergetool завершился с ошибкой ({rc}), ПЛИС не загружалась", file=sys.stderr)
        return rc
    return ld.run((["-f"] if target == "flash" else []) + [str(out)])


def spiflash_mode(ld, board, elf, force):
    """spiflash: битовый поток (если изменился) и образ программы во внешнюю флеш, затем перезапуск ПЛИС."""
    if not board.ext_cfg:
        print("В конфигураторе не выбрано хранение во внешней SPI-флеш: битовый поток собран без загрузчика "
              "программы. Включите в блоке SPIFLASH «Конфигурация и программа - во внешней флеш (MSPI)», "
              "пересоберите ПЛИС - или используйте sram/flash.", file=sys.stderr)
        return 1
    elf = Path(elf).resolve() if elf else board.build / "riscv.elf"
    try:
        segs = bootimage.segments_from_elf(elf)
        img = bootimage.build(segs, board.mem)
    except (bootimage.ImageError, OSError) as e:
        print("Образ программы: " + str(e), file=sys.stderr)
        return 1
    fs = board.pnr / "riscv.fs"
    stamp = board.build / "riscv_extflash_cfg.sha256"
    digest = hashlib.sha256(fs.read_bytes()).hexdigest()
    if not force and stamp.exists() and stamp.read_text().strip() == digest:
        print("Конфигурация ПЛИС во внешней флеш не менялась - пропуск (записать заново: --force)")
    else:
        print(f"Конфигурация ПЛИС {os.path.relpath(fs, ROOT)} -> внешняя флеш с адреса 0x000000 ({board.cfg_write})")
        stamp.unlink(missing_ok=True)
        rc = ld.run(["--external-flash", "-o", "0", str(fs)])
        if rc:
            return rc
        stamp.write_text(digest + "\n")
    out = elf.with_name(elf.stem + "_flash.bin")
    out.write_bytes(img)
    print(f"Образ {out.name}: {len(img)} Байт ({bootimage.describe(segs)}) -> внешняя флеш с адреса 0x{board.boot_addr:06X}")
    rc = ld.run(["--external-flash", "-o", str(board.boot_addr), str(out)])
    if rc:
        return rc
    #Запись внешней флеш стирает конфигурацию ПЛИС: перезапуск - из внешней флеш (MSPI), загрузчик возьмёт программу
    print("Перезапуск ПЛИС из внешней флеш (MSPI)")
    return ld.run(["-r"])


def erase_mode(ld, board, target):
    """erase-flash / erase-spiflash: стирание встроенной flash или всей внешней флеш (--bulk-erase)."""
    if target == "erase-flash":
        if not board.dev["embeddedFlash"]:
            print(f"У ПЛИС {board.dev['part']} ({board.title}) нет встроенной flash - стирать нечего", file=sys.stderr)
            return 1
        print("Стирание встроенной flash ПЛИС")
        rc = ld.run(["--bulk-erase"])
        if not rc and board.ext_cfg:
            print("ПЛИС собрана для внешней флеш (MSPI): после перезапуска она снова загружается из внешней флеш")
        return rc
    print("Стирание всей внешней SPI-флеш: битовый поток, образ программы, данные программы")
    (board.build / "riscv_extflash_cfg.sha256").unlink(missing_ok=True)   #Следующая запись spiflash пишет и битовый поток
    rc = ld.run(["--external-flash", "--bulk-erase"])
    if not rc and board.ext_cfg:
        print("Внешняя флеш пуста: при MSPI ПЛИС не загрузится, пока не записать spiflash")
    return rc


def main():
    ap = argparse.ArgumentParser(description="Загрузка ПЛИС и программы через openFPGALoader")
    ap.add_argument("target", choices=["sram", "flash", "spiflash", "erase-flash", "erase-spiflash", "describe"],
                    help="sram - SRAM ПЛИС (до выключения питания), flash - встроенная flash (AUTO BOOT), "
                         "spiflash - внешняя SPI-флеш (MSPI); erase-flash, erase-spiflash - стереть встроенную "
                         "flash или всю внешнюю флеш; describe - сведения о плате (JSON)")
    ap.add_argument("--config", help="плата по конфигурации сборки Eclipse (TangNano9K, TangPrimer20K) или id платы")
    ap.add_argument("--gwsoc", help="плата по файлу конфигурации ПЛИС fw/boards/<плата>/<плата>.gwsoc")
    ap.add_argument("--elf", help="программа (по умолчанию <каталог сборки>/riscv.elf и riscv.bin сборки Eclipse)")
    ap.add_argument("--force", action="store_true", help="spiflash: писать битовый поток, даже если он не менялся")
    ap.add_argument("--oss", help="openFPGALoader из OSS CAD Suite в этом каталоге (вместо sdk/openfpgaloader/bin)")
    a = ap.parse_args()

    board = pick_board(a)
    if a.target == "describe":
        print(json.dumps({"board": board.id, "title": board.title, "buildConfig": board.config,
                          "device": board.dev["part"], "family": board.dev["family"],
                          "embeddedFlash": board.dev["embeddedFlash"], "extCfg": board.ext_cfg,
                          "bootAddr": None if board.boot_addr is None else f"0x{board.boot_addr:06X}",
                          "cfgWrite": board.cfg_write}, ensure_ascii=False))
        return 0
    print(f"Плата: {board.title} ({board.dev['part']}), {board.rel}")

    #1 Программатор платы (плат несколько - по IDCODE ПЛИС) и не занят ли он отладкой
    try:
        probe = boardsel.select(board.gwsoc)
    except SystemExit as e:
        print(str(e), file=sys.stderr)
        return 1
    if probe:
        print(f"Программатор платы: шина {probe['bus']}, адрес {probe['addr']}, порт USB {probe['location']}")
    busy = debugger_busy(probe)
    if busy:
        print(f"Программатор занят: запущен {', '.join(busy)} (идёт отладка).\n"
              "Остановите отладку в Eclipse (Terminate) и запустите загрузку ещё раз.", file=sys.stderr)
        return 1

    exe, path = find_loader(a.oss)
    if not exe:
        print("Не найден openFPGALoader: sdk/openfpgaloader/bin или OSS CAD Suite (C:/oss-cad-suite, OSS_CAD_SUITE; "
              "SETUP.md п. 10)", file=sys.stderr)
        return 1
    board.build.mkdir(parents=True, exist_ok=True)
    ld = Loader(exe, path, board, probe)
    if a.target.startswith("erase-"):
        return erase_mode(ld, board, a.target)
    if a.target == "spiflash":
        return spiflash_mode(ld, board, a.elf, a.force)
    return bitstream_mode(ld, board, a.target, a.elf)


if __name__ == "__main__":
    sys.exit(main())
