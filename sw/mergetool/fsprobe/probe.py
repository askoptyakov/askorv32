"""Разбор расположения данных BSRAM в битовом потоке .fs GW2A-18C.

Пробный проект: NB блоков SP (как в hw/src/mem.sv: BIT_WIDTH 8, READ_MODE 0, WRITE_MODE 00, RESET_MODE SYNC),
у каждого - начальное содержимое INIT_RAM_00..3F. Бит i блока j (i = адрес*8 + номер бита, 0..16383) в сборке k
равен разряду k кода (j << 14 | i). Сборка 'ones' - все единицы, 'zero' - все нули. По набору сборок у каждого
изменившегося бита .fs восстанавливается (блок, i).

Запуск (каталог sw/mergetool/fsprobe, Gowin EDA 1.9.11; 22 сборки по ~6 с):
    py probe.py build zero ones 0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19
    py probe.py analyze        -> work/mapping.json: бит (блок, i) -> (строка данных .fs, столбец)
    py struct.py               -> границы блоков в строках/столбцах, общий ли рисунок битов у всех блоков
    py verify.py <out.fs> <riscv.posp> <riscv.bin>   -> проверка файла после mergetool по таблице
Описание и результат - sw/mergetool/README.md, раздел «Кристалл GW2A-18 (Tang Primer 20K)».
"""
import json
import re
import shutil
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
WORK = HERE / "work"            #Пробные сборки и результаты (в git не хранятся)
GW = r"C:\Program Files\Gowin\Gowin_V1.9.11.03_Education_x64\IDE\bin\gw_sh.exe"
NB = 46                 #Блоков BSRAM в GW2A-18
NBITS = 16384           #Бит данных блока при BIT_WIDTH 8 (2048 адресов)
KBITS = 20              #Разрядов кода: 6 - блок, 14 - бит


def bitval(build, j, i):
    if build == "ones":
        return 1
    if build == "zero":
        return 0
    return ((j << 14 | i) >> int(build)) & 1


def init_params(build, j):
    out = []
    for x in range(64):
        v = 0
        for b in range(256):
            if bitval(build, j, x * 256 + b):
                v |= 1 << b
        out.append(f".INIT_RAM_{x:02X}(256'h{v:064X})")
    return out


def gen(build):
    L = ["module top(input clk, input we, input [7:0] di, output led);",
         "    logic [10:0] a = 0;",
         "    always_ff @(posedge clk) a <= a + 1'b1;",
         f"    logic [7:0] q [{NB}];"]
    for j in range(NB):
        L.append(f"    logic [23:0] e{j};")
        L.append("    SP #(.READ_MODE(1'b0), .WRITE_MODE(2'b00), .BIT_WIDTH(8), .BLK_SEL(3'b000), .RESET_MODE(\"SYNC\"),")
        L.append("        " + ",\n        ".join(init_params(build, j)) + f") b{j} (")
        L.append(f"        .DO({{e{j}, q[{j}]}}), .CLK(clk), .OCE(1'b0), .CE(1'b1), .RESET(1'b0), .WRE(we),")
        L.append("        .BLKSEL(3'b000), .AD({a, 3'b000}), .DI({24'd0, di}));")
    L.append("    logic [7:0] x;")
    L.append("    always_comb begin x = 0; for (int j = 0; j < %d; j++) x ^= q[j]; end" % NB)
    L.append("    assign led = ^x;")
    L.append("endmodule")
    return "\n".join(L) + "\n"


