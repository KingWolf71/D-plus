$file = 'd:\OneDrive\WIP\Sources\Intense.2020\D+AI\c2-pointers-v05.pbi'
$content = Get-Content $file -Raw

# Add frameTop save after frameBase save
$old = '   gStack(gStackDepth)\frameBase = savedLocalBase
   gStack(gStackDepth)\localCount = totalVars'
$new = '   gStack(gStackDepth)\frameBase = savedLocalBase
   gStack(gStackDepth)\frameTop = gFrameTop     ; V1.034.21: Save caller''s frameTop (was missing!)
   gStack(gStackDepth)\localCount = totalVars'

$content = $content.Replace($old, $new)
Set-Content $file -Value $content -NoNewline
Write-Output "Fixed CALLFUNCPTR - added frameTop save"
