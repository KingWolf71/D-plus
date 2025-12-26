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
;  Compiler - Optimizer V02
;- Peephole optimizations and instruction fusion
;- Split from c2-postprocessor-V08.pbi
;
; V1.033.0: Initial version - consolidated optimization passes
; V1.033.6: Extended peephole optimizations
; V1.034.80: Consolidated pass framework
;            - Pass 1: Array instruction fusion
;            - Pass 2: Unified peephole optimizations (merged 2/2a/2b/2c)
;            - Pass 3: Compound assignment optimization
;            - Pass 4: Preload optimization
;            - Pass 5: PUSH_IMM conversion (must be last)
; V1.035.3: Rule-based peephole optimization
;            - Uses lookup tables from c2-codegen-rules.pbi
;            - IsDeadCodeOpcode(), GetFlippedCompare(), IsIdentityOp()
;            - GetFetchStoreFusion(), GetCompoundAssignOpcode()
; V1.035.5: New optimizations
;            - FETCH x + FETCH x → FETCH x + DUP (for x*x squared patterns)
;            - PUSH_IMM + NEGATE → negative constant folding at compile time
;            - Saves memory reads and instruction count in tight loops
; V1.035.16: Comparison-Jump fusion (Pass 6)
;            - FETCH + PUSH_IMM + LESS/GREATER/etc + JZ → JGE_VAR_IMM etc
;            - Fuses 4 instructions into 1 for loop conditions
;            - Supports both global (VAR) and local (LVAR) variables
;            - Removed #pragma optimizecode check (always optimize)
;            - Pass 6 runs AFTER PUSH_IMM conversion (Pass 5)

