# Fix all gLocal references in remaining .pbi files
$basePath = "d:/OneDrive/WIP/Sources/Intense.2020/D+AI"

$filesToFix = @(
    "c2-collections-v03.pbi",
    "c2-pointers-v05.pbi"
)

foreach ($fileName in $filesToFix) {
    $file = Join-Path $basePath $fileName
    if (Test-Path $file) {
        Write-Host "Patching $fileName..." -ForegroundColor Yellow
        $content = Get-Content $file -Raw
        $content = $content.Replace("gLocal(", "gEvalStack(")
        $content = $content.Replace("gLocalBase", "gFrameBase")
        $content = $content.Replace("gLocalTop", "gFrameTop")
        $content = $content.Replace("gLocalStack", "gMaxEvalStack")
        $content = $content.Replace(")\localBase", ")\frameBase")
        Set-Content $file $content -NoNewline
        Write-Host "  Done" -ForegroundColor Green
    }
}

Write-Host "All files patched!" -ForegroundColor Cyan
