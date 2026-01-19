$content = Get-Content 'd:\OneDrive\WIP\Sources\Intense.2020\D+AI\c2-arrays-v06.pbi' -Raw

# Replace any remaining gVar( that's not already *gVar(
$content = $content -replace '(?<!\*)(gVar\()', '*$1'

Set-Content 'd:\OneDrive\WIP\Sources\Intense.2020\D+AI\c2-arrays-v06.pbi' -Value $content -NoNewline

Write-Host "Done"
