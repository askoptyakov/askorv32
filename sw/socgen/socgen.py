#!/usr/bin/env python3
"""socgen - генератор проекта ПЛИС askoRV32 из файла конфигурации .gwsoc.

По файлу fw/riscv.gwsoc (его редактирует визуальный конфигуратор в Eclipse) создаёт:
  hw/src/top.sv     - верхний уровень платы: выводы, параметры процессора cpu.sv, карта адресов
                    и шина пользовательской периферии, сами устройства и их прерывания;
  hw/src/riscv.cst  - назначение выводов (IO_LOC/IO_PORT) для Gowin EDA и nextpnr;
  fw/Core/Inc/soc.h - для прошивки: частота, адреса и указатели устройств, номера источников PLIC
                    и имена обработчиков, настройки устройств, имена выводов GPIO (<ЦЕПЬ>_PIN/_PORT).
С ключом --build собирает проект ПЛИС: в Gowin EDA (gw_sh, проект hw/riscv.gprj) или открытым
маршрутом Yosys + nextpnr-himbaechel + apicula - по build.toolchain в .gwsoc или ключу --toolchain.

Пользовательская периферия - список экземпляров "periph" (тип, имя, адрес, настройки, выводы);
имя экземпляра - имя устройства в прошивке (указатель на регистры), в top.sv - его строчная форма.
Правила (адреса, rPLL, проверки, имена) продублированы в web/app.js - при изменении править оба места.

Запуск:  py sw/socgen/socgen.py fw/riscv.gwsoc [--check] [--build [--toolchain gowin|apicula]]
                                                [--gowin <каталог IDE>] [--oss C:/oss-cad-suite]
"""
import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import time
import xml.etree.ElementTree as ET
from pathlib import Path

HERE = Path(__file__).resolve().parent

# ============================================================================================
# Данные кристалла и правила
# ============================================================================================
JTAG_PINS = {5: "TMS", 6: "TCK", 7: "TDI", 8: "TDO"}
ODIV_SET = [2, 4, 8, 16, 32, 48, 64, 80, 96, 112, 128]
PLL = dict(inMin=3, inMax=400, pfdMin=3, pfdMax=400, vcoMin=400, vcoMax=1200, outMin=3.125, outMax=600)

#Библиотека устройств (как TYPES в web/app.js). slot - окно адресов первого экземпляра при "auto";
#cat - группа на схеме: iface - интерфейсы, gpio - выводы общего назначения, custom - своя периферия
TYPES = {
    "gpio":   dict(title="GPIO",   slot=0x11, cat="gpio",   irq=False, module="gpio_top"),
    "tm1638": dict(title="TM1638", slot=0x12, cat="custom", irq=False, module="tm1638_top"),
    "stim":   dict(title="STIM",   slot=0x13, cat="custom", irq=True,  module="stim_top"),
    "uart":   dict(title="UART",   slot=0x14, cat="iface",  irq=True,  module="uart_top"),
}
UART_BAUDS = [1200, 2400, 4800, 9600, 19200, 38400, 57600, 115200, 230400, 460800, 921600]
UART_PARITY = {"none": 0, "even": 1, "odd": 2}
FIFO_DEPTHS = [8, 16, 32]
MEM_KB = [8, 16, 32]
BSRAM_TOTAL = 26           #Блоков BSRAM (18 кбит, 2 кБайт данных) в GW1NR-9
FIXED_REGIONS = {"IMEM": 0x00, "CLINT": 0x02, "PLIC": 0x0C, "DMEM": 0x10, "SIM": 0x1F}
AUTO_FIRST, AUTO_LAST = 0x11, 0x1E
PLACE_OPTIONS = {"0": "быстрее компиляция", "1": "лучше трассируемость", "2": "лучше тайминги"}

NET_RE = re.compile(r"^([A-Za-z_][A-Za-z0-9_$]*)(?:\[(\d+)\])?$")
NAME_RE = re.compile(r"^[A-Za-z_][A-Za-z0-9_]{0,23}$")
SV_KEYWORDS = {"input", "output", "inout", "wire", "logic", "reg", "module", "endmodule", "assign", "always",
               "begin", "end", "if", "else", "case", "for", "generate", "parameter", "localparam", "int", "bit"}
#Имена, занятые в top.sv независимо от состава периферии: порт cpu, сигналы, экземпляры и модули, параметры
#(сигналы шины устройств <экземпляр>_Write... и <ИМЯ>_BASE добавляет reserved_nets)
RESERVED_NETS = {"tck_pad_i", "tms_pad_i", "tdi_pad_i", "tdo_pad_o", "clk_per", "rst_per", "bus_per_Write",
                 "bus_per_Read", "bus_per_Addr", "bus_per_WData", "bus_per_RData", "irq_local", "irq_src",
                 "sRead", "top", "cpu", "permux", "memmux", "gpio_top", "stim_top", "tm1638_top", "uart_top",
                 "CORE_TYPE", "M_EXT", "DIV_BPC", "IMEM_TYPE", "BSRAM_IMEM_SIZE", "SYNTH_IMEM_SIZE", "IMEM_INIT_FILE",
                 "DMEM_TYPE", "BSRAM_DMEM_SIZE", "SYNTH_DMEM_SIZE", "DMEM_INIT_FILE", "DEBUG_EN", "PLIC_SOURCES",
                 "FCLKIN", "XTAL_KHZ", "PLL_IDIV_SEL", "PLL_FBDIV_SEL", "PLL_ODIV_SEL", "WIN_MASK", "CLK_BASE_MHZ",
                 "CLK_DMEM_MHZ"}
#Имена экземпляров, занятые в прошивке (periphery.h, soc.h, драйверы)
RESERVED_C = {"CLINT", "PLIC", "SOC", "SYSCLK_HZ", "MTIME_HZ", "LI", "IRQ", "NULL", "MODE", "OUT", "IN"}


class ConfigError(Exception):
    pass


def load_device():
    text = (HERE / "web" / "device.js").read_text(encoding="utf-8")
    start = text.index("{", text.index("GWSOC_DEVICE"))
    dev = json.loads(text[start:text.rindex("}") + 1])
    dev["byNum"] = {p["n"]: p for p in dev["pins"]}
    return dev


def slot_hex(slot):
    v = f"{slot * 0x01000000:08X}"
    return f"32'h{v[:4]}_{v[4:]}"


# --- Модель: переход со старого формата и экземпляры ---
def migrate(m):
    """Формат 1 ("blocks": фиксированные GPIO/TM1638/STIM/UART с enabled) -> формат 2 ("periph": список
    экземпляров). Включённые блоки становятся экземплярами с именами типов, порядок прежний."""
    if "periph" in m:
        return m
    periph = []
    for t, b in (m.pop("blocks", None) or {}).items():
        if t in TYPES and b.get("enabled"):
            inst = {"type": t, "name": TYPES[t]["title"]}
            inst.update({k: v for k, v in b.items() if k != "enabled"})
            periph.append(inst)
    periph.sort(key=lambda i: list(TYPES).index(i["type"]))
    m["periph"] = periph
    m["version"] = 2
    return m


def insts(m, typ=None):
    return [i for i in m["periph"] if typ is None or i["type"] == typ]


def hdl(inst):
    """Имя экземпляра в top.sv и префикс его сигналов шины."""
    return inst["name"].lower()


def inst_title(inst):
    """Подпись экземпляра: имя, а если оно не совпадает с типом - «имя (тип)»."""
    t = TYPES[inst["type"]]["title"]
    return inst["name"] if inst["name"] == t else f"{inst['name']} ({t})"


def first_of_type(m, inst):
    return insts(m, inst["type"])[0] is inst


# --- Сигналы ---
def inst_signals(inst):
    """Сигналы устройства, которым нужен вывод: (ключ, подпись, направление, обязателен)."""
    t = inst["type"]
    if t == "gpio":
        return [(f"line{i}", f"линия {i}", "inout", True) for i in range(len(inst.get("lines", [])))]
    if t == "tm1638":
        return [("dio", "DIO", "inout", True), ("clk", "CLK", "output", True), ("stb", "STB", "output", True)]
    if t == "stim":
        return [("out", "выход ШИМ", "output", False)] if inst.get("out") is not None else []
    if t == "uart":
        return [("tx", "TX", "output", True), ("rx", "RX", "input", True)]
    return []


def inst_pin(inst, key):
    if key.startswith("line"):
        return inst["lines"][int(key[4:])]
    return inst.get(key)


def signals(m):
    s = [dict(id="clk", inst=None, key="clk", name="Кварц", dir="input", pin=m["clock"].get("xtalPin")),
         dict(id="rst", inst=None, key="rst", name="Сброс rst_n", dir="input", pin=m["reset"].get("pin"))]
    for inst in insts(m):
        for key, label, d, _ in inst_signals(inst):
            s.append(dict(id=f"{inst['name']}.{key}", inst=inst, key=key, name=f"{inst['name']} {label}",
                          dir=d, pin=inst_pin(inst, key)))
    return s


def net_of(m, pin):
    return (m["pins"].get(str(pin)) or {}).get("net", "")


def c_name(net):
    """Имя цепи -> имя в Си (define): LED[3] -> LED3, заглавными (скобки индекса убираются, $ -> _)."""
    mm = NET_RE.match(net)
    return (mm.group(1) + (mm.group(2) or "")).replace("$", "_").upper()


def reserved_nets(m):
    """Все имена, занятые в top.sv при текущем составе периферии."""
    r = set(RESERVED_NETS)
    for inst in insts(m):
        h = hdl(inst)
        r |= {h, f"{h}_Write", f"{h}_Addr", f"{h}_WriteData", f"{h}_ReadData", f"irq_{h}", f"{inst['name'].upper()}_BASE"}
    return r


