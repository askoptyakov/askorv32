#!/usr/bin/env python3
"""Сборка общего установщика инструментов askoRV32 (askorv32-sdk-setup-<дата>.exe).

Из дистрибутивов (таблица в sdk/SETUP.md) собирается промежуточный каталог stage/ - так, как всё
должно лечь у пользователя, - и Inno Setup упаковывает его в один .exe (askorv32-sdk.iss):
  eclipse/            Eclipse IDE for Embedded C/C++ с уже установленными плагинами askoRV32
                      (конфигуратор ПЛИС, пульт выпрямителя) и настройками консоли
  riscv-toolchain/    xPack RISC-V GCC, Windows Build Tools, OpenOCD
  oss-cad-suite/      OSS CAD Suite (Yosys, nextpnr, apicula)
  iverilog/           Icarus Verilog + GTKWave (копия установленного, по умолчанию C:\\iverilog)
  openfpgaloader/     исправленный openFPGALoader из sdk/openfpgaloader/bin
  zadig/              Zadig
  redist/             установщики Python, Gowin EDA, GitHub Desktop - запускаются из установщика

Дистрибутивы ищутся в sdk/, затем в %USERPROFILE%\\Downloads (или в каталогах --distr).
Нужен Inno Setup 6 (ISCC.exe; по умолчанию - установленный для текущего пользователя).
Запуск:  py sdk/installer/build.py [--distr <каталог>] [--keep-stage] [--no-compile]
"""
import argparse
import datetime
import os
import re
import shutil
import subprocess
import sys
import zipfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent
STAGE = HERE / "stage"
OUT = HERE / "out"
TAR = Path(os.environ.get("SystemRoot", r"C:\Windows")) / "System32" / "tar.exe"   #bsdtar: zip и tgz, быстрее zipfile

#Плагины Eclipse: p2-архив и устанавливаемая группа
PLUGINS = [
    (ROOT / "sw" / "socgen" / "eclipse" / "build" / "askorv32-gwsoc-repo.zip", "ru.askorv32.gwsoc.feature.feature.group"),
    (ROOT / "sw" / "rectgui" / "build" / "askorv32-rectgui-repo.zip", "ru.askorv32.rectgui.feature.feature.group"),
]

#Настройки по умолчанию, дописываемые в plugin_customization.ini пакета Eclipse (sdk/SETUP.md, п. 8.5):
#полоса хода openFPGALoader в одной строке консоли. Файл в ISO 8859-1 - комментарий латиницей.
CUSTOMIZATION = """
#------------------------------------------------------------------------------
# askoRV32: openFPGALoader progress bar on one console line (\\r as control character)
org.eclipse.debug.ui/Console.interpret_control_characters=true
org.eclipse.debug.ui/Console.interpret_cr_as_control_characters=true
"""


def log(msg):
    print(msg, flush=True)


def version_key(path):
    return [int(n) for n in re.findall(r"\d+", path.name)]


def find_distr(dirs, pattern, what, required=True):
    """Самый новый файл по маске в первом каталоге, где он есть."""
    for d in dirs:
        hits = sorted(Path(d).glob(pattern), key=version_key)
        if hits:
            return hits[-1]
    if required:
        sys.exit(f"Не найден дистрибутив «{what}» ({pattern}) в: " + ", ".join(str(d) for d in dirs))
    return None


def untar(archive, dest):
    """Распаковка zip/tgz системным tar.exe (bsdtar)."""
    dest.mkdir(parents=True, exist_ok=True)
    subprocess.run([str(TAR), "-xf", str(archive), "-C", str(dest)], check=True)


def top_dir(archive):
    """Каталог верхнего уровня zip-архива (xpack-...-<версия>)."""
    with zipfile.ZipFile(archive) as z:
        return z.namelist()[0].split("/")[0]


def find_iscc(arg):
    cands = [arg, os.environ.get("ISCC"),
             Path(os.environ.get("LOCALAPPDATA", "")) / "Programs" / "Inno Setup 6" / "ISCC.exe",
             Path(r"C:\Program Files (x86)\Inno Setup 6\ISCC.exe"), Path(r"C:\Program Files\Inno Setup 6\ISCC.exe")]
    for c in cands:
        if c and Path(c).is_file():
            return Path(c)
    sys.exit("Не найден Inno Setup 6 (ISCC.exe): https://jrsoftware.org/isdl.php, ключ --iscc или переменная ISCC")


