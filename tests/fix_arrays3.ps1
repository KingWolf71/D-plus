$content = Get-Content 'd:\OneDrive\WIP\Sources\Intense.2020\D+AI\c2-arrays-v06.pbi' -Raw

# Pattern: *gVar(...)\i or \s etc. where there's no \var(0) after the closing paren
# Match *gVar(...)\field and insert \var(0) before \field
# Using negative lookahead to avoid matching if \var is already there
$content = $content -replace '(\*gVar\([^)]+\))(?!\\var\(0\))(\\[isfb]\b)', '$1\var(0)$2'

# Same for \dta
$content = $content -replace '(\*gVar\([^)]+\))(?!\\var\(0\))(\\dta)', '$1\var(0)$2'

# Same for \ptrtype
$content = $content -replace '(\*gVar\([^)]+\))(?!\\var\(0\))(\\ptrtype)', '$1\var(0)$2'

# Same for \ptr
$content = $content -replace '(\*gVar\([^)]+\))(?!\\var\(0\))(\\ptr\b)', '$1\var(0)$2'

Set-Content 'd:\OneDrive\WIP\Sources\Intense.2020\D+AI\c2-arrays-v06.pbi' -Value $content -NoNewline

Write-Host "Done"