# --- Адреса ---
def parse_base(v):
    if v in (None, "", "auto"):
        return None
    if isinstance(v, int):
        return v
    try:
        return int(str(v).replace("_", ""), 16)
    except ValueError:
        return -1


def address_map(m, errors):
    """Окна адресов экземпляров: {имя: слот}. Сначала ручные адреса, затем автоматические; при "auto" первый
    экземпляр типа занимает окно типа, остальные - первое свободное с 0x11."""
    taken = {slot: name for name, slot in FIXED_REGIONS.items()}
    result = {}
    for pass_ in ("manual", "auto"):
        for inst in insts(m):
            base = parse_base(inst.get("base", "auto"))
            if (base is None) != (pass_ == "auto"):
                continue
            name = inst["name"]
            if base is None:
                s = TYPES[inst["type"]]["slot"] if first_of_type(m, inst) else AUTO_FIRST
                if s in taken:
                    s = AUTO_FIRST
                    while s <= AUTO_LAST and s in taken:
                        s += 1
                if s > AUTO_LAST:
                    errors.append(f"{name}: нет свободного окна адресов")
                    continue
            else:
                if base < 0 or base > 0xFFFFFFFF or base & 0x00FFFFFF:
                    errors.append(f"{name}: адрес должен быть кратен 0x0100_0000 (окно 16 МБайт)")
                    continue
                s = base >> 24
                if s in taken:
                    errors.append(f"{name}: адрес {slot_hex(s)} уже занят ({taken[s]})")
            taken[s] = name
            result[name] = s
    return result


# --- rPLL ---
def pll_eval(fin, idiv, fbdiv, odiv):
    pfd, fout = fin / (idiv + 1), fin * (fbdiv + 1) / (idiv + 1)
    vco = fout * odiv
    errs = []
    if not PLL["inMin"] <= fin <= PLL["inMax"]:
        errs.append(f"частота кварца {fin} МГц вне {PLL['inMin']}..{PLL['inMax']}")
    if not PLL["pfdMin"] <= pfd <= PLL["pfdMax"]:
        errs.append(f"PFD {pfd:.3f} МГц вне {PLL['pfdMin']}..{PLL['pfdMax']}")
    if not PLL["vcoMin"] <= vco <= PLL["vcoMax"]:
        errs.append(f"VCO {vco:.3f} МГц вне {PLL['vcoMin']}..{PLL['vcoMax']}")
    if not PLL["outMin"] <= fout <= PLL["outMax"]:
        errs.append(f"CLKOUT {fout:.3f} МГц вне {PLL['outMin']}..{PLL['outMax']}")
    if odiv not in ODIV_SET:
        errs.append(f"ODIV_SEL {odiv} не из {ODIV_SET}")
    if not (0 <= idiv <= 63 and 0 <= fbdiv <= 63):
        errs.append("IDIV_SEL и FBDIV_SEL должны быть 0..63")
    return pfd, fout, vco, errs


def pll_solve(fin, target):
    """Минимальная ошибка частоты, затем наименьшие делители, затем наибольшая VCO."""
    best = None
    for idiv in range(64):
        pfd = fin / (idiv + 1)
        if not PLL["pfdMin"] <= pfd <= PLL["pfdMax"]:
            continue
        for fbdiv in range(64):
            fout = fin * (fbdiv + 1) / (idiv + 1)
            if not PLL["outMin"] <= fout <= PLL["outMax"]:
                continue
            odivs = [o for o in ODIV_SET if PLL["vcoMin"] <= fout * o <= PLL["vcoMax"]]
            if not odivs:
                continue
            key = (round(abs(fout - target), 9), idiv + fbdiv, -fout * odivs[-1])
            if best is None or key < best[0]:
                best = (key, idiv, fbdiv, odivs[-1])
    return best[1:] if best else None


def resolve_pll(m):
    c, p = m["clock"], m["clock"]["pll"]
    if p.get("mode", "auto") == "auto":
        r = pll_solve(float(c["xtalMHz"]), float(p["targetMHz"]))
        if r:
            p["idiv"], p["fbdiv"], p["odiv"] = r
    return pll_eval(float(c["xtalMHz"]), int(p["idiv"]), int(p["fbdiv"]), int(p["odiv"]))


# --- Частота шины периферии, UART, прерывания, стандарты выводов ---
def sysclk_hz(m):
    """Частота шины периферии (clk_dmem), Гц: выход rPLL; однотактное ядро с BSRAM делит её на 3.
    Та же формула, что CLK_DMEM_MHZ в top.sv, но без округления до МГц (для делителей UART)."""
    fout = resolve_pll(m)[1]
    core = m["core"]
    bsram = any((core.get(k) or {}).get("type", "bsram") == "bsram" for k in ("imem", "dmem"))
    div3 = core.get("coreType") == "singlecycle" and bsram
    return round(fout * 1e6 / (3 if div3 else 1))


def uart_div(m, u):
    """Делитель UART для скорости экземпляра: div, фактическая скорость, ошибка в %."""
    f, baud = sysclk_hz(m), int(u.get("baud", 115200))
    div = max(0, round(f / baud) - 1)
    real = f / (div + 1)
    return div, real, abs(real - baud) / baud * 100


def bsram_blocks(m):
    """Блоки BSRAM: IMEM и DMEM по 2 кБайт на блок, шрифт каждого TM1638 - один блок. (занято, всего)."""
    core = m["core"]
    used = sum(int((core.get(k) or {}).get("kb", 8)) // 2 for k in ("imem", "dmem")
               if (core.get(k) or {}).get("type", "bsram") == "bsram")
    return used + len(insts(m, "tm1638")), BSRAM_TOTAL


def irq_map(m):
    """Прерывания устройств: по умолчанию - источники PLIC 1, 2, ... в порядке списка периферии; по выбору
    (irq = "local") - локальные линии LI0, LI1, ...; irq = "none" - не подключено.
    Возвращает {имя экземпляра: ("plic", номер) | ("local", номер)}."""
    res, n_plic, n_loc = {}, 0, 0
    for inst in insts(m):
        if not TYPES[inst["type"]]["irq"]:
            continue
        route = inst.get("irq", "plic")
        if route == "plic":
            n_plic += 1
            res[inst["name"]] = ("plic", n_plic)
        elif route == "local":
            res[inst["name"]] = ("local", n_loc)
            n_loc += 1
    return res


def pin_attrs(m, dev, pin):
    """Стандарт вывода: собственные настройки вывода, иначе настройки его банка, иначе общие."""
    bank = str((dev["byNum"].get(pin) or {}).get("bank"))
    a = dict(m.get("ioDefaults", {}))
    a.update((m.get("banks") or {}).get(bank, {}))
    a.update({k: v for k, v in (m["pins"].get(str(pin)) or {}).items() if k != "net"})
    return a


def gpio_pins(m):
    """Выводы GPIO для прошивки: [(экземпляр, линия, вывод, цепь, имя в Си)]."""
    out = []
    for inst in insts(m, "gpio"):
        for i, pin in enumerate(inst.get("lines", [])):
            net = net_of(m, pin) if pin is not None else ""
            if net and NET_RE.match(net):
                out.append((inst, i, pin, net, c_name(net)))
    return out


