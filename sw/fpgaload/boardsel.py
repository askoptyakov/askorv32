"""
boardsel - выбор программатора нужной платы, когда к ПК подключено несколько плат.

У Tang Nano 9K (BL702) и Tang Primer 20K (BL616) программаторы одинаковые для ПК: FTDI-совместимые 0403:6010,
одно имя и один серийный номер. openFPGALoader и OpenOCD без подсказки берут первый попавшийся. Плату
различает ПЛИС на ней: IDCODE по JTAG (GW1NR-9 - 0x1100481b, GW2A-18 - 0x0000081b; "idcode" в
sw/socgen/web/devices.js).

Как выбирается:
1. libusb (sdk/openfpgaloader/bin/libusb-1.0.dll, та же, что у openFPGALoader) перечисляет программаторы
   0403:6010: шина, адрес, путь порта (bus-port.port...).
2. Один программатор - он и есть (ничего не опрашивается).
3. Несколько - у каждого читается IDCODE: openFPGALoader --busdev-num <шина:адрес> --detect. Результат
   запоминается (кэш в %TEMP%/askorv32_probes.json по шине, адресу и порту: адрес меняется при каждом
   переподключении, поэтому старый кэш не мешает). Программатор, занятый другой программой (OpenOCD
   отлаживает другую плату), не открывается - он пропускается, если его IDCODE ещё не в кэше.
4. Выбирается программатор с IDCODE кристалла платы.

Кто пользуется:
- fpgaload.py: ключ openFPGALoader --busdev-num <шина:адрес>;
- fw/boards/<плата>/openocd.cfg: при запуске OpenOCD вызывает «boardsel.py --gwsoc <файл> --openocd» и
  получает команду «adapter usb location <шина-порт>» (или пустую строку, если программатор один).

Запуск:  py sw/fpgaload/boardsel.py [--gwsoc <файл .gwsoc> | --config TangNano9K] [--openocd | --busdev]
         py sw/fpgaload/boardsel.py --list      - все программаторы и ПЛИС на них
"""
import argparse
import ctypes as C
import json
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BIN = ROOT / "sdk" / "openfpgaloader" / "bin"
PROBES = [(0x0403, 0x6010)]                 #FTDI FT2232 и совместимые (BL702, BL616)
CACHE = Path(tempfile.gettempdir()) / "askorv32_probes.json"
IDMASK = 0x0FFFFFFF                         #Версия кристалла (старшие 4 бита) не сравнивается


class DevDesc(C.Structure):
    _fields_ = [("bLength", C.c_uint8), ("bDescriptorType", C.c_uint8), ("bcdUSB", C.c_uint16),
                ("bDeviceClass", C.c_uint8), ("bDeviceSubClass", C.c_uint8), ("bDeviceProtocol", C.c_uint8),
                ("bMaxPacketSize0", C.c_uint8), ("idVendor", C.c_uint16), ("idProduct", C.c_uint16),
                ("bcdDevice", C.c_uint16), ("iManufacturer", C.c_uint8), ("iProduct", C.c_uint8),
                ("iSerialNumber", C.c_uint8), ("bNumConfigurations", C.c_uint8)]


def usb_probes():
    """Программаторы на USB: [{bus, addr, location}] (location - «шина-порт.порт», как у OpenOCD)."""
    lib = C.CDLL(str(BIN / "libusb-1.0.dll"))
    lib.libusb_get_device_list.restype = C.c_ssize_t
    lib.libusb_get_bus_number.restype = C.c_uint8
    lib.libusb_get_device_address.restype = C.c_uint8
    ctx = C.c_void_p()
    if lib.libusb_init(C.byref(ctx)):
        return []
    lst = C.POINTER(C.c_void_p)()
    n = lib.libusb_get_device_list(ctx, C.byref(lst))
    out = []
    for i in range(max(0, n)):
        dev = C.c_void_p(lst[i])
        d = DevDesc()
        if lib.libusb_get_device_descriptor(dev, C.byref(d)) or (d.idVendor, d.idProduct) not in PROBES:
            continue
        ports = (C.c_uint8 * 8)()
        k = lib.libusb_get_port_numbers(dev, ports, 8)
        bus = lib.libusb_get_bus_number(dev)
        out.append(dict(bus=bus, addr=lib.libusb_get_device_address(dev),
                        location=f"{bus}-" + ".".join(str(ports[j]) for j in range(max(0, k)))))
    lib.libusb_free_device_list(lst, 1)
    lib.libusb_exit(ctx)
    return sorted(out, key=lambda p: (p["bus"], p["addr"]))


def key(p):
    return f"{p['bus']}:{p['addr']}@{p['location']}"


def read_idcode(p):
    """IDCODE ПЛИС за программатором (openFPGALoader --detect) или None (занят, нет ответа)."""
    try:
        r = subprocess.run([str(BIN / "openFPGALoader.exe"), "--busdev-num", f"{p['bus']}:{p['addr']}", "--detect"],
                           capture_output=True, text=True, timeout=20, errors="replace")
    except (OSError, subprocess.TimeoutExpired):
        return None
    m = re.search(r"idcode\s+0x([0-9a-fA-F]+)", r.stdout + r.stderr)
    return int(m.group(1), 16) if m else None


