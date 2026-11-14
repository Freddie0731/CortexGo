@echo off
rem ===========================================================================
rem  GoAI3 -- single-file optimized build (MSVC x64)
rem
rem  Usage:  build.bat            (Release, AVX2 + LTCG, default)
rem          build.bat portable   (no /arch:AVX2 -- runs on any x64 CPU)
rem          build.bat debug      (unoptimized, asserts on)
rem
rem  Requires the MSVC x64 toolchain. The script locates vcvars64.bat itself
rem  from the usual Visual Studio install roots; set VCVARS64 to override.
rem ===========================================================================
setlocal

set SRC=go_ai_single.cpp
set OUT=GoAI3.exe

if /i "%~1"=="portable" (
    set ARCH=
    set MODE=portable (SSE2 baseline)
) else if /i "%~1"=="debug" (
    set ARCH=
    set MODE=debug
) else (
    set ARCH=/arch:AVX2
    set MODE=release (AVX2 + LTCG)
)

rem ---- locate the MSVC environment ----------------------------------------
if not defined VCVARS64 (
    for %%R in (
        "C:\Program Files\Microsoft Visual Studio\18\Community"
        "C:\Program Files\Microsoft Visual Studio\18\BuildTools"
        "C:\Program Files\Microsoft Visual Studio\17\Community"
        "C:\Program Files\Microsoft Visual Studio\17\BuildTools"
        "C:\Program Files (x86)\Microsoft Visual Studio\2019\Community"
        "C:\Program Files (x86)\Microsoft Visual Studio\2019\BuildTools"
    ) do (
        if not defined VCVARS64 if exist "%%~R\VC\Auxiliary\Build\vcvars64.bat" (
            set VCVARS64=%%~R\VC\Auxiliary\Build\vcvars64.bat
        )
    )
)
if not defined VCVARS64 (
    echo [FAILED] vcvars64.bat not found. Open a "x64 Native Tools" prompt
    echo          or set VCVARS64 to its full path, then rerun.
    exit /b 1
)

call "%VCVARS64%" >nul
if errorlevel 1 (
    echo [FAILED] could not initialise the MSVC environment.
    exit /b 1
)

rem ---- compile ------------------------------------------------------------
rem  /O2   optimise for speed          /GL /LTCG  whole-program optimisation
rem  /Oi   intrinsic inlining          /Ot        favour speed over size
rem  /fp:fast  relaxed float math      /openmp    parallel CPU kernels
rem  /utf-8    source is UTF-8 with BOM (Chinese comments in the amalgamation)
echo Building %MODE% ...
if /i "%~1"=="debug" (
    cl /nologo /Od /Zi /EHsc /std:c++20 /W3 /utf-8 /openmp %SRC% ^
       /Fe:%OUT% /link gdiplus.lib gdi32.lib user32.lib
) else (
    cl /nologo /O2 /GL /Oi /Ot %ARCH% /fp:fast /EHsc /std:c++20 /W3 /DNDEBUG ^
       /utf-8 /openmp %SRC% /Fe:%OUT% ^
       /link /LTCG gdiplus.lib gdi32.lib user32.lib
)
if errorlevel 1 (
    echo [FAILED] compile or link failed.
    exit /b 1
)

del /q *.obj 2>nul
echo.
echo Built %OUT%
echo.
echo Running the self test ...
%OUT% --selftest
if errorlevel 1 (
    echo [FAILED] self test did not report SELF TEST PASSED.
    exit /b 1
)
echo.
echo OK. Run "run.bat" for the GUI, or "run.bat cli" for GTP on stdio.
endlocal
