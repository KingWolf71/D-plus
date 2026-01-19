$file = Get-Content 'd:\OneDrive\WIP\Sources\Intense.2020\D+AI\c2-inc-v17.pbi' -Raw

# Count enum entries between #ljUNUSED and #ljPTRADD (which is 279)
$enumSection = $file -split 'Enumeration\r?\n\s+#ljUNUSED' | Select-Object -Last 1
$enumSection = $enumSection -split '#ljPTRADD' | Select-Object -First 1

# Count non-comment lines starting with #lj
$enumLines = ($enumSection -split '\r?\n') | Where-Object { $_ -match '^\s*#lj' }
Write-Output "Enum entries before PTRADD: $($enumLines.Count)"

# Count Data.s entries between "UNUSED" and "PTRADD"
$dataSection = $file -split 'Data\.s\s+"UNUSED"' | Select-Object -Last 1
$dataSection = $dataSection -split 'Data\.s\s+"PTRADD"' | Select-Object -First 1

$dataLines = ($dataSection -split '\r?\n') | Where-Object { $_ -match 'Data\.s\s+"' }
Write-Output "Data entries before PTRADD: $($dataLines.Count)"

Write-Output ""
Write-Output "If enum has more entries than Data, there are MISSING Data entries."
Write-Output "If Data has more entries than enum, there are EXTRA Data entries."
