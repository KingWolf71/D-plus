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

; V1.029.35: Helper to generate field type bitmap for struct collections
; Encodes field types as 2 bits each: 00=int, 01=float, 10=string
; Recursively flattens nested structs
; Returns: bitmap (64-bit) and updates fieldIndex
Procedure.q GenerateStructTypeBitmap(structType.s, *fieldIndex.Integer)
   Protected bitmap.q = 0
   Protected idx.i, fieldType.w, nestedBitmap.q

   If FindMapElement(mapStructDefs(), structType)
      ForEach mapStructDefs()\fields()
         If mapStructDefs()\fields()\structType <> ""
            ; Nested struct - recursively process
            PushMapPosition(mapStructDefs())
            nestedBitmap = GenerateStructTypeBitmap(mapStructDefs()\fields()\structType, *fieldIndex)
            PopMapPosition(mapStructDefs())
            bitmap = bitmap | nestedBitmap
         Else
            ; Primitive field - encode type
            idx = *fieldIndex\i
            If idx < 32  ; Max 32 fields with 2 bits each
               fieldType = mapStructDefs()\fields()\fieldType
               If fieldType & #C2FLAG_FLOAT
                  bitmap = bitmap | (1 << (idx * 2))  ; 01 = float
               ElseIf fieldType & #C2FLAG_STR
                  bitmap = bitmap | (2 << (idx * 2))  ; 10 = string
               EndIf
               ; 00 = int (default, no bits set)
            EndIf
            *fieldIndex\i + 1
         EndIf
      Next
   EndIf

   ProcedureReturn bitmap
EndProcedure

