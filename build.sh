#!/usr/bin/env bash
# Builds dist/Fingertip-dit-<version>.msi from source.
# Run in an MSYS2 MINGW64 shell with:
#   pacman -S --needed base-devel autotools git mingw-w64-x86_64-toolchain \
#     mingw-w64-x86_64-unbound mingw-w64-x86_64-crt-git mingw-w64-x86_64-msitools
set -euo pipefail
cd "$(dirname "$0")"

VERSION=0.0.4
# Official Fingertip 0.0.3 release; fingertip.exe is taken from it unchanged.
FINGERTIP_MSI_URL=https://github.com/imperviousinc/fingertip/releases/download/v0.0.3/Fingertip-v0.0.3.msi
FINGERTIP_MSI_SHA256=9b0bb0d84a4243010d424a6a5349a3bc3eeb53907b1e7b9a2911d86b58f08cd9
FINGERTIP_EXE_SHA256=d44873f11308dd665b976f726d49819463fea4ccf9ced55873ad76434b37f41d

if [ "${MSYSTEM:-}" != "MINGW64" ]; then
  echo "error: run this from an MSYS2 MINGW64 shell" >&2
  exit 1
fi

git submodule update --init
rm -rf build && mkdir -p build/stage dist

echo "==> hnsd ($(git -C third_party/hnsd rev-parse --short HEAD))"
git -C third_party/hnsd archive --format=tar --prefix=hnsd/ HEAD | tar -x -C build
(cd build/hnsd && ./autogen.sh >/dev/null 2>&1 && ./configure >/dev/null && make >/dev/null 2>&1)  # serial: the bundled libuv has a parallel-make race
cp build/hnsd/hnsd.exe build/stage/hnsd-core.exe

echo "==> hnsd wrapper"
gcc -O2 -municode -static -o build/stage/hnsd.exe wrapper/hnsd-wrapper.c

echo "==> fingertip.exe (official v0.0.3)"
curl -fsSL -o build/fingertip-v0.0.3.msi "$FINGERTIP_MSI_URL"
echo "$FINGERTIP_MSI_SHA256  build/fingertip-v0.0.3.msi" | sha256sum -c -
(mkdir -p build/fingertip && cd build/fingertip && msiextract ../fingertip-v0.0.3.msi >/dev/null)
cp build/fingertip/Fingertip/fingertip.exe build/stage/
echo "$FINGERTIP_EXE_SHA256  build/stage/fingertip.exe" | sha256sum -c -

echo "==> runtime DLLs"
for dll in libunbound-8.dll libssl-3-x64.dll libcrypto-3-x64.dll; do
  cp "/mingw64/bin/$dll" build/stage/
done
# Fail if hnsd-core needs any other non-system DLL.
missing=$(ldd build/stage/hnsd-core.exe | awk '/\/mingw64\// {print $1}' | while read -r d; do
  [ -f "build/stage/$d" ] || echo "$d"; done)
if [ -n "$missing" ]; then
  echo "error: hnsd-core.exe needs DLLs not in the stage: $missing" >&2
  exit 1
fi

echo "==> notices"
{
  cat THIRD-PARTY-NOTICES.txt
  for n in fingertip hnsd unbound openssl; do
    printf '\n\n----- %s license -----\n\n' "$n"
    cat "licenses/$n-LICENSE.txt"
  done
} | sed 's/$/\r/' > build/stage/THIRD-PARTY-NOTICES.txt

echo "==> msi"
wixl -a x64 -o "dist/Fingertip-dit-$VERSION.msi" installer/fingertip-dit.wxs
(cd dist && sha256sum "Fingertip-dit-$VERSION.msi" | tee "Fingertip-dit-$VERSION.msi.sha256")
