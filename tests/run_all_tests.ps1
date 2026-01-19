param([string]$Compiler = ".\dpai.exe")

$ErrorActionPreference = "SilentlyContinue"
Set-Location (Split-Path $PSScriptRoot -Parent)

$passed = 0
$failed = 0
$failedTests = @()

$examples = Get-ChildItem "Examples\*.d" | Sort-Object Name

foreach ($file in $examples) {
    $name = $file.Name

    # Run compiler using cmd to properly capture output
    $output = cmd /c "`"$Compiler`" -t `"$($file.FullName)`" 2>&1"
    if ($output -is [array]) { $output = $output -join "`n" }
    if ($null -eq $output) { $output = "" }

    $isCompileError = $output -match "COMPILATION FAILED|AST Error|Scanner Error"
    $isLoadError = $output -match "LOAD ERROR"

    if ($name -match "130-error") {
        # Expected to fail compilation
        if ($isCompileError) {
            Write-Host "[PASS] $name (expected compile error)" -ForegroundColor Green
            $passed++
        } else {
            Write-Host "[FAIL] $name (should have failed)" -ForegroundColor Red
            $failed++
            $failedTests += $name
        }
    } elseif ($isCompileError -or $isLoadError) {
        Write-Host "[FAIL] $name" -ForegroundColor Red
        $failed++
        $failedTests += $name
    } else {
        Write-Host "[PASS] $name" -ForegroundColor Green
        $passed++
    }
}

Write-Host ""
Write-Host "=== RESULTS ===" -ForegroundColor Cyan
Write-Host "Passed: $passed" -ForegroundColor Green
Write-Host "Failed: $failed" -ForegroundColor $(if ($failed -gt 0) { "Red" } else { "Green" })
if ($failedTests.Count -gt 0) {
    Write-Host "Failed tests:" -ForegroundColor Red
    foreach ($t in $failedTests) {
        Write-Host "  - $t" -ForegroundColor Red
    }
}