Procedure            InitJumpTracker()
      ; V1.020.077: Initialize jump tracker BEFORE PostProcessor runs
      ; This allows optimization passes to call AdjustJumpsForNOOP() with populated tracker

      Protected         i, pos, pair
      Protected         srcPos.i
      Protected         offset.i
      Protected         *targetInstr.stType  ; V1.020.085: Store target instruction pointer
      Protected         *currentNoop         ; V1.022.98: For function-end NOOPIF check

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

               ; V1.020.097: BUGFIX - Do NOT call NextElement() unconditionally!
               ; fix() stores the target position, but if it's a NOOPIF, we must advance past it
               ; because NOOPIF will be deleted and the pointer would become dangling.
               ;
               ; V1.022.85: Skip past NOOPIF/NOOP markers to store pointer to actual target instruction
               ; This prevents dangling pointer after Pass25 deletes NOOPs
               ;
               ; V1.022.98: CRITICAL FIX - Do NOT skip NOOPIF at function ends!
               ; If NOOPIF is followed by #ljfunction/#ljHALT, it will be converted to RETURN by Pass 13.
               ; We must keep the pointer pointing at the NOOPIF (future RETURN), not skip to #ljfunction
               ; (which acts as NOOP at runtime, causing fallthrough to next function).
               While llObjects()\code = #ljNOOPIF Or llObjects()\code = #ljNOOP
                  ; Check what comes after this NOOPIF/NOOP
                  *currentNoop = @llObjects()
                  If NextElement(llObjects())
                     ; V1.022.98: If next is function marker or HALT, STOP - keep pointer at NOOPIF
                     ; Pass 13 will convert this NOOPIF to RETURN, so pointer should point here
                     If llObjects()\code = #ljfunction Or llObjects()\code = #ljHALT
                        ChangeCurrentElement(llObjects(), *currentNoop)  ; Go back to NOOPIF
                        CompilerIf #DEBUG
                           Debug "InitJumpTracker: Keeping pointer at function-end NOOPIF (will become RETURN)"
                        CompilerEndIf
                        Break  ; Exit while loop - don't skip this NOOPIF
                     EndIf
                     ; Otherwise continue skipping NOOPs
                  Else
                     ; End of list - stop here
                     ChangeCurrentElement(llObjects(), *currentNoop)
                     Break
                  EndIf
               Wend
               pos = ListIndex(llObjects())  ; Update pos to actual target (after skipping NOOPs)
               *targetInstr = @llObjects()   ; Store pointer to non-NOOP instruction (won't be deleted)
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

         ElseIf llHoles()\mode = #C2HOLE_LOOPBACK
            ; V1.023.42: While loop backward jump - target is NOOPIF at loop start
            ; Must skip past NOOPIF to actual target so pointer stays valid after deletion
            llHoles()\mode = #C2HOLE_PAIR
            ChangeCurrentElement( llObjects(), llHoles()\src )
            ; Skip past NOOPIF/NOOP to actual target instruction
            While llObjects()\code = #ljNOOPIF Or llObjects()\code = #ljNOOP
               If Not NextElement(llObjects())
                  Break
               EndIf
            Wend
            pos = ListIndex( llObjects() )
            *targetInstr = @llObjects()  ; Store pointer to instruction AFTER NOOPIF
            ChangeCurrentElement( llObjects(), llHoles()\location )
            srcPos = ListIndex( llObjects() )
            offset = (pos - srcPos)
            llObjects()\i = offset

            AddElement(llJumpTracker())
            llJumpTracker()\instruction = @llObjects()
            llJumpTracker()\target = *targetInstr
            llJumpTracker()\srcPos = srcPos
            llJumpTracker()\targetPos = pos
            llJumpTracker()\offset = offset
            llJumpTracker()\type = llObjects()\code
            llJumpTracker()\holeMode = #C2HOLE_LOOPBACK  ; Track while loop backward jumps

            CompilerIf #DEBUG
               Debug "InitJumpTracker: LOOPBACK jump at srcPos=" + Str(srcPos) + " targetPos=" + Str(pos) + " offset=" + Str(offset) + " (while loop backward JMP)"
            CompilerEndIf

         ; V1.024.0: FOR loop backward jump - similar to LOOPBACK
         ElseIf llHoles()\mode = #C2HOLE_FORLOOP
            llHoles()\mode = #C2HOLE_PAIR
            ChangeCurrentElement( llObjects(), llHoles()\src )
            ; Skip past NOOPIF/NOOP to actual target instruction
            While llObjects()\code = #ljNOOPIF Or llObjects()\code = #ljNOOP
               If Not NextElement(llObjects())
                  Break
               EndIf
            Wend
            pos = ListIndex( llObjects() )
            *targetInstr = @llObjects()
            ChangeCurrentElement( llObjects(), llHoles()\location )
            srcPos = ListIndex( llObjects() )
            offset = (pos - srcPos)
            llObjects()\i = offset

            AddElement(llJumpTracker())
            llJumpTracker()\instruction = @llObjects()
            llJumpTracker()\target = *targetInstr
            llJumpTracker()\srcPos = srcPos
            llJumpTracker()\targetPos = pos
            llJumpTracker()\offset = offset
            llJumpTracker()\type = llObjects()\code
            llJumpTracker()\holeMode = #C2HOLE_FORLOOP

            CompilerIf #DEBUG
               Debug "InitJumpTracker: FORLOOP jump at srcPos=" + Str(srcPos) + " targetPos=" + Str(pos) + " offset=" + Str(offset)
            CompilerEndIf

         ; V1.024.0: CONTINUE backward jump - jumps to loop start or update section
         ElseIf llHoles()\mode = #C2HOLE_CONTINUE
            llHoles()\mode = #C2HOLE_PAIR
            ChangeCurrentElement( llObjects(), llHoles()\src )
            ; Skip past NOOPIF/NOOP to actual target instruction
            While llObjects()\code = #ljNOOPIF Or llObjects()\code = #ljNOOP
               If Not NextElement(llObjects())
                  Break
               EndIf
            Wend
            pos = ListIndex( llObjects() )
            *targetInstr = @llObjects()
            ChangeCurrentElement( llObjects(), llHoles()\location )
            srcPos = ListIndex( llObjects() )
            offset = (pos - srcPos)
            llObjects()\i = offset

            AddElement(llJumpTracker())
            llJumpTracker()\instruction = @llObjects()
            llJumpTracker()\target = *targetInstr
            llJumpTracker()\srcPos = srcPos
            llJumpTracker()\targetPos = pos
            llJumpTracker()\offset = offset
            llJumpTracker()\type = llObjects()\code
            llJumpTracker()\holeMode = #C2HOLE_CONTINUE

            CompilerIf #DEBUG
               Debug "InitJumpTracker: CONTINUE jump at srcPos=" + Str(srcPos) + " targetPos=" + Str(pos) + " offset=" + Str(offset)
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
      ; V1.022.96: CRITICAL FIX - Convert ALL NOOPs at function ends to RETURN
      ; SIMPLIFIED: Don't check if jump target - just convert any NOOP before #ljFunction or #ljHALT
      ; This ensures JZ targets at function ends become RETURN instead of being deleted
      ; V1.022.97: Added unconditional debug to verify pass runs
      CompilerIf #DEBUG
         Debug "    Pass 25a: Convert NOOPs at function ends to RETURN (V1.022.97 debug)"
      CompilerEndIf

      Protected *savedNoop
      Protected convertedCount.i = 0
      Protected noopPos.i = 0
      Protected nextCode.i = 0
      Protected inFunction.i = #False   ; V1.022.103: Track if we're inside a function
      ForEach llObjects()
         ; V1.022.103: Track when we enter a function - main code comes before first #ljfunction
         If llObjects()\code = #ljfunction
            inFunction = #True
         EndIf
         ; V1.022.110: CRITICAL FIX - Also check for #ljNOOPIF!
         ; If functions end with if/while blocks, they have #ljNOOPIF not #ljNOOP
         If llObjects()\code = #ljNOOP Or llObjects()\code = #ljNOOPIF
            ; Save pointer to this NOOP/NOOPIF
            *savedNoop = @llObjects()
            noopPos = ListIndex(llObjects())
            ; Check if next element is function or HALT (meaning this is at function end)
            If NextElement(llObjects())
               nextCode = llObjects()\code
               CompilerIf #DEBUG
                  Debug "  Pass25a: NOOP/NOOPIF at pos " + Str(noopPos) + " -> next is " + gszATR(nextCode)\s + " (" + Str(nextCode) + ") inFunction=" + Str(inFunction)
               CompilerEndIf
               ; V1.022.103: Only convert to RETURN if:
               ; - Next is #ljfunction (always a function boundary), OR
               ; - Next is #ljHALT AND we're inside a function (not main code)
               If llObjects()\code = #ljfunction Or (llObjects()\code = #ljHALT And inFunction)
                  ; This NOOP is at function end - convert to RETURN
                  ChangeCurrentElement(llObjects(), *savedNoop)
                  llObjects()\code = #ljreturn
                  llObjects()\i = 0
                  llObjects()\j = 0
                  llObjects()\n = 0
                  llObjects()\ndx = -1
                  convertedCount + 1
                  CompilerIf #DEBUG
                     Debug "  Pass25a: CONVERTED NOOP/NOOPIF at pos " + Str(noopPos) + " to RETURN"
                  CompilerEndIf
               Else
                  ; Not at function end (or main code before HALT) - restore position
                  ChangeCurrentElement(llObjects(), *savedNoop)
                  CompilerIf #DEBUG
                     Debug "  Pass25a: SKIPPED NOOP/NOOPIF at pos " + Str(noopPos) + " (main code or mid-function)"
                  CompilerEndIf
               EndIf
            Else
               ; End of list - only convert if inside a function
               CompilerIf #DEBUG
                  Debug "  Pass25a: NOOP/NOOPIF at pos " + Str(noopPos) + " -> END OF LIST, inFunction=" + Str(inFunction)
               CompilerEndIf
               ChangeCurrentElement(llObjects(), *savedNoop)
               If inFunction
                  llObjects()\code = #ljreturn
                  llObjects()\i = 0
                  llObjects()\j = 0
                  llObjects()\n = 0
                  llObjects()\ndx = -1
                  convertedCount + 1
                  CompilerIf #DEBUG
                     Debug "  Pass25a: CONVERTED NOOP/NOOPIF at pos " + Str(noopPos) + " to RETURN (end of list, in function)"
                  CompilerEndIf
               Else
                  CompilerIf #DEBUG
                     Debug "  Pass25a: SKIPPED NOOP/NOOPIF at pos " + Str(noopPos) + " (end of list, main code)"
                  CompilerEndIf
               EndIf
            EndIf
         EndIf
      Next
      CompilerIf #DEBUG
         Debug "Pass25a: Converted " + Str(convertedCount) + " NOOP/NOOPIFs at function ends to RETURN"
      CompilerEndIf

      CompilerIf #True  ; V1.020.094: Re-enabled after fixing incremental adjustment bug
      noopCount = 0
      Protected *currentNoop, *nextInstr
      ForEach llObjects()
         ; V1.023.42: Delete both NOOP and NOOPIF (LOOPBACK mode handles backward jumps)
         If llObjects()\code = #ljNOOP Or llObjects()\code = #ljNOOPIF
            ; V1.023.38: CRITICAL FIX - Before deleting, update any jump tracker targets
            ; that point to this NOOP to point to the next instruction instead
            *currentNoop = @llObjects()
            *nextInstr = #Null
            PushListPosition(llObjects())
            If NextElement(llObjects())
               *nextInstr = @llObjects()
            EndIf
            PopListPosition(llObjects())
            ; Update any jump tracker entries that target this NOOP
            ; V1.024.24: BUGFIX - Multiple jumps can target same NOOP (e.g. JZ and break)
            ; Must update ALL of them, not just the first one found
            If *nextInstr
               PushListPosition(llJumpTracker())
               ForEach llJumpTracker()
                  If llJumpTracker()\target = *currentNoop
                     llJumpTracker()\target = *nextInstr
                     CompilerIf #DEBUG
                        Debug "Pass25: Redirected jump target from deleted NOOP to next instruction"
                     CompilerEndIf
                     ; V1.024.24: DON'T break - continue checking for more jumps targeting same NOOP
                  EndIf
               Next
               PopListPosition(llJumpTracker())
            EndIf
            ; Now safe to delete - llObjects() is still at *currentNoop
            noopCount + 1
            DeleteElement(llObjects())
         EndIf
      Next
      CompilerIf #DEBUG
         Debug "Pass 25: Deleted " + Str(noopCount) + " NOOP/NOOPIF instructions"
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
               ; V1.026.4: Removed incorrect -1 LOOPBACK adjustment
               ; The offset targetPos - srcPos is correct for VM: pc = pc + offset
               ; Analysis: JMP at 312 needs to reach position 300, so offset = 300 - 312 = -12
               ; VM does: pc = 312 + (-12) = 300 (correct!)
               ; The previous -1 adjustment caused offset -13, landing at 299 (LIST_RESET) instead
               offset = targetPos - srcPos
               llJumpTracker()\instruction\i = offset
               CompilerIf #DEBUG
                  ; V1.020.096: Enhanced debug to show instruction types and hole mode
                  Protected srcInstrName.s = gszATR(llJumpTracker()\instruction\code)\s
                  Protected tgtInstrName.s = gszATR(llObjects()\code)\s
                  Protected modeStr.s = ""
                  Select llJumpTracker()\holeMode
                     Case #C2HOLE_LOOPBACK : modeStr = "LOOPBACK"
                     Case #C2HOLE_FORLOOP : modeStr = "FORLOOP"
                     Case #C2HOLE_CONTINUE : modeStr = "CONTINUE"
                     Case #C2HOLE_BREAK : modeStr = "BREAK"
                     Case #C2HOLE_BLIND : modeStr = "BLIND"
                     Default : modeStr = "DEFAULT"
                  EndSelect
                  Debug "Pass26: " + srcInstrName + " at pos=" + Str(srcPos) + " → " + tgtInstrName + " at pos=" + Str(targetPos) + " offset=" + Str(offset) + " (was " + Str(llJumpTracker()\offset) + ") mode=" + modeStr
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

      ; V1.020.110: Patch GETFUNCADDR instructions with correct function PC addresses
      ; Similar to CALL patching above, but only updates the PC address (stored in i field)
      Debug " -- Patching GETFUNCADDR instructions..."
      ForEach llObjects()
         If llObjects()\code = #ljGETFUNCADDR
            ForEach mapModules()
               If mapModules()\function = llObjects()\i
                  llObjects()\i = mapModules()\Index  ; Update to actual PC address after NOOP removal
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
      Protected sourceIsArrayPointer.b  ; V1.027.0: Track array pointer flag for MOV
      Protected isArrayElementPointer.b ; V1.027.0: Track array element pointers in Pass 1
      Protected pointerBaseType.i
      Protected ptrOpcode.i
      ; V1.20.47: Variables for function-aware pointer tracking
      Protected currentFunctionName.s
      Protected srcSlot.i
      Protected srcVarKey.s
      Protected funcId.i
      Protected varName.s
      Protected flags.s
      Protected localOffset
      Protected arrayStoreIdx, valueInstrIdx  ; V1.022.89: For Pass 11 NOOP skipping
      ; V1.023.0: Variables for template building
      Protected maxFuncId.i
      Protected funcName.s
      Protected funcPrefix.s
      Protected nParams.i
      Protected localCount.i
      Protected templateIdx.i
      Protected removedMovCount.i
      ; V1.023.1: Variables for local variable name lookup
      Protected localParamOffset.i
      Protected localVarName.s
      ; V1.023.9: Key for tracking removed local inits
      Protected localKey.s

      CompilerIf #DEBUG
         Debug "    Pass 1: Pointer type tracking (mark variables assigned from pointer sources)"
      CompilerEndIf

      ;- Pass 1: Pointer type tracking (V1.20.34)
      ; Traverse bytecode to identify variables that receive pointer values
      ; Mark them with #C2FLAG_POINTER in mapVariableTypes for proper handling
      ForEach llObjects()
         Select llObjects()\code
            ; Variables assigned from GETADDR or GETARRAYADDR are pointers
            ; V1.021.12: Include GETARRAYADDR variants for array element pointers (&arr[i])
            ; V1.022.58: Include GETSTRUCTADDR for struct pointers (&structVar)
            Case #ljGETADDR, #ljGETADDRF, #ljGETADDRS, #ljGETARRAYADDR, #ljGETARRAYADDRF, #ljGETARRAYADDRS, #ljGETSTRUCTADDR
               ; Store the GETADDR type for later use
               getAddrType = llObjects()\code

               ; Find the next STORE/POP to see which variable gets this pointer
               If NextElement(llObjects())
                  ; V1.029.84: Include STORE_STRUCT for struct variable pointer tracking
                  If llObjects()\code = #ljStore Or llObjects()\code = #ljSTORES Or llObjects()\code = #ljSTOREF Or llObjects()\code = #ljSTORE_STRUCT Or
                     llObjects()\code = #ljPOP Or llObjects()\code = #ljPOPS Or llObjects()\code = #ljPOPF
                     ptrVarSlot = llObjects()\i

                     ; Mark this variable as a pointer in mapVariableTypes
                     If ptrVarSlot >= 0 And ptrVarSlot < gnLastVariable
                        ptrVarKey = gVarMeta(ptrVarSlot)\name

                        ; Determine pointer base type from GETADDR/GETARRAYADDR variant
                        ; V1.027.0: Also track if this is an array element pointer
                        isArrayElementPointer = #False
                        Select getAddrType
                           Case #ljGETADDRF
                              pointerBaseType = #C2FLAG_FLOAT
                           Case #ljGETARRAYADDRF
                              pointerBaseType = #C2FLAG_FLOAT
                              isArrayElementPointer = #True
                           Case #ljGETADDRS
                              pointerBaseType = #C2FLAG_STR
                           Case #ljGETARRAYADDRS
                              pointerBaseType = #C2FLAG_STR
                              isArrayElementPointer = #True
                           Case #ljGETARRAYADDR
                              pointerBaseType = #C2FLAG_INT
                              isArrayElementPointer = #True
                           Default
                              pointerBaseType = #C2FLAG_INT
                        EndSelect

                        ; Store pointer type in map (V1.027.0: include array pointer flag)
                        If isArrayElementPointer
                           mapVariableTypes(ptrVarKey) = #C2FLAG_POINTER | pointerBaseType | #C2FLAG_ARRAYPTR
                        Else
                           mapVariableTypes(ptrVarKey) = #C2FLAG_POINTER | pointerBaseType
                        EndIf

                        CompilerIf #DEBUG
                           Debug "      Marked variable '" + ptrVarKey + "' as pointer (from GETADDR/GETARRAYADDR)"
                        CompilerEndIf
                     EndIf
                  EndIf
                  PreviousElement(llObjects())  ; Restore position
               EndIf

            ; Variables assigned from pointer arithmetic are also pointers
            ; V1.027.0: Pointer arithmetic on array pointers produces array pointers
            Case #ljPTRADD, #ljPTRSUB
               ; These operations leave a pointer on the stack
               ; Find the next STORE/POP to see which variable gets this pointer
               If NextElement(llObjects())
                  ; V1.029.84: Include STORE_STRUCT for struct variable pointer tracking
                  If llObjects()\code = #ljStore Or llObjects()\code = #ljSTORES Or llObjects()\code = #ljSTOREF Or llObjects()\code = #ljSTORE_STRUCT Or
                     llObjects()\code = #ljPOP Or llObjects()\code = #ljPOPS Or llObjects()\code = #ljPOPF
                     ptrVarSlot = llObjects()\i

                     ; V1.027.0: Mark as array pointer since PTRADD/PTRSUB is typically used with array pointers
                     ; (Simple variable pointers rarely use arithmetic)
                     If ptrVarSlot >= 0 And ptrVarSlot < gnLastVariable
                        ptrVarKey = gVarMeta(ptrVarSlot)\name
                        mapVariableTypes(ptrVarKey) = #C2FLAG_POINTER | #C2FLAG_INT | #C2FLAG_ARRAYPTR

                        CompilerIf #DEBUG
                           Debug "      Marked variable '" + ptrVarKey + "' as array pointer (from pointer arithmetic)"
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
               sourceIsArrayPointer = #False  ; V1.027.0: Track array pointer flag
               If srcVar >= 0 And srcVar < gnLastVariable
                  searchKey = gVarMeta(srcVar)\name
                  If FindMapElement(mapVariableTypes(), searchKey)
                     If mapVariableTypes() & #C2FLAG_POINTER
                        sourceIsPointer = #True
                        pointerBaseType = mapVariableTypes() & #C2FLAG_TYPE
                        sourceIsArrayPointer = Bool((mapVariableTypes() & #C2FLAG_ARRAYPTR) <> 0)  ; V1.027.0
                     EndIf
                  EndIf

                  ; V1.20.35: Also check if source is a parameter
                  ; Parameters can hold pointer values but aren't in mapVariableTypes
                  If Not sourceIsPointer And (gVarMeta(srcVar)\flags & #C2FLAG_PARAM)
                     ; Parameter - assume it could be a pointer (we don't know at compile time)
                     sourceIsPointer = #True
                     pointerBaseType = #C2FLAG_INT  ; Default to int pointers
                     sourceIsArrayPointer = #False  ; V1.027.0: Can't know if parameter is array ptr

                     CompilerIf #DEBUG
                        Debug "      Source is parameter '" + gVarMeta(srcVar)\name + "', treating as potential pointer"
                     CompilerEndIf
                  EndIf
               EndIf

               ; If source is pointer, mark destination as pointer too
               ; V1.027.0: Preserve array pointer flag
               If sourceIsPointer And dstVar >= 0 And dstVar < gnLastVariable
                  ptrVarKey = gVarMeta(dstVar)\name
                  If sourceIsArrayPointer
                     mapVariableTypes(ptrVarKey) = #C2FLAG_POINTER | pointerBaseType | #C2FLAG_ARRAYPTR
                  Else
                     mapVariableTypes(ptrVarKey) = #C2FLAG_POINTER | pointerBaseType
                  EndIf

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
               ; Check if this push should be typed or converted to immediate
               n = llObjects()\i
               If n >= 0 And n < gnLastVariable
                  ; Skip parameters - they're generic and handled at runtime
                  If Not (gVarMeta(n)\flags & #C2FLAG_PARAM)
                     If gVarMeta(n)\flags & #C2FLAG_FLOAT
                        llObjects()\code = #ljPUSHF
                     ElseIf gVarMeta(n)\flags & #C2FLAG_STR
                        llObjects()\code = #ljPUSHS
                     ; V1.031.113: PUSH_IMM conversion moved to Pass 28 (after all constant folding)
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
            ; V1.027.0: Use type-specialized opcodes to eliminate runtime Select
            Case #ljINC_VAR
               ; Check if variable is a pointer
               n = llObjects()\i
               If n >= 0 And n < gnLastVariable
                  searchKey = gVarMeta(n)\name
                  If FindMapElement(mapVariableTypes(), searchKey)
                     If mapVariableTypes() & #C2FLAG_POINTER
                        ; V1.027.0: Select typed variant based on pointer type
                        If mapVariableTypes() & #C2FLAG_ARRAYPTR
                           llObjects()\code = #ljPTRINC_ARRAY
                        ElseIf mapVariableTypes() & #C2FLAG_STR
                           llObjects()\code = #ljPTRINC_STRING
                        ElseIf mapVariableTypes() & #C2FLAG_FLOAT
                           llObjects()\code = #ljPTRINC_FLOAT
                        Else
                           llObjects()\code = #ljPTRINC_INT
                        EndIf
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
                        ; V1.027.0: Select typed variant based on pointer type
                        If mapVariableTypes() & #C2FLAG_ARRAYPTR
                           llObjects()\code = #ljPTRDEC_ARRAY
                        ElseIf mapVariableTypes() & #C2FLAG_STR
                           llObjects()\code = #ljPTRDEC_STRING
                        ElseIf mapVariableTypes() & #C2FLAG_FLOAT
                           llObjects()\code = #ljPTRDEC_FLOAT
                        Else
                           llObjects()\code = #ljPTRDEC_INT
                        EndIf
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
                        ; V1.027.0: Select typed variant based on pointer type
                        If mapVariableTypes() & #C2FLAG_ARRAYPTR
                           llObjects()\code = #ljPTRINC_PRE_ARRAY
                        ElseIf mapVariableTypes() & #C2FLAG_STR
                           llObjects()\code = #ljPTRINC_PRE_STRING
                        ElseIf mapVariableTypes() & #C2FLAG_FLOAT
                           llObjects()\code = #ljPTRINC_PRE_FLOAT
                        Else
                           llObjects()\code = #ljPTRINC_PRE_INT
                        EndIf
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
                        ; V1.027.0: Select typed variant based on pointer type
                        If mapVariableTypes() & #C2FLAG_ARRAYPTR
                           llObjects()\code = #ljPTRDEC_PRE_ARRAY
                        ElseIf mapVariableTypes() & #C2FLAG_STR
                           llObjects()\code = #ljPTRDEC_PRE_STRING
                        ElseIf mapVariableTypes() & #C2FLAG_FLOAT
                           llObjects()\code = #ljPTRDEC_PRE_FLOAT
                        Else
                           llObjects()\code = #ljPTRDEC_PRE_INT
                        EndIf
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
                        ; V1.027.0: Select typed variant based on pointer type
                        If mapVariableTypes() & #C2FLAG_ARRAYPTR
                           llObjects()\code = #ljPTRINC_POST_ARRAY
                        ElseIf mapVariableTypes() & #C2FLAG_STR
                           llObjects()\code = #ljPTRINC_POST_STRING
                        ElseIf mapVariableTypes() & #C2FLAG_FLOAT
                           llObjects()\code = #ljPTRINC_POST_FLOAT
                        Else
                           llObjects()\code = #ljPTRINC_POST_INT
                        EndIf
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
                        ; V1.027.0: Select typed variant based on pointer type
                        If mapVariableTypes() & #C2FLAG_ARRAYPTR
                           llObjects()\code = #ljPTRDEC_POST_ARRAY
                        ElseIf mapVariableTypes() & #C2FLAG_STR
                           llObjects()\code = #ljPTRDEC_POST_STRING
                        ElseIf mapVariableTypes() & #C2FLAG_FLOAT
                           llObjects()\code = #ljPTRDEC_POST_FLOAT
                        Else
                           llObjects()\code = #ljPTRDEC_POST_INT
                        EndIf
                     EndIf
                  EndIf
               EndIf

            ; V1.20.36: Also handle local increment/decrement on pointers
            ; V1.027.0: Use type-specialized opcodes to eliminate runtime Select
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
                        ; V1.027.0: Select typed variant based on pointer type
                        If mapVariableTypes() & #C2FLAG_ARRAYPTR
                           llObjects()\code = #ljPTRINC_ARRAY
                        ElseIf mapVariableTypes() & #C2FLAG_STR
                           llObjects()\code = #ljPTRINC_STRING
                        ElseIf mapVariableTypes() & #C2FLAG_FLOAT
                           llObjects()\code = #ljPTRINC_FLOAT
                        Else
                           llObjects()\code = #ljPTRINC_INT
                        EndIf
                        CompilerIf #DEBUG
                           Debug "        Converted LINC_VAR -> typed PTRINC"
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
                        ; V1.027.0: Select typed variant based on pointer type
                        If mapVariableTypes() & #C2FLAG_ARRAYPTR
                           llObjects()\code = #ljPTRDEC_ARRAY
                        ElseIf mapVariableTypes() & #C2FLAG_STR
                           llObjects()\code = #ljPTRDEC_STRING
                        ElseIf mapVariableTypes() & #C2FLAG_FLOAT
                           llObjects()\code = #ljPTRDEC_FLOAT
                        Else
                           llObjects()\code = #ljPTRDEC_INT
                        EndIf
                        CompilerIf #DEBUG
                           Debug "        Converted LDEC_VAR -> typed PTRDEC"
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
                        ; V1.027.0: Select typed variant based on pointer type
                        If mapVariableTypes() & #C2FLAG_ARRAYPTR
                           llObjects()\code = #ljPTRINC_PRE_ARRAY
                        ElseIf mapVariableTypes() & #C2FLAG_STR
                           llObjects()\code = #ljPTRINC_PRE_STRING
                        ElseIf mapVariableTypes() & #C2FLAG_FLOAT
                           llObjects()\code = #ljPTRINC_PRE_FLOAT
                        Else
                           llObjects()\code = #ljPTRINC_PRE_INT
                        EndIf
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
                        ; V1.027.0: Select typed variant based on pointer type
                        If mapVariableTypes() & #C2FLAG_ARRAYPTR
                           llObjects()\code = #ljPTRDEC_PRE_ARRAY
                        ElseIf mapVariableTypes() & #C2FLAG_STR
                           llObjects()\code = #ljPTRDEC_PRE_STRING
                        ElseIf mapVariableTypes() & #C2FLAG_FLOAT
                           llObjects()\code = #ljPTRDEC_PRE_FLOAT
                        Else
                           llObjects()\code = #ljPTRDEC_PRE_INT
                        EndIf
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
                        ; V1.027.0: Select typed variant based on pointer type
                        If mapVariableTypes() & #C2FLAG_ARRAYPTR
                           llObjects()\code = #ljPTRINC_POST_ARRAY
                        ElseIf mapVariableTypes() & #C2FLAG_STR
                           llObjects()\code = #ljPTRINC_POST_STRING
                        ElseIf mapVariableTypes() & #C2FLAG_FLOAT
                           llObjects()\code = #ljPTRINC_POST_FLOAT
                        Else
                           llObjects()\code = #ljPTRINC_POST_INT
                        EndIf
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
                        ; V1.027.0: Select typed variant based on pointer type
                        If mapVariableTypes() & #C2FLAG_ARRAYPTR
                           llObjects()\code = #ljPTRDEC_POST_ARRAY
                        ElseIf mapVariableTypes() & #C2FLAG_STR
                           llObjects()\code = #ljPTRDEC_POST_STRING
                        ElseIf mapVariableTypes() & #C2FLAG_FLOAT
                           llObjects()\code = #ljPTRDEC_POST_FLOAT
                        Else
                           llObjects()\code = #ljPTRDEC_POST_INT
                        EndIf
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

                  ; V1.027.0: Convert PTRFETCH to type-specialized variants (no runtime If checks)
                  ; Convert PTRFETCH based on what we found
                  If isArrayPointer
                     ; V1.027.0: Convert to typed ARREL variant (was kept as generic)
                     ; Determine element type from GETARRAYADDR variant
                     Select getAddrType
                        Case #ljGETARRAYADDRF
                           llObjects()\code = #ljPTRFETCH_ARREL_FLOAT
                        Case #ljGETARRAYADDRS
                           llObjects()\code = #ljPTRFETCH_ARREL_STR
                        Default
                           llObjects()\code = #ljPTRFETCH_ARREL_INT
                     EndSelect
                  ElseIf foundGetAddr
                     ; V1.027.0: Convert to typed VAR variant (no If check needed)
                     Select getAddrType
                        Case #ljGETADDRF
                           llObjects()\code = #ljPTRFETCH_VAR_FLOAT
                        Case #ljGETADDRS
                           llObjects()\code = #ljPTRFETCH_VAR_STR
                        Default
                           llObjects()\code = #ljPTRFETCH_VAR_INT
                     EndSelect
                  Else
                     ; Couldn't find GETADDR - default to simple variable int variant
                     llObjects()\code = #ljPTRFETCH_VAR_INT
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
      ; V1.027.0: Updated to handle VAR and ARREL variants
      ; Now that PTRFETCH is typed, fix PRTI that follow typed PTRFETCH
      ForEach llObjects()
         If llObjects()\code = #ljPRTI
            If PreviousElement(llObjects())
               ; V1.027.0: Check for float variants (VAR and ARREL)
               If llObjects()\code = #ljPTRFETCH_VAR_FLOAT Or llObjects()\code = #ljPTRFETCH_ARREL_FLOAT
                  NextElement(llObjects())
                  llObjects()\code = #ljPRTF
                  PreviousElement(llObjects())
               ; V1.027.0: Check for string variants (VAR and ARREL)
               ElseIf llObjects()\code = #ljPTRFETCH_VAR_STR Or llObjects()\code = #ljPTRFETCH_ARREL_STR
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
      ;- Enhanced Instruction Fusion Optimizations
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
                     ; V1.022.89: Handle LFETCH for local index variables (recursion safety)
                     ElseIf (llObjects()\code = #ljLFETCH Or llObjects()\code = #ljLFETCHF Or llObjects()\code = #ljLFETCHS)
                        ; Get the local offset from LFETCH's i field
                        localOffset = llObjects()\i
                        NextElement(llObjects())  ; Back to ARRAYFETCH/ARRAYSTORE

                        ; Encode local offset as negative value: -(offset + 2)
                        ; This distinguishes from ndx=-1 (stack) and ndx>=0 (global)
                        llObjects()\ndx = -(localOffset + 2)
                        CompilerIf #DEBUG
                           Debug "      [Pass9] LOCAL index optimized: offset=" + Str(localOffset) + " encoded as ndx=" + Str(llObjects()\ndx)
                        CompilerEndIf

                        ; Mark LFETCH as NOOP
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
               arrayStoreIdx = ListIndex(llObjects())  ; V1.022.89: Save ARRAYSTORE position
               CompilerIf #DEBUG
                  Debug "    [Pass11] Found ARRAYSTORE at pos=" + Str(arrayStoreIdx) + " n=" + Str(llObjects()\n)
               CompilerEndIf
               If PreviousElement(llObjects())
                  ; V1.022.89: Skip NOOPs (from Pass 9 index optimization) to find value instruction
                  While llObjects()\code = #ljNOOP
                     If Not PreviousElement(llObjects())
                        Break
                     EndIf
                  Wend
                  valueInstrIdx = ListIndex(llObjects())  ; Save value instruction position
                  CompilerIf #DEBUG
                     Debug "    [Pass11] Value instruction code=" + Str(llObjects()\code) + " at pos=" + Str(valueInstrIdx) + " (LFETCH=" + Str(#ljLFETCH) + " LFETCHF=" + Str(#ljLFETCHF) + ")"
                  CompilerEndIf
                  If (llObjects()\code = #ljPush Or llObjects()\code = #ljPUSHF Or llObjects()\code = #ljPUSHS)
                     ; Get the value variable/constant slot (GLOBAL)
                     valueSlot = llObjects()\i

                     ; Mark PUSH as NOOP first (while we're positioned at it)
                     llObjects()\code = #ljNOOP
                     AdjustJumpsForNOOP(ListIndex(llObjects()))

                     ; Navigate back to ARRAYSTORE and set n field
                     SelectElement(llObjects(), arrayStoreIdx)
                     llObjects()\n = valueSlot
                     optimized = #True
                  ; V1.022.87: Also handle LFETCH (local variable value) for proper recursion safety
                  ElseIf (llObjects()\code = #ljLFETCH Or llObjects()\code = #ljLFETCHF Or llObjects()\code = #ljLFETCHS)
                     ; Get the local offset from LFETCH's i field
                     localOffset = llObjects()\i
                     CompilerIf #DEBUG
                        Debug "    [Pass11] Found LFETCH before ARRAYSTORE: localOffset=" + Str(localOffset)
                     CompilerEndIf

                     ; Mark LFETCH as NOOP first (while we're positioned at it)
                     llObjects()\code = #ljNOOP
                     AdjustJumpsForNOOP(ListIndex(llObjects()))

                     ; Navigate back to ARRAYSTORE
                     SelectElement(llObjects(), arrayStoreIdx)
                     ; Encode local offset as negative value for pass 12: -(offset + 2)
                     llObjects()\n = -(localOffset + 2)
                     optimized = #True
                     CompilerIf #DEBUG
                        Debug "    [Pass11] Encoded n=" + Str(llObjects()\n) + " for ARRAYSTORE"
                     CompilerEndIf
                  Else
                     ; Not a value instruction, navigate back to ARRAYSTORE
                     SelectElement(llObjects(), arrayStoreIdx)
                  EndIf
               EndIf

               ; If not optimized AND n is not already set (slot-only mode), set n = -1
               ; V1.022.23: Skip if n >= 0 (codegen already set value slot directly)
               ; V1.022.90: Skip if n < -1 (codegen already set local encoding for local temps)
               If Not optimized And llObjects()\n = -1
                  ; n is -1 (stack mode), keep it - no change needed
                  ; Note: n >= 0 means global slot, n < -1 means local encoding
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
            ; V1.022.86: ndx encoding: >=0 = global slot, -1 = STACK, < -1 = local offset (-(ndx+2))
            Case #ljARRAYFETCH_INT
               If llObjects()\j = 0  ; Global array
                  If llObjects()\ndx >= 0
                     llObjects()\code = #ljARRAYFETCH_INT_GLOBAL_OPT
                  ElseIf llObjects()\ndx < -1  ; V1.022.86: Local index temp
                     llObjects()\code = #ljARRAYFETCH_INT_GLOBAL_LOPT
                     llObjects()\ndx = -(llObjects()\ndx + 2)  ; Decode to local offset
                  Else  ; ndx = -1: STACK
                     llObjects()\code = #ljARRAYFETCH_INT_GLOBAL_STACK
                  EndIf
               Else  ; Local array
                  If llObjects()\ndx >= 0
                     llObjects()\code = #ljARRAYFETCH_INT_LOCAL_OPT
                  ElseIf llObjects()\ndx < -1  ; V1.022.113: Local index variable
                     llObjects()\code = #ljARRAYFETCH_INT_LOCAL_LOPT
                     llObjects()\ndx = -(llObjects()\ndx + 2)  ; Decode to local offset
                  Else  ; ndx = -1: STACK
                     llObjects()\code = #ljARRAYFETCH_INT_LOCAL_STACK
                  EndIf
               EndIf

            Case #ljARRAYFETCH_FLOAT
               If llObjects()\j = 0  ; Global array
                  If llObjects()\ndx >= 0
                     llObjects()\code = #ljARRAYFETCH_FLOAT_GLOBAL_OPT
                  ElseIf llObjects()\ndx < -1  ; V1.022.86: Local index temp
                     llObjects()\code = #ljARRAYFETCH_FLOAT_GLOBAL_LOPT
                     llObjects()\ndx = -(llObjects()\ndx + 2)  ; Decode to local offset
                  Else  ; ndx = -1: STACK
                     llObjects()\code = #ljARRAYFETCH_FLOAT_GLOBAL_STACK
                  EndIf
               Else  ; Local array
                  If llObjects()\ndx >= 0
                     llObjects()\code = #ljARRAYFETCH_FLOAT_LOCAL_OPT
                  ElseIf llObjects()\ndx < -1  ; V1.022.113: Local index variable
                     llObjects()\code = #ljARRAYFETCH_FLOAT_LOCAL_LOPT
                     llObjects()\ndx = -(llObjects()\ndx + 2)  ; Decode to local offset
                  Else  ; ndx = -1: STACK
                     llObjects()\code = #ljARRAYFETCH_FLOAT_LOCAL_STACK
                  EndIf
               EndIf

            Case #ljARRAYFETCH_STR
               If llObjects()\j = 0  ; Global array
                  If llObjects()\ndx >= 0
                     llObjects()\code = #ljARRAYFETCH_STR_GLOBAL_OPT
                  ElseIf llObjects()\ndx < -1  ; V1.022.86: Local index temp
                     llObjects()\code = #ljARRAYFETCH_STR_GLOBAL_LOPT
                     llObjects()\ndx = -(llObjects()\ndx + 2)  ; Decode to local offset
                  Else  ; ndx = -1: STACK
                     llObjects()\code = #ljARRAYFETCH_STR_GLOBAL_STACK
                  EndIf
               Else  ; Local array
                  If llObjects()\ndx >= 0
                     llObjects()\code = #ljARRAYFETCH_STR_LOCAL_OPT
                  ElseIf llObjects()\ndx < -1  ; V1.022.113: Local index variable
                     llObjects()\code = #ljARRAYFETCH_STR_LOCAL_LOPT
                     llObjects()\ndx = -(llObjects()\ndx + 2)  ; Decode to local offset
                  Else  ; ndx = -1: STACK
                     llObjects()\code = #ljARRAYFETCH_STR_LOCAL_STACK
                  EndIf
               EndIf

            ; ARRAYSTORE specialization (3 dimensions: global/local, index source, value source)
            ; V1.022.86: ndx/n encoding: >=0 = global slot, -1 = STACK, < -1 = local offset (-(val+2))
            Case #ljARRAYSTORE_INT
               If llObjects()\j = 0  ; Global array
                  If llObjects()\ndx >= 0  ; Global optimized index
                     If llObjects()\n >= 0  ; Optimized value
                        llObjects()\code = #ljARRAYSTORE_INT_GLOBAL_OPT_OPT
                     ElseIf llObjects()\n < -1  ; V1.022.114: Local value temp (function scope expression result)
                        llObjects()\n = -(llObjects()\n + 2)  ; Decode to local offset
                        llObjects()\code = #ljARRAYSTORE_INT_GLOBAL_OPT_LOPT
                     Else  ; Stack value (n = -1)
                        llObjects()\code = #ljARRAYSTORE_INT_GLOBAL_OPT_STACK
                     EndIf
                  ElseIf llObjects()\ndx < -1  ; V1.022.86: Local index temp
                     llObjects()\ndx = -(llObjects()\ndx + 2)  ; Decode to local offset
                     If llObjects()\n < -1  ; Local value temp
                        llObjects()\n = -(llObjects()\n + 2)
                        llObjects()\code = #ljARRAYSTORE_INT_GLOBAL_LOPT_LOPT
                     ElseIf llObjects()\n >= 0  ; Global value
                        llObjects()\code = #ljARRAYSTORE_INT_GLOBAL_LOPT_OPT
                     Else  ; Stack value (n = -1)
                        llObjects()\code = #ljARRAYSTORE_INT_GLOBAL_LOPT_STACK
                     EndIf
                  Else  ; Stack index (ndx = -1)
                     If llObjects()\n >= 0  ; Optimized value
                        llObjects()\code = #ljARRAYSTORE_INT_GLOBAL_STACK_OPT
                     ElseIf llObjects()\n < -1  ; V1.022.91: Local value with stack index - ERROR case!
                        CompilerIf #DEBUG
                           Debug "    [Pass12] ERROR: STACK index with LOCAL value! ndx=" + Str(llObjects()\ndx) + " n=" + Str(llObjects()\n) + " at pos=" + Str(ListIndex(llObjects()))
                        CompilerEndIf
                        ; Fall back to STACK_STACK (will be buggy, but at least we know)
                        llObjects()\code = #ljARRAYSTORE_INT_GLOBAL_STACK_STACK
                     Else  ; Stack value (n = -1)
                        llObjects()\code = #ljARRAYSTORE_INT_GLOBAL_STACK_STACK
                     EndIf
                  EndIf
               Else  ; Local array
                  If llObjects()\ndx >= 0  ; Global optimized index (OPT)
                     If llObjects()\n >= 0  ; Global optimized value
                        llObjects()\code = #ljARRAYSTORE_INT_LOCAL_OPT_OPT
                     ElseIf llObjects()\n < -1  ; V1.022.115: Local value temp (function scope expression result)
                        llObjects()\n = -(llObjects()\n + 2)  ; Decode to local offset
                        llObjects()\code = #ljARRAYSTORE_INT_LOCAL_OPT_LOPT
                     Else  ; Stack value (n = -1)
                        llObjects()\code = #ljARRAYSTORE_INT_LOCAL_OPT_STACK
                     EndIf
                  ElseIf llObjects()\ndx < -1  ; V1.022.113: Local index variable (LOPT)
                     llObjects()\ndx = -(llObjects()\ndx + 2)  ; Decode to local offset
                     If llObjects()\n < -1  ; Local value (LOPT)
                        llObjects()\n = -(llObjects()\n + 2)
                        llObjects()\code = #ljARRAYSTORE_INT_LOCAL_LOPT_LOPT
                     ElseIf llObjects()\n >= 0  ; Global value (OPT)
                        llObjects()\code = #ljARRAYSTORE_INT_LOCAL_LOPT_OPT
                     Else  ; Stack value (n = -1)
                        llObjects()\code = #ljARRAYSTORE_INT_LOCAL_LOPT_STACK
                     EndIf
                  Else  ; Stack index (ndx = -1)
                     If llObjects()\n >= 0  ; Optimized value
                        llObjects()\code = #ljARRAYSTORE_INT_LOCAL_STACK_OPT
                     ElseIf llObjects()\n < -1  ; V1.022.113: Local value with stack index - fall back
                        llObjects()\code = #ljARRAYSTORE_INT_LOCAL_STACK_STACK
                     Else  ; Stack value
                        llObjects()\code = #ljARRAYSTORE_INT_LOCAL_STACK_STACK
                     EndIf
                  EndIf
               EndIf

            Case #ljARRAYSTORE_FLOAT
               CompilerIf #DEBUG
                  Debug "    [Pass12] ARRAYSTORE_FLOAT at pos=" + Str(ListIndex(llObjects())) + " j=" + Str(llObjects()\j) + " ndx=" + Str(llObjects()\ndx) + " n=" + Str(llObjects()\n)
               CompilerEndIf
               If llObjects()\j = 0  ; Global array
                  If llObjects()\ndx >= 0  ; Global optimized index
                     If llObjects()\n >= 0  ; Optimized value
                        llObjects()\code = #ljARRAYSTORE_FLOAT_GLOBAL_OPT_OPT
                     ElseIf llObjects()\n < -1  ; V1.022.114: Local value temp (function scope expression result)
                        llObjects()\n = -(llObjects()\n + 2)  ; Decode to local offset
                        llObjects()\code = #ljARRAYSTORE_FLOAT_GLOBAL_OPT_LOPT
                     Else  ; Stack value (n = -1)
                        llObjects()\code = #ljARRAYSTORE_FLOAT_GLOBAL_OPT_STACK
                     EndIf
                  ElseIf llObjects()\ndx < -1  ; V1.022.86: Local index temp
                     llObjects()\ndx = -(llObjects()\ndx + 2)  ; Decode to local offset
                     If llObjects()\n < -1  ; Local value temp
                        llObjects()\n = -(llObjects()\n + 2)
                        llObjects()\code = #ljARRAYSTORE_FLOAT_GLOBAL_LOPT_LOPT
                     ElseIf llObjects()\n >= 0  ; Global value
                        llObjects()\code = #ljARRAYSTORE_FLOAT_GLOBAL_LOPT_OPT
                     Else  ; Stack value (n = -1)
                        llObjects()\code = #ljARRAYSTORE_FLOAT_GLOBAL_LOPT_STACK
                     EndIf
                  Else  ; Stack index (ndx = -1)
                     If llObjects()\n >= 0  ; Optimized value
                        llObjects()\code = #ljARRAYSTORE_FLOAT_GLOBAL_STACK_OPT
                     ElseIf llObjects()\n < -1  ; V1.022.91: Local value with stack index - ERROR case!
                        CompilerIf #DEBUG
                           Debug "    [Pass12] ERROR: FLOAT STACK index with LOCAL value! ndx=" + Str(llObjects()\ndx) + " n=" + Str(llObjects()\n) + " at pos=" + Str(ListIndex(llObjects()))
                        CompilerEndIf
                        ; Fall back to STACK_STACK (will be buggy, but at least we know)
                        llObjects()\code = #ljARRAYSTORE_FLOAT_GLOBAL_STACK_STACK
                     Else  ; Stack value (n = -1)
                        llObjects()\code = #ljARRAYSTORE_FLOAT_GLOBAL_STACK_STACK
                     EndIf
                  EndIf
               Else  ; Local array
                  If llObjects()\ndx >= 0  ; Global optimized index (OPT)
                     If llObjects()\n >= 0  ; Global optimized value
                        llObjects()\code = #ljARRAYSTORE_FLOAT_LOCAL_OPT_OPT
                     ElseIf llObjects()\n < -1  ; V1.022.115: Local value temp (function scope expression result)
                        llObjects()\n = -(llObjects()\n + 2)  ; Decode to local offset
                        llObjects()\code = #ljARRAYSTORE_FLOAT_LOCAL_OPT_LOPT
                     Else  ; Stack value (n = -1)
                        llObjects()\code = #ljARRAYSTORE_FLOAT_LOCAL_OPT_STACK
                     EndIf
                  ElseIf llObjects()\ndx < -1  ; V1.022.113: Local index variable (LOPT)
                     llObjects()\ndx = -(llObjects()\ndx + 2)  ; Decode to local offset
                     If llObjects()\n < -1  ; Local value (LOPT)
                        llObjects()\n = -(llObjects()\n + 2)
                        llObjects()\code = #ljARRAYSTORE_FLOAT_LOCAL_LOPT_LOPT
                     ElseIf llObjects()\n >= 0  ; Global value (OPT)
                        llObjects()\code = #ljARRAYSTORE_FLOAT_LOCAL_LOPT_OPT
                     Else  ; Stack value (n = -1)
                        llObjects()\code = #ljARRAYSTORE_FLOAT_LOCAL_LOPT_STACK
                     EndIf
                  Else  ; Stack index (ndx = -1)
                     If llObjects()\n >= 0  ; Optimized value
                        llObjects()\code = #ljARRAYSTORE_FLOAT_LOCAL_STACK_OPT
                     Else  ; Stack value
                        llObjects()\code = #ljARRAYSTORE_FLOAT_LOCAL_STACK_STACK
                     EndIf
                  EndIf
               EndIf

            Case #ljARRAYSTORE_STR
               If llObjects()\j = 0  ; Global array
                  If llObjects()\ndx >= 0  ; Global optimized index
                     If llObjects()\n >= 0  ; Optimized value
                        llObjects()\code = #ljARRAYSTORE_STR_GLOBAL_OPT_OPT
                     ElseIf llObjects()\n < -1  ; V1.022.114: Local value temp (function scope expression result)
                        llObjects()\n = -(llObjects()\n + 2)  ; Decode to local offset
                        llObjects()\code = #ljARRAYSTORE_STR_GLOBAL_OPT_LOPT
                     Else  ; Stack value (n = -1)
                        llObjects()\code = #ljARRAYSTORE_STR_GLOBAL_OPT_STACK
                     EndIf
                  ElseIf llObjects()\ndx < -1  ; V1.022.86: Local index temp
                     llObjects()\ndx = -(llObjects()\ndx + 2)  ; Decode to local offset
                     If llObjects()\n < -1  ; Local value temp
                        llObjects()\n = -(llObjects()\n + 2)
                        llObjects()\code = #ljARRAYSTORE_STR_GLOBAL_LOPT_LOPT
                     ElseIf llObjects()\n >= 0  ; Global value
                        llObjects()\code = #ljARRAYSTORE_STR_GLOBAL_LOPT_OPT
                     Else  ; Stack value (n = -1)
                        llObjects()\code = #ljARRAYSTORE_STR_GLOBAL_LOPT_STACK
                     EndIf
                  Else  ; Stack index (ndx = -1)
                     If llObjects()\n >= 0  ; Optimized value
                        llObjects()\code = #ljARRAYSTORE_STR_GLOBAL_STACK_OPT
                     Else  ; Stack value
                        llObjects()\code = #ljARRAYSTORE_STR_GLOBAL_STACK_STACK
                     EndIf
                  EndIf
               Else  ; Local
                  If llObjects()\ndx >= 0  ; Global optimized index (OPT)
                     If llObjects()\n >= 0  ; Global optimized value
                        llObjects()\code = #ljARRAYSTORE_STR_LOCAL_OPT_OPT
                     ElseIf llObjects()\n < -1  ; V1.022.115: Local value temp (function scope expression result)
                        llObjects()\n = -(llObjects()\n + 2)  ; Decode to local offset
                        llObjects()\code = #ljARRAYSTORE_STR_LOCAL_OPT_LOPT
                     Else  ; Stack value (n = -1)
                        llObjects()\code = #ljARRAYSTORE_STR_LOCAL_OPT_STACK
                     EndIf
                  ElseIf llObjects()\ndx < -1  ; V1.022.113: Local index variable (LOPT)
                     llObjects()\ndx = -(llObjects()\ndx + 2)  ; Decode to local offset
                     If llObjects()\n < -1  ; Local value (LOPT)
                        llObjects()\n = -(llObjects()\n + 2)
                        llObjects()\code = #ljARRAYSTORE_STR_LOCAL_LOPT_LOPT
                     ElseIf llObjects()\n >= 0  ; Global value (OPT)
                        llObjects()\code = #ljARRAYSTORE_STR_LOCAL_LOPT_OPT
                     Else  ; Stack value (n = -1)
                        llObjects()\code = #ljARRAYSTORE_STR_LOCAL_LOPT_STACK
                     EndIf
                  Else  ; Stack index (ndx = -1)
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
         Debug "    Pass 12b: Specialize struct opcodes for local index/value source"
      CompilerEndIf

      ;- Pass 12b: Specialize struct opcodes for local index/value source (V1.022.117/118/119)
      ; When value comes from local temp (ndx < -1), use LOPT variant
      ; V1.022.119: When pointer comes from local (i < -1), use LPTR variant
      ForEach llObjects()
         Select llObjects()\code
            ; V1.022.117/119: PTRSTRUCTFETCH - pointer from local
            Case #ljPTRSTRUCTFETCH_INT
               If llObjects()\i < -1  ; Local pointer (function scope)
                  llObjects()\i = -(llObjects()\i + 2)  ; Decode to local offset
                  llObjects()\code = #ljPTRSTRUCTFETCH_INT_LPTR
               EndIf

            Case #ljPTRSTRUCTFETCH_FLOAT
               If llObjects()\i < -1
                  llObjects()\i = -(llObjects()\i + 2)
                  llObjects()\code = #ljPTRSTRUCTFETCH_FLOAT_LPTR
               EndIf

            Case #ljPTRSTRUCTFETCH_STR
               If llObjects()\i < -1
                  llObjects()\i = -(llObjects()\i + 2)
                  llObjects()\code = #ljPTRSTRUCTFETCH_STR_LPTR
               EndIf

            ; V1.022.117/119: PTRSTRUCTSTORE - check both pointer and value
            Case #ljPTRSTRUCTSTORE_INT
               Debug "[Pass12b] PTRSTRUCTSTORE_INT: i=" + Str(llObjects()\i) + " ndx=" + Str(llObjects()\ndx)
               If llObjects()\i < -1 And llObjects()\ndx < -1  ; Both local
                  llObjects()\i = -(llObjects()\i + 2)
                  llObjects()\ndx = -(llObjects()\ndx + 2)
                  llObjects()\code = #ljPTRSTRUCTSTORE_INT_LPTR_LOPT
               ElseIf llObjects()\i < -1  ; Local pointer, global value
                  llObjects()\i = -(llObjects()\i + 2)
                  llObjects()\code = #ljPTRSTRUCTSTORE_INT_LPTR
               ElseIf llObjects()\ndx < -1  ; Global pointer, local value
                  llObjects()\ndx = -(llObjects()\ndx + 2)
                  llObjects()\code = #ljPTRSTRUCTSTORE_INT_LOPT
               EndIf

            Case #ljPTRSTRUCTSTORE_FLOAT
               If llObjects()\i < -1 And llObjects()\ndx < -1  ; Both local
                  llObjects()\i = -(llObjects()\i + 2)
                  llObjects()\ndx = -(llObjects()\ndx + 2)
                  llObjects()\code = #ljPTRSTRUCTSTORE_FLOAT_LPTR_LOPT
               ElseIf llObjects()\i < -1  ; Local pointer, global value
                  llObjects()\i = -(llObjects()\i + 2)
                  llObjects()\code = #ljPTRSTRUCTSTORE_FLOAT_LPTR
               ElseIf llObjects()\ndx < -1  ; Global pointer, local value
                  llObjects()\ndx = -(llObjects()\ndx + 2)
                  llObjects()\code = #ljPTRSTRUCTSTORE_FLOAT_LOPT
               EndIf

            Case #ljPTRSTRUCTSTORE_STR
               If llObjects()\i < -1 And llObjects()\ndx < -1  ; Both local
                  llObjects()\i = -(llObjects()\i + 2)
                  llObjects()\ndx = -(llObjects()\ndx + 2)
                  llObjects()\code = #ljPTRSTRUCTSTORE_STR_LPTR_LOPT
               ElseIf llObjects()\i < -1  ; Local pointer, global value
                  llObjects()\i = -(llObjects()\i + 2)
                  llObjects()\code = #ljPTRSTRUCTSTORE_STR_LPTR
               ElseIf llObjects()\ndx < -1  ; Global pointer, local value
                  llObjects()\ndx = -(llObjects()\ndx + 2)
                  llObjects()\code = #ljPTRSTRUCTSTORE_STR_LOPT
               EndIf

            ; V1.022.118: ARRAYOFSTRUCT - index from local temp
            Case #ljARRAYOFSTRUCT_FETCH_INT
               If llObjects()\ndx < -1  ; Local index temp
                  llObjects()\ndx = -(llObjects()\ndx + 2)  ; Decode to local offset
                  llObjects()\code = #ljARRAYOFSTRUCT_FETCH_INT_LOPT
               EndIf

            Case #ljARRAYOFSTRUCT_FETCH_FLOAT
               If llObjects()\ndx < -1
                  llObjects()\ndx = -(llObjects()\ndx + 2)
                  llObjects()\code = #ljARRAYOFSTRUCT_FETCH_FLOAT_LOPT
               EndIf

            Case #ljARRAYOFSTRUCT_FETCH_STR
               If llObjects()\ndx < -1
                  llObjects()\ndx = -(llObjects()\ndx + 2)
                  llObjects()\code = #ljARRAYOFSTRUCT_FETCH_STR_LOPT
               EndIf

            Case #ljARRAYOFSTRUCT_STORE_INT
               If llObjects()\ndx < -1
                  llObjects()\ndx = -(llObjects()\ndx + 2)
                  llObjects()\code = #ljARRAYOFSTRUCT_STORE_INT_LOPT
               EndIf

            Case #ljARRAYOFSTRUCT_STORE_FLOAT
               If llObjects()\ndx < -1
                  llObjects()\ndx = -(llObjects()\ndx + 2)
                  llObjects()\code = #ljARRAYOFSTRUCT_STORE_FLOAT_LOPT
               EndIf

            Case #ljARRAYOFSTRUCT_STORE_STR
               If llObjects()\ndx < -1
                  llObjects()\ndx = -(llObjects()\ndx + 2)
                  llObjects()\code = #ljARRAYOFSTRUCT_STORE_STR_LOPT
               EndIf
         EndSelect
      Next

      CompilerIf #DEBUG
         Debug "    Pass 13: Add implicit returns to functions without explicit returns"
      CompilerEndIf

      ;- Pass 13: Add implicit returns to functions without explicit returns (V1.20.34: renamed from Pass 1c)
      ; Scan for function boundaries and ensure each has a RET before next function/HALT
      ; V1.022.93: CRITICAL FIX - When previous element is NOOPIF, REPLACE it with RETURN
      ;            instead of inserting new RETURN. This preserves jump tracker targets!
      ;            Without this fix, JZ targets pointing to NOOPIF become dangling pointers
      ;            when NOOPIF is deleted, causing jumps to wrong locations.
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
                     ; V1.022.93: Check if previous element is NOOPIF (common JZ target)
                     ; If so, REPLACE it with RETURN to preserve jump targets
                     Protected prevIsNoopif.b = #False
                     Protected *prevElement = #Null

                     If PreviousElement(llObjects())
                        If llObjects()\code = #ljNOOPIF Or llObjects()\code = #ljNOOP
                           prevIsNoopif = #True
                           *prevElement = @llObjects()
                           CompilerIf #DEBUG
                              Debug "Pass13: Found NOOPIF at function end - replacing with RETURN to preserve jump targets"
                           CompilerEndIf
                        EndIf
                        NextElement(llObjects())  ; Back to function/HALT
                     EndIf

                     If prevIsNoopif And *prevElement
                        ; REPLACE the NOOPIF with RETURN - this preserves jump tracker targets!
                        ChangeCurrentElement(llObjects(), *prevElement)
                        llObjects()\code = #ljreturn
                        llObjects()\i = 0
                        llObjects()\j = 0
                        llObjects()\n = 0
                        llObjects()\ndx = -1
                        NextElement(llObjects())  ; Back to function/HALT
                     Else
                        ; No NOOPIF before function - insert new RETURN
                        ; Insert RET before FUNCTION/HALT marker (after last instruction of function)
                        InsertElement(llObjects())
                        llObjects()\code = #ljreturn
                        llObjects()\i = 0
                        llObjects()\j = 0
                        llObjects()\n = 0
                        llObjects()\ndx = -1
                        NextElement(llObjects())  ; Move back to function/HALT
                     EndIf
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
               ; V1.022.93: Check if last element is NOOPIF
               LastElement(llObjects())
               If llObjects()\code = #ljNOOPIF Or llObjects()\code = #ljNOOP
                  ; Replace NOOPIF with RETURN
                  llObjects()\code = #ljreturn
                  llObjects()\i = 0
                  llObjects()\j = 0
                  llObjects()\n = 0
                  llObjects()\ndx = -1
                  CompilerIf #DEBUG
                     Debug "Pass13: Replaced NOOPIF at end of code with RETURN"
                  CompilerEndIf
               Else
                  ; Position at last element, then add RET after it
                  AddElement(llObjects())
                  llObjects()\code = #ljreturn
                  llObjects()\i = 0
                  llObjects()\j = 0
                  llObjects()\n = 0
                  llObjects()\ndx = -1
               EndIf
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
            Case #ljStore, #ljSTORES, #ljSTOREF, #ljSTORE_STRUCT  ; V1.029.84: Include STORE_STRUCT
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
      ; V1.027.0: Use type-specialized opcodes to eliminate runtime Select
      ForEach llObjects()
         Select llObjects()\code
            Case #ljADD_ASSIGN_VAR
               ; Check if variable is a pointer
               varSlot = llObjects()\i
               If varSlot >= 0 And varSlot < gnLastVariable
                  searchKey = gVarMeta(varSlot)\name
                  If FindMapElement(mapVariableTypes(), searchKey)
                     If mapVariableTypes() & #C2FLAG_POINTER
                        ; V1.027.0: Select typed variant based on pointer type
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
               ; Check if variable is a pointer
               varSlot = llObjects()\i
               If varSlot >= 0 And varSlot < gnLastVariable
                  searchKey = gVarMeta(varSlot)\name
                  If FindMapElement(mapVariableTypes(), searchKey)
                     If mapVariableTypes() & #C2FLAG_POINTER
                        ; V1.027.0: Select typed variant based on pointer type
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

      ;- V1.023.0: Build variable preloading templates
      ; This builds gGlobalTemplate and gFuncTemplates from gVarMeta values
      ; Variables marked with #C2FLAG_PRELOAD have their constant init values stored
      CompilerIf #DEBUG
         Debug "    Building variable preloading templates..."
      CompilerEndIf

      ; V1.023.17: Build global template - resize to gnLastVariable (not gnGlobalVariables)
      ; Slots aren't allocated in order - constants come before variables
      ; So we need to cover all slots and check flags to identify preloadable globals
      If gnLastVariable > 0
         ReDim gGlobalTemplate.stVarTemplate(gnLastVariable - 1)
         Protected preloadCount.i = 0
         For i = 0 To gnLastVariable - 1
            ; V1.023.17: Only populate template for global variables (not constants)
            ; Global vars have: paramOffset=-1, no CONST flag
            If gVarMeta(i)\paramOffset = -1 And Not (gVarMeta(i)\flags & #C2FLAG_CONST)
               ; Copy metadata to template for this global variable
               If gVarMeta(i)\flags & #C2FLAG_INT
                  gGlobalTemplate(i)\i = gVarMeta(i)\valueInt
                  CompilerIf #DEBUG
                     ; V1.027.8: Show template values for preloadable variables
                     If gVarMeta(i)\flags & #C2FLAG_PRELOAD
                        Debug "V1.027.8: Template[" + Str(i) + "] '" + gVarMeta(i)\name + "' = " + Str(gVarMeta(i)\valueInt) + " (PRELOAD)"
                     EndIf
                  CompilerEndIf
               ElseIf gVarMeta(i)\flags & #C2FLAG_FLOAT
                  gGlobalTemplate(i)\f = gVarMeta(i)\valueFloat
               ElseIf gVarMeta(i)\flags & #C2FLAG_STR
                  gGlobalTemplate(i)\ss = gVarMeta(i)\valueString
               EndIf
               ; Copy array size if applicable
               gGlobalTemplate(i)\arraySize = gVarMeta(i)\arraySize
               If gVarMeta(i)\flags & #C2FLAG_PRELOAD
                  preloadCount + 1
               EndIf
            EndIf
         Next
         CompilerIf #DEBUG
            Debug "      Built global template: " + Str(gnLastVariable) + " slots, " + Str(preloadCount) + " preloadable"
         CompilerEndIf
      EndIf

      ; Build function templates - one per function
      ; First, count functions and their locals
      ; V1.023.0: Index by funcId directly (wastes slots 0..#C2FUNCSTART-1, but faster VM access)
      maxFuncId = 0
      ForEach mapModules()
         If mapModules()\function >= #C2FUNCSTART
            If mapModules()\function > maxFuncId
               maxFuncId = mapModules()\function
            EndIf
         EndIf
      Next

      If maxFuncId >= #C2FUNCSTART
         gnFuncTemplateCount = maxFuncId + 1  ; Size array to hold funcId directly
         ReDim gFuncTemplates.stFuncTemplate(maxFuncId)  ; Index 0..maxFuncId

         ; For each function, find its non-param locals and build template
         ForEach mapModules()
            If mapModules()\function >= #C2FUNCSTART
               funcId = mapModules()\function  ; Use funcId directly (no subtraction)
               funcName = MapKey(mapModules())
               funcPrefix = funcName + "_"
               nParams = mapModules()\nParams
               localCount = 0

               ; Count non-param locals for this function
               For i = 0 To gnLastVariable - 1
                  If gVarMeta(i)\paramOffset >= nParams  ; Skip params (0..nParams-1)
                     If Left(LCase(gVarMeta(i)\name), Len(funcPrefix)) = LCase(funcPrefix)
                        localCount + 1
                     EndIf
                  EndIf
               Next

               ; Build template for this function (indexed by funcId directly)
               gFuncTemplates(funcId)\funcId = funcId
               gFuncTemplates(funcId)\localCount = localCount

               If localCount > 0
                  ReDim gFuncTemplates(funcId)\template.stVarTemplate(localCount - 1)

                  ; V1.023.5: Index template by (paramOffset - nParams) to match C2CALL expectations
                  ; C2CALL applies template[i] to LOCAL[nParams + i], so template index must equal
                  ; (variable's paramOffset - nParams) for correct value placement
                  For i = 0 To gnLastVariable - 1
                     If gVarMeta(i)\paramOffset >= nParams
                        If Left(LCase(gVarMeta(i)\name), Len(funcPrefix)) = LCase(funcPrefix)
                           ; Calculate template index from paramOffset
                           templateIdx = gVarMeta(i)\paramOffset - nParams
                           If templateIdx >= 0 And templateIdx < localCount
                              ; Copy values to template at correct position
                              If gVarMeta(i)\flags & #C2FLAG_INT
                                 gFuncTemplates(funcId)\template(templateIdx)\i = gVarMeta(i)\valueInt
                              ElseIf gVarMeta(i)\flags & #C2FLAG_FLOAT
                                 gFuncTemplates(funcId)\template(templateIdx)\f = gVarMeta(i)\valueFloat
                              ElseIf gVarMeta(i)\flags & #C2FLAG_STR
                                 gFuncTemplates(funcId)\template(templateIdx)\ss = gVarMeta(i)\valueString
                              EndIf
                              gFuncTemplates(funcId)\template(templateIdx)\arraySize = gVarMeta(i)\arraySize
                           EndIf
                        EndIf
                     EndIf
                  Next
               EndIf

               CompilerIf #DEBUG
                  Debug "      Function '" + funcName + "' (funcId=" + Str(funcId) + "): " + Str(localCount) + " local template slots"
               CompilerEndIf
            EndIf
         Next
      EndIf

      ;- V1.023.0: Convert MOV/LMOV to NOOP for preloadable variables
      ; Variables with #C2FLAG_PRELOAD get their values from templates at VM init/function entry
      ; IMPORTANT: Only remove the FIRST MOV for each variable (the initialization)
      ; Subsequent runtime assignments must still execute, even if assigning a constant
      CompilerIf #DEBUG
         Debug "    Pass 26: Remove MOV instructions for preloadable variables"
      CompilerEndIf

      ; Track which global variables have had their init MOV removed
      NewMap removedGlobalInits.i()

      ; V1.023.1: Track current function for local variable name lookup
      currentFunctionName = ""

      ; V1.023.9: Track which local variables have had their init LMOV removed (per function)
      ; Key = paramOffset, cleared on each new function
      NewMap removedLocalInits.i()

      ; V1.023.10: Only optimize LMOVs in straight-line code at function entry
      ; Once we hit a control flow instruction (loop/if), stop optimizing to avoid
      ; breaking loop variable re-initialization like "op2 = 0" inside "while op1 < 4"
      Protected localOptimizationEnabled.b = #False

      ; V1.023.18: Same for global MOVs - only optimize before first control flow
      Protected globalOptimizationEnabled.b = #True

      removedMovCount = 0
      ForEach llObjects()
         ; Track function boundaries for local variable name lookup
         If llObjects()\code = #ljFUNCTION
            funcId = llObjects()\i
            currentFunctionName = ""
            ForEach mapModules()
               If mapModules()\function = funcId
                  currentFunctionName = MapKey(mapModules())
                  Break
               EndIf
            Next
            ; V1.023.9: Clear local init tracking for new function
            ClearMap(removedLocalInits())
            ; V1.023.10: Re-enable optimization at function entry
            localOptimizationEnabled = #True
         EndIf

         ; V1.023.10: Disable local optimization once we see control flow
         ; V1.023.18: Also disable global optimization
         ; This ensures we don't optimize away loop variable re-initializations
         Select llObjects()\code
            Case #ljJMP, #ljJZ, #ljCall, #ljreturn, #ljreturnF, #ljreturnS
               localOptimizationEnabled = #False
               globalOptimizationEnabled = #False
         EndSelect

         Select llObjects()\code
            ; Global MOV: i = destination slot, j = source slot
            Case #ljMOV, #ljMOVF, #ljMOVS
               ; V1.023.18: Only optimize in straight-line code before control flow
               If globalOptimizationEnabled
                  ; Check if destination is preloadable and source is constant
                  ; V1.023.17: Don't use slot range check - slots aren't allocated in order
                  ; Instead check: dst has PRELOAD flag, src is CONST, dst is global var (not const)
                  dstVar = llObjects()\i
                  srcVar = llObjects()\j
                  If dstVar >= 0 And dstVar < gnLastVariable
                     ; V1.023.17: Check dst is a global variable (paramOffset=-1, not a constant)
                     If (gVarMeta(dstVar)\flags & #C2FLAG_PRELOAD) And (gVarMeta(srcVar)\flags & #C2FLAG_CONST) And Not (gVarMeta(dstVar)\flags & #C2FLAG_CONST) And gVarMeta(dstVar)\paramOffset = -1
                        ; Only remove the FIRST MOV for each variable
                        If Not removedGlobalInits(Str(dstVar))
                           llObjects()\code = #ljNOOP
                           removedGlobalInits(Str(dstVar)) = #True
                           removedMovCount + 1
                           ; V1.023.0: Report global variable preloading
                           SetInfo("Global '" + gVarMeta(dstVar)\name + "' preloaded from template")
                           CompilerIf #DEBUG
                              Debug "V1.027.8: Pass26 REMOVED MOV '" + gVarMeta(dstVar)\name + "' srcValue=" + Str(gVarMeta(srcVar)\valueInt) + " templateValue=" + Str(gVarMeta(dstVar)\valueInt)
                           CompilerEndIf
                        CompilerIf #DEBUG
                        Else
                           Debug "V1.027.8: Pass26 KEPT MOV '" + gVarMeta(dstVar)\name + "' srcValue=" + Str(gVarMeta(srcVar)\valueInt) + " (already in removedGlobalInits)"
                        CompilerEndIf
                        EndIf
                     EndIf
                  EndIf
               EndIf

            ; Local LMOV: i = destination paramOffset, j = source slot
            ; V1.023.10: Only optimize in straight-line code before any control flow
            ; Variables initialized inside loops/conditionals must keep their LMOV
            Case #ljLMOV, #ljLMOVF, #ljLMOVS
               If localOptimizationEnabled
                  srcVar = llObjects()\j
                  localParamOffset = llObjects()\i
                  If srcVar >= 0 And srcVar < gnLastVariable
                     If gVarMeta(srcVar)\flags & #C2FLAG_CONST
                        ; Source is constant and we're in straight-line init code
                        localKey = Str(localParamOffset)
                        If Not removedLocalInits(localKey)
                           ; First LMOV for this local - template handles the init
                           llObjects()\code = #ljNOOP
                           removedLocalInits(localKey) = #True
                           removedMovCount + 1
                           ; V1.023.1: Look up actual local variable name by paramOffset and function
                           localVarName = ""
                           If currentFunctionName <> ""
                              funcPrefix = currentFunctionName + "_"
                              For varIdx = 0 To gnLastVariable - 1
                                 If gVarMeta(varIdx)\paramOffset = localParamOffset
                                    varName = gVarMeta(varIdx)\name
                                    If Left(LCase(varName), Len(funcPrefix)) = LCase(funcPrefix)
                                       ; Extract just the variable name (after function prefix)
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

      ; V1.023.0: Summary info message
      If removedMovCount > 0
         SetInfo("Preload optimization: " + Str(removedMovCount) + " MOV/LMOV instructions replaced by templates")
      EndIf

      CompilerIf #DEBUG
         Debug "      Removed " + Str(removedMovCount) + " MOV/LMOV instructions (replaced with templates)"
      CompilerEndIf

      ;- V1.026.8: Pass 27 - Convert generic collection opcodes to typed versions
      ; LIST_ADD/GET/SET/INSERT and MAP_PUT/GET/VALUE need type info for VM
      ; Look back to find the FETCH that pushed the collection variable and get its type
      ; V1.027.10: Track function context to scope local variable search correctly
      CompilerIf #DEBUG
         Debug "    Pass 27: Convert generic collection opcodes to typed versions"
      CompilerEndIf

      Protected collectionSlot.i, collectionType.w
      Protected stepsBack.i, collTypedCount.i = 0
      Protected *fetchInstr
      Protected searchLocalIdx.i
      Protected mapLocalOffset.i, mapSearchIdx.i
      ; V1.027.10: Track function context for local variable scoping
      Protected pass27FuncName.s = ""
      Protected pass27FuncId.i
      Protected pass27VarName.s
      ; V1.027.11: Variables for backwards search to find collection FETCH
      Protected maxSearchDepth.i, foundCollectionFetch.i, searchDepth.i
      Protected checkSlot.i, checkParamOffset.i

      ForEach llObjects()
         ; V1.027.10: Track function boundaries
         If llObjects()\code = #ljFUNCTION
            pass27FuncId = llObjects()\i
            pass27FuncName = ""
            ForEach mapModules()
               If mapModules()\function = pass27FuncId
                  pass27FuncName = MapKey(mapModules())
                  Break
               EndIf
            Next
         EndIf

         Select llObjects()\code
            ; List value operations - need typed conversion
            Case #ljLIST_ADD, #ljLIST_INSERT, #ljLIST_GET, #ljLIST_SET
               ; V1.027.11: Search backwards to find collection's FETCH instruction
               ; Can't use paramCount as step count because complex expressions (n*2) use multiple instructions
               ; The collection variable's FETCH is always the first FETCH before the value expression
               ; Save current position
               *fetchInstr = @llObjects()

               ; V1.027.11: Search backwards to find a FETCH that fetches from a collection variable
               ; Maximum search depth to prevent infinite loops
               maxSearchDepth = 20
               foundCollectionFetch = #False
               searchDepth = 0

               While PreviousElement(llObjects()) And searchDepth < maxSearchDepth
                  searchDepth + 1
                  ; Check if this is a FETCH/LFETCH
                  If llObjects()\code = #ljFetch Or llObjects()\code = #ljLFETCH Or llObjects()\code = #ljPFETCH Or llObjects()\code = #ljPLFETCH
                     ; Check if it fetches from a collection variable
                     checkSlot = -1
                     If llObjects()\code = #ljLFETCH Or llObjects()\code = #ljPLFETCH
                        ; Local - find by paramOffset
                        checkParamOffset = llObjects()\i
                        For searchLocalIdx = 0 To gnLastVariable - 1
                           If gVarMeta(searchLocalIdx)\paramOffset = checkParamOffset
                              ; V1.027.10: Verify this local belongs to current function
                              pass27VarName = gVarMeta(searchLocalIdx)\name
                              If pass27FuncName <> "" And Left(pass27VarName, 1) <> "$"
                                 If LCase(Left(pass27VarName, Len(pass27FuncName) + 1)) = LCase(pass27FuncName + "_")
                                    checkSlot = searchLocalIdx
                                    Break
                                 EndIf
                              ElseIf pass27FuncName = ""
                                 checkSlot = searchLocalIdx
                                 Break
                              EndIf
                           EndIf
                        Next
                     Else
                        ; Global - slot directly
                        checkSlot = llObjects()\i
                     EndIf

                     ; Check if this slot is a collection (LIST or MAP)
                     If checkSlot >= 0 And checkSlot < gnLastVariable
                        If gVarMeta(checkSlot)\flags & (#C2FLAG_LIST | #C2FLAG_MAP)
                           foundCollectionFetch = #True
                           Break
                        EndIf
                     EndIf
                  EndIf
               Wend

               If foundCollectionFetch
                  ; V1.027.11: We already found the collection slot (checkSlot) during search
                  collectionSlot = checkSlot
                  collectionType = 0

                  ; Get type from gVarMeta
                  Protected collectionStructType.s = ""
                  Protected collectionStructSize.i = 0
                  If collectionSlot >= 0 And collectionSlot < gnLastVariable
                     collectionType = gVarMeta(collectionSlot)\flags & (#C2FLAG_INT | #C2FLAG_FLOAT | #C2FLAG_STR)
                     ; V1.029.28: Check for struct element type
                     ; V1.029.31: Use totalSize for flattened struct size (supports nested structs)
                     collectionStructType = gVarMeta(collectionSlot)\structType
                     If collectionStructType <> "" And FindMapElement(mapStructDefs(), collectionStructType)
                        collectionStructSize = mapStructDefs()\totalSize
                     EndIf
                  EndIf

                  ; Restore to collection opcode
                  ChangeCurrentElement(llObjects(), *fetchInstr)

                  ; Convert based on type and opcode
                  Select llObjects()\code
                     Case #ljLIST_ADD
                        ; V1.029.28: Check for struct type first
                        ; V1.029.65: Use _PTR variant for \ptr storage model
                        If collectionStructType <> "" And collectionStructSize > 0
                           llObjects()\code = #ljLIST_ADD_STRUCT_PTR
                           llObjects()\i = collectionStructSize * 8  ; Byte size (8 bytes per field)
                           ; V1.031.33: Generate string field bitmap for deep copy
                           Protected listAddFieldIdx.i = 0
                           llObjects()\j = GenerateStructTypeBitmap(collectionStructType, @listAddFieldIdx)
                        ElseIf collectionType & #C2FLAG_STR
                           llObjects()\code = #ljLIST_ADD_STR
                        ElseIf collectionType & #C2FLAG_FLOAT
                           llObjects()\code = #ljLIST_ADD_FLOAT
                        Else
                           llObjects()\code = #ljLIST_ADD_INT
                        EndIf
                        collTypedCount + 1
                     Case #ljLIST_INSERT
                        If collectionType & #C2FLAG_STR
                           llObjects()\code = #ljLIST_INSERT_STR
                        ElseIf collectionType & #C2FLAG_FLOAT
                           llObjects()\code = #ljLIST_INSERT_FLOAT
                        Else
                           llObjects()\code = #ljLIST_INSERT_INT
                        EndIf
                        collTypedCount + 1
                     Case #ljLIST_GET
                        ; V1.029.28: Check for struct type first
                        ; V1.029.65: Use _PTR variant for \ptr storage model
                        If collectionStructType <> "" And collectionStructSize > 0
                           llObjects()\code = #ljLIST_GET_STRUCT_PTR
                           llObjects()\i = collectionStructSize * 8  ; Byte size
                           ; V1.029.31: Find following STORE and get destination slot
                           ; V1.029.66: Look ahead up to 3 elements for STORE (in case of type conversion ops)
                           ;            Also include struct store opcodes in check
                           Protected *listGetPos = @llObjects()
                           Protected listStoreFound.b = #False
                           Protected listLookAhead.i = 0
                           While NextElement(llObjects()) And listLookAhead < 3 And Not listStoreFound
                              ; V1.031.32: Check for any STORE variant (regular, struct, or local)
                              If llObjects()\code = #ljStore Or llObjects()\code = #ljSTOREF Or llObjects()\code = #ljSTORES Or llObjects()\code = #ljSTRUCT_STORE_INT Or llObjects()\code = #ljSTRUCT_STORE_FLOAT Or llObjects()\code = #ljSTRUCT_STORE_STR Or llObjects()\code = #ljSTORE_STRUCT
                                 ; Found global STORE - capture destination slot
                                 Protected listDestSlot.i = llObjects()\i
                                 llObjects()\code = #ljNOOP  ; Remove STORE
                                 ; Go back to LIST_GET_STRUCT_PTR and set destination
                                 ChangeCurrentElement(llObjects(), *listGetPos)
                                 llObjects()\j = listDestSlot
                                 listStoreFound = #True
                              ElseIf llObjects()\code = #ljLSTORE_STRUCT Or llObjects()\code = #ljLSTORE Or llObjects()\code = #ljLSTOREF Or llObjects()\code = #ljLSTORES
                                 ; V1.031.32: Found LOCAL STORE - capture offset with local flag
                                 listDestSlot = llObjects()\i | #C2_LOCAL_COLLECTION_FLAG
                                 llObjects()\code = #ljNOOP  ; Remove STORE
                                 ; Go back to LIST_GET_STRUCT_PTR and set destination with local flag
                                 ChangeCurrentElement(llObjects(), *listGetPos)
                                 llObjects()\j = listDestSlot
                                 listStoreFound = #True
                              ElseIf llObjects()\code = #ljNOOP
                                 ; Skip NOOPs
                                 listLookAhead + 1
                              Else
                                 ; Found non-STORE, non-NOOP - stop looking
                                 listLookAhead = 3
                              EndIf
                           Wend
                           If Not listStoreFound
                              ; No STORE found - restore position
                              ChangeCurrentElement(llObjects(), *listGetPos)
                           EndIf
                        ElseIf collectionType & #C2FLAG_STR
                           llObjects()\code = #ljLIST_GET_STR
                        ElseIf collectionType & #C2FLAG_FLOAT
                           llObjects()\code = #ljLIST_GET_FLOAT
                        Else
                           llObjects()\code = #ljLIST_GET_INT
                        EndIf
                        collTypedCount + 1
                     Case #ljLIST_SET
                        ; V1.029.35: Check for struct type first
                        If collectionStructType <> "" And collectionStructSize > 0
                           llObjects()\code = #ljLIST_SET_STRUCT
                           llObjects()\i = collectionStructSize
                           ; V1.029.35: Generate field type bitmap
                           Protected listSetFieldIdx.i = 0
                           llObjects()\n = GenerateStructTypeBitmap(collectionStructType, @listSetFieldIdx)
                        ElseIf collectionType & #C2FLAG_STR
                           llObjects()\code = #ljLIST_SET_STR
                        ElseIf collectionType & #C2FLAG_FLOAT
                           llObjects()\code = #ljLIST_SET_FLOAT
                        Else
                           llObjects()\code = #ljLIST_SET_INT
                        EndIf
                        collTypedCount + 1
                  EndSelect
               Else
                  ; Didn't find FETCH, restore position
                  ChangeCurrentElement(llObjects(), *fetchInstr)
               EndIf

            ; Map value operations - need typed conversion
            Case #ljMAP_PUT, #ljMAP_GET, #ljMAP_VALUE
               ; V1.027.11: Search backwards to find collection's FETCH instruction
               ; Can't use paramCount as step count because complex expressions use multiple instructions
               *fetchInstr = @llObjects()

               ; V1.027.11: Search backwards to find a FETCH that fetches from a collection variable
               maxSearchDepth = 20
               foundCollectionFetch = #False
               searchDepth = 0
               checkSlot = -1

               While PreviousElement(llObjects()) And searchDepth < maxSearchDepth
                  searchDepth + 1
                  If llObjects()\code = #ljFetch Or llObjects()\code = #ljLFETCH Or llObjects()\code = #ljPFETCH Or llObjects()\code = #ljPLFETCH
                     ; Check if it fetches from a collection variable
                     checkSlot = -1
                     If llObjects()\code = #ljLFETCH Or llObjects()\code = #ljPLFETCH
                        ; Local - find by paramOffset
                        checkParamOffset = llObjects()\i
                        For mapSearchIdx = 0 To gnLastVariable - 1
                           If gVarMeta(mapSearchIdx)\paramOffset = checkParamOffset
                              pass27VarName = gVarMeta(mapSearchIdx)\name
                              If pass27FuncName <> "" And Left(pass27VarName, 1) <> "$"
                                 If LCase(Left(pass27VarName, Len(pass27FuncName) + 1)) = LCase(pass27FuncName + "_")
                                    checkSlot = mapSearchIdx
                                    Break
                                 EndIf
                              ElseIf pass27FuncName = ""
                                 checkSlot = mapSearchIdx
                                 Break
                              EndIf
                           EndIf
                        Next
                     Else
                        ; Global - slot directly
                        checkSlot = llObjects()\i
                     EndIf

                     ; Check if this slot is a collection (LIST or MAP)
                     If checkSlot >= 0 And checkSlot < gnLastVariable
                        If gVarMeta(checkSlot)\flags & (#C2FLAG_LIST | #C2FLAG_MAP)
                           foundCollectionFetch = #True
                           Break
                        EndIf
                     EndIf
                  EndIf
               Wend

               If foundCollectionFetch
                  ; V1.027.11: We already found the collection slot during search
                  collectionSlot = checkSlot
                  collectionType = 0

                  ; V1.029.28: Check for struct element type
                  ; V1.029.35: Use totalSize for flattened struct size (supports nested structs)
                  Protected mapStructType.s = ""
                  Protected mapStructSize.i = 0
                  If collectionSlot >= 0 And collectionSlot < gnLastVariable
                     collectionType = gVarMeta(collectionSlot)\flags & (#C2FLAG_INT | #C2FLAG_FLOAT | #C2FLAG_STR)
                     mapStructType = gVarMeta(collectionSlot)\structType
                     If mapStructType <> "" And FindMapElement(mapStructDefs(), mapStructType)
                        mapStructSize = mapStructDefs()\totalSize
                     EndIf
                  EndIf

                  ChangeCurrentElement(llObjects(), *fetchInstr)

                  Select llObjects()\code
                     Case #ljMAP_PUT
                        ; V1.029.28: Check for struct type first
                        ; V1.029.65: Use _PTR variant for \ptr storage model
                        If mapStructType <> "" And mapStructSize > 0
                           llObjects()\code = #ljMAP_PUT_STRUCT_PTR
                           llObjects()\i = mapStructSize * 8  ; Byte size
                        ElseIf collectionType & #C2FLAG_STR
                           llObjects()\code = #ljMAP_PUT_STR
                        ElseIf collectionType & #C2FLAG_FLOAT
                           llObjects()\code = #ljMAP_PUT_FLOAT
                        Else
                           llObjects()\code = #ljMAP_PUT_INT
                        EndIf
                        collTypedCount + 1
                     Case #ljMAP_GET
                        ; V1.029.28: Check for struct type first
                        ; V1.029.65: Use _PTR variant for \ptr storage model
                        If mapStructType <> "" And mapStructSize > 0
                           llObjects()\code = #ljMAP_GET_STRUCT_PTR
                           llObjects()\i = mapStructSize * 8  ; Byte size
                           ; V1.029.31: Find following STORE and get destination slot
                           ; V1.029.66: Look ahead up to 3 elements for STORE (in case of type conversion ops)
                           ;            Also include struct store opcodes in check
                           Protected *mapGetPos = @llObjects()
                           Protected mapStoreFound.b = #False
                           Protected mapLookAhead.i = 0
                           While NextElement(llObjects()) And mapLookAhead < 3 And Not mapStoreFound
                              ; Check for any STORE variant (regular or struct)
                              If llObjects()\code = #ljStore Or llObjects()\code = #ljSTOREF Or llObjects()\code = #ljSTORES Or llObjects()\code = #ljSTRUCT_STORE_INT Or llObjects()\code = #ljSTRUCT_STORE_FLOAT Or llObjects()\code = #ljSTRUCT_STORE_STR
                                 Protected mapDestSlot.i = llObjects()\i
                                 llObjects()\code = #ljNOOP  ; Remove STORE
                                 ChangeCurrentElement(llObjects(), *mapGetPos)
                                 llObjects()\j = mapDestSlot  ; Destination base slot
                                 mapStoreFound = #True
                              ElseIf llObjects()\code = #ljNOOP
                                 ; Skip NOOPs
                                 mapLookAhead + 1
                              Else
                                 ; Found non-STORE, non-NOOP - stop looking
                                 mapLookAhead = 3
                              EndIf
                           Wend
                           If Not mapStoreFound
                              ChangeCurrentElement(llObjects(), *mapGetPos)
                           EndIf
                        ElseIf collectionType & #C2FLAG_STR
                           llObjects()\code = #ljMAP_GET_STR
                        ElseIf collectionType & #C2FLAG_FLOAT
                           llObjects()\code = #ljMAP_GET_FLOAT
                        Else
                           llObjects()\code = #ljMAP_GET_INT
                        EndIf
                        collTypedCount + 1
                     Case #ljMAP_VALUE
                        ; V1.029.28: Check for struct type first
                        If mapStructType <> "" And mapStructSize > 0
                           llObjects()\code = #ljMAP_VALUE_STRUCT
                           llObjects()\i = mapStructSize
                           ; V1.029.35: Generate field type bitmap
                           Protected mapValueFieldIdx.i = 0
                           llObjects()\n = GenerateStructTypeBitmap(mapStructType, @mapValueFieldIdx)
                        ElseIf collectionType & #C2FLAG_STR
                           llObjects()\code = #ljMAP_VALUE_STR
                        ElseIf collectionType & #C2FLAG_FLOAT
                           llObjects()\code = #ljMAP_VALUE_FLOAT
                        Else
                           llObjects()\code = #ljMAP_VALUE_INT
                        EndIf
                        collTypedCount + 1
                  EndSelect
               Else
                  ChangeCurrentElement(llObjects(), *fetchInstr)
               EndIf
         EndSelect
      Next

      CompilerIf #DEBUG
         Debug "      Converted " + Str(collTypedCount) + " collection opcodes to typed versions"
      CompilerEndIf

      ;- V1.031.113: Pass 28 - Convert PUSH const to PUSH_IMM (immediate value)
      ; IMPORTANT: This MUST run AFTER all passes that use gVarMeta (passes 16-27)
      ; because it changes the operand from slot index to actual value
      ; V1.031.118: Re-enabled after stack size fix
      CompilerIf #DEBUG
         Debug "    Pass 28: Convert PUSH const to PUSH_IMM (immediate value)"
      CompilerEndIf

      CompilerIf #True ; Pass 28 enabled
      Protected pushImmCount.i = 0
      ForEach llObjects()
         If llObjects()\code = #ljPush
            Protected pushSlot.i = llObjects()\i
            ; Check if this is a valid slot and an integer constant
            ; V1.031.113: Also exclude negative slots (invalid)
            If pushSlot >= 0 And pushSlot < gnLastVariable
               If gVarMeta(pushSlot)\flags & #C2FLAG_CONST And gVarMeta(pushSlot)\flags & #C2FLAG_INT
                  ; V1.031.113: Additional safety - don't convert if it could be a string/float disguised
                  If Not (gVarMeta(pushSlot)\flags & (#C2FLAG_STR | #C2FLAG_FLOAT))
                     ; Convert to PUSH_IMM with the actual value as operand
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
      CompilerEndIf
      CompilerEndIf ; Pass 28 enabled

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
         If gVarMeta(i)\flags & #C2FLAG_PRELOAD : flags + "PRELOAD " : EndIf
         Debug "  [" + RSet(Str(i), 3) + "] " + LSet(gVarMeta(i)\name, 25) + " " + flags
      Next
      Debug "========================================="
      CompilerEndIf

      ; V1.030.10: Debug - check ALL STRUCT_* opcodes (both local and global) after postprocessor
      Debug "=== POSTPROCESSOR: Checking ALL STRUCT_* opcodes ==="
      Protected ppCheckIdx.i = 0
      ForEach llObjects()
         Select llObjects()\code
            ; LOCAL variants
            Case #ljSTRUCT_ALLOC_LOCAL
               Debug "  [" + Str(ppCheckIdx) + "] STRUCT_ALLOC_LOCAL .i=" + Str(llObjects()\i) + " .j=" + Str(llObjects()\j)
            Case #ljSTRUCT_FETCH_INT_LOCAL
               Debug "  [" + Str(ppCheckIdx) + "] STRUCT_FETCH_INT_LOCAL .i=" + Str(llObjects()\i) + " .j=" + Str(llObjects()\j)
            Case #ljSTRUCT_FETCH_FLOAT_LOCAL
               Debug "  [" + Str(ppCheckIdx) + "] STRUCT_FETCH_FLOAT_LOCAL .i=" + Str(llObjects()\i) + " .j=" + Str(llObjects()\j)
            Case #ljSTRUCT_FETCH_STR_LOCAL
               Debug "  [" + Str(ppCheckIdx) + "] STRUCT_FETCH_STR_LOCAL .i=" + Str(llObjects()\i) + " .j=" + Str(llObjects()\j)
            Case #ljSTRUCT_STORE_INT_LOCAL
               Debug "  [" + Str(ppCheckIdx) + "] STRUCT_STORE_INT_LOCAL .i=" + Str(llObjects()\i) + " .j=" + Str(llObjects()\j)
            Case #ljSTRUCT_STORE_FLOAT_LOCAL
               Debug "  [" + Str(ppCheckIdx) + "] STRUCT_STORE_FLOAT_LOCAL .i=" + Str(llObjects()\i) + " .j=" + Str(llObjects()\j)
            Case #ljSTRUCT_STORE_STR_LOCAL
               Debug "  [" + Str(ppCheckIdx) + "] STRUCT_STORE_STR_LOCAL .i=" + Str(llObjects()\i) + " .j=" + Str(llObjects()\j)
            ; GLOBAL variants (no LOCAL suffix)
            Case #ljSTRUCT_ALLOC
               Debug "  [" + Str(ppCheckIdx) + "] STRUCT_ALLOC (GLOBAL) .i=" + Str(llObjects()\i) + " .j=" + Str(llObjects()\j)
            Case #ljSTRUCT_FETCH_INT
               Debug "  [" + Str(ppCheckIdx) + "] STRUCT_FETCH_INT (GLOBAL) .i=" + Str(llObjects()\i) + " .j=" + Str(llObjects()\j)
            Case #ljSTRUCT_FETCH_FLOAT
               Debug "  [" + Str(ppCheckIdx) + "] STRUCT_FETCH_FLOAT (GLOBAL) .i=" + Str(llObjects()\i) + " .j=" + Str(llObjects()\j)
            Case #ljSTRUCT_FETCH_STR
               Debug "  [" + Str(ppCheckIdx) + "] STRUCT_FETCH_STR (GLOBAL) .i=" + Str(llObjects()\i) + " .j=" + Str(llObjects()\j)
            Case #ljSTRUCT_STORE_INT
               Debug "  [" + Str(ppCheckIdx) + "] STRUCT_STORE_INT (GLOBAL) .i=" + Str(llObjects()\i) + " .j=" + Str(llObjects()\j)
            Case #ljSTRUCT_STORE_FLOAT
               Debug "  [" + Str(ppCheckIdx) + "] STRUCT_STORE_FLOAT (GLOBAL) .i=" + Str(llObjects()\i) + " .j=" + Str(llObjects()\j)
            Case #ljSTRUCT_STORE_STR
               Debug "  [" + Str(ppCheckIdx) + "] STRUCT_STORE_STR (GLOBAL) .i=" + Str(llObjects()\i) + " .j=" + Str(llObjects()\j)
         EndSelect
         ppCheckIdx + 1
      Next
      Debug "=== END POSTPROCESSOR CHECK ==="

   EndProcedure

; IDE Options = PureBasic 6.21 (Windows - x64)
; CursorPosition = 1475
; FirstLine = 1465
; Folding = --------------
; EnableAsm
; EnableThread
; EnableXP
; CPU = 1
; EnablePurifier
; EnableCompileCount = 1
; EnableBuildCount = 0
; EnableExeConstant