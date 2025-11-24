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
;  Compiler
;- Fixes code and optimizer
;
Procedure            InitJumpTracker()
      ; V1.020.077: Initialize jump tracker BEFORE PostProcessor runs
      ; This allows optimization passes to call AdjustJumpsForNOOP() with populated tracker

      Protected         i, pos, pair
      Protected         srcPos.i
      Protected         offset.i
      Protected         *targetInstr.stType  ; V1.020.085: Store target instruction pointer

      CompilerIf #DEBUG
         Debug "InitJumpTracker: Populating jump tracker before optimization"
      CompilerEndIf

      ForEach llHoles()
         If llHoles()\mode = #C2HOLE_DEFAULT
            PushListPosition( llHoles() )
               llHoles()\mode = #C2HOLE_PAIR
               pair  = llHoles()\id
               ChangeCurrentElement( llObjects(), llHoles()\location )
               pos   = ListIndex( llObjects() )

               ; V1.020.097: BUGFIX - Do NOT call NextElement()!
               ; fix() already stores the correct target position (the instruction where JZ should land)
               ; The previous NextElement() call was causing JZ to skip over RET and land on next function
               ; Example: if fix() stores RET at pos 345, we want to jump to 345, not NextElement() at 346!
               *targetInstr = @llObjects()  ; Store pointer to current position (what fix() stored)
               llObjects()\anchor = pair  ; V1.020.070: Mark target instruction with anchor
               CompilerIf #DEBUG
                  Debug "FixJMP: Target pos=" + Str(pos) + " (" + gszATR(llObjects()\code)\s + "), anchor=" + Str(pair)
               CompilerEndIf

               i     = 0
               
               ForEach llHoles()
                  If llHoles()\mode = #C2HOLE_START And llHoles()\id = pair
                     llHoles()\mode = #C2HOLE_PAIR
                        ChangeCurrentElement( llObjects(), llHoles()\location )
                        srcPos = ListIndex( llObjects() )

                        ; After PostProcessor removes NOOPs, list positions are final
                        ; Use direct offset calculation (pos - srcPos)
                        offset = (pos - srcPos)

                        CompilerIf #DEBUG
                           ; V1.020.096: Enhanced debug to show both source and target instructions
                           Protected savedPos = ListIndex(llObjects())
                           Debug "FixJMP: Source: " + gszATR(llObjects()\code)\s + " at srcPos=" + Str(srcPos)
                           If ChangeCurrentElement(llObjects(), *targetInstr)
                              Debug "FixJMP: Target: " + gszATR(llObjects()\code)\s + " at pos=" + Str(pos) + " (ptr valid)"
                              SelectElement(llObjects(), savedPos)  ; Restore position
                           Else
                              Debug "FixJMP: Target: pos=" + Str(pos) + " (ptr INVALID!)"
                           EndIf
                           Debug "FixJMP: Calculated offset=" + Str(offset) + " (pos " + Str(pos) + " - srcPos " + Str(srcPos) + ")"
                        CompilerEndIf
                        ;If llObjects()\code = #ljTENIF Or llObjects()\code = #ljTENELSE
                        ;   Debug "FixJMP: " + gszATR(llObjects()\code)\s + " at " + Str(srcPos) + " target " + Str(pos) + " (NOOPIF) offset " + Str(offset)
                        ;ElseIf llObjects()\code = #ljJMP And (llObjects()\flags & #INST_FLAG_TERNARY)
                        ;   Debug "FixJMP: Ternary JMP at " + Str(srcPos) + " target " + Str(pos) + " offset " + Str(offset)
                        ;EndIf
                        llObjects()\i = offset
                        llObjects()\anchor = pair  ; V1.020.070: Store anchor ID for Pass 26 recalculation

                        ; V1.020.077: Add to jump tracker for incremental NOOP adjustment
                        ; V1.020.085: Store target instruction pointer for post-NOOP offset recalc
                        ; Tracker is populated BEFORE PostProcessor runs
                        AddElement(llJumpTracker())
                        llJumpTracker()\instruction = @llObjects()  ; V1.020.085: Store explicit address of source
                        llJumpTracker()\target = *targetInstr  ; V1.020.085: Store target pointer
                        llJumpTracker()\srcPos = srcPos
                        llJumpTracker()\targetPos = pos
                        llJumpTracker()\offset = offset
                        llJumpTracker()\type = llObjects()\code

                        CompilerIf #DEBUG
                           Debug "InitJumpTracker: Added " + gszATR(llObjects()\code)\s + " at srcPos=" + Str(srcPos) + " targetPos=" + Str(pos) + " offset=" + Str(offset)
                        CompilerEndIf

                     Break
                  EndIf
               Next
            PopListPosition( llHoles() )
         ElseIf llHoles()\mode = #C2HOLE_BLIND
            ; V1.020.087: BLIND jumps also tracked for post-NOOP recalculation
            llHoles()\mode = #C2HOLE_PAIR
            ChangeCurrentElement( llObjects(), llHoles()\src )
            pos = ListIndex( llObjects() )
            *targetInstr = @llObjects()  ; V1.020.087: Store target pointer
            ChangeCurrentElement( llObjects(), llHoles()\location )
            srcPos = ListIndex( llObjects() )
            ; Calculate offset based on current pre-optimization positions
            offset = (pos - srcPos)
            llObjects()\i = offset

            ; V1.020.087: Add BLIND jump to tracker for recalculation
            AddElement(llJumpTracker())
            llJumpTracker()\instruction = @llObjects()
            llJumpTracker()\target = *targetInstr
            llJumpTracker()\srcPos = srcPos
            llJumpTracker()\targetPos = pos
            llJumpTracker()\offset = offset
            llJumpTracker()\type = llObjects()\code  ; Store the jump opcode

            CompilerIf #DEBUG
               Debug "InitJumpTracker: BLIND jump at srcPos=" + Str(srcPos) + " targetPos=" + Str(pos) + " offset=" + Str(offset)
            CompilerEndIf
         EndIf
      Next

      CompilerIf #DEBUG
         Debug "InitJumpTracker: Populated " + Str(ListSize(llJumpTracker())) + " jumps"
      CompilerEndIf
   EndProcedure

Procedure            FixJMP()
      ; V1.020.077: FixJMP now runs AFTER PostProcessor and uses pre-populated tracker
      ; InitJumpTracker() must be called BEFORE PostProcessor to populate the tracker
      ; BLIND jumps are calculated in InitJumpTracker (before optimization)

      Protected         i, pos, pair
      Protected         srcPos.i
      Protected         offset.i
      Protected         remapIdx.i
      Protected         anchorID, targetPos
      Protected         noopCount.i, stepCount.i
      Protected         flags.s

      CompilerIf #DEBUG
         Debug "FixJMP: Starting post-optimization fixup (tracker has " + Str(ListSize(llJumpTracker())) + " jumps)"
      CompilerEndIf

      ; Recalculate function addresses after PostProcessor optimizations
      ; This is critical because PostProcessor may add/remove/optimize instructions
      ; Strategy: Use stored element pointers to find actual post-optimization positions

      ; gFuncLocalArraySlots already populated during CodeGenerator phase
      ; Array sized at (512, 15) - sufficient for most programs
      ; DO NOT redimension here as Dim/ReDim would clear the data!

      ; V1.020.027: MOVED AFTER NOOP REMOVAL - see lines after NOOP deletion
      ; Function address recalculation must happen AFTER NOOPs are removed
      ; because ListIndex() values change when NOOPs are deleted

      ; Convert all NOOPIF markers to NOOP - they were only needed for offset calculation
      ; V1.20.19: Now that offsets are calculated, we can safely delete NOOPs
      ForEach llObjects()
         If llObjects()\code = #ljNOOPIF
            llObjects()\code = #ljNOOP
         EndIf
      Next

      CompilerIf #DEBUG
         Debug "    Pass 26: NOOP-aware jump offset adjustment and NOOP deletion"
      CompilerEndIf

      ;- Pass 26: NOOP-aware jump offset adjustment (V1.20.34: renamed from Pass 11)
      ; V1.20.20: Adjust jump offsets to account for NOOP removal, then delete NOOPs
      ; User insight: "make a pass 11; a reverse pass and adjust the jumps accordingly"
      ; V1.020.066: TEMPORARILY DISABLED (along with Pass 25) to test FizzBuzz corruption
      ; V1.020.067: RE-ENABLED but skip jump adjustment (keep function patching)
      ; V1.020.072: Anchor system disabled - too complex, reverting to stable (NOOPs in place)
      ; V1.020.074: Incremental jump adjustment system - offsets adjusted during optimization!
      ;             Now we can safely remove NOOPs and the jump offsets will be correct
      ; V1.020.082: ENABLED - Testing incremental adjustment with NOOP deletion

      ; Pass 25: Delete all NOOP instructions
      ; Jump offsets have already been adjusted incrementally by AdjustJumpsForNOOP()
      ; during optimization passes, so we can safely remove NOOPs now
      ; V1.020.093: TEMPORARILY DISABLED to test if NOOP deletion causes array corruption
      ; V1.020.094: RE-ENABLED - Real bug was incremental adjustment, not NOOP deletion
      CompilerIf #True  ; V1.020.094: Re-enabled after fixing incremental adjustment bug
      noopCount = 0
      ForEach llObjects()
         If llObjects()\code = #ljNOOP
            noopCount + 1
            DeleteElement(llObjects())
         EndIf
      Next
      CompilerIf #DEBUG
         Debug "Pass 25: Deleted " + Str(noopCount) + " NOOP instructions"
      CompilerEndIf
      CompilerEndIf

      ; V1.020.085: Recalculate jump offsets AFTER NOOP deletion using stored pointers
      ; Jump tracker stores direct pointers to both jump instruction and target instruction
      ; Use stored pointers to find current positions in post-NOOP list and recalculate offset
      ForEach llJumpTracker()
         ; Find current position of jump instruction using stored pointer
         If ChangeCurrentElement(llObjects(), llJumpTracker()\instruction)
            srcPos = ListIndex(llObjects())

            ; Find current position of target instruction using stored pointer
            If llJumpTracker()\target And ChangeCurrentElement(llObjects(), llJumpTracker()\target)
               targetPos = ListIndex(llObjects())

               ; Recalculate offset based on post-NOOP positions
               offset = targetPos - srcPos
               llJumpTracker()\instruction\i = offset
               CompilerIf #DEBUG
                  ; V1.020.096: Enhanced debug to show instruction types
                  Protected srcInstrName.s = gszATR(llJumpTracker()\instruction\code)\s
                  Protected tgtInstrName.s = gszATR(llObjects()\code)\s
                  Debug "Pass26: " + srcInstrName + " at pos=" + Str(srcPos) + " → " + tgtInstrName + " at pos=" + Str(targetPos) + " offset=" + Str(offset) + " (was " + Str(llJumpTracker()\offset) + ")"
               CompilerEndIf
            Else
               CompilerIf #DEBUG
                  Debug "FixJMP: WARNING - Could not find target for jump at pos=" + Str(srcPos) + " (target pointer invalid)"
               CompilerEndIf
            EndIf
         Else
            CompilerIf #DEBUG
               Debug "FixJMP: WARNING - Could not find jump instruction (instruction pointer invalid)"
            CompilerEndIf
         EndIf
      Next

      ; V1.020.027: NOW recalculate function addresses AFTER NOOP removal
      ; This ensures ListIndex() values are correct (NOOPs have been deleted)
      ; V1.020.067: KEEP THIS ACTIVE - Essential for function calls to work!

      ; Recalculate function indexes using stored element pointers
      ForEach mapModules()
         If mapModules()\NewPos
            ; Use stored pointer to find current position of function entry
            ; NOOPs are now deleted, so ListIndex() gives final bytecode positions
            If ChangeCurrentElement(llObjects(), mapModules()\NewPos)
               mapModules()\Index = ListIndex(llObjects()) + 1
               CompilerIf #DEBUG
                  Debug "Function fixup (post-NOOP): funcId=" + Str(mapModules()\function) + " -> Index=" + Str(mapModules()\Index)
               CompilerEndIf
            EndIf
         EndIf
      Next

      ; Now patch all CALL instructions with correct function addresses AND nLocals count
      ; IMPORTANT: Store function ID in funcid field (for gFuncLocalArraySlots lookup)
      ;            Store PC address in i field (for jumping)
      ForEach llObjects()
         If llObjects()\code = #ljCall
            CompilerIf #DEBUG
               Debug "Patching CALL (post-NOOP): old funcId=" + Str(llObjects()\i)
            CompilerEndIf
            ForEach mapModules()
               If mapModules()\function = llObjects()\i
                  llObjects()\funcid = mapModules()\function  ; Store function ID in funcid (for array lookup)
                  llObjects()\i = mapModules()\Index  ; Store PC address in i (for jumping)
                  llObjects()\n = mapModules()\nLocals  ; Update nLocals from final count
                  CompilerIf #DEBUG
                     Debug "  -> PC=" + Str(mapModules()\Index) + ", funcId=" + Str(mapModules()\function) + ", nLocals=" + Str(mapModules()\nLocals)
                  CompilerEndIf
                  Break
               EndIf
            Next
         EndIf
      Next

      ; NO REMAPPING NEEDED - gFuncLocalArraySlots stays indexed by function ID
      ; VM will use funcid field to get function ID for array lookup

   EndProcedure

