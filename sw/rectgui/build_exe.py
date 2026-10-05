#!/usr/bin/env python3
"""Сборка пульта выпрямителя askoRV32 отдельной программой для Windows (без Eclipse).

Что нужно на ПК сборки:
- Eclipse с CDT (как для плагина, build.py): Java JustJ, SWT и пакет COM-порта CDT - из пула ~/.p2/pool/plugins;
- MSYS2 UCRT64 (C:\\msys64\\ucrt64\\bin): gcc и windres - запускатель RectPult.exe со значком;
- Python с Pillow - значок.

Результат: dist/RectPult/ - RectPult.exe, lib (rectgui.jar, SWT, COM-порт, serial.dll), runtime (Java JustJ,
около 180 МБ) - и dist/RectPult-<версия>.zip. Каталог переносится как есть, установка не нужна; на другом ПК
Eclipse и Java не нужны. Настройки пульта (порт, осциллограмма) - общие с плагином (реестр, ru/askorv32/rectgui).

Запуск:  py sw/rectgui/build_exe.py            (--no-zip - без архива, --gcc <каталог> - другой MSYS2)
"""
import argparse
import datetime
import importlib.util
import math
import os
import shutil
import subprocess
import sys
import zipfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
DIST = HERE / "dist"
APP = DIST / "RectPult"
STAGE = DIST / "stage"
MAIN = "ru.askorv32.rectgui.RectApp"
TITLE = "Пульт выпрямителя askoRV32"
#Классы вида Eclipse (нужен верстак Eclipse) в программу не входят
ECLIPSE_ONLY = {"RectView.java", "OpenViewHandler.java"}

_spec = importlib.util.spec_from_file_location("gwsoc_build", HERE.parent / "socgen" / "eclipse" / "build.py")
gb = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(gb)


def latest(pattern):
    found = sorted(gb.POOL.glob(pattern))
    if not found:
        sys.exit(f"Нет пакета {pattern} в {gb.POOL} - нужен Eclipse с CDT")
    return found[-1]


def run(cmd, **kw):
    r = subprocess.run([str(c) for c in cmd], capture_output=True, text=True, **kw)
    if r.returncode:
        sys.exit(f"Ошибка: {' '.join(str(c) for c in cmd[:3])} ...\n{r.stdout}{r.stderr}")
    return r


def icons(png_dir, ico):
    """Значок: выпрямленное напряжение (полуволны) над осью - как у плагина, в нескольких размерах"""
    from PIL import Image, ImageDraw
    big = Image.new("RGBA", (256, 256), (0, 0, 0, 0))
    d = ImageDraw.Draw(big)
    d.rounded_rectangle((8, 8, 248, 248), radius=44, fill=(28, 32, 40, 255))
    d.line((28, 200, 228, 200), fill=(150, 156, 166, 255), width=10)
    pts = [(28 + x, 200 - 140 * abs(math.sin(x / 200 * 3 * math.pi))) for x in range(0, 201)]
    d.line(pts, fill=(245, 158, 11, 255), width=16, joint="curve")
    png_dir.mkdir(parents=True, exist_ok=True)
    for s in (16, 32, 48, 256):
        big.resize((s, s), Image.LANCZOS).save(png_dir / f"app{s}.png")
    big.save(ico, sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])


