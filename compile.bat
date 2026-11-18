@echo off
rem Windows: needs luajit.exe (2.1) on PATH. Output goes next to the input.
luajit.exe -b -s %1 "%~dpn1.luac"
