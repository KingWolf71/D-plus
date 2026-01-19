$f = 'd:\OneDrive\WIP\Sources\Intense.2020\D+AI\c2-inc-v17.pbi'
$c = Get-Content $f -Raw

# Restore LLPMOV placeholder to maintain enum order
$c = $c.Replace('   ; V1.034.21: #ljLLPMOV removed - use #ljPMOV with n=3

   ;- In-place increment/decrement opcodes', '   #ljLLPMOV_DEPRECATED     ; V1.034.21: Deprecated - use #ljPMOV with n=3

   ;- In-place increment/decrement opcodes')

# Restore PLFETCH, PLSTORE, PLMOV placeholders to maintain enum order
$c = $c.Replace('   #ljPPOP                ; Pointer-only POP (always copies ptr/ptrtype)
   ; V1.034.21: PLFETCH, PLSTORE, PLMOV removed - use unified PFETCH/PSTORE/PMOV with j=1

   ;- Cast Operators', '   #ljPPOP                ; Pointer-only POP (always copies ptr/ptrtype)
   #ljPLFETCH_DEPRECATED      ; V1.034.21: Deprecated - use #ljPFETCH with j=1
   #ljPLSTORE_DEPRECATED      ; V1.034.21: Deprecated - use #ljPSTORE with j=1
   #ljPLMOV_DEPRECATED        ; V1.034.21: Deprecated - use #ljPMOV with n field

   ;- Cast Operators')

Set-Content $f -Value $c -NoNewline
Write-Output 'Done fixing c2-inc-v17 enum placeholders'

# Same for c2-inc-v18
$f2 = 'd:\OneDrive\WIP\Sources\Intense.2020\D+AI\c2-inc-v18.pbi'
if (Test-Path $f2) {
    $c2 = Get-Content $f2 -Raw
    $c2 = $c2.Replace('   ; V1.034.21: #ljLLPMOV removed - use #ljPMOV with n=3

   ;- In-place increment/decrement opcodes', '   #ljLLPMOV_DEPRECATED     ; V1.034.21: Deprecated - use #ljPMOV with n=3

   ;- In-place increment/decrement opcodes')
    $c2 = $c2.Replace('   #ljPPOP                ; Pointer-only POP (always copies ptr/ptrtype)
   ; V1.034.21: PLFETCH, PLSTORE, PLMOV removed - use unified PFETCH/PSTORE/PMOV with j=1

   ;- Cast Operators', '   #ljPPOP                ; Pointer-only POP (always copies ptr/ptrtype)
   #ljPLFETCH_DEPRECATED      ; V1.034.21: Deprecated - use #ljPFETCH with j=1
   #ljPLSTORE_DEPRECATED      ; V1.034.21: Deprecated - use #ljPSTORE with j=1
   #ljPLMOV_DEPRECATED        ; V1.034.21: Deprecated - use #ljPMOV with n field

   ;- Cast Operators')
    Set-Content $f2 -Value $c2 -NoNewline
    Write-Output 'Done fixing c2-inc-v18 enum placeholders'
}
