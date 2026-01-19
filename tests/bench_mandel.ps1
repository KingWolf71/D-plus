# Benchmark Mandelbrot-b 10 times
Set-Location 'D:\OneDrive\WIP\Sources\D+AI.2026'

Write-Host "=== Mandelbrot-b Benchmark (10 runs) ===" -ForegroundColor Cyan

$times = @()
for ($i = 1; $i -le 10; $i++) {
    $output = & ./dpai.exe -t 'Examples/112 Mandelbrot-b.d' 2>&1
    $runtime = $output | Where-Object { $_.ToString() -match 'Runtime: (\d+\.\d+)' }
    if ($runtime) {
        $match = [regex]::Match($runtime.ToString(), 'Runtime: (\d+\.\d+)')
        if ($match.Success) {
            $time = [double]$match.Groups[1].Value
            $times += $time
            Write-Host "Run $i`: $time seconds"
        }
    }
}

if ($times.Count -gt 0) {
    $avg = ($times | Measure-Object -Average).Average
    $min = ($times | Measure-Object -Minimum).Minimum
    $max = ($times | Measure-Object -Maximum).Maximum
    Write-Host "`n=== Results ===" -ForegroundColor Green
    Write-Host "Average: $([math]::Round($avg, 3)) seconds"
    Write-Host "Min: $min seconds"
    Write-Host "Max: $max seconds"
}
