#!/bin/bash
# Сборка openFPGALoader v1.1.1 с исправлениями gowin_spi_flush.patch, gowin_gw1n_erase.patch
# и bl616_bitmode_tail.patch
# в sdk/openfpgaloader/bin (README.md).
# Запуск - в оболочке MSYS2 UCRT64 (C:\msys64\ucrt64.exe) или из PowerShell:
#   $env:MSYSTEM='UCRT64'; C:\msys64\usr\bin\bash.exe -l <путь к этому файлу>
# Нужные пакеты MSYS2:
#   pacman -S --needed git mingw-w64-ucrt-x86_64-{gcc,cmake,ninja,pkgconf,libftdi,libusb,hidapi,zlib}
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
WORK="${TMP:-/tmp}/askorv32-openfpgaloader"
mkdir -p "$WORK" && cd "$WORK"
[ -d openFPGALoader ] || git clone -q --depth 1 --branch v1.1.1 https://github.com/trabucayre/openFPGALoader.git
cd openFPGALoader
git checkout -q -- src
git apply "$HERE/gowin_spi_flush.patch"
git apply "$HERE/gowin_gw1n_erase.patch"
git apply "$HERE/bl616_bitmode_tail.patch"
git diff --stat
rm -rf build && mkdir build && cd build
cmake -G Ninja -DCMAKE_BUILD_TYPE=Release -DENABLE_UDEV=OFF -DENABLE_LIBGPIOD=OFF -DENABLE_CMSISDAP=ON .. > cmake.log 2>&1 \
    || { tail -30 cmake.log; exit 1; }
# Пути вида /ucrt64/... (из пакетов MSYS2) Ninja и gcc под Windows не понимают - полный путь;
# в строках зависимостей build двоеточие диска экранируется ($:)
sed -i -E 's@(^|[ ;="]|-I|-L)/ucrt64/@\1C:/msys64/ucrt64/@g' build.ninja
sed -i '/^build /s|C:/msys64/|C$:/msys64/|g' build.ninja
ninja > ninja.log 2>&1 || { tail -30 ninja.log; exit 1; }
mkdir -p "$HERE/bin"
cp openFPGALoader.exe "$HERE/bin/"
#Библиотеки MSYS2, нужные программе (чтобы она работала без MSYS2 в PATH)
for dll in $(ldd openFPGALoader.exe | grep -i '/ucrt64/' | awk '{print $3}'); do cp "$dll" "$HERE/bin/"; done
ls "$HERE/bin"
"$HERE/bin/openFPGALoader.exe" -V