# --- Проверка ---
def validate(m, dev):
    errors, warns = [], []

    #Имена экземпляров: идентификатор Си и SystemVerilog, уникальные без учёта регистра
    seen = {}
    for inst in insts(m):
        n, t = inst.get("name", ""), inst.get("type")
        if t not in TYPES:
            errors.append(f"{n}: неизвестный тип устройства «{t}»")
            continue
        if not NAME_RE.match(n):
            errors.append(f"Имя устройства «{n}»: латиница, цифры и _, не с цифры, до 24 символов")
            continue
        if n.lower() in seen:
            errors.append(f"Имя устройства «{n}» повторяется ({seen[n.lower()]})")
        seen[n.lower()] = n
        if n.upper() in RESERVED_C or n.lower() in RESERVED_NETS or n.lower() in SV_KEYWORDS:
            errors.append(f"Имя устройства «{n}» занято в прошивке или в top.sv")
        own = [k for k, v in TYPES.items() if v["title"] == n]
        if own and (own[0] != t or not first_of_type(m, inst)):
            errors.append(f"Имя «{n}» - имя типа {n}: его может носить только первый блок этого типа")
    if errors:
        return errors, warns, {}, {}

    sigs = signals(m)
    by_pin = {}
    for s in sigs:
        pin = s["pin"]
        if pin is None:
            errors.append(f"{s['name']}: вывод не назначен")
            continue
        p = dev["byNum"].get(pin)
        if not p or p["type"] != "io":
            errors.append(f"{s['name']}: вывод {pin} не является I/O")
            continue
        if m["core"].get("debug") and pin in JTAG_PINS:
            errors.append(f"{s['name']}: вывод {pin} занят JTAG ({JTAG_PINS[pin]})")
        by_pin.setdefault(pin, []).append(s)
    for pin, lst in by_pin.items():
        if len(lst) > 1:
            errors.append(f"Вывод {pin}: {', '.join(s['name'] for s in lst)} - конфликт")

    reserved = reserved_nets(m)
    nets, buses = {}, {}
    for pin in by_pin:
        net = net_of(m, pin)
        if not net:
            errors.append(f"Вывод {pin}: нет имени цепи")
            continue
        mm = NET_RE.match(net)
        if not mm or mm.group(1) in SV_KEYWORDS:
            errors.append(f"Вывод {pin}: имя «{net}» недопустимо для порта SystemVerilog")
            continue
        if mm.group(1) in reserved:
            errors.append(f"Вывод {pin}: имя «{mm.group(1)}» уже занято в top.sv - выберите другое")
            continue
        if net in nets:
            errors.append(f"Имя «{net}» у выводов {nets[net]} и {pin}")
        nets[net] = pin
        b = buses.setdefault(mm.group(1), dict(idx=[], scalar=False))
        if mm.group(2) is None:
            b["scalar"] = True
        else:
            b["idx"].append(int(mm.group(2)))
    for name, b in buses.items():
        if b["scalar"] and b["idx"]:
            errors.append(f"«{name}» используется и как шина, и как одиночный сигнал")
        if b["idx"]:
            miss = [i for i in range(max(b["idx"]) + 1) if i not in b["idx"]]
            if miss:
                errors.append(f"Шина «{name}[{max(b['idx'])}:0]»: нет разрядов {', '.join(map(str, miss))}")

    #Имена выводов GPIO в Си: <ИМЯ>_PIN, <ИМЯ>_PORT; шина - <ИМЯ>_MSK, <ИМЯ>_POS, <ИМЯ>_PORT
    cnames = {}
    for inst, i, pin, net, cn in gpio_pins(m):
        if cn in cnames and cnames[cn] != net:
            errors.append(f"Цепи «{cnames[cn]}» и «{net}» дают в Си одно имя {cn}_PIN")
        cnames[cn] = net
    bus_port = {}
    for inst, i, pin, net, cn in gpio_pins(m):
        mm = NET_RE.match(net)
        if mm.group(2) is not None:
            bus_port.setdefault(mm.group(1), set()).add(inst["name"])
    for bname, ports in bus_port.items():
        if len(ports) > 1:
            warns.append(f"Шина «{bname}» на разных GPIO ({', '.join(sorted(ports))}): {bname.upper()}_MSK в soc.h не создаётся")

    #Банк: одно напряжение VCCIO на все выводы (иначе Gowin EDA остановит размещение)
    bank_v = {}
    for pin in by_pin:
        p = dev["byNum"].get(pin)
        if p and p.get("bank") is not None:
            bank_v.setdefault(p["bank"], {}).setdefault(pin_attrs(m, dev, pin).get("vccio", "1.8"), []).append(pin)
    for bank, vs in sorted(bank_v.items()):
        if len(vs) > 1:
            errors.append(f"Банк {bank}: разные BANK_VCCIO - " +
                          "; ".join(f"{v} В у выводов {', '.join(map(str, sorted(ps)))}" for v, ps in vs.items()))

    #Ядро
    core = m["core"]
    if core.get("coreType", "pipeline") not in ("pipeline", "singlecycle"):
        errors.append("Ядро: тип pipeline или singlecycle")
    if int(core.get("divBpc", 2)) not in (1, 2, 4):
        errors.append("Ядро: бит частного за такт (divBpc) - 1, 2 или 4")
    for k in ("imem", "dmem"):
        mm_ = core.get(k) or {}
        if mm_.get("type", "bsram") == "bsram" and int(mm_.get("kb", 8)) not in MEM_KB:
            errors.append(f"Ядро: {k.upper()} в BSRAM - 8, 16 или 32 кБайт")
    nsrc = int(core.get("plicSources", 8))
    if not 1 <= nsrc <= 31:
        errors.append("Ядро: источников PLIC 1..31")
    used, total = bsram_blocks(m)
    if used > total:
        errors.append(f"BSRAM: нужно {used} блоков, в ПЛИС {total} - уменьшите IMEM/DMEM")
    if not core.get("mExt", True):
        warns.append("Ядро без расширения M: в настройках проекта Eclipse замените -march=rv32im_zicsr на rv32i_zicsr")

    #Прерывания устройств
    irqs = irq_map(m)
    used_plic = [n for r, n in irqs.values() if r == "plic"]
    if used_plic and max(used_plic) > nsrc:
        errors.append(f"PLIC: устройствам нужно {max(used_plic)} источников, а в ядре {nsrc} - увеличьте число источников PLIC")
    if sum(1 for r, _ in irqs.values() if r == "local") > 16:
        errors.append("Локальных линий прерываний всего 16")

    #Настройки устройств
    for inst in insts(m):
        n = inst["name"]
        if inst["type"] == "gpio":
            if not inst.get("lines"):
                errors.append(f"{n}: нет ни одной линии")
            elif len(inst["lines"]) > 32:
                errors.append(f"{n}: не больше 32 линий")
        if inst["type"] == "stim" and int(inst.get("width", 16)) not in (16, 32):
            errors.append(f"{n}: разрядность 16 или 32")
        if inst["type"] == "uart":
            if inst.get("parity", "none") not in UART_PARITY:
                errors.append(f"{n}: чётность none, even или odd")
            if int(inst.get("stop", 1)) not in (1, 2):
                errors.append(f"{n}: стоп-битов 1 или 2")
            if int(inst.get("fifo", 16)) not in FIFO_DEPTHS:
                errors.append(f"{n}: глубина FIFO 8, 16 или 32")
            div, real, err = uart_div(m, inst)
            if div < 7 or div > 0xFFFF:
                errors.append(f"{n}: скорость {inst.get('baud')} при частоте {sysclk_hz(m)} Гц не получить (div = {div}, нужно 7..65535)")
            elif err > 2.0:
                errors.append(f"{n}: ошибка скорости {err:.2f} % (фактически {real:.0f} бит/с) - больше 2 %")
            elif err > 1.0:
                warns.append(f"{n}: ошибка скорости {err:.2f} % (фактически {real:.0f} бит/с)")

    po = str((m.get("build") or {}).get("placeOption", ""))
    if po and po not in PLACE_OPTIONS:
        errors.append(f"Place_Option: 0, 1 или 2 (сейчас «{po}»)")

    xp = m["clock"].get("xtalPin")
    if xp in dev["byNum"] and not re.search(r"GCLK|PLL_T_IN", dev["byNum"][xp].get("cfg", "")):
        warns.append(f"Кварц на выводе {xp} без GCLK/PLL_IN: такт пойдёт по обычной трассировке")
    errors += ["rPLL: " + e for e in resolve_pll(m)[3]]
    bases = address_map(m, errors)
    return errors, warns, by_pin, bases


# ============================================================================================
# Генерация
# ============================================================================================
def ports_of(m, sigs):
    """Порты top: имя -> направление и разрядность; порядок - по первому появлению."""
    ports = {}
    for s in sigs:
        mm = NET_RE.match(net_of(m, s["pin"]))
        name, idx = mm.group(1), mm.group(2)
        p = ports.setdefault(name, dict(dirs=set(), width=None, pins=[]))
        p["dirs"].add(s["dir"])
        p["pins"].append((None if idx is None else int(idx), s["pin"]))
        if idx is not None:
            p["width"] = max(p["width"] or 0, int(idx) + 1)
    for p in ports.values():
        p["dir"] = next(iter(p["dirs"])) if len(p["dirs"]) == 1 else "inout"
    return ports


def compress_bits(items):
    """Подряд идущие разряды одной шины (от старшего к младшему) - одним диапазоном: led[5:0]."""
    out = []
    for it in items:
        mm = NET_RE.match(it)
        if out and mm.group(2) is not None:
            prev = out[-1]
            if prev[0] == mm.group(1) and prev[2] - 1 == int(mm.group(2)):
                prev[2] = int(mm.group(2))
                continue
        out.append([mm.group(1), None if mm.group(2) is None else int(mm.group(2)),
                    None if mm.group(2) is None else int(mm.group(2))])
    res = []
    for name, hi, lo in out:
        res.append(name if hi is None else (f"{name}[{hi}]" if hi == lo else f"{name}[{hi}:{lo}]"))
    return res


def fmt_mhz(x):
    return f"{x:.6f}".rstrip("0").rstrip(".")


