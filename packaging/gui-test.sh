#!/usr/bin/env bash
# Launches the whole app from an AppImage (fingertip + tray + hnsd) on a virtual
# X display and fails if it crashes or logs GTK/GLib errors within 25 seconds.
# Catches library clashes such as "undefined symbol: g_module_open_full".
# Needs: Xvfb, dbus-run-session, GTK 3 from the distro.
# Usage: gui-test.sh <AppImage>
set -uo pipefail
APPIMAGE=$(realpath "$1")
WORK=$(mktemp -d)
LOG="$WORK/app.log"
export HOME="$WORK/home" XDG_DATA_HOME="$WORK/home/.local/share" XDG_CONFIG_HOME="$WORK/home/.config"
mkdir -p "$HOME"

cd "$WORK" && chmod +x "$APPIMAGE" && "$APPIMAGE" --appimage-extract >/dev/null
echo "--- libraries fingertip can't find:"
if ldd squashfs-root/usr/bin/fingertip | grep 'not found'; then
  echo "FAIL: missing libraries"; exit 1
fi
echo "(none)"

Xvfb :99 -screen 0 1024x768x24 >/dev/null 2>&1 &
XVFB=$!
trap 'kill $XVFB 2>/dev/null' EXIT
sleep 2

DISPLAY=:99 timeout 25 dbus-run-session -- squashfs-root/AppRun >"$LOG" 2>&1
code=$?
echo "--- app output (exit code $code; 124 means it was still running):"
grep -vE '^\S+ \S+ \[INFO\] hns: ' "$LOG" | head -40

if grep -qE 'symbol lookup error|undefined symbol|GLib-GIO-ERROR|Gtk-ERROR|Settings schema .* does not contain|SIGSEGV|^panic:|^fatal error:' "$LOG"; then
  echo "FAIL: library/GTK error in output"; exit 1
fi
if [ "$code" -ne 124 ]; then
  echo "FAIL: app exited after less than 25s"; exit 1
fi
if ! grep -q 'hns: ' "$LOG"; then
  echo "FAIL: app never started hnsd"; exit 1
fi
echo "OK: app ran for 25s with no GTK/GLib errors and started hnsd"
