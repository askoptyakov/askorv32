"""
Генератор тестовых программ RV32IM для askoRV32.

Для каждой инструкции создаётся файл rv32i/<инструкция>.S из макросов riscv_test.h.
Ожидаемые значения вычисляет эталонная модель RV32IM (функции ниже), а не человек.

Запуск (из любой папки):  py hw/sim/tests/gen_rv32i.py
"""
from pathlib import Path

M32 = 0xFFFFFFFF
OUT_DIR = Path(__file__).resolve().parent / "rv32i"


# ----------------------------------------------------------------------------------------
# Эталонная модель RV32I
# ----------------------------------------------------------------------------------------
def u32(x):
    return x & M32


def s32(x):
    x &= M32
    return x - (1 << 32) if x & 0x80000000 else x


def sext(value, bits):
    value &= (1 << bits) - 1
    return value - (1 << bits) if value & (1 << (bits - 1)) else value


RR = {
    "add":  lambda a, b: u32(a + b),
    "sub":  lambda a, b: u32(a - b),
    "sll":  lambda a, b: u32(a << (b & 31)),
    "slt":  lambda a, b: int(s32(a) < s32(b)),
    "sltu": lambda a, b: int(u32(a) < u32(b)),
    "xor":  lambda a, b: u32(a ^ b),
    "srl":  lambda a, b: u32(a) >> (b & 31),
    "sra":  lambda a, b: u32(s32(a) >> (b & 31)),
    "or":   lambda a, b: u32(a | b),
    "and":  lambda a, b: u32(a & b),
}

# imm - 12-битная константа со знаком (для сдвигов - shamt 0..31)
IMM = {
    "addi":  lambda a, i: u32(a + i),
    "slti":  lambda a, i: int(s32(a) < i),
    "sltiu": lambda a, i: int(u32(a) < u32(i)),
    "xori":  lambda a, i: u32(a ^ i),
    "ori":   lambda a, i: u32(a | i),
    "andi":  lambda a, i: u32(a & i),
    "slli":  lambda a, i: u32(a << i),
    "srli":  lambda a, i: u32(a) >> i,
    "srai":  lambda a, i: u32(s32(a) >> i),
}

BRANCH = {
    "beq":  lambda a, b: u32(a) == u32(b),
    "bne":  lambda a, b: u32(a) != u32(b),
    "blt":  lambda a, b: s32(a) < s32(b),
    "bge":  lambda a, b: s32(a) >= s32(b),
    "bltu": lambda a, b: u32(a) < u32(b),
    "bgeu": lambda a, b: u32(a) >= u32(b),
}

LOAD = {  # размер в байтах, знаковое расширение
    "lb": (1, True), "lh": (2, True), "lw": (4, True), "lbu": (1, False), "lhu": (2, False),
}

STORE = {"sb": 1, "sh": 2, "sw": 4}


# Расширение M. Деление округляется к нулю, знак остатка - знак делимого.
# Особые случаи (спецификация, а не ловушки): деление на 0 - частное все единицы, остаток - делимое;
# переполнение -2^31 / -1 - частное -2^31, остаток 0.
def ref_div(a, b):
    a, b = s32(a), s32(b)
    if b == 0:
        return M32
    q = abs(a) // abs(b)
    return u32(-q if (a < 0) != (b < 0) else q)


def ref_rem(a, b):
    a, b = s32(a), s32(b)
    if b == 0:
        return u32(a)
    r = abs(a) % abs(b)
    return u32(-r if a < 0 else r)


MD = {
    "mul":    lambda a, b: u32(a * b),
    "mulh":   lambda a, b: u32((s32(a) * s32(b)) >> 32),
    "mulhsu": lambda a, b: u32((s32(a) * u32(b)) >> 32),
    "mulhu":  lambda a, b: u32((u32(a) * u32(b)) >> 32),
    "div":    ref_div,
    "divu":   lambda a, b: M32 if u32(b) == 0 else u32(a) // u32(b),
    "rem":    ref_rem,
    "remu":   lambda a, b: u32(a) if u32(b) == 0 else u32(a) % u32(b),
}


