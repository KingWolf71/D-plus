# Fix localBase field reference in c2-pointers-v05.pbi
$file = "d:/OneDrive/WIP/Sources/Intense.2020/D+AI/c2-pointers-v05.pbi"
$content = Get-Content $file -Raw
$content = $content.Replace(")\localBase", ")\frameBase")
Set-Content $file $content -NoNewline
Write-Host "Fixed localBase -> frameBase in c2-pointers-v05.pbi"
