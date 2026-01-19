# Refactor opcode names - replace DataSection with inline InitOpcodeNames procedure

$incFile = 'd:\OneDrive\WIP\Sources\Intense.2020\D+AI\c2-inc-v18.pbi'
$opcodeProc = Get-Content 'd:\OneDrive\WIP\Sources\Intense.2020\D+AI\opcode_names_proc_v18.txt' -Raw
$content = Get-Content $incFile -Raw

# Find the DataSection start
$dataSectionMatch = [regex]::Match($content, '(?ms)^;- End of file\r?\n\r?\nDataSection\r?\nc2tokens:.*?EndDataSection\r?\n')

if ($dataSectionMatch.Success) {
    Write-Output "Found DataSection at position $($dataSectionMatch.Index), length $($dataSectionMatch.Length)"

    # Build replacement: InitOpcodeNames procedure + IDE Options comment only
    $replacement = ";- End of file`r`n`r`n" + $opcodeProc

    # Replace DataSection with the new procedure
    $newContent = $content.Substring(0, $dataSectionMatch.Index) + $replacement

    # Get any IDE Options after EndDataSection (keep them)
    $afterDataSection = $content.Substring($dataSectionMatch.Index + $dataSectionMatch.Length)
    $newContent += $afterDataSection

    # Write back
    Set-Content $incFile -Value $newContent -NoNewline
    Write-Output "DataSection replaced with InitOpcodeNames procedure"
    Write-Output "Removed approximately $($dataSectionMatch.Length) bytes of DataSection"
} else {
    Write-Output "ERROR: Could not find DataSection pattern"
}