# ----------------------------------------------------------------------------------------
# Наборы тестовых значений
# ----------------------------------------------------------------------------------------
ARITH_PAIRS = [
    (0x00000000, 0x00000000), (0x00000001, 0x00000001), (0x00000003, 0x00000007),
    (0x00000000, 0xFFFF8000), (0x80000000, 0x00000000), (0x80000000, 0xFFFF8000),
    (0x00000000, 0x00007FFF), (0x7FFFFFFF, 0x00000000), (0x7FFFFFFF, 0x00007FFF),
    (0x80000000, 0x00007FFF), (0x7FFFFFFF, 0xFFFF8000), (0x00000000, 0xFFFFFFFF),
    (0xFFFFFFFF, 0x00000001), (0xFFFFFFFF, 0xFFFFFFFF), (0x00000001, 0x7FFFFFFF),
    (0x7FFFFFFF, 0x80000000), (0x80000000, 0x7FFFFFFF), (0xFFFFFFFF, 0x00000000),
    (0x55555555, 0xAAAAAAAA), (0x12345678, 0xFEDCBA98), (0x0F0F0F0F, 0x00FF00FF),
]

# Дополнительно для умножения и деления: знаки операндов, переполнение, большие беззнаковые
MD_PAIRS = [
    (0x80000000, 0xFFFFFFFF), (0x80000000, 0x00000001), (0x00000007, 0xFFFFFFFD),
    (0xFFFFFFF9, 0x00000003), (0xFFFFFFF9, 0xFFFFFFFD), (0x00000007, 0x00000003),
    (0xFFFFFFFE, 0xFFFFFFFF), (0xFFFFFFFF, 0x80000000), (0x12345678, 0x0000ABCD),
    (0xDEADBEEF, 0x00000010), (0x00010000, 0x00010000), (0xFFFF0000, 0x0000FFFF),
    (0x0001E240, 0x80000001), (0xFFFFFFFF, 0x7FFFFFFF), (0x76543210, 0x76543211),
]

SHIFT_VALUES = [0x00000001, 0xFFFFFFFF, 0x21212121, 0x80000000, 0x12345678]
SHIFT_AMOUNTS = [0, 1, 7, 14, 31]
# Для сдвигов регистром используются только младшие 5 бит rs2
SHIFT_RS2_HIGH_BITS = [0xFFFFFFC0, 0xFFFFFFC1, 0xFFFFFFE7, 0xFFFFFFCE, 0xFFFFFFFF, 0x00000020]

IMM_PAIRS = [
    (0x00000000, 0), (0x00000001, 1), (0x00000003, 7), (0x00000000, -2048),
    (0x80000000, 0), (0x80000000, -2048), (0x00000000, 2047), (0x7FFFFFFF, 0),
    (0x7FFFFFFF, 2047), (0x80000000, 2047), (0x7FFFFFFF, -2048), (0x00000000, -1),
    (0xFFFFFFFF, 1), (0xFFFFFFFF, -1), (0x00FF00FF, 0x0F0), (0xFF00FF00, -241),
    # imm[10] = 1: бит 30 инструкции (funct7[5] в R-типе) не должен влиять на addi/xori/...
    (0x12345678, 1024), (0x12345678, -1024), (0x00000400, 1365), (0xAAAAAAAA, -683),
]

IMM_SHIFT_AMOUNTS = [0, 1, 7, 14, 20, 31]

BRANCH_PAIRS = [
    (0x00000000, 0x00000000), (0x00000001, 0x00000001), (0xFFFFFFFF, 0xFFFFFFFF),
    (0x00000000, 0x00000001), (0x00000001, 0x00000000), (0xFFFFFFFF, 0x00000001),
    (0x00000001, 0xFFFFFFFF), (0xFFFFFFFE, 0xFFFFFFFF), (0xFFFFFFFF, 0xFFFFFFFE),
    (0x7FFFFFFF, 0x80000000), (0x80000000, 0x7FFFFFFF), (0x80000000, 0x80000000),
    (0x00000000, 0x80000000), (0x80000000, 0x00000000), (0x12345678, 0x12345679),
]

LUI_IMMS = [0x00000, 0x00001, 0x7FFFF, 0x80000, 0xFFFFF, 0x12345, 0xABCDE]
AUIPC_IMMS = [0x00000, 0x00001, 0x7FFFF, 0x80000, 0xFFFFF, 0x12345, 0xFFFF0]

# Комбинации числа nop для тестов байпаса (как в riscv-tests)
BYPASS_12 = [(0, 0), (0, 1), (0, 2), (1, 0), (1, 1), (2, 0)]
BYPASS_1 = [0, 1, 2]

# Данные для загрузок: байты подобраны так, чтобы знак и позиция байта были различимы
LOAD_DATA = [0x00FF80FF, 0xFF007F00, 0x0FF00FF0, 0xF00FF00F, 0x80818283, 0x7F7E7D7C]
MERGE_FILL = 0xA5A5A5A5