Procedure            AdjustJumpsForNOOP(noopPos.i)
      ; V1.020.074: Adjust jump offsets when NOOP is created during optimization
      ; V1.020.094: DISABLED - Incremental adjustment is flawed because it doesn't update
      ;             srcPos/targetPos as NOOPs are created, causing offsets to drift.
      ;             Pass 26's pointer-based recalculation is correct and sufficient.
      ProcedureReturn

      ; DISABLED CODE BELOW
      ; When an optimization pass creates a NOOP, we need to adjust all jump offsets
      ; that span across the NOOP position. This is done incrementally as NOOPs are
      ; created, rather than trying to recalculate everything after NOOP removal.
      ;
      ; For each tracked jump:
      ;   If NOOP is between source and target:
      ;     - Forward jump: offset -= 1 (NOOP will be removed, target gets closer)
      ;     - Backward jump: offset += 1 (NOOP will be removed, source gets farther)
      ;   Update both tracker and instruction's offset field

      Protected srcPos.i
      Protected targetPos.i

      ForEach llJumpTracker()
         srcPos = llJumpTracker()\srcPos
         targetPos = llJumpTracker()\targetPos

         ; Check if NOOP is between source and target
         ; ASYMMETRY: Forward vs Backward jumps handle target position differently
         ;
         ; Forward jump: If NOOP at exact target, DON'T adjust (jump lands at same position number)
         ; Backward jump: If NOOP at exact target, DO adjust (source shifts, target deleted)

         If llJumpTracker()\offset > 0  ; Forward jump (srcPos < targetPos)
            ; Adjust for NOOPs strictly between source and target (not at target itself)
            If noopPos > srcPos And noopPos < targetPos
               llJumpTracker()\offset - 1
               llJumpTracker()\instruction\i = llJumpTracker()\offset
               CompilerIf #DEBUG
                  Debug "AdjustJumpsForNOOP: Forward jump at " + Str(srcPos) + " adjusted to offset " + Str(llJumpTracker()\offset)
               CompilerEndIf
            EndIf
         ElseIf llJumpTracker()\offset < 0  ; Backward jump (srcPos > targetPos)
            ; Adjust for NOOPs between target and source (INCLUDING at target position)
            If noopPos >= targetPos And noopPos < srcPos
               llJumpTracker()\offset + 1
               llJumpTracker()\instruction\i = llJumpTracker()\offset
               CompilerIf #DEBUG
                  Debug "AdjustJumpsForNOOP: Backward jump at " + Str(srcPos) + " adjusted to offset " + Str(llJumpTracker()\offset)
               CompilerEndIf
            EndIf
         EndIf
      Next
   EndProcedure

