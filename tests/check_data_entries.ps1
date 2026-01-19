$lines = Get-Content 'd:\OneDrive\WIP\Sources\Intense.2020\D+AI\c2-inc-v17.pbi'
$inDataSection = $false
$count = 0
$targets = @(279, 280, 281, 282, 283, 284, 285)

foreach ($line in $lines) {
    if ($line -match 'c2tokens:') {
        $inDataSection = $true
        continue
    }
    if ($inDataSection -and $line -match 'Data\.s\s+"([^"]+)"') {
        $name = $Matches[1]
        if ($targets -contains $count) {
            Write-Output "Entry $count = $name"
        }
        $count++
        if ($line -match 'Data\.s\s+"-"') {
            break
        }
    }
}
Write-Output "Total data entries: $count"
