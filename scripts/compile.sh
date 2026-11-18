#!/usr/bin/env bash
# Compile every .lua under SRC_DIR to LuaJIT bytecode in OUT_DIR,
# keeping the folder structure.
#
# Usage: scripts/compile.sh [SRC_DIR] [OUT_DIR]
# Env:   LUAJIT  path to luajit binary   (default: .luajit/bin/luajit, then PATH)
#        STRIP   1 = strip debug info, 0 = keep it (default 1, same as the old compile.bat)
#        EXT     output extension        (default luac)
set -euo pipefail

SRC_DIR="${1:-src}"
OUT_DIR="${2:-dist}"
STRIP="${STRIP:-1}"
EXT="${EXT:-luac}"

if [ -z "${LUAJIT:-}" ]; then
  if [ -x ".luajit/bin/luajit" ]; then LUAJIT=".luajit/bin/luajit"
  else LUAJIT="$(command -v luajit || true)"; fi
fi
[ -n "$LUAJIT" ] && [ -x "$LUAJIT" ] || { echo "luajit not found. Run scripts/build-luajit.sh first." >&2; exit 1; }
[ -d "$SRC_DIR" ] || { echo "Source dir '$SRC_DIR' not found." >&2; exit 1; }

FLAG=-s; [ "$STRIP" = "0" ] && FLAG=-g

count=0
while IFS= read -r -d '' f; do
  rel="${f#"$SRC_DIR"/}"
  out="$OUT_DIR/${rel%.lua}.$EXT"
  mkdir -p "$(dirname "$out")"
  echo "  $f -> $out"
  "$LUAJIT" -b "$FLAG" "$f" "$out"
  count=$((count + 1))
done < <(find "$SRC_DIR" -type f -name '*.lua' -print0 | sort -z)

[ "$count" -gt 0 ] || { echo "No .lua files found in $SRC_DIR" >&2; exit 1; }
echo "Compiled $count file(s) with $("$LUAJIT" -v | cut -d' ' -f1-2)"
