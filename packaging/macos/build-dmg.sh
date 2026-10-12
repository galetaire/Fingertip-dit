#!/usr/bin/env bash
# Builds dist/Fingertip-dit-<version>.dmg on macOS (Intel or Apple Silicon).
# Needs Xcode command line tools and: brew install autoconf automake libtool
#
# The official fingertip binary is x86_64-only, so hnsd-core is built for x86_64
# too (Apple Silicon runs both under Rosetta 2). OpenSSL and Unbound are built
# from source and linked statically, so the app runs on macOS 10.13+ like 0.0.3.
set -euo pipefail
cd "$(dirname "$0")/../.."

VERSION=0.0.4
BUNDLE_ID=io.github.galetaire.fingertip-dit
ARCH=x86_64
export MACOSX_DEPLOYMENT_TARGET=10.13
FINGERTIP_URL=https://github.com/imperviousinc/fingertip/releases/download/v0.0.3/Fingertip-v0.0.3.dmg
FINGERTIP_SHA256=b93e8e36ff5157a4cfc350ad788141efac997ea6c0cde8b05701301f96759da7
OPENSSL_VERSION=3.5.9
OPENSSL_SHA256=603f5602e2eef00d77fbd429d34dcd5822bb301757a1bc9cdb24c670f1eb859a
UNBOUND_VERSION=1.26.1
UNBOUND_SHA256=35a6dc0e425a9282c3426d9a3043144011bf0534aed4b73ab62c52aee0af1503

B="$PWD/build/macos"
DEPS="$B/deps"
rm -rf "$B" && mkdir -p "$B" "$DEPS" dist
CFLAGS="-arch $ARCH -mmacosx-version-min=$MACOSX_DEPLOYMENT_TARGET -O2"
HOST=x86_64-apple-darwin
JOBS=$(sysctl -n hw.ncpu)

fetch() { # url sha256 dest
  curl -fsSL -o "$3" "$1"
  echo "$2  $3" | shasum -a 256 -c -
}

echo "==> OpenSSL $OPENSSL_VERSION (static, $ARCH)"
fetch "https://github.com/openssl/openssl/releases/download/openssl-$OPENSSL_VERSION/openssl-$OPENSSL_VERSION.tar.gz" \
  "$OPENSSL_SHA256" "$B/openssl.tar.gz"
tar -xzf "$B/openssl.tar.gz" -C "$B"
(cd "$B/openssl-$OPENSSL_VERSION" &&
  ./Configure darwin64-x86_64-cc no-shared no-tests no-docs no-apps \
    --prefix="$DEPS" --libdir=lib "-mmacosx-version-min=$MACOSX_DEPLOYMENT_TARGET" >/dev/null &&
  make -j"$JOBS" >/dev/null && make install_sw >/dev/null)

echo "==> Unbound $UNBOUND_VERSION (static, $ARCH)"
fetch "https://nlnetlabs.nl/downloads/unbound/unbound-$UNBOUND_VERSION.tar.gz" "$UNBOUND_SHA256" "$B/unbound.tar.gz"
tar -xzf "$B/unbound.tar.gz" -C "$B"
(cd "$B/unbound-$UNBOUND_VERSION" &&
  ./configure --host="$HOST" --prefix="$DEPS" --disable-shared --enable-static \
    --with-ssl="$DEPS" --with-libexpat="$(xcrun --show-sdk-path)/usr" \
    --disable-flto --without-pythonmodule --without-pyunbound CFLAGS="$CFLAGS" >/dev/null &&
  make -j"$JOBS" lib >/dev/null && make install-lib >/dev/null)

echo "==> hnsd ($(git -C third_party/hnsd rev-parse --short HEAD))"
git -C third_party/hnsd archive --format=tar --prefix=hnsd/ HEAD | tar -x -C "$B"
# serial make: the bundled libuv has a parallel-make race
(cd "$B/hnsd" && ./autogen.sh >/dev/null 2>&1 &&
  ./configure --host="$HOST" --with-unbound="$DEPS" CFLAGS="$CFLAGS" \
    LIBS="-L$DEPS/lib -lssl -lcrypto" >/dev/null &&
  make >/dev/null 2>&1)

