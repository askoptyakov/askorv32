"""Проверка mergetool для GW2A-18 по измеренной таблице: бит (блок, i) -> (строка данных, столбец)."""
import json
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
WORK = HERE / "work"            #Пробные сборки и результаты (в git не хранятся)
fs_path, posp_path, bin_path = sys.argv[1:4]
d = json.loads((WORK / "mapping.json").read_text())
loc_of_probe = {int(j): tuple(v) for j, v in d["posp"].items()}
table = {}
for k, (ln, c, inv) in d["map"].items():
    j, i = map(int, k.split(","))
    table[(loc_of_probe[j], i)] = (ln, c)
lines = [l for l in Path(fs_path).read_text().splitlines() if not l.startswith("//")]
data = Path(bin_path).read_bytes()
bad = good = 0
for m in re.finditer(r"cpu/([id])mem/cluster\[(\d+)\]\.sector\[(\d+)\]\.bsram PLACE_BSRAM_(R\d+)\[(\d+)\]", Path(posp_path).read_text()):
    mem, cl, sec, row, idx = m.group(1), int(m.group(2)), int(m.group(3)), m.group(4), int(m.group(5))
    base = (0 if mem == "i" else 32768) + cl * 8192
    for a in range(2048):
        off = base + a * 4 + sec
        byte = data[off] if off < len(data) else 0
        for b in range(8):
            ln, c = table[((row, idx), a * 8 + b)]
            if (lines[ln][c] == "1") == bool(byte >> b & 1):
                good += 1
            else:
                bad += 1
print(f"совпало бит: {good}, не совпало: {bad}")
