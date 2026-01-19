$content = Get-Content 'd:\OneDrive\WIP\Sources\Intense.2020\D+AI\c2-arrays-v06.pbi' -Raw

# Pattern 1: gVar(slot)\i or gVar(slot)\ss etc. (direct variable access) -> *gVar(slot)\var(0)\i
$content = $content -replace 'gVar\(([^)]+)\)\\([isfb])\b', '*gVar($1)\var(0)\$2'

# Pattern 2: gVar(slot)\dta -> *gVar(slot)\var(0)\dta
$content = $content -replace 'gVar\(([^)]+)\)\\dta', '*gVar($1)\var(0)\dta'

# Pattern 3: gVar(slot)\ptrtype -> *gVar(slot)\var(0)\ptrtype
$content = $content -replace 'gVar\(([^)]+)\)\\ptrtype', '*gVar($1)\var(0)\ptrtype'

# Pattern 4: gVar(slot)\ptr -> *gVar(slot)\var(0)\ptr
$content = $content -replace 'gVar\(([^)]+)\)\\ptr\b', '*gVar($1)\var(0)\ptr'

# Pattern 5: gLocal(slot)\i etc -> _LVAR(slot)\i (macro handles the rest)
$content = $content -replace 'gLocal\(([^)]+)\)\\', '_LVAR($1)\'

# Pattern 6: gLocal(slot) alone (rare but possible)
$content = $content -replace 'gLocal\(([^)]+)\)', '_LVAR($1)'

Set-Content 'd:\OneDrive\WIP\Sources\Intense.2020\D+AI\c2-arrays-v06.pbi' -Value $content -NoNewline

Write-Host "Replacements completed"
