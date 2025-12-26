# Remove #pragma optimizecode from all .lj files
$files = Get-ChildItem "d:\OneDrive\WIP\Sources\Intense.2020\lj2\Examples\*.lj"
foreach ($file in $files) {
    $content = Get-Content -Path $file.FullName -Raw
    if ($content -match '#pragma optimizecode') {
        $newContent = $content -replace '#pragma optimizecode on\r?\n', ''
        $newContent = $newContent -replace '#pragma optimizecode off\r?\n', ''
        Set-Content -Path $file.FullName -Value $newContent -NoNewline
        Write-Host "Updated: $($file.Name)"
    }
}
Write-Host "Done!"