Procedure            PostProcessor()
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
      Protected funcEndIdx.i, lastOpcode.i, needsReturn.i, returnOpcode.i
      Protected optimizationsEnabled.i
      Protected indexVarSlot.i
      Protected varSlot.i
      Protected isFetch.i
      Protected optimized.i
      Protected valueSlot.i
      Protected stepsForward.i
      Protected savedPos
      Protected foundEnd.i
      Protected foundGetAddr.i
      Protected getAddrType.i
      Protected isArrayPointer.b
      ; V1.20.27: Variables for pointer opcode upgrading
      Protected searchKey.s
      Protected srcVar.i, dstVar.i
      Protected isPointer.b
      ; V1.20.34: Variables for pointer type tracking pass
      Protected ptrVarSlot.i
      Protected ptrVarKey.s
      Protected sourceIsPointer.b
      Protected pointerBaseType.i
      Protected ptrOpcode.i
      ; V1.20.47: Variables for function-aware pointer tracking
      Protected currentFunctionName.s
      Protected srcSlot.i
      Protected srcVarKey.s
      Protected funcId.i
      Protected varName.s
      Protected flags.s

      CompilerIf #DEBUG
         Debug "    Pass 1: Pointer type tracking (mark variables assigned from pointer sources)"
      CompilerEndIf

      ;- Pass 1: Pointer type tracking (V1.20.34)
      ; Traverse bytecode to identify variables that receive pointer values
      ; Mark them with #C2FLAG_POINTER in mapVariableTypes for proper handling
      ForEach llObjects()
         Select llObjects()\code
            ; Variables assigned from GETADDR are pointers
            Case #ljGETADDR, #ljGETADDRF, #ljGETADDRS
               ; Store the GETADDR type for later use
               getAddrType = llObjects()\code

               ; Find the next STORE/POP to see which variable gets this pointer
               If NextElement(llObjects())
                  If llObjects()\code = #ljStore Or llObjects()\code = #ljSTORES Or llObjects()\code = #ljSTOREF Or
                     llObjects()\code = #ljPOP Or llObjects()\code = #ljPOPS Or llObjects()\code = #ljPOPF
                     ptrVarSlot = llObjects()\i

                     ; Mark this variable as a pointer in mapVariableTypes
                     If ptrVarSlot >= 0 And ptrVarSlot < gnLastVariable
                        ptrVarKey = gVarMeta(ptrVarSlot)\name

                        ; Determine pointer base type from GETADDR variant
                        Select getAddrType
                           Case #ljGETADDRF
                              pointerBaseType = #C2FLAG_FLOAT
                           Case #ljGETADDRS
                              pointerBaseType = #C2FLAG_STR
                           Default
                              pointerBaseType = #C2FLAG_INT
                        EndSelect

                        ; Store pointer type in map
                        mapVariableTypes(ptrVarKey) = #C2FLAG_POINTER | pointerBaseType

                        CompilerIf #DEBUG
                           Debug "      Marked variable '" + ptrVarKey + "' as pointer (from GETADDR)"
                        CompilerEndIf
                     EndIf
                  EndIf
                  PreviousElement(llObjects())  ; Restore position
               EndIf

            ; Variables assigned from pointer arithmetic are also pointers
            Case #ljPTRADD, #ljPTRSUB
               ; These operations leave a pointer on the stack
               ; Find the next STORE/POP to see which variable gets this pointer
               If NextElement(llObjects())
                  If llObjects()\code = #ljStore Or llObjects()\code = #ljSTORES Or llObjects()\code = #ljSTOREF Or
                     llObjects()\code = #ljPOP Or llObjects()\code = #ljPOPS Or llObjects()\code = #ljPOPF
                     ptrVarSlot = llObjects()\i

                     ; Mark this variable as a pointer (preserve int type for arithmetic)
                     If ptrVarSlot >= 0 And ptrVarSlot < gnLastVariable
                        ptrVarKey = gVarMeta(ptrVarSlot)\name
                        mapVariableTypes(ptrVarKey) = #C2FLAG_POINTER | #C2FLAG_INT

                        CompilerIf #DEBUG
                           Debug "      Marked variable '" + ptrVarKey + "' as pointer (from pointer arithmetic)"
                        CompilerEndIf
                     EndIf
                  EndIf
                  PreviousElement(llObjects())  ; Restore position
               EndIf

            ; Variables assigned from other pointers via MOV
            Case #ljMOV, #ljPMOV, #ljLMOV
               srcVar = llObjects()\j
               dstVar = llObjects()\i

               ; Check if source is a pointer
               sourceIsPointer = #False
               If srcVar >= 0 And srcVar < gnLastVariable
                  searchKey = gVarMeta(srcVar)\name
                  If FindMapElement(mapVariableTypes(), searchKey)
                     If mapVariableTypes() & #C2FLAG_POINTER
                        sourceIsPointer = #True
                        pointerBaseType = mapVariableTypes() & #C2FLAG_TYPE
                     EndIf
                  EndIf

                  ; V1.20.35: Also check if source is a parameter
                  ; Parameters can hold pointer values but aren't in mapVariableTypes
                  If Not sourceIsPointer And (gVarMeta(srcVar)\flags & #C2FLAG_PARAM)
                     ; Parameter - assume it could be a pointer (we don't know at compile time)
                     sourceIsPointer = #True
                     pointerBaseType = #C2FLAG_INT  ; Default to int pointers

                     CompilerIf #DEBUG
                        Debug "      Source is parameter '" + gVarMeta(srcVar)\name + "', treating as potential pointer"
                     CompilerEndIf
                  EndIf
               EndIf

               ; If source is pointer, mark destination as pointer too
               If sourceIsPointer And dstVar >= 0 And dstVar < gnLastVariable
                  ptrVarKey = gVarMeta(dstVar)\name
                  mapVariableTypes(ptrVarKey) = #C2FLAG_POINTER | pointerBaseType

                  CompilerIf #DEBUG
                     Debug "      Marked variable '" + ptrVarKey + "' as pointer (from MOV from pointer)"
                  CompilerEndIf
               EndIf
         EndSelect
      Next

      ;- Pass 1a: Mark variables used with pointer field access operations as pointers (V1.20.41)
      ; If a variable is used with IPTRFETCH, IPTRSTORE, etc., it must be a pointer
      CompilerIf #DEBUG
         Debug "    Pass 1a: Mark variables used with pointer operations as pointers"
      CompilerEndIf
      ForEach llObjects()
         Select llObjects()\code
            Case #ljPTRFETCH_INT, #ljPTRFETCH_FLOAT, #ljPTRFETCH_STR, #ljPTRSTORE_INT, #ljPTRSTORE_FLOAT, #ljPTRSTORE_STR
               ; These opcodes operate on pointers
               ; Remember which opcode we're processing
               ptrOpcode = llObjects()\code

               ; Look back to find what variable was fetched
               If PreviousElement(llObjects())
                  ; V1.20.46: Only process FETCH and PFETCH here (global variables)
                  ; LFETCH uses slot offsets which are ambiguous across functions
                  ; Local pointers are tracked by Pass 1b instead
                  If llObjects()\code = #ljFetch Or llObjects()\code = #ljPFETCH
                     ptrVarSlot = llObjects()\i
                     ptrVarKey = ""

                     ; FETCH and PFETCH use variable index directly
                     If ptrVarSlot >= 0 And ptrVarSlot < gnLastVariable
                        ptrVarKey = gVarMeta(ptrVarSlot)\name
                     EndIf

                     If ptrVarKey <> ""
                        ; Mark as pointer if not already marked
                        If Not FindMapElement(mapVariableTypes(), ptrVarKey)
                           AddMapElement(mapVariableTypes(), ptrVarKey)
                        EndIf

                        ; Set pointer flag (preserve base type if already set)
                        If (mapVariableTypes() & #C2FLAG_POINTER) = 0
                           ; Determine base type from the PTRFETCH/PTRSTORE variant
                           Select ptrOpcode
                              Case #ljPTRFETCH_INT, #ljPTRSTORE_INT
                                 mapVariableTypes() = #C2FLAG_POINTER | #C2FLAG_INT
                              Case #ljPTRFETCH_FLOAT, #ljPTRSTORE_FLOAT
                                 mapVariableTypes() = #C2FLAG_POINTER | #C2FLAG_FLOAT
                              Case #ljPTRFETCH_STR, #ljPTRSTORE_STR
                                 mapVariableTypes() = #C2FLAG_POINTER | #C2FLAG_STR
                           EndSelect

                           CompilerIf #DEBUG
                              Debug "      Marked variable '" + ptrVarKey + "' as pointer (from pointer field access)"
                           CompilerEndIf
                        EndIf
                     EndIf
                  EndIf
                  NextElement(llObjects())  ; Move back to PTRFETCH/PTRSTORE
               EndIf
         EndSelect
      Next

      ; V1.20.46: Second pass - track pointer parameter usage via PTRFETCH
      ; When we see PLFETCH + PTRFETCH, mark the parameter as a pointer
      CompilerIf #DEBUG
         Debug "    Pass 1b: Track pointer parameters via PTRFETCH usage"
      CompilerEndIf
      currentFunctionName = ""
      ForEach llObjects()
         ; Track function boundaries
         If llObjects()\code = #ljFUNCTION
            ; Get function name from metadata
            funcId = llObjects()\i
            currentFunctionName = ""
            ForEach mapModules()
              If mapModules()\function = funcId
                 currentFunctionName = MapKey(mapModules())
                 Break
              EndIf
            Next
         EndIf

         ; Look for PLFETCH/LFETCH followed by PTRFETCH
         If llObjects()\code = #ljPLFETCH Or llObjects()\code = #ljLFETCH
            srcSlot = llObjects()\i
            srcVarKey = ""

            ; Find variable with matching paramOffset in current function
            For varIdx = 0 To gnLastVariable - 1
               If gVarMeta(varIdx)\paramOffset = srcSlot
                  varName = gVarMeta(varIdx)\name
                  ; Verify it belongs to current function (or is global)
                  If currentFunctionName <> "" And Left(varName, 1) <> "$"
                     If Left(varName, Len(currentFunctionName) + 1) = currentFunctionName + "_"
                        srcVarKey = varName
                        Break
                     EndIf
                  ElseIf currentFunctionName = ""  ; Global context
                     srcVarKey = varName
                     Break
                  EndIf
               EndIf
            Next

            ; Check if next instruction is PTRFETCH (indicates this is a pointer)
            If srcVarKey <> "" And NextElement(llObjects())
               Select llObjects()\code
                  Case #ljPTRFETCH_INT, #ljPTRFETCH_FLOAT, #ljPTRFETCH_STR, #ljPTRSTORE_INT, #ljPTRSTORE_FLOAT, #ljPTRSTORE_STR
                     ; This variable is used with pointer operations - mark it as pointer
                     If Not FindMapElement(mapVariableTypes(), srcVarKey)
                        AddMapElement(mapVariableTypes(), srcVarKey)
                     EndIf
                     If (mapVariableTypes() & #C2FLAG_POINTER) = 0
                        Select llObjects()\code
                           Case #ljPTRFETCH_INT, #ljPTRSTORE_INT
                              mapVariableTypes() = #C2FLAG_POINTER | #C2FLAG_INT
                           Case #ljPTRFETCH_FLOAT, #ljPTRSTORE_FLOAT
                              mapVariableTypes() = #C2FLAG_POINTER | #C2FLAG_FLOAT
                           Case #ljPTRFETCH_STR, #ljPTRSTORE_STR
                              mapVariableTypes() = #C2FLAG_POINTER | #C2FLAG_STR
                        EndSelect
                        CompilerIf #DEBUG
                           Debug "      [PASS1b] Marked local variable '" + srcVarKey + "' (slot=" + Str(srcSlot) + ") as pointer (from LFETCH+PTRFETCH)"
                        CompilerEndIf
                     EndIf
               EndSelect
               PreviousElement(llObjects())  ; Move back
            EndIf
         EndIf
      Next

      ; Fix up opcodes based on actual variable types
      ; This handles cases where types weren't known at parse time
      CompilerIf #DEBUG
         Debug "    Pass 2: Type-based opcode fixups"
      CompilerEndIf
      ForEach llObjects()
         Select llObjects()\code
            Case #ljPush
               ; Check if this push should be typed
               n = llObjects()\i
               If n >= 0 And n < gnLastVariable
                  ; Skip parameters - they're generic and handled at runtime
                  If Not (gVarMeta(n)\flags & #C2FLAG_PARAM)
                     If gVarMeta(n)\flags & #C2FLAG_FLOAT
                        llObjects()\code = #ljPUSHF
                     ElseIf gVarMeta(n)\flags & #C2FLAG_STR
                        llObjects()\code = #ljPUSHS
                     EndIf
                  EndIf
               EndIf

            Case #ljGETADDR
               ; Fix GETADDR type based on variable type
               n = llObjects()\i
               If n >= 0 And n < gnLastVariable
                  If gVarMeta(n)\flags & #C2FLAG_FLOAT
                     llObjects()\code = #ljGETADDRF
                  ElseIf gVarMeta(n)\flags & #C2FLAG_STR
                     llObjects()\code = #ljGETADDRS
                  EndIf
               EndIf

            ; V1.20.27: Upgrade to pointer-only opcodes for pointer variables
            Case #ljFetch
               ; Check if variable is a pointer
               n = llObjects()\i
               If n >= 0 And n < gnLastVariable
                  searchKey = gVarMeta(n)\name
                  If FindMapElement(mapVariableTypes(), searchKey)
                     If mapVariableTypes() & #C2FLAG_POINTER
                        llObjects()\code = #ljPFETCH
                     EndIf
                  EndIf
               EndIf

            Case #ljStore
               ; Check if variable is a pointer
               n = llObjects()\i
               If n >= 0 And n < gnLastVariable
                  searchKey = gVarMeta(n)\name
                  If FindMapElement(mapVariableTypes(), searchKey)
                     If mapVariableTypes() & #C2FLAG_POINTER
                        llObjects()\code = #ljPSTORE
                     EndIf
                  EndIf
               EndIf

            Case #ljPOP
               ; Check if variable is a pointer
               n = llObjects()\i
               If n >= 0 And n < gnLastVariable
                  searchKey = gVarMeta(n)\name
                  If FindMapElement(mapVariableTypes(), searchKey)
                     If mapVariableTypes() & #C2FLAG_POINTER
                        llObjects()\code = #ljPPOP
                     EndIf
                  EndIf
               EndIf

            Case #ljMOV
               ; Check if source or destination is a pointer
               srcVar = llObjects()\j
               dstVar = llObjects()\i
               isPointer = #False

               ; Check destination
               If dstVar >= 0 And dstVar < gnLastVariable
                  searchKey = gVarMeta(dstVar)\name
                  If FindMapElement(mapVariableTypes(), searchKey)
                     If mapVariableTypes() & #C2FLAG_POINTER
                        isPointer = #True
                     EndIf
                  EndIf
               EndIf

               ; Check source if not already identified as pointer
               If Not isPointer And srcVar >= 0 And srcVar < gnLastVariable
                  searchKey = gVarMeta(srcVar)\name
                  If FindMapElement(mapVariableTypes(), searchKey)
                     If mapVariableTypes() & #C2FLAG_POINTER
                        isPointer = #True
                     EndIf
                  EndIf
               EndIf

               If isPointer
                  llObjects()\code = #ljPMOV
               EndIf

            Case #ljLFETCH
               ; V1.20.45: Convert LFETCH to PLFETCH for pointer locals
               ; Local variables have paramOffset set - search for matching variable
               n = llObjects()\i  ; This is the local slot offset
               CompilerIf #DEBUG
                  Debug "[LFETCH] Looking for local slot " + Str(n)
               CompilerEndIf
               For varIdx = 0 To gnLastVariable - 1
                  If gVarMeta(varIdx)\paramOffset = n
                     searchKey = gVarMeta(varIdx)\name
                     CompilerIf #DEBUG
                        Debug "  Found variable: " + searchKey + " at slot " + Str(n)
                     CompilerEndIf
                     If FindMapElement(mapVariableTypes(), searchKey)
                        CompilerIf #DEBUG
                           Debug "    In mapVariableTypes, flags=" + Hex(mapVariableTypes())
                        CompilerEndIf
                        If mapVariableTypes() & #C2FLAG_POINTER
                           CompilerIf #DEBUG
                              Debug "    -> Converting LFETCH to PLFETCH"
                           CompilerEndIf
                           llObjects()\code = #ljPLFETCH
                           Break
                        EndIf
                     Else
                        CompilerIf #DEBUG
                           Debug "    NOT in mapVariableTypes"
                        CompilerEndIf
                     EndIf
                  EndIf
               Next

            Case #ljLSTORE
               ; V1.20.45: Convert LSTORE to PLSTORE for pointer locals
               ; Local variables have paramOffset set - search for matching variable
               n = llObjects()\i  ; This is the local slot offset
               CompilerIf #DEBUG
                  Debug "[LSTORE] Looking for local slot " + Str(n)
               CompilerEndIf
               For varIdx = 0 To gnLastVariable - 1
                  If gVarMeta(varIdx)\paramOffset = n
                     searchKey = gVarMeta(varIdx)\name
                     CompilerIf #DEBUG
                        Debug "  Found variable: " + searchKey + " at slot " + Str(n)
                     CompilerEndIf
                     If FindMapElement(mapVariableTypes(), searchKey)
                        CompilerIf #DEBUG
                           Debug "    In mapVariableTypes, flags=" + Hex(mapVariableTypes())
                        CompilerEndIf
                        If mapVariableTypes() & #C2FLAG_POINTER
                           CompilerIf #DEBUG
                              Debug "    -> Converting LSTORE to PLSTORE"
                           CompilerEndIf
                           llObjects()\code = #ljPLSTORE
                           Break
                        EndIf
                     Else
                        CompilerIf #DEBUG
                           Debug "    NOT in mapVariableTypes"
                        CompilerEndIf
                     EndIf
                  EndIf
               Next

            Case #ljLMOV
               ; Local MOV - skip for now (would need both src and dst checks)

            ; V1.20.36: Convert increment/decrement on pointers to pointer arithmetic
            Case #ljINC_VAR
               ; Check if variable is a pointer
               n = llObjects()\i
               If n >= 0 And n < gnLastVariable
                  searchKey = gVarMeta(n)\name
                  If FindMapElement(mapVariableTypes(), searchKey)
                     If mapVariableTypes() & #C2FLAG_POINTER
                        llObjects()\code = #ljPTRINC
                     EndIf
                  EndIf
               EndIf

            Case #ljDEC_VAR
               ; Check if variable is a pointer
               n = llObjects()\i
               If n >= 0 And n < gnLastVariable
                  searchKey = gVarMeta(n)\name
                  If FindMapElement(mapVariableTypes(), searchKey)
                     If mapVariableTypes() & #C2FLAG_POINTER
                        llObjects()\code = #ljPTRDEC
                     EndIf
                  EndIf
               EndIf

            Case #ljINC_VAR_PRE
               ; Check if variable is a pointer
               n = llObjects()\i
               If n >= 0 And n < gnLastVariable
                  searchKey = gVarMeta(n)\name
                  If FindMapElement(mapVariableTypes(), searchKey)
                     If mapVariableTypes() & #C2FLAG_POINTER
                        llObjects()\code = #ljPTRINC_PRE
                     EndIf
                  EndIf
               EndIf

            Case #ljDEC_VAR_PRE
               ; Check if variable is a pointer
               n = llObjects()\i
               If n >= 0 And n < gnLastVariable
                  searchKey = gVarMeta(n)\name
                  If FindMapElement(mapVariableTypes(), searchKey)
                     If mapVariableTypes() & #C2FLAG_POINTER
                        llObjects()\code = #ljPTRDEC_PRE
                     EndIf
                  EndIf
               EndIf

            Case #ljINC_VAR_POST
               ; Check if variable is a pointer
               n = llObjects()\i
               If n >= 0 And n < gnLastVariable
                  searchKey = gVarMeta(n)\name
                  If FindMapElement(mapVariableTypes(), searchKey)
                     If mapVariableTypes() & #C2FLAG_POINTER
                        llObjects()\code = #ljPTRINC_POST
                     EndIf
                  EndIf
               EndIf

            Case #ljDEC_VAR_POST
               ; Check if variable is a pointer
               n = llObjects()\i
               If n >= 0 And n < gnLastVariable
                  searchKey = gVarMeta(n)\name
                  If FindMapElement(mapVariableTypes(), searchKey)
                     If mapVariableTypes() & #C2FLAG_POINTER
                        llObjects()\code = #ljPTRDEC_POST
                     EndIf
                  EndIf
               EndIf

            ; V1.20.36: Also handle local increment/decrement on pointers
            Case #ljLINC_VAR
               ; Check if local variable is a pointer
               n = llObjects()\i
               If n >= 0 And n < gnLastVariable
                  searchKey = gVarMeta(n)\name
                  CompilerIf #DEBUG
                     Debug "      [PASS2 LINC_VAR] Looking up variable '" + searchKey + "' (idx=" + Str(n) + ")"
                  CompilerEndIf
                  If FindMapElement(mapVariableTypes(), searchKey)
                     CompilerIf #DEBUG
                        Debug "        Found in map, flags=" + Str(mapVariableTypes())
                     CompilerEndIf
                     If mapVariableTypes() & #C2FLAG_POINTER
                        llObjects()\code = #ljPTRINC
                        CompilerIf #DEBUG
                           Debug "        Converted LINC_VAR -> PTRINC"
                        CompilerEndIf
                     EndIf
                  Else
                     CompilerIf #DEBUG
                        Debug "        NOT found in map!"
                     CompilerEndIf
                  EndIf
               EndIf

            Case #ljLDEC_VAR
               ; Check if local variable is a pointer
               n = llObjects()\i
               If n >= 0 And n < gnLastVariable
                  searchKey = gVarMeta(n)\name
                  CompilerIf #DEBUG
                     Debug "      [PASS2 LDEC_VAR] Looking up variable '" + searchKey + "' (idx=" + Str(n) + ")"
                  CompilerEndIf
                  If FindMapElement(mapVariableTypes(), searchKey)
                     CompilerIf #DEBUG
                        Debug "        Found in map, flags=" + Str(mapVariableTypes())
                     CompilerEndIf
                     If mapVariableTypes() & #C2FLAG_POINTER
                        llObjects()\code = #ljPTRDEC
                        CompilerIf #DEBUG
                           Debug "        Converted LDEC_VAR -> PTRDEC"
                        CompilerEndIf
                     EndIf
                  Else
                     CompilerIf #DEBUG
                        Debug "        NOT found in map!"
                     CompilerEndIf
                  EndIf
               EndIf

            Case #ljLINC_VAR_PRE
               ; Check if local variable is a pointer
               n = llObjects()\i
               If n >= 0 And n < gnLastVariable
                  searchKey = gVarMeta(n)\name
                  If FindMapElement(mapVariableTypes(), searchKey)
                     If mapVariableTypes() & #C2FLAG_POINTER
                        llObjects()\code = #ljPTRINC_PRE
                     EndIf
                  EndIf
               EndIf

            Case #ljLDEC_VAR_PRE
               ; Check if local variable is a pointer
               n = llObjects()\i
               If n >= 0 And n < gnLastVariable
                  searchKey = gVarMeta(n)\name
                  If FindMapElement(mapVariableTypes(), searchKey)
                     If mapVariableTypes() & #C2FLAG_POINTER
                        llObjects()\code = #ljPTRDEC_PRE
                     EndIf
                  EndIf
               EndIf

            Case #ljLINC_VAR_POST
               ; Check if local variable is a pointer
               n = llObjects()\i
               If n >= 0 And n < gnLastVariable
                  searchKey = gVarMeta(n)\name
                  If FindMapElement(mapVariableTypes(), searchKey)
                     If mapVariableTypes() & #C2FLAG_POINTER
                        llObjects()\code = #ljPTRINC_POST
                     EndIf
                  EndIf
               EndIf

            Case #ljLDEC_VAR_POST
               ; Check if local variable is a pointer
               n = llObjects()\i
               If n >= 0 And n < gnLastVariable
                  searchKey = gVarMeta(n)\name
                  If FindMapElement(mapVariableTypes(), searchKey)
                     If mapVariableTypes() & #C2FLAG_POINTER
                        llObjects()\code = #ljPTRDEC_POST
                     EndIf
                  EndIf
               EndIf

            ; V1.20.37: Convert ADD/SUB on pointers to pointer arithmetic
            Case #ljADD
               ; Check if previous instruction fetched a pointer
               ; Pattern: FETCH/LFETCH/PFETCH ptr, PUSH/FETCH offset, ADD → becomes PTRADD
               CompilerIf #DEBUG
                  Debug "      [PASS2 ADD] Checking for pointer arithmetic pattern"
               CompilerEndIf
               If PreviousElement(llObjects())
                  ; Skip the PUSH/FETCH (offset value)
                  If llObjects()\code = #ljPush Or llObjects()\code = #ljFetch Or llObjects()\code = #ljLFETCH Or llObjects()\code = #ljPFETCH
                     If PreviousElement(llObjects())
                        ; Check if this FETCH is loading a pointer
                        If llObjects()\code = #ljFetch Or llObjects()\code = #ljLFETCH Or llObjects()\code = #ljPFETCH
                           n = llObjects()\i
                           If n >= 0 And n < gnLastVariable
                              searchKey = gVarMeta(n)\name
                              CompilerIf #DEBUG
                                 Debug "        Looking up variable '" + searchKey + "' (idx=" + Str(n) + ")"
                              CompilerEndIf
                              If FindMapElement(mapVariableTypes(), searchKey)
                                 CompilerIf #DEBUG
                                    Debug "          Found in map, flags=" + Str(mapVariableTypes())
                                 CompilerEndIf
                                 If mapVariableTypes() & #C2FLAG_POINTER
                                    ; Found pointer arithmetic pattern - convert ADD to PTRADD
                                    CompilerIf #DEBUG
                                       Debug "          Converting ADD -> PTRADD"
                                    CompilerEndIf
                                    NextElement(llObjects())  ; Move to offset
                                    NextElement(llObjects())  ; Move to ADD
                                    llObjects()\code = #ljPTRADD
                                    PreviousElement(llObjects())
                                    PreviousElement(llObjects())
                                 Else
                                    CompilerIf #DEBUG
                                       Debug "          Variable is not a pointer"
                                    CompilerEndIf
                                    NextElement(llObjects())
                                    NextElement(llObjects())
                                 EndIf
                              Else
                                 CompilerIf #DEBUG
                                    Debug "          NOT found in map!"
                                 CompilerEndIf
                                 NextElement(llObjects())
                                 NextElement(llObjects())
                              EndIf
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

            Case #ljSUBTRACT
               ; Check if previous instruction fetched a pointer
               ; Pattern: FETCH/LFETCH/PFETCH ptr, PUSH/FETCH offset, SUB → becomes PTRSUB
               If PreviousElement(llObjects())
                  ; Skip the PUSH/FETCH (offset value)
                  If llObjects()\code = #ljPush Or llObjects()\code = #ljFetch Or llObjects()\code = #ljLFETCH Or llObjects()\code = #ljPFETCH
                     If PreviousElement(llObjects())
                        ; Check if this FETCH is loading a pointer
                        If llObjects()\code = #ljFetch Or llObjects()\code = #ljLFETCH Or llObjects()\code = #ljPFETCH
                           n = llObjects()\i
                           If n >= 0 And n < gnLastVariable
                              searchKey = gVarMeta(n)\name
                              If FindMapElement(mapVariableTypes(), searchKey)
                                 If mapVariableTypes() & #C2FLAG_POINTER
                                    ; Found pointer arithmetic pattern - convert SUB to PTRSUB
                                    NextElement(llObjects())  ; Move to offset
                                    NextElement(llObjects())  ; Move to SUB
                                    llObjects()\code = #ljPTRSUB
                                    PreviousElement(llObjects())
                                    PreviousElement(llObjects())
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

            Case #ljPRTI
               ; Check if print should use different type
               ; Look back to find what's being printed (previous FETCH/PUSH)
               If PreviousElement(llObjects())
                  If llObjects()\code = #ljPTRFETCH_FLOAT
                     ; Float pointer fetch - change to PRTF
                     NextElement(llObjects())
                     llObjects()\code = #ljPRTF
                     PreviousElement(llObjects())
                  ElseIf llObjects()\code = #ljPTRFETCH_STR
                     ; String pointer fetch - change to PRTS
                     NextElement(llObjects())
                     llObjects()\code = #ljPRTS
                     PreviousElement(llObjects())
                  ElseIf llObjects()\code = #ljFETCHF Or llObjects()\code = #ljPUSHF Or llObjects()\code = #ljLFETCHF
                     ; Typed float fetch/push - change to PRTF
                     NextElement(llObjects())
                     llObjects()\code = #ljPRTF
                     PreviousElement(llObjects())
                  ElseIf llObjects()\code = #ljFETCHS Or llObjects()\code = #ljPUSHS Or llObjects()\code = #ljLFETCHS
                     ; Typed string fetch/push - change to PRTS
                     NextElement(llObjects())
                     llObjects()\code = #ljPRTS
                     PreviousElement(llObjects())
                  ElseIf llObjects()\code = #ljFetch Or llObjects()\code = #ljPush
                     n = llObjects()\i
                     If n >= 0 And n < gnLastVariable
                        If gVarMeta(n)\flags & #C2FLAG_FLOAT
                           NextElement(llObjects())  ; Move back to PRTI
                           llObjects()\code = #ljPRTF
                           PreviousElement(llObjects())  ; Stay positioned
                        ElseIf gVarMeta(n)\flags & #C2FLAG_STR
                           NextElement(llObjects())  ; Move back to PRTI
                           llObjects()\code = #ljPRTS
                           PreviousElement(llObjects())
                        EndIf
                     EndIf
                  ElseIf llObjects()\code = #ljFLOATADD Or llObjects()\code = #ljFLOATSUB Or
                         llObjects()\code = #ljFLOATMUL Or llObjects()\code = #ljFLOATDIV Or
                         llObjects()\code = #ljFLOATNEG
                     ; Float operations always produce float results
                     NextElement(llObjects())  ; Move back to PRTI
                     llObjects()\code = #ljPRTF
                     PreviousElement(llObjects())  ; Stay positioned
                  ; Check if previous operation is a string operation
                  ElseIf llObjects()\code = #ljSTRADD
                     ; String operations always produce string results
                     NextElement(llObjects())  ; Move back to PRTI
                     llObjects()\code = #ljPRTS
                     PreviousElement(llObjects())  ; Stay positioned
                  ; Check if previous operation is an array fetch
                  ElseIf llObjects()\code = #ljARRAYFETCH_FLOAT Or
                         llObjects()\code = #ljARRAYFETCH_FLOAT_GLOBAL_OPT Or
                         llObjects()\code = #ljARRAYFETCH_FLOAT_GLOBAL_STACK Or
                         llObjects()\code = #ljARRAYFETCH_FLOAT_LOCAL_OPT Or
                         llObjects()\code = #ljARRAYFETCH_FLOAT_LOCAL_STACK
                     ; Float array fetch - change to PRTF
                     NextElement(llObjects())  ; Move back to PRTI
                     llObjects()\code = #ljPRTF
                     PreviousElement(llObjects())  ; Stay positioned
                  ElseIf llObjects()\code = #ljARRAYFETCH_STR Or
                         llObjects()\code = #ljARRAYFETCH_STR_GLOBAL_OPT Or
                         llObjects()\code = #ljARRAYFETCH_STR_GLOBAL_STACK Or
                         llObjects()\code = #ljARRAYFETCH_STR_LOCAL_OPT Or
                         llObjects()\code = #ljARRAYFETCH_STR_LOCAL_STACK
                     ; String array fetch - change to PRTS
                     NextElement(llObjects())  ; Move back to PRTI
                     llObjects()\code = #ljPRTS
                     PreviousElement(llObjects())  ; Stay positioned
                  EndIf
                  NextElement(llObjects())  ; Return to PRTI position
               EndIf
               
            Case #ljPRTF
               ; Check if float print is actually int/string
               If PreviousElement(llObjects())
                  If llObjects()\code = #ljFetch Or llObjects()\code = #ljPush
                     n = llObjects()\i
                     If n >= 0 And n < gnLastVariable
                        If gVarMeta(n)\flags & #C2FLAG_INT
                           NextElement(llObjects())
                           llObjects()\code = #ljPRTI
                           PreviousElement(llObjects())
                        ElseIf gVarMeta(n)\flags & #C2FLAG_STR
                           NextElement(llObjects())
                           llObjects()\code = #ljPRTS
                           PreviousElement(llObjects())
                        EndIf
                     EndIf
                  ElseIf llObjects()\code = #ljARRAYFETCH_INT Or
                         llObjects()\code = #ljARRAYFETCH_INT_GLOBAL_OPT Or
                         llObjects()\code = #ljARRAYFETCH_INT_GLOBAL_STACK Or
                         llObjects()\code = #ljARRAYFETCH_INT_LOCAL_OPT Or
                         llObjects()\code = #ljARRAYFETCH_INT_LOCAL_STACK
                     ; Integer array fetch - change to PRTI
                     NextElement(llObjects())
                     llObjects()\code = #ljPRTI
                     PreviousElement(llObjects())
                  ElseIf llObjects()\code = #ljARRAYFETCH_STR Or
                         llObjects()\code = #ljARRAYFETCH_STR_GLOBAL_OPT Or
                         llObjects()\code = #ljARRAYFETCH_STR_GLOBAL_STACK Or
                         llObjects()\code = #ljARRAYFETCH_STR_LOCAL_OPT Or
                         llObjects()\code = #ljARRAYFETCH_STR_LOCAL_STACK
                     ; String array fetch - change to PRTS
                     NextElement(llObjects())
                     llObjects()\code = #ljPRTS
                     PreviousElement(llObjects())
                  EndIf
                  NextElement(llObjects())
               EndIf
               
            Case #ljPRTS
               ; Check if string print is actually int/float
               If PreviousElement(llObjects())
                  If llObjects()\code = #ljFetch Or llObjects()\code = #ljPush
                     n = llObjects()\i
                     If n >= 0 And n < gnLastVariable
                        If gVarMeta(n)\flags & #C2FLAG_INT
                           NextElement(llObjects())
                           llObjects()\code = #ljPRTI
                           PreviousElement(llObjects())
                        ElseIf gVarMeta(n)\flags & #C2FLAG_FLOAT
                           NextElement(llObjects())
                           llObjects()\code = #ljPRTF
                           PreviousElement(llObjects())
                        EndIf
                     EndIf
                  ElseIf llObjects()\code = #ljARRAYFETCH_INT Or
                         llObjects()\code = #ljARRAYFETCH_INT_GLOBAL_OPT Or
                         llObjects()\code = #ljARRAYFETCH_INT_GLOBAL_STACK Or
                         llObjects()\code = #ljARRAYFETCH_INT_LOCAL_OPT Or
                         llObjects()\code = #ljARRAYFETCH_INT_LOCAL_STACK
                     ; Integer array fetch - change to PRTI
                     NextElement(llObjects())
                     llObjects()\code = #ljPRTI
                     PreviousElement(llObjects())
                  ElseIf llObjects()\code = #ljARRAYFETCH_FLOAT Or
                         llObjects()\code = #ljARRAYFETCH_FLOAT_GLOBAL_OPT Or
                         llObjects()\code = #ljARRAYFETCH_FLOAT_GLOBAL_STACK Or
                         llObjects()\code = #ljARRAYFETCH_FLOAT_LOCAL_OPT Or
                         llObjects()\code = #ljARRAYFETCH_FLOAT_LOCAL_STACK
                     ; Float array fetch - change to PRTF
                     NextElement(llObjects())
                     llObjects()\code = #ljPRTF
                     PreviousElement(llObjects())
                  EndIf
                  NextElement(llObjects())
               EndIf
         EndSelect
      Next

      CompilerIf #DEBUG
         Debug "    Pass 3: Convert generic PTRFETCH to typed variants"
      CompilerEndIf

      ;- Pass 3: Convert generic PTRFETCH to typed variants (V1.20.34: renamed from Pass 0b)
      ; Track pointer types and convert PTRFETCH to PTRFETCH_INT/FLOAT/STR
      ; This fixes print type detection for pointer dereferences
      ForEach llObjects()
         If llObjects()\code = #ljPTRFETCH
            ; Look back to find FETCH instruction
            If PreviousElement(llObjects())
               If llObjects()\code = #ljFetch Or llObjects()\code = #ljFETCHF Or llObjects()\code = #ljFETCHS
                  varSlot = llObjects()\i
                  ; Scan backwards to find most recent GETADDR variant that stored to this variable
                  ; Pattern: GETADDR[F|S], then STORE/POP to varSlot
                  savedPos = @llObjects()
                  foundGetAddr = #False
                  isArrayPointer = #False
                  getAddrType = #ljGETADDR  ; Default to int

                  While PreviousElement(llObjects())
                     If (llObjects()\code = #ljStore Or llObjects()\code = #ljPOP) And llObjects()\i = varSlot
                        ; Found store to our variable - check if previous instruction is GETADDR
                        If PreviousElement(llObjects())
                           If llObjects()\code = #ljGETADDR Or llObjects()\code = #ljGETADDRF Or llObjects()\code = #ljGETADDRS
                              getAddrType = llObjects()\code
                              foundGetAddr = #True
                              Break
                           ElseIf llObjects()\code = #ljGETARRAYADDR Or llObjects()\code = #ljGETARRAYADDRF Or llObjects()\code = #ljGETARRAYADDRS
                              ; Array pointer - leave PTRFETCH generic (uses function pointers)
                              ; Don't convert to typed variant because array pointers need peek/poke functions
                              isArrayPointer = #True
                              Break
                           ElseIf llObjects()\code = #ljPTRADD Or llObjects()\code = #ljPTRSUB
                              ; Pointer arithmetic - result is also an array pointer, keep generic
                              ; The source pointer was an array element pointer, so result is too
                              isArrayPointer = #True
                              Break
                           Else
                              NextElement(llObjects())  ; Back to STORE
                           EndIf
                        Else
                           Break  ; Can't go back further
                        EndIf
                     EndIf
                  Wend

                  ; Restore position to PTRFETCH
                  ChangeCurrentElement(llObjects(), savedPos)
                  NextElement(llObjects())  ; Move from FETCH to PTRFETCH

                  ; Convert PTRFETCH based on what we found
                  If isArrayPointer
                     ; Leave as generic PTRFETCH for array pointers (need function pointers)
                     ; Do nothing - keep as #ljPTRFETCH
                  ElseIf foundGetAddr
                     ; Found regular variable pointer - convert to typed variant
                     Select getAddrType
                        Case #ljGETADDRF
                           llObjects()\code = #ljPTRFETCH_FLOAT
                        Case #ljGETADDRS
                           llObjects()\code = #ljPTRFETCH_STR
                        Default
                           llObjects()\code = #ljPTRFETCH_INT
                     EndSelect
                  Else
                     ; Couldn't find GETADDR - default to int variant
                     llObjects()\code = #ljPTRFETCH_INT
                  EndIf
               Else
                  NextElement(llObjects())  ; Back to PTRFETCH
               EndIf
            EndIf
         EndIf
      Next

      ;- Pass 4 and 5: REMOVED (V1.20.34)
      ; Arrays of pointers now preserve full pointer metadata (peekfn/pokefn)
      ; via CopyStructure in generic ARRAYFETCH/ARRAYSTORE operations.
      ; Generic PTRFETCH/PTRSTORE use this metadata for correct dereferencing.
      ; This allows arrays to hold mixed pointer types (int, float, string, array elements)

      CompilerIf #DEBUG
         Debug "    Pass 6: Fix print types after PTRFETCH typing"
      CompilerEndIf

      ;- Pass 6: Fix print types after PTRFETCH typing (V1.20.34: renamed from Pass 0c)
      ; Now that PTRFETCH is typed, fix PRTI that follow typed PTRFETCH
      ForEach llObjects()
         If llObjects()\code = #ljPRTI
            If PreviousElement(llObjects())
               If llObjects()\code = #ljPTRFETCH_FLOAT
                  NextElement(llObjects())
                  llObjects()\code = #ljPRTF
                  PreviousElement(llObjects())
               ElseIf llObjects()\code = #ljPTRFETCH_STR
                  NextElement(llObjects())
                  llObjects()\code = #ljPRTS
                  PreviousElement(llObjects())
               EndIf
               NextElement(llObjects())
            EndIf
         EndIf
      Next

      ;- Pass 7: DISABLED (V1.20.34)
      ; Fix print types for array pointer PTRFETCH (generic)
      ; DISABLED: Replaced by Pass 8 which uses PRTPTR for all generic PTRFETCH cases
      ; This allows arrays of mixed pointer types to work correctly

      CompilerIf #DEBUG
         Debug "    Pass 8: Use PRTPTR after generic PTRFETCH"
      CompilerEndIf

      ;- Pass 8: Use PRTPTR after generic PTRFETCH (V1.20.34: renamed from Pass 0e)
      ; For generic PTRFETCH (not typed variants), convert any following print to PRTPTR
      ; This handles arrays of mixed pointer types where we can't determine type statically
      ; PRTPTR examines ptrtype field at runtime to print the correct field
      ForEach llObjects()
         If llObjects()\code = #ljPRTI Or llObjects()\code = #ljPRTF Or llObjects()\code = #ljPRTS
            ; Check if previous instruction is generic PTRFETCH
            If PreviousElement(llObjects())
               If llObjects()\code = #ljPTRFETCH
                  ; Generic PTRFETCH followed by print - convert to PRTPTR
                  NextElement(llObjects())
                  llObjects()\code = #ljPRTPTR
                  PreviousElement(llObjects())
               EndIf
               NextElement(llObjects())
            EndIf
         EndIf
      Next

      ;- ==================================================================
      ;- Enhanced Instruction Fusion Optimizations (backward compatible)
      ;- ==================================================================

      ; Check if optimizations are enabled (default ON)
      optimizationsEnabled = #True
      If FindMapElement(mapPragmas(), "optimizecode")
         If LCase(mapPragmas()) = "off" Or mapPragmas() = "0"
            optimizationsEnabled = #False
         EndIf
      EndIf

      If optimizationsEnabled
      CompilerIf #DEBUG
         Debug "    Pass 9: Array index optimization"
      CompilerEndIf

      ;- Pass 9: Array index optimization (V1.20.34: renamed from Pass 1a)
      ; PUSH var/const + ARRAYFETCH/STORE → move index to ndx field
      ForEach llObjects()
         Select llObjects()\code
            Case #ljARRAYFETCH, #ljARRAYSTORE
               ; ndx < 0 means index is on stack (codegen always emits ndx=-1)
               If llObjects()\ndx < 0
                  ; Check if previous instruction is PUSH (of any variable or constant)
                  If PreviousElement(llObjects())
                     If (llObjects()\code = #ljPush Or llObjects()\code = #ljPUSHF Or llObjects()\code = #ljPUSHS)
                        ; Get the variable/constant index
                        indexVarSlot = llObjects()\i
                        NextElement(llObjects())  ; Back to ARRAYFETCH/ARRAYSTORE

                        ; Store variable slot in ndx field (ndx >= 0 signals optimization)
                        llObjects()\ndx = indexVarSlot

                        ; Mark PUSH as NOOP
                        PreviousElement(llObjects())
                        llObjects()\code = #ljNOOP
                        AdjustJumpsForNOOP(ListIndex(llObjects()))  ; V1.020.074: Adjust tracked jumps
                        NextElement(llObjects())
                     Else
                        NextElement(llObjects())
                     EndIf
                  EndIf
               EndIf
         EndSelect
      Next

      CompilerIf #DEBUG
         Debug "    Pass 10: Type array operations based on array metadata"
      CompilerEndIf

      ;- Pass 10: Type array operations based on array metadata (V1.20.34: renamed from Pass 1b)
      ForEach llObjects()
         Select llObjects()\code
            Case #ljARRAYFETCH, #ljARRAYSTORE
               ; Get varSlot from n field (codegen stores it there for typing)
               varSlot = llObjects()\n
               isFetch = Bool(llObjects()\code = #ljARRAYFETCH)

               ; Type the operation based on array's type flags
               If gVarMeta(varSlot)\flags & #C2FLAG_STR
                  If isFetch
                     llObjects()\code = #ljARRAYFETCH_STR
                  Else
                     llObjects()\code = #ljARRAYSTORE_STR
                  EndIf
               ElseIf gVarMeta(varSlot)\flags & #C2FLAG_FLOAT
                  If isFetch
                     llObjects()\code = #ljARRAYFETCH_FLOAT
                  Else
                     llObjects()\code = #ljARRAYSTORE_FLOAT
                  EndIf
               Else
                  If isFetch
                     llObjects()\code = #ljARRAYFETCH_INT
                  Else
                     llObjects()\code = #ljARRAYSTORE_INT
                  EndIf
               EndIf
         EndSelect
      Next

      CompilerIf #DEBUG
         Debug "    Pass 11: Fold value PUSH into ARRAYSTORE"
      CompilerEndIf

      ;- Pass 11: Fold value PUSH into ARRAYSTORE (V1.20.34: renamed from Pass 1b2)
      ; Optimize: PUSH value + ARRAYSTORE → ARRAYSTORE with value in n field
      ; Since typing is complete, we can repurpose the n field to hold the value slot
      ; If not optimized, set n = -1 to signal VM to use stack
      ForEach llObjects()
         Select llObjects()\code
            Case #ljARRAYSTORE_INT, #ljARRAYSTORE_FLOAT, #ljARRAYSTORE_STR
               ; Check if previous instruction is PUSH (of value)
               optimized = #False
               If PreviousElement(llObjects())
                  If (llObjects()\code = #ljPush Or llObjects()\code = #ljPUSHF Or llObjects()\code = #ljPUSHS)
                     ; Get the value variable/constant slot
                     valueSlot = llObjects()\i
                     NextElement(llObjects())  ; Back to ARRAYSTORE

                     ; Store value slot in n field (repurposing after typing complete)
                     ; n field is now used by VM to fetch value directly instead of from stack
                     llObjects()\n = valueSlot
                     optimized = #True

                     ; Mark PUSH as NOOP
                     PreviousElement(llObjects())
                     llObjects()\code = #ljNOOP
                     AdjustJumpsForNOOP(ListIndex(llObjects()))  ; V1.020.074: Adjust tracked jumps
                     NextElement(llObjects())
                  Else
                     NextElement(llObjects())
                  EndIf
               EndIf

               ; If not optimized, set n = -1 to signal VM to use stack for value
               If Not optimized
                  llObjects()\n = -1
               EndIf
         EndSelect
      Next

      CompilerIf #DEBUG
         Debug "    Pass 12: Specialize array opcodes to eliminate runtime branching"
      CompilerEndIf

      ;- Pass 12: Specialize array opcodes to eliminate runtime branching (V1.20.34: renamed from Pass 1b3)
      ; Convert typed opcodes to fully specialized variants based on:
      ; - j field: 0=GLOBAL, 1=LOCAL
      ; - ndx field: >=0=OPT, -1=STACK
      ; - n field (STORE only): >=0=OPT, -1=STACK
      ForEach llObjects()
         Select llObjects()\code
            ; ARRAYFETCH specialization
            Case #ljARRAYFETCH_INT
               If llObjects()\j = 0  ; Global
                  If llObjects()\ndx >= 0
                     llObjects()\code = #ljARRAYFETCH_INT_GLOBAL_OPT
                  Else
                     llObjects()\code = #ljARRAYFETCH_INT_GLOBAL_STACK
                  EndIf
               Else  ; Local
                  If llObjects()\ndx >= 0
                     llObjects()\code = #ljARRAYFETCH_INT_LOCAL_OPT
                  Else
                     llObjects()\code = #ljARRAYFETCH_INT_LOCAL_STACK
                  EndIf
               EndIf

            Case #ljARRAYFETCH_FLOAT
               If llObjects()\j = 0  ; Global
                  If llObjects()\ndx >= 0
                     llObjects()\code = #ljARRAYFETCH_FLOAT_GLOBAL_OPT
                  Else
                     llObjects()\code = #ljARRAYFETCH_FLOAT_GLOBAL_STACK
                  EndIf
               Else  ; Local
                  If llObjects()\ndx >= 0
                     llObjects()\code = #ljARRAYFETCH_FLOAT_LOCAL_OPT
                  Else
                     llObjects()\code = #ljARRAYFETCH_FLOAT_LOCAL_STACK
                  EndIf
               EndIf

            Case #ljARRAYFETCH_STR
               If llObjects()\j = 0  ; Global
                  If llObjects()\ndx >= 0
                     llObjects()\code = #ljARRAYFETCH_STR_GLOBAL_OPT
                  Else
                     llObjects()\code = #ljARRAYFETCH_STR_GLOBAL_STACK
                  EndIf
               Else  ; Local
                  If llObjects()\ndx >= 0
                     llObjects()\code = #ljARRAYFETCH_STR_LOCAL_OPT
                  Else
                     llObjects()\code = #ljARRAYFETCH_STR_LOCAL_STACK
                  EndIf
               EndIf

            ; ARRAYSTORE specialization (3 dimensions: global/local, index source, value source)
            Case #ljARRAYSTORE_INT
               If llObjects()\j = 0  ; Global
                  If llObjects()\ndx >= 0  ; Optimized index
                     If llObjects()\n >= 0  ; Optimized value
                        llObjects()\code = #ljARRAYSTORE_INT_GLOBAL_OPT_OPT
                     Else  ; Stack value
                        llObjects()\code = #ljARRAYSTORE_INT_GLOBAL_OPT_STACK
                     EndIf
                  Else  ; Stack index
                     If llObjects()\n >= 0  ; Optimized value
                        llObjects()\code = #ljARRAYSTORE_INT_GLOBAL_STACK_OPT
                     Else  ; Stack value
                        llObjects()\code = #ljARRAYSTORE_INT_GLOBAL_STACK_STACK
                     EndIf
                  EndIf
               Else  ; Local
                  If llObjects()\ndx >= 0  ; Optimized index
                     If llObjects()\n >= 0  ; Optimized value
                        llObjects()\code = #ljARRAYSTORE_INT_LOCAL_OPT_OPT
                     Else  ; Stack value
                        llObjects()\code = #ljARRAYSTORE_INT_LOCAL_OPT_STACK
                     EndIf
                  Else  ; Stack index
                     If llObjects()\n >= 0  ; Optimized value
                        llObjects()\code = #ljARRAYSTORE_INT_LOCAL_STACK_OPT
                     Else  ; Stack value
                        llObjects()\code = #ljARRAYSTORE_INT_LOCAL_STACK_STACK
                     EndIf
                  EndIf
               EndIf

            Case #ljARRAYSTORE_FLOAT
               If llObjects()\j = 0  ; Global
                  If llObjects()\ndx >= 0  ; Optimized index
                     If llObjects()\n >= 0  ; Optimized value
                        llObjects()\code = #ljARRAYSTORE_FLOAT_GLOBAL_OPT_OPT
                     Else  ; Stack value
                        llObjects()\code = #ljARRAYSTORE_FLOAT_GLOBAL_OPT_STACK
                     EndIf
                  Else  ; Stack index
                     If llObjects()\n >= 0  ; Optimized value
                        llObjects()\code = #ljARRAYSTORE_FLOAT_GLOBAL_STACK_OPT
                     Else  ; Stack value
                        llObjects()\code = #ljARRAYSTORE_FLOAT_GLOBAL_STACK_STACK
                     EndIf
                  EndIf
               Else  ; Local
                  If llObjects()\ndx >= 0  ; Optimized index
                     If llObjects()\n >= 0  ; Optimized value
                        llObjects()\code = #ljARRAYSTORE_FLOAT_LOCAL_OPT_OPT
                     Else  ; Stack value
                        llObjects()\code = #ljARRAYSTORE_FLOAT_LOCAL_OPT_STACK
                     EndIf
                  Else  ; Stack index
                     If llObjects()\n >= 0  ; Optimized value
                        llObjects()\code = #ljARRAYSTORE_FLOAT_LOCAL_STACK_OPT
                     Else  ; Stack value
                        llObjects()\code = #ljARRAYSTORE_FLOAT_LOCAL_STACK_STACK
                     EndIf
                  EndIf
               EndIf

            Case #ljARRAYSTORE_STR
               If llObjects()\j = 0  ; Global
                  If llObjects()\ndx >= 0  ; Optimized index
                     If llObjects()\n >= 0  ; Optimized value
                        llObjects()\code = #ljARRAYSTORE_STR_GLOBAL_OPT_OPT
                     Else  ; Stack value
                        llObjects()\code = #ljARRAYSTORE_STR_GLOBAL_OPT_STACK
                     EndIf
                  Else  ; Stack index
                     If llObjects()\n >= 0  ; Optimized value
                        llObjects()\code = #ljARRAYSTORE_STR_GLOBAL_STACK_OPT
                     Else  ; Stack value
                        llObjects()\code = #ljARRAYSTORE_STR_GLOBAL_STACK_STACK
                     EndIf
                  EndIf
               Else  ; Local
                  If llObjects()\ndx >= 0  ; Optimized index
                     If llObjects()\n >= 0  ; Optimized value
                        llObjects()\code = #ljARRAYSTORE_STR_LOCAL_OPT_OPT
                     Else  ; Stack value
                        llObjects()\code = #ljARRAYSTORE_STR_LOCAL_OPT_STACK
                     EndIf
                  Else  ; Stack index
                     If llObjects()\n >= 0  ; Optimized value
                        llObjects()\code = #ljARRAYSTORE_STR_LOCAL_STACK_OPT
                     Else  ; Stack value
                        llObjects()\code = #ljARRAYSTORE_STR_LOCAL_STACK_STACK
                     EndIf
                  EndIf
               EndIf
         EndSelect
      Next

      CompilerIf #DEBUG
         Debug "    Pass 13: Add implicit returns to functions without explicit returns"
      CompilerEndIf

      ;- Pass 13: Add implicit returns to functions without explicit returns (V1.20.34: renamed from Pass 1c)
      ; Scan for function boundaries and ensure each has a RET before next function/HALT
      ForEach llObjects()
         If llObjects()\code = #ljFunction
            ; Found a function start, scan forward to find where it ends
            needsReturn = #True
            savedPos = @llObjects()
            foundEnd = #False

            While NextElement(llObjects())
               ; Check if we hit another function or HALT
               If llObjects()\code = #ljFunction Or llObjects()\code = #ljHALT
                  ; End of current function - check if previous instruction was RET
                  If needsReturn
                     ; Insert RET before FUNCTION/HALT marker (after last instruction of function)
                     ; Do NOT use PreviousElement - insert directly before current element
                     InsertElement(llObjects())
                     llObjects()\code = #ljreturn
                     llObjects()\i = 0
                     llObjects()\j = 0
                     llObjects()\n = 0
                     llObjects()\ndx = -1
                     NextElement(llObjects())  ; Move back to function/HALT
                  EndIf
                  foundEnd = #True
                  Break
               EndIf

               ; Check if current instruction is a return
               If llObjects()\code = #ljreturn Or llObjects()\code = #ljreturnF Or llObjects()\code = #ljreturnS
                  needsReturn = #False
               ElseIf llObjects()\code <> #ljNOOP
                  ; Non-NOOP instruction means we need to check again
                  needsReturn = #True
               EndIf
            Wend

            ; If we reached end of list without finding another function/HALT, add RET at end
            If Not foundEnd And needsReturn
               ; Position at last element, then add RET after it
               LastElement(llObjects())
               AddElement(llObjects())
               llObjects()\code = #ljreturn
               llObjects()\i = 0
               llObjects()\j = 0
               llObjects()\n = 0
               llObjects()\ndx = -1
            EndIf

            ; Restore position to continue scanning
            ChangeCurrentElement(llObjects(), savedPos)
         EndIf
      Next

      CompilerIf #DEBUG
         Debug "    Pass 14: Redundant assignment elimination"
      CompilerEndIf

      ; Pass 14: Redundant assignment elimination (V1.20.34: renamed from Pass 2)
      ; x = x becomes NOP
      ; V1.020.050: Only eliminate FETCH+STORE, NOT PUSH+STORE (different index spaces!)
      ForEach llObjects()
         Select llObjects()\code
            Case #ljStore, #ljSTORES, #ljSTOREF
               ; Check if previous instruction fetches the same variable
               ; NOTE: PUSH opcodes reference constants in same index space as variables!
               ; We must NOT compare PUSH constant indices with STORE variable indices!
               If PreviousElement(llObjects())
                  If (llObjects()\code = #ljFetch Or llObjects()\code = #ljFETCHS Or
                      llObjects()\code = #ljFETCHF)
                     ; Only FETCH opcodes - these reference variables, safe to compare
                     fetchVar = llObjects()\i
                     NextElement(llObjects())  ; Back to STORE
                     If llObjects()\i = fetchVar
                        ; Redundant assignment: x = x
                        llObjects()\code = #ljNOOP
                        AdjustJumpsForNOOP(ListIndex(llObjects()))  ; V1.020.074: Adjust tracked jumps
                        PreviousElement(llObjects())
                        llObjects()\code = #ljNOOP
                        AdjustJumpsForNOOP(ListIndex(llObjects()))  ; V1.020.074: Adjust tracked jumps
                        NextElement(llObjects())
                     Else
                        ; Different variables, restore position
                     EndIf
                  Else
                     NextElement(llObjects())
                  EndIf
               EndIf
         EndSelect
      Next

      CompilerIf #DEBUG
         Debug "    Pass 15: Dead code elimination"
      CompilerEndIf

      ; Pass 15: Dead code elimination (V1.20.34: renamed from Pass 3)
      ; PUSH/FETCH followed immediately by POP
      ForEach llObjects()
         Select llObjects()\code
            Case #ljPOP, #ljPOPS, #ljPOPF
               ; Check if previous instruction is PUSH/FETCH
               If PreviousElement(llObjects())
                  If (llObjects()\code = #ljFetch Or llObjects()\code = #ljFETCHS Or
                      llObjects()\code = #ljFETCHF Or llObjects()\code = #ljPush Or
                      llObjects()\code = #ljPUSHS Or llObjects()\code = #ljPUSHF)
                     ; Dead code: value pushed then immediately popped
                     llObjects()\code = #ljNOOP
                     AdjustJumpsForNOOP(ListIndex(llObjects()))  ; V1.020.074: Adjust tracked jumps
                     NextElement(llObjects())  ; Back to POP
                     llObjects()\code = #ljNOOP
                     AdjustJumpsForNOOP(ListIndex(llObjects()))  ; V1.020.074: Adjust tracked jumps
                  Else
                     NextElement(llObjects())
                  EndIf
               EndIf
         EndSelect
      Next

      CompilerIf #DEBUG
         Debug "    Pass 16: Constant folding for integer arithmetic"
      CompilerEndIf

      ; Pass 16: Constant folding for integer arithmetic (V1.20.34: renamed from Pass 4)
      ForEach llObjects()
         Select llObjects()\code
            Case #ljADD, #ljSUBTRACT, #ljMULTIPLY, #ljDIVIDE, #ljMOD
               opCode = llObjects()\code
               ; Look back for two consecutive constant pushes
               If PreviousElement(llObjects())
                  If (llObjects()\code = #ljPush Or llObjects()\code = #ljPUSHF Or llObjects()\code = #ljPUSHS) And (gVarMeta( llObjects()\i )\flags & #C2FLAG_CONST)
                     const2 = gVarMeta( llObjects()\i )\valueInt
                     const2Idx = llObjects()\i
                     If PreviousElement(llObjects())
                        If (llObjects()\code = #ljPush Or llObjects()\code = #ljPUSHF Or llObjects()\code = #ljPUSHS) And (gVarMeta( llObjects()\i )\flags & #C2FLAG_CONST)
                           const1 = gVarMeta( llObjects()\i )\valueInt
                           canFold = #True

                           ; Compute the constant result
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
                                    canFold = #False  ; Don't fold division by zero
                                 EndIf
                              Case #ljMOD
                                 If const2 <> 0
                                    result = const1 % const2
                                 Else
                                    canFold = #False
                                 EndIf
                           EndSelect

                           If canFold
                              ; Create a new constant for the folded result
                              newConstIdx = gnLastVariable
                              ; Clear all fields first
                              gVarMeta(newConstIdx)\name = "$fold" + Str(newConstIdx)
                              gVarMeta(newConstIdx)\valueInt = result
                              gVarMeta(newConstIdx)\valueFloat = 0.0
                              gVarMeta(newConstIdx)\valueString = ""
                              gVarMeta(newConstIdx)\flags = #C2FLAG_CONST | #C2FLAG_INT
                              gVarMeta(newConstIdx)\paramOffset = -1  ; Constants don't need frame offsets
                              gnLastVariable + 1

                              ; Replace first PUSH with new constant, eliminate second PUSH and operation
                              llObjects()\i = newConstIdx
                              NextElement(llObjects())  ; Second PUSH
                              llObjects()\code = #ljNOOP
                              AdjustJumpsForNOOP(ListIndex(llObjects()))  ; V1.020.074: Adjust tracked jumps
                              NextElement(llObjects())  ; Operation
                              llObjects()\code = #ljNOOP
                              AdjustJumpsForNOOP(ListIndex(llObjects()))  ; V1.020.074: Adjust tracked jumps
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
         EndSelect
      Next

      CompilerIf #DEBUG
         Debug "    Pass 17: Constant folding for float arithmetic"
      CompilerEndIf

      ; Pass 17: Constant folding for float arithmetic (V1.20.34: renamed from Pass 4b)
      ForEach llObjects()
         Select llObjects()\code
            Case #ljFLOATADD, #ljFLOATSUB, #ljFLOATMUL, #ljFLOATDIV
               opCode = llObjects()\code
               ; Look back for two consecutive constant pushes
               If PreviousElement(llObjects())
                  If (llObjects()\code = #ljPUSHF Or llObjects()\code = #ljPush) And (gVarMeta( llObjects()\i )\flags & #C2FLAG_CONST)
                     const2fIdx = llObjects()\i
                     const2f = gVarMeta(const2fIdx)\valueFloat
                     If PreviousElement(llObjects())
                        If (llObjects()\code = #ljPUSHF Or llObjects()\code = #ljPush) And (gVarMeta( llObjects()\i )\flags & #C2FLAG_CONST)
                           const1f = gVarMeta(llObjects()\i)\valueFloat
                           canFold = #True

                           ; Compute the constant result
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
                                    canFold = #False  ; Don't fold division by zero
                                 EndIf
                           EndSelect

                           If canFold
                              ; Create a new constant for the folded result
                              newConstFIdx = gnLastVariable
                              ; Clear all fields first
                              gVarMeta(newConstFIdx)\name = "$ffold" + Str(newConstFIdx)
                              gVarMeta(newConstFIdx)\valueInt = 0
                              gVarMeta(newConstFIdx)\valueFloat = resultf
                              gVarMeta(newConstFIdx)\valueString = ""
                              gVarMeta(newConstFIdx)\flags = #C2FLAG_CONST | #C2FLAG_FLOAT
                              gVarMeta(newConstFIdx)\paramOffset = -1  ; Constants don't need frame offsets
                              gnLastVariable + 1

                              ; Replace first PUSH with new constant, eliminate second PUSH and STRADD
                              llObjects()\i = newConstFIdx
                              NextElement(llObjects())  ; Second PUSH
                              llObjects()\code = #ljNOOP
                              AdjustJumpsForNOOP(ListIndex(llObjects()))  ; V1.020.074: Adjust tracked jumps
                              NextElement(llObjects())  ; STRADD
                              llObjects()\code = #ljNOOP
                              AdjustJumpsForNOOP(ListIndex(llObjects()))  ; V1.020.074: Adjust tracked jumps
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
         EndSelect
      Next

      CompilerIf #DEBUG
         Debug "    Pass 18: Arithmetic identity optimizations"
      CompilerEndIf

      ; Pass 18: Arithmetic identity optimizations (V1.20.34: renamed from Pass 5)
      ForEach llObjects()
         Select llObjects()\code
            Case #ljADD
               ; x + 0 = x, eliminate ADD and the constant 0 push
               If PreviousElement(llObjects())
                  If (llObjects()\code = #ljPush Or llObjects()\code = #ljPUSHF Or llObjects()\code = #ljPUSHS) And (gVarMeta( llObjects()\i )\flags & #C2FLAG_CONST)
                     If gVarMeta( llObjects()\i )\valueInt = 0
                        llObjects()\code = #ljNOOP  ; Eliminate PUSH 0
                        AdjustJumpsForNOOP(ListIndex(llObjects()))  ; V1.020.074: Adjust tracked jumps
                        NextElement(llObjects())     ; Back to ADD
                        llObjects()\code = #ljNOOP  ; Eliminate ADD
                        AdjustJumpsForNOOP(ListIndex(llObjects()))  ; V1.020.074: Adjust tracked jumps
                     Else
                        NextElement(llObjects())
                     EndIf
                  Else
                     NextElement(llObjects())
                  EndIf
               EndIf

            Case #ljSUBTRACT
               ; x - 0 = x
               If PreviousElement(llObjects())
                  If (llObjects()\code = #ljPush Or llObjects()\code = #ljPUSHF Or llObjects()\code = #ljPUSHS) And (gVarMeta( llObjects()\i )\flags & #C2FLAG_CONST)
                     If gVarMeta( llObjects()\i )\valueInt = 0
                        llObjects()\code = #ljNOOP
                        AdjustJumpsForNOOP(ListIndex(llObjects()))  ; V1.020.074: Adjust tracked jumps
                        NextElement(llObjects())
                        llObjects()\code = #ljNOOP
                        AdjustJumpsForNOOP(ListIndex(llObjects()))  ; V1.020.074: Adjust tracked jumps
                     Else
                        NextElement(llObjects())
                     EndIf
                  Else
                     NextElement(llObjects())
                  EndIf
               EndIf

            Case #ljMULTIPLY
               ; x * 1 = x, x * 0 = 0
               If PreviousElement(llObjects())
                  If (llObjects()\code = #ljPush Or llObjects()\code = #ljPUSHF Or llObjects()\code = #ljPUSHS) And (gVarMeta( llObjects()\i )\flags & #C2FLAG_CONST)
                     mulConst = gVarMeta( llObjects()\i )\valueInt
                     If mulConst = 1
                        ; x * 1 = x, eliminate multiply and the constant
                        llObjects()\code = #ljNOOP
                        AdjustJumpsForNOOP(ListIndex(llObjects()))  ; V1.020.074: Adjust tracked jumps
                        NextElement(llObjects())
                        llObjects()\code = #ljNOOP
                        AdjustJumpsForNOOP(ListIndex(llObjects()))  ; V1.020.074: Adjust tracked jumps
                     ElseIf mulConst = 0
                        ; x * 0 = 0, keep the PUSH 0 but eliminate value below and multiply
                        ; This requires looking back 2 instructions
                        If PreviousElement(llObjects())
                           llObjects()\code = #ljNOOP  ; Eliminate the x value
                           AdjustJumpsForNOOP(ListIndex(llObjects()))  ; V1.020.074: Adjust tracked jumps
                           NextElement(llObjects())     ; Back to PUSH 0
                           NextElement(llObjects())     ; To MULTIPLY
                           llObjects()\code = #ljNOOP  ; Eliminate MULTIPLY
                           AdjustJumpsForNOOP(ListIndex(llObjects()))  ; V1.020.074: Adjust tracked jumps
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

            Case #ljDIVIDE
               ; x / 1 = x
               If PreviousElement(llObjects())
                  If (llObjects()\code = #ljPush Or llObjects()\code = #ljPUSHF Or llObjects()\code = #ljPUSHS) And (gVarMeta( llObjects()\i )\flags & #C2FLAG_CONST)
                     If gVarMeta( llObjects()\i )\valueInt = 1
                        llObjects()\code = #ljNOOP
                        NextElement(llObjects())
                        llObjects()\code = #ljNOOP
                     Else
                        NextElement(llObjects())
                     EndIf
                  Else
                     NextElement(llObjects())
                  EndIf
               EndIf
         EndSelect
      Next

      CompilerIf #DEBUG
         Debug "    Pass 19: String identity optimization"
      CompilerEndIf

      ;- Pass 19: String identity optimization (V1.20.34: renumbered from Pass 7) (str + "" â†’ str)
      ForEach llObjects()
         If llObjects()\code = #ljSTRADD
            ; Check if previous instruction is PUSHS with empty string
            If PreviousElement(llObjects())
               If llObjects()\code = #ljPUSHS Or llObjects()\code = #ljPush
                  strIdx = llObjects()\i
                  If (gVarMeta(strIdx)\flags & #C2FLAG_STR) And gVarMeta(strIdx)\valueString = ""
                     ; Empty string found - eliminate it and STRADD
                     llObjects()\code = #ljNOOP
                     NextElement(llObjects())  ; Back to STRADD
                     llObjects()\code = #ljNOOP
                  Else
                     NextElement(llObjects())
                  EndIf
               Else
                  NextElement(llObjects())
               EndIf
            EndIf
         EndIf
      Next

      CompilerIf #DEBUG
         Debug "    Pass 20: String constant folding"
      CompilerEndIf

      ;- Pass 20: String constant folding (V1.20.34: renumbered from Pass 8) ("a" + "b" â†’ "ab")
      ForEach llObjects()
         If llObjects()\code = #ljSTRADD
            ; Look back for two consecutive string constant pushes
            If PreviousElement(llObjects())
               If (llObjects()\code = #ljPUSHS Or llObjects()\code = #ljPush) And (gVarMeta( llObjects()\i )\flags & #C2FLAG_CONST)
                  str2Idx = llObjects()\i
                  str2 = gVarMeta(str2Idx)\valueString
                  If PreviousElement(llObjects())
                     If (llObjects()\code = #ljPUSHS Or llObjects()\code = #ljPush) And (gVarMeta( llObjects()\i )\flags & #C2FLAG_CONST)
                        str1 = gVarMeta( llObjects()\i )\valueString
                        combinedStr = str1 + str2

                        ; Create new constant for combined string
                        newStrIdx = gnLastVariable
                        ; Clear all fields first
                        gVarMeta(newStrIdx)\name = "$strfold" + Str(newStrIdx)
                        gVarMeta(newStrIdx)\valueInt = 0
                        gVarMeta(newStrIdx)\valueFloat = 0.0
                        gVarMeta(newStrIdx)\valueString = combinedStr
                        gVarMeta(newStrIdx)\flags = #C2FLAG_CONST | #C2FLAG_STR
                        gVarMeta(newStrIdx)\paramOffset = -1  ; Constants don't need frame offsets
                        gnLastVariable + 1

                        ; Replace first PUSH with combined string, eliminate second PUSH and STRADD
                        llObjects()\i = newStrIdx
                        NextElement(llObjects())  ; Second PUSH
                        llObjects()\code = #ljNOOP
                        NextElement(llObjects())  ; STRADD
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
            EndIf
         EndIf
      Next

      CompilerIf #DEBUG
         Debug "    Pass 21: Return value type conversions"
      CompilerEndIf

      ;- Pass 21: Return value type conversions (V1.20.34: renamed from Pass 9)
      ; Insert type conversions before return statements when return value type doesn't match function return type
      ; Only valid conversions: FTOI, ITOF, FTOS, ITOS (no string-to-number conversions exist)
      ForEach llObjects()
         Select llObjects()\code
            Case #ljreturn
               ; Function returns INT - check if we're pushing a FLOAT
               If PreviousElement(llObjects())
                  Select llObjects()\code
                     Case #ljPUSHF, #ljFETCHF, #ljLFETCHF
                        ; Returning FLOAT from INT function - insert FTOI
                        NextElement(llObjects())
                        InsertElement(llObjects())
                        llObjects()\code = #ljFTOI
                        llObjects()\i = 0
                        llObjects()\n = 0
                        PreviousElement(llObjects())
                        NextElement(llObjects())
                     Default
                        NextElement(llObjects())
                  EndSelect
               EndIf

            Case #ljreturnF
               ; Function returns FLOAT - check if we're pushing an INT
               If PreviousElement(llObjects())
                  Select llObjects()\code
                     Case #ljPush, #ljFetch, #ljLFETCH
                        ; Need to verify this is not a FLOAT constant marked as PUSH
                        varIdx = llObjects()\i
                        If varIdx >= 0 And varIdx < gnLastVariable
                           If Not (gVarMeta(varIdx)\flags & #C2FLAG_FLOAT)
                              ; Returning INT from FLOAT function - insert ITOF
                              NextElement(llObjects())
                              InsertElement(llObjects())
                              llObjects()\code = #ljITOF
                              llObjects()\i = 0
                              llObjects()\n = 0
                              PreviousElement(llObjects())
                              NextElement(llObjects())
                           Else
                              NextElement(llObjects())
                           EndIf
                        Else
                           NextElement(llObjects())
                        EndIf
                     Default
                        NextElement(llObjects())
                  EndSelect
               EndIf

            Case #ljreturnS
               ; Function returns STRING - check if we're pushing an INT or FLOAT
               If PreviousElement(llObjects())
                  Select llObjects()\code
                     Case #ljPush, #ljFetch, #ljLFETCH
                        ; Need to verify this is not a STRING constant marked as PUSH
                        varIdx = llObjects()\i
                        If varIdx >= 0 And varIdx < gnLastVariable
                           If Not (gVarMeta(varIdx)\flags & #C2FLAG_STR)
                              ; Returning INT from STRING function - insert ITOS
                              NextElement(llObjects())
                              InsertElement(llObjects())
                              llObjects()\code = #ljITOS
                              llObjects()\i = 0
                              llObjects()\n = 0
                              PreviousElement(llObjects())
                              NextElement(llObjects())
                           Else
                              NextElement(llObjects())
                           EndIf
                        Else
                           NextElement(llObjects())
                        EndIf
                     Case #ljPUSHF, #ljFETCHF, #ljLFETCHF
                        ; Returning FLOAT from STRING function - insert FTOS
                        NextElement(llObjects())
                        InsertElement(llObjects())
                        llObjects()\code = #ljFTOS
                        llObjects()\i = 0
                        llObjects()\n = 0
                        PreviousElement(llObjects())
                        NextElement(llObjects())
                     Default
                        NextElement(llObjects())
                  EndSelect
               EndIf
         EndSelect
      Next

      ;- Pass 22: DISABLED (V1.20.34)
      ; Add implicit returns to functions that don't have explicit returns
      ; DISABLED: CodeGenerator now handles all returns correctly with proper typing
      ; This pass was adding duplicate returns due to incorrect function boundary detection

      CompilerIf #DEBUG
         Debug "    Pass 23: Optimize compound assignment patterns"
      CompilerEndIf

      ;- Pass 23: Optimize compound assignment patterns (V1.20.34: renamed from Pass 9.6)
      ; Pattern: FETCH var, PUSH/FETCH value, ADD/SUB/MUL/DIV/MOD, STORE same_var
      ; Replace with more efficient in-place operations
      ; V1.18.56.3: Convert to NOOP (Pass 10 disabled to preserve llHoles() pointers)
      ForEach llObjects()
         If llObjects()\code = #ljFetch Or llObjects()\code = #ljFETCHF
            varSlot = llObjects()\i

            ; V1.18.56.1: Track how many steps forward we go
            stepsForward = 0

            ; Check next is PUSH or Fetch (value to add/sub/etc)
            If NextElement(llObjects())
               stepsForward = 1
               If llObjects()\code = #ljPush Or llObjects()\code = #ljFetch Or llObjects()\code = #ljPUSHF Or llObjects()\code = #ljFETCHF
                  valueSlot = llObjects()\i

                  ; Check next is arithmetic operation
                  If NextElement(llObjects())
                     stepsForward = 2
                     Select llObjects()\code
                        Case #ljADD, #ljSUBTRACT, #ljMULTIPLY, #ljDIVIDE, #ljMOD, #ljFLOATADD, #ljFLOATSUB, #ljFLOATMUL, #ljFLOATDIV
                           opCode = llObjects()\code

                           ; Check next is STORE to same variable
                           If NextElement(llObjects())
                              stepsForward = 3
                              If (llObjects()\code = #ljStore Or llObjects()\code = #ljSTOREF) And llObjects()\i = varSlot
                                 ; Found pattern! Optimize it
                                 ; V1.18.56.3: Convert to NOOP (don't delete - ForEach can't handle deletion safely)
                                 ; Pass 10 is disabled to prevent NOOP removal from invalidating llHoles() pointers

                                 ; Go back to start of pattern (from STORE, back 3 to FETCH)
                                 PreviousElement(llObjects())
                                 PreviousElement(llObjects())
                                 PreviousElement(llObjects())

                                 ; Convert FETCH to NOOP
                                 llObjects()\code = #ljNOOP
                                 NextElement(llObjects())  ; Now at PUSH/FETCH value

                                 ; Keep value load
                                 NextElement(llObjects())  ; Now at ADD/SUB/etc

                                 ; Replace arithmetic with compound assignment variant
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
                                 llObjects()\i = varSlot  ; Store variable slot in opcode

                                 ; Move to STORE and convert to NOOP
                                 NextElement(llObjects())
                                 llObjects()\code = #ljNOOP
                              Else
                                 ; Not a match, restore by going back stepsForward times
                                 For i = 1 To stepsForward
                                    PreviousElement(llObjects())
                                 Next
                              EndIf
                           Else
                              ; Not a match, restore by going back stepsForward times
                              For i = 1 To stepsForward
                                 PreviousElement(llObjects())
                              Next
                           EndIf

                        Default
                           ; Not a match, restore by going back stepsForward times
                           For i = 1 To stepsForward
                              PreviousElement(llObjects())
                           Next
                     EndSelect
                  Else
                     ; Not a match, restore by going back stepsForward times
                     For i = 1 To stepsForward
                        PreviousElement(llObjects())
                     Next
                  EndIf
               Else
                  ; Not a match, restore by going back stepsForward times
                  For i = 1 To stepsForward
                     PreviousElement(llObjects())
                  Next
               EndIf
            Else
               ; Not a match, restore by going back stepsForward times
               For i = 1 To stepsForward
                  PreviousElement(llObjects())
               Next
            EndIf
         EndIf
      Next

      CompilerIf #DEBUG
         Debug "    Pass 23b: Convert pointer compound assignments (V1.20.37)"
      CompilerEndIf

      ;- Pass 23b: Convert compound assignments on pointers to pointer arithmetic (V1.20.37)
      ; ADD_ASSIGN_VAR on pointer → PTRADD_ASSIGN
      ; SUB_ASSIGN_VAR on pointer → PTRSUB_ASSIGN
      ForEach llObjects()
         Select llObjects()\code
            Case #ljADD_ASSIGN_VAR
               ; Check if variable is a pointer
               varSlot = llObjects()\i
               If varSlot >= 0 And varSlot < gnLastVariable
                  searchKey = gVarMeta(varSlot)\name
                  If FindMapElement(mapVariableTypes(), searchKey)
                     If mapVariableTypes() & #C2FLAG_POINTER
                        llObjects()\code = #ljPTRADD_ASSIGN
                     EndIf
                  EndIf
               EndIf

            Case #ljSUB_ASSIGN_VAR
               ; Check if variable is a pointer
               varSlot = llObjects()\i
               If varSlot >= 0 And varSlot < gnLastVariable
                  searchKey = gVarMeta(varSlot)\name
                  If FindMapElement(mapVariableTypes(), searchKey)
                     If mapVariableTypes() & #C2FLAG_POINTER
                        llObjects()\code = #ljPTRSUB_ASSIGN
                     EndIf
                  EndIf
               EndIf
         EndSelect
      Next

      CompilerIf #DEBUG
         Debug "    Pass 24: Optimize increment/decrement + POP patterns"
      CompilerEndIf

      ;- Pass 24: Optimize increment/decrement + POP patterns (V1.20.34: renamed from Pass 9.7)
      ; When increment/decrement is used standalone (not in expression), it's wrapped with POP
      ; PRE/POST variants push a value, but if immediately followed by POP, we can use the simpler INC/DEC opcodes
      ForEach llObjects()
         Select llObjects()\code
            Case #ljINC_VAR_PRE, #ljINC_VAR_POST
               ; Check if next instruction is POP
               If NextElement(llObjects())
                  If llObjects()\code = #ljPOP
                     ; Replace PRE/POST with simple INC and remove POP
                     PreviousElement(llObjects())
                     llObjects()\code = #ljINC_VAR
                     NextElement(llObjects())
                     llObjects()\code = #ljNOOP
                  Else
                     PreviousElement(llObjects())
                  EndIf
               EndIf

            Case #ljDEC_VAR_PRE, #ljDEC_VAR_POST
               ; Check if next instruction is POP
               If NextElement(llObjects())
                  If llObjects()\code = #ljPOP
                     ; Replace PRE/POST with simple DEC and remove POP
                     PreviousElement(llObjects())
                     llObjects()\code = #ljDEC_VAR
                     NextElement(llObjects())
                     llObjects()\code = #ljNOOP
                  Else
                     PreviousElement(llObjects())
                  EndIf
               EndIf

            Case #ljLINC_VAR_PRE, #ljLINC_VAR_POST
               ; Check if next instruction is POP
               If NextElement(llObjects())
                  If llObjects()\code = #ljPOP
                     ; Replace PRE/POST with simple LINC and remove POP
                     PreviousElement(llObjects())
                     llObjects()\code = #ljLINC_VAR
                     NextElement(llObjects())
                     llObjects()\code = #ljNOOP
                  Else
                     PreviousElement(llObjects())
                  EndIf
               EndIf

            Case #ljLDEC_VAR_PRE, #ljLDEC_VAR_POST
               ; Check if next instruction is POP
               If NextElement(llObjects())
                  If llObjects()\code = #ljPOP
                     ; Replace PRE/POST with simple LDEC and remove POP
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
         Debug "    Pass 25: Remove all NOOP instructions"
      CompilerEndIf

      ;- Pass 25: Remove all NOOP instructions from the code stream (V1.20.34: renamed from Pass 10)
      ; V1.20.18: RE-ENABLED - Test if NOOP removal works with current codebase
      ; Previous issue: removing NOOPs invalidated llHoles() element pointers
      ; This caused FixJMP() to calculate wrong offsets, breaking nested loops
      ; Testing to see if this still occurs with current implementation
      ; V1.020.066: TEMPORARILY DISABLED to test FizzBuzz corruption issue
      ; V1.020.068: RE-ENABLED - Testing if sp fix resolved all issues
      ; V1.020.069: Confirmed NOOP bug still exists, reverting to disabled
      ; V1.020.070: PERMANENTLY DISABLED - Pass 26 now handles NOOP removal with anchor system
      CompilerIf #False
      ForEach llObjects()
         If llObjects()\code = #ljNOOP
            DeleteElement(llObjects())
         EndIf
      Next
      CompilerEndIf
      EndIf  ; optimizationsEnabled

      ; V1.020.057: Debug output for Stack=-11 investigation
      CompilerIf #DEBUG
      Debug "=== VARIABLE ALLOCATION DEBUG ==="
      Debug "gnLastVariable=" + Str(gnLastVariable) + " (total allocations including params/locals/constants)"
      Debug "gnGlobalVariables=" + Str(gnGlobalVariables) + " (global scope only, used for stack calculation)"
      Debug "Difference=" + Str(gnLastVariable - gnGlobalVariables) + " (function params/locals/constants)"
      Debug ""
      For i = 0 To gnLastVariable - 1
         flags = ""
         If gVarMeta(i)\flags & #C2FLAG_CONST : flags + "CONST " : EndIf
         If gVarMeta(i)\flags & #C2FLAG_IDENT : flags + "VAR " : EndIf
         If gVarMeta(i)\flags & #C2FLAG_INT : flags + "INT " : EndIf
         If gVarMeta(i)\flags & #C2FLAG_FLOAT : flags + "FLT " : EndIf
         If gVarMeta(i)\flags & #C2FLAG_STR : flags + "STR " : EndIf
         If gVarMeta(i)\flags & #C2FLAG_PARAM : flags + "PARAM " : EndIf
         If gVarMeta(i)\flags & #C2FLAG_ARRAY : flags + "ARRAY " : EndIf
         Debug "  [" + RSet(Str(i), 3) + "] " + LSet(gVarMeta(i)\name, 25) + " " + flags
      Next
      Debug "========================================="
      CompilerEndIf

   EndProcedure

; IDE Options = PureBasic 6.21 (Windows - x64)
; CursorPosition = 26
; FirstLine = 21
; Folding = -------------
; EnableAsm
; EnableThread
; EnableXP
; CPU = 1
; EnablePurifier
; EnableCompileCount = 1
; EnableBuildCount = 0
; EnableExeConstant