def build(name):
    d = WORK / f"b_{name}"
    WORK.mkdir(exist_ok=True)
    if d.exists():
        shutil.rmtree(d)
    (d / "impl").mkdir(parents=True)
    (d / "top.sv").write_text(gen(name), encoding="utf-8")
    shutil.copy(HERE / "riscv_process_config.json", d / "impl" / "riscv_process_config.json")
    (d / "riscv.gprj").write_text("""<?xml version="1" encoding="UTF-8"?>
<!DOCTYPE gowin-fpga-project>
<Project>
    <Template>FPGA</Template>
    <Version>5</Version>
    <Device name="GW2A-18C" pn="GW2A-LV18PG256C8/I7">gw2a18c-011</Device>
    <FileList>
        <File path="top.sv" type="file.verilog" enable="1"/>
        <File path="probe.cst" type="file.cst" enable="1"/>
    </FileList>
</Project>
""", encoding="utf-8")
    (d / "probe.cst").write_text('IO_LOC "clk" H11;\nIO_LOC "led" C13;\nIO_LOC "we" T10;\n' +
                                 "".join(f'IO_LOC "di[{k}]" {p};\n' for k, p in enumerate(["J14", "J16", "J15", "K16", "H14", "H16", "G16", "H15"])),
                                 encoding="utf-8")
    (d / "b.tcl").write_text("open_project riscv.gprj\nrun all\n", encoding="utf-8")
    r = subprocess.run([GW, "b.tcl"], cwd=d, capture_output=True, text=True, encoding="utf-8", errors="replace")
    (d / "gw.log").write_text(r.stdout + r.stderr, encoding="utf-8")
    fs = d / "impl" / "pnr" / "riscv.fs"
    errs = [l for l in r.stdout.splitlines() if l.startswith("ERROR")]
    print(name, "ok" if fs.exists() and not errs else "FAIL", errs[:3], flush=True)


def load_fs(name):
    lines = (WORK / f"b_{name}" / "impl" / "pnr" / "riscv.fs").read_text().splitlines()
    return [l for l in lines if not l.startswith("//")]


def posp(name):
    t = (WORK / f"b_{name}" / "impl" / "pnr" / "riscv.posp").read_text()
    return {int(m.group(1)): (m.group(2), int(m.group(3))) for m in re.finditer(r"^b(\d+)\S* PLACE_BSRAM_(R\d+)\[(\d+)\]", t, re.M)}


def analyze():
    zero = load_fs("zero")
    ones = load_fs("ones")
    pz, po = posp("zero"), posp("ones")
    assert pz == po, "размещение блоков разное"
    #Биты, которые отличаются между «все нули» и «все единицы» - это данные BSRAM
    diff = []
    for ln, (a, b) in enumerate(zip(zero, ones)):
        if a != b:
            assert len(a) == len(b)
            for c, (x, y) in enumerate(zip(a, b)):
                if x != y:
                    diff.append((ln, c, x == "1"))      #x - значение в «нулях»: '1' - бит инвертирован
    print("различающихся бит:", len(diff), "ожидается", NB * NBITS)
    builds = {k: load_fs(str(k)) for k in range(KBITS)}
    for k in range(KBITS):
        assert posp(str(k)) == pz, f"размещение в сборке {k} другое"
    mapping = {}
    for ln, c, inv in diff:
        code = 0
        for k in range(KBITS):
            bit = builds[k][ln][c] == "1"
            if inv:
                bit = not bit
            if bit:
                code |= 1 << k
        j, i = code >> 14, code & 0x3FFF
        assert (j, i) not in mapping, ("повтор", j, i)
        mapping[(j, i)] = (ln, c, inv)
    print("сопоставлено:", len(mapping))
    #Проверка: прочие биты не менялись ни в одной сборке
    dset = {(ln, c) for ln, c, _ in diff}
    other = 0
    for k in range(KBITS):
        for ln, (a, b) in enumerate(zip(zero, builds[k])):
            if a != b:
                for c, (x, y) in enumerate(zip(a, b)):
                    if x != y and (ln, c) not in dset:
                        other += 1
    print("лишних изменений:", other)
    out = {"posp": {str(j): list(v) for j, v in pz.items()},
           "map": {f"{j},{i}": list(v) for (j, i), v in mapping.items()}}
    (WORK / "mapping.json").write_text(json.dumps(out), encoding="utf-8")


if __name__ == "__main__":
    if sys.argv[1] == "build":
        for n in sys.argv[2:]:
            build(n)
    else:
        analyze()
