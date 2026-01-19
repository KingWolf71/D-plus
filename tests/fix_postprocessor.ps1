$f = 'd:\OneDrive\WIP\Sources\Intense.2020\D+AI\c2-postprocessor-V11.pbi'
$c = Get-Content $f -Raw

# Replace PLFETCH checks with PFETCH j=1 checks
# Line 588: Or llObjects()\code = #ljPLFETCH
$c = $c.Replace('Or llObjects()\code = #ljPFETCH Or llObjects()\code = #ljPLFETCH', 'Or llObjects()\code = #ljPFETCH')

# Line 590: If llObjects()\code = #ljLFETCH Or llObjects()\code = #ljPLFETCH
$c = $c.Replace('If llObjects()\code = #ljLFETCH Or llObjects()\code = #ljPLFETCH', 'If llObjects()\code = #ljLFETCH Or (llObjects()\code = #ljPFETCH And llObjects()\j = 1)')

# Line 717-719: Same pattern
# Already handled by above replacement

Set-Content $f -Value $c -NoNewline
Write-Output 'Done fixing postprocessor'