echo "==> official Fingertip 0.0.3 app"
fetch "$FINGERTIP_URL" "$FINGERTIP_SHA256" "$B/fingertip.dmg"
MNT="$B/mnt"
mkdir -p "$MNT"
hdiutil attach -nobrowse -readonly -mountpoint "$MNT" "$B/fingertip.dmg" >/dev/null
APP="$B/Fingertip-dit.app"
ditto "$MNT/Fingertip.app" "$APP"
hdiutil detach "$MNT" >/dev/null

echo "==> replace hnsd"
if otool -L "$APP/Contents/MacOS/fingertip" | grep -q '@executable_path'; then
  echo "error: fingertip links bundled dylibs; refusing to remove Frameworks" >&2
  exit 1
fi
# Frameworks only held the old hnsd's OpenSSL 1.1 and libunbound.
rm -rf "$APP/Contents/MacOS/hnsd" "$APP/Contents/MacOS/.gitignore" "$APP/Contents/Frameworks" \
  "$APP/Contents/_CodeSignature"
install -m755 "$B/hnsd/hnsd" "$APP/Contents/MacOS/hnsd-core"
clang $CFLAGS -Wall -o "$APP/Contents/MacOS/hnsd" wrapper/hnsd-wrapper-posix.c

PB=/usr/libexec/PlistBuddy
PL="$APP/Contents/Info.plist"
$PB -c "Set :CFBundleIdentifier $BUNDLE_ID" "$PL"
$PB -c "Set :CFBundleShortVersionString $VERSION" "$PL"
$PB -c "Set :CFBundleVersion $VERSION" "$PL"
$PB -c "Add :CFBundleName string Fingertip-dit" "$PL"
$PB -c "Add :CFBundleDisplayName string Fingertip-dit" "$PL"
$PB -c "Add :LSMinimumSystemVersion string $MACOSX_DEPLOYMENT_TARGET" "$PL"
{
  cat THIRD-PARTY-NOTICES.txt
  for n in fingertip hnsd unbound openssl; do
    printf '\n\n----- %s license -----\n\n' "$n"
    cat "licenses/$n-LICENSE.txt"
  done
} > "$APP/Contents/Resources/THIRD-PARTY-NOTICES.txt"

echo "==> check"
for bin in hnsd hnsd-core; do
  f="$APP/Contents/MacOS/$bin"
  lipo -archs "$f"
  if otool -L "$f" | tail -n +2 | grep -vE '^\s+/(usr/lib|System/Library)/'; then
    echo "error: $bin links non-system libraries" >&2
    exit 1
  fi
  otool -l "$f" | grep -A3 -E 'LC_BUILD_VERSION|LC_VERSION_MIN_MACOSX' | grep -E 'minos|version ' | head -1
done
arch -x86_64 "$APP/Contents/MacOS/hnsd-core" --version

echo "==> sign (ad-hoc)"
codesign --force --sign - "$APP/Contents/MacOS/hnsd-core" "$APP/Contents/MacOS/hnsd"
codesign --force --sign - "$APP"
codesign --verify --strict --deep --verbose=2 "$APP"

echo "==> dmg"
STAGE="$B/dmg"
mkdir -p "$STAGE"
ditto "$APP" "$STAGE/Fingertip-dit.app"
ln -s /Applications "$STAGE/Applications"
OUT="dist/Fingertip-dit-$VERSION.dmg"
rm -f "$OUT"
hdiutil create -volname "Fingertip-dit $VERSION" -srcfolder "$STAGE" -fs HFS+ -format UDZO "$OUT" >/dev/null
(cd dist && shasum -a 256 "$(basename "$OUT")" | tee "$(basename "$OUT").sha256")
