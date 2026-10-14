#!/usr/bin/env bash
# Builds dist/Fingertip-dit-<version>-x86_64.AppImage.
# Run from the repo root on Ubuntu 22.04 x86_64 (CI uses an ubuntu:22.04 container;
# the result runs on distros with glibc >= 2.35):
#   apt-get install -y build-essential autoconf automake libtool git curl file \
#     libunbound-dev patchelf
set -euo pipefail
cd "$(dirname "$0")/../.."

VERSION=0.0.4
# Official Fingertip 0.0.3 AppImage; the fingertip binary is reused unchanged.
FINGERTIP_URL=https://github.com/imperviousinc/fingertip/releases/download/v0.0.3/Fingertip-v0.0.3.AppImage
FINGERTIP_SHA256=4b03e998d7065dc56b756511f34e19fbf934f2d5c7b77f533b4ed26c1ca3c94f
APPIMAGETOOL_URL=https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-x86_64.AppImage

B=build/linux
rm -rf "$B" && mkdir -p "$B" dist
export APPIMAGE_EXTRACT_AND_RUN=1  # no FUSE in containers

echo "==> official Fingertip 0.0.3 AppDir"
curl -fsSL -o "$B/fingertip.AppImage" "$FINGERTIP_URL"
echo "$FINGERTIP_SHA256  $B/fingertip.AppImage" | sha256sum -c -
chmod +x "$B/fingertip.AppImage"
(cd "$B" && ./fingertip.AppImage --appimage-extract >/dev/null)
APPDIR="$B/squashfs-root"

echo "==> hnsd ($(git -C third_party/hnsd rev-parse --short HEAD))"
git -C third_party/hnsd archive --format=tar --prefix=hnsd/ HEAD | tar -x -C "$B"
# serial make: the bundled libuv has a parallel-make race
(cd "$B/hnsd" && ./autogen.sh >/dev/null 2>&1 && ./configure >/dev/null && make >/dev/null 2>&1)

echo "==> use the system GTK"
# The official AppImage bundles Ubuntu 18.04 copies of GTK 3 and part of GLib
# (libgmodule, but not libglib/libgio). On current distros those clash with the
# system GLib ("undefined symbol: g_module_open_full") and GNOME settings, so
# fingertip must use the host's GTK stack. Only the AppIndicator tray libraries
# are kept: many distros no longer ship libappindicator3, and they work against
# any GTK 3. Everything else in usr/lib was the 18.04 desktop stack or the old
# hnsd's libraries.
KEEP_LIBS="libappindicator3.so.1 libindicator3.so.7 libdbusmenu-glib.so.4 libdbusmenu-gtk3.so.4"
for lib in "$APPDIR"/usr/lib/*; do
  [ -f "$lib" ] || continue
  case " $KEEP_LIBS " in
    *" $(basename "$lib") "*) ;;
    *) rm "$lib" ;;
  esac
done
echo "kept: $(cd "$APPDIR/usr/lib" && ls)"

echo "==> replace hnsd"
rm "$APPDIR/usr/bin/hnsd"
install -m755 "$B/hnsd/hnsd" "$APPDIR/usr/bin/hnsd-core"
gcc -O2 -Wall -o "$APPDIR/usr/bin/hnsd" wrapper/hnsd-wrapper-linux.c

# hnsd-core's own libraries go in a separate folder so they never clash with
# the tray libraries fingertip uses from usr/lib.
mkdir -p "$APPDIR/usr/lib/hnsd"
ldd "$APPDIR/usr/bin/hnsd-core" | awk '$3 ~ /^\// {print $3}' | while read -r lib; do
  case "$(basename "$lib")" in
    # glibc is provided by the host system
    libc.so*|libm.so*|libdl.so*|librt.so*|libpthread.so*|libresolv.so*|ld-linux*) ;;
    *) cp -L "$lib" "$APPDIR/usr/lib/hnsd/" ;;
  esac
done
patchelf --set-rpath '$ORIGIN/../lib/hnsd' "$APPDIR/usr/bin/hnsd-core"
for lib in "$APPDIR"/usr/lib/hnsd/*; do patchelf --set-rpath '$ORIGIN' "$lib"; done

echo "==> branding and notices"
sed -i -e 's/^Name=.*/Name=Fingertip-dit/' -e "s/^X-AppImage-Version=.*/X-AppImage-Version=$VERSION/" \
  "$APPDIR/fingertip.desktop"
cp "$APPDIR/fingertip.desktop" "$APPDIR/usr/share/applications/fingertip.desktop"
mkdir -p "$APPDIR/usr/share/doc/fingertip-dit"
{
  cat THIRD-PARTY-NOTICES.txt
  for n in fingertip hnsd unbound openssl; do
    printf '\n\n----- %s license -----\n\n' "$n"
    cat "licenses/$n-LICENSE.txt"
  done
} > "$APPDIR/usr/share/doc/fingertip-dit/THIRD-PARTY-NOTICES.txt"

echo "==> check"
missing=$(ldd "$APPDIR/usr/bin/hnsd-core" | grep 'not found' || true)
if [ -n "$missing" ]; then echo "error: $missing" >&2; exit 1; fi
ldd "$APPDIR/usr/bin/hnsd-core" | grep -E 'unbound|ssl|crypto'
"$APPDIR/usr/bin/hnsd-core" --version

echo "==> AppImage"
curl -fsSL -o "$B/appimagetool" "$APPIMAGETOOL_URL"
chmod +x "$B/appimagetool"
echo "appimagetool sha256: $(sha256sum "$B/appimagetool" | cut -d' ' -f1)"
OUT="dist/Fingertip-dit-$VERSION-x86_64.AppImage"
ARCH=x86_64 "$B/appimagetool" --no-appstream "$APPDIR" "$OUT"
(cd dist && sha256sum "$(basename "$OUT")" | tee "$(basename "$OUT").sha256")
