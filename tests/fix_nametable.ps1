$filePath = 'd:\OneDrive\WIP\Sources\Intense.2020\D+AI\c2-inc-v17.pbi'
$content = Get-Content $filePath -Raw

# Add LLPMOV entry after LLMOVF (line 1705) and before INC_VAR comment (line 1707)
$old1 = @'
   Data.s   "LLMOVF"
   Data.i   0, 0

   ; In-place increment/decrement opcodes
'@

$new1 = @'
   Data.s   "LLMOVF"
   Data.i   0, 0
   Data.s   "LLPMOV"          ; V1.034.21: Deprecated placeholder (use PMOV with n=3)
   Data.i   0, 0

   ; In-place increment/decrement opcodes
'@

$content = $content.Replace($old1, $new1)
Set-Content $filePath -Value $content -NoNewline
Write-Output 'Done adding LLPMOV to name table'
