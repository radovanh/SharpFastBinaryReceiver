@echo off
rem Convert a .bin to .sxb and send it over serial in one step:
rem   bin2send COM5 prog.bin ADDR [--exec ADDR] [sxsend options]
rem   bin2send COM5 prog.bin 1000 --exec 1000
rem   bin2send COM5 prog.bin 1000 --exec 1000 -Stop 2        (PC-G815)
rem ADDR in hex. The .sxb is written next to the .bin. Anything after the --exec
rem part is passed to sxsend (-Baud, -Stop, -Pause, -Delay, -RtsCts).
rem Start it only when the pocket computer shows the waiting screen.
if "%~3"=="" (
  echo usage: bin2send COMx FILE.bin ADDR [--exec ADDR] [-Baud n] [-Stop 1^|2] [-Pause MS] [-Delay MS] [-RtsCts]
  exit /b 1
)
set "SX_DIR=%~dp0"
set "SX_PORT=%~1"
set "SX_BIN=%~2"
set "SX_ADDR=%~3"
set "SX_OUT=%~dpn2.sxb"
set "SX_EXEC="
set "SX_REST="
shift
shift
shift
:args
if "%~1"=="" goto run
if /i "%~1"=="--exec" (
  set "SX_EXEC=--exec %~2"
  shift
  shift
  goto args
)
set "SX_REST=%SX_REST% %1"
shift
goto args
:run
powershell -NoProfile -ExecutionPolicy Bypass -File "%SX_DIR%..\release\bin2sxb.ps1" "%SX_BIN%" %SX_ADDR% %SX_EXEC% -o "%SX_OUT%"
if errorlevel 1 exit /b 1
powershell -NoProfile -ExecutionPolicy Bypass -File "%SX_DIR%sxsend.ps1" %SX_PORT% "%SX_OUT%" %SX_REST%
exit /b %errorlevel%
