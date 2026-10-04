#!/usr/bin/env python3
"""Сборка плагина Eclipse «Пульт выпрямителя askoRV32» и p2-репозитория для установки.

Как у конфигуратора ПЛИС (sw/socgen/eclipse/build.py): ничего, кроме установленного Eclipse, не нужно -
javac из встроенной Java Eclipse (JustJ), библиотеки платформы - из пула пакетов Oomph (~/.p2/pool/plugins),
COM-порт - пакет CDT org.eclipse.cdt.native.serial (есть в Eclipse Embedded CDT), метаданные p2 пишутся напрямую.

Результат: build/askorv32-rectgui-repo.zip - архив для Help > Install New Software > Add > Archive.
Запуск:  py sw/rectgui/build.py
"""
import argparse
import datetime
import hashlib
import importlib.util
import re
import shutil
import struct
import subprocess
import sys
import zlib
from pathlib import Path
from xml.sax.saxutils import escape, quoteattr

HERE = Path(__file__).resolve().parent
BUILD = HERE / "build"
BUNDLE = "ru.askorv32.rectgui"
FEATURE = "ru.askorv32.rectgui.feature"
NAME = "askoRV32 - пульт выпрямителя"
DESC = ("Управление выпрямителем askoRV32 по UART: режим (имитатор, сеть и угол, сеть и ПИ-регулятор), импульсы, "
        "задание и коэффициенты регуляторов, биты ошибок, осциллограмма напряжения и тока с запуском по фронту.")

#Общие части сборки - из сборки конфигуратора ПЛИС
_spec = importlib.util.spec_from_file_location("gwsoc_build", HERE.parent / "socgen" / "eclipse" / "build.py")
gb = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(gb)


def png_icon(path):
    """Значок 16x16: выпрямленное напряжение (полуволны) над осью"""
    W = H = 16
    px = [[(0, 0, 0, 0)] * W for _ in range(H)]
    axis, wave = (120, 126, 136, 255), (217, 119, 6, 255)
    for x in range(W):
        px[13][x] = axis
    import math
    for x in range(1, 15):
        y = 13 - round(9 * abs(math.sin((x - 1) * math.pi / 6.5)))
        for yy in (y, y + 1):
            if 0 <= yy < 13:
                px[yy][x] = wave
    raw = b"".join(b"\x00" + b"".join(bytes(p) for p in row) for row in px)
    chunk = lambda t, d: struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xFFFFFFFF)
    path.write_bytes(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", W, H, 8, 6, 0, 0, 0)) +
                     chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))


def main():
    argparse.ArgumentParser(description="Сборка плагина «Пульт выпрямителя» и p2-репозитория").parse_args()
    qualifier = "v" + datetime.datetime.now().strftime("%Y%m%d%H%M")
    version = "1.0.0." + qualifier
    shutil.rmtree(BUILD, ignore_errors=True)
    stage = BUILD / "plugin"
    (stage / "META-INF").mkdir(parents=True)
    (stage / "icons").mkdir()

    java = gb.find_java()
    jars = sorted(str(p) for p in gb.POOL.glob("*.jar"))
    srcs = [str(p) for p in (HERE / "src").rglob("*.java")]
    argfile = BUILD / "javac.args"
    argfile.write_text("\n".join(['-encoding', 'UTF-8', '--release', '21', '-nowarn', '-d', f'"{stage.as_posix()}"',
                                  '-cp', '"' + ";".join(jars).replace("\\", "/") + '"'] +
                                 [f'"{s}"'.replace("\\", "/") for s in srcs]), encoding="utf-8")
    print(f"javac: {len(srcs)} файл(ов), classpath {len(jars)} jar")
    if not any("org.eclipse.cdt.native.serial" in j for j in jars):
        sys.exit("Нет пакета org.eclipse.cdt.native.serial (COM-порт) в ~/.p2/pool/plugins - нужен Eclipse с CDT")
    r = subprocess.run([str(java), "-m", "jdk.compiler/com.sun.tools.javac.Main", "@" + str(argfile)])
    if r.returncode:
        sys.exit("Ошибка компиляции")

    mf = (HERE / "META-INF" / "MANIFEST.MF").read_text(encoding="utf-8").replace("1.0.0.qualifier", version)
    (stage / "META-INF" / "MANIFEST.MF").write_text(mf, encoding="utf-8", newline="\n")
    shutil.copy(HERE / "plugin.xml", stage / "plugin.xml")
    (stage / "plugin.properties").write_text(gb.props_escape((HERE / "plugin.properties").read_text(encoding="utf-8")),
                                             encoding="latin-1", newline="\n")
    png_icon(stage / "icons" / "rect.png")

    src = BUILD / "repo_src"
    (src / "plugins").mkdir(parents=True)
    (src / "features").mkdir()
    jar = src / "plugins" / f"{BUNDLE}_{version}.jar"
    gb.zip_dir(stage, jar)
    fstage = BUILD / "feature"
    fstage.mkdir()
    (fstage / "feature.xml").write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<feature id="{FEATURE}" label="askoRV32 - rectifier control panel" version="{version}" provider-name="askoRV32">
   <description>Control of the askoRV32 thyristor rectifier over UART: modes, pulses, set points, PI gains, error bits, voltage and current oscilloscope.</description>
   <requires>
      <import plugin="org.eclipse.ui"/>
      <import plugin="org.eclipse.cdt.native.serial"/>
   </requires>
   <plugin id="{BUNDLE}" version="{version}" unpack="false"/>
