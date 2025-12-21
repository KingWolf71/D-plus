param([string]$testFile = "069 test typed pointer opcodes.lj")

$proc = Start-Process -FilePath '.\lj2.exe' -ArgumentList '--test', ".\Examples\$testFile" -NoNewWindow -PassThru -RedirectStandardOutput 'debug-out.txt' -RedirectStandardError 'debug-err.txt'
$completed = $proc.WaitForExit(15000)
if (-not $completed) {
    $proc.Kill()
    Write-Output "TIMEOUT - Process killed after 15 seconds"
} else {
    Write-Output "Completed with exit code: $($proc.ExitCode)"
}

Write-Output "`n=== STDOUT (first 50 lines) ==="
Get-Content 'debug-out.txt' -ErrorAction SilentlyContinue | Select-Object -First 50

Write-Output "`n=== STDERR ==="
Get-Content 'debug-err.txt' -ErrorAction SilentlyContinue | Select-Object -First 20
