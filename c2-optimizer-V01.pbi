; -- lexical parser to VM for a simplified C Language
; Tested in UTF8
; PBx64 v6.20
;
; Based on  https://rosettacode.org/wiki/Compiler/lexical_analyzer
; And
; https://rosettacode.org/wiki/Compiler/syntax_analyzer
; Distribute and use freely
;
; Kingwolf71 May/2025
;
;
;  Compiler - Optimizer
;- Peephole optimizations and instruction fusion
;- Split from c2-postprocessor-V08.pbi
;
; V1.033.0: Initial version - consolidated optimization passes
;           - Peephole optimizations (single pass)
;           - Instruction fusion (array index/value folding)
;           - Constant folding (int/float/string)
;           - Arithmetic identities
;           - Compound assignment optimization
;           - Preload optimization
;           - PUSH_IMM conversion (must be last)
;
; V1.033.6: Extended peephole optimizations (Pass 2a)
;           - Jump to next instruction elimination
;           - Conditional jump on constant (JZ with known value)
;           - Double negation (NOT NOT → identity)
;           - Double negate (NEGATE NEGATE → identity)
;           - Compare with zero optimization (x == 0 → !x)
;           - Comparison + NOT → flipped comparison (LT+NOT → GE, etc.)

; Helper to adjust jump offsets when NOOP is created
Procedure AdjustJumpsForNOOP(noopPos.i)
   ; V1.020.094: DISABLED - Pass 26's pointer-based recalculation is correct and sufficient
   ; This incremental adjustment doesn't work because srcPos/targetPos don't update as NOOPs are created
   ProcedureReturn
EndProcedure

