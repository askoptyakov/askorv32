#!/usr/bin/env python3
"""mkdevices - база кристаллов конфигуратора ПЛИС: sw/socgen/web/devices.js.

Выводы корпусов берутся из файлов Gowin IDE (data/device/<кристалл>/<корпус>.json), свойства семейств
(пределы rPLL, ресурсы, встроенная flash, выводы двойного назначения, маршрут apicula) - из таблицы
FAMILIES ниже. Файл devices.js читают и страница конфигуратора (<script>), и генератор socgen.py
(JSON после GWSOC_DEVICES), поэтому правила семейства задаются в одном месте.

Запуск:  py sw/socgen/mkdevices.py [--gowin "C:/Program Files/Gowin/Gowin_V1.9.11.03_Education_x64/IDE"]
Новый кристалл: строка в FAMILIES (номер детали Gowin - как в data/device/device_package.csv) и запуск.
"""
import argparse
import csv
import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent

#Свойства семейств. pll - пределы rPLL (МГц): вход, PFD, VCO, выход (GW1NR-9: DS117, GW2A-18: DS102).
#cfgRegion - не ниже этого адреса внешней флеш кладётся образ программы, когда флеш хранит и битовый
#поток (режим MSPI): GW1NR-9 - 442 кБайт, GW2A-18 - 882 кБайт. dualPurpose - выводы двойного назначения,
#которые можно занять как обычные I/O: флажок настройки процесса Gowin EDA -> функции вывода (cfg) и
#ключ gowin_pack. resources - всего в кристалле (для панели ресурсов, пока нет отчёта сборки). mergetool - раскладку
#BSRAM в битовом потоке знает sw/mergetool (программа вливается в .fs); иначе fpgaload грузит программу отладчиком.
#idcode - JTAG IDCODE кристалла: по нему sw/fpgaload/boardsel.py находит программатор платы, если плат несколько.
FAMILIES = {
    "GW1NR-LV9QN88PC6/I5": dict(
        title="GW1NR-LV9QN88P", family="GW1NR-9C", idcode="0x1100481B", series="GW1NR-9", version="C", pllDevice="GW1NR-9C",
        pll=dict(inMin=3, inMax=400, pfdMin=3, pfdMax=400, vcoMin=400, vcoMax=1200, outMin=3.125, outMax=600),
        vcc="1.2", embeddedFlash=True, mergetool=True, cfgRegion=0x80000, cfgUser=0x100000,
        resources=dict(lut=8640, reg=6480, bsram=26, dsp=10, io=71, pll=2),
        dualPurpose={"MSPI": [["MCLK", "MCS_N", "MO", "MI"], "--mspi_as_gpio"]},
        apicula=dict(family="GW1N-9C", jtag=False)),
    "GW2A-LV18PG256C8/I7": dict(
        title="GW2A-LV18PG256", family="GW2A-18C", idcode="0x0000081B", series="GW2A-18", version="C", pllDevice="GW2A-18C",
        pll=dict(inMin=3, inMax=500, pfdMin=3, pfdMax=500, vcoMin=500, vcoMax=1250, outMin=3.90625, outMax=625),
        vcc="1.0", embeddedFlash=False, mergetool=True, cfgRegion=0x100000, cfgUser=0x100000,
        resources=dict(lut=20736, reg=15552, bsram=46, dsp=24, io=207, pll=4),
        dualPurpose={"MSPI": [["MCLK", "MCS_N", "MO", "MI"], "--mspi_as_gpio"],
                     "SSPI": [["SCLK", "SSPI_CS_N", "SI", "SO"], "--sspi_as_gpio"],
                     "READY": [["READY"], "--ready_as_gpio"],
                     "DONE": [["DONE"], "--done_as_gpio"],
                     "RECONFIG_N": [["RECONFIG_N"], "--reconfign_as_gpio"]},
        apicula=dict(family="GW2A-18C", jtag=True)),
}
TYPES = {"I/O": "io", "POWER": "pwr", "GROUND": "gnd"}


def find_ide(arg):
    cands = [arg] + sorted((str(p / "IDE") for p in Path("C:/Program Files/Gowin").glob("*")), reverse=True)
    for c in cands:
        if c and (Path(c) / "data" / "device" / "device_package.csv").exists():
            return Path(c)
    sys.exit("Не найден Gowin IDE (data/device): укажите --gowin")


def device(ide, part, fam):
    rows = list(csv.reader(open(ide / "data/device/device_package.csv", encoding="utf-8", errors="replace")))
    row = next(r for r in rows if len(r) > 5 and r[1] == part)
    dev_id, pkg_file = row[0], row[5]
    src = json.loads((ide / "data/device" / pkg_file).read_text(encoding="utf-8"))
    pins = []
    for p in src["PIN_DATA"]:
        n = p["INDEX"]
        q = {"n": int(n) if n.isdigit() else n, "name": p["NAME"], "type": TYPES.get(p["TYPE"], "nc")}
        for k_src, k in (("BANK", "bank"), ("CFG", "cfg"), ("DIFF", "diff"), ("PAIR", "pair")):
            if p.get(k_src) not in (None, "", "None"):
                q[k] = p[k_src]
        if p.get("TRUELVDS"):
            q["lvds"] = True
        pins.append(q)
    d = {"part": part, "deviceId": dev_id, "package": src["NAME"], "pkgType": src["PKG_TYPE"]}
    if src["PKG_TYPE"] == "ARRAY":
        d.update(rows=src["ROW_MARK"].split(","), cols=src["COL_COUNT"])
    else:
        d["perSide"] = len(pins) // 4
        pins.sort(key=lambda x: x["n"])
    d.update(fam)
    d["source"] = f"Gowin IDE, data/device/{pkg_file}"
    d["pins"] = pins
    return d


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--gowin", help="каталог Gowin IDE")
    a = ap.parse_args()
    ide = find_ide(a.gowin)
    devs = {part: device(ide, part, fam) for part, fam in FAMILIES.items()}
    out = HERE / "web" / "devices.js"
    lines = ["// Кристаллы конфигуратора ПЛИС askoRV32: выводы корпусов (из Gowin IDE) и свойства семейств.",
             "// Файл создан sw/socgen/mkdevices.py - не редактируйте вручную. Его читают страница конфигуратора",
             "// (<script>) и генератор socgen.py (JSON после GWSOC_DEVICES).",
             "window.GWSOC_DEVICES = {"]
    for i, (part, d) in enumerate(devs.items()):
        head = {k: v for k, v in d.items() if k != "pins"}
        lines.append(f"{json.dumps(part)}: " + json.dumps(head, ensure_ascii=False)[:-1] + ', "pins": [')
        lines += ["  " + json.dumps(p, ensure_ascii=False) + ("," if j < len(d["pins"]) - 1 else "")
                  for j, p in enumerate(d["pins"])]
        lines.append("]}" + ("," if i < len(devs) - 1 else ""))
    lines.append("};")
    out.write_text("\n".join(lines) + "\n", encoding="utf-8", newline="\n")
    for part, d in devs.items():
        print(f"{part}: {d['package']}, выводов {len(d['pins'])} (I/O {sum(p['type'] == 'io' for p in d['pins'])})")
    print(f"Записан {out}")


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8")
    main()