# ----------------------------------------------------------------------------------------
# Вспомогательные функции генерации
# ----------------------------------------------------------------------------------------
def hx(v):
    return f"0x{u32(v):08x}"


def load_ref(inst, words, byte_addr):
    size, signed = LOAD[inst]
    mem = b"".join(w.to_bytes(4, "little") for w in words)
    raw = int.from_bytes(mem[byte_addr:byte_addr + size], "little")
    return u32(sext(raw, size * 8)) if signed else raw


def nonzero_pair(fn, pairs):
    """Первая пара значений с ненулевым результатом - для тестов байпаса."""
    for a, b in pairs:
        if fn(a, b):
            return a, b
    return pairs[0]


class Program:
    def __init__(self, inst, title):
        self.inst, self.title = inst, title
        self.lines, self.data, self.n = [], [], 0

    def test(self, macro, *args):
        self.n += 1
        self.lines.append(f"    {macro}({', '.join(str(a) for a in (self.n,) + args)})")

    def comment(self, text):
        self.lines.append(f"\n    //{text}")

    def write(self):
        OUT_DIR.mkdir(parents=True, exist_ok=True)
        body = [
            f"// {self.inst}.S - тесты инструкции {self.inst.upper()}: {self.title}",
            "// Сгенерировано gen_rv32i.py - не редактировать вручную.",
            '#include "riscv_test.h"',
            "",
            "RVTEST_CODE_BEGIN",
            *self.lines,
            "",
            "    j pass",
            "RVTEST_CODE_END",
        ]
        if self.data:
            body += ["", "RVTEST_DATA_BEGIN", *self.data]
        (OUT_DIR / f"{self.inst}.S").write_text("\n".join(body) + "\n", encoding="utf-8", newline="\n")
        return self.n


# ----------------------------------------------------------------------------------------
# Генераторы по классам инструкций
# ----------------------------------------------------------------------------------------
def gen_rr(inst):
    fn = RR[inst] if inst in RR else MD[inst]
    p = Program(inst, "регистр-регистр" if inst in RR else "расширение M")
    is_shift = inst in ("sll", "srl", "sra")
    p.comment("Значения")
    if is_shift:
        for a in SHIFT_VALUES:
            for sh in SHIFT_AMOUNTS:
                p.test("TEST_RR_OP", inst, hx(fn(a, sh)), hx(a), hx(sh))
        p.comment("Используются только младшие 5 бит rs2")
        for b in SHIFT_RS2_HIGH_BITS:
            p.test("TEST_RR_OP", inst, hx(fn(0x21212121, b)), hx(0x21212121), hx(b))
        a, b = 0x87654321, 7
    else:
        for a, b in ARITH_PAIRS + (MD_PAIRS if inst in MD else []):
            p.test("TEST_RR_OP", inst, hx(fn(a, b)), hx(a), hx(b))
        a, b = nonzero_pair(fn, [(0x87654321, 0x0000000B), (0x0000000B, 0x87654321)])
    p.comment("Совпадение регистров")
    p.test("TEST_RR_SRC1_EQ_DEST", inst, hx(fn(a, b)), hx(a), hx(b))
    p.test("TEST_RR_SRC2_EQ_DEST", inst, hx(fn(a, b)), hx(a), hx(b))
    c = 0x0000000D
    p.test("TEST_RR_SRC12_EQ_DEST", inst, hx(fn(c, c)), hx(c))
    p.comment("Байпас (конвейер)")
    for k in BYPASS_1:
        p.test("TEST_RR_DEST_BYPASS", k, inst, hx(fn(a, b)), hx(a), hx(b))
    for k1, k2 in BYPASS_12:
        p.test("TEST_RR_SRC12_BYPASS", k1, k2, inst, hx(fn(a, b)), hx(a), hx(b))
    for k1, k2 in BYPASS_12:
        p.test("TEST_RR_SRC21_BYPASS", k1, k2, inst, hx(fn(a, b)), hx(a), hx(b))
    p.comment("Регистр x0")
    p.test("TEST_RR_ZEROSRC1", inst, hx(fn(0, b)), hx(b))
    p.test("TEST_RR_ZEROSRC2", inst, hx(fn(a, 0)), hx(a))
    p.test("TEST_RR_ZEROSRC12", inst, hx(fn(0, 0)))
    p.test("TEST_RR_ZERODEST", inst, hx(a), hx(b))
    if inst in MD:
        gen_md_chain(p, inst, fn, a, b)
    return p.write()


