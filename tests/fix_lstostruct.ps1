$filePath = 'd:\OneDrive\WIP\Sources\Intense.2020\D+AI\c2-inc-v17.pbi'
$content = Get-Content $filePath -Raw

# Add missing LSTOSTRUCT entry after STOSTRUCT
$old = @'
   Data.s   "STOSTRUCT"
   Data.i   0, 0

   ; In-place compound assignment opcodes (renamed V1.029.61)
   Data.s   "ADDASS"
'@

$new = @'
   Data.s   "STOSTRUCT"
   Data.i   0, 0
   Data.s   "LSTOSTRUC"       ; V1.034.21: Missing entry - LSTORE_STRUCT (local variant)
   Data.i   0, 0

   ; In-place compound assignment opcodes (renamed V1.029.61)
   Data.s   "ADDASS"
'@

$content = $content.Replace($old, $new)
Set-Content $filePath -Value $content -NoNewline
Write-Output 'Done adding LSTOSTRUCT to Data section'