def gen_top(m, bases, cfg_rel):
    c, core = m["clock"], m["core"]
    p = c["pll"]
    pfd, fout, vco, _ = resolve_pll(m)
    sigs = [s for s in signals(m) if s["pin"] is not None]
    ports = ports_of(m, sigs)
    net = {s["id"]: net_of(m, s["pin"]) for s in sigs}

    L = []
    w = L.append
    w("//==============================================================================================")
    w("// top.sv - ВЕРХНИЙ УРОВЕНЬ askoRV32. ФАЙЛ СОЗДАН КОНФИГУРАТОРОМ ПЛИС - НЕ РЕДАКТИРУЙТЕ ВРУЧНУЮ.")
    w(f"// Источник: {cfg_rel}; генератор: sw/socgen/socgen.py (кнопка «Собрать» в Eclipse).")
    w("// Процессор (ядро, память, отладчик, CLINT, PLIC) - в cpu.sv, он правится вручную; здесь -")
    w("// параметры платы для cpu и пользовательская периферия на его порту bus_per.")
    w("//==============================================================================================")
    w("")
    coretype = 1 if core.get("coreType") == "singlecycle" else 0
    im, dm = core.get("imem", {}), core.get("dmem", {})
    xtal = float(c["xtalMHz"])
    params = [
        ("//Ядро", None, None),
        ("bit", "CORE_TYPE", f"{coretype}", "1 - однотактное, 0 - конвейерное"),
        ("bit", "M_EXT", f"{1 if core.get('mExt', True) else 0}", "расширение M"),
        ("int", "DIV_BPC", f"{core.get('divBpc', 2)}", "бит частного за такт: 1, 2, 4"),
        ("//Память команд и данных", None, None),
        ("bit", "IMEM_TYPE", f"{1 if im.get('type', 'bsram') == 'bsram' else 0}", "1 - BSRAM, 0 - синтезированная"),
        ("int", "BSRAM_IMEM_SIZE", f"{im.get('kb', 8)}", "кБайт: 8/16/32"),
        ("int", "SYNTH_IMEM_SIZE", f"{im.get('synthWords', 256)}", "слов по 4 Байт"),
        ("", "IMEM_INIT_FILE", json.dumps(im.get("init", "mem_init/i.mem")), None),
        ("bit", "DMEM_TYPE", f"{1 if dm.get('type', 'bsram') == 'bsram' else 0}", "1 - BSRAM, 0 - синтезированная"),
        ("int", "BSRAM_DMEM_SIZE", f"{dm.get('kb', 8)}", "кБайт: 8/16/32"),
        ("int", "SYNTH_DMEM_SIZE", f"{dm.get('synthWords', 256)}", "слов по 4 Байт"),
        ("", "DMEM_INIT_FILE", json.dumps(dm.get("init", "mem_init/d.mem")), None),
        ("//Отладка и прерывания", None, None),
        ("bit", "DEBUG_EN", f"{1 if core.get('debug', True) else 0}", "модуль отладки JTAG (выводы 5-8)"),
        ("int", "PLIC_SOURCES", f"{core.get('plicSources', 8)}", "источников PLIC (1..31)"),
        (f"//Тактирование: кварц {fmt_mhz(xtal)} МГц, rPLL -> {fmt_mhz(fout)} МГц (PFD {fmt_mhz(pfd)}, VCO {fmt_mhz(vco)} МГц)", None, None),
        ("", "FCLKIN", json.dumps(fmt_mhz(xtal)), "частота кварца, МГц (строка для rPLL)"),
        ("int", "XTAL_KHZ", f"{round(xtal * 1000)}", "частота кварца, кГц"),
        ("int", "PLL_IDIV_SEL", f"{p['idiv']}", None),
        ("int", "PLL_FBDIV_SEL", f"{p['fbdiv']}", None),
        ("int", "PLL_ODIV_SEL", f"{p['odiv']}", None),
    ]
    items = [x for x in params if x[1] is not None]
    w("module top #(")
    for x in params:
        if x[1] is None:
            w(f"                {x[0]}")
            continue
        typ, name, val, com = x
        last = x is items[-1]
        decl = f"             parameter {typ + ' ' if typ else ''}{name}".ljust(45) + f"= {val}{')' if last else ','}"
        w(decl + (f" //{com}" if com else ""))

    # --- Порты: по группам - такт и сброс, затем устройства в порядке списка ---
    w("   (")
    group_of_port = {}
    for s in sigs:
        group_of_port.setdefault(NET_RE.match(net_of(m, s["pin"])).group(1), s["inst"]["name"] if s["inst"] else None)
    groups = [("Такт и сброс", None)] + [(inst_title(i), i["name"]) for i in insts(m)]
    entries = []
    for title, key in groups:
        names = [n for n in ports if group_of_port.get(n) == key]
        if not names:
            continue
        entries.append(("//" + title, None))
        for n in names:
            pr = ports[n]
            rng = f"[{pr['width'] - 1}:0] " if pr["width"] else ""
            pins = ", ".join(str(pn) for _, pn in sorted(pr["pins"], key=lambda t: -1 if t[0] is None else t[0]))
            entries.append((f"{pr['dir'] + ' wire':<12} {rng:<7}{n}", f"//вывод{'ы' if len(pr['pins']) > 1 else ''} {pins}"))
    last = max(i for i, e in enumerate(entries) if e[1] is not None)
    for i, (decl, com) in enumerate(entries):
        if com is None:
            w("    " + decl)
        else:
            w("    " + f"{decl}{'' if i == last else ','}".ljust(42) + com)
    debug = bool(core.get("debug", True))
    if debug:
        w("`ifndef GWSOC_NO_JTAG_PINS")
        w("    //Выводы JTAG ПЛИС: для примитива GW_JTAG (отладчик), назначения в .cst не требуются")
        w("   ,input  logic        tck_pad_i, tms_pad_i, tdi_pad_i,")
        w("    output logic        tdo_pad_o")
        w("`endif")
    w(");")
    if debug:
        w("`ifdef GWSOC_NO_JTAG_PINS")
        w("    //Сборка без выводов JTAG (apicula не поддерживает GW_JTAG для GW1N-9C, DEBUG_EN = 0)")
    else:
        w("    //Отладчик выключен (core.debug = false): выводы JTAG остаются за ПЛИС")
    w("    logic tck_pad_i = 1'b0, tms_pad_i = 1'b1, tdi_pad_i = 1'b0;")
    w("    logic tdo_pad_o;")
    if debug:
        w("`endif")

    # --- Карта адресов пользовательской периферии ---
    order = [i for i in insts(m) if i["name"] in bases]
    w("    //#1 Карта адресов пользовательской периферии: у каждого устройства окно 16 МБайт (маска 0xFF00_0000).")
    w("    //Системные окна - в cpu.sv: IMEM 0x0000_0000, CLINT 0x0200_0000, PLIC 0x0C00_0000, DMEM 0x1000_0000;")
    w("    //0x1F00_0000 - устройства тестбенча. Всё вне системных окон cpu отдаёт на порт bus_per")
    bw = max([12] + [len(i["name"]) + 6 for i in order])
    for i in order:
        w(f"    localparam logic [31:0] {i['name'].upper() + '_BASE':<{bw}}= {slot_hex(bases[i['name']])};")
    w(f"    localparam logic [31:0] {'WIN_MASK':<{bw}}= 32'hFF00_0000;")
    w("")
    w("    //Частота шины периферии (clk_per), МГц, целая часть: для делителей периферии (TM1638).")
    w("    //Однотактное ядро с BSRAM делит базовую частоту на 3. Прошивке то же значение задаёт SYSCLK_HZ.")
    w("    localparam int CLK_BASE_MHZ = XTAL_KHZ * (PLL_FBDIV_SEL + 1) / (PLL_IDIV_SEL + 1) / 1000;")
    w("    localparam int CLK_DMEM_MHZ = ((IMEM_TYPE | DMEM_TYPE) & CORE_TYPE) ? CLK_BASE_MHZ / 3 : CLK_BASE_MHZ;")
    w("")

    # --- Процессор ---
    w("    //#2 Процессор (cpu.sv): такт, сброс, ядро, отладчик, память команд и данных, CLINT, PLIC.")
    w("    //Параметры платы переопределяют значения по умолчанию из cpu.sv")
    w("    logic        clk_per, rst_per;")
    w("    logic [ 3:0] bus_per_Write;")
    w("    logic        bus_per_Read;")
    w("    logic [31:0] bus_per_Addr, bus_per_WData, bus_per_RData;")
    w("    logic [15:0] irq_local;")
    w("    logic [PLIC_SOURCES:1] irq_src;")
    w("")
    w("    cpu #(.CORE_TYPE(CORE_TYPE), .M_EXT(M_EXT), .DIV_BPC(DIV_BPC),")
    w("          .IMEM_TYPE(IMEM_TYPE), .BSRAM_IMEM_SIZE(BSRAM_IMEM_SIZE), .SYNTH_IMEM_SIZE(SYNTH_IMEM_SIZE), .IMEM_INIT_FILE(IMEM_INIT_FILE),")
    w("          .DMEM_TYPE(DMEM_TYPE), .BSRAM_DMEM_SIZE(BSRAM_DMEM_SIZE), .SYNTH_DMEM_SIZE(SYNTH_DMEM_SIZE), .DMEM_INIT_FILE(DMEM_INIT_FILE),")
    w("          .DEBUG_EN(DEBUG_EN), .PLIC_SOURCES(PLIC_SOURCES),")
    w("          .FCLKIN(FCLKIN), .PLL_IDIV_SEL(PLL_IDIV_SEL), .PLL_FBDIV_SEL(PLL_FBDIV_SEL), .PLL_ODIV_SEL(PLL_ODIV_SEL))")
    w("        cpu (.clk(" + net["clk"] + "), .rst_n(" + net["rst"] + "),")
    w("             .tck_pad_i(tck_pad_i), .tms_pad_i(tms_pad_i), .tdi_pad_i(tdi_pad_i), .tdo_pad_o(tdo_pad_o),")
    w("             .clk_per(clk_per), .rst_per(rst_per),")
    w("             .bus_per_Write(bus_per_Write), .bus_per_Read(bus_per_Read), .bus_per_Addr(bus_per_Addr), .bus_per_WData(bus_per_WData), .bus_per_RData(bus_per_RData),")
    w("             .irq_local(irq_local), .irq_src(irq_src));")
    w("")

    # --- Шина пользовательской периферии ---
    n = len(order)
    if n:
        pre = [hdl(i) for i in order]
        cat = lambda suf: "{" + ", ".join(f"{h}_{suf}" for h in pre) + "}"
        w(f"    //#3 Шина пользовательской периферии (memmux): ведомые перечислены от старшего номера к младшему")
        w(f"    logic [ 3:0] {', '.join(h + '_Write' for h in pre)};")
        w(f"    logic [31:0] {', '.join(h + '_Addr' for h in pre)};")
        w(f"    logic [31:0] {', '.join(h + '_WriteData' for h in pre)};")
        w(f"    logic [31:0] {', '.join(h + '_ReadData' for h in pre)};")
        w(f"    logic [{n - 1:>2}:0] sRead;")
        w("")
        w(f"    memmux #(.MEMORY_TYPE(DMEM_TYPE), .SLAVES({n}),")
        w("              .MATCH_ADDR ({" + ", ".join(i["name"].upper() + "_BASE" for i in order) + "}),")
        w(f"              .MATCH_MASK ({{{n}{{WIN_MASK}}}}))")
        w("            permux")
        w("             (.clk(clk_per), .rst(rst_per),")
        w("              .mWrite(bus_per_Write), .mRead(bus_per_Read), .mAddr(bus_per_Addr), .mWData(bus_per_WData), .mRData(bus_per_RData),")
        w(f"              .sWrite({cat('Write')}),")
        w("              .sRead (sRead),")
        w(f"              .sAddr ({cat('Addr')}),")
        w(f"              .sWData({cat('WriteData')}),")
        w(f"              .sRData({cat('ReadData')}));")
    else:
        w("    //#3 Пользовательской периферии нет: обращения к порту bus_per читаются как 0")
        w("    assign bus_per_RData = 32'd0;")
    w("")

    num = 1
    for idx, inst in enumerate(order):
        h, name, t = hdl(inst), inst["name"], inst["type"]
        base = slot_hex(bases[name])
        bus = f".Write({h}_Write), .Addr({h}_Addr), .WData({h}_WriteData), .RData({h}_ReadData)"
        if t == "gpio":
            lines = inst["lines"]
            io = ", ".join(compress_bits([net[f"{name}.line{i}"] for i in reversed(range(len(lines)))]))
            w(f"    //-{num}- {inst_title(inst)}: {len(lines)} лин., регистры с {base} (линия 0 - младший разряд)")
            w(f"    gpio_top #(.MEMORY_TYPE(DMEM_TYPE), .WIDTH({len(lines)})) {h}")
            w("              (.clk(clk_per), .rst(rst_per),")
            w(f"               {bus},")
            w(f"               .io_ports({{{io}}}));")
        elif t == "tm1638":
            w(f"    //-{num}- {inst_title(inst)}: внешний модуль LED&KEY, регистры с {base}")
            w(f"    tm1638_top #(.MEMORY_TYPE(DMEM_TYPE), .CLK_MHZ(CLK_DMEM_MHZ)) {h}")
            w("                (.clk(clk_per), .rst(rst_per),")
            w(f"                 {bus},")
            w(f"                 .tm_dio({net[name + '.dio']}), .tm_clk({net[name + '.clk']}), .tm_stb({net[name + '.stb']}));")
        elif t == "stim":
            out = net.get(f"{name}.out", "")
            w(f"    //-{num}- {inst_title(inst)}: простой таймер ({inst.get('width', 16)} бит), регистры с {base}")
            w(f"    logic irq_{h};")
            w(f"    stim_top #(.MEMORY_TYPE(DMEM_TYPE), .WIDTH({inst.get('width', 16)})) {h}")
            w("                (.clk(clk_per), .rst(rst_per),")
            w(f"                 {bus},")
            w(f"                 .tim_out({out}), .irq(irq_{h}));" + ("" if out else "   //выход ШИМ не выведен"))
        elif t == "uart":
            div, real, err = uart_div(m, inst)
            par = UART_PARITY[inst.get("parity", "none")]
            rd = n - 1 - idx          #Строб чтения: rxdata забирает байт из FIFO
            w(f"    //-{num}- {inst_title(inst)}: {inst.get('baud', 115200)} бит/с (div {div}, фактически {real:.0f}, ошибка {err:.2f} %), "
              f"чётность {inst.get('parity', 'none')}, стоп-битов {inst.get('stop', 1)}, FIFO {inst.get('fifo', 16)}")
            w(f"    //    регистры с {base}")
            w(f"    logic irq_{h};")
            w(f"    uart_top #(.MEMORY_TYPE(DMEM_TYPE), .DEPTH({inst.get('fifo', 16)}), .DIV_INIT({div}), "
              f".STOP_INIT({inst.get('stop', 1)}), .PARITY_INIT({par})) {h}")
            w("                (.clk(clk_per), .rst(rst_per),")
            w(f"                 .Write({h}_Write), .Read(sRead[{rd}]), .Addr({h}_Addr), .WData({h}_WriteData), .RData({h}_ReadData),")
            w(f"                 .tx({net[name + '.tx']}), .rx({net[name + '.rx']}), .irq(irq_{h}));")
        w("")
        num += 1

    # --- Прерывания: по умолчанию - в PLIC, по выбору - на локальную линию ---
    irqs = irq_map(m)
    nsrc = int(core.get("plicSources", 8))
    by_name = {i["name"]: i for i in insts(m)}
    plic = {n_: f"irq_{hdl(by_name[k])}" for k, (r, n_) in irqs.items() if r == "plic"}
    loc = {n_: f"irq_{hdl(by_name[k])}" for k, (r, n_) in irqs.items() if r == "local"}
    w(f"    //-{num}- Прерывания периферии: источники PLIC (MEI, векторный режим) и локальные линии LI0..LI15")
    for k, (r, n_) in irqs.items():
        w(f"    //    {k}: " + (f"источник PLIC {n_}" if r == "plic" else f"LI{n_} (mcause {16 + n_})"))
    if not irqs:
        w("    //    устройств с прерываниями нет")
    src_bits = ", ".join(plic.get(i, "1'b0") for i in range(nsrc, 0, -1))
    w(f"    assign irq_src   = {{{src_bits}}};   //старший разряд - источник {nsrc}, младший - источник 1")
    if loc:
        loc_bits = ", ".join(loc.get(i, "1'b0") for i in range(15, -1, -1))
        w(f"    assign irq_local = {{{loc_bits}}};   //старший разряд - LI15")
    else:
        w("    assign irq_local = 16'd0;")
    w("endmodule")
    return "\n".join(L) + "\n"