def gen_md_chain(p, inst, fn, a, b):
    """Зависимые цепочки умножения и деления: результат нужен сразу следующей инструкции
    (приостановка на 1 такт после mul, удержание стадий на время деления)."""
    other = "divu" if inst.startswith("mul") else "mul"
    fo = MD[other]
    c = 0x00000005
    p.comment("Зависимые цепочки (конвейер)")
    r = fn(a, b)
    p.test("TEST_CASE", "x14", hx(fn(r, b)), f'("{inst}->{inst}")',
           f"li x1, {hx(a)}; li x2, {hx(b)}; {inst} x3, x1, x2; {inst} x14, x3, x2")
    p.test("TEST_CASE", "x14", hx(fo(r, c)), f'("{inst}->{other}")',
           f"li x1, {hx(a)}; li x2, {hx(b)}; li x4, {hx(c)}; {inst} x3, x1, x2; {other} x14, x3, x4")
    r2 = fo(a, c)
    p.test("TEST_CASE", "x14", hx(fn(r2, b)), f'("{other}->{inst}")',
           f"li x1, {hx(a)}; li x2, {hx(b)}; li x4, {hx(c)}; {other} x3, x1, x4; {inst} x14, x3, x2")
    # Инструкции после деления стоят в D и F, пока оно идёт: ни одна не должна потеряться
    p.test("TEST_CASE", "x14", hx(u32(r + a + 1 + 2)), f'("{inst}[addi,addi,add]")',
           f"li x1, {hx(a)}; li x2, {hx(b)}; {inst} x3, x1, x2; addi x4, x1, 1; addi x4, x4, 2; add x14, x3, x4")
    # Запись результата в память сразу после операции
    p.test("TEST_CASE", "x14", hx(r), f'("{inst}->sw->lw")',
           f"la x5, md_buf; li x1, {hx(a)}; li x2, {hx(b)}; {inst} x3, x1, x2; sw x3, 0(x5); lw x14, 0(x5)")
    # Переход по результату сразу после операции
    p.test("TEST_CASE", "x14", hx(1 if r == 0 else 2), f'("{inst}->bnez")',
           f"li x1, {hx(a)}; li x2, {hx(b)}; li x14, 2; {inst} x3, x1, x2; bnez x3, 1f; li x14, 1; 1: nop")
    if not any(l.startswith("md_buf:") for l in p.data):
        p.data += ["    .align 2", "md_buf: .word 0"]


def gen_imm(inst):
    fn = IMM[inst]
    p = Program(inst, "регистр-константа")
    p.comment("Значения")
    if inst in ("slli", "srli", "srai"):
        for a in SHIFT_VALUES:
            for sh in IMM_SHIFT_AMOUNTS:
                p.test("TEST_IMM_OP", inst, hx(fn(a, sh)), hx(a), sh)
        a, i = 0x87654321, 7
    else:
        for a, i in IMM_PAIRS:
            p.test("TEST_IMM_OP", inst, hx(fn(a, i)), hx(a), i)
        a, i = nonzero_pair(fn, [(0x87654321, 0x0B), (0x0000000B, -1), (0x0000000B, 0x0F)])
    p.comment("Совпадение регистров")
    p.test("TEST_IMM_SRC1_EQ_DEST", inst, hx(fn(a, i)), hx(a), i)
    p.comment("Байпас (конвейер)")
    for k in BYPASS_1:
        p.test("TEST_IMM_DEST_BYPASS", k, inst, hx(fn(a, i)), hx(a), i)
    for k in BYPASS_1:
        p.test("TEST_IMM_SRC1_BYPASS", k, inst, hx(fn(a, i)), hx(a), i)
    p.comment("Регистр x0")
    p.test("TEST_IMM_ZEROSRC1", inst, hx(fn(0, i)), i)
    p.test("TEST_IMM_ZERODEST", inst, hx(a), i)
    return p.write()


def gen_lui():
    p = Program("lui", "загрузка старших 20 бит")
    p.comment("Значения")
    for imm in LUI_IMMS:
        p.test("TEST_LUI", hx(imm << 12), hx(imm))
    p.comment("Байпас (конвейер)")
    for k in BYPASS_1:
        p.test("TEST_LUI_DEST_BYPASS", k, hx(0x12345 << 12), hx(0x12345))
    p.comment("Регистр x0")
    p.test("TEST_LUI_ZERODEST", hx(0x12345))
    return p.write()


