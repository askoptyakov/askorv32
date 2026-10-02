"""
bootimage - образ программы askoRV32 для загрузчика из внешней SPI-флеш (контроллер spiflash_top,
hw/src/periph/spiflash/README.md, «Формат образа»).

Образ - 32-битные слова младшим байтом вперёд:
    MAGIC 0x31565241 ("ARV1")
    сегменты: адрес (кратен 4; 0x00xx_xxxx - IMEM, 0x10xx_xxxx - DMEM), число слов N, N слов
    конец:    адрес 0, число слов 0
    контрольное слово: сумма всех слов образа (вместе с ним) по модулю 2^32 равна 0

Сегменты берутся из ELF: загружаемые сегменты программы (PT_LOAD) с данными, адрес - VMA (адрес, по
которому программа работает): .text - в IMEM с 0, .data/.rodata - в DMEM с 0x1000_0000 (у .data в
GW1NR9.lds адрес загрузки LMA 0x8000 - для mergetool, загрузчику он не нужен). .bss обнуляет start.S.

Запуск:  py sw/bootimage/bootimage.py fw/Debug/riscv.elf [-o riscv_flash.bin] [--imem-kb 16 --dmem-kb 8]
Из Python: segments_from_elf(path) -> [(адрес, байты)], build(segments) -> bytes.
"""
import argparse
import struct
import sys
from pathlib import Path

MAGIC = 0x31565241
MAX_WORDS = 16384               #Предел образа в загрузчике (BOOT_WORDS): 64 кБайт
REGIONS = {0x00: "IMEM", 0x10: "DMEM"}


class ImageError(Exception):
    pass


def segments_from_elf(path, lma=False):
    """Загружаемые сегменты ELF32 (RISC-V, little-endian) с данными: [(VMA, байты)]; lma=True - по адресам
    загрузки (LMA, как в riscv.bin для mergetool: .data с 0x8000)."""
    data = Path(path).read_bytes()
    if data[:4] != b"\x7fELF" or data[4] != 1 or data[5] != 1:
        raise ImageError(f"{path}: не ELF32 little-endian")
    e_phoff, = struct.unpack_from("<I", data, 28)
    e_phentsize, e_phnum = struct.unpack_from("<HH", data, 42)
    segs = []
    for i in range(e_phnum):
        p_type, p_offset, p_vaddr, p_paddr, p_filesz, p_memsz, p_flags, p_align = \
            struct.unpack_from("<8I", data, e_phoff + i * e_phentsize)
        if p_type == 1 and p_filesz > 0:                    #PT_LOAD
            segs.append((p_paddr if lma else p_vaddr, data[p_offset:p_offset + p_filesz]))
    if not segs:
        raise ImageError(f"{path}: нет загружаемых сегментов")
    return sorted(segs)


def build(segments, mem_bytes=None):
    """Образ из сегментов [(адрес, байты)]. mem_bytes - {0x00: размер IMEM, 0x10: размер DMEM} для проверки."""
    words = [MAGIC]
    total = 0
    for addr, blob in segments:
        if addr % 4:
            raise ImageError(f"сегмент 0x{addr:08X}: адрес не кратен 4")
        region = addr >> 24
        if region not in REGIONS:
            raise ImageError(f"сегмент 0x{addr:08X}: вне IMEM (0x00xx_xxxx) и DMEM (0x10xx_xxxx)")
        blob = bytes(blob) + b"\0" * (-len(blob) % 4)
        end = (addr & 0xFFFFFF) + len(blob)
        if mem_bytes and region in mem_bytes and end > mem_bytes[region]:
            raise ImageError(f"сегмент 0x{addr:08X}: {len(blob)} Байт не помещается в {REGIONS[region]} "
                             f"({mem_bytes[region]} Байт)")
        n = len(blob) // 4
        words += [addr, n] + list(struct.unpack(f"<{n}I", blob))
        total += n
    words += [0, 0]
    words.append((-sum(words)) & 0xFFFFFFFF)
    if len(words) > MAX_WORDS:
        raise ImageError(f"образ {len(words)} слов больше предела загрузчика {MAX_WORDS}")
    return struct.pack(f"<{len(words)}I", *words)


def describe(segments):
    return ", ".join(f"{REGIONS.get(a >> 24, '?')} 0x{a:08X} {len(b)} Байт" for a, b in segments)


def main():
    ap = argparse.ArgumentParser(description="Образ программы для загрузчика из SPI-флеш askoRV32")
    ap.add_argument("elf", help="программа (ELF)")
    ap.add_argument("-o", "--output", help="файл образа (по умолчанию <elf>_flash.bin)")
    ap.add_argument("--imem-kb", type=int, help="размер IMEM для проверки, кБайт")
    ap.add_argument("--dmem-kb", type=int, help="размер DMEM для проверки, кБайт")
    a = ap.parse_args()
    try:
        sys.stdout.reconfigure(encoding="utf-8")
    except Exception:
        pass
    elf = Path(a.elf)
    out = Path(a.output) if a.output else elf.with_name(elf.stem + "_flash.bin")
    mem = {k: v * 1024 for k, v in ((0x00, a.imem_kb), (0x10, a.dmem_kb)) if v}
    try:
        segs = segments_from_elf(elf)
        img = build(segs, mem)
    except ImageError as e:
        print("ОШИБКА: " + str(e), file=sys.stderr)
        return 1
    out.write_bytes(img)
    print(f"{out.name}: {len(img)} Байт ({describe(segs)})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
