#!/usr/bin/env python3
"""Сборка плагина Eclipse «Конфигуратор ПЛИС askoRV32» и p2-репозитория для установки.

Ничего, кроме установленного Eclipse, не нужно: javac берётся из встроенной Java Eclipse (JustJ),
библиотеки платформы - из пула пакетов Oomph (~/.p2/pool/plugins), метаданные p2-репозитория
пишутся напрямую.

Результат: build/askorv32-gwsoc-repo.zip - архив для Help > Install New Software > Add > Archive.
Запуск:  py sw/socgen/eclipse/build.py
"""
import argparse
import datetime
import os
import re
import shutil
import subprocess
import sys
import zipfile
import zlib
import struct
from pathlib import Path

HERE = Path(__file__).resolve().parent
WEB = HERE.parent / "web"
BUILD = HERE / "build"
POOL = Path.home() / ".p2" / "pool" / "plugins"
BUNDLE = "ru.askorv32.gwsoc"
FEATURE = "ru.askorv32.gwsoc.feature"


def find_java():
    for d in sorted(POOL.glob("org.eclipse.justj.openjdk.hotspot.jre.full.win32.x86_64_*"), reverse=True):
        j = d / "jre" / "bin" / "java.exe"
        if j.exists():
            return j
    j = shutil.which("java")
    if not j:
        sys.exit("Не найдена Java с компилятором (JustJ из Eclipse)")
    return Path(j)


def props_escape(text):
    """.properties читается в ISO-8859-1: всё выше 0x7F - в \\uXXXX."""
    return "".join(c if ord(c) < 0x80 else f"\\u{ord(c):04x}" for c in text)


def png_icon(path):
    """Значок 16x16: микросхема с выводами (без сторонних библиотек)."""
    W = H = 16
    px = [[(0, 0, 0, 0)] * W for _ in range(H)]
    body, pin, dot = (43, 47, 54, 255), (160, 166, 176, 255), (14, 159, 142, 255)
    for y in range(3, 13):
        for x in range(3, 13):
            px[y][x] = body
    for k in (4, 7, 10):
        for t in (0, 1, 2):
            px[k][t] = px[k][15 - t] = px[t][k] = px[15 - t][k] = pin
            px[k + 1][t] = px[k + 1][15 - t] = px[t][k + 1] = px[15 - t][k + 1] = pin
    for y in range(5, 8):
        for x in range(5, 8):
            px[y][x] = dot
    raw = b"".join(b"\x00" + b"".join(bytes(p) for p in row) for row in px)
    chunk = lambda t, d: struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xFFFFFFFF)
    path.write_bytes(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", W, H, 8, 6, 0, 0, 0)) +
                     chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))


def zip_dir(src, dst, manifest_first=True):
    with zipfile.ZipFile(dst, "w", zipfile.ZIP_DEFLATED) as z:
        files = sorted(p for p in src.rglob("*") if p.is_file())
        if manifest_first:
            files.sort(key=lambda p: 0 if p.relative_to(src).as_posix() == "META-INF/MANIFEST.MF" else 1)
        for p in files:
            z.write(p, p.relative_to(src).as_posix())


def main():
    argparse.ArgumentParser(description="Сборка плагина конфигуратора ПЛИС и p2-репозитория").parse_args()

    qualifier = "v" + datetime.datetime.now().strftime("%Y%m%d%H%M")
    version = "1.0.0." + qualifier
    shutil.rmtree(BUILD, ignore_errors=True)
    stage = BUILD / "plugin"
    (stage / "META-INF").mkdir(parents=True)
    (stage / "icons").mkdir()

    # --- Компиляция ---
    java = find_java()
    classes = stage
    jars = sorted(str(p) for p in POOL.glob("*.jar"))
    argfile = BUILD / "javac.args"
    srcs = [str(p) for p in (HERE / "src").rglob("*.java")]
    argfile.write_text("\n".join(['-encoding', 'UTF-8', '--release', '21', '-nowarn', '-d', f'"{classes.as_posix()}"',
                                  '-cp', '"' + os.pathsep.join(jars).replace("\\", "/") + '"'] +
                                 [f'"{s}"'.replace("\\", "/") for s in srcs]), encoding="utf-8")
    print(f"javac: {len(srcs)} файл(ов), classpath {len(jars)} jar")
    r = subprocess.run([str(java), "-m", "jdk.compiler/com.sun.tools.javac.Main", "@" + str(argfile)])
    if r.returncode:
        sys.exit("Ошибка компиляции")

    # --- Состав плагина ---
    mf = (HERE / "META-INF" / "MANIFEST.MF").read_text(encoding="utf-8").replace("1.0.0.qualifier", version)
    (stage / "META-INF" / "MANIFEST.MF").write_text(mf, encoding="utf-8", newline="\n")
    shutil.copy(HERE / "plugin.xml", stage / "plugin.xml")
    (stage / "plugin.properties").write_text(props_escape((HERE / "plugin.properties").read_text(encoding="utf-8")),
                                             encoding="latin-1", newline="\n")
    png_icon(stage / "icons" / "chip.png")
    shutil.copytree(WEB, stage / "web")

    src = BUILD / "repo_src"
    (src / "plugins").mkdir(parents=True)
    (src / "features").mkdir()
    jar = src / "plugins" / f"{BUNDLE}_{version}.jar"
    zip_dir(stage, jar)

    fstage = BUILD / "feature"
    fstage.mkdir()
    (fstage / "feature.xml").write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<feature id="{FEATURE}" label="askoRV32 - FPGA configurator (GW1NR-9)" version="{version}" provider-name="askoRV32">
   <description>Visual configuration of the askoRV32 FPGA project (GW1NR-LV9QN88P): pins, hardware blocks, rPLL; generates top.sv and riscv.cst and builds the bitstream with Yosys + nextpnr + apicula.</description>
   <requires>
      <import plugin="org.eclipse.ui"/>
      <import plugin="org.eclipse.ui.ide"/>
      <import plugin="org.eclipse.ui.console"/>
   </requires>
   <plugin id="{BUNDLE}" version="{version}" unpack="true"/>