def prepare_eclipse(zip_path):
    log(f"Eclipse: {zip_path.name}")
    untar(zip_path, STAGE)
    ecl = STAGE / "eclipse"
    for repo, _ in PLUGINS:
        if not repo.is_file():
            sys.exit(f"Нет p2-архива плагина: {repo.relative_to(ROOT)} (собрать: py {repo.parent.parent.relative_to(ROOT)}/build.py)")
    repos = ",".join(f"jar:{repo.as_uri()}!/" for repo, _ in PLUGINS)
    ius = ",".join(iu for _, iu in PLUGINS)
    ws = HERE / "stage-ws"
    log("Eclipse: установка плагинов askoRV32 (p2 director)")
    r = subprocess.run([str(ecl / "eclipsec.exe"), "-nosplash", "-consoleLog",
                        "-application", "org.eclipse.equinox.p2.director",
                        "-repository", repos, "-installIU", ius, "-data", str(ws)],
                       capture_output=True, text=True, encoding="utf-8", errors="replace")
    print(r.stdout[-3000:], r.stderr[-3000:], sep="\n")
    if r.returncode != 0 or "Operation completed" not in r.stdout:
        sys.exit("p2 director не установил плагины (вывод выше)")
    shutil.rmtree(ws, ignore_errors=True)
    bundles = (ecl / "configuration" / "org.eclipse.equinox.simpleconfigurator" / "bundles.info").read_text(encoding="utf-8")
    for bundle in ("ru.askorv32.gwsoc,", "ru.askorv32.rectgui,"):
        if bundle not in bundles:
            sys.exit(f"Плагин {bundle[:-1]} не попал в bundles.info")
    #Кэш OSGi и журналы первого запуска пересоздаются Eclipse сам - не везём
    conf = ecl / "configuration"
    for name in ("org.eclipse.osgi", "org.eclipse.core.runtime", "org.eclipse.e4.ui.css.swt.theme", "org.eclipse.ui.intro.universal"):
        shutil.rmtree(conf / name, ignore_errors=True)
    for f in conf.glob("*.log"):
        f.unlink()
    prod = next((ecl / "plugins").glob("org.eclipse.epp.package.*_*/plugin_customization.ini"))
    with open(prod, "a", encoding="latin-1", newline="\n") as f:
        f.write(CUSTOMIZATION)
    ini = (ecl / "eclipse.ini").read_text(encoding="utf-8")
    if "-Dosgi.instance.area.default=" not in ini:
        sys.exit("В eclipse.ini нет -Dosgi.instance.area.default (его подменяет установщик)")
    rel = re.search(r"-(\d{4}-\d{2})-R", zip_path.name).group(1)
    return f"{rel} ({re.search(r'_(\d+\.\d+)', prod.parent.name).group(1)})"


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--distr", action="append", help="каталог с дистрибутивами (можно несколько)")
    ap.add_argument("--iverilog", default=r"C:\iverilog", help="установленный Icarus Verilog + GTKWave")
    ap.add_argument("--iscc", help="путь к ISCC.exe")
    ap.add_argument("--keep-stage", action="store_true", help="не пересобирать stage/, если он уже есть")
    ap.add_argument("--no-compile", action="store_true", help="только подготовить stage/")
    args = ap.parse_args()
    dirs = args.distr or [ROOT / "sdk", Path.home() / "Downloads", Path(r"C:\Distr")]

    d = {
        "eclipse": find_distr(dirs, "eclipse-embedcpp-*-win32-x86_64.zip", "Eclipse IDE for Embedded C/C++"),
        "gcc": find_distr(dirs, "xpack-riscv-none-elf-gcc-*-win32-x64.zip", "xPack RISC-V GCC"),
        "buildtools": find_distr(dirs, "xpack-windows-build-tools-*-win32-x64.zip", "xPack Windows Build Tools"),
        "openocd": find_distr(dirs, "xpack-openocd-*-win32-x64.zip", "xPack OpenOCD"),
        "oss": find_distr(dirs, "oss-cad-suite-windows-x64-*.tgz", "OSS CAD Suite"),
        "zadig": find_distr(dirs, "zadig-*.exe", "Zadig"),
        "python": find_distr(dirs, "python-3.*-amd64.exe", "Python (установщик python.org)"),
        "gowin": find_distr(dirs, "Gowin_V*_Education_x64_win.zip", "Gowin EDA Education"),
        "github": find_distr(dirs, "GitHubDesktopSetup-x64.exe", "GitHub Desktop"),
    }
    for k, v in d.items():
        log(f"  {k:10} {v}")
    iverilog = Path(args.iverilog)
    if not (iverilog / "bin" / "iverilog.exe").is_file() or not (iverilog / "bin" / "gtkwave.exe").is_file():
        sys.exit(f"Нет Icarus Verilog с GTKWave в {iverilog} (ключ --iverilog)")
    loader = ROOT / "sdk" / "openfpgaloader"
    if not (loader / "bin" / "openFPGALoader.exe").is_file():
        sys.exit("Нет sdk/openfpgaloader/bin/openFPGALoader.exe")

    tc = STAGE / "riscv-toolchain"
    if not (args.keep_stage and STAGE.is_dir()):
        if STAGE.exists():
            log("Очистка stage/")
            shutil.rmtree(STAGE)
        STAGE.mkdir(parents=True)
        eclipse_ver = prepare_eclipse(d["eclipse"])
        for k in ("gcc", "buildtools", "openocd"):
            log(f"{k}: {d[k].name}")
            untar(d[k], tc)
        log(f"OSS CAD Suite: {d['oss'].name}")
        untar(d["oss"], STAGE)
        log(f"Icarus Verilog: {iverilog}")
        shutil.copytree(iverilog, STAGE / "iverilog", ignore=shutil.ignore_patterns("Uninstall.exe", "unins*.exe", "unins*.dat"))
        shutil.copytree(loader / "bin", STAGE / "openfpgaloader" / "bin")
        shutil.copy2(loader / "README.md", STAGE / "openfpgaloader" / "README.md")
        (STAGE / "zadig").mkdir()
        shutil.copy2(d["zadig"], STAGE / "zadig" / d["zadig"].name)
        redist = STAGE / "redist"
        redist.mkdir()
        shutil.copy2(d["python"], redist / d["python"].name)
        shutil.copy2(d["github"], redist / d["github"].name)
        log(f"Gowin EDA: {d['gowin'].name}")
        untar(d["gowin"], redist)
        (STAGE / "eclipse.version").write_text(eclipse_ver, encoding="utf-8")
    eclipse_ver = (STAGE / "eclipse.version").read_text(encoding="utf-8")
    gowin_exe = next((STAGE / "redist").glob("Gowin_*.exe"))

    tdir = lambda k: top_dir(d[k])
    oss_date = re.search(r"(\d{8})", d["oss"].name).group(1)
    defines = {
        "AppVersion": datetime.date.today().strftime("%Y.%m.%d"),
        "EclipseVer": eclipse_ver,
        "GccDir": tdir("gcc"), "BuildToolsDir": tdir("buildtools"), "OpenOcdDir": tdir("openocd"),
        "OssDate": f"{oss_date[:4]}-{oss_date[4:6]}-{oss_date[6:]}",
        "ZadigExe": d["zadig"].name, "PythonExe": d["python"].name, "GowinExe": gowin_exe.name, "GitHubExe": d["github"].name,
        "PythonVer": re.search(r"python-([\d.]+)", d["python"].name).group(1),
        "GowinVer": re.search(r"Gowin_V([\d.]+)", gowin_exe.name).group(1),
        "Stage": str(STAGE), "OutDir": str(OUT),
        #Установщик не пишет пути длиннее MAX_PATH (259 символов): самый длинный файл определяет предел для каталога
        "LongestRel": str(max(len(str(f.relative_to(STAGE))) for f in STAGE.rglob("*") if f.is_file())),
    }
    #Плагины askoRV32 в Eclipse: по ним установщик узнаёт, что Eclipse этой сборки уже стоит
    plugins = STAGE / "eclipse" / "plugins"
    defines["EclipseProduct"] = next(p for p in plugins.glob("org.eclipse.epp.package.*_*") if ".common_" not in p.name).name
    defines["GwsocPlugin"] = next(plugins.glob("ru.askorv32.gwsoc_*")).name
    defines["RectguiPlugin"] = next(plugins.glob("ru.askorv32.rectgui_*")).name
    #Размеры (МБ) для окна выбора инструментов; у сторонних программ - размер их установщика
    sizes = {"Eclipse": "eclipse", "Gcc": f"riscv-toolchain/{defines['GccDir']}",
             "BuildTools": f"riscv-toolchain/{defines['BuildToolsDir']}", "OpenOcd": f"riscv-toolchain/{defines['OpenOcdDir']}",
             "Loader": "openfpgaloader", "Oss": "oss-cad-suite", "Iverilog": "iverilog", "Zadig": "zadig",
             "Python": f"redist/{defines['PythonExe']}", "Gowin": f"redist/{gowin_exe.name}", "GitHub": f"redist/{defines['GitHubExe']}"}
    for name, sub in sizes.items():
        p = STAGE / sub
        size = p.stat().st_size if p.is_file() else sum(f.stat().st_size for f in p.rglob("*") if f.is_file())
        defines[f"Size{name}"] = str(max(1, round(size / 2**20)))
    for k, v in defines.items():
        log(f"  /D{k}={v}")
    if args.no_compile:
        return
    iscc = find_iscc(args.iscc)
    OUT.mkdir(exist_ok=True)
    log(f"Inno Setup: {iscc}")
    cmd = [str(iscc), "/Qp"] + [f"/D{k}={v}" for k, v in defines.items()] + [str(HERE / "askorv32-sdk.iss")]
    t0 = datetime.datetime.now()
    subprocess.run(cmd, check=True)
    exe = OUT / f"askorv32-sdk-setup-{defines['AppVersion']}.exe"
    log(f"Готово: {exe.relative_to(ROOT)}  ({exe.stat().st_size / 2**20:.0f} МБ, {datetime.datetime.now() - t0})")


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8")
    main()