; Helper to adjust jump offsets when NOOP is created
Procedure AdjustJumpsForNOOP(noopPos.i)
   ; V1.020.094: DISABLED - Pass 26's pointer-based recalculation is correct and sufficient
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
   Protected savedPos, savedIdx.i
   Protected indexVarSlot.i
   Protected localOffset.i
   Protected arrayStoreIdx, valueInstrIdx
   ; V1.035.16: Removed optimizationsEnabled - always optimize
   Protected searchKey.s
   Protected currentFunctionName.s
   Protected funcId.i
   Protected funcPrefix.s
   Protected varName.s
   Protected localKey.s
   Protected localParamOffset.i
   Protected localVarName.s
   Protected removedMovCount.i

   ; Pass 2 variables (unified peephole)
   Protected peepholeCount.i, movFusionCount.i
   Protected fetchSlot.i, fetchJ.i, storeSlot.i, storeJ.i, movN.i
   Protected srcOffset.i, dstOffset.i
   Protected *fetchInstr, *lfetchInstr
   Protected jmpOffset.i, nextRealIdx.i, constVal.i

   ; V1.035.16: Optimizer always enabled (removed pragma optimizecode check)
   ; V1.035.3: Initialize rule-based optimization tables
   InitAllOptimizationRules()

   CompilerIf #DEBUG
      Debug "=== Optimizer V03 Starting (rule-based) ==="
      Debug "    Pass 1: Array Instruction Fusion"
   CompilerEndIf

   ;- ========================================
   ;- PASS 1: ARRAY INSTRUCTION FUSION
   ;- ========================================
   ; Fold PUSH index into ARRAYFETCH/ARRAYSTORE ndx field
   ForEach llObjects()
      Select llObjects()\code
         Case #ljARRAYFETCH, #ljARRAYSTORE, #ljARRAYFETCH_INT, #ljARRAYFETCH_FLOAT, #ljARRAYFETCH_STR,
              #ljARRAYSTORE_INT, #ljARRAYSTORE_FLOAT, #ljARRAYSTORE_STR
            If llObjects()\ndx < 0
               If PreviousElement(llObjects())
                  If (llObjects()\code = #ljPush Or llObjects()\code = #ljPUSHF Or llObjects()\code = #ljPUSHS)
                     indexVarSlot = llObjects()\i
                     NextElement(llObjects())
                     llObjects()\ndx = indexVarSlot
                     PreviousElement(llObjects())
                     llObjects()\code = #ljNOOP
                     NextElement(llObjects())
                  ElseIf (llObjects()\code = #ljLFETCH Or llObjects()\code = #ljLFETCHF Or llObjects()\code = #ljLFETCHS)
                     localOffset = llObjects()\i
                     NextElement(llObjects())
                     llObjects()\ndx = -(localOffset + 2)
                     PreviousElement(llObjects())
                     llObjects()\code = #ljNOOP
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
               While llObjects()\code = #ljNOOP
                  If Not PreviousElement(llObjects())
                     Break
                  EndIf
               Wend
               valueInstrIdx = ListIndex(llObjects())
               If (llObjects()\code = #ljPush Or llObjects()\code = #ljPUSHF Or llObjects()\code = #ljPUSHS)
                  valueSlot = llObjects()\i
                  llObjects()\code = #ljNOOP
                  SelectElement(llObjects(), arrayStoreIdx)
                  llObjects()\n = valueSlot
                  optimized = #True
               ElseIf (llObjects()\code = #ljLFETCH Or llObjects()\code = #ljLFETCHF Or llObjects()\code = #ljLFETCHS)
                  localOffset = llObjects()\i
                  llObjects()\code = #ljNOOP
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
      Debug "    Pass 2: Unified Peephole Optimizations"
   CompilerEndIf

   ;- ========================================
   ;- PASS 2: UNIFIED PEEPHOLE OPTIMIZATIONS (V1.034.80)
   ;- ========================================
   ; All small-window pattern matching in one pass:
   ; - Dead code elimination (PUSH+POP, FETCH var+STORE same var)
   ; - Constant folding (int, float, string)
   ; - Arithmetic identities (+0, *1, *0, /1)
   ; - FETCH+STORE → MOV fusion (all locality combinations)
   ; - STORE+FETCH same var → NOOP FETCH
   ; - Jump optimizations (JMP to next, JZ on constant)
   ; - Double negation/negate elimination
   ; - Comparison flipping (CMP + NOT → flipped CMP)
   ; - Increment/decrement + POP → simple inc/dec

   peepholeCount = 0
   movFusionCount = 0

   ForEach llObjects()
      Select llObjects()\code

         ;- ====== DEAD CODE: PUSH/FETCH + POP ======
         ; V1.035.3: Use rule-based lookup for dead code patterns
         Case #ljPOP, #ljPOPS, #ljPOPF
            If PreviousElement(llObjects())
               If IsDeadCodeOpcode(llObjects()\code)
                  llObjects()\code = #ljNOOP
                  NextElement(llObjects())
                  llObjects()\code = #ljNOOP
                  peepholeCount + 1
               Else
                  NextElement(llObjects())
               EndIf
            EndIf

         ;- ====== FETCH+STORE FUSION → MOV or FETCH+FETCH → FETCH+DUP ======
         Case #ljFetch
            fetchSlot = llObjects()\i
            fetchJ = llObjects()\j
            *fetchInstr = @llObjects()
            savedIdx = ListIndex(llObjects())
            If NextElement(llObjects())
               While llObjects()\code = #ljNOOP
                  If Not NextElement(llObjects()) : Break : EndIf
               Wend
               If llObjects()\code = #ljStore
                  storeSlot = llObjects()\i
                  storeJ = llObjects()\j
                  ; Don't fuse self-assignment
                  If Not (fetchSlot = storeSlot And fetchJ = storeJ)
                     ; n: bit0 = src local, bit1 = dst local
                     movN = fetchJ | (storeJ << 1)
                     llObjects()\code = #ljMOV
                     llObjects()\i = storeSlot
                     llObjects()\j = fetchSlot
                     llObjects()\n = movN
                     ChangeCurrentElement(llObjects(), *fetchInstr)
                     llObjects()\code = #ljNOOP
                     movFusionCount + 1
                  Else
                     ; Self-assignment: NOOP both
                     llObjects()\code = #ljNOOP
                     ChangeCurrentElement(llObjects(), *fetchInstr)
                     llObjects()\code = #ljNOOP
                     peepholeCount + 1
                  EndIf
               ElseIf llObjects()\code = #ljFetch
                  ; V1.035.5: FETCH x + FETCH x → FETCH x + DUP (for x*x patterns)
                  If llObjects()\i = fetchSlot And llObjects()\j = fetchJ
                     llObjects()\code = #ljDUP_I
                     llObjects()\i = 0
                     llObjects()\j = 0
                     peepholeCount + 1
                  EndIf
               EndIf
               SelectElement(llObjects(), savedIdx)
            EndIf

         Case #ljFETCHS
            fetchSlot = llObjects()\i
            fetchJ = llObjects()\j
            *fetchInstr = @llObjects()
            savedIdx = ListIndex(llObjects())
            If NextElement(llObjects())
               While llObjects()\code = #ljNOOP
                  If Not NextElement(llObjects()) : Break : EndIf
               Wend
               If llObjects()\code = #ljSTORES
                  storeSlot = llObjects()\i
                  storeJ = llObjects()\j
                  If Not (fetchSlot = storeSlot And fetchJ = storeJ)
                     movN = fetchJ | (storeJ << 1)
                     llObjects()\code = #ljMOVS
                     llObjects()\i = storeSlot
                     llObjects()\j = fetchSlot
                     llObjects()\n = movN
                     ChangeCurrentElement(llObjects(), *fetchInstr)
                     llObjects()\code = #ljNOOP
                     movFusionCount + 1
                  Else
                     llObjects()\code = #ljNOOP
                     ChangeCurrentElement(llObjects(), *fetchInstr)
                     llObjects()\code = #ljNOOP
                     peepholeCount + 1
                  EndIf
               ElseIf llObjects()\code = #ljFETCHS
                  ; V1.035.5: FETCHS x + FETCHS x → FETCHS x + DUP_S
                  If llObjects()\i = fetchSlot And llObjects()\j = fetchJ
                     llObjects()\code = #ljDUP_S
                     llObjects()\i = 0
                     llObjects()\j = 0
                     peepholeCount + 1
                  EndIf
               EndIf
               SelectElement(llObjects(), savedIdx)
            EndIf

         Case #ljFETCHF
            fetchSlot = llObjects()\i
            fetchJ = llObjects()\j
            *fetchInstr = @llObjects()
            savedIdx = ListIndex(llObjects())
            If NextElement(llObjects())
               While llObjects()\code = #ljNOOP
                  If Not NextElement(llObjects()) : Break : EndIf
               Wend
               If llObjects()\code = #ljSTOREF
                  storeSlot = llObjects()\i
                  storeJ = llObjects()\j
                  If Not (fetchSlot = storeSlot And fetchJ = storeJ)
                     movN = fetchJ | (storeJ << 1)
                     llObjects()\code = #ljMOVF
                     llObjects()\i = storeSlot
                     llObjects()\j = fetchSlot
                     llObjects()\n = movN
                     ChangeCurrentElement(llObjects(), *fetchInstr)
                     llObjects()\code = #ljNOOP
                     movFusionCount + 1
                  Else
                     llObjects()\code = #ljNOOP
                     ChangeCurrentElement(llObjects(), *fetchInstr)
                     llObjects()\code = #ljNOOP
                     peepholeCount + 1
                  EndIf
               ElseIf llObjects()\code = #ljFETCHF
                  ; V1.035.5: FETCHF x + FETCHF x → FETCHF x + DUP_F (for x*x patterns with floats)
                  If llObjects()\i = fetchSlot And llObjects()\j = fetchJ
                     llObjects()\code = #ljDUP_F
                     llObjects()\i = 0
                     llObjects()\j = 0
                     peepholeCount + 1
                  EndIf
               EndIf
               SelectElement(llObjects(), savedIdx)
            EndIf

         ;- ====== STORE+FETCH SAME VAR → NOOP FETCH ======
         Case #ljStore, #ljSTORES, #ljSTOREF, #ljSTORE_STRUCT
            storeSlot = llObjects()\i
            storeJ = llObjects()\j
            savedIdx = ListIndex(llObjects())
            If NextElement(llObjects())
               While llObjects()\code = #ljNOOP
                  If Not NextElement(llObjects()) : Break : EndIf
               Wend
               ; Check for matching FETCH
               If (llObjects()\code = #ljFetch Or llObjects()\code = #ljFETCHS Or llObjects()\code = #ljFETCHF)
                  If llObjects()\i = storeSlot And llObjects()\j = storeJ
                     ; Redundant FETCH - value was just stored, still on stack concept
                     ; But STORE pops, so we need DUP before STORE for this optimization
                     ; For now just mark as detected; true optimization needs codegen change
                     ; Actually we CAN optimize: just NOOP the FETCH if we had DUP support
                     ; Skip for now - needs more careful analysis
                  EndIf
               EndIf
               SelectElement(llObjects(), savedIdx)
            EndIf

         ;- ====== CONSTANT FOLDING: INT ======
         Case #ljADD, #ljSUBTRACT, #ljMULTIPLY, #ljDIVIDE, #ljMOD, #ljSHL, #ljSHR
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
                           Case #ljADD : result = const1 + const2
                           Case #ljSUBTRACT : result = const1 - const2
                           Case #ljMULTIPLY : result = const1 * const2
                           Case #ljDIVIDE
                              If const2 <> 0 : result = const1 / const2 : Else : canFold = #False : EndIf
                           Case #ljMOD
                              If const2 <> 0 : result = const1 % const2 : Else : canFold = #False : EndIf
                           Case #ljSHL : result = const1 << const2
                           Case #ljSHR : result = const1 >> const2
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
                           NextElement(llObjects())
                           llObjects()\code = #ljNOOP
                           peepholeCount + 1
                        Else
                           NextElement(llObjects()) : NextElement(llObjects())
                        EndIf
                     Else
                        NextElement(llObjects()) : NextElement(llObjects())
                     EndIf
                  Else
                     NextElement(llObjects())
                  EndIf
               Else
                  ; V1.035.3: Use rule-based identity optimization lookup
                  ; Check for identity optimizations: +0, -0, *1, /1, *0
                  If (llObjects()\code = #ljPush Or llObjects()\code = #ljPUSHF Or llObjects()\code = #ljPUSHS) And (gVarMeta(llObjects()\i)\flags & #C2FLAG_CONST)
                     mulConst = gVarMeta(llObjects()\i)\valueInt
                     If IsIdentityOp(opCode, mulConst)
                        ; Identity operation: x op identity = x (e.g., x+0, x*1, x/1)
                        llObjects()\code = #ljNOOP
                        NextElement(llObjects())
                        llObjects()\code = #ljNOOP
                        peepholeCount + 1
                     ElseIf opCode = #ljMULTIPLY And mulConst = 0
                        ; Special case: x * 0 = 0 (replace with just the constant)
                        If PreviousElement(llObjects())
                           llObjects()\code = #ljNOOP
                           NextElement(llObjects())
                           NextElement(llObjects())
                           llObjects()\code = #ljNOOP
                           peepholeCount + 1
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
            EndIf

         ;- ====== CONSTANT FOLDING: FLOAT ======
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
                           Case #ljFLOATADD : resultf = const1f + const2f
                           Case #ljFLOATSUB : resultf = const1f - const2f
                           Case #ljFLOATMUL : resultf = const1f * const2f
                           Case #ljFLOATDIV
                              If const2f <> 0.0 : resultf = const1f / const2f : Else : canFold = #False : EndIf
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
                           NextElement(llObjects())
                           llObjects()\code = #ljNOOP
                           peepholeCount + 1
                        Else
                           NextElement(llObjects()) : NextElement(llObjects())
                        EndIf
                     Else
                        NextElement(llObjects()) : NextElement(llObjects())
                     EndIf
                  Else
                     NextElement(llObjects())
                  EndIf
               Else
                  NextElement(llObjects())
               EndIf
            EndIf

         ;- ====== STRING IDENTITY: str + "" = str ======
         Case #ljSTRADD
            If PreviousElement(llObjects())
               If llObjects()\code = #ljPUSHS Or llObjects()\code = #ljPush
                  strIdx = llObjects()\i
                  If (gVarMeta(strIdx)\flags & #C2FLAG_STR) And gVarMeta(strIdx)\valueString = ""
                     llObjects()\code = #ljNOOP
                     NextElement(llObjects())
                     llObjects()\code = #ljNOOP
                     peepholeCount + 1
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
                           peepholeCount + 1
                        Else
                           NextElement(llObjects()) : NextElement(llObjects())
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

         ;- ====== INCREMENT/DECREMENT + POP/DROP → SIMPLE INC/DEC ======
         ; V1.035.3: Use rule-based opcode lookup
         Case #ljINC_VAR_PRE, #ljINC_VAR_POST, #ljDEC_VAR_PRE, #ljDEC_VAR_POST,
              #ljLINC_VAR_PRE, #ljLINC_VAR_POST, #ljLDEC_VAR_PRE, #ljLDEC_VAR_POST
            Protected incDecOp.i = llObjects()\code
            If NextElement(llObjects())
               If IsPopOpcode(llObjects()\code)
                  PreviousElement(llObjects())
                  If IsIncrementOpcode(incDecOp)
                     llObjects()\code = GetSimpleIncrementOpcode(incDecOp)
                  Else
                     llObjects()\code = GetSimpleDecrementOpcode(incDecOp)
                  EndIf
                  NextElement(llObjects())
                  llObjects()\code = #ljNOOP
                  peepholeCount + 1
               Else
                  PreviousElement(llObjects())
               EndIf
            EndIf

         ;- ====== JUMP OPTIMIZATIONS ======
         Case #ljJMP
            savedIdx = ListIndex(llObjects())
            jmpOffset = llObjects()\i
            ; Only optimize forward jumps (not loops)
            If jmpOffset >= 0
               If NextElement(llObjects())
                  While llObjects()\code = #ljNOOP Or llObjects()\code = #ljNOOPIF
                     If Not NextElement(llObjects()) : Break : EndIf
                  Wend
                  nextRealIdx = ListIndex(llObjects())
                  SelectElement(llObjects(), savedIdx)
                  If nextRealIdx - savedIdx = jmpOffset
                     llObjects()\code = #ljNOOP
                     peepholeCount + 1
                  EndIf
               EndIf
            EndIf

         Case #ljJZ
            savedIdx = ListIndex(llObjects())
            If PreviousElement(llObjects())
               If llObjects()\code = #ljPUSH_IMM
                  constVal = llObjects()\i
                  If constVal = 0
                     ; Always jumps
                     llObjects()\code = #ljNOOP
                     NextElement(llObjects())
                     llObjects()\code = #ljJMP
                     peepholeCount + 1
                  Else
                     ; Never jumps
                     llObjects()\code = #ljNOOP
                     NextElement(llObjects())
                     llObjects()\code = #ljNOOP
                     peepholeCount + 1
                  EndIf
               Else
                  NextElement(llObjects())
               EndIf
            EndIf

         ;- ====== DOUBLE NEGATION/NEGATE ======
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

         Case #ljNEGATE
            ; V1.035.5: PUSH constant + NEGATE → fold negative constant at compile time
            If PreviousElement(llObjects())
               Protected negateOpt.b = #False
               If llObjects()\code = #ljPUSH_IMM
                  ; Already converted to PUSH_IMM - fold directly
                  Protected negatedValue.i = -llObjects()\i
                  llObjects()\i = negatedValue
                  NextElement(llObjects())
                  llObjects()\code = #ljNOOP
                  peepholeCount + 1
                  negateOpt = #True
               ElseIf llObjects()\code = #ljPush
                  ; PUSH with slot reference - check if it's an integer constant
                  Protected pushConstSlot.i = llObjects()\i
                  If pushConstSlot >= 0 And pushConstSlot < gnLastVariable
                     If (gVarMeta(pushConstSlot)\flags & #C2FLAG_CONST) And (gVarMeta(pushConstSlot)\flags & #C2FLAG_INT)
                        ; Create new constant with negated value
                        Protected negValue.i = -gVarMeta(pushConstSlot)\valueInt
                        Protected newNegConstIdx.i = gnLastVariable
                        gVarMeta(newNegConstIdx)\name = "$neg" + Str(newNegConstIdx)
                        gVarMeta(newNegConstIdx)\valueInt = negValue
                        gVarMeta(newNegConstIdx)\valueFloat = 0.0
                        gVarMeta(newNegConstIdx)\valueString = ""
                        gVarMeta(newNegConstIdx)\flags = #C2FLAG_CONST | #C2FLAG_INT
                        gVarMeta(newNegConstIdx)\paramOffset = -1
                        gnLastVariable + 1
                        ; Update PUSH to reference new constant
                        llObjects()\i = newNegConstIdx
                        NextElement(llObjects())
                        llObjects()\code = #ljNOOP
                        peepholeCount + 1
                        negateOpt = #True
                     EndIf
                  EndIf
               EndIf

               If Not negateOpt
                  NextElement(llObjects())
                  ; Check for double negate
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
               EndIf
            Else
               ; Check for double negate
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
            EndIf

         ;- ====== COMPARE WITH ZERO: x == 0 → !x ======
         Case #ljEQUAL
            If PreviousElement(llObjects())
               If llObjects()\code = #ljPUSH_IMM And llObjects()\i = 0
                  llObjects()\code = #ljNOOP
                  NextElement(llObjects())
                  llObjects()\code = #ljNOT
                  peepholeCount + 1
               Else
                  NextElement(llObjects())
               EndIf
            EndIf

         ;- ====== COMPARISON + NOT → FLIPPED COMPARISON ======
         ; V1.035.3: Use rule-based comparison flip lookup
         Case #ljLESS, #ljGREATER, #ljLESSEQUAL, #ljGreaterEqual, #ljNOTEQUAL
            Protected cmpOp.i = llObjects()\code
            Protected flippedOp.i = GetFlippedCompare(cmpOp)
            If flippedOp And NextElement(llObjects())
               If llObjects()\code = #ljNOT
                  llObjects()\code = #ljNOOP
                  PreviousElement(llObjects())
                  llObjects()\code = flippedOp
                  peepholeCount + 1
               Else
                  PreviousElement(llObjects())
               EndIf
            EndIf

         ;- ====== LEGACY LOCAL FUSION (LFETCH+LSTORE → LLMOV) ======
         Case #ljLFETCH
            srcOffset = llObjects()\i
            *lfetchInstr = @llObjects()
            savedIdx = ListIndex(llObjects())
            If NextElement(llObjects())
               While llObjects()\code = #ljNOOP
                  If Not NextElement(llObjects()) : Break : EndIf
               Wend
               If llObjects()\code = #ljLSTORE
                  dstOffset = llObjects()\i
                  If srcOffset <> dstOffset
                     llObjects()\code = #ljLLMOV
                     llObjects()\i = dstOffset
                     llObjects()\j = srcOffset
                     ChangeCurrentElement(llObjects(), *lfetchInstr)
                     llObjects()\code = #ljNOOP
                     movFusionCount + 1
                  EndIf
               EndIf
               SelectElement(llObjects(), savedIdx)
            EndIf

         Case #ljLFETCHS
            srcOffset = llObjects()\i
            *lfetchInstr = @llObjects()
            savedIdx = ListIndex(llObjects())
            If NextElement(llObjects())
               While llObjects()\code = #ljNOOP
                  If Not NextElement(llObjects()) : Break : EndIf
               Wend
               If llObjects()\code = #ljLSTORES
                  dstOffset = llObjects()\i
                  If srcOffset <> dstOffset
                     llObjects()\code = #ljLLMOVS
                     llObjects()\i = dstOffset
                     llObjects()\j = srcOffset
                     ChangeCurrentElement(llObjects(), *lfetchInstr)
                     llObjects()\code = #ljNOOP
                     movFusionCount + 1
                  EndIf
               EndIf
               SelectElement(llObjects(), savedIdx)
            EndIf

         Case #ljLFETCHF
            srcOffset = llObjects()\i
            *lfetchInstr = @llObjects()
            savedIdx = ListIndex(llObjects())
            If NextElement(llObjects())
               While llObjects()\code = #ljNOOP
                  If Not NextElement(llObjects()) : Break : EndIf
               Wend
               If llObjects()\code = #ljLSTOREF
                  dstOffset = llObjects()\i
                  If srcOffset <> dstOffset
                     llObjects()\code = #ljLLMOVF
                     llObjects()\i = dstOffset
                     llObjects()\j = srcOffset
                     ChangeCurrentElement(llObjects(), *lfetchInstr)
                     llObjects()\code = #ljNOOP
                     movFusionCount + 1
                  EndIf
               EndIf
               SelectElement(llObjects(), savedIdx)
            EndIf

         Case #ljPFETCH
            If llObjects()\j = 1   ; Only local PFETCH
               srcOffset = llObjects()\i
               *lfetchInstr = @llObjects()
               savedIdx = ListIndex(llObjects())
               If NextElement(llObjects())
                  While llObjects()\code = #ljNOOP
                     If Not NextElement(llObjects()) : Break : EndIf
                  Wend
                  If llObjects()\code = #ljPSTORE And llObjects()\j = 1
                     dstOffset = llObjects()\i
                     If srcOffset <> dstOffset
                        llObjects()\code = #ljPMOV
                        llObjects()\n = 3   ; LL
                        llObjects()\i = dstOffset
                        llObjects()\j = srcOffset
                        ChangeCurrentElement(llObjects(), *lfetchInstr)
                        llObjects()\code = #ljNOOP
                        movFusionCount + 1
                     EndIf
                  EndIf
                  SelectElement(llObjects(), savedIdx)
               EndIf
            EndIf
      EndSelect
   Next

   CompilerIf #DEBUG
      Debug "      Peephole optimizations: " + Str(peepholeCount)
      Debug "      MOV fusion: " + Str(movFusionCount)
      Debug "    Pass 3: Compound Assignment Optimization"
   CompilerEndIf

   ;- ========================================
   ;- PASS 3: COMPOUND ASSIGNMENT OPTIMIZATION
   ;- ========================================
   ; V1.035.3: Use rule-based compound assignment lookup
   ; Pattern: FETCH var + PUSH val + OP + STORE same_var → compound assign
   Protected compoundOp.i
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
                  opCode = llObjects()\code
                  compoundOp = GetCompoundAssignOpcode(opCode)
                  If compoundOp
                     If NextElement(llObjects())
                        stepsForward = 3
                        If (llObjects()\code = #ljStore Or llObjects()\code = #ljSTOREF) And llObjects()\i = varSlot
                           Protected storeLocalityJ.i = llObjects()\j
                           PreviousElement(llObjects())
                           PreviousElement(llObjects())
                           PreviousElement(llObjects())
                           llObjects()\code = #ljNOOP
                           NextElement(llObjects())
                           NextElement(llObjects())
                           llObjects()\code = compoundOp
                           llObjects()\i = varSlot
                           llObjects()\j = storeLocalityJ
                           NextElement(llObjects())
                           llObjects()\code = #ljNOOP
                        Else
                           For i = 1 To stepsForward : PreviousElement(llObjects()) : Next
                        EndIf
                     Else
                        For i = 1 To stepsForward : PreviousElement(llObjects()) : Next
                     EndIf
                  Else
                     For i = 1 To stepsForward : PreviousElement(llObjects()) : Next
                  EndIf
               Else
                  For i = 1 To stepsForward : PreviousElement(llObjects()) : Next
               EndIf
            Else
               For i = 1 To stepsForward : PreviousElement(llObjects()) : Next
            EndIf
         Else
            For i = 1 To stepsForward : PreviousElement(llObjects()) : Next
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
                           varIdx = FindVariableSlotByOffset(localParamOffset, currentFunctionName)
                           If varIdx >= 0
                              funcPrefix = currentFunctionName + "_"
                              varName = gVarMeta(varIdx)\name
                              If Left(LCase(varName), Len(funcPrefix)) = LCase(funcPrefix)
                                 localVarName = Mid(varName, Len(funcPrefix) + 1)
                              EndIf
                           EndIf
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
      Debug "    Pass 6: Comparison-Jump Fusion"
   CompilerEndIf

   ;- ========================================
   ;- PASS 6: COMPARISON-JUMP FUSION (V1.035.16)
   ;- ========================================
   ; Pattern: FETCH/LFETCH + PUSH_IMM + LESS/GREATER/etc + JZ → fused conditional jump
   ; This eliminates 4 instructions (including stack operations) into 1
   ; Uses \ndx=slot, \j=immediate, \i=offset (offset in \i for FixJMP compatibility)
   ; MUST run after Pass 5 (PUSH_IMM conversion) to see PUSH_IMM opcodes
   Protected cmpJmpCount.i = 0
   Protected *fetchInstr2.stType, *pushInstr2.stType, *cmpInstr.stType, *jzInstr.stType
   Protected fusedOpcode.i, isLocal.i, cmpOpcode.i

   ResetList(llObjects())
   While NextElement(llObjects())
      ; Look for FETCH (global) or LFETCH (local) - integer only for now
      ; V1.035.17: Local variables can be #ljLFETCH OR #ljFetch with \j=1
      If llObjects()\code = #ljFetch Or llObjects()\code = #ljLFETCH
         isLocal = Bool(llObjects()\code = #ljLFETCH Or (llObjects()\code = #ljFetch And llObjects()\j = 1))
         fetchSlot = llObjects()\i
         *fetchInstr2 = @llObjects()
         savedIdx = ListIndex(llObjects())

         If NextElement(llObjects())
            ; Skip NOOPs
            While llObjects()\code = #ljNOOP
               If Not NextElement(llObjects()) : Break : EndIf
            Wend

            ; Check for PUSH_IMM (immediate value)
            If llObjects()\code = #ljPUSH_IMM
               constVal = llObjects()\i
               *pushInstr2 = @llObjects()

               If NextElement(llObjects())
                  ; Skip NOOPs
                  While llObjects()\code = #ljNOOP
                     If Not NextElement(llObjects()) : Break : EndIf
                  Wend

                  ; Check for comparison opcode
                  cmpOpcode = llObjects()\code
                  If cmpOpcode = #ljLESS Or cmpOpcode = #ljLESSEQUAL Or cmpOpcode = #ljGREATER Or cmpOpcode = #ljGreaterEqual Or cmpOpcode = #ljEQUAL Or cmpOpcode = #ljNotEqual
                     *cmpInstr = @llObjects()

                     If NextElement(llObjects())
                        ; Skip NOOPs
                        While llObjects()\code = #ljNOOP
                           If Not NextElement(llObjects()) : Break : EndIf
                        Wend

                        ; Check for JZ
                        If llObjects()\code = #ljJZ
                           jmpOffset = llObjects()\i
                           *jzInstr = @llObjects()

                           ; Determine fused opcode based on comparison and locality
                           ; JZ after comparison inverts: LESS+JZ becomes JGE (jump if NOT less)
                           Select cmpOpcode
                              Case #ljLESS
                                 fusedOpcode = #ljJGE_VAR_IMM
                              Case #ljLESSEQUAL
                                 fusedOpcode = #ljJGT_VAR_IMM
                              Case #ljGREATER
                                 fusedOpcode = #ljJLE_VAR_IMM
                              Case #ljGreaterEqual
                                 fusedOpcode = #ljJLT_VAR_IMM
                              Case #ljEQUAL
                                 fusedOpcode = #ljJNE_VAR_IMM
                              Case #ljNotEqual
                                 fusedOpcode = #ljJEQ_VAR_IMM
                           EndSelect

                           ; Adjust for local variable version
                           If isLocal
                              ; Local versions are 6 opcodes after global versions
                              fusedOpcode + 6
                           EndIf

                           ; Apply fusion: Replace JZ with fused opcode, NOOP the rest
                           ; JZ becomes fused conditional jump
                           ChangeCurrentElement(llObjects(), *jzInstr)
                           llObjects()\code = fusedOpcode
                           llObjects()\ndx = fetchSlot  ; slot/offset
                           llObjects()\j = constVal     ; immediate value
                           llObjects()\i = jmpOffset    ; jump offset (in \i for FixJMP compatibility)

                           ; NOOP the FETCH, PUSH_IMM, and comparison
                           ChangeCurrentElement(llObjects(), *fetchInstr2)
                           llObjects()\code = #ljNOOP
                           ChangeCurrentElement(llObjects(), *pushInstr2)
                           llObjects()\code = #ljNOOP
                           ChangeCurrentElement(llObjects(), *cmpInstr)
                           llObjects()\code = #ljNOOP

                           cmpJmpCount + 1
                        EndIf
                     EndIf
                  EndIf
               EndIf
            EndIf
         EndIf

         SelectElement(llObjects(), savedIdx)
      EndIf
   Wend

   CompilerIf #DEBUG
      Debug "      Comparison-Jump fusion: " + Str(cmpJmpCount)
      Debug "=== Optimizer V03 Complete ==="
   CompilerEndIf

EndProcedure

; IDE Options = PureBasic 6.21 (Windows - x64)
; EnableThread
; EnableXP
; CPU = 1
