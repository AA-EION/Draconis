#!/usr/bin/env bash
# Builds Steam's steamwebhelper wrapper (Tools/steamwebhelper-wrapper, MIT,
# from notpop/steam-on-m1-wine) into the app's resources. Draconis Wine needs
# it for Steam's window to draw; without mingw-w64 the build skips it.
set -euo pipefail
cd "$(dirname "$0")/.."
CC="${CC:-x86_64-w64-mingw32-gcc}"
OUT="Draconis/Resources/steamwebhelper.exe"
if ! command -v "$CC" >/dev/null 2>&1; then
  echo "warning: $CC not found (brew install mingw-w64); Steam under Draconis Wine will lack its window fix" >&2
  exit 0
fi
"$CC" -O2 -Wall -Wextra -municode -DUNICODE -D_UNICODE \
  -o "$OUT" Tools/steamwebhelper-wrapper/steamwebhelper-wrapper.c -static -lshell32 -mwindows
echo "Built $OUT ($(wc -c < "$OUT" | tr -d ' ') bytes)"
