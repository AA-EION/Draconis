#!/usr/bin/env bash
# usage: compare.sh <macos shots dir> <out dir> <draconis binary>
# For each page: crops the macOS window, renders the Rust UI at that size and
# position over the same desktop, and writes a side-by-side image,
# a difference image and an RMSE score (0 = identical, 1 = opposite).
set -euo pipefail
mac=$1 out=$2 bin=$3
mkdir -p "$out"
echo "| Page | RMSE |" > "$out/scores.txt"
echo "|---|---|" >> "$out/scores.txt"
for page in play mods servers console settings; do
  shot="$mac/macos-$page.png"
  [ -f "$shot" ] || continue
  window=$mac/macos-window.txt
  [ "$page" = settings ] && window=$mac/macos-settings-window.txt
  IFS=, read -r x y w h < "$window"
  geometry="${w}x${h}+${x}+${y}"
  convert "$shot" -crop "$geometry" +repage "$out/$page-macos.png"
  if [ "$page" = settings ]; then
    "$bin" --snapshot "$out/$page-rust.png" "${w}x${h}" "$page"
  else
    "$bin" --snapshot "$out/$page-rust.png" "${w}x${h}" "$page" --backdrop "$mac/desktop.png" --at "$x,$y"
  fi
  score=$(compare -metric RMSE "$out/$page-macos.png" "$out/$page-rust.png" null: 2>&1 | sed -E 's/.*\((.*)\).*/\1/' || true)
  compare -fuzz 6% "$out/$page-macos.png" "$out/$page-rust.png" -compose src "$out/$page-diff.png" || true
  convert "$out/$page-macos.png" "$out/$page-rust.png" "$out/$page-diff.png" +append "$out/$page-side-by-side.png"
  echo "| $page | $score |" >> "$out/scores.txt"
done
cat "$out/scores.txt"
