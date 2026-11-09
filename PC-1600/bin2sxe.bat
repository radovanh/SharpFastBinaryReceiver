@echo off
rem Make an .sxe (escaped .sxb for the PC-1600) from a .bin; needs Python 3:
rem   bin2sxe prog.bin C300 --exec C300
if "%~2"=="" (
  echo usage: bin2sxe FILE.bin ADDR [--exec ADDR] [-o OUT.sxe]   addresses in hex, e.g. C300
  exit /b 1
)
python "%~dp0bin2sxe.py" %*