def gen_auipc():
    p = Program("auipc", "PC + старшие 20 бит")
    p.comment("Значения (ожидаемое значение считает компоновщик от адреса auipc)")
    for imm in AUIPC_IMMS:
        p.test("TEST_AUIPC", hx(imm), sext(imm, 20) << 12)
    p.comment("Байпас (конвейер)")
    for k in BYPASS_1:
        p.test("TEST_AUIPC_DEST_BYPASS", k, hx(0x00001), 1 << 12)
    return p.write()


def gen_branch(inst):
    fn = BRANCH[inst]
    p = Program(inst, "условный переход")
    p.comment("Значения: переход выполняется / не выполняется")
    taken_pair = nottaken_pair = None
    for a, b in BRANCH_PAIRS:
        if fn(a, b):
            p.test("TEST_BR2_OP_TAKEN", inst, hx(a), hx(b))
            taken_pair = taken_pair or (a, b)
        else:
            p.test("TEST_BR2_OP_NOTTAKEN", inst, hx(a), hx(b))
            nottaken_pair = nottaken_pair or (a, b)
    # Пары для байпаса: значения, которые не совпадут с обнулёнными регистрами
    taken_pair = next((ab for ab in [(0x12345678, 0x12345678), (0x12345678, 0x87654321),
                                     (0x87654321, 0x12345678)] if fn(*ab)), taken_pair)
    nottaken_pair = next((ab for ab in [(0x12345678, 0x12345678), (0x12345678, 0x87654321),
                                        (0x87654321, 0x12345678)] if not fn(*ab)), nottaken_pair)
    p.comment("Сброс конвейера после выполненного перехода")
    p.test("TEST_BR2_FLUSH", inst, hx(taken_pair[0]), hx(taken_pair[1]))
    p.comment("Байпас (конвейер)")
    for taken, (a, b) in ((1, taken_pair), (0, nottaken_pair)):
        for k1, k2 in BYPASS_12:
            p.test("TEST_BR2_SRC12_BYPASS", k1, k2, taken, inst, hx(a), hx(b))
        for k1, k2 in BYPASS_12:
            p.test("TEST_BR2_SRC21_BYPASS", k1, k2, taken, inst, hx(a), hx(b))
        for k in BYPASS_1:
            p.test("TEST_BR2_LOAD_BYPASS", k, taken, inst, hx(a), hx(b), "tscratch")
    p.data += ["tscratch: .word 0"]
    return p.write()


def gen_jal():
    p = Program("jal", "безусловный переход")
    p.test("TEST_JAL_LINK")
    p.test("TEST_JAL_BACKWARD")
    p.test("TEST_JAL_FLUSH")
    p.comment("Байпас (конвейер)")
    for k in BYPASS_1:
        p.test("TEST_JAL_DEST_BYPASS", k)
    p.comment("Регистр x0")
    p.test("TEST_JAL_ZERODEST")
    return p.write()


def gen_jalr():
    p = Program("jalr", "переход по регистру")
    for off in (0, 8, -8, 2047, -2048):
        p.test("TEST_JALR", off)
    p.test("TEST_JALR_RD_EQ_RS1")
    p.test("TEST_JALR_FLUSH")
    p.comment("Байпас (конвейер)")
    for k in BYPASS_1:
        p.test("TEST_JALR_SRC1_BYPASS", k)
    for k in BYPASS_1:
        p.test("TEST_JALR_LOAD_BYPASS", k)
    p.comment("Младший бит адреса перехода обнуляется: (rs1 + imm) & ~1")
    p.test("TEST_JALR_LSB", 1, 0)
    p.test("TEST_JALR_LSB", 0, 1)
    p.comment("Регистр x0")
    p.test("TEST_JALR_ZERODEST")
    return p.write()


