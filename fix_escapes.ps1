# Fix escape sequences in LJ files
$files = @(
    "Examples\18 test pragma no optimize.lj",
    "Examples\19 Mandelbrot.lj",
    "Examples\21 Julia Set.lj",
    "Examples\26 test array of pointers.lj",
    "Examples\27 test function pointers.lj",
    "Examples\28 test pointers comprehensive.lj"
)

foreach ($file in $files) {
    if (Test-Path $file) {
        Write-Host "Processing: $file"
        $content = Get-Content $file -Raw

        # Replace standalone "\n" with ""
        $content = $content -replace '\\n"', '"'

        Write-Host "  Removed \n escape sequences"

        Set-Content -Path $file -Value $content -NoNewline
    }
}

Write-Host "Done! Note: You'll need to manually add print(`"`"); where line breaks are needed."
