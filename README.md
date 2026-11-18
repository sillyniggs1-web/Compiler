# LuaJIT 2.1 bytecode compiler (GitHub Actions)

Compiles every `.lua` in `src/` to LuaJIT bytecode (`.luac`) on every push, using
LuaJIT **2.1.0-beta3** built from source, so no `luajit.exe` / `lua51.dll` is committed.

## Use it

1. Put your scripts in `src/` (subfolders are kept).
2. Push to `main`/`master`, or run **Actions → Compile Lua to LuaJIT bytecode → Run workflow**.
3. Download the `luajit-bytecode` artifact from the run.
4. Push a tag like `v1.0` and the compiled files are also attached to a GitHub Release.

Manual run options: `strip` (default on, same as the old `compile.bat`) and `ext` (default `luac`).

## Run locally (Linux/macOS/WSL)

    bash scripts/build-luajit.sh        # once, builds into .luajit/
    bash scripts/compile.sh src dist    # STRIP=0 to keep debug info, EXT=lua to change extension

## Windows

`compile.bat file.lua` works if a LuaJIT 2.1 `luajit.exe` is on your PATH.

## Notes

- Pinned to commit `80aaaee` (2018-01-18) to match the old bundled compiler. Change
  `LUAJIT_REF` in `scripts/build-luajit.sh` to use a newer LuaJIT (the cache key follows the file).
- The old exe was 32-bit. This builds 64-bit; the bytecode format is the same for
  non-GC64 builds, so 32-bit targets (e.g. armeabi-v7a) can load it.
- A syntax error in any file fails the workflow.