def gen_load(inst):
    size, _ = LOAD[inst]
    p = Program(inst, "загрузка из памяти")
    p.comment("Значения: все допустимые смещения внутри слов, положительные и отрицательные")
    offsets = range(0, 16, size)
    for off in offsets:
        p.test("TEST_LD_OP", inst, hx(load_ref(inst, LOAD_DATA, off)), off, "tdat")
    for off in offsets:  # база в середине массива, отрицательные смещения
        p.test("TEST_LD_OP", inst, hx(load_ref(inst, LOAD_DATA, 16 + off - 16)), off - 16, "tdat16")
    p.test("TEST_LD_OP", inst, hx(load_ref(inst, LOAD_DATA, 20)), 4, "tdat16")
    p.comment("Совпадение регистров")
    p.test("TEST_LD_RD_EQ_RS1", inst, hx(load_ref(inst, LOAD_DATA, 4)), 4, "tdat")
    p.comment("Байпас и приостановка конвейера (load-use)")
    for k in BYPASS_1:
        p.test("TEST_LD_DEST_BYPASS", k, inst, hx(load_ref(inst, LOAD_DATA, 4)), 4, "tdat")
    for k in BYPASS_1:
        p.test("TEST_LD_DEST_BYPASS2", k, inst, hx(load_ref(inst, LOAD_DATA, 8)), 8, "tdat")
    for k in BYPASS_1:
        p.test("TEST_LD_SRC1_BYPASS", k, inst, hx(load_ref(inst, LOAD_DATA, 12)), 12, "tdat")
    p.comment("Регистр x0")
    p.test("TEST_LD_ZERODEST", inst, 0, "tdat")
    p.data += ["tdat:"] + [f"    .word {hx(w)}" for w in LOAD_DATA[:4]]
    p.data += ["tdat16:"] + [f"    .word {hx(w)}" for w in LOAD_DATA[4:]]
    return p.write()


def gen_store(inst):
    size = STORE[inst]
    ld = {"sb": "lb", "sh": "lh", "sw": "lw"}[inst]
    p = Program(inst, "запись в память (проверка обратным чтением)")
    values = [0xFFFFFFAA, 0x0000000A, 0xFFFFAA00, 0x0000A00A, 0xAA00AA00, 0x00AA00AA,
              0x0AA00AA0, 0xA00AA00A]
    val_mask = (1 << (size * 8)) - 1

    def readback(v):
        return u32(sext(v & val_mask, size * 8))

    p.comment("Значения: разные смещения, положительные и отрицательные")
    for i, v in enumerate(values):
        off = (i * size) % 16
        p.test("TEST_ST_OP", ld, inst, hx(readback(v)), off, "tscratch")
    for i, v in enumerate(values[:4]):
        off = -16 + i * size * 2
        p.test("TEST_ST_OP", ld, inst, hx(readback(v)), off, "tscratch32")
    p.comment("Байтовые стробы: соседние байты слова не меняются")
    for off in range(0, 4, size):
        v = 0x12345678
        fill = MERGE_FILL.to_bytes(4, "little")
        merged = bytearray(fill)
        merged[off:off + size] = (v & val_mask).to_bytes(size, "little")
        p.test("TEST_ST_MERGE", inst, hx(v), off, "tscratch48", hx(MERGE_FILL),
               hx(int.from_bytes(merged, "little")))
    p.comment("Байпас (конвейер)")
    v = readback(0x87654321) if size < 4 else 0x87654321
    for k1, k2 in BYPASS_12:
        p.test("TEST_ST_SRC12_BYPASS", k1, k2, ld, inst, hx(v), 4, "tscratch")
    for k1, k2 in BYPASS_12:
        p.test("TEST_ST_SRC21_BYPASS", k1, k2, ld, inst, hx(v), 8, "tscratch")
    for k in BYPASS_1:
        p.test("TEST_ST_LOAD_DATA", k, ld, inst, hx(v), 12, "tscratch", "tsrc")
    p.data += ["tsrc: .word 0", "tscratch: .zero 32", "tscratch32: .zero 16", "tscratch48: .zero 16"]
    return p.write()


# ----------------------------------------------------------------------------------------
ORDER = (["lui", "auipc", "jal", "jalr"] + list(BRANCH) + list(LOAD) + list(STORE)
         + ["addi", "slti", "sltiu", "xori", "ori", "andi", "slli", "srli", "srai"] + list(RR) + list(MD))


def main():
    total = 0
    for inst in ORDER:
        if inst in RR or inst in MD:
            n = gen_rr(inst)
        elif inst in IMM:
            n = gen_imm(inst)
        elif inst in BRANCH:
            n = gen_branch(inst)
        elif inst in LOAD:
            n = gen_load(inst)
        elif inst in STORE:
            n = gen_store(inst)
        else:
            n = {"lui": gen_lui, "auipc": gen_auipc, "jal": gen_jal, "jalr": gen_jalr}[inst]()
        total += n
        print(f"{inst:6s} {n:3d} тестов")
    print(f"Итого: {len(ORDER)} инструкций, {total} тестов -> {OUT_DIR}")


if __name__ == "__main__":
    main()
