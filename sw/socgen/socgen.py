#!/usr/bin/env python3
"""socgen - генератор проекта ПЛИС askoRV32 из файла конфигурации .gwsoc.

По файлу fw/riscv.gwsoc (его редактирует визуальный конфигуратор в Eclipse) создаёт:
  hw/src/top.sv     - верхний уровень платы: выводы, параметры процессора cpu.sv, карта адресов
                    и шина пользовательской периферии, сами устройства и их прерывания;
  hw/src/riscv.cst  - назначение выводов (IO_LOC/IO_PORT) для Gowin EDA и nextpnr.
С ключом --build собирает проект ПЛИС: в Gowin EDA (gw_sh, проект hw/riscv.gprj) или открытым
маршрутом Yosys + nextpnr-himbaechel + apicula - по build.toolchain в .gwsoc или ключу --toolchain.

Правила (адреса, rPLL, проверки) продублированы в web/app.js - при изменении править оба места.

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

BLOCKS = {  # порядок = порядок подключения к memmux и портов top
    "gpio":   dict(title="GPIO",   slot=0x11),
    "tm1638": dict(title="TM1638", slot=0x12),
    "stim":   dict(title="STIM",   slot=0x13),
}
FIXED_REGIONS = {"IMEM": 0x00, "CLINT": 0x02, "PLIC": 0x0C, "DMEM": 0x10, "SIM": 0x1F}
AUTO_FIRST, AUTO_LAST = 0x11, 0x1E

NET_RE = re.compile(r"^([A-Za-z_][A-Za-z0-9_$]*)(?:\[(\d+)\])?$")
SV_KEYWORDS = {"input", "output", "inout", "wire", "logic", "reg", "module", "endmodule", "assign", "always",
               "begin", "end", "if", "else", "case", "for", "generate", "parameter", "localparam", "int", "bit"}
#Имена, уже занятые в top.sv: порт cpu, сигналы, экземпляры и модули, параметры (как RESERVED_NETS в web/app.js)
RESERVED_NETS = {"tck_pad_i", "tms_pad_i", "tdi_pad_i", "tdo_pad_o", "per_clk", "per_rst", "per_Write",
                 "per_Read", "per_Addr", "per_WData", "per_RData", "irq_stim", "irq_local", "irq_src",
                 "sRead", "top", "cpu", "permux", "memmux", "gpio", "gpio_top", "stim", "stim_top", "tm1638", "tm1638_top",
                 "CORE_TYPE", "M_EXT", "DIV_BPC", "IMEM_TYPE", "BSRAM_IMEM_SIZE", "SYNTH_IMEM_SIZE", "IMEM_INIT_FILE",
                 "DMEM_TYPE", "BSRAM_DMEM_SIZE", "SYNTH_DMEM_SIZE", "DMEM_INIT_FILE", "DEBUG_EN", "PLIC_SOURCES",
                 "FCLKIN", "XTAL_KHZ", "PLL_IDIV_SEL", "PLL_FBDIV_SEL", "PLL_ODIV_SEL", "WIN_MASK", "CLK_BASE_MHZ",
                 "CLK_DMEM_MHZ"}
#Сигналы шины устройств (gpio_Write, tim_Addr...) и их адреса (GPIO_BASE...)
RESERVED_RE = re.compile(r"^(gpio|tim|tm)_(Write|Addr|WriteData|ReadData)$|^(GPIO|TM1638|STIM)_BASE$")


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


# --- Сигналы ---
def signals(m):
    s = [dict(id="clk", block="sys", name="Кварц", dir="input", pin=m["clock"].get("xtalPin")),
         dict(id="rst", block="sys", name="Сброс rst_n", dir="input", pin=m["reset"].get("pin"))]
    b = m["blocks"]
    if b["gpio"].get("enabled"):
        for i, p in enumerate(b["gpio"].get("lines", [])):
            s.append(dict(id=f"gpio.{i}", block="gpio", name=f"GPIO {i}", dir="inout", pin=p))
    if b["tm1638"].get("enabled"):
        for k, d in (("dio", "inout"), ("clk", "output"), ("stb", "output")):
            s.append(dict(id=f"tm1638.{k}", block="tm1638", name=f"TM1638 {k.upper()}", dir=d, pin=b["tm1638"].get(k)))
    if b["stim"].get("enabled") and b["stim"].get("out") is not None:
        s.append(dict(id="stim.out", block="stim", name="STIM выход", dir="output", pin=b["stim"]["out"]))
    return s


def net_of(m, pin):
    return (m["pins"].get(str(pin)) or {}).get("net", "")


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
    taken = {slot: name for name, slot in FIXED_REGIONS.items()}
    result = {}
    for pass_ in ("manual", "auto"):
        for k, meta in BLOCKS.items():
            b = m["blocks"][k]
            base = parse_base(b.get("base", "auto"))
            if (base is None) != (pass_ == "auto") or not b.get("enabled"):
                continue
            if base is None:
                s = meta["slot"]
                if s in taken:
                    s = AUTO_FIRST
                    while s <= AUTO_LAST and s in taken:
                        s += 1
                if s > AUTO_LAST:
                    errors.append(f"{meta['title']}: нет свободного окна адресов")
                    continue
            else:
                if base < 0 or base > 0xFFFFFFFF or base & 0x00FFFFFF:
                    errors.append(f"{meta['title']}: адрес должен быть кратен 0x0100_0000 (окно 16 МБайт)")
                    continue
                s = base >> 24
                if s in taken:
                    errors.append(f"{meta['title']}: адрес {slot_hex(s)} уже занят ({taken[s]})")
            taken[s] = meta["title"]
            result[k] = s
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


# --- Проверка ---
def validate(m, dev):
    errors, warns = [], []
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
        if mm.group(1) in RESERVED_NETS or RESERVED_RE.match(mm.group(1)):
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

    xp = m["clock"].get("xtalPin")
    if xp in dev["byNum"] and not re.search(r"GCLK|PLL_T_IN", dev["byNum"][xp].get("cfg", "")):
        warns.append(f"Кварц на выводе {xp} без GCLK/PLL_IN: такт пойдёт по обычной трассировке")
    errors += ["rPLL: " + e for e in resolve_pll(m)[3]]
    if m["blocks"]["gpio"].get("enabled") and not m["blocks"]["gpio"].get("lines"):
        errors.append("GPIO: нет ни одной линии")
    if m["blocks"]["gpio"].get("enabled") and len(m["blocks"]["gpio"]["lines"]) > 32:
        errors.append("GPIO: не больше 32 линий")
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
    c, core, b = m["clock"], m["core"], m["blocks"]
    p = c["pll"]
    pfd, fout, vco, _ = resolve_pll(m)
    sigs = signals(m)
    ports = ports_of(m, sigs)
    net = {s["id"]: net_of(m, s["pin"]) for s in sigs if s["pin"] is not None}
    pin_of = {s["id"]: s["pin"] for s in sigs}

    L = []
    w = L.append
    w("//==============================================================================================")
    w("// top.sv - ВЕРХНИЙ УРОВЕНЬ askoRV32. ФАЙЛ СОЗДАН КОНФИГУРАТОРОМ ПЛИС - НЕ РЕДАКТИРУЙТЕ ВРУЧНУЮ.")
    w(f"// Источник: {cfg_rel}; генератор: sw/socgen/socgen.py (кнопка «Собрать» в Eclipse).")
    w("// Процессор (ядро, память, отладчик, CLINT, PLIC) - в cpu.sv, он правится вручную; здесь -")
    w("// параметры платы для cpu и пользовательская периферия на его порту per_*.")
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
    for i, x in enumerate(params):
        if x[1] is None:
            w(f"                {x[0]}")
            continue
        typ, name, val, com = x
        last = x is items[-1]
        decl = f"             parameter {typ + ' ' if typ else ''}{name}".ljust(45) + f"= {val}{')' if last else ','}"
        w(decl + (f" //{com}" if com else ""))

    # --- Порты ---
    w("   (")
    groups = [("Такт и сброс", "sys"), ("GPIO", "gpio"), ("TM1638", "tm1638"), ("STIM", "stim")]
    block_of_port = {}
    for s in sigs:
        if s["pin"] is None:
            continue
        name = NET_RE.match(net_of(m, s["pin"])).group(1)
        block_of_port.setdefault(name, s["block"])
    # Запятая ставится после каждого порта, кроме последнего; порты JTAG идут отдельным блоком
    entries = []
    for title, blk in groups:
        names = [n for n in ports if block_of_port.get(n) == blk]
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
    order = [k for k in BLOCKS if k in bases]
    names = {"gpio": "GPIO", "tm1638": "TM1638", "stim": "STIM"}
    w("    //#1 Карта адресов пользовательской периферии: у каждого устройства окно 16 МБайт (маска 0xFF00_0000).")
    w("    //Системные окна - в cpu.sv: IMEM 0x0000_0000, CLINT 0x0200_0000, PLIC 0x0C00_0000, DMEM 0x1000_0000;")
    w("    //0x1F00_0000 - устройства тестбенча. Всё вне системных окон cpu отдаёт на порт per_*")
    for k in order:
        w(f"    localparam logic [31:0] {names[k] + '_BASE':<12}= {slot_hex(bases[k])};")
    w(f"    localparam logic [31:0] {'WIN_MASK':<12}= 32'hFF00_0000;")
    w("")
    w("    //Частота шины периферии (per_clk), МГц, целая часть: для делителей периферии (TM1638).")
    w("    //Однотактное ядро с BSRAM делит базовую частоту на 3. Прошивке то же значение задаёт SYSCLK_HZ.")
    w("    localparam int CLK_BASE_MHZ = XTAL_KHZ * (PLL_FBDIV_SEL + 1) / (PLL_IDIV_SEL + 1) / 1000;")
    w("    localparam int CLK_DMEM_MHZ = ((IMEM_TYPE | DMEM_TYPE) & CORE_TYPE) ? CLK_BASE_MHZ / 3 : CLK_BASE_MHZ;")
    w("")

    # --- Процессор ---
    w("    //#2 Процессор (cpu.sv): такт, сброс, ядро, отладчик, память команд и данных, CLINT, PLIC.")
    w("    //Параметры платы переопределяют значения по умолчанию из cpu.sv")
    w("    logic        per_clk, per_rst;")
    w("    logic [ 3:0] per_Write;")
    w("    logic        per_Read;")
    w("    logic [31:0] per_Addr, per_WData, per_RData;")
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
    w("             .per_clk(per_clk), .per_rst(per_rst),")
    w("             .per_Write(per_Write), .per_Read(per_Read), .per_Addr(per_Addr), .per_WData(per_WData), .per_RData(per_RData),")
    w("             .irq_local(irq_local), .irq_src(irq_src));")
    w("")

    # --- Шина пользовательской периферии ---
    pre = {"gpio": "gpio", "tm1638": "tm", "stim": "tim"}
    n = len(order)
    if n:
        cat = lambda suf: "{" + ", ".join(f"{pre[k]}_{suf}" for k in order) + "}"
        w(f"    //#3 Шина пользовательской периферии (memmux): ведомые перечислены от старшего номера к младшему")
        w(f"    logic [ 3:0] {', '.join(pre[k] + '_Write' for k in order)};")
        w(f"    logic [31:0] {', '.join(pre[k] + '_Addr' for k in order)};")
        w(f"    logic [31:0] {', '.join(pre[k] + '_WriteData' for k in order)};")
        w(f"    logic [31:0] {', '.join(pre[k] + '_ReadData' for k in order)};")
        w(f"    logic [{n - 1:>2}:0] sRead;")
        w("")
        w(f"    memmux #(.MEMORY_TYPE(DMEM_TYPE), .SLAVES({n}),")
        w("              .MATCH_ADDR ({" + ", ".join(names[k] + "_BASE" for k in order) + "}),")
        w(f"              .MATCH_MASK ({{{n}{{WIN_MASK}}}}))")
        w("            permux")
        w("             (.clk(per_clk), .rst(per_rst),")
        w("              .mWrite(per_Write), .mRead(per_Read), .mAddr(per_Addr), .mWData(per_WData), .mRData(per_RData),")
        w(f"              .sWrite({cat('Write')}),")
        w("              .sRead (sRead),")
        w(f"              .sAddr ({cat('Addr')}),")
        w(f"              .sWData({cat('WriteData')}),")
        w(f"              .sRData({cat('ReadData')}));")
    else:
        w("    //#3 Пользовательской периферии нет: обращения к порту per_* читаются как 0")
        w("    assign per_RData = 32'd0;")
    w("")

    num = 1
    if "gpio" in bases:
        lines = b["gpio"]["lines"]
        io = ", ".join(compress_bits([net[f"gpio.{i}"] for i in reversed(range(len(lines)))]))
        w(f"    //-{num}- GPIO: {len(lines)} лин., регистры с {slot_hex(bases['gpio'])} (линия 0 - младший разряд)")
        w(f"    gpio_top #(.MEMORY_TYPE(DMEM_TYPE), .WIDTH({len(lines)})) gpio")
        w("              (.clk(per_clk), .rst(per_rst),")
        w("               .Write(gpio_Write), .Addr(gpio_Addr), .WData(gpio_WriteData), .RData(gpio_ReadData),")
        w(f"               .io_ports({{{io}}}));")
        w("")
        num += 1
    if "tm1638" in bases:
        w(f"    //-{num}- Внешний модуль TM1638, регистры с {slot_hex(bases['tm1638'])}")
        w("    tm1638_top #(.MEMORY_TYPE(DMEM_TYPE), .CLK_MHZ(CLK_DMEM_MHZ)) tm1638")
        w("                (.clk(per_clk), .rst(per_rst),")
        w("                 .Write(tm_Write), .Addr(tm_Addr), .WData(tm_WriteData), .RData(tm_ReadData),")
        w(f"                 .tm_dio({net['tm1638.dio']}), .tm_clk({net['tm1638.clk']}), .tm_stb({net['tm1638.stb']}));")
        w("")
        num += 1
    if "stim" in bases:
        out = net.get("stim.out", "")
        w(f"    //-{num}- Простой таймер STIM ({b['stim'].get('width', 16)} бит), регистры с {slot_hex(bases['stim'])}")
        w("    logic irq_stim;")
        w(f"    stim_top #(.MEMORY_TYPE(DMEM_TYPE), .WIDTH({b['stim'].get('width', 16)})) stim")
        w("                (.clk(per_clk), .rst(per_rst),")
        w("                 .Write(tim_Write), .Addr(tim_Addr), .WData(tim_WriteData), .RData(tim_ReadData),")
        w(f"                 .tim_out({out}), .irq(irq_stim));" + ("" if out else "   //выход ШИМ не выведен"))
        w("")
        num += 1
    else:
        w("    logic irq_stim;")
        w("    assign irq_stim = 1'b0;   //таймер STIM выключен")
        w("")
    w(f"    //-{num}- Прерывания периферии: LI0 (mcause 16) и источник 1 PLIC - таймер STIM (в программе")
    w("    //разрешают один путь). Источники PLIC 2..PLIC_SOURCES свободны")
    w("    assign irq_local = {15'd0, irq_stim};")
    w("    assign irq_src   = PLIC_SOURCES'(irq_stim);   //источник 1 - младший разряд")
    w("endmodule")
    return "\n".join(L) + "\n"


def gen_cst(m, dev, cfg_rel):
    sigs = [s for s in signals(m) if s["pin"] is not None]
    d = m.get("ioDefaults", {})
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
        a = dict(d, **{k: v for k, v in (m["pins"].get(str(s["pin"])) or {}).items() if k != "net"})
        attrs = [f"IO_TYPE={a.get('ioType', 'LVCMOS18')}", f"PULL_MODE={a.get('pull', 'UP')}"]
        if s["dir"] != "input":
            attrs.append(f"DRIVE={a.get('drive', '8')}")
        attrs.append(f"BANK_VCCIO={a.get('vccio', '1.8')}")
        L.append(f'IO_LOC "{net}" {s["pin"]};')
        L.append(f'IO_PORT "{net}" {" ".join(attrs)};')
    return "\n".join(L) + "\n"


def write_if_changed(path, text):
    """Запись без смены времени файла, если содержимое то же (Gowin EDA и make не пересобирают зря)."""
    old = path.read_text(encoding="utf-8") if path.exists() else None
    if old == text:
        return False
    path.write_text(text, encoding="utf-8", newline="\n")
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


def run_tool(cmd, env, log, cwd):
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
    run_tool([oss / "bin" / "yosys.exe", "-m", "slang", "-q", "-l", "yosys.log", "-s", "synth.ys"], env, out / "yosys.out", out)
    print("Размещение и трассировка (nextpnr-himbaechel):", flush=True)
    run_tool([oss / "bin" / "nextpnr-himbaechel.exe", "--json", "top.json", "--write", "pnr.json",
              "--device", m.get("device", "GW1NR-LV9QN88PC6/I5"), "--vopt", "family=GW1N-9C",
              "--vopt", "cst=" + os.path.relpath(cst, out).replace("\\", "/"),
              "--freq", fmt_mhz(fmax_mhz), "--timing-allow-fail", "--report", "report.json"],
             env, out / "nextpnr.log", out)
    print("Битовый поток (apicula gowin_pack):", flush=True)
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
    tcl = impl / "socgen_build.tcl"
    tcl.write_text("# Создано socgen.py: сборка проекта Gowin EDA из командной строки\n"
                   "open_project riscv.gprj\nrun all\n", encoding="utf-8", newline="\n")
    fs = impl / "pnr" / "riscv.fs"
    t0 = time.time()
    print(f"Синтез, размещение, трассировка и битовый поток (Gowin EDA, {ide.parent.name}):", flush=True)
    try:
        run_tool([ide / "bin" / "gw_sh.exe", os.path.relpath(tcl, hw)], dict(os.environ), impl / "socgen_gw_sh.log", hw)
    except ConfigError:
        pass   #Код возврата gw_sh ненадёжен - итог определяется по ошибкам в журнале и файлу .fs
    log = (impl / "socgen_gw_sh.log").read_text(encoding="utf-8", errors="replace")
    errs = [l for l in log.splitlines() if l.startswith("ERROR")]
    if errs or not fs.exists() or fs.stat().st_mtime < t0:
        raise ConfigError(f"Gowin EDA: ошибок {len(errs)}, битовый поток не создан (журнал hw/impl/socgen_gw_sh.log)")
    print(f"Готово: {os.path.relpath(fs, hw.parent)} ({fs.stat().st_size} Байт)")
    rpt = impl / "pnr" / "riscv.rpt.txt"
    if rpt.exists():
        r = rpt.read_text(encoding="utf-8", errors="replace")
        used = []
        for k in ("Logic", "Register", "CLS", "BSRAM", "DSP", "I/O Port"):
            mm = re.search(rf"^\s*{re.escape(k)}\s*\|\s*(\d+)/(\d+)", r, re.M)
            if mm:
                used.append(f"{k} {mm.group(1)}/{mm.group(2)}")
        print("  Ресурсы: " + ", ".join(used))
    tr = impl / "pnr" / "riscv_tr_content.html"
    if tr.exists():
        t = html_text(tr)
        #Такт ядра проверяется по рабочей частоте rPLL: цель в riscv.sdc нарочно выше (50 МГц при 45), поэтому
        #отрицательный запас относительно цели - нормальное состояние
        core_ok = {}
        for name, con, ach in re.findall(r"\d+ (\S+) ([\d.]+)\(MHz\) ([\d.]+)\(MHz\) \d+ TOP", t):
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
    for k, v in dict(core={}, clock={}, reset={}, blocks={}, pins={}, ioDefaults={}, paths={}).items():
        m.setdefault(k, v)
    for k in BLOCKS:
        m["blocks"].setdefault(k, {"enabled": False})
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
    for k, s in bases.items():
        print(f"  {BLOCKS[k]['title']:<7} {slot_hex(s)}")
    if a.check:
        print("Проверка пройдена")
        return 0

    for path, text in ((top, gen_top(m, bases, cfg_rel)), (cst, gen_cst(m, dev, cfg_rel))):
        changed = write_if_changed(path, text)
        print(f"  {os.path.relpath(path, hw.parent)}: {'обновлён' if changed else 'без изменений'}")

    if a.build:
        toolchain = a.toolchain or (m.get("build") or {}).get("toolchain", "gowin")
        try:
            if toolchain == "apicula":
                build_oss(m, hw, cst, a.oss, fout)
            else:
                build_gowin(m, hw, a.gowin, fout)
        except ConfigError as e:
            print("ОШИБКА СБОРКИ: " + str(e))
            return 2
    return 0


if __name__ == "__main__":
    try:
        sys.stdout.reconfigure(encoding="utf-8")
    except Exception:
        pass
    sys.exit(main())