</feature>
''', encoding="utf-8", newline="\n")
    zip_dir(fstage, src / "features" / f"{FEATURE}_{version}.jar", manifest_first=False)
    # --- p2-репозиторий: метаданные пишутся напрямую (content.xml, artifacts.xml) ---
    #Встроенный publisher Eclipse здесь не годится: запущенный отдельно, он ищет реестр профилей p2
    #в Program Files (путь к ~/.p2 с пробелом в config.ini не разбирается) и падает.
    repo = BUILD / "repo"
    (repo / "plugins").mkdir(parents=True)
    (repo / "features").mkdir()
    shutil.copy(jar, repo / "plugins" / jar.name)
    fjar = src / "features" / f"{FEATURE}_{version}.jar"
    shutil.copy(fjar, repo / "features" / fjar.name)
    write_p2(repo, version, mf, repo / 'plugins' / jar.name, repo / 'features' / fjar.name)
    out = BUILD / "askorv32-gwsoc-repo.zip"
    zip_dir(repo, out, manifest_first=False)
    print(f"Готово: {out.relative_to(HERE.parent.parent.parent)}  (версия {version})")
    print("Установка: Help > Install New Software > Add > Archive… > этот zip > askoRV32 > Next > Finish, перезапуск Eclipse")


def write_p2(repo, v, manifest, bundle_jar, feature_jar):
    import hashlib
    from xml.sax.saxutils import escape, quoteattr
    #Новый p2 без контрольной суммы артефакт не проверяет (предупреждение «No digest algorithm»)
    def art_props(f):
        data = f.read_bytes()
        return (f"      <properties size='3'>\n"
                f"        <property name='artifact.size' value='{len(data)}'/>\n"
                f"        <property name='download.size' value='{len(data)}'/>\n"
                f"        <property name='download.checksum.sha-256' value='{hashlib.sha256(data).hexdigest()}'/>\n"
                f"      </properties>\n")
    ts = str(int(datetime.datetime.now().timestamp() * 1000))
    reqs = re.search(r"Require-Bundle:(.*?)(?:\n\S|\Z)", manifest, re.S).group(1)
    reqs = [r.strip().split(";")[0] for r in reqs.replace("\n ", "").split(",") if r.strip()]
    name = "askoRV32 - конфигуратор ПЛИС"
    desc = ("Визуальная настройка проекта ПЛИС askoRV32 (GW1NR-LV9QN88P): выводы, аппаратные блоки, rPLL; "
            "генерация top.sv и riscv.cst, сборка Yosys + nextpnr + apicula.")
    fg, fj = FEATURE + ".feature.group", FEATURE + ".feature.jar"
    mf_short = f"Bundle-SymbolicName: {BUNDLE};singleton:=true\nBundle-Version: {v}\n"
    units = [
        # Плагин (распаковывается каталогом: страница web/ открывается из файлов)
        f"""    <unit id='{BUNDLE}' version='{v}' singleton='true'>
      <update id='{BUNDLE}' range='[0.0.0,{v})' severity='0'/>
      <properties size='2'>
        <property name='org.eclipse.equinox.p2.name' value={quoteattr(name)}/>
        <property name='org.eclipse.equinox.p2.provider' value='askoRV32'/>
      </properties>
      <provides size='3'>
        <provided namespace='org.eclipse.equinox.p2.iu' name='{BUNDLE}' version='{v}'/>
        <provided namespace='osgi.bundle' name='{BUNDLE}' version='{v}'/>
        <provided namespace='org.eclipse.equinox.p2.eclipse.type' name='bundle' version='1.0.0'/>
      </provides>
      <requires size='{len(reqs)}'>
""" + "".join(f"        <required namespace='osgi.bundle' name='{r}' range='0.0.0'/>\n" for r in reqs) + f"""      </requires>
      <artifacts size='1'>
        <artifact classifier='osgi.bundle' id='{BUNDLE}' version='{v}'/>
      </artifacts>
      <touchpoint id='org.eclipse.equinox.p2.osgi' version='1.0.0'/>
      <touchpointData size='1'>
        <instructions size='2'>
          <instruction key='zipped'>true</instruction>
          <instruction key='manifest'>{escape(mf_short).replace(chr(10), '&#xA;')}</instruction>
        </instructions>
      </touchpointData>
    </unit>
""",
        # Файл feature
        f"""    <unit id='{fj}' version='{v}'>
      <properties size='1'>
        <property name='org.eclipse.equinox.p2.name' value={quoteattr(name)}/>
      </properties>
      <provides size='3'>
        <provided namespace='org.eclipse.equinox.p2.iu' name='{fj}' version='{v}'/>
        <provided namespace='org.eclipse.equinox.p2.eclipse.type' name='feature' version='1.0.0'/>
        <provided namespace='org.eclipse.update.feature' name='{FEATURE}' version='{v}'/>
      </provides>
      <filter>(org.eclipse.update.install.features=true)</filter>
      <artifacts size='1'>
        <artifact classifier='org.eclipse.update.feature' id='{FEATURE}' version='{v}'/>
      </artifacts>
      <touchpoint id='org.eclipse.equinox.p2.osgi' version='1.0.0'/>
      <touchpointData size='1'>
        <instructions size='1'>
          <instruction key='zipped'>true</instruction>
        </instructions>
      </touchpointData>
    </unit>
""",
        # Группа (то, что выбирают в Install New Software)
        f"""    <unit id='{fg}' version='{v}' singleton='false'>
      <update id='{fg}' range='[0.0.0,{v})' severity='0'/>
      <properties size='3'>
        <property name='org.eclipse.equinox.p2.name' value={quoteattr(name)}/>
        <property name='org.eclipse.equinox.p2.description' value={quoteattr(desc)}/>
        <property name='org.eclipse.equinox.p2.type.group' value='true'/>
      </properties>
      <provides size='1'>
        <provided namespace='org.eclipse.equinox.p2.iu' name='{fg}' version='{v}'/>
      </provides>
      <requires size='2'>
        <required namespace='org.eclipse.equinox.p2.iu' name='{BUNDLE}' range='[{v},{v}]'/>
        <required namespace='org.eclipse.equinox.p2.iu' name='{fj}' range='[{v},{v}]'>
          <filter>(org.eclipse.update.install.features=true)</filter>
        </required>
      </requires>
      <touchpoint id='null' version='0.0.0'/>
    </unit>
""",
        # Категория
        f"""    <unit id='askorv32.category.{v}' version='{v}'>
      <properties size='2'>
        <property name='org.eclipse.equinox.p2.name' value='askoRV32'/>
        <property name='org.eclipse.equinox.p2.type.category' value='true'/>
      </properties>
      <provides size='1'>
        <provided namespace='org.eclipse.equinox.p2.iu' name='askorv32.category.{v}' version='{v}'/>
      </provides>
      <requires size='1'>
        <required namespace='org.eclipse.equinox.p2.iu' name='{fg}' range='[{v},{v}]'/>
      </requires>
      <touchpoint id='null' version='0.0.0'/>
    </unit>
""",
    ]
    (repo / "content.xml").write_text(f"""<?xml version='1.0' encoding='UTF-8'?>
<?metadataRepository version='1.2.0'?>
<repository name='askoRV32' type='org.eclipse.equinox.internal.p2.metadata.repository.LocalMetadataRepository' version='1'>
  <properties size='2'>
    <property name='p2.timestamp' value='{ts}'/>
    <property name='p2.compressed' value='false'/>
  </properties>
  <units size='{len(units)}'>
{''.join(units)}  </units>
</repository>
""", encoding="utf-8", newline="\n")
    (repo / "artifacts.xml").write_text(f"""<?xml version='1.0' encoding='UTF-8'?>
<?artifactRepository version='1.1.0'?>
<repository name='askoRV32' type='org.eclipse.equinox.p2.artifact.repository.simpleRepository' version='1'>
  <properties size='2'>
    <property name='p2.timestamp' value='{ts}'/>
    <property name='p2.compressed' value='false'/>
  </properties>
  <mappings size='3'>
    <rule filter='(&amp; (classifier=osgi.bundle))' output='${{repoUrl}}/plugins/${{id}}_${{version}}.jar'/>
    <rule filter='(&amp; (classifier=binary))' output='${{repoUrl}}/binary/${{id}}_${{version}}'/>
    <rule filter='(&amp; (classifier=org.eclipse.update.feature))' output='${{repoUrl}}/features/${{id}}_${{version}}.jar'/>
  </mappings>
  <artifacts size='2'>
    <artifact classifier='osgi.bundle' id='{BUNDLE}' version='{v}'>
{art_props(bundle_jar)}    </artifact>
    <artifact classifier='org.eclipse.update.feature' id='{FEATURE}' version='{v}'>
{art_props(feature_jar)}    </artifact>
  </artifacts>
</repository>
""", encoding="utf-8", newline="\n")

if __name__ == "__main__":
    try:
        sys.stdout.reconfigure(encoding="utf-8")
    except Exception:
        pass
    main()