</feature>
''', encoding="utf-8", newline="\n")
    fjar = src / "features" / f"{FEATURE}_{version}.jar"
    gb.zip_dir(fstage, fjar, manifest_first=False)

    repo = BUILD / "repo"
    (repo / "plugins").mkdir(parents=True)
    (repo / "features").mkdir()
    shutil.copy(jar, repo / "plugins" / jar.name)
    shutil.copy(fjar, repo / "features" / fjar.name)
    write_p2(repo, version, mf, repo / "plugins" / jar.name, repo / "features" / fjar.name)
    out = BUILD / "askorv32-rectgui-repo.zip"
    gb.zip_dir(repo, out, manifest_first=False)
    print(f"Готово: {out.relative_to(HERE.parent.parent)}  (версия {version})")
    print("Установка: Help > Install New Software > Add > Archive… > этот zip > askoRV32 > Next > Finish, перезапуск Eclipse")
    print("Открыть: кнопка на панели инструментов или Window > Show View > Other > askoRV32 > Пульт выпрямителя")


def write_p2(repo, v, manifest, bundle_jar, feature_jar):
    """content.xml и artifacts.xml (как у конфигуратора ПЛИС; плагин - обычным jar)"""
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
    fg, fj = FEATURE + ".feature.group", FEATURE + ".feature.jar"
    mf_short = f"Bundle-SymbolicName: {BUNDLE};singleton:=true\nBundle-Version: {v}\n"
    units = [
        f"""    <unit id='{BUNDLE}' version='{v}' singleton='true'>
      <update id='{BUNDLE}' range='[0.0.0,{v})' severity='0'/>
      <properties size='2'>
        <property name='org.eclipse.equinox.p2.name' value={quoteattr(NAME)}/>
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
        <instructions size='1'>
          <instruction key='manifest'>{escape(mf_short).replace(chr(10), '&#xA;')}</instruction>
        </instructions>
      </touchpointData>
    </unit>
""",
        f"""    <unit id='{fj}' version='{v}'>
      <properties size='1'>
        <property name='org.eclipse.equinox.p2.name' value={quoteattr(NAME)}/>
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
        f"""    <unit id='{fg}' version='{v}' singleton='false'>
      <update id='{fg}' range='[0.0.0,{v})' severity='0'/>
      <properties size='3'>
        <property name='org.eclipse.equinox.p2.name' value={quoteattr(NAME)}/>
        <property name='org.eclipse.equinox.p2.description' value={quoteattr(DESC)}/>
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
        f"""    <unit id='askorv32.rectgui.category.{v}' version='{v}'>
      <properties size='2'>
        <property name='org.eclipse.equinox.p2.name' value='askoRV32'/>
        <property name='org.eclipse.equinox.p2.type.category' value='true'/>
      </properties>
      <provides size='1'>
        <provided namespace='org.eclipse.equinox.p2.iu' name='askorv32.rectgui.category.{v}' version='{v}'/>
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
<repository name='askoRV32 - rectifier control panel' type='org.eclipse.equinox.internal.p2.metadata.repository.LocalMetadataRepository' version='1'>
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
<repository name='askoRV32 - rectifier control panel' type='org.eclipse.equinox.p2.artifact.repository.simpleRepository' version='1'>
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
