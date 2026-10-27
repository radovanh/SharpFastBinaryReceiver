@echo off
rem Make an .sxb for SXRECVB from a .bin (uses PowerShell, built into Windows 7 and later):
rem   bin2sxb prog.bin ADDR [--exec ADDR] [-o out.sxb]      addresses in hex, e.g.
rem   bin2sxb prog.bin 1000 --exec 1000
if "%~2"=="" (
  echo usage: bin2sxb FILE.bin ADDR [--exec ADDR] [-o OUT.sxb]   addresses in hex, e.g. 1000
  exit /b 1
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0bin2sxb.ps1" %*
