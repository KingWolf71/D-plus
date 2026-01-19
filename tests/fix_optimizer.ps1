$f = 'd:\OneDrive\WIP\Sources\Intense.2020\D+AI\c2-optimizer-V02.pbi'
$c = Get-Content $f -Raw

# Simple replacement of L-variant opcodes
$c = $c.Replace('#ljPLFETCH', '#ljPFETCH')
$c = $c.Replace('#ljPLSTORE', '#ljPSTORE')
$c = $c.Replace('#ljLLPMOV', '#ljPMOV')

# Update comments
$c = $c.Replace('V1.033.41: PLFETCH (pointer) followed by PLSTORE', 'V1.034.21: PFETCH(j=1) followed by PSTORE(j=1)')

Set-Content $f -Value $c -NoNewline
Write-Output 'Done fixing optimizer'