def gen_cst(m, dev, cfg_rel):
    sigs = [s for s in signals(m) if s["pin"] is not None]
    L = [
        "//Physical Constraints file",
        "//Part Number: " + m.get("device", dev["part"]),
        "//Device: GW1NR-9",
        "//Device Version: C",
        f"//ФАЙЛ СОЗДАН КОНФИГУРАТОРОМ ПЛИС (sw/socgen/socgen.py) из {cfg_rel} - не редактируйте вручную.",
        "",
    ]
    for s in sigs:
        net = net_of(m, s["pin"])
        a = pin_attrs(m, dev, s["pin"])
        attrs = [f"IO_TYPE={a.get('ioType', 'LVCMOS18')}", f"PULL_MODE={a.get('pull', 'UP')}"]
        if s["dir"] != "input":
            attrs.append(f"DRIVE={a.get('drive', '8')}")
        attrs.append(f"BANK_VCCIO={a.get('vccio', '1.8')}")
        L.append(f'IO_LOC "{net}" {s["pin"]};')
        L.append(f'IO_PORT "{net}" {" ".join(attrs)};')
    return "\n".join(L) + "\n"


def cdef(name, value, comment=""):
    """#define с выравниванием табуляцией, как в остальных заголовках прошивки."""
    s = f"#define {name}"
    tabs = max(1, (40 - len(s) + 3) // 4)
    s += "\t" * tabs + value
    if comment:
        s += "\t\t//" + comment
    return s


def gen_soc_h(m, bases, cfg_rel):
    """fw/Core/Inc/soc.h - что прошивке нужно знать о собранной ПЛИС."""
    core = m["core"]
    im, dm = core.get("imem", {}), core.get("dmem", {})
    memb = lambda x: int(x.get("kb", 8)) * 1024 if x.get("type", "bsram") == "bsram" else int(x.get("synthWords", 256)) * 4
    L = []
    w = L.append
    w("/*")
    w(" *****************************************************************************************")
    w(" * @file        soc.h")
    w(" * @device      AskoRV32")
    w(f" * @brief       ФАЙЛ СОЗДАН КОНФИГУРАТОРОМ ПЛИС (sw/socgen/socgen.py) из {cfg_rel} - не редактируйте вручную.")
    w(" *              Частота, устройства (адреса, указатели, настройки), прерывания периферии и имена")
    w(" *              выводов GPIO собранной ПЛИС. Типы регистров - в заголовках драйверов (gpio.h, uart.h, plic.h...).")
    w(" *****************************************************************************************")
    w(" */")
    w("#ifndef __SOC_H")
    w("#define __SOC_H")
    w("")
    w("/* Ядро и память */")
    w(cdef("SOC_CORE_PIPELINE", str(0 if core.get('coreType') == 'singlecycle' else 1), "1 - конвейерное, 0 - однотактное"))
    w(cdef("SOC_M_EXT", str(1 if core.get('mExt', True) else 0), "Расширение M (mul/div)"))
    w(cdef("SOC_DEBUG", str(1 if core.get('debug', True) else 0), "Отладчик JTAG"))
    w(cdef("SOC_IMEM_BYTES", f"{memb(im)}U"))
    w(cdef("SOC_DMEM_BYTES", f"{memb(dm)}U"))
    w("")
    w("/* Частота шины периферии (clk_per), Гц: от неё считают таймер STIM, UART и mtime в CLINT */")
    w(cdef("SYSCLK_HZ", f"{sysclk_hz(m)}U"))
    w("")
    w("/* Системные устройства процессора (cpu.sv): адреса и указатели; типы регистров - в clint.h и plic.h */")
    w(cdef("CLINT_BASE", f"(0x{FIXED_REGIONS['CLINT'] * 0x01000000:08X}U)"))
    w(cdef("CLINT", "((CLINT_TypeDef*) CLINT_BASE)"))
    w(cdef("PLIC_BASE", f"(0x{FIXED_REGIONS['PLIC'] * 0x01000000:08X}U)"))
    w(cdef("PLIC", "((PLIC_TypeDef*) PLIC_BASE)"))
    w("")
    w("/* Устройства. <ТИП>_PRESENT - есть ли в ПЛИС блоки типа, <ТИП>_COUNT - сколько их.")
    w("   Для каждого блока: <ИМЯ>_BASE - адрес регистров, <ИМЯ> - указатель на регистры, настройки <ИМЯ>_xxx.")
    w("   Драйверы (gpio.c, uart.c...) работают с первым блоком типа под именем типа (GPIO, UART...) */")
    for t, meta in TYPES.items():
        cnt = len(insts(m, t))
        w(cdef(f"{meta['title']}_PRESENT", "1" if cnt else "0"))
        w(cdef(f"{meta['title']}_COUNT", f"{cnt}U"))
    for inst in insts(m):
        t, N = inst["type"], inst["name"]
        T = TYPES[t]["title"]
        w("")
        w(f"/* {inst_title(inst)} */")
        w(cdef(f"{N}_BASE", f"(0x{bases[N] * 0x01000000:08X}U)"))
        w(cdef(N, f"(({T}_TypeDef*) {N}_BASE)"))
        params = []
        if t == "gpio":
            params.append(("WIDTH", f"{len(inst.get('lines', []))}U", "Число линий"))
        if t == "stim":
            params.append(("WIDTH", f"{inst.get('width', 16)}U", "Разрядность PR, PER, PUL, CNT"))
        if t == "uart":
            div, real, err = uart_div(m, inst)
            params += [("BAUD", f"{int(inst.get('baud', 115200))}U", f"Скорость по умолчанию, бит/с (div {div}, ошибка {err:.2f} %)"),
                       ("PARITY_DEFAULT", str(UART_PARITY[inst.get('parity', 'none')]), "0 - нет, 1 - even, 2 - odd"),
                       ("STOP_DEFAULT", str(int(inst.get('stop', 1))), "Стоп-битов"),
                       ("FIFO_DEPTH", f"{int(inst.get('fifo', 16))}U", "Глубина FIFO приёма и передачи")]
        for suf, val, com in params:
            w(cdef(f"{N}_{suf}", val, com))
        #Первый блок типа под другим именем: имена типа для драйверов - его синонимы
        if first_of_type(m, inst) and N != T:
            w(cdef(f"{T}_BASE", f"{N}_BASE", "Драйверы: первый блок типа"))
            w(cdef(T, N))
            for suf, _, _ in params:
                w(cdef(f"{T}_{suf}", f"{N}_{suf}"))
    w("")
    irqs = irq_map(m)
    w("/* Прерывания периферии. Источники PLIC (векторный режим, start.S): обработчик источника S -")
    w("   PLIC_SRCS_IRQHandler; ниже - понятные имена. Локальные линии: LIn_IRQHandler, номер LIn_IRQn */")
    w(cdef("PLIC_NUM_SOURCES", f"{int(core.get('plicSources', 8))}U"))
    plic = [(n_, k) for k, (r, n_) in irqs.items() if r == "plic"]
    w("typedef enum")
    w("{")
    if plic:
        for i, (n_, k) in enumerate(plic):
            w(f"  PLIC_SRC_{k} = {n_}{',' if i < len(plic) - 1 else ''}\t\t//{k}")
    else:
        w("  PLIC_SRC_NONE = 0")
    w("} PLIC_SRC_Type;")
    for n_, k in plic:
        w(cdef(f"PLIC_{k}_IRQHandler", f"PLIC_SRC{n_}_IRQHandler"))
    for k, (r, n_) in irqs.items():
        if r == "local":
            w(cdef(f"{k}_IRQn", f"LI{n_}_IRQn", f"{k} - локальная линия LI{n_}"))
            w(cdef(f"{k}_IRQHandler", f"LI{n_}_IRQHandler"))
    w("")
    #Выводы GPIO: имена цепей из конфигуратора
    gp = gpio_pins(m)
    w("/* Выводы GPIO: имя цепи из конфигуратора -> <ИМЯ>_PIN (номер линии) и <ИМЯ>_PORT (блок GPIO);")
    w("   цепь LED[3] даёт имя LED3. Шина (LED[0], LED[1]...) на одном блоке: <ИМЯ>_MSK, <ИМЯ>_POS, <ИМЯ>_PORT.")
    w("   Работа по имени - макросы GPIO_WRITE(LED3, GPIO_PIN_SET), GPIO_READ(...), GPIO_MODE(...) в gpio.h */")
    if not gp:
        w("/* выводов GPIO нет */")
    for inst, i, pin, net, cn in gp:
        w(cdef(f"{cn}_PIN", f"{i}U", f"вывод {pin}, цепь {net}"))
        w(cdef(f"{cn}_PORT", inst["name"]))
    buses = {}
    for inst, i, pin, net, cn in gp:
        mm = NET_RE.match(net)
        if mm.group(2) is not None:
            buses.setdefault(mm.group(1), []).append((inst["name"], i, int(mm.group(2))))
    for bname, lst in buses.items():
        if len({p for p, _, _ in lst}) != 1:
            continue
        mask = 0
        for _, i, _ in lst:
            mask |= 1 << i
        pos = min(i for _, i, _ in lst)
        ordered = all(i == pos + idx for _, i, idx in lst)
        w(cdef(f"{bname.upper()}_MSK", f"0x{mask:08X}U", f"шина {bname}[{max(x for _, _, x in lst)}:0]" +
               ("" if ordered else ", разряды шины не подряд по линиям")))
        w(cdef(f"{bname.upper()}_POS", f"{pos}U"))
        w(cdef(f"{bname.upper()}_PORT", lst[0][0]))
    w("")
    w("#endif /* __SOC_H */")
    return "\n".join(L) + "\n"


def sync_sdc_clock(hw, net):
    """Ограничение такта кварца в riscv.sdc ссылается на порт top.sv - его имя задаёт конфигуратор (цепь вывода
    кварца). Генератор меняет в строке create_clock -name clk только имя порта; остальное правится вручную."""
    sdc = hw / "src" / "riscv.sdc"
    if not sdc.exists() or not net:
        return None
    t = sdc.read_bytes().decode("utf-8")
    new, n = re.subn(r"(create_clock\s+-name\s+clk\s[^\n]*\[get_ports\s*\{)([^}]*)(\}\])",
                     lambda mm: mm.group(1) + net + mm.group(3), t, count=1)
    if not n:
        print("Предупреждение: в riscv.sdc нет строки create_clock -name clk ... [get_ports {...}] - порт кварца не проверен")
        return None
    if new == t:
        return False
    sdc.write_bytes(new.encode("utf-8"))
    return True


def write_if_changed(path, text, enc="utf-8"):
    """Запись без смены времени файла, если содержимое то же (Gowin EDA и make не пересобирают зря).
    Файлы прошивки (cp1251) пишутся с CRLF, как весь проект Eclipse."""
    newline = "\r\n" if enc == "cp1251" else "\n"
    data = text.replace("\n", newline).encode(enc)
    if path.exists() and path.read_bytes() == data:
        return False
    path.write_bytes(data)
    return True


# ============================================================================================
# Сборка открытым маршрутом (Yosys + nextpnr-himbaechel + apicula)
# ============================================================================================
def gprj_sources(gprj):
    """Файлы Verilog из проекта Gowin EDA (riscv.gprj) - один список на оба маршрута."""
    root = ET.parse(gprj).getroot()
    out = []
    for f in root.iter("File"):
        if f.get("type") == "file.verilog" and f.get("enable") == "1":
            out.append((gprj.parent / f.get("path")).resolve())
    return out


def find_oss(arg):
    for cand in [arg, os.environ.get("OSS_CAD_SUITE"), "C:/oss-cad-suite"]:
        if cand and (Path(cand) / "bin").is_dir():
            return Path(cand)
    return None


def progress(pct, text):
    """Ход сборки для плагина Eclipse (строка не выводится в консоль, плагин показывает её полосой)."""
    print(f"@@PROGRESS {int(pct)} {text}", flush=True)


def run_tool(cmd, env, log, cwd, on_line=None):
    print("  $ " + " ".join(str(c) for c in cmd), flush=True)
    t0 = time.time()
    with open(log, "w", encoding="utf-8", errors="replace") as lf:
        p = subprocess.Popen([str(c) for c in cmd], cwd=cwd, env=env, stdout=subprocess.PIPE,
                             stderr=subprocess.STDOUT, text=True, encoding="utf-8", errors="replace")
        tail = []
        for line in p.stdout:
            lf.write(line)
            tail.append(line.rstrip())
            tail = tail[-40:]
            if on_line:
                on_line(line)
            if re.search(r"^(ERROR|Error)|error:|Warning: .*(latch|multiple drivers)|Max frequency for clock", line):
                print("    " + line.rstrip(), flush=True)
        p.wait()
    print(f"    ({time.time() - t0:.1f} с, журнал {log.name})", flush=True)
    if p.returncode != 0:
        print("\n".join("    | " + t for t in tail[-15:]))
        raise ConfigError(f"{Path(cmd[0]).stem} завершился с кодом {p.returncode}")


def build_oss(m, hw, cst, oss_arg, fmax_mhz):
    oss = find_oss(oss_arg)
    if not oss:
        raise ConfigError("Не найден OSS CAD Suite (C:/oss-cad-suite или переменная OSS_CAD_SUITE)")
    env = dict(os.environ)
    env["PATH"] = os.pathsep.join([str(oss / "bin"), str(oss / "lib"), env.get("PATH", "")])
    env["YOSYSHQ_ROOT"] = str(oss) + os.sep
    out = hw / "impl_oss"
    out.mkdir(exist_ok=True)
    srcs = gprj_sources(hw / "riscv.gprj")
    # Файлы в порядке проекта; slang разбирает их вместе (как один компилируемый блок)
    ys = out / "synth.ys"
    rel = [os.path.relpath(s, out).replace("\\", "/") for s in srcs]
    # Примитивы Gowin, которые встречаются в исходниках, - описания (* blackbox *) с параметрами из Yosys
    lib = [oss / "share" / "yosys" / "gowin" / f for f in ("cells_sim.v", "cells_xtra_gw1n.v")]
    src_text = "\n".join(s.read_text(encoding="utf-8", errors="replace") for s in srcs)
    prims = []
    for lf in lib:
        t = lf.read_text(encoding="utf-8", errors="replace")
        for mm in re.finditer(r"\(\*\s*blackbox\s*\*\)\s*module\s+(\w+)\b.*?endmodule", t, re.S):
            name = mm.group(1)
            if re.search(rf"^\s*{name}\s*(#|\w+\s*\()", src_text, re.M) and name not in [p_[0] for p_ in prims]:
                prims.append((name, mm.group(0)))
    (out / "gowin_prims.v").write_text("// Создано socgen.py: примитивы Gowin из библиотеки Yosys (" +
                                       ", ".join(n for n, _ in prims) + ")\n\n" +
                                       "\n\n".join(t for _, t in prims) + "\n", encoding="utf-8", newline="\n")
    # apicula 0.34 не умеет примитив GW_JTAG для GW1N-9C (только для GW2A-18C): сборка без отладчика
    defs = ""
    if m["core"].get("debug", True):
        print("Предупреждение: apicula не поддерживает GW_JTAG для GW1N-9C - отладчик в этой сборке выключен (DEBUG_EN=0)")
        defs = "-G DEBUG_EN=0 "
    ys.write_text(
        "# Создано socgen.py: синтез askoRV32 для GW1NR-9C открытым маршрутом\n"
        "# Примитивы Gowin (rPLL, SP, ...) остаются ячейками с параметрами - их знает synth_gowin\n"
        f"read_slang --top top --empty-blackboxes -D GWSOC_NO_JTAG_PINS {defs}gowin_prims.v " + " ".join(rel) + "\n"
        "# syn_ramstyle=\"distributed_ram\" - значение GowinSynthesis, Yosys его не знает: выбор памяти за ним\n"
        "setattr -unset syn_ramstyle a:syn_ramstyle\n"
        "# Этап map_luts (abc9) в сборке Yosys для Windows падает на assert в write_xaiger2 (aiger.cc),\n"
        "# поэтому LUT отображает классический abc, остальное - штатный сценарий synth_gowin\n"
        "synth_gowin -top top -run begin:map_luts\n"
        "abc -lut 4:8\n"
        "clean\n"
        "synth_gowin -top top -run map_cells: -json top.json\n"
        "tee -o utilization.txt stat\n", encoding="utf-8", newline="\n")
    print("Синтез (yosys + slang):", flush=True)
    progress(3, "Синтез (yosys)")
    run_tool([oss / "bin" / "yosys.exe", "-m", "slang", "-q", "-l", "yosys.log", "-s", "synth.ys"], env, out / "yosys.out", out)
    print("Размещение и трассировка (nextpnr-himbaechel):", flush=True)
    progress(40, "Размещение (nextpnr)")

    def pnr_line(line):
        if re.search(r"Info: (Running main analytical placer|Running placer|Starting placement)", line):
            progress(45, "Размещение (nextpnr)")
        elif re.search(r"Info: (Routing|Running router|Router1|Router2)", line):
            progress(70, "Трассировка (nextpnr)")
    run_tool([oss / "bin" / "nextpnr-himbaechel.exe", "--json", "top.json", "--write", "pnr.json",
              "--device", m.get("device", "GW1NR-LV9QN88PC6/I5"), "--vopt", "family=GW1N-9C",
              "--vopt", "cst=" + os.path.relpath(cst, out).replace("\\", "/"),
              "--freq", fmt_mhz(fmax_mhz), "--timing-allow-fail", "--report", "report.json"],
             env, out / "nextpnr.log", out, pnr_line)
    print("Битовый поток (apicula gowin_pack):", flush=True)
    progress(92, "Битовый поток (gowin_pack)")
    run_tool([oss / "bin" / "gowin_pack.exe", "-d", "GW1N-9C", "-o", "riscv.fs", "pnr.json"], env, out / "gowin_pack.log", out)
    fs = out / "riscv.fs"
    print(f"Готово: {os.path.relpath(fs, hw.parent)} ({fs.stat().st_size} Байт)")
    rep = out / "report.json"
    if rep.exists():
        r = json.loads(rep.read_text(encoding="utf-8"))
        util = r.get("utilization") or {}
        used = [f"{k} {util[k]['used']}/{util[k]['available']}" for k in
                ("LUT4", "ALU", "DFF", "RAM16SDP4", "BSRAM", "MULT36X36", "MULT18X18", "rPLL") if k in util]
        io = sum(util[k]["used"] for k in ("IOB", "IOBUF") if k in util)   #IOBUF (inout) apicula считает отдельно
        used.append(f"выводов {io}")
        print("  Ресурсы: " + ", ".join(used))
        u = lambda k: util.get(k, {}).get("used", 0)
        a = lambda k: util.get(k, {}).get("available", 0)
        save_resources(hw, "apicula", {
            "lut": [u("LUT4") + u("ALU"), a("LUT4")], "reg": [u("DFF"), a("DFF")], "bsram": [u("BSRAM"), a("BSRAM")],
            "dsp": [u("MULT36X36") * 2 + u("MULT18X18"), a("MULT18X18") or 10], "io": [io, IO_USER_TOTAL],
            "pll": [u("rPLL"), a("rPLL") or 2]},
            {clk: v.get("achieved", 0) for clk, v in (r.get("fmax") or {}).items()})
        slow = []
        for clk, v in (r.get("fmax") or {}).items():
            ach, con = v.get("achieved", 0), v.get("constraint", 0)
            print(f"  Fmax {clk}: {ach:.1f} МГц (нужно {con:.1f}){'' if ach >= con else '  <-- НЕ ДОСТИГНУТО'}")
            if ach < con:
                slow.append(ach)
        if slow:
            fin = float(m["clock"]["xtalMHz"])
            best = None
            for idiv in range(64):
                for fbdiv in range(64):
                    f = fin * (fbdiv + 1) / (idiv + 1)
                    if f <= min(slow) and not pll_eval(fin, idiv, fbdiv, 16)[3] or \
                       f <= min(slow) and any(not pll_eval(fin, idiv, fbdiv, o)[3] for o in ODIV_SET):
                        best = max(best or 0, f)
            print(f"Предупреждение: открытый маршрут не держит {fmt_mhz(fmax_mhz)} МГц - битовый поток собран, "
                  f"но на плате при этой частоте возможны сбои." +
                  (f" Для apicula выберите в rPLL не больше {fmt_mhz(best)} МГц." if best else ""))


# ============================================================================================
# Сборка в Gowin EDA (gw_sh - командная строка IDE, проект hw/riscv.gprj)
# ============================================================================================
IO_USER_TOTAL = 71         #Пользовательских выводов I/O у GW1NR-9 в корпусе QN88 (как в отчёте Gowin)


def save_resources(hw, toolchain, items, fmax):
    """Занятые ресурсы последней сборки - для панели ресурсов конфигуратора (hw/impl/socgen/resources.json)."""
    d = hw / "impl" / "socgen"
    d.mkdir(parents=True, exist_ok=True)
    (d / "resources.json").write_text(json.dumps({
        "toolchain": toolchain, "time": time.strftime("%Y-%m-%d %H:%M"), "items": items, "fmax": fmax},
        ensure_ascii=False, indent=1), encoding="utf-8")


def find_gowin(arg):
    """Каталог IDE Gowin (в нём bin/gw_sh.exe): ключ --gowin, GOWIN_HOME, типовые места установки."""
    cands = [arg, os.environ.get("GOWIN_HOME")]
    for root in ("C:/Program Files/Gowin", "C:/Gowin", "D:/Gowin"):
        cands += sorted((str(p) for p in Path(root).glob("*")), reverse=True) if Path(root).is_dir() else []
    for c in cands:
        if not c:
            continue
        for ide in (Path(c), Path(c) / "IDE"):
            if (ide / "bin" / "gw_sh.exe").exists():
                return ide
    return None


def html_text(path):
    t = Path(path).read_text(encoding="utf-8", errors="replace")
    import html as _html
    return re.sub(r"\s+", " ", _html.unescape(re.sub(r"<[^>]+>", " ", t)))


def sdc_target_mhz(hw):
    """Цель такта ядра из riscv.sdc (МГц) или None."""
    sdc = hw / "src" / "riscv.sdc"
    if not sdc.exists():
        return None
    mm = re.search(r"create_clock\s+-name\s+clk_core\s+-period\s+([\d.]+)", sdc.read_text(encoding="utf-8"))
    return 1000.0 / float(mm.group(1)) if mm else None


def check_sdc_period(hw, fout):
    """riscv.sdc задаёт цель такта ядра вручную, выше рабочей частоты (50 МГц при 45 МГц от rPLL): с запасом
    по цели Gowin размещает лучше. Цель ниже рабочей частоты - ошибка настройки: анализ пропустит нарушения."""
    tgt = sdc_target_mhz(hw)
    if tgt is not None and tgt < fout * 0.999:
        print(f"Предупреждение: в riscv.sdc цель clk_core {tgt:.1f} МГц ниже рабочей частоты rPLL {fmt_mhz(fout)} МГц - "
              f"задайте period не больше {1000 / fout:.3f} нс (рекомендуется цель на ~10 % выше рабочей)")


def set_place_option(cfg, opt):
    """Place_Option из .gwsoc (build.placeOption) - в настройку процесса Gowin EDA. Файл правится заменой
    одного значения, остальное остаётся как его записала IDE."""
    if opt in (None, ""):
        return
    opt = str(opt)
    if not cfg.exists():
        print(f"Предупреждение: нет {cfg.name} - Place_Option {opt} не задан")
        return
    t = cfg.read_text(encoding="utf-8")
    new, n = re.subn(r'("Place_Option"\s*:\s*)"[^"]*"', lambda mm: f'{mm.group(1)}"{opt}"', t)
    if not n:
        print(f"Предупреждение: в {cfg.name} нет Place_Option - значение {opt} не задано")
        return
    if new != t:
        cfg.write_text(new, encoding="utf-8", newline="")
    print(f"  Place_Option = {opt} ({PLACE_OPTIONS.get(opt, '?')})")


def build_gowin(m, hw, gowin_arg, fout):
    ide = find_gowin(gowin_arg)
    if not ide:
        raise ConfigError("Не найден Gowin EDA (gw_sh.exe): укажите каталог IDE в переменной GOWIN_HOME или ключом --gowin")
    gprj = hw / "riscv.gprj"
    if not gprj.exists():
        raise ConfigError(f"Нет проекта Gowin {gprj}")
    check_sdc_period(hw, fout)
    impl = hw / "impl"
    impl.mkdir(exist_ok=True)
    set_place_option(impl / "riscv_process_config.json", (m.get("build") or {}).get("placeOption"))
    tcl = impl / "socgen_build.tcl"
    tcl.write_text("# Создано socgen.py: сборка проекта Gowin EDA из командной строки\n"
                   "open_project riscv.gprj\nrun all\n", encoding="utf-8", newline="\n")
    fs = impl / "pnr" / "riscv.fs"
    t0 = time.time()
    print(f"Синтез, размещение, трассировка и битовый поток (Gowin EDA, {ide.parent.name}):", flush=True)
    #Ход: синтез [x%] -> 5..45 %, размещение и трассировка [x%] -> 45..95 %, битовый поток и отчёты -> 95..100 %
    st = {"pnr": False}

    def gw_line(line):
        mm = re.match(r"\[(\d+)%\]", line)
        if line.startswith("Running parser"):
            progress(2, "Разбор исходников")
        elif "GowinSynthesis finish" in line:
            st["pnr"] = True
            progress(45, "Синтез завершён")
        elif line.startswith("Running placement"):
            st["pnr"] = True
            progress(46, "Размещение")
        elif line.startswith("Running routing"):
            progress(70, "Трассировка")
        elif line.startswith("Bitstream generation"):
            progress(96, "Битовый поток")
        elif mm:
            x = int(mm.group(1))
            if st["pnr"]:
                progress(45 + x * 0.5, "Размещение" if x <= 50 else "Трассировка" if x < 95 else "Анализ таймингов")
            else:
                progress(5 + x * 0.4, "Синтез")

    try:
        run_tool([ide / "bin" / "gw_sh.exe", os.path.relpath(tcl, hw)], dict(os.environ), impl / "socgen_gw_sh.log", hw, gw_line)
    except ConfigError:
        pass   #Код возврата gw_sh ненадёжен - итог определяется по ошибкам в журнале и файлу .fs
    log = (impl / "socgen_gw_sh.log").read_text(encoding="utf-8", errors="replace")
    errs = [l for l in log.splitlines() if l.startswith("ERROR")]
    if errs or not fs.exists() or fs.stat().st_mtime < t0:
        raise ConfigError(f"Gowin EDA: ошибок {len(errs)}, битовый поток не создан (журнал hw/impl/socgen_gw_sh.log)")
    print(f"Готово: {os.path.relpath(fs, hw.parent)} ({fs.stat().st_size} Байт)")
    rpt = impl / "pnr" / "riscv.rpt.txt"
    res = {}
    if rpt.exists():
        r = rpt.read_text(encoding="utf-8", errors="replace")
        used = []
        for k, key in (("Logic", "lut"), ("Register", "reg"), ("CLS", "cls"), ("BSRAM", "bsram"), ("DSP", "dsp"),
                       ("I/O Port", "io"), ("rPLL", "pll")):
            mm = re.search(rf"^\s*{re.escape(k)}\s*\|\s*(\d+)/(\d+)", r, re.M)
            if mm:
                if key != "pll":
                    used.append(f"{k} {mm.group(1)}/{mm.group(2)}")
                res[key] = [int(mm.group(1)), int(mm.group(2))]
        print("  Ресурсы: " + ", ".join(used))
    fmax = {}
    tr = impl / "pnr" / "riscv_tr_content.html"
    if tr.exists():
        t = html_text(tr)
        #Такт ядра проверяется по рабочей частоте rPLL: цель в riscv.sdc нарочно выше (50 МГц при 45), поэтому
        #отрицательный запас относительно цели - нормальное состояние
        core_ok = {}
        for name, con, ach in re.findall(r"\d+ (\S+) ([\d.]+)\(MHz\) ([\d.]+)\(MHz\) \d+ TOP", t):
            fmax[name] = float(ach)
            need = fout if name == "clk_core" else float(con)
            bad = float(ach) < need
            core_ok[name] = not bad
            extra = f", цель в riscv.sdc {float(con):.1f}" if name == "clk_core" else ""
            print(f"  Fmax {name}: {float(ach):.1f} МГц (нужно {need:.1f}{extra}){'  <-- НЕ ДОСТИГНУТО' if bad else ''}")
        tns = re.findall(r"(\S+) Setup (-[\d.]+) (\d+)", t)
        for name, v, n in tns:
            if name == "clk_core" and core_ok.get(name):
                continue    #Нарушение только относительно цели выше рабочей частоты
            print(f"Предупреждение: отрицательный запас по {name}: TNS {v} нс, путей {n} - см. hw/impl/pnr/riscv.tr.html")
    if res:
        save_resources(hw, "gowin", res, fmax)


# ============================================================================================
def main():
    ap = argparse.ArgumentParser(description="Генератор top.sv и riscv.cst для askoRV32 из файла .gwsoc")
    ap.add_argument("config", help="файл конфигурации .gwsoc")
    ap.add_argument("--check", action="store_true", help="только проверить, файлы не писать")
    ap.add_argument("--build", action="store_true", help="после генерации собрать проект ПЛИС")
    ap.add_argument("--toolchain", choices=["gowin", "apicula"],
                    help="чем собирать: gowin - Gowin EDA (gw_sh), apicula - Yosys + nextpnr + apicula "
                         "(по умолчанию - build.toolchain из .gwsoc, иначе gowin)")
    ap.add_argument("--gowin", help="каталог Gowin IDE (где bin/gw_sh.exe; по умолчанию GOWIN_HOME или C:/Program Files/Gowin/*)")
    ap.add_argument("--oss", help="каталог OSS CAD Suite (по умолчанию C:/oss-cad-suite)")
    a = ap.parse_args()

    cfg = Path(a.config).resolve()
    m = json.loads(cfg.read_text(encoding="utf-8"))
    for k, v in dict(core={}, clock={}, reset={}, pins={}, ioDefaults={}, paths={}).items():
        m.setdefault(k, v)
    migrate(m)
    m["clock"].setdefault("pll", {"mode": "auto", "targetMHz": 27})
    dev = load_device()

    errors, warns, _, bases = validate(m, dev)
    for w_ in warns:
        print("Предупреждение: " + w_)
    if errors:
        for e in errors:
            print("ОШИБКА: " + e)
        print(f"Генерация остановлена: ошибок {len(errors)}")
        return 1

    hw = (cfg.parent / m["paths"].get("hw", "../hw")).resolve()
    top = hw / m["paths"].get("top", "src/top.sv")
    cst = hw / m["paths"].get("cst", "src/riscv.cst")
    cfg_rel = os.path.relpath(cfg, hw.parent).replace("\\", "/")
    pfd, fout, vco, _ = resolve_pll(m)
    print(f"Конфигурация: {cfg_rel}")
    print(f"  rPLL: {fmt_mhz(float(m['clock']['xtalMHz']))} МГц -> {fmt_mhz(fout)} МГц "
          f"(IDIV {m['clock']['pll']['idiv']}, FBDIV {m['clock']['pll']['fbdiv']}, ODIV {m['clock']['pll']['odiv']}, VCO {fmt_mhz(vco)})")
    irqs = irq_map(m)
    for inst in insts(m):
        k = inst["name"]
        r = irqs.get(k)
        irq = "" if not r else ("  прерывание: источник PLIC " + str(r[1]) if r[0] == "plic" else f"  прерывание: LI{r[1]}")
        print(f"  {k:<8} {TYPES[inst['type']]['title']:<7} {slot_hex(bases[k])}{irq}")
    if not insts(m):
        print("  Пользовательской периферии нет")
    print(f"  Частота шины периферии: {sysclk_hz(m)} Гц")
    if a.check:
        print("Проверка пройдена")
        return 0

    soc = (cfg.parent / m["paths"].get("soc", "Core/Inc/soc.h")).resolve()
    #Файлы - в кодировке соседних: top.sv и riscv.cst - UTF-8, soc.h (проект Eclipse) - cp1251 с CRLF
    for path, text, enc in ((top, gen_top(m, bases, cfg_rel), "utf-8"), (cst, gen_cst(m, dev, cfg_rel), "utf-8"),
                            (soc, gen_soc_h(m, bases, cfg_rel), "cp1251")):
        changed = write_if_changed(path, text, enc)
        print(f"  {os.path.relpath(path, hw.parent)}: {'обновлён' if changed else 'без изменений'}")
    xnet = net_of(m, m["clock"].get("xtalPin"))
    if sync_sdc_clock(hw, xnet):
        print(f"  hw\\src\\riscv.sdc: такт кварца - порт {xnet}")

    if a.build:
        toolchain = a.toolchain or (m.get("build") or {}).get("toolchain", "gowin")
        progress(1, "Генерация файлов")
        try:
            if toolchain == "apicula":
                build_oss(m, hw, cst, a.oss, fout)
            else:
                build_gowin(m, hw, a.gowin, fout)
        except ConfigError as e:
            print("ОШИБКА СБОРКИ: " + str(e))
            return 2
        progress(100, "Готово")
    return 0


if __name__ == "__main__":
    try:
        sys.stdout.reconfigure(encoding="utf-8")
    except Exception:
        pass
    sys.exit(main())
