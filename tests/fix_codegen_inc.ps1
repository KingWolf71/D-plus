$f1 = 'd:\OneDrive\WIP\Sources\Intense.2020\D+AI\c2-codegen-v07.pbi'
$c1 = Get-Content $f1 -Raw

# Fix line 944: Remove PLSTORE and PLFETCH from the list since they're no longer used
$c1 = $c1.Replace('#ljLMOV, #ljLMOVS, #ljLMOVF, #ljPLSTORE, #ljPMOV, #ljPLFETCH', '#ljLMOV, #ljLMOVS, #ljLMOVF, #ljPMOV')
$c1 = $c1.Replace('; V1.023.23: Added pointer-preserving local opcodes (PLSTORE, PLMOV, PLFETCH) - also use paramOffset', '; V1.034.21: PMOV uses j/n fields for locality instead of separate local opcodes')

Set-Content $f1 -Value $c1 -NoNewline
Write-Output 'Done fixing codegen'

# Now fix the inc files
$f2 = 'd:\OneDrive\WIP\Sources\Intense.2020\D+AI\c2-inc-v17.pbi'
$c2 = Get-Content $f2 -Raw

# Remove LLPMOV, PLFETCH, PLSTORE, PLMOV opcode definitions
$c2 = $c2.Replace('   #ljLLPMOV     ; LL PMOV: pointer variant (copies i, ptr, ptrtype)
', '   ; V1.034.21: #ljLLPMOV removed - use #ljPMOV with n=3
')
$c2 = $c2.Replace('   #ljPLFETCH             ; Pointer-only local FETCH (always copies ptr/ptrtype)
   #ljPLSTORE             ; Pointer-only local STORE (always copies ptr/ptrtype)
   #ljPLMOV               ; Pointer-only local MOV (always copies ptr/ptrtype)
', '   ; V1.034.21: PLFETCH, PLSTORE, PLMOV removed - use unified PFETCH/PSTORE/PMOV with j=1
')

# Fix the helper that checks for local store
$c2 = $c2.Replace('ElseIf obj\code = #ljLSTORE Or obj\code = #ljLSTORES Or obj\code = #ljLSTOREF Or obj\code = #ljPLSTORE', 'ElseIf obj\code = #ljLSTORE Or obj\code = #ljLSTORES Or obj\code = #ljLSTOREF Or (obj\code = #ljPSTORE And obj\j = 1)')

Set-Content $f2 -Value $c2 -NoNewline
Write-Output 'Done fixing c2-inc-v17'

# Also update c2-inc-v18 if it exists
$f3 = 'd:\OneDrive\WIP\Sources\Intense.2020\D+AI\c2-inc-v18.pbi'
if (Test-Path $f3) {
    $c3 = Get-Content $f3 -Raw
    $c3 = $c3.Replace('   #ljLLPMOV     ; LL PMOV: pointer variant (copies i, ptr, ptrtype)
', '   ; V1.034.21: #ljLLPMOV removed - use #ljPMOV with n=3
')
    $c3 = $c3.Replace('   #ljPLFETCH             ; Pointer-only local FETCH (always copies ptr/ptrtype)
   #ljPLSTORE             ; Pointer-only local STORE (always copies ptr/ptrtype)
   #ljPLMOV               ; Pointer-only local MOV (always copies ptr/ptrtype)
', '   ; V1.034.21: PLFETCH, PLSTORE, PLMOV removed - use unified PFETCH/PSTORE/PMOV with j=1
')
    $c3 = $c3.Replace('ElseIf obj\code = #ljLSTORE Or obj\code = #ljLSTORES Or obj\code = #ljLSTOREF Or obj\code = #ljPLSTORE', 'ElseIf obj\code = #ljLSTORE Or obj\code = #ljLSTORES Or obj\code = #ljLSTOREF Or (obj\code = #ljPSTORE And obj\j = 1)')
    Set-Content $f3 -Value $c3 -NoNewline
    Write-Output 'Done fixing c2-inc-v18'
}
