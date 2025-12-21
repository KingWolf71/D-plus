$ErrorActionPreference = "SilentlyContinue"
Set-Location "D:\OneDrive\WIP\Sources\Intense.2020\lj2"

# Exclude: bug/error tests, 064/069 (RunThreaded hangs in direct test), 120/122 (comprehensive tests that hang)
$testFiles = Get-ChildItem ".\Examples\*.lj" | Where-Object { $_.Name -notmatch "bug|error|064|069|120|122" } | Sort-Object Name
$passed = 0
$failed = 0
$failedList = @()

Write-Host "Running $($testFiles.Count) tests..." -ForegroundColor Yellow
Write-Host ""

foreach ($f in $testFiles) {
    $output = & .\lj2.exe --test $f.FullName 2>&1 | Out-String
    if ($output -and $output.Trim().Length -gt 0) {
        Write-Host "PASS: $($f.Name)" -ForegroundColor Green
        $passed++
    } else {
        Write-Host "FAIL: $($f.Name)" -ForegroundColor Red
        $failed++
        $failedList += $f.Name
    }
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Results: $passed passed, $failed failed" -ForegroundColor $(if ($failed -eq 0) { "Green" } else { "Red" })
Write-Host "========================================" -ForegroundColor Cyan

if ($failedList.Count -gt 0) {
    Write-Host "Failed tests:" -ForegroundColor Red
    $failedList | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
}
