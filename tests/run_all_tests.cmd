@echo off
setlocal enabledelayedexpansion

cd /d "%~dp0.."

set PASSED=0
set FAILED=0

for %%f in (Examples\*.d) do (
    set "NAME=%%~nxf"

    REM Run compiler and save output
    dpai.exe -t "%%f" > "%TEMP%\lj2out.txt" 2>&1

    REM Check for expected error test
    echo !NAME! | findstr /i "130-error" > nul
    if !errorlevel! equ 0 (
        REM This should fail to compile - use find with /u for Unicode
        find /i "COMPILATION" "%TEMP%\lj2out.txt" > nul 2>&1
        if !errorlevel! equ 0 (
            echo [PASS] !NAME! ^(expected compile error^)
            set /a PASSED+=1
        ) else (
            echo [FAIL] !NAME! ^(should have failed to compile^)
            set /a FAILED+=1
        )
    ) else (
        REM Normal test - should compile and run
        set FAILED_TEST=0
        find /i "COMPILATION FAILED" "%TEMP%\lj2out.txt" > nul 2>&1 && set FAILED_TEST=1
        find /i "AST Error" "%TEMP%\lj2out.txt" > nul 2>&1 && set FAILED_TEST=1
        find /i "LOAD ERROR" "%TEMP%\lj2out.txt" > nul 2>&1 && set FAILED_TEST=1

        if !FAILED_TEST! equ 1 (
            echo [FAIL] !NAME!
            set /a FAILED+=1
        ) else (
            echo [PASS] !NAME!
            set /a PASSED+=1
        )
    )
)

echo.
echo === WINDOWS RESULTS ===
echo Passed: %PASSED%
echo Failed: %FAILED%

del "%TEMP%\lj2out.txt" 2>nul
