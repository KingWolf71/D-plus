$f = 'd:\OneDrive\WIP\Sources\Intense.2020\D+AI\c2-optimizer-V02.pbi'
$c = Get-Content $f -Raw

# Replace the entire optimization block
$oldBlock = @'
         ;- V1.034.21: PFETCH(j=1) followed by PSTORE(j=1) → LLPMOV
         Case #ljPFETCH
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
               If llObjects()\code = #ljPSTORE
                  dstOffset = llObjects()\i
                  If srcOffset <> dstOffset
                     llObjects()\code = #ljPMOV
                     llObjects()\i = dstOffset
                     llObjects()\j = srcOffset
                     ChangeCurrentElement(llObjects(), *lfetchInstr)
                     llObjects()\code = #ljNOOP
                     llmovCount + 1
                  EndIf
               EndIf
               SelectElement(llObjects(), savedIdx)
            EndIf
'@

$newBlock = @'
         ;- V1.034.21: PFETCH(j=1) followed by PSTORE(j=1) -> PMOV(n=3) for LL
         Case #ljPFETCH
            If llObjects()\j = 1   ; Only local PFETCH
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
            EndIf
'@

$c = $c.Replace($oldBlock, $newBlock)

Set-Content $f -Value $c -NoNewline
Write-Output 'Done fixing optimizer with j=1 checks and n=3'
