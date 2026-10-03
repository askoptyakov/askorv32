"""Временные диаграммы СИФУ для README.md (SVG без сторонних библиотек).

    py hw/src/periph/sifu/img/gen_diagrams.py

sifu_pair.svg      - одна пара фаз (AB/BA): линейное напряжение, оно же после RC-фильтра NSB, оптроны, пила,
                     пороги ALPHA + DELAY и + WIDTH, импульсы VS1 и VS4;
sifu_bridge.svg    - весь мост: линейные напряжения, точки естественной коммутации, импульсы VS1..VS6 со
                     сдвоенными импульсами и выходное напряжение выпрямителя на активной нагрузке при
                     угле 0, 30 и 60 эл. град. (как на осциллограмме стенда).
Числа - как на стенде: тик ГПН 500 кГц (1 эл. град. = 27.8 тика при 50 Гц), DELAY 400, WIDTH 150.
Запаздывание NSB (RC-фильтр + порог оптрона) взято таким, чтобы DELAY = 400 тиков (14.4 град.)
приводил импульс при ALPHA = 0 в точку естественной коммутации: окно оптрона начинается через
60 - 14.4 = 45.6 град. после перехода линейного напряжения через 0.
"""
import math
from pathlib import Path

HERE = Path(__file__).resolve().parent
TPD = 5000 / 180            #Тиков ГПН на эл. градус (500 кГц, 50 Гц)
DELAY, WIDTH = 400, 150
LAG = 35.0                  #Запаздывание напряжения после RC-фильтра NSB, град.
DZ = 10.6                   #Мёртвая зона оптронов (порог), град.: LAG + DZ = 45.6
FG, MUTED, GRID, ACC, ACC2 = "#222", "#888", "#ddd", "#1f6fb2", "#c2410c"


class Svg:
    def __init__(self, w, h):
        self.w, self.h, self.items = w, h, []

    def add(self, s):
        self.items.append(s)

    def line(self, x1, y1, x2, y2, color=FG, width=1.0, dash=None):
        d = f' stroke-dasharray="{dash}"' if dash else ""
        self.add(f'<line x1="{x1:.1f}" y1="{y1:.1f}" x2="{x2:.1f}" y2="{y2:.1f}" stroke="{color}" stroke-width="{width}"{d}/>')

    def poly(self, pts, color=FG, width=1.4, dash=None):
        d = f' stroke-dasharray="{dash}"' if dash else ""
        p = " ".join(f"{x:.1f},{y:.1f}" for x, y in pts)
        self.add(f'<polyline points="{p}" fill="none" stroke="{color}" stroke-width="{width}"{d}/>')

    def rect(self, x, y, w, h, fill, opacity=1.0):
        self.add(f'<rect x="{x:.1f}" y="{y:.1f}" width="{w:.1f}" height="{h:.1f}" fill="{fill}" fill-opacity="{opacity}"/>')

    def text(self, x, y, s, size=12, color=FG, anchor="start", weight="normal"):
        s = s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
        self.add(f'<text x="{x:.1f}" y="{y:.1f}" font-size="{size}" fill="{color}" text-anchor="{anchor}" '
                 f'font-weight="{weight}">{s}</text>')

    def arrow(self, x1, x2, y, label, color=FG):
        self.line(x1, y, x2, y, color, 1)
        for x, s in ((x1, 1), (x2, -1)):
            self.add(f'<path d="M{x:.1f},{y:.1f} l{6 * s},-3 l0,6 z" fill="{color}"/>')
        self.text((x1 + x2) / 2, y - 4, label, 11, color, "middle")

    def save(self, name):
        body = "\n".join(self.items)
        (HERE / name).write_text(
            f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {self.w} {self.h}" width="{self.w}" height="{self.h}" '
            f'font-family="Segoe UI, Arial, sans-serif">\n<rect width="100%" height="100%" fill="#fff"/>\n{body}\n</svg>\n',
            encoding="utf-8")


def wrap(a):
    return a % 360


def in_win(theta, start, length):
    return wrap(theta - start) < length


