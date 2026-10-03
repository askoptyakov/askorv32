import json
from collections import defaultdict
from pathlib import Path

HERE = Path(__file__).resolve().parent
WORK = HERE / "work"            #Пробные сборки и результаты (в git не хранятся)
d = json.loads((WORK / "mapping.json").read_text())
posp = {int(j): tuple(v) for j, v in d["posp"].items()}
m = defaultdict(dict)
for k, (ln, c, inv) in d["map"].items():
    j, i = map(int, k.split(","))
    m[j][i] = (ln, c)

blocks = {}
for j, bits in m.items():
    lns = [v[0] for v in bits.values()]
    cs = [v[1] for v in bits.values()]
    blocks[posp[j]] = dict(j=j, l0=min(lns), l1=max(lns), c0=min(cs), c1=max(cs))
for loc in sorted(blocks, key=lambda x: (x[0], x[1])):
    b = blocks[loc]
    print(loc, "lines", b["l0"], b["l1"], "cols", b["c0"], b["c1"], "w", b["c1"] - b["c0"] + 1)

#Рисунок внутри блока относительно (l1, c1): одинаков ли у всех
pat = {}
for loc, b in blocks.items():
    bits = m[b["j"]]
    pat[loc] = tuple((b["l1"] - bits[i][0], b["c1"] - bits[i][1]) for i in range(16384))
ref = next(iter(pat.values()))
same = [loc for loc, p in pat.items() if p == ref]
print("одинаковый рисунок у", len(same), "из", len(pat))
#Первые биты: строка (от конца блока) и позиция (от правого края)
print("i: (строк от конца, символов от правого края)")
for i in list(range(0, 20)) + [16, 32, 64, 128, 256, 4096, 8192, 12288, 16383]:
    print(i, ref[i])
#Позиции внутри строки у 16-битных групп (как bit_loc_pas в mergetool GW1N)
by_line = defaultdict(list)
for i, (dl, dc) in enumerate(ref):
    by_line[dl].append((dc, i))
print("строка 0 от конца:", sorted(by_line[0])[:40])
(WORK / "pattern.json").write_text(json.dumps({"blocks": {f"{k[0]}[{k[1]}]": v for k, v in blocks.items()}, "ref": ref}))
