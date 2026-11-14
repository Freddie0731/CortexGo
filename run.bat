@echo off
rem ===========================================================================
rem  GoAI3 launcher
rem
rem   run.bat              GUI (Win32 board window)
rem   run.bat cli          GTP engine on stdio (Sabaki / KaTrain / etc.)
rem   run.bat bench        speed benchmark
rem   run.bat test         built-in self test
rem
rem  Everything runs with this folder as the working directory, because the
rem  engine looks for the weights and the ONNX model RELATIVE TO THE CWD.
rem ===========================================================================
setlocal
cd /d "%~dp0"

if not exist GoAI3.exe (
    echo [FAILED] GoAI3.exe not found. Run build.bat first.
    exit /b 1
)

if /i "%~1"=="cli"   goto cli
if /i "%~1"=="bench" goto bench
if /i "%~1"=="test"  goto test

:gui
GoAI3.exe %*
exit /b %errorlevel%

:cli
GoAI3.exe --cli %2 %3 %4 %5 %6 %7 %8 %9
exit /b %errorlevel%

:bench
GoAI3.exe --benchmark %2 %3 %4 %5 %6 %7 %8 %9
exit /b %errorlevel%

:test
GoAI3.exe --selftest
exit /b %errorlevel%