# ---------------------------------------------------------------------------------------------
def pair_diagram(alpha_deg=30):
    W, L, R = 1010, 120, 960
    s = Svg(W, 560)
    x = lambda th: L + (R - L) * th / 360
    rows = {"u": 70, "opto": 180, "saw": 300, "vs": 440}
    #Сетка по 30 град.
    for th in range(0, 361, 30):
        s.line(x(th), 30, x(th), 520, GRID, 1)
        s.text(x(th), 540, f"{th}°", 11, MUTED, "middle")
    s.text(L, 556, "фаза U_AB, эл. град. (0 - переход U_AB через 0 вверх)", 11, MUTED)

    #1 Напряжения
    y0, A = rows["u"], 42
    s.text(10, y0 - 30, "Сеть", 13, FG, weight="bold")
    s.poly([(x(t / 2), y0 - A * math.sin(math.radians(t / 2))) for t in range(721)], FG)
    s.poly([(x(t / 2), y0 - A * 0.55 * math.sin(math.radians(t / 2 - LAG))) for t in range(721)], MUTED, 1.2, "4 3")
    s.line(L, y0, R, y0, MUTED, 0.6)
    s.text(R + 4, y0 - A + 4, "U_AB", 11)
    s.text(x(LAG + 270), y0 + A * 0.55 + 14, "U_A'B' после RC-фильтра NSB", 11, MUTED, "middle")
    for th, name in ((60, "VS1"), (240, "VS4")):
        s.line(x(th), y0 - A - 8, x(th), rows["vs"] + 30, ACC2, 1, "2 3")
        s.text(x(th) + 3, y0 - A - 10, f"ест. коммутация {name}", 10, ACC2)

    #2 Оптроны NSB (0 - открыт)
    def digital(y, f, label, color=FG):
        pts, prev = [], None
        for t in range(0, 3601):
            th = t / 10
            v = f(th)
            yy = y - (14 if v else 0)
            if prev is not None and v != prev:
                pts.append((x(th), y - (14 if prev else 0)))
            pts.append((x(th), yy))
            prev = v
        s.poly(pts, color, 1.4)
        s.text(10, y - 3, label, 11)
    win_p = (LAG + DZ, 180 - 2 * DZ)
    win_n = (180 + LAG + DZ, 180 - 2 * DZ)
    yo = rows["opto"]
    s.text(10, yo - 52, "Входы (NSB, 0 - оптрон открыт)", 13, FG, weight="bold")
    digital(yo - 24, lambda th: not in_win(th, *win_p), "sync_ab")
    digital(yo + 6, lambda th: not in_win(th, *win_n), "sync_ba")
    s.arrow(x(0), x(LAG + DZ), yo + 26, "запаздывание NSB 45.6°", MUTED)

    #3 Пила
    ys, H = rows["saw"] + 50, 90
    s.text(10, rows["saw"] - 50, "Пила OnePulse_3 (cnt): от смены полярности, через мёртвую зону", 13, FG, weight="bold")
    def saw(th):
        #Пила - от начала полуволны (смена полярности) до начала следующей, через мёртвую зону
        d = min(wrap(th - win_p[0]), wrap(th - win_n[0]))
        return min(d * TPD, 4095)
    s.poly([(x(t / 4), ys - H * saw(t / 4) / 4095) for t in range(1441)], ACC, 1.4)
    t_on = alpha_deg * TPD + DELAY
    t_off = t_on + WIDTH
    for v, lab in ((t_on, f"t_on = ALPHA + DELAY = {round(t_on)}"), (4095, "4095 - насыщение")):
        s.line(L, ys - H * v / 4095, R, ys - H * v / 4095, MUTED, 0.8, "5 3")
        s.text(R - 2, ys - H * v / 4095 - 3, lab, 10, MUTED, "end")
    s.text(L - 4, ys + 4, "0", 10, MUTED, "end")

    #4 Импульсы
    yv = rows["vs"]
    s.text(10, yv - 40, "Импульсы (до сдваивания)", 13, FG, weight="bold")
    p_on = (win_p[0] + t_on / TPD, WIDTH / TPD)
    n_on = (win_n[0] + t_on / TPD, WIDTH / TPD)
    digital(yv - 10, lambda th: in_win(th, *p_on), "VS1", ACC2)
    digital(yv + 22, lambda th: in_win(th, *n_on), "VS4", ACC2)
    s.arrow(x(win_p[0]), x(win_p[0] + DELAY / TPD), yv + 46, "DELAY", FG)
    s.arrow(x(60), x(60 + alpha_deg), yv + 62, f"ALPHA = {alpha_deg}°", ACC2)
    s.save("sifu_pair.svg")


