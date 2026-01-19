# Fix remaining gLocal references

$file = "d:/OneDrive/WIP/Sources/Intense.2020/D+AI/c2-vm-V16.pb"
$content = Get-Content $file -Raw

# Comment out the localstack pragma line
$content = $content -replace 'vm_SetArrayFromPragma\("localstack", gLocal, gMaxEvalStack\)', '; V1.034.12: localstack removed - locals in gEvalStack'

# Fix comment about gLocal[0]
$content = $content -replace 'gFrameBase = 0\s+; Local variables start at gLocal\[0\]', 'gFrameBase = 0                      ; V1.034.12: Frame locals start at gEvalStack[0]'

Set-Content $file $content -NoNewline
Write-Host "Fixed remaining gLocal references"
