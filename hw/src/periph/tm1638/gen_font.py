"""
Знакогенератор TM1638: код символа (cp1251) -> сегменты семисегментного индикатора.

    py hw/src/periph/tm1638/gen_font.py

Создаёт tm1638_font.sv (ПЗУ 256 x 8 с синхронным чтением - один блок BSRAM) и таблицу символов
font.md для README. Начертание задаётся буквами сегментов:

       --a--
      |     |
      f     b
      |     |
       --g--
      |     |
      e     c
      |     |
       --d--   h (точка)

Бит сегмента в коде индикатора: a - 0, b - 1, ..., g - 6, h - 7 (как в tm1638_board_controller).
Семь сегментов не передают все буквы: часть начертаний приближённая, некоторые буквы совпадают
(например Н и Х, П и Л). Символ без начертания выводится пустым.
"""
from pathlib import Path

HERE = Path(__file__).resolve().parent

GLYPHS = {
    # Цифры
    "0": "abcdef", "1": "bc", "2": "abdeg", "3": "abcdg", "4": "bcfg",
    "5": "acdfg", "6": "acdefg", "7": "abc", "8": "abcdefg", "9": "abcdfg",
    # Латиница, прописные
    "A": "abcefg", "B": "cdefg", "C": "adef", "D": "bcdeg", "E": "adefg", "F": "aefg",
    "G": "acdef", "H": "bcefg", "I": "ef", "J": "bcde", "K": "acefg", "L": "def",
    "M": "abcef", "N": "ceg", "O": "abcdef", "P": "abefg", "Q": "abcfg", "R": "eg",
    "S": "acdfg", "T": "defg", "U": "bcdef", "V": "cde", "W": "bcdef", "X": "bcefg",
    "Y": "bcdfg", "Z": "abdeg",
    # Латиница, строчные (где есть отдельное начертание)
    "a": "abcdeg", "b": "cdefg", "c": "deg", "d": "bcdeg", "e": "abdefg", "f": "aefg",
    "g": "abcdfg", "h": "cefg", "i": "c", "j": "bcd", "k": "acefg", "l": "ef",
    "m": "ceg", "n": "ceg", "o": "cdeg", "p": "abefg", "q": "abcfg", "r": "eg",
    "s": "acdfg", "t": "defg", "u": "cde", "v": "cde", "w": "cde", "x": "bcefg",
    "y": "bcdfg", "z": "abdeg",
    # Знаки
    " ": "", "-": "g", "_": "d", "=": "dg", '"': "bf", "'": "f", "`": "b",
    "(": "adef", ")": "abcd", "[": "adef", "]": "abcd", "?": "abeg", "/": "beg",
    "\\": "cfg", "|": "ef", "^": "abf", "°": "abfg", "*": "abfg",
    ".": "h", ",": "h", "!": "bh", ":": "h",
    # Кириллица, прописные
    "А": "abcefg", "Б": "acdefg", "В": "abcdefg", "Г": "aef", "Д": "bcdeg", "Е": "adefg",
    "Ё": "adefg", "Ж": "bcefg", "З": "abcdg", "И": "bcdef", "Й": "bcdef", "К": "acefg",
    "Л": "abcef", "М": "abcef", "Н": "bcefg", "О": "abcdef", "П": "abcef", "Р": "abefg",
    "С": "adef", "Т": "defg", "У": "bcdfg", "Ф": "abfg", "Х": "bcefg", "Ц": "cdef",
    "Ч": "bcfg", "Ш": "bcdef", "Щ": "bcdef", "Ъ": "cdefg", "Ы": "cdefg", "Ь": "cdefg",
    "Э": "abcdg", "Ю": "bcefg", "Я": "abcfg",
    # Кириллица, строчные: отдельное начертание, где оно понятнее прописного
    "б": "acdefg", "в": "cdefg", "г": "eg", "д": "bcdeg", "е": "abdefg", "ё": "abdefg",
    "о": "cdeg", "р": "abefg", "с": "deg", "у": "bcdfg", "ч": "cfg", "ь": "cdefg",
}
# Остальные строчные кириллические - как прописные
for up, lo in zip("АБВГДЕЖЗИЙКЛМНОПРСТУФХЦЧШЩЪЫЬЭЮЯ", "абвгдежзийклмнопрстуфхцчшщъыьэюя"):
    GLYPHS.setdefault(lo, GLYPHS[up])


def seg_code(s):
    return sum(1 << "abcdefgh".index(ch) for ch in s)


def table():
    rom = [0] * 256
    for ch, s in GLYPHS.items():
        rom[ch.encode("cp1251")[0]] = seg_code(s)
    return rom


def main():
    rom = table()
    lines = [
        "//==============================================================================================",
        "// tm1638_font - знакогенератор TM1638: код символа cp1251 -> сегменты (ПЗУ 256 x 8, один блок BSRAM)",
        "//==============================================================================================",
        "//ФАЙЛ СОЗДАН hw/src/periph/tm1638/gen_font.py - начертания правятся там. Чтение синхронное:",
        "//сегменты символа code - на следующем такте. Бит: a - 0, ..., g - 6, h (точка) - 7.",
        "module tm1638_font",
        "   (input  logic       clk,",
        "    input  logic [7:0] code,",
        "    output logic [7:0] seg",
        ");",
        "    (* syn_romstyle = \"block_rom\" *) logic [7:0] q;",
        "    assign seg = q;",
        "    always_ff @(posedge clk)",
        "        case (code)",
    ]
    for c in range(256):
        if rom[c]:
            ch = bytes([c]).decode("cp1251", errors="replace")
            ch = {"\\": "обратная косая"}.get(ch, ch)
            lines.append(f"            8'h{c:02X}: q <= 8'h{rom[c]:02X};   //{ch}")
    lines += ["            default: q <= 8'h00;", "        endcase", "endmodule", ""]
    (HERE / "tm1638_font.sv").write_text("\n".join(lines), encoding="utf-8", newline="\n")

    md = ["| Символы | Как выглядят |", "|---|---|"]
    groups = [("Цифры", "0123456789"), ("Латиница", "ABCDEFGHIJKLMNOPQRSTUVWXYZ"),
              ("Латиница, строчные", "abcdefghijklmnopqrstuvwxyz"),
              ("Кириллица", "АБВГДЕЁЖЗИЙКЛМНОПРСТУФХЦЧШЩЪЫЬЭЮЯ"),
              ("Кириллица, строчные", "абвгдеёжзийклмнопрстуфхцчшщъыьэюя"),
              ("Знаки", " -_=\"'`()[]?/\\|^°*.,!:")]
    for title, chars in groups:
        md.append(f"| {title} | " + " ".join(f"`{c}`:{GLYPHS.get(c, '') or '—'}" for c in chars if c != "|") + " |")
    (HERE / "font.md").write_text("\n".join(md) + "\n", encoding="utf-8", newline="\n")
    print(f"tm1638_font.sv: {sum(1 for v in rom if v)} символов")


if __name__ == "__main__":
    main()