Procedure Optimizer()
   Protected n.i, i.i
   Protected fetchVar.i
   Protected opCode.i
   Protected const1.i, const2.i, const2Idx.i
   Protected result.i
   Protected canFold.i
   Protected mulConst.i
   Protected newConstIdx.i
   Protected strIdx.i, str2Idx.i, newStrIdx.i
   Protected str1.s, str2.s, combinedStr.s
   Protected const1f.d, const2f.d, const2fIdx.i
   Protected resultf.d
   Protected newConstFIdx.i
   Protected varIdx.i
   Protected varSlot.i
   Protected valueSlot.i
   Protected stepsForward.i
   Protected savedPos
   Protected indexVarSlot.i
   Protected localOffset.i
   Protected arrayStoreIdx, valueInstrIdx
   Protected optimizationsEnabled.i
   Protected searchKey.s
   Protected currentFunctionName.s
   Protected funcId.i
   Protected funcPrefix.s
   Protected varName.s
   Protected localKey.s
   Protected localParamOffset.i
   Protected localVarName.s
   Protected removedMovCount.i

   ; Check if optimizations are enabled
   optimizationsEnabled = #True
   If FindMapElement(mapPragmas(), "optimizecode")
      If LCase(mapPragmas()) = "off" Or mapPragmas() = "0"
         optimizationsEnabled = #False
      EndIf
   EndIf

   If Not optimizationsEnabled
      CompilerIf #DEBUG
         Debug "=== Optimizer V01 DISABLED (pragma optimizecode=off) ==="
      CompilerEndIf
      ProcedureReturn
   EndIf

   CompilerIf #DEBUG
      Debug "=== Optimizer V01 Starting ==="
      Debug "    Pass 1: Instruction Fusion (Array Index/Value)"
   CompilerEndIf

   ;- ========================================
   ;- PASS 1: INSTRUCTION FUSION (Array Index/Value)
   ;- ========================================
   ; Fold PUSH index into ARRAYFETCH/ARRAYSTORE ndx field
   ; Fold PUSH value into ARRAYSTORE n field
   ForEach llObjects()
      Select llObjects()\code
         Case #ljARRAYFETCH, #ljARRAYSTORE, #ljARRAYFETCH_INT, #ljARRAYFETCH_FLOAT, #ljARRAYFETCH_STR,
              #ljARRAYSTORE_INT, #ljARRAYSTORE_FLOAT, #ljARRAYSTORE_STR
            ; ndx < 0 means index is on stack
            If llObjects()\ndx < 0
               If PreviousElement(llObjects())
                  If (llObjects()\code = #ljPush Or llObjects()\code = #ljPUSHF Or llObjects()\code = #ljPUSHS)
                     indexVarSlot = llObjects()\i
                     NextElement(llObjects())
                     llObjects()\ndx = indexVarSlot
                     PreviousElement(llObjects())
                     llObjects()\code = #ljNOOP
                     AdjustJumpsForNOOP(ListIndex(llObjects()))
                     NextElement(llObjects())
                  ElseIf (llObjects()\code = #ljLFETCH Or llObjects()\code = #ljLFETCHF Or llObjects()\code = #ljLFETCHS)
                     localOffset = llObjects()\i
                     NextElement(llObjects())
                     llObjects()\ndx = -(localOffset + 2)
                     PreviousElement(llObjects())
                     llObjects()\code = #ljNOOP
                     AdjustJumpsForNOOP(ListIndex(llObjects()))
                     NextElement(llObjects())
                  Else
                     NextElement(llObjects())
                  EndIf
               EndIf
            EndIf
      EndSelect
   Next

   ; Fold value PUSH into ARRAYSTORE
   ForEach llObjects()
      Select llObjects()\code
         Case #ljARRAYSTORE_INT, #ljARRAYSTORE_FLOAT, #ljARRAYSTORE_STR
            Protected optimized.b = #False
            arrayStoreIdx = ListIndex(llObjects())
            If PreviousElement(llObjects())
               ; Skip NOOPs from previous optimizations
               While llObjects()\code = #ljNOOP
                  If Not PreviousElement(llObjects())
                     Break
                  EndIf
               Wend
               valueInstrIdx = ListIndex(llObjects())
               If (llObjects()\code = #ljPush Or llObjects()\code = #ljPUSHF Or llObjects()\code = #ljPUSHS)
                  valueSlot = llObjects()\i
                  llObjects()\code = #ljNOOP
                  AdjustJumpsForNOOP(ListIndex(llObjects()))
                  SelectElement(llObjects(), arrayStoreIdx)
                  llObjects()\n = valueSlot
                  optimized = #True
               ElseIf (llObjects()\code = #ljLFETCH Or llObjects()\code = #ljLFETCHF Or llObjects()\code = #ljLFETCHS)
                  localOffset = llObjects()\i
                  llObjects()\code = #ljNOOP
                  AdjustJumpsForNOOP(ListIndex(llObjects()))
                  SelectElement(llObjects(), arrayStoreIdx)
                  llObjects()\n = -(localOffset + 2)
                  optimized = #True
               Else
                  SelectElement(llObjects(), arrayStoreIdx)
               EndIf
            EndIf
      EndSelect
   Next

   CompilerIf #DEBUG
      Debug "    Pass 2: Peephole Optimizations (Single Pass)"
   CompilerEndIf

   ;- ========================================
   ;- PASS 2: PEEPHOLE OPTIMIZATIONS (Single Pass)
   ;- ========================================
   ; All small-window pattern matching in one pass
   ForEach llObjects()
      Select llObjects()\code
         ;- Dead code: PUSH/FETCH + POP
         Case #ljPOP, #ljPOPS, #ljPOPF
            If PreviousElement(llObjects())
               If (llObjects()\code = #ljFetch Or llObjects()\code = #ljFETCHS Or
                   llObjects()\code = #ljFETCHF Or llObjects()\code = #ljPush Or
                   llObjects()\code = #ljPUSHS Or llObjects()\code = #ljPUSHF)
                  llObjects()\code = #ljNOOP
                  AdjustJumpsForNOOP(ListIndex(llObjects()))
                  NextElement(llObjects())
                  llObjects()\code = #ljNOOP
                  AdjustJumpsForNOOP(ListIndex(llObjects()))
               Else
                  NextElement(llObjects())
               EndIf
            EndIf

         ;- Redundant assignment: FETCH var + STORE same var
         Case #ljStore, #ljSTORES, #ljSTOREF, #ljSTORE_STRUCT
            If PreviousElement(llObjects())
               If (llObjects()\code = #ljFetch Or llObjects()\code = #ljFETCHS Or
                   llObjects()\code = #ljFETCHF)
                  fetchVar = llObjects()\i
                  NextElement(llObjects())
                  If llObjects()\i = fetchVar
                     llObjects()\code = #ljNOOP
                     AdjustJumpsForNOOP(ListIndex(llObjects()))
                     PreviousElement(llObjects())
                     llObjects()\code = #ljNOOP
                     AdjustJumpsForNOOP(ListIndex(llObjects()))
                     NextElement(llObjects())
                  EndIf
               Else
                  NextElement(llObjects())
               EndIf
            EndIf

         ;- Constant folding: PUSH const + PUSH const + OP
         Case #ljADD, #ljSUBTRACT, #ljMULTIPLY, #ljDIVIDE, #ljMOD
            opCode = llObjects()\code
            If PreviousElement(llObjects())
               If (llObjects()\code = #ljPush Or llObjects()\code = #ljPUSHF Or llObjects()\code = #ljPUSHS) And (gVarMeta(llObjects()\i)\flags & #C2FLAG_CONST)
                  const2 = gVarMeta(llObjects()\i)\valueInt
                  const2Idx = llObjects()\i
                  If PreviousElement(llObjects())
                     If (llObjects()\code = #ljPush Or llObjects()\code = #ljPUSHF Or llObjects()\code = #ljPUSHS) And (gVarMeta(llObjects()\i)\flags & #C2FLAG_CONST)
                        const1 = gVarMeta(llObjects()\i)\valueInt
                        canFold = #True
                        Select opCode
                           Case #ljADD
                              result = const1 + const2
                           Case #ljSUBTRACT
                              result = const1 - const2
                           Case #ljMULTIPLY
                              result = const1 * const2
                           Case #ljDIVIDE
                              If const2 <> 0
                                 result = const1 / const2
                              Else
                                 canFold = #False
                              EndIf
                           Case #ljMOD
                              If const2 <> 0
                                 result = const1 % const2
                              Else
                                 canFold = #False
                              EndIf
                        EndSelect
                        If canFold
                           newConstIdx = gnLastVariable
                           gVarMeta(newConstIdx)\name = "$fold" + Str(newConstIdx)
                           gVarMeta(newConstIdx)\valueInt = result
                           gVarMeta(newConstIdx)\valueFloat = 0.0
                           gVarMeta(newConstIdx)\valueString = ""
                           gVarMeta(newConstIdx)\flags = #C2FLAG_CONST | #C2FLAG_INT
                           gVarMeta(newConstIdx)\paramOffset = -1
                           gnLastVariable + 1
                           llObjects()\i = newConstIdx
                           NextElement(llObjects())
                           llObjects()\code = #ljNOOP
                           AdjustJumpsForNOOP(ListIndex(llObjects()))
                           NextElement(llObjects())
                           llObjects()\code = #ljNOOP
                           AdjustJumpsForNOOP(ListIndex(llObjects()))
                        Else
                           NextElement(llObjects())
                           NextElement(llObjects())
                        EndIf
                     Else
                        NextElement(llObjects())
                        NextElement(llObjects())
                     EndIf
                  Else
                     NextElement(llObjects())
                  EndIf
               Else
                  ; Check for identity optimizations
                  If (llObjects()\code = #ljPush Or llObjects()\code = #ljPUSHF Or llObjects()\code = #ljPUSHS) And (gVarMeta(llObjects()\i)\flags & #C2FLAG_CONST)
                     mulConst = gVarMeta(llObjects()\i)\valueInt
                     Select opCode
                        Case #ljADD, #ljSUBTRACT
                           ; x + 0 = x, x - 0 = x
                           If mulConst = 0
                              llObjects()\code = #ljNOOP
                              AdjustJumpsForNOOP(ListIndex(llObjects()))
                              NextElement(llObjects())
                              llObjects()\code = #ljNOOP
                              AdjustJumpsForNOOP(ListIndex(llObjects()))
                           Else
                              NextElement(llObjects())
                           EndIf
                        Case #ljMULTIPLY
                           ; x * 1 = x
                           If mulConst = 1
                              llObjects()\code = #ljNOOP
                              AdjustJumpsForNOOP(ListIndex(llObjects()))
                              NextElement(llObjects())
                              llObjects()\code = #ljNOOP
                              AdjustJumpsForNOOP(ListIndex(llObjects()))
                           ElseIf mulConst = 0
                              ; x * 0 = 0, eliminate x but keep PUSH 0
                              If PreviousElement(llObjects())
                                 llObjects()\code = #ljNOOP
                                 AdjustJumpsForNOOP(ListIndex(llObjects()))
                                 NextElement(llObjects())
                                 NextElement(llObjects())
                                 llObjects()\code = #ljNOOP
                                 AdjustJumpsForNOOP(ListIndex(llObjects()))
                              Else
                                 NextElement(llObjects())
                              EndIf
                           Else
                              NextElement(llObjects())
                           EndIf
                        Case #ljDIVIDE
                           ; x / 1 = x
                           If mulConst = 1
                              llObjects()\code = #ljNOOP
                              NextElement(llObjects())
                              llObjects()\code = #ljNOOP
                           Else
                              NextElement(llObjects())
                           EndIf
                        Default
                           NextElement(llObjects())
                     EndSelect
                  Else
                     NextElement(llObjects())
                  EndIf
               EndIf
            EndIf

         ;- Float constant folding
         Case #ljFLOATADD, #ljFLOATSUB, #ljFLOATMUL, #ljFLOATDIV
            opCode = llObjects()\code
            If PreviousElement(llObjects())
               If (llObjects()\code = #ljPUSHF Or llObjects()\code = #ljPush) And (gVarMeta(llObjects()\i)\flags & #C2FLAG_CONST)
                  const2fIdx = llObjects()\i
                  const2f = gVarMeta(const2fIdx)\valueFloat
                  If PreviousElement(llObjects())
                     If (llObjects()\code = #ljPUSHF Or llObjects()\code = #ljPush) And (gVarMeta(llObjects()\i)\flags & #C2FLAG_CONST)
                        const1f = gVarMeta(llObjects()\i)\valueFloat
                        canFold = #True
                        Select opCode
                           Case #ljFLOATADD
                              resultf = const1f + const2f
                           Case #ljFLOATSUB
                              resultf = const1f - const2f
                           Case #ljFLOATMUL
                              resultf = const1f * const2f
                           Case #ljFLOATDIV
                              If const2f <> 0.0
                                 resultf = const1f / const2f
                              Else
                                 canFold = #False
                              EndIf
                        EndSelect
                        If canFold
                           newConstFIdx = gnLastVariable
                           gVarMeta(newConstFIdx)\name = "$ffold" + Str(newConstFIdx)
                           gVarMeta(newConstFIdx)\valueInt = 0
                           gVarMeta(newConstFIdx)\valueFloat = resultf
                           gVarMeta(newConstFIdx)\valueString = ""
                           gVarMeta(newConstFIdx)\flags = #C2FLAG_CONST | #C2FLAG_FLOAT
                           gVarMeta(newConstFIdx)\paramOffset = -1
                           gnLastVariable + 1
                           llObjects()\i = newConstFIdx
                           NextElement(llObjects())
                           llObjects()\code = #ljNOOP
                           AdjustJumpsForNOOP(ListIndex(llObjects()))
                           NextElement(llObjects())
                           llObjects()\code = #ljNOOP
                           AdjustJumpsForNOOP(ListIndex(llObjects()))
                        Else
                           NextElement(llObjects())
                           NextElement(llObjects())
                        EndIf
                     Else
                        NextElement(llObjects())
                        NextElement(llObjects())
                     EndIf
                  Else
                     NextElement(llObjects())
                  EndIf
               Else
                  NextElement(llObjects())
               EndIf
            EndIf

         ;- String identity: str + "" = str
         Case #ljSTRADD
            If PreviousElement(llObjects())
               If llObjects()\code = #ljPUSHS Or llObjects()\code = #ljPush
                  strIdx = llObjects()\i
                  If (gVarMeta(strIdx)\flags & #C2FLAG_STR) And gVarMeta(strIdx)\valueString = ""
                     llObjects()\code = #ljNOOP
                     NextElement(llObjects())
                     llObjects()\code = #ljNOOP
                  ElseIf (gVarMeta(strIdx)\flags & #C2FLAG_CONST) And (gVarMeta(strIdx)\flags & #C2FLAG_STR)
                     ; String constant folding
                     str2 = gVarMeta(strIdx)\valueString
                     str2Idx = strIdx
                     If PreviousElement(llObjects())
                        If (llObjects()\code = #ljPUSHS Or llObjects()\code = #ljPush) And (gVarMeta(llObjects()\i)\flags & #C2FLAG_CONST)
                           str1 = gVarMeta(llObjects()\i)\valueString
                           combinedStr = str1 + str2
                           newStrIdx = gnLastVariable
                           gVarMeta(newStrIdx)\name = "$strfold" + Str(newStrIdx)
                           gVarMeta(newStrIdx)\valueInt = 0
                           gVarMeta(newStrIdx)\valueFloat = 0.0
                           gVarMeta(newStrIdx)\valueString = combinedStr
                           gVarMeta(newStrIdx)\flags = #C2FLAG_CONST | #C2FLAG_STR
                           gVarMeta(newStrIdx)\paramOffset = -1
                           gnLastVariable + 1
                           llObjects()\i = newStrIdx
                           NextElement(llObjects())
                           llObjects()\code = #ljNOOP
                           NextElement(llObjects())
                           llObjects()\code = #ljNOOP
                        Else
                           NextElement(llObjects())
                           NextElement(llObjects())
                        EndIf
                     Else
                        NextElement(llObjects())
                     EndIf
                  Else
                     NextElement(llObjects())
                  EndIf
               Else
                  NextElement(llObjects())
               EndIf
            EndIf

         ;- Increment/decrement + POP optimization
         Case #ljINC_VAR_PRE, #ljINC_VAR_POST
            If NextElement(llObjects())
               If llObjects()\code = #ljPOP
                  PreviousElement(llObjects())
                  llObjects()\code = #ljINC_VAR
                  NextElement(llObjects())
                  llObjects()\code = #ljNOOP
               Else
                  PreviousElement(llObjects())
               EndIf
            EndIf

         Case #ljDEC_VAR_PRE, #ljDEC_VAR_POST
            If NextElement(llObjects())
               If llObjects()\code = #ljPOP
                  PreviousElement(llObjects())
                  llObjects()\code = #ljDEC_VAR
                  NextElement(llObjects())
                  llObjects()\code = #ljNOOP
               Else
                  PreviousElement(llObjects())
               EndIf
            EndIf

         Case #ljLINC_VAR_PRE, #ljLINC_VAR_POST
            If NextElement(llObjects())
               If llObjects()\code = #ljPOP
                  PreviousElement(llObjects())
                  llObjects()\code = #ljLINC_VAR
                  NextElement(llObjects())
                  llObjects()\code = #ljNOOP
               Else
                  PreviousElement(llObjects())
               EndIf
            EndIf

         Case #ljLDEC_VAR_PRE, #ljLDEC_VAR_POST
            If NextElement(llObjects())
               If llObjects()\code = #ljPOP
                  PreviousElement(llObjects())
                  llObjects()\code = #ljLDEC_VAR
                  NextElement(llObjects())
                  llObjects()\code = #ljNOOP
               Else
                  PreviousElement(llObjects())
               EndIf
            EndIf
      EndSelect
   Next

   CompilerIf #DEBUG
      Debug "    Pass 2a: Additional Peephole Optimizations"
   CompilerEndIf

   ;- ========================================
   ;- PASS 2a: ADDITIONAL PEEPHOLE OPTIMIZATIONS
   ;- ========================================
   ; V1.033.6: Extended peephole patterns
   Protected peepholeCount.i = 0
   Protected jmpTargetIdx.i
   Protected *jmpTarget.stType
   Protected constVal.i
   Protected nextOpCode.i
   Protected shiftAmount.i
   Protected savedIdx.i
   Protected jmpOffset.i       ; V1.033.31: JMP offset for backward jump check
   Protected nextRealIdx.i     ; V1.033.31: Index of next real instruction

   ForEach llObjects()
      Select llObjects()\code
         ;- Store followed by Fetch of same var → keep store, DUP the value
         ;  Pattern: STORE var + FETCH var → can use value still on stack
         Case #ljStore, #ljSTORES, #ljSTOREF
            varSlot = llObjects()\i
            savedIdx = ListIndex(llObjects())
            If NextElement(llObjects())
               If (llObjects()\code = #ljFetch Or llObjects()\code = #ljFETCHS Or llObjects()\code = #ljFETCHF) And llObjects()\i = varSlot
                  ; We just stored, now fetching same → value is gone from stack but in var
                  ; Convert FETCH to a simple PUSH from that var (more efficient than re-reading)
                  ; Actually this is already optimal, but we can skip if immediately followed by operation
                  PreviousElement(llObjects())
               Else
                  PreviousElement(llObjects())
               EndIf
            EndIf

         ;- Jump to next instruction → NOOP
         ;  Pattern: JMP/JZ to immediately following instruction is useless
         ;  V1.033.31: CRITICAL FIX - Don't optimize backward JMPs (while loops)!
         ;  Only forward jumps (offset > 0) that land on the next instruction can be removed
         Case #ljJMP
            savedIdx = ListIndex(llObjects())
            jmpOffset = llObjects()\i  ; Jump offset (negative for backward jumps)
            ; V1.033.31: Never optimize backward jumps - these are loop constructs
            If jmpOffset >= 0
               ; Check if target is next instruction (skip NOOPs)
               If NextElement(llObjects())
                  While llObjects()\code = #ljNOOP Or llObjects()\code = #ljNOOPIF
                     If Not NextElement(llObjects())
                        Break
                     EndIf
                  Wend
                  ; Check if we ended up at the jump target (offset of 1 after skipping NOOPs)
                  nextRealIdx = ListIndex(llObjects())
                  SelectElement(llObjects(), savedIdx)
                  ; Only remove if the forward jump lands exactly on the next real instruction
                  If nextRealIdx - savedIdx = jmpOffset
                     llObjects()\code = #ljNOOP
                     peepholeCount + 1
                  EndIf
               EndIf
            Else
               ; Backward jump - do not optimize (this is a loop)
            EndIf

         ;- Conditional jump on constant → unconditional or NOOP
         ;  Pattern: PUSH_IMM 0 + JZ → always jump (JMP), PUSH_IMM non-zero + JZ → never jump (NOOP both)
         Case #ljJZ
            savedIdx = ListIndex(llObjects())
            If PreviousElement(llObjects())
               If llObjects()\code = #ljPUSH_IMM
                  constVal = llObjects()\i
                  If constVal = 0
                     ; Condition is always false, JZ always jumps
                     llObjects()\code = #ljNOOP
                     NextElement(llObjects())
                     llObjects()\code = #ljJMP  ; Convert to unconditional jump
                     peepholeCount + 1
                  Else
                     ; Condition is always true, JZ never jumps
                     llObjects()\code = #ljNOOP
                     NextElement(llObjects())
                     llObjects()\code = #ljNOOP
                     peepholeCount + 1
                  EndIf
               Else
                  NextElement(llObjects())
               EndIf
            EndIf

         ;- Double negation → NOOP
         ;  Pattern: NOT + NOT → cancel out
         Case #ljNOT
            If NextElement(llObjects())
               If llObjects()\code = #ljNOT
                  llObjects()\code = #ljNOOP
                  PreviousElement(llObjects())
                  llObjects()\code = #ljNOOP
                  peepholeCount + 1
               Else
                  PreviousElement(llObjects())
               EndIf
            EndIf

         ;- Double negate → NOOP (for integer negation)
         Case #ljNEGATE
            If NextElement(llObjects())
               If llObjects()\code = #ljNEGATE
                  llObjects()\code = #ljNOOP
                  PreviousElement(llObjects())
                  llObjects()\code = #ljNOOP
                  peepholeCount + 1
               Else
                  PreviousElement(llObjects())
               EndIf
            EndIf

         ;- Compare with zero optimization
         ;  Pattern: PUSH_IMM 0 + EQUAL → NOT (x == 0 → !x)
         Case #ljEQUAL
            If PreviousElement(llObjects())
               If llObjects()\code = #ljPUSH_IMM And llObjects()\i = 0
                  ; Comparing with 0: x == 0 is same as NOT x
                  llObjects()\code = #ljNOOP
                  NextElement(llObjects())
                  llObjects()\code = #ljNOT  ; x == 0 → !x
                  peepholeCount + 1
               Else
                  NextElement(llObjects())
               EndIf
            EndIf

         ;- Comparison followed by NOT → flip comparison
         ;  Pattern: LESS + NOT → GreaterEqual, GREATER + NOT → LESSEQUAL, etc.
         Case #ljLESS
            If NextElement(llObjects())
               If llObjects()\code = #ljNOT
                  llObjects()\code = #ljNOOP
                  PreviousElement(llObjects())
                  llObjects()\code = #ljGreaterEqual
                  peepholeCount + 1
               Else
                  PreviousElement(llObjects())
               EndIf
            EndIf

         Case #ljGREATER
            If NextElement(llObjects())
               If llObjects()\code = #ljNOT
                  llObjects()\code = #ljNOOP
                  PreviousElement(llObjects())
                  llObjects()\code = #ljLESSEQUAL
                  peepholeCount + 1
               Else
                  PreviousElement(llObjects())
               EndIf
            EndIf

         Case #ljLESSEQUAL
            If NextElement(llObjects())
               If llObjects()\code = #ljNOT
                  llObjects()\code = #ljNOOP
                  PreviousElement(llObjects())
                  llObjects()\code = #ljGREATER
                  peepholeCount + 1
               Else
                  PreviousElement(llObjects())
               EndIf
            EndIf

         Case #ljGreaterEqual
            If NextElement(llObjects())
               If llObjects()\code = #ljNOT
                  llObjects()\code = #ljNOOP
                  PreviousElement(llObjects())
                  llObjects()\code = #ljLESS
                  peepholeCount + 1
               Else
                  PreviousElement(llObjects())
               EndIf
            EndIf

      EndSelect
   Next

   CompilerIf #DEBUG
      Debug "      Applied " + Str(peepholeCount) + " additional peephole optimizations"
      Debug "    Pass 2b: LFETCH+LSTORE → LLMOV Fusion"
   CompilerEndIf

   ;- ========================================
   ;- PASS 2b: LFETCH+LSTORE → LLMOV FUSION (V1.033.14)
   ;- ========================================
   ; Convert consecutive LFETCH + LSTORE to single LLMOV (local-to-local move)
   ; Pattern: LFETCH src_offset + LSTORE dst_offset → LLMOV dst_offset, src_offset
   ; This eliminates stack operations (push/pop) for local variable assignments
   Protected llmovCount.i = 0
   Protected srcOffset.i, dstOffset.i
   Protected *lfetchInstr

   ForEach llObjects()
      Select llObjects()\code
         ;- LFETCH (int) followed by LSTORE → LLMOV
         Case #ljLFETCH
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
               If llObjects()\code = #ljLSTORE
                  dstOffset = llObjects()\i
                  ; Don't fuse if src == dst (would be self-assignment)
                  If srcOffset <> dstOffset
                     ; Convert LSTORE to LLMOV with both offsets
                     llObjects()\code = #ljLLMOV
                     llObjects()\i = dstOffset  ; destination offset
                     llObjects()\j = srcOffset  ; source offset
                     ; NOOP the LFETCH
                     ChangeCurrentElement(llObjects(), *lfetchInstr)
                     llObjects()\code = #ljNOOP
                     llmovCount + 1
                  EndIf
               EndIf
               SelectElement(llObjects(), savedIdx)
            EndIf

         ;- LFETCHS (string) followed by LSTORES → LLMOVS
         Case #ljLFETCHS
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
               If llObjects()\code = #ljLSTORES
                  dstOffset = llObjects()\i
                  If srcOffset <> dstOffset
                     llObjects()\code = #ljLLMOVS
                     llObjects()\i = dstOffset
                     llObjects()\j = srcOffset
                     ChangeCurrentElement(llObjects(), *lfetchInstr)
                     llObjects()\code = #ljNOOP
                     llmovCount + 1
                  EndIf
               EndIf
               SelectElement(llObjects(), savedIdx)
            EndIf

         ;- LFETCHF (float) followed by LSTOREF → LLMOVF
         Case #ljLFETCHF
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
               If llObjects()\code = #ljLSTOREF
                  dstOffset = llObjects()\i
                  If srcOffset <> dstOffset
                     llObjects()\code = #ljLLMOVF
                     llObjects()\i = dstOffset
                     llObjects()\j = srcOffset
                     ChangeCurrentElement(llObjects(), *lfetchInstr)
                     llObjects()\code = #ljNOOP
                     llmovCount + 1
                  EndIf
               EndIf
               SelectElement(llObjects(), savedIdx)
            EndIf

         ;- V1.033.41: PLFETCH (pointer) followed by PLSTORE → LLPMOV
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
            EndIf
      EndSelect
   Next

   CompilerIf #DEBUG
      Debug "      Fused " + Str(llmovCount) + " LFETCH+LSTORE pairs to LLMOV"
      Debug "    Pass 3: Compound Assignment Optimization"
   CompilerEndIf

   ;- ========================================
   ;- PASS 3: COMPOUND ASSIGNMENT OPTIMIZATION
   ;- ========================================
   ; Pattern: FETCH var + PUSH val + OP + STORE same_var → compound assign
   ForEach llObjects()
      If llObjects()\code = #ljFetch Or llObjects()\code = #ljFETCHF
         varSlot = llObjects()\i
         stepsForward = 0
         If NextElement(llObjects())
            stepsForward = 1
            If llObjects()\code = #ljPush Or llObjects()\code = #ljFetch Or llObjects()\code = #ljPUSHF Or llObjects()\code = #ljFETCHF
               valueSlot = llObjects()\i
               If NextElement(llObjects())
                  stepsForward = 2
                  Select llObjects()\code
                     Case #ljADD, #ljSUBTRACT, #ljMULTIPLY, #ljDIVIDE, #ljMOD, #ljFLOATADD, #ljFLOATSUB, #ljFLOATMUL, #ljFLOATDIV
                        opCode = llObjects()\code
                        If NextElement(llObjects())
                           stepsForward = 3
                           If (llObjects()\code = #ljStore Or llObjects()\code = #ljSTOREF) And llObjects()\i = varSlot
                              PreviousElement(llObjects())
                              PreviousElement(llObjects())
                              PreviousElement(llObjects())
                              llObjects()\code = #ljNOOP
                              NextElement(llObjects())
                              NextElement(llObjects())
                              Select opCode
                                 Case #ljADD
                                    llObjects()\code = #ljADD_ASSIGN_VAR
                                 Case #ljSUBTRACT
                                    llObjects()\code = #ljSUB_ASSIGN_VAR
                                 Case #ljMULTIPLY
                                    llObjects()\code = #ljMUL_ASSIGN_VAR
                                 Case #ljDIVIDE
                                    llObjects()\code = #ljDIV_ASSIGN_VAR
                                 Case #ljMOD
                                    llObjects()\code = #ljMOD_ASSIGN_VAR
                                 Case #ljFLOATADD
                                    llObjects()\code = #ljFLOATADD_ASSIGN_VAR
                                 Case #ljFLOATSUB
                                    llObjects()\code = #ljFLOATSUB_ASSIGN_VAR
                                 Case #ljFLOATMUL
                                    llObjects()\code = #ljFLOATMUL_ASSIGN_VAR
                                 Case #ljFLOATDIV
                                    llObjects()\code = #ljFLOATDIV_ASSIGN_VAR
                              EndSelect
                              llObjects()\i = varSlot
                              NextElement(llObjects())
                              llObjects()\code = #ljNOOP
                           Else
                              For i = 1 To stepsForward
                                 PreviousElement(llObjects())
                              Next
                           EndIf
                        Else
                           For i = 1 To stepsForward
                              PreviousElement(llObjects())
                           Next
                        EndIf
                     Default
                        For i = 1 To stepsForward
                           PreviousElement(llObjects())
                        Next
                  EndSelect
               Else
                  For i = 1 To stepsForward
                     PreviousElement(llObjects())
                  Next
               EndIf
            Else
               For i = 1 To stepsForward
                  PreviousElement(llObjects())
               Next
            EndIf
         Else
            For i = 1 To stepsForward
               PreviousElement(llObjects())
            Next
         EndIf
      EndIf
   Next

   ; Convert pointer compound assignments to typed variants
   ForEach llObjects()
      Select llObjects()\code
         Case #ljADD_ASSIGN_VAR
            varSlot = llObjects()\i
            If varSlot >= 0 And varSlot < gnLastVariable
               searchKey = gVarMeta(varSlot)\name
               If FindMapElement(mapVariableTypes(), searchKey)
                  If mapVariableTypes() & #C2FLAG_POINTER
                     If mapVariableTypes() & #C2FLAG_ARRAYPTR
                        llObjects()\code = #ljPTRADD_ASSIGN_ARRAY
                     ElseIf mapVariableTypes() & #C2FLAG_STR
                        llObjects()\code = #ljPTRADD_ASSIGN_STRING
                     ElseIf mapVariableTypes() & #C2FLAG_FLOAT
                        llObjects()\code = #ljPTRADD_ASSIGN_FLOAT
                     Else
                        llObjects()\code = #ljPTRADD_ASSIGN_INT
                     EndIf
                  EndIf
               EndIf
            EndIf

         Case #ljSUB_ASSIGN_VAR
            varSlot = llObjects()\i
            If varSlot >= 0 And varSlot < gnLastVariable
               searchKey = gVarMeta(varSlot)\name
               If FindMapElement(mapVariableTypes(), searchKey)
                  If mapVariableTypes() & #C2FLAG_POINTER
                     If mapVariableTypes() & #C2FLAG_ARRAYPTR
                        llObjects()\code = #ljPTRSUB_ASSIGN_ARRAY
                     ElseIf mapVariableTypes() & #C2FLAG_STR
                        llObjects()\code = #ljPTRSUB_ASSIGN_STRING
                     ElseIf mapVariableTypes() & #C2FLAG_FLOAT
                        llObjects()\code = #ljPTRSUB_ASSIGN_FLOAT
                     Else
                        llObjects()\code = #ljPTRSUB_ASSIGN_INT
                     EndIf
                  EndIf
               EndIf
            EndIf
      EndSelect
   Next

   CompilerIf #DEBUG
      Debug "    Pass 4: Preload Optimization"
   CompilerEndIf

   ;- ========================================
   ;- PASS 4: PRELOAD OPTIMIZATION
   ;- ========================================
   ; Remove MOV/LMOV for preloadable variables (value comes from template)
   NewMap removedGlobalInits.i()
   currentFunctionName = ""
   NewMap removedLocalInits.i()
   Protected localOptimizationEnabled.b = #False
   Protected globalOptimizationEnabled.b = #True
   Protected dstVar.i, srcVar.i

   removedMovCount = 0
   ForEach llObjects()
      If llObjects()\code = #ljFUNCTION
         funcId = llObjects()\i
         currentFunctionName = ""
         ForEach mapModules()
            If mapModules()\function = funcId
               currentFunctionName = MapKey(mapModules())
               Break
            EndIf
         Next
         ClearMap(removedLocalInits())
         localOptimizationEnabled = #True
      EndIf

      ; Disable optimization after control flow
      Select llObjects()\code
         Case #ljJMP, #ljJZ, #ljCall, #ljreturn, #ljreturnF, #ljreturnS
            localOptimizationEnabled = #False
            globalOptimizationEnabled = #False
      EndSelect

      Select llObjects()\code
         Case #ljMOV, #ljMOVF, #ljMOVS
            If globalOptimizationEnabled
               dstVar = llObjects()\i
               srcVar = llObjects()\j
               If dstVar >= 0 And dstVar < gnLastVariable
                  If (gVarMeta(dstVar)\flags & #C2FLAG_PRELOAD) And (gVarMeta(srcVar)\flags & #C2FLAG_CONST) And Not (gVarMeta(dstVar)\flags & #C2FLAG_CONST) And gVarMeta(dstVar)\paramOffset = -1
                     If Not removedGlobalInits(Str(dstVar))
                        llObjects()\code = #ljNOOP
                        removedGlobalInits(Str(dstVar)) = #True
                        removedMovCount + 1
                        SetInfo("Global '" + gVarMeta(dstVar)\name + "' preloaded from template")
                     EndIf
                  EndIf
               EndIf
            EndIf

         Case #ljLMOV, #ljLMOVF, #ljLMOVS
            If localOptimizationEnabled
               srcVar = llObjects()\j
               localParamOffset = llObjects()\i
               If srcVar >= 0 And srcVar < gnLastVariable
                  If gVarMeta(srcVar)\flags & #C2FLAG_CONST
                     localKey = Str(localParamOffset)
                     If Not removedLocalInits(localKey)
                        llObjects()\code = #ljNOOP
                        removedLocalInits(localKey) = #True
                        removedMovCount + 1
                        localVarName = ""
                        If currentFunctionName <> ""
                           funcPrefix = currentFunctionName + "_"
                           For varIdx = 0 To gnLastVariable - 1
                              If gVarMeta(varIdx)\paramOffset = localParamOffset
                                 varName = gVarMeta(varIdx)\name
                                 If Left(LCase(varName), Len(funcPrefix)) = LCase(funcPrefix)
                                    localVarName = Mid(varName, Len(funcPrefix) + 1)
                                    Break
                                 EndIf
                              EndIf
                           Next
                        EndIf
                        If localVarName <> ""
                           SetInfo("Local '" + localVarName + "' in " + currentFunctionName + "() preloaded from template")
                        Else
                           SetInfo("Local [slot " + Str(localParamOffset) + "] in " + currentFunctionName + "() preloaded from template")
                        EndIf
                     EndIf
                  EndIf
               EndIf
            EndIf
      EndSelect
   Next

   FreeMap(removedGlobalInits())
   FreeMap(removedLocalInits())

   If removedMovCount > 0
      SetInfo("Preload optimization: " + Str(removedMovCount) + " MOV/LMOV instructions replaced by templates")
   EndIf

   CompilerIf #DEBUG
      Debug "    Pass 5: PUSH_IMM Conversion (MUST BE LAST)"
   CompilerEndIf

   ;- ========================================
   ;- PASS 5: PUSH_IMM CONVERSION (MUST BE LAST)
   ;- ========================================
   ; Convert PUSH of integer constants to PUSH_IMM with actual value
   ; This must be the LAST optimization pass because it changes operand meaning
   Protected pushImmCount.i = 0
   Protected pushSlot.i
   ForEach llObjects()
      If llObjects()\code = #ljPush
         pushSlot = llObjects()\i
         If pushSlot >= 0 And pushSlot < gnLastVariable
            If gVarMeta(pushSlot)\flags & #C2FLAG_CONST And gVarMeta(pushSlot)\flags & #C2FLAG_INT
               If Not (gVarMeta(pushSlot)\flags & (#C2FLAG_STR | #C2FLAG_FLOAT))
                  llObjects()\code = #ljPUSH_IMM
                  llObjects()\i = gVarMeta(pushSlot)\valueInt
                  pushImmCount + 1
               EndIf
            EndIf
         EndIf
      EndIf
   Next

   CompilerIf #DEBUG
      Debug "      Converted " + Str(pushImmCount) + " PUSH to PUSH_IMM"
      Debug "=== Optimizer V01 Complete ==="
   CompilerEndIf

EndProcedure

; IDE Options = PureBasic 6.21 (Windows - x64)
; EnableThread
; EnableXP
; CPU = 1
