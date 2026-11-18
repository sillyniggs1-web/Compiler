#!/usr/bin/env bash
# Builds LuaJIT 2.1 from source into $PREFIX (default: ./.luajit).
# Pinned to the v2.1 commit that matches the old bundled luajit.exe
# (LuaJIT 2.1.0-beta3, jit/*.lua dated 2018-01-18), so bytecode is identical.
set -euo pipefail

LUAJIT_REF="${LUAJIT_REF:-80aaaeee99d7f7b06c9e75ed3a457c49d86fc4db}"
PREFIX="${PREFIX:-$PWD/.luajit}"
WORK="${WORK:-$(mktemp -d)}"

if [ -x "$PREFIX/bin/luajit" ]; then
  echo "LuaJIT already built at $PREFIX"; exit 0
fi

git clone --quiet https://github.com/LuaJIT/LuaJIT.git "$WORK/LuaJIT"
cd "$WORK/LuaJIT"
git checkout --quiet "$LUAJIT_REF"

# PREFIX must be passed to BOTH make and make install, otherwise the
# binary can't find its jit/*.lua modules (needed for `luajit -b`).
make -j"$(nproc 2>/dev/null || echo 2)" amalg PREFIX="$PREFIX"
make install PREFIX="$PREFIX"
ln -sf luajit-2.1.0-beta3 "$PREFIX/bin/luajit"

"$PREFIX/bin/luajit" -v