def busy_by_openocd(p):
    """Программатор занят OpenOCD (номер процесса в %TEMP%/askorv32_openocd_<порт>.pid и процесс жив): его
    не опрашиваем - чужой доступ сбивает USB-соединение OpenOCD."""
    f = Path(tempfile.gettempdir()) / ("askorv32_openocd_" + p["location"].replace("-", "_").replace(".", "_") + ".pid")
    try:
        pid = int(f.read_text().strip())
    except (OSError, ValueError):
        return False
    r = subprocess.run(["tasklist", "/FI", "IMAGENAME eq openocd.exe", "/FI", f"PID eq {pid}", "/NH"],
                       capture_output=True, text=True, encoding="cp866", errors="replace")
    return "openocd.exe" in r.stdout.lower()


def identify(probes):
    """IDCODE каждого программатора (с кэшем): {ключ: idcode или None}."""
    try:
        cache = json.loads(CACHE.read_text())
    except (OSError, ValueError):
        cache = {}
    res, changed = {}, False
    for p in probes:
        k = key(p)
        if k in cache:
            res[k] = cache[k]
        else:
            res[k] = None if busy_by_openocd(p) else read_idcode(p)
            if res[k] is not None:
                cache[k] = res[k]
                changed = True
    if changed:
        live = {key(p) for p in probes}
        try:
            CACHE.write_text(json.dumps({k: v for k, v in cache.items() if k in live}))
        except OSError:
            pass
    return res


def device_idcode(gwsoc):
    m = json.loads(Path(gwsoc).read_text(encoding="utf-8"))
    text = (ROOT / "sw" / "socgen" / "web" / "devices.js").read_text(encoding="utf-8")
    devs = json.loads(text[text.index("{", text.index("GWSOC_DEVICES")):text.rindex("}") + 1])
    d = devs.get(m.get("device"))
    if not d or "idcode" not in d:
        raise SystemExit(f"{Path(gwsoc).name}: нет IDCODE кристалла «{m.get('device')}» в devices.js")
    return int(d["idcode"], 16), (m.get("board") or {}).get("title", Path(gwsoc).stem)


def select(gwsoc):
    """Программатор платы: dict(bus, addr, location) или None, если программатор один (выбирать не нужно).
    Если плату не нашли - SystemExit с объяснением."""
    probes = usb_probes()
    if len(probes) <= 1:
        return None
    want, title = device_idcode(gwsoc)
    ids = identify(probes)
    found = [p for p in probes if ids[key(p)] is not None and (ids[key(p)] & IDMASK) == (want & IDMASK)]
    if len(found) == 1:
        return found[0]
    seen = ", ".join(f"{key(p)}: " + ("занят или нет ответа" if ids[key(p)] is None else f"0x{ids[key(p)]:08x}")
                     for p in probes)
    if not found:
        raise SystemExit(f"Плата {title} (IDCODE 0x{want:08x}) не найдена среди программаторов: {seen}")
    raise SystemExit(f"Плат {title} подключено несколько ({seen}) - оставьте одну")


def gwsoc_by_config(cfg):
    for p in sorted((ROOT / "fw" / "boards").glob("*/*.gwsoc")):
        b = json.loads(p.read_text(encoding="utf-8")).get("board") or {}
        if cfg.lower() in (str(b.get("buildConfig", "")).lower(), str(b.get("id", "")).lower(), p.stem.lower()):
            return p
    raise SystemExit(f"Нет платы для «{cfg}»")


def main():
    ap = argparse.ArgumentParser(description="Выбор программатора платы по IDCODE ПЛИС")
    ap.add_argument("--gwsoc", help="плата - файл .gwsoc")
    ap.add_argument("--config", help="плата - конфигурация сборки Eclipse или id платы")
    ap.add_argument("--openocd", action="store_true", help="вывести команду OpenOCD «adapter usb location ...» (или пусто)")
    ap.add_argument("--busdev", action="store_true", help="вывести ключ openFPGALoader «--busdev-num B:A» (или пусто)")
    ap.add_argument("--list", action="store_true", help="перечислить программаторы и ПЛИС на них")
    a = ap.parse_args()
    if a.list:
        probes = usb_probes()
        ids = identify(probes) if probes else {}
        for p in probes:
            v = ids.get(key(p))
            print(f"шина {p['bus']}, адрес {p['addr']}, порт {p['location']}: " + ("занят или нет ответа" if v is None else f"IDCODE 0x{v:08x}"))
        if not probes:
            print("Программаторов 0403:6010 не найдено")
        return 0
    gwsoc = a.gwsoc or (gwsoc_by_config(a.config) if a.config else None)
    if not gwsoc:
        ap.error("укажите --gwsoc или --config")
    try:
        p = select(gwsoc)
    except SystemExit as e:
        print(e, file=sys.stderr)
        return 1
    if a.openocd:
        print(f"adapter usb location {p['location']}" if p else "")
    elif a.busdev:
        print(f"--busdev-num {p['bus']}:{p['addr']}" if p else "")
    else:
        print("программатор один - выбирать не нужно" if not p else f"шина {p['bus']}, адрес {p['addr']}, порт {p['location']}")
    return 0


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8")
    sys.stderr.reconfigure(encoding="utf-8")
    sys.exit(main())
