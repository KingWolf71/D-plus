$filePath = 'd:\OneDrive\WIP\Sources\Intense.2020\D+AI\c2-typeinfer-V02.pbi'
$content = Get-Content $filePath -Raw

# Fix line 237-240: MOV -> PMOV conversion with n-field encoding
$old1 = '                  ; Convert MOV to PMOV variants to preserve pointer metadata
                  Select llObjects()\code
                     Case #ljMOV
                        llObjects()\code = #ljPMOV
                     Case #ljLMOV
                        llObjects()\code = #ljPLMOV
                     Case #ljLLMOV
                        llObjects()\code = #ljLLPMOV
                  EndSelect'
$new1 = '                  ; V1.034.21: Convert MOV to unified PMOV with n-field encoding
                  ; n-field: n & 1 = source is local, n >> 1 = dest is local
                  Select llObjects()\code
                     Case #ljMOV
                        llObjects()\code = #ljPMOV
                        ; n already 0 for GG
                     Case #ljLMOV
                        llObjects()\code = #ljPMOV
                        llObjects()\n = 2   ; GL: dest is local
                     Case #ljLLMOV
                        llObjects()\code = #ljPMOV
                        llObjects()\n = 3   ; LL: both local
                  EndSelect'
$content = $content.Replace($old1, $new1)

# Fix line 249: Check for unified PFETCH with j=1 instead of PLFETCH
$old2 = 'If llObjects()\code = #ljFetch Or llObjects()\code = #ljPFETCH Or llObjects()\code = #ljLFETCH Or llObjects()\code = #ljPLFETCH'
$new2 = 'If llObjects()\code = #ljFetch Or llObjects()\code = #ljPFETCH Or llObjects()\code = #ljLFETCH'
$content = $content.Replace($old2, $new2)

# Fix line 289: Check for PFETCH with j=1 or LFETCH instead of PLFETCH
$old3 = 'If llObjects()\code = #ljPLFETCH Or llObjects()\code = #ljLFETCH'
$new3 = 'If (llObjects()\code = #ljPFETCH And llObjects()\j = 1) Or llObjects()\code = #ljLFETCH'
$content = $content.Replace($old3, $new3)

# Fix line 508: LLMOV -> PMOV n=3
$old4 = '            If mapVariableTypes() & #C2FLAG_POINTER
               llObjects()\code = #ljLLPMOV
            EndIf'
$new4 = '            If mapVariableTypes() & #C2FLAG_POINTER
               ; V1.034.21: Use unified PMOV with n=3 for LL
               llObjects()\code = #ljPMOV
               llObjects()\n = 3
            EndIf'
$content = $content.Replace($old4, $new4)

# Fix line 650: LFETCH -> PFETCH j=1
$old5 = '            ; V1.033.35: If next opcode is pointer op, convert to PLFETCH
            If isPointer
               llObjects()\code = #ljPLFETCH'
$new5 = '            ; V1.034.21: If next opcode is pointer op, convert to unified PFETCH with j=1
            If isPointer
               llObjects()\code = #ljPFETCH
               llObjects()\j = 1   ; local'
$content = $content.Replace($old5, $new5)

# Fix line 658: Map-based LFETCH -> PFETCH j=1
$old6 = '                  If FindMapElement(mapVariableTypes(), searchKey)
                     If mapVariableTypes() & #C2FLAG_POINTER
                        llObjects()\code = #ljPLFETCH
                     EndIf
                  EndIf'
$new6 = '                  If FindMapElement(mapVariableTypes(), searchKey)
                     If mapVariableTypes() & #C2FLAG_POINTER
                        ; V1.034.21: Use unified PFETCH with j=1 for local
                        llObjects()\code = #ljPFETCH
                        llObjects()\j = 1
                     EndIf
                  EndIf'
$content = $content.Replace($old6, $new6)

# Fix line 674: LSTORE -> PSTORE j=1
$old7 = '               If FindMapElement(mapVariableTypes(), searchKey)
                  If mapVariableTypes() & #C2FLAG_POINTER
                     llObjects()\code = #ljPLSTORE
                  EndIf
               EndIf'
$new7 = '               If FindMapElement(mapVariableTypes(), searchKey)
                  If mapVariableTypes() & #C2FLAG_POINTER
                     ; V1.034.21: Use unified PSTORE with j=1 for local
                     llObjects()\code = #ljPSTORE
                     llObjects()\j = 1
                  EndIf
               EndIf'
$content = $content.Replace($old7, $new7)

# Fix line 1212: Remove PLFETCH from checks
$old8 = 'If llObjects()\code = #ljFetch Or llObjects()\code = #ljFETCHF Or llObjects()\code = #ljFETCHS Or llObjects()\code = #ljLFETCH Or llObjects()\code = #ljLFETCHF Or llObjects()\code = #ljLFETCHS Or llObjects()\code = #ljPFETCH Or llObjects()\code = #ljPLFETCH'
$new8 = 'If llObjects()\code = #ljFetch Or llObjects()\code = #ljFETCHF Or llObjects()\code = #ljFETCHS Or llObjects()\code = #ljLFETCH Or llObjects()\code = #ljLFETCHF Or llObjects()\code = #ljLFETCHS Or llObjects()\code = #ljPFETCH'
$content = $content.Replace($old8, $new8)

# Fix line 1221: Remove PLSTORE from checks
$old9 = 'If (llObjects()\code = #ljStore Or llObjects()\code = #ljPOP Or llObjects()\code = #ljLSTORE Or llObjects()\code = #ljPSTORE Or llObjects()\code = #ljPLSTORE) And llObjects()\i = varSlot'
$new9 = 'If (llObjects()\code = #ljStore Or llObjects()\code = #ljPOP Or llObjects()\code = #ljLSTORE Or llObjects()\code = #ljPSTORE) And llObjects()\i = varSlot'
$content = $content.Replace($old9, $new9)

Set-Content $filePath -Value $content -NoNewline
Write-Output 'Done updating c2-typeinfer-V02.pbi'
