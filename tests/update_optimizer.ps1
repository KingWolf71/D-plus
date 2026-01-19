$filePath = 'd:\OneDrive\WIP\Sources\Intense.2020\D+AI\c2-optimizer-V02.pbi'
$content = Get-Content $filePath -Raw

# Fix lines 766-790: PLFETCH+PLSTORE -> PMOV with j-field encoding
$old1 = '         ;- V1.033.41: PLFETCH (pointer) followed by PLSTORE → LLPMOV
         Case #ljPLFETCH
            srcOffset = llObjects()\i
            *lfetchInstr = @llObjects()
            savedIdx = ListIndex(llObjects())
            If NextElement(llObjects())
               ; Skip NOOPs
               While llObjects()\code = #ljNOOP
                  If Not NextElement(llObjects())
                     Break
                  EndIf
               Wend
               If llObjects()\code = #ljPLSTORE
                  dstOffset = llObjects()\i
                  If srcOffset <> dstOffset
                     llObjects()\code = #ljLLPMOV
                     llObjects()\i = dstOffset
                     llObjects()\j = srcOffset
                     ChangeCurrentElement(llObjects(), *lfetchInstr)
                     llObjects()\code = #ljNOOP
                     llmovCount + 1
                  EndIf
               EndIf
               SelectElement(llObjects(), savedIdx)
            EndIf'
$new1 = '         ;- V1.034.21: PFETCH(j=1)+PSTORE(j=1) -> PMOV(n=3) for local-to-local
         Case #ljPFETCH
            If llObjects()\j = 1   ; Only optimize local PFETCH
               srcOffset = llObjects()\i
               *lfetchInstr = @llObjects()
               savedIdx = ListIndex(llObjects())
               If NextElement(llObjects())
                  ; Skip NOOPs
                  While llObjects()\code = #ljNOOP
                     If Not NextElement(llObjects())
                        Break
                     EndIf
                  Wend
                  If llObjects()\code = #ljPSTORE And llObjects()\j = 1   ; Local PSTORE
                     dstOffset = llObjects()\i
                     If srcOffset <> dstOffset
                        ; V1.034.21: Use unified PMOV with n=3 for LL
                        llObjects()\code = #ljPMOV
                        llObjects()\n = 3   ; LL: both local
                        llObjects()\i = dstOffset
                        llObjects()\j = srcOffset
                        ChangeCurrentElement(llObjects(), *lfetchInstr)
                        llObjects()\code = #ljNOOP
                        llmovCount + 1
                     EndIf
                  EndIf
                  SelectElement(llObjects(), savedIdx)
               EndIf
            EndIf'
$content = $content.Replace($old1, $new1)

Set-Content $filePath -Value $content -NoNewline
Write-Output 'Done updating c2-optimizer-V02.pbi'