def main():
    ap = argparse.ArgumentParser(description="Сборка RectPult.exe - пульт выпрямителя без Eclipse")
    ap.add_argument("--gcc", default="C:/msys64/ucrt64/bin", help="каталог gcc и windres (MSYS2 UCRT64)")
    ap.add_argument("--no-zip", action="store_true", help="не собирать архив")
    a = ap.parse_args()
    version = datetime.datetime.now().strftime("%Y.%m.%d.%H%M")
    gcc, windres = Path(a.gcc) / "gcc.exe", Path(a.gcc) / "windres.exe"
    if not gcc.exists() or not windres.exists():
        sys.exit(f"Нет gcc/windres в {a.gcc}: установите MSYS2 и пакет mingw-w64-ucrt-x86_64-gcc или укажите --gcc")

    java = gb.find_java()
    jre = java.parent.parent
    swt = latest("org.eclipse.swt.win32.win32.x86_64_*.jar")
    serial = latest("org.eclipse.cdt.native.serial_*.jar")
    print(f"Java: {jre}\nSWT: {swt.name}\nCOM-порт: {serial.name}")

    #1. Классы и значки -> rectgui.jar
    shutil.rmtree(STAGE, ignore_errors=True)
    cls = STAGE / "classes"
    cls.mkdir(parents=True)
    srcs = [p for p in (HERE / "src").rglob("*.java") if p.name not in ECLIPSE_ONLY]
    args = STAGE / "javac.args"
    args.write_text("\n".join(['-encoding', 'UTF-8', '--release', '21', '-nowarn', '-d', f'"{cls.as_posix()}"',
                               '-cp', f'"{swt.as_posix()};{serial.as_posix()}"'] + [f'"{s.as_posix()}"' for s in srcs]),
                    encoding="utf-8")
    run([java, "-m", "jdk.compiler/com.sun.tools.javac.Main", "@" + str(args)])
    ico = STAGE / "rectpult.ico"
    icons(cls / "icons", ico)
    jar = STAGE / "rectgui.jar"
    with zipfile.ZipFile(jar, "w", zipfile.ZIP_DEFLATED) as z:
        z.writestr("META-INF/MANIFEST.MF", f"Manifest-Version: 1.0\r\nMain-Class: {MAIN}\r\n"
                                           f"Implementation-Title: {TITLE}\r\nImplementation-Version: {version}\r\n\r\n")
        for f in sorted(cls.rglob("*")):
            if f.is_file():
                z.write(f, f.relative_to(cls).as_posix())
    print(f"rectgui.jar: {len(srcs)} исходных файлов")

    #2. Запускатель RectPult.exe со значком и сведениями о версии
    v4 = ",".join(version.replace(".", ",").split(",")[:4])
    rc = STAGE / "rectpult.rc"
    rc.write_text(f'''#include <winver.h>
1 ICON "{ico.as_posix()}"
1 VERSIONINFO
FILEVERSION {v4}
PRODUCTVERSION {v4}
FILEOS VOS_NT_WINDOWS32
FILETYPE VFT_APP
BEGIN
  BLOCK "StringFileInfo"
  BEGIN
    BLOCK "041904B0"
    BEGIN
      VALUE "FileDescription", "{TITLE}"
      VALUE "ProductName", "{TITLE}"
      VALUE "FileVersion", "{version}"
      VALUE "ProductVersion", "{version}"
      VALUE "OriginalFilename", "RectPult.exe"
    END
  END
  BLOCK "VarFileInfo"
  BEGIN
    VALUE "Translation", 0x419, 1200
  END
END
''', encoding="utf-8")
    env = dict(os.environ, PATH=str(Path(a.gcc)) + os.pathsep + os.environ.get("PATH", ""))
    res = STAGE / "rectpult_res.o"
    run([windres, "--codepage=65001", "-O", "coff", "-i", rc, "-o", res], env=env)
    exe = STAGE / "RectPult.exe"
    run([gcc, "-O2", "-municode", "-mwindows", "-static", "-s", HERE / "launcher" / "rectpult.c", res, "-o", exe], env=env)

    #3. Каталог программы: exe, lib, runtime (Java копируется, только если версия сменилась)
    APP.mkdir(parents=True, exist_ok=True)
    shutil.copy2(exe, APP / "RectPult.exe")
    lib = APP / "lib"
    shutil.rmtree(lib, ignore_errors=True)
    lib.mkdir()
    shutil.copy2(jar, lib / "rectgui.jar")
    shutil.copy2(swt, lib / swt.name)
    shutil.copy2(serial, lib / serial.name)
    with zipfile.ZipFile(serial) as z:
        dll = next(n for n in z.namelist() if n.endswith("serial.dll") and "x86_64" in n)
        (lib / "serial.dll").write_bytes(z.read(dll))
    rt, mark = APP / "runtime", APP / "runtime" / ".justj"
    if not (mark.exists() and mark.read_text(encoding="utf-8") == jre.parent.name):
        shutil.rmtree(rt, ignore_errors=True)
        shutil.copytree(jre, rt)
        mark.write_text(jre.parent.name, encoding="utf-8")
        print(f"runtime: скопирована Java {jre.parent.name}")
    (APP / "ВЕРСИЯ.txt").write_text(f"{TITLE}\nверсия {version}\nJava: {jre.parent.name}\nSWT: {swt.name}\n"
                                    f"COM-порт: {serial.name}\n", encoding="utf-8")
    size = sum(f.stat().st_size for f in APP.rglob("*") if f.is_file()) / 2**20
    print(f"Готово: {APP / 'RectPult.exe'}  (каталог {size:.0f} МБ, версия {version})")

    #4. Архив для переноса
    if not a.no_zip:
        for old in DIST.glob("RectPult-*.zip"):
            old.unlink()
        zp = DIST / f"RectPult-{version}.zip"
        with zipfile.ZipFile(zp, "w", zipfile.ZIP_DEFLATED, compresslevel=6) as z:
            for f in sorted(APP.rglob("*")):
                if f.is_file():
                    z.write(f, ("RectPult" / f.relative_to(APP)).as_posix())
        print(f"Архив: {zp}  ({zp.stat().st_size / 2**20:.0f} МБ)")


if __name__ == "__main__":
    main()