# ---------------------------------------------------------------------------------------------
def bridge_diagram():
    W, L, R = 1010, 120, 960
    s = Svg(W, 700)
    #Фаза theta_A; линейные напряжения и тиристоры (VSk проводит от своей точки + alpha на 120 град.)
    va = lambda t: math.sin(math.radians(t))
    vb = lambda t: math.sin(math.radians(t - 120))
    vc = lambda t: math.sin(math.radians(t - 240))
    #Естественная коммутация VSk: 30 + 60 * (k - 1) по фазе U_A; VS1 - A+, VS2 - C-, VS3 - B+, VS4 - A-, VS5 - C+, VS6 - B-
    nat = {k: 30 + 60 * (k - 1) for k in range(1, 7)}
    top = {1: va, 3: vb, 5: vc}
    bot = {4: va, 6: vb, 2: vc}

    #Часть 1: один период, alpha = 30, импульсы
    alpha = 30
    x = lambda th: L + (R - L) * th / 360
    for th in range(0, 361, 30):
        s.line(x(th), 30, x(th), 330, GRID, 1)
        s.text(x(th), 344, f"{th}°", 10, MUTED, "middle")
    y0, A = 90, 40
    s.text(10, 16, f"Мост: фазы и импульсы при ALPHA = {alpha}°, сдвоенные импульсы (CR.DBL)", 13, FG, weight="bold")
    for f, n in ((va, "U_A"), (vb, "U_B"), (vc, "U_C")):
        s.poly([(x(t / 2), y0 - A * f(t / 2)) for t in range(721)], MUTED, 1.1)
    s.text(R + 4, y0 - A * va(360) + 4, "U_A", 10, MUTED)
    for k, th in nat.items():
        s.line(x(th), y0 - A - 6, x(th), 320, ACC2, 0.8, "2 3")
        s.text(x(th), y0 - A - 9, f"{k}", 10, ACC2, "middle")
    s.text(L - 6, y0 - A - 9, "ест. коммутация VS", 10, ACC2, "end")
    w = WIDTH / TPD
    for k in range(1, 7):
        yk = 140 + (k - 1) * 30
        own = (nat[k] + alpha) % 360
        nxt = (nat[k % 6 + 1] + alpha) % 360
        pts = []
        for t in range(0, 3601):
            th = t / 10
            v = in_win(th, own, w) or in_win(th, nxt, w)
            pts.append((x(th), yk - (14 if v else 0)))
        s.poly(pts, ACC2 if k else FG, 1.4)
        s.text(10, yk - 3, f"VS{k}", 11)
        s.text(x(own) + 6, yk - 4, "свой", 9, MUTED)
        s.text(x(nxt) + 6, yk - 4, f"с VS{k % 6 + 1}", 9, MUTED)

    #Часть 2: выходное напряжение, R-нагрузка, alpha 0 -> 30 -> 60 (по 1.5 периода)
    yb, B = 600, 170
    s.text(10, 395, "Выходное напряжение выпрямителя (без фильтра, активная нагрузка): ALPHA 0°, 30°, 60°", 13, FG, weight="bold")
    seg = 540                                  #град. на угол
    xs = lambda th: L + (R - L) * th / (3 * seg)
    s.line(L, yb, R, yb, MUTED, 0.8)
    pts = []
    for i, al in enumerate((0, 30, 60)):
        s.text(xs(i * seg + seg / 2), 418, f"ALPHA = {al}°", 11, ACC, "middle")
        if i:
            s.line(xs(i * seg), 405, xs(i * seg), yb + 8, MUTED, 0.8, "4 3")
        for t in range(0, seg * 4 + 1):
            th = i * seg + t / 4
            #Последний включённый тиристор катодной и анодной групп
            def last(group):
                best, bd = None, 1e9
                for k in group:
                    d = wrap(th - (nat[k] + al))
                    if d < bd:
                        best, bd = k, d
                return best
            kt, kb = last((1, 3, 5)), last((4, 6, 2))
            ud = top[kt](th) - bot[kb](th)
            pts.append((xs(th), yb - B * max(ud, 0) / math.sqrt(3)))
    s.poly(pts, ACC, 1.4)
    s.text(L - 6, yb - B + 4, "√2·U_л", 10, MUTED, "end")
    s.line(L, yb - B, R, yb - B, GRID, 1)
    s.text(L - 6, yb + 4, "0", 10, MUTED, "end")
    s.text(L, 680, "ALPHA до 60°: ток непрерывен, U_d = U_d0·cos(ALPHA); после 60° на активной нагрузке напряжение касается нуля, "
                   "U_d = U_d0·(1 + cos(ALPHA + 60°)), 0 при 120°", 10, MUTED)
    s.save("sifu_bridge.svg")


if __name__ == "__main__":
    pair_diagram()
    bridge_diagram()
    print("sifu_pair.svg, sifu_bridge.svg -", HERE)
