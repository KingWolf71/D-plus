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
;  Compiler - PostProcessor
;- Fixes code types and correctness (no optimizations)
;- Optimizations moved to c2-optimizer-V01.pbi
;
; V1.033.0: Split from c2-postprocessor-V08.pbi
;           - Essential passes for correctness only
;           - Optimizations moved to separate optimizer file
;           - Consolidated passes to reduce total count

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

               ; V1.022.98: CRITICAL FIX - Do NOT skip NOOPIF at function ends!
               ; If NOOPIF is followed by #ljfunction/#ljHALT, it will be converted to RETURN by Pass 13.
               While llObjects()\code = #ljNOOPIF Or llObjects()\code = #ljNOOP
                  *currentNoop = @llObjects()
                  If NextElement(llObjects())
                     If llObjects()\code = #ljfunction Or llObjects()\code = #ljHALT
                        ChangeCurrentElement(llObjects(), *currentNoop)
                        CompilerIf #DEBUG
                           Debug "InitJumpTracker: Keeping pointer at function-end NOOPIF (will become RETURN)"
                        CompilerEndIf
                        Break
                     EndIf
                  Else
                     ChangeCurrentElement(llObjects(), *currentNoop)
                     Break
                  EndIf
               Wend
               pos = ListIndex(llObjects())
               *targetInstr = @llObjects()
               llObjects()\anchor = pair

               i     = 0

               ForEach llHoles()
                  If llHoles()\mode = #C2HOLE_START And llHoles()\id = pair
                     llHoles()\mode = #C2HOLE_PAIR
                        ChangeCurrentElement( llObjects(), llHoles()\location )
                        srcPos = ListIndex( llObjects() )
                        offset = (pos - srcPos)
                        llObjects()\i = offset
                        llObjects()\anchor = pair

                        AddElement(llJumpTracker())
                        llJumpTracker()\instruction = @llObjects()
                        llJumpTracker()\target = *targetInstr
                        llJumpTracker()\srcPos = srcPos
                        llJumpTracker()\targetPos = pos
                        llJumpTracker()\offset = offset
                        llJumpTracker()\type = llObjects()\code

                     Break
                  EndIf
               Next
            PopListPosition( llHoles() )
         ElseIf llHoles()\mode = #C2HOLE_BLIND
            llHoles()\mode = #C2HOLE_PAIR
            ChangeCurrentElement( llObjects(), llHoles()\src )
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

         ElseIf llHoles()\mode = #C2HOLE_LOOPBACK
            llHoles()\mode = #C2HOLE_PAIR
            ChangeCurrentElement( llObjects(), llHoles()\src )
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
            llJumpTracker()\holeMode = #C2HOLE_LOOPBACK

         ElseIf llHoles()\mode = #C2HOLE_FORLOOP
            llHoles()\mode = #C2HOLE_PAIR
            ChangeCurrentElement( llObjects(), llHoles()\src )
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

         ElseIf llHoles()\mode = #C2HOLE_CONTINUE
            llHoles()\mode = #C2HOLE_PAIR
            ChangeCurrentElement( llObjects(), llHoles()\src )
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
         EndIf
      Next

      CompilerIf #DEBUG
         Debug "InitJumpTracker: Populated " + Str(ListSize(llJumpTracker())) + " jumps"
      CompilerEndIf
   EndProcedure

Procedure            FixJMP()
      ; V1.020.077: FixJMP now runs AFTER PostProcessor and uses pre-populated tracker

      Protected         i, pos, pair
      Protected         srcPos.i
      Protected         offset.i
      Protected         targetPos
      Protected         noopCount.i

      CompilerIf #DEBUG
         Debug "FixJMP: Starting post-optimization fixup (tracker has " + Str(ListSize(llJumpTracker())) + " jumps)"
      CompilerEndIf

      ; Convert all NOOPIF markers to NOOP
      ForEach llObjects()
         If llObjects()\code = #ljNOOPIF
            llObjects()\code = #ljNOOP
         EndIf
      Next

      CompilerIf #DEBUG
         Debug "    Pass: Convert NOOPs at function ends to RETURN"
      CompilerEndIf

      ; Convert NOOPs at function ends to RETURN
      Protected *savedNoop
      Protected convertedCount.i = 0
      Protected noopPos.i = 0
      Protected nextCode.i = 0
      Protected inFunction.i = #False
      ForEach llObjects()
         If llObjects()\code = #ljfunction
            inFunction = #True
         EndIf
         If llObjects()\code = #ljNOOP Or llObjects()\code = #ljNOOPIF
            *savedNoop = @llObjects()
            noopPos = ListIndex(llObjects())
            If NextElement(llObjects())
               nextCode = llObjects()\code
               If llObjects()\code = #ljfunction Or (llObjects()\code = #ljHALT And inFunction)
                  ChangeCurrentElement(llObjects(), *savedNoop)
                  llObjects()\code = #ljreturn
                  llObjects()\i = 0
                  llObjects()\j = 0
                  llObjects()\n = 0
                  llObjects()\ndx = -1
                  convertedCount + 1
               Else
                  ChangeCurrentElement(llObjects(), *savedNoop)
               EndIf
            Else
               ChangeCurrentElement(llObjects(), *savedNoop)
               If inFunction
                  llObjects()\code = #ljreturn
                  llObjects()\i = 0
                  llObjects()\j = 0
                  llObjects()\n = 0
                  llObjects()\ndx = -1
                  convertedCount + 1
               EndIf
            EndIf
         EndIf
      Next
      CompilerIf #DEBUG
         Debug "  Converted " + Str(convertedCount) + " NOOPs at function ends to RETURN"
      CompilerEndIf

      ; Delete all NOOP instructions
      noopCount = 0
      Protected *currentNoop, *nextInstr
      ForEach llObjects()
         If llObjects()\code = #ljNOOP Or llObjects()\code = #ljNOOPIF
            *currentNoop = @llObjects()
            *nextInstr = #Null
            PushListPosition(llObjects())
            If NextElement(llObjects())
               *nextInstr = @llObjects()
            EndIf
            PopListPosition(llObjects())
            ; Update any jump tracker entries that target this NOOP
            If *nextInstr
               PushListPosition(llJumpTracker())
               ForEach llJumpTracker()
                  If llJumpTracker()\target = *currentNoop
                     llJumpTracker()\target = *nextInstr
                  EndIf
               Next
               PopListPosition(llJumpTracker())
            EndIf
            noopCount + 1
            DeleteElement(llObjects())
         EndIf
      Next
      CompilerIf #DEBUG
         Debug "  Deleted " + Str(noopCount) + " NOOP instructions"
      CompilerEndIf

      ; Recalculate jump offsets AFTER NOOP deletion using stored pointers
      ForEach llJumpTracker()
         If ChangeCurrentElement(llObjects(), llJumpTracker()\instruction)
            srcPos = ListIndex(llObjects())
            If llJumpTracker()\target And ChangeCurrentElement(llObjects(), llJumpTracker()\target)
               targetPos = ListIndex(llObjects())
               offset = targetPos - srcPos
               llJumpTracker()\instruction\i = offset
            EndIf
         EndIf
      Next

      ; Recalculate function addresses after NOOP removal
      ForEach mapModules()
         If mapModules()\NewPos
            If ChangeCurrentElement(llObjects(), mapModules()\NewPos)
               mapModules()\Index = ListIndex(llObjects()) + 1
            EndIf
         EndIf
      Next

      ; Patch all CALL instructions with correct function addresses
      ; V1.033.12: Also handle optimized CALL0, CALL1, CALL2 opcodes
      ForEach llObjects()
         If llObjects()\code = #ljCall Or llObjects()\code = #ljCALL0 Or llObjects()\code = #ljCALL1 Or llObjects()\code = #ljCALL2
            ForEach mapModules()
               If mapModules()\function = llObjects()\i
                  llObjects()\funcid = mapModules()\function
                  llObjects()\i = mapModules()\Index
                  llObjects()\n = mapModules()\nLocals
                  Break
               EndIf
            Next
         EndIf
      Next

      ; Patch GETFUNCADDR instructions
      ForEach llObjects()
         If llObjects()\code = #ljGETFUNCADDR
            ForEach mapModules()
               If mapModules()\function = llObjects()\i
                  llObjects()\i = mapModules()\Index
                  Break
               EndIf
            Next
         EndIf
      Next
   EndProcedure

Procedure            PostProcessor()
      Protected n.i, i.i
      Protected opCode.i
      Protected varIdx.i
      Protected funcId.i
      Protected varName.s
      Protected flags.s
      ; Pointer tracking variables
      Protected ptrVarSlot.i
      Protected ptrVarKey.s
      Protected sourceIsPointer.b
      Protected sourceIsArrayPointer.b
      Protected pointerBaseType.i
      Protected ptrOpcode.i
      Protected currentFunctionName.s
      Protected srcSlot.i
      Protected srcVarKey.s
      Protected searchKey.s
      Protected srcVar.i, dstVar.i
      Protected isPointer.b
      Protected getAddrType.i
      Protected isArrayElementPointer.b
      Protected isArrayPointer.b
      Protected savedPos
      Protected foundGetAddr.i
      Protected varSlot.i
      Protected funcName.s
      Protected funcPrefix.s
      Protected nParams.i
      Protected localCount.i
      Protected templateIdx.i
      Protected maxFuncId.i
      Protected needsReturn.i
      Protected foundEnd.i

      CompilerIf #DEBUG
         Debug "=== PostProcessor V09 (Essential Passes Only) ==="
         Debug "    Pass 1: Pointer type tracking (consolidated)"
      CompilerEndIf

      ;- ========================================
      ;- PASS 1: POINTER TYPE TRACKING (Consolidated from Pass 1, 1a, 1b)
      ;- ========================================
      ; Traverse bytecode to identify ALL pointer variables
      ; Mark them with #C2FLAG_POINTER in mapVariableTypes

      ForEach llObjects()
         Select llObjects()\code
            ; Variables assigned from GETADDR or GETARRAYADDR are pointers
            Case #ljGETADDR, #ljGETADDRF, #ljGETADDRS, #ljGETARRAYADDR, #ljGETARRAYADDRF, #ljGETARRAYADDRS, #ljGETSTRUCTADDR
               getAddrType = llObjects()\code
               If NextElement(llObjects())
                  If llObjects()\code = #ljStore Or llObjects()\code = #ljSTORES Or llObjects()\code = #ljSTOREF Or llObjects()\code = #ljSTORE_STRUCT Or
                     llObjects()\code = #ljPOP Or llObjects()\code = #ljPOPS Or llObjects()\code = #ljPOPF
                     ptrVarSlot = llObjects()\i
                     If ptrVarSlot >= 0 And ptrVarSlot < gnLastVariable
                        ptrVarKey = gVarMeta(ptrVarSlot)\name
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
                        If isArrayElementPointer
                           mapVariableTypes(ptrVarKey) = #C2FLAG_POINTER | pointerBaseType | #C2FLAG_ARRAYPTR
                        Else
                           mapVariableTypes(ptrVarKey) = #C2FLAG_POINTER | pointerBaseType
                        EndIf
                     EndIf
                  EndIf
                  PreviousElement(llObjects())
               EndIf

            ; Variables assigned from pointer arithmetic
            Case #ljPTRADD, #ljPTRSUB
               If NextElement(llObjects())
                  If llObjects()\code = #ljStore Or llObjects()\code = #ljSTORES Or llObjects()\code = #ljSTOREF Or llObjects()\code = #ljSTORE_STRUCT Or
                     llObjects()\code = #ljPOP Or llObjects()\code = #ljPOPS Or llObjects()\code = #ljPOPF
                     ptrVarSlot = llObjects()\i
                     If ptrVarSlot >= 0 And ptrVarSlot < gnLastVariable
                        ptrVarKey = gVarMeta(ptrVarSlot)\name
                        mapVariableTypes(ptrVarKey) = #C2FLAG_POINTER | #C2FLAG_INT | #C2FLAG_ARRAYPTR
                     EndIf
                  EndIf
                  PreviousElement(llObjects())
               EndIf

            ; Variables assigned from other pointers via MOV
            Case #ljMOV, #ljPMOV, #ljLMOV
               srcVar = llObjects()\j
               dstVar = llObjects()\i
               sourceIsPointer = #False
               sourceIsArrayPointer = #False
               If srcVar >= 0 And srcVar < gnLastVariable
                  searchKey = gVarMeta(srcVar)\name
                  If FindMapElement(mapVariableTypes(), searchKey)
                     If mapVariableTypes() & #C2FLAG_POINTER
                        sourceIsPointer = #True
                        pointerBaseType = mapVariableTypes() & #C2FLAG_TYPE
                        sourceIsArrayPointer = Bool((mapVariableTypes() & #C2FLAG_ARRAYPTR) <> 0)
                     EndIf
                  EndIf
                  If Not sourceIsPointer And (gVarMeta(srcVar)\flags & #C2FLAG_PARAM)
                     sourceIsPointer = #True
                     pointerBaseType = #C2FLAG_INT
                     sourceIsArrayPointer = #False
                  EndIf
               EndIf
               If sourceIsPointer And dstVar >= 0 And dstVar < gnLastVariable
                  ptrVarKey = gVarMeta(dstVar)\name
                  If sourceIsArrayPointer
                     mapVariableTypes(ptrVarKey) = #C2FLAG_POINTER | pointerBaseType | #C2FLAG_ARRAYPTR
                  Else
                     mapVariableTypes(ptrVarKey) = #C2FLAG_POINTER | pointerBaseType
                  EndIf
               EndIf

            ; Variables used with PTRFETCH/PTRSTORE operations are pointers (from Pass 1a)
            Case #ljPTRFETCH_INT, #ljPTRFETCH_FLOAT, #ljPTRFETCH_STR, #ljPTRSTORE_INT, #ljPTRSTORE_FLOAT, #ljPTRSTORE_STR
               ptrOpcode = llObjects()\code
               If PreviousElement(llObjects())
                  If llObjects()\code = #ljFetch Or llObjects()\code = #ljPFETCH
                     ptrVarSlot = llObjects()\i
                     ptrVarKey = ""
                     If ptrVarSlot >= 0 And ptrVarSlot < gnLastVariable
                        ptrVarKey = gVarMeta(ptrVarSlot)\name
                     EndIf
                     If ptrVarKey <> ""
                        If Not FindMapElement(mapVariableTypes(), ptrVarKey)
                           AddMapElement(mapVariableTypes(), ptrVarKey)
                        EndIf
                        If (mapVariableTypes() & #C2FLAG_POINTER) = 0
                           Select ptrOpcode
                              Case #ljPTRFETCH_INT, #ljPTRSTORE_INT
                                 mapVariableTypes() = #C2FLAG_POINTER | #C2FLAG_INT
                              Case #ljPTRFETCH_FLOAT, #ljPTRSTORE_FLOAT
                                 mapVariableTypes() = #C2FLAG_POINTER | #C2FLAG_FLOAT
                              Case #ljPTRFETCH_STR, #ljPTRSTORE_STR
                                 mapVariableTypes() = #C2FLAG_POINTER | #C2FLAG_STR
                           EndSelect
                        EndIf
                     EndIf
                  EndIf
                  NextElement(llObjects())
               EndIf
         EndSelect
      Next

      ; Pass 1b: Track pointer parameters via PTRFETCH usage
      currentFunctionName = ""
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
         EndIf
         If llObjects()\code = #ljPLFETCH Or llObjects()\code = #ljLFETCH
            srcSlot = llObjects()\i
            srcVarKey = ""
            For varIdx = 0 To gnLastVariable - 1
               If gVarMeta(varIdx)\paramOffset = srcSlot
                  varName = gVarMeta(varIdx)\name
                  If currentFunctionName <> "" And Left(varName, 1) <> "$"
                     If Left(varName, Len(currentFunctionName) + 1) = currentFunctionName + "_"
                        srcVarKey = varName
                        Break
                     EndIf
                  ElseIf currentFunctionName = ""
                     srcVarKey = varName
                     Break
                  EndIf
               EndIf
            Next
            If srcVarKey <> "" And NextElement(llObjects())
               Select llObjects()\code
                  Case #ljPTRFETCH_INT, #ljPTRFETCH_FLOAT, #ljPTRFETCH_STR, #ljPTRSTORE_INT, #ljPTRSTORE_FLOAT, #ljPTRSTORE_STR
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
                     EndIf
               EndSelect
               PreviousElement(llObjects())
            EndIf
         EndIf
      Next

      CompilerIf #DEBUG
         Debug "    Pass 2: Type-based opcode fixups"
      CompilerEndIf

      ;- ========================================
      ;- PASS 2: TYPE-BASED OPCODE FIXUPS
      ;- ========================================
      ForEach llObjects()
         Select llObjects()\code
            Case #ljPush
               n = llObjects()\i
               If n >= 0 And n < gnLastVariable
                  If Not (gVarMeta(n)\flags & #C2FLAG_PARAM)
                     If gVarMeta(n)\flags & #C2FLAG_FLOAT
                        llObjects()\code = #ljPUSHF
                     ElseIf gVarMeta(n)\flags & #C2FLAG_STR
                        llObjects()\code = #ljPUSHS
                     EndIf
                  EndIf
               EndIf

            Case #ljGETADDR
               n = llObjects()\i
               If n >= 0 And n < gnLastVariable
                  If gVarMeta(n)\flags & #C2FLAG_FLOAT
                     llObjects()\code = #ljGETADDRF
                  ElseIf gVarMeta(n)\flags & #C2FLAG_STR
                     llObjects()\code = #ljGETADDRS
                  EndIf
               EndIf

            Case #ljFetch
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
               srcVar = llObjects()\j
               dstVar = llObjects()\i
               isPointer = #False
               If dstVar >= 0 And dstVar < gnLastVariable
                  searchKey = gVarMeta(dstVar)\name
                  If FindMapElement(mapVariableTypes(), searchKey)
                     If mapVariableTypes() & #C2FLAG_POINTER
                        isPointer = #True
                     EndIf
                  EndIf
               EndIf
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
               n = llObjects()\i
               For varIdx = 0 To gnLastVariable - 1
                  If gVarMeta(varIdx)\paramOffset = n
                     searchKey = gVarMeta(varIdx)\name
                     If FindMapElement(mapVariableTypes(), searchKey)
                        If mapVariableTypes() & #C2FLAG_POINTER
                           llObjects()\code = #ljPLFETCH
                           Break
                        EndIf
                     EndIf
                  EndIf
               Next

            Case #ljLSTORE
               n = llObjects()\i
               For varIdx = 0 To gnLastVariable - 1
                  If gVarMeta(varIdx)\paramOffset = n
                     searchKey = gVarMeta(varIdx)\name
                     If FindMapElement(mapVariableTypes(), searchKey)
                        If mapVariableTypes() & #C2FLAG_POINTER
                           llObjects()\code = #ljPLSTORE
                           Break
                        EndIf
                     EndIf
                  EndIf
               Next

            ; Pointer increment/decrement conversions
            Case #ljINC_VAR
               n = llObjects()\i
               If n >= 0 And n < gnLastVariable
                  searchKey = gVarMeta(n)\name
                  If FindMapElement(mapVariableTypes(), searchKey)
                     If mapVariableTypes() & #C2FLAG_POINTER
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
               n = llObjects()\i
               If n >= 0 And n < gnLastVariable
                  searchKey = gVarMeta(n)\name
                  If FindMapElement(mapVariableTypes(), searchKey)
                     If mapVariableTypes() & #C2FLAG_POINTER
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

            Case #ljINC_VAR_PRE, #ljINC_VAR_POST
               n = llObjects()\i
               If n >= 0 And n < gnLastVariable
                  searchKey = gVarMeta(n)\name
                  If FindMapElement(mapVariableTypes(), searchKey)
                     If mapVariableTypes() & #C2FLAG_POINTER
                        If llObjects()\code = #ljINC_VAR_PRE
                           If mapVariableTypes() & #C2FLAG_ARRAYPTR
                              llObjects()\code = #ljPTRINC_PRE_ARRAY
                           ElseIf mapVariableTypes() & #C2FLAG_STR
                              llObjects()\code = #ljPTRINC_PRE_STRING
                           ElseIf mapVariableTypes() & #C2FLAG_FLOAT
                              llObjects()\code = #ljPTRINC_PRE_FLOAT
                           Else
                              llObjects()\code = #ljPTRINC_PRE_INT
                           EndIf
                        Else
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
               EndIf

            Case #ljDEC_VAR_PRE, #ljDEC_VAR_POST
               n = llObjects()\i
               If n >= 0 And n < gnLastVariable
                  searchKey = gVarMeta(n)\name
                  If FindMapElement(mapVariableTypes(), searchKey)
                     If mapVariableTypes() & #C2FLAG_POINTER
                        If llObjects()\code = #ljDEC_VAR_PRE
                           If mapVariableTypes() & #C2FLAG_ARRAYPTR
                              llObjects()\code = #ljPTRDEC_PRE_ARRAY
                           ElseIf mapVariableTypes() & #C2FLAG_STR
                              llObjects()\code = #ljPTRDEC_PRE_STRING
                           ElseIf mapVariableTypes() & #C2FLAG_FLOAT
                              llObjects()\code = #ljPTRDEC_PRE_FLOAT
                           Else
                              llObjects()\code = #ljPTRDEC_PRE_INT
                           EndIf
                        Else
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
               EndIf

            ; Local pointer increment/decrement
            Case #ljLINC_VAR, #ljLDEC_VAR, #ljLINC_VAR_PRE, #ljLINC_VAR_POST, #ljLDEC_VAR_PRE, #ljLDEC_VAR_POST
               n = llObjects()\i
               If n >= 0 And n < gnLastVariable
                  searchKey = gVarMeta(n)\name
                  If FindMapElement(mapVariableTypes(), searchKey)
                     If mapVariableTypes() & #C2FLAG_POINTER
                        Select llObjects()\code
                           Case #ljLINC_VAR
                              If mapVariableTypes() & #C2FLAG_ARRAYPTR : llObjects()\code = #ljPTRINC_ARRAY
                              ElseIf mapVariableTypes() & #C2FLAG_STR : llObjects()\code = #ljPTRINC_STRING
                              ElseIf mapVariableTypes() & #C2FLAG_FLOAT : llObjects()\code = #ljPTRINC_FLOAT
                              Else : llObjects()\code = #ljPTRINC_INT : EndIf
                           Case #ljLDEC_VAR
                              If mapVariableTypes() & #C2FLAG_ARRAYPTR : llObjects()\code = #ljPTRDEC_ARRAY
                              ElseIf mapVariableTypes() & #C2FLAG_STR : llObjects()\code = #ljPTRDEC_STRING
                              ElseIf mapVariableTypes() & #C2FLAG_FLOAT : llObjects()\code = #ljPTRDEC_FLOAT
                              Else : llObjects()\code = #ljPTRDEC_INT : EndIf
                           Case #ljLINC_VAR_PRE
                              If mapVariableTypes() & #C2FLAG_ARRAYPTR : llObjects()\code = #ljPTRINC_PRE_ARRAY
                              ElseIf mapVariableTypes() & #C2FLAG_STR : llObjects()\code = #ljPTRINC_PRE_STRING
                              ElseIf mapVariableTypes() & #C2FLAG_FLOAT : llObjects()\code = #ljPTRINC_PRE_FLOAT
                              Else : llObjects()\code = #ljPTRINC_PRE_INT : EndIf
                           Case #ljLDEC_VAR_PRE
                              If mapVariableTypes() & #C2FLAG_ARRAYPTR : llObjects()\code = #ljPTRDEC_PRE_ARRAY
                              ElseIf mapVariableTypes() & #C2FLAG_STR : llObjects()\code = #ljPTRDEC_PRE_STRING
                              ElseIf mapVariableTypes() & #C2FLAG_FLOAT : llObjects()\code = #ljPTRDEC_PRE_FLOAT
                              Else : llObjects()\code = #ljPTRDEC_PRE_INT : EndIf
                           Case #ljLINC_VAR_POST
                              If mapVariableTypes() & #C2FLAG_ARRAYPTR : llObjects()\code = #ljPTRINC_POST_ARRAY
                              ElseIf mapVariableTypes() & #C2FLAG_STR : llObjects()\code = #ljPTRINC_POST_STRING
                              ElseIf mapVariableTypes() & #C2FLAG_FLOAT : llObjects()\code = #ljPTRINC_POST_FLOAT
                              Else : llObjects()\code = #ljPTRINC_POST_INT : EndIf
                           Case #ljLDEC_VAR_POST
                              If mapVariableTypes() & #C2FLAG_ARRAYPTR : llObjects()\code = #ljPTRDEC_POST_ARRAY
                              ElseIf mapVariableTypes() & #C2FLAG_STR : llObjects()\code = #ljPTRDEC_POST_STRING
                              ElseIf mapVariableTypes() & #C2FLAG_FLOAT : llObjects()\code = #ljPTRDEC_POST_FLOAT
                              Else : llObjects()\code = #ljPTRDEC_POST_INT : EndIf
                        EndSelect
                     EndIf
                  EndIf
               EndIf

            ; Convert ADD/SUB to pointer arithmetic
            Case #ljADD
               If PreviousElement(llObjects())
                  If llObjects()\code = #ljPush Or llObjects()\code = #ljFetch Or llObjects()\code = #ljLFETCH Or llObjects()\code = #ljPFETCH
                     If PreviousElement(llObjects())
                        If llObjects()\code = #ljFetch Or llObjects()\code = #ljLFETCH Or llObjects()\code = #ljPFETCH
                           n = llObjects()\i
                           If n >= 0 And n < gnLastVariable
                              searchKey = gVarMeta(n)\name
                              If FindMapElement(mapVariableTypes(), searchKey)
                                 If mapVariableTypes() & #C2FLAG_POINTER
                                    NextElement(llObjects())
                                    NextElement(llObjects())
                                    llObjects()\code = #ljPTRADD
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

            Case #ljSUBTRACT
               If PreviousElement(llObjects())
                  If llObjects()\code = #ljPush Or llObjects()\code = #ljFetch Or llObjects()\code = #ljLFETCH Or llObjects()\code = #ljPFETCH
                     If PreviousElement(llObjects())
                        If llObjects()\code = #ljFetch Or llObjects()\code = #ljLFETCH Or llObjects()\code = #ljPFETCH
                           n = llObjects()\i
                           If n >= 0 And n < gnLastVariable
                              searchKey = gVarMeta(n)\name
                              If FindMapElement(mapVariableTypes(), searchKey)
                                 If mapVariableTypes() & #C2FLAG_POINTER
                                    NextElement(llObjects())
                                    NextElement(llObjects())
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

            ; Fix print types
            Case #ljPRTI
               If PreviousElement(llObjects())
                  If llObjects()\code = #ljPTRFETCH_FLOAT
                     NextElement(llObjects())
                     llObjects()\code = #ljPRTF
                     PreviousElement(llObjects())
                  ElseIf llObjects()\code = #ljPTRFETCH_STR
                     NextElement(llObjects())
                     llObjects()\code = #ljPRTS
                     PreviousElement(llObjects())
                  ElseIf llObjects()\code = #ljFETCHF Or llObjects()\code = #ljPUSHF Or llObjects()\code = #ljLFETCHF
                     NextElement(llObjects())
                     llObjects()\code = #ljPRTF
                     PreviousElement(llObjects())
                  ElseIf llObjects()\code = #ljFETCHS Or llObjects()\code = #ljPUSHS Or llObjects()\code = #ljLFETCHS
                     NextElement(llObjects())
                     llObjects()\code = #ljPRTS
                     PreviousElement(llObjects())
                  ElseIf llObjects()\code = #ljFetch Or llObjects()\code = #ljPush
                     n = llObjects()\i
                     If n >= 0 And n < gnLastVariable
                        If gVarMeta(n)\flags & #C2FLAG_FLOAT
                           NextElement(llObjects())
                           llObjects()\code = #ljPRTF
                           PreviousElement(llObjects())
                        ElseIf gVarMeta(n)\flags & #C2FLAG_STR
                           NextElement(llObjects())
                           llObjects()\code = #ljPRTS
                           PreviousElement(llObjects())
                        EndIf
                     EndIf
                  ElseIf llObjects()\code = #ljFLOATADD Or llObjects()\code = #ljFLOATSUB Or
                         llObjects()\code = #ljFLOATMUL Or llObjects()\code = #ljFLOATDIV Or
                         llObjects()\code = #ljFLOATNEG
                     NextElement(llObjects())
                     llObjects()\code = #ljPRTF
                     PreviousElement(llObjects())
                  ElseIf llObjects()\code = #ljSTRADD
                     NextElement(llObjects())
                     llObjects()\code = #ljPRTS
                     PreviousElement(llObjects())
                  ElseIf llObjects()\code = #ljARRAYFETCH_FLOAT Or
                         llObjects()\code = #ljARRAYFETCH_FLOAT_GLOBAL_OPT Or
                         llObjects()\code = #ljARRAYFETCH_FLOAT_GLOBAL_STACK Or
                         llObjects()\code = #ljARRAYFETCH_FLOAT_LOCAL_OPT Or
                         llObjects()\code = #ljARRAYFETCH_FLOAT_LOCAL_STACK
                     NextElement(llObjects())
                     llObjects()\code = #ljPRTF
                     PreviousElement(llObjects())
                  ElseIf llObjects()\code = #ljARRAYFETCH_STR Or
                         llObjects()\code = #ljARRAYFETCH_STR_GLOBAL_OPT Or
                         llObjects()\code = #ljARRAYFETCH_STR_GLOBAL_STACK Or
                         llObjects()\code = #ljARRAYFETCH_STR_LOCAL_OPT Or
                         llObjects()\code = #ljARRAYFETCH_STR_LOCAL_STACK
                     NextElement(llObjects())
                     llObjects()\code = #ljPRTS
                     PreviousElement(llObjects())
                  EndIf
                  NextElement(llObjects())
               EndIf
         EndSelect
      Next

      CompilerIf #DEBUG
         Debug "    Pass 3: PTRFETCH specialization"
      CompilerEndIf

      ;- ========================================
      ;- PASS 3: PTRFETCH SPECIALIZATION
      ;- V1.033.5: Added local pointer detection for LVAR/LARREL opcodes
      ;- ========================================
      Protected isLocalPointer.b
      ForEach llObjects()
         If llObjects()\code = #ljPTRFETCH
            If PreviousElement(llObjects())
               If llObjects()\code = #ljFetch Or llObjects()\code = #ljFETCHF Or llObjects()\code = #ljFETCHS Or llObjects()\code = #ljLFETCH Or llObjects()\code = #ljLFETCHF Or llObjects()\code = #ljLFETCHS
                  varSlot = llObjects()\i
                  savedPos = @llObjects()
                  foundGetAddr = #False
                  isArrayPointer = #False
                  isLocalPointer = #False
                  getAddrType = #ljGETADDR

                  While PreviousElement(llObjects())
                     If (llObjects()\code = #ljStore Or llObjects()\code = #ljPOP Or llObjects()\code = #ljLSTORE) And llObjects()\i = varSlot
                        If PreviousElement(llObjects())
                           ; Global variable address
                           If llObjects()\code = #ljGETADDR Or llObjects()\code = #ljGETADDRF Or llObjects()\code = #ljGETADDRS
                              getAddrType = llObjects()\code
                              foundGetAddr = #True
                              Break
                           ; Global array address
                           ElseIf llObjects()\code = #ljGETARRAYADDR Or llObjects()\code = #ljGETARRAYADDRF Or llObjects()\code = #ljGETARRAYADDRS
                              getAddrType = llObjects()\code
                              isArrayPointer = #True
                              Break
                           ; V1.033.5: Local variable address
                           ElseIf llObjects()\code = #ljGETLOCALADDR Or llObjects()\code = #ljGETLOCALADDRF Or llObjects()\code = #ljGETLOCALADDRS
                              getAddrType = llObjects()\code
                              foundGetAddr = #True
                              isLocalPointer = #True
                              Break
                           ; V1.033.5: Local array address
                           ElseIf llObjects()\code = #ljGETLOCALARRAYADDR Or llObjects()\code = #ljGETLOCALARRAYADDRF Or llObjects()\code = #ljGETLOCALARRAYADDRS
                              getAddrType = llObjects()\code
                              isArrayPointer = #True
                              isLocalPointer = #True
                              Break
                           ElseIf llObjects()\code = #ljPTRADD Or llObjects()\code = #ljPTRSUB
                              isArrayPointer = #True
                              Break
                           Else
                              NextElement(llObjects())
                           EndIf
                        Else
                           Break
                        EndIf
                     EndIf
                  Wend

                  ChangeCurrentElement(llObjects(), savedPos)
                  NextElement(llObjects())

                  If isArrayPointer
                     If isLocalPointer
                        ; V1.033.5: Local array element pointer
                        Select getAddrType
                           Case #ljGETLOCALARRAYADDRF
                              llObjects()\code = #ljPTRFETCH_LARREL_FLOAT
                           Case #ljGETLOCALARRAYADDRS
                              llObjects()\code = #ljPTRFETCH_LARREL_STR
                           Default
                              llObjects()\code = #ljPTRFETCH_LARREL_INT
                        EndSelect
                     Else
                        ; Global array element pointer
                        Select getAddrType
                           Case #ljGETARRAYADDRF
                              llObjects()\code = #ljPTRFETCH_ARREL_FLOAT
                           Case #ljGETARRAYADDRS
                              llObjects()\code = #ljPTRFETCH_ARREL_STR
                           Default
                              llObjects()\code = #ljPTRFETCH_ARREL_INT
                        EndSelect
                     EndIf
                  ElseIf foundGetAddr
                     If isLocalPointer
                        ; V1.033.5: Local simple variable pointer
                        Select getAddrType
                           Case #ljGETLOCALADDRF
                              llObjects()\code = #ljPTRFETCH_LVAR_FLOAT
                           Case #ljGETLOCALADDRS
                              llObjects()\code = #ljPTRFETCH_LVAR_STR
                           Default
                              llObjects()\code = #ljPTRFETCH_LVAR_INT
                        EndSelect
                     Else
                        ; Global simple variable pointer
                        Select getAddrType
                           Case #ljGETADDRF
                              llObjects()\code = #ljPTRFETCH_VAR_FLOAT
                           Case #ljGETADDRS
                              llObjects()\code = #ljPTRFETCH_VAR_STR
                           Default
                              llObjects()\code = #ljPTRFETCH_VAR_INT
                        EndSelect
                     EndIf
                  Else
                     llObjects()\code = #ljPTRFETCH_VAR_INT
                  EndIf
               Else
                  NextElement(llObjects())
               EndIf
            EndIf
         EndIf
      Next

      CompilerIf #DEBUG
         Debug "    Pass 4: Print type fixups (consolidated)"
      CompilerEndIf

      ;- ========================================
      ;- PASS 4: PRINT TYPE FIXUPS (Consolidated from Pass 6, 8)
      ;- V1.033.5: Added local pointer opcode detection
      ;- ========================================
      ForEach llObjects()
         If llObjects()\code = #ljPRTI
            If PreviousElement(llObjects())
               If llObjects()\code = #ljPTRFETCH_VAR_FLOAT Or llObjects()\code = #ljPTRFETCH_ARREL_FLOAT Or llObjects()\code = #ljPTRFETCH_LVAR_FLOAT Or llObjects()\code = #ljPTRFETCH_LARREL_FLOAT
                  NextElement(llObjects())
                  llObjects()\code = #ljPRTF
                  PreviousElement(llObjects())
               ElseIf llObjects()\code = #ljPTRFETCH_VAR_STR Or llObjects()\code = #ljPTRFETCH_ARREL_STR Or llObjects()\code = #ljPTRFETCH_LVAR_STR Or llObjects()\code = #ljPTRFETCH_LARREL_STR
                  NextElement(llObjects())
                  llObjects()\code = #ljPRTS
                  PreviousElement(llObjects())
               ElseIf llObjects()\code = #ljPTRFETCH
                  ; Generic PTRFETCH - use PRTPTR for runtime type check
                  NextElement(llObjects())
                  llObjects()\code = #ljPRTPTR
                  PreviousElement(llObjects())
               EndIf
               NextElement(llObjects())
            EndIf
         ElseIf llObjects()\code = #ljPRTF Or llObjects()\code = #ljPRTS
            If PreviousElement(llObjects())
               If llObjects()\code = #ljPTRFETCH
                  NextElement(llObjects())
                  llObjects()\code = #ljPRTPTR
                  PreviousElement(llObjects())
               EndIf
               NextElement(llObjects())
            EndIf
         EndIf
      Next

      CompilerIf #DEBUG
         Debug "    Pass 5: Array typing and specialization"
      CompilerEndIf

      ;- ========================================
      ;- PASS 5: ARRAY TYPING AND SPECIALIZATION (Consolidated from Pass 10, 12)
      ;- ========================================
      Protected isFetch.i
      ForEach llObjects()
         Select llObjects()\code
            Case #ljARRAYFETCH, #ljARRAYSTORE
               varSlot = llObjects()\n
               isFetch = Bool(llObjects()\code = #ljARRAYFETCH)
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

      ; Now specialize to GLOBAL/LOCAL × OPT/LOPT/STACK variants
      ForEach llObjects()
         Select llObjects()\code
            Case #ljARRAYFETCH_INT
               If llObjects()\j = 0
                  If llObjects()\ndx >= 0
                     llObjects()\code = #ljARRAYFETCH_INT_GLOBAL_OPT
                  ElseIf llObjects()\ndx < -1
                     llObjects()\code = #ljARRAYFETCH_INT_GLOBAL_LOPT
                     llObjects()\ndx = -(llObjects()\ndx + 2)
                  Else
                     llObjects()\code = #ljARRAYFETCH_INT_GLOBAL_STACK
                  EndIf
               Else
                  If llObjects()\ndx >= 0
                     llObjects()\code = #ljARRAYFETCH_INT_LOCAL_OPT
                  ElseIf llObjects()\ndx < -1
                     llObjects()\code = #ljARRAYFETCH_INT_LOCAL_LOPT
                     llObjects()\ndx = -(llObjects()\ndx + 2)
                  Else
                     llObjects()\code = #ljARRAYFETCH_INT_LOCAL_STACK
                  EndIf
               EndIf

            Case #ljARRAYFETCH_FLOAT
               If llObjects()\j = 0
                  If llObjects()\ndx >= 0
                     llObjects()\code = #ljARRAYFETCH_FLOAT_GLOBAL_OPT
                  ElseIf llObjects()\ndx < -1
                     llObjects()\code = #ljARRAYFETCH_FLOAT_GLOBAL_LOPT
                     llObjects()\ndx = -(llObjects()\ndx + 2)
                  Else
                     llObjects()\code = #ljARRAYFETCH_FLOAT_GLOBAL_STACK
                  EndIf
               Else
                  If llObjects()\ndx >= 0
                     llObjects()\code = #ljARRAYFETCH_FLOAT_LOCAL_OPT
                  ElseIf llObjects()\ndx < -1
                     llObjects()\code = #ljARRAYFETCH_FLOAT_LOCAL_LOPT
                     llObjects()\ndx = -(llObjects()\ndx + 2)
                  Else
                     llObjects()\code = #ljARRAYFETCH_FLOAT_LOCAL_STACK
                  EndIf
               EndIf

            Case #ljARRAYFETCH_STR
               If llObjects()\j = 0
                  If llObjects()\ndx >= 0
                     llObjects()\code = #ljARRAYFETCH_STR_GLOBAL_OPT
                  ElseIf llObjects()\ndx < -1
                     llObjects()\code = #ljARRAYFETCH_STR_GLOBAL_LOPT
                     llObjects()\ndx = -(llObjects()\ndx + 2)
                  Else
                     llObjects()\code = #ljARRAYFETCH_STR_GLOBAL_STACK
                  EndIf
               Else
                  If llObjects()\ndx >= 0
                     llObjects()\code = #ljARRAYFETCH_STR_LOCAL_OPT
                  ElseIf llObjects()\ndx < -1
                     llObjects()\code = #ljARRAYFETCH_STR_LOCAL_LOPT
                     llObjects()\ndx = -(llObjects()\ndx + 2)
                  Else
                     llObjects()\code = #ljARRAYFETCH_STR_LOCAL_STACK
                  EndIf
               EndIf

            Case #ljARRAYSTORE_INT
               If llObjects()\j = 0
                  If llObjects()\ndx >= 0
                     If llObjects()\n >= 0
                        llObjects()\code = #ljARRAYSTORE_INT_GLOBAL_OPT_OPT
                     ElseIf llObjects()\n < -1
                        llObjects()\n = -(llObjects()\n + 2)
                        llObjects()\code = #ljARRAYSTORE_INT_GLOBAL_OPT_LOPT
                     Else
                        llObjects()\code = #ljARRAYSTORE_INT_GLOBAL_OPT_STACK
                     EndIf
                  ElseIf llObjects()\ndx < -1
                     llObjects()\ndx = -(llObjects()\ndx + 2)
                     If llObjects()\n < -1
                        llObjects()\n = -(llObjects()\n + 2)
                        llObjects()\code = #ljARRAYSTORE_INT_GLOBAL_LOPT_LOPT
                     ElseIf llObjects()\n >= 0
                        llObjects()\code = #ljARRAYSTORE_INT_GLOBAL_LOPT_OPT
                     Else
                        llObjects()\code = #ljARRAYSTORE_INT_GLOBAL_LOPT_STACK
                     EndIf
                  Else
                     If llObjects()\n >= 0
                        llObjects()\code = #ljARRAYSTORE_INT_GLOBAL_STACK_OPT
                     Else
                        llObjects()\code = #ljARRAYSTORE_INT_GLOBAL_STACK_STACK
                     EndIf
                  EndIf
               Else
                  If llObjects()\ndx >= 0
                     If llObjects()\n >= 0
                        llObjects()\code = #ljARRAYSTORE_INT_LOCAL_OPT_OPT
                     ElseIf llObjects()\n < -1
                        llObjects()\n = -(llObjects()\n + 2)
                        llObjects()\code = #ljARRAYSTORE_INT_LOCAL_OPT_LOPT
                     Else
                        llObjects()\code = #ljARRAYSTORE_INT_LOCAL_OPT_STACK
                     EndIf
                  ElseIf llObjects()\ndx < -1
                     llObjects()\ndx = -(llObjects()\ndx + 2)
                     If llObjects()\n < -1
                        llObjects()\n = -(llObjects()\n + 2)
                        llObjects()\code = #ljARRAYSTORE_INT_LOCAL_LOPT_LOPT
                     ElseIf llObjects()\n >= 0
                        llObjects()\code = #ljARRAYSTORE_INT_LOCAL_LOPT_OPT
                     Else
                        llObjects()\code = #ljARRAYSTORE_INT_LOCAL_LOPT_STACK
                     EndIf
                  Else
                     If llObjects()\n >= 0
                        llObjects()\code = #ljARRAYSTORE_INT_LOCAL_STACK_OPT
                     Else
                        llObjects()\code = #ljARRAYSTORE_INT_LOCAL_STACK_STACK
                     EndIf
                  EndIf
               EndIf

            Case #ljARRAYSTORE_FLOAT
               If llObjects()\j = 0
                  If llObjects()\ndx >= 0
                     If llObjects()\n >= 0
                        llObjects()\code = #ljARRAYSTORE_FLOAT_GLOBAL_OPT_OPT
                     ElseIf llObjects()\n < -1
                        llObjects()\n = -(llObjects()\n + 2)
                        llObjects()\code = #ljARRAYSTORE_FLOAT_GLOBAL_OPT_LOPT
                     Else
                        llObjects()\code = #ljARRAYSTORE_FLOAT_GLOBAL_OPT_STACK
                     EndIf
                  ElseIf llObjects()\ndx < -1
                     llObjects()\ndx = -(llObjects()\ndx + 2)
                     If llObjects()\n < -1
                        llObjects()\n = -(llObjects()\n + 2)
                        llObjects()\code = #ljARRAYSTORE_FLOAT_GLOBAL_LOPT_LOPT
                     ElseIf llObjects()\n >= 0
                        llObjects()\code = #ljARRAYSTORE_FLOAT_GLOBAL_LOPT_OPT
                     Else
                        llObjects()\code = #ljARRAYSTORE_FLOAT_GLOBAL_LOPT_STACK
                     EndIf
                  Else
                     If llObjects()\n >= 0
                        llObjects()\code = #ljARRAYSTORE_FLOAT_GLOBAL_STACK_OPT
                     Else
                        llObjects()\code = #ljARRAYSTORE_FLOAT_GLOBAL_STACK_STACK
                     EndIf
                  EndIf
               Else
                  If llObjects()\ndx >= 0
                     If llObjects()\n >= 0
                        llObjects()\code = #ljARRAYSTORE_FLOAT_LOCAL_OPT_OPT
                     ElseIf llObjects()\n < -1
                        llObjects()\n = -(llObjects()\n + 2)
                        llObjects()\code = #ljARRAYSTORE_FLOAT_LOCAL_OPT_LOPT
                     Else
                        llObjects()\code = #ljARRAYSTORE_FLOAT_LOCAL_OPT_STACK
                     EndIf
                  ElseIf llObjects()\ndx < -1
                     llObjects()\ndx = -(llObjects()\ndx + 2)
                     If llObjects()\n < -1
                        llObjects()\n = -(llObjects()\n + 2)
                        llObjects()\code = #ljARRAYSTORE_FLOAT_LOCAL_LOPT_LOPT
                     ElseIf llObjects()\n >= 0
                        llObjects()\code = #ljARRAYSTORE_FLOAT_LOCAL_LOPT_OPT
                     Else
                        llObjects()\code = #ljARRAYSTORE_FLOAT_LOCAL_LOPT_STACK
                     EndIf
                  Else
                     If llObjects()\n >= 0
                        llObjects()\code = #ljARRAYSTORE_FLOAT_LOCAL_STACK_OPT
                     Else
                        llObjects()\code = #ljARRAYSTORE_FLOAT_LOCAL_STACK_STACK
                     EndIf
                  EndIf
               EndIf

            Case #ljARRAYSTORE_STR
               If llObjects()\j = 0
                  If llObjects()\ndx >= 0
                     If llObjects()\n >= 0
                        llObjects()\code = #ljARRAYSTORE_STR_GLOBAL_OPT_OPT
                     ElseIf llObjects()\n < -1
                        llObjects()\n = -(llObjects()\n + 2)
                        llObjects()\code = #ljARRAYSTORE_STR_GLOBAL_OPT_LOPT
                     Else
                        llObjects()\code = #ljARRAYSTORE_STR_GLOBAL_OPT_STACK
                     EndIf
                  ElseIf llObjects()\ndx < -1
                     llObjects()\ndx = -(llObjects()\ndx + 2)
                     If llObjects()\n < -1
                        llObjects()\n = -(llObjects()\n + 2)
                        llObjects()\code = #ljARRAYSTORE_STR_GLOBAL_LOPT_LOPT
                     ElseIf llObjects()\n >= 0
                        llObjects()\code = #ljARRAYSTORE_STR_GLOBAL_LOPT_OPT
                     Else
                        llObjects()\code = #ljARRAYSTORE_STR_GLOBAL_LOPT_STACK
                     EndIf
                  Else
                     If llObjects()\n >= 0
                        llObjects()\code = #ljARRAYSTORE_STR_GLOBAL_STACK_OPT
                     Else
                        llObjects()\code = #ljARRAYSTORE_STR_GLOBAL_STACK_STACK
                     EndIf
                  EndIf
               Else
                  If llObjects()\ndx >= 0
                     If llObjects()\n >= 0
                        llObjects()\code = #ljARRAYSTORE_STR_LOCAL_OPT_OPT
                     ElseIf llObjects()\n < -1
                        llObjects()\n = -(llObjects()\n + 2)
                        llObjects()\code = #ljARRAYSTORE_STR_LOCAL_OPT_LOPT
                     Else
                        llObjects()\code = #ljARRAYSTORE_STR_LOCAL_OPT_STACK
                     EndIf
                  ElseIf llObjects()\ndx < -1
                     llObjects()\ndx = -(llObjects()\ndx + 2)
                     If llObjects()\n < -1
                        llObjects()\n = -(llObjects()\n + 2)
                        llObjects()\code = #ljARRAYSTORE_STR_LOCAL_LOPT_LOPT
                     ElseIf llObjects()\n >= 0
                        llObjects()\code = #ljARRAYSTORE_STR_LOCAL_LOPT_OPT
                     Else
                        llObjects()\code = #ljARRAYSTORE_STR_LOCAL_LOPT_STACK
                     EndIf
                  Else
                     If llObjects()\n >= 0
                        llObjects()\code = #ljARRAYSTORE_STR_LOCAL_STACK_OPT
                     Else
                        llObjects()\code = #ljARRAYSTORE_STR_LOCAL_STACK_STACK
                     EndIf
                  EndIf
               EndIf
         EndSelect
      Next

      ; Struct opcode specialization
      ForEach llObjects()
         Select llObjects()\code
            Case #ljPTRSTRUCTFETCH_INT
               If llObjects()\i < -1
                  llObjects()\i = -(llObjects()\i + 2)
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
            Case #ljPTRSTRUCTSTORE_INT
               If llObjects()\i < -1 And llObjects()\ndx < -1
                  llObjects()\i = -(llObjects()\i + 2)
                  llObjects()\ndx = -(llObjects()\ndx + 2)
                  llObjects()\code = #ljPTRSTRUCTSTORE_INT_LPTR_LOPT
               ElseIf llObjects()\i < -1
                  llObjects()\i = -(llObjects()\i + 2)
                  llObjects()\code = #ljPTRSTRUCTSTORE_INT_LPTR
               ElseIf llObjects()\ndx < -1
                  llObjects()\ndx = -(llObjects()\ndx + 2)
                  llObjects()\code = #ljPTRSTRUCTSTORE_INT_LOPT
               EndIf
            Case #ljPTRSTRUCTSTORE_FLOAT
               If llObjects()\i < -1 And llObjects()\ndx < -1
                  llObjects()\i = -(llObjects()\i + 2)
                  llObjects()\ndx = -(llObjects()\ndx + 2)
                  llObjects()\code = #ljPTRSTRUCTSTORE_FLOAT_LPTR_LOPT
               ElseIf llObjects()\i < -1
                  llObjects()\i = -(llObjects()\i + 2)
                  llObjects()\code = #ljPTRSTRUCTSTORE_FLOAT_LPTR
               ElseIf llObjects()\ndx < -1
                  llObjects()\ndx = -(llObjects()\ndx + 2)
                  llObjects()\code = #ljPTRSTRUCTSTORE_FLOAT_LOPT
               EndIf
            Case #ljPTRSTRUCTSTORE_STR
               If llObjects()\i < -1 And llObjects()\ndx < -1
                  llObjects()\i = -(llObjects()\i + 2)
                  llObjects()\ndx = -(llObjects()\ndx + 2)
                  llObjects()\code = #ljPTRSTRUCTSTORE_STR_LPTR_LOPT
               ElseIf llObjects()\i < -1
                  llObjects()\i = -(llObjects()\i + 2)
                  llObjects()\code = #ljPTRSTRUCTSTORE_STR_LPTR
               ElseIf llObjects()\ndx < -1
                  llObjects()\ndx = -(llObjects()\ndx + 2)
                  llObjects()\code = #ljPTRSTRUCTSTORE_STR_LOPT
               EndIf
            Case #ljARRAYOFSTRUCT_FETCH_INT
               If llObjects()\ndx < -1
                  llObjects()\ndx = -(llObjects()\ndx + 2)
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
         Debug "    Pass 6: Add implicit returns"
      CompilerEndIf

      ;- ========================================
      ;- PASS 6: ADD IMPLICIT RETURNS
      ;- ========================================
      ForEach llObjects()
         If llObjects()\code = #ljFunction
            needsReturn = #True
            savedPos = @llObjects()
            foundEnd = #False
            While NextElement(llObjects())
               If llObjects()\code = #ljFunction Or llObjects()\code = #ljHALT
                  If needsReturn
                     Protected prevIsNoopif.b = #False
                     Protected *prevElement = #Null
                     If PreviousElement(llObjects())
                        If llObjects()\code = #ljNOOPIF Or llObjects()\code = #ljNOOP
                           prevIsNoopif = #True
                           *prevElement = @llObjects()
                        EndIf
                        NextElement(llObjects())
                     EndIf
                     If prevIsNoopif And *prevElement
                        ChangeCurrentElement(llObjects(), *prevElement)
                        llObjects()\code = #ljreturn
                        llObjects()\i = 0
                        llObjects()\j = 0
                        llObjects()\n = 0
                        llObjects()\ndx = -1
                        NextElement(llObjects())
                     Else
                        InsertElement(llObjects())
                        llObjects()\code = #ljreturn
                        llObjects()\i = 0
                        llObjects()\j = 0
                        llObjects()\n = 0
                        llObjects()\ndx = -1
                        NextElement(llObjects())
                     EndIf
                  EndIf
                  foundEnd = #True
                  Break
               EndIf
               If llObjects()\code = #ljreturn Or llObjects()\code = #ljreturnF Or llObjects()\code = #ljreturnS
                  needsReturn = #False
               ElseIf llObjects()\code <> #ljNOOP
                  needsReturn = #True
               EndIf
            Wend
            If Not foundEnd And needsReturn
               LastElement(llObjects())
               If llObjects()\code = #ljNOOPIF Or llObjects()\code = #ljNOOP
                  llObjects()\code = #ljreturn
                  llObjects()\i = 0
                  llObjects()\j = 0
                  llObjects()\n = 0
                  llObjects()\ndx = -1
               Else
                  AddElement(llObjects())
                  llObjects()\code = #ljreturn
                  llObjects()\i = 0
                  llObjects()\j = 0
                  llObjects()\n = 0
                  llObjects()\ndx = -1
               EndIf
            EndIf
            ChangeCurrentElement(llObjects(), savedPos)
         EndIf
      Next

      CompilerIf #DEBUG
         Debug "    Pass 7: Return value type conversions"
      CompilerEndIf

      ;- ========================================
      ;- PASS 7: RETURN VALUE TYPE CONVERSIONS
      ;- ========================================
      ForEach llObjects()
         Select llObjects()\code
            Case #ljreturn
               If PreviousElement(llObjects())
                  Select llObjects()\code
                     Case #ljPUSHF, #ljFETCHF, #ljLFETCHF
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
               If PreviousElement(llObjects())
                  Select llObjects()\code
                     Case #ljPush, #ljFetch, #ljLFETCH
                        varIdx = llObjects()\i
                        If varIdx >= 0 And varIdx < gnLastVariable
                           If Not (gVarMeta(varIdx)\flags & #C2FLAG_FLOAT)
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
               If PreviousElement(llObjects())
                  Select llObjects()\code
                     Case #ljPush, #ljFetch, #ljLFETCH
                        varIdx = llObjects()\i
                        If varIdx >= 0 And varIdx < gnLastVariable
                           If Not (gVarMeta(varIdx)\flags & #C2FLAG_STR)
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

      CompilerIf #DEBUG
         Debug "    Pass 8: Collection opcode typing"
      CompilerEndIf

      ;- ========================================
      ;- PASS 8: COLLECTION OPCODE TYPING (from Pass 27)
      ;- ========================================
      ; Include collection typing here - it's essential for correctness
      ; (Full implementation from original Pass 27 - abbreviated for brevity)
      ; This pass converts LIST_ADD/GET/SET/INSERT and MAP_PUT/GET/VALUE to typed versions

      Protected collectionSlot.i, collectionType.w
      Protected stepsBack.i, collTypedCount.i = 0
      Protected *fetchInstr
      Protected searchLocalIdx.i
      Protected pass8FuncName.s = ""
      Protected pass8FuncId.i
      Protected pass8VarName.s
      Protected maxSearchDepth.i, foundCollectionFetch.i, searchDepth.i
      Protected checkSlot.i, checkParamOffset.i

      ForEach llObjects()
         If llObjects()\code = #ljFUNCTION
            pass8FuncId = llObjects()\i
            pass8FuncName = ""
            ForEach mapModules()
               If mapModules()\function = pass8FuncId
                  pass8FuncName = MapKey(mapModules())
                  Break
               EndIf
            Next
         EndIf

         Select llObjects()\code
            Case #ljLIST_ADD, #ljLIST_INSERT, #ljLIST_GET, #ljLIST_SET
               *fetchInstr = @llObjects()
               maxSearchDepth = 20
               foundCollectionFetch = #False
               searchDepth = 0

               While PreviousElement(llObjects()) And searchDepth < maxSearchDepth
                  searchDepth + 1
                  If llObjects()\code = #ljFetch Or llObjects()\code = #ljLFETCH Or llObjects()\code = #ljPFETCH Or llObjects()\code = #ljPLFETCH
                     checkSlot = -1
                     If llObjects()\code = #ljLFETCH Or llObjects()\code = #ljPLFETCH
                        checkParamOffset = llObjects()\i
                        For searchLocalIdx = 0 To gnLastVariable - 1
                           If gVarMeta(searchLocalIdx)\paramOffset = checkParamOffset
                              pass8VarName = gVarMeta(searchLocalIdx)\name
                              If pass8FuncName <> "" And Left(pass8VarName, 1) <> "$"
                                 If LCase(Left(pass8VarName, Len(pass8FuncName) + 1)) = LCase(pass8FuncName + "_")
                                    checkSlot = searchLocalIdx
                                    Break
                                 EndIf
                              ElseIf pass8FuncName = ""
                                 checkSlot = searchLocalIdx
                                 Break
                              EndIf
                           EndIf
                        Next
                     Else
                        checkSlot = llObjects()\i
                     EndIf
                     If checkSlot >= 0 And checkSlot < gnLastVariable
                        If gVarMeta(checkSlot)\flags & (#C2FLAG_LIST | #C2FLAG_MAP)
                           foundCollectionFetch = #True
                           Break
                        EndIf
                     EndIf
                  EndIf
               Wend

               If foundCollectionFetch
                  collectionSlot = checkSlot
                  collectionType = 0
                  Protected collStructType.s = ""
                  Protected collStructSize.i = 0
                  If collectionSlot >= 0 And collectionSlot < gnLastVariable
                     collectionType = gVarMeta(collectionSlot)\flags & (#C2FLAG_INT | #C2FLAG_FLOAT | #C2FLAG_STR)
                     collStructType = gVarMeta(collectionSlot)\structType
                     If collStructType <> "" And FindMapElement(mapStructDefs(), collStructType)
                        collStructSize = mapStructDefs()\totalSize
                     EndIf
                  EndIf
                  ChangeCurrentElement(llObjects(), *fetchInstr)
                  Select llObjects()\code
                     Case #ljLIST_ADD
                        If collStructType <> "" And collStructSize > 0
                           llObjects()\code = #ljLIST_ADD_STRUCT_PTR
                           llObjects()\i = collStructSize * 8
                           Protected listAddFieldIdx.i = 0
                           llObjects()\j = GenerateStructTypeBitmap(collStructType, @listAddFieldIdx)
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
                        If collStructType <> "" And collStructSize > 0
                           llObjects()\code = #ljLIST_GET_STRUCT_PTR
                           llObjects()\i = collStructSize * 8
                           ; V1.033.1: Find following STORE and set destination slot
                           Protected *listGetPos = @llObjects()
                           Protected listStoreFound.b = #False
                           Protected listLookAhead.i = 0
                           While NextElement(llObjects()) And listLookAhead < 3 And Not listStoreFound
                              ; Check for any STORE variant (regular, struct, or local)
                              If llObjects()\code = #ljStore Or llObjects()\code = #ljSTOREF Or llObjects()\code = #ljSTORES Or llObjects()\code = #ljSTRUCT_STORE_INT Or llObjects()\code = #ljSTRUCT_STORE_FLOAT Or llObjects()\code = #ljSTRUCT_STORE_STR Or llObjects()\code = #ljSTORE_STRUCT
                                 ; Found global STORE - capture destination slot
                                 Protected listDestSlot.i = llObjects()\i
                                 llObjects()\code = #ljNOOP  ; Remove STORE
                                 ; Go back to LIST_GET_STRUCT_PTR and set destination
                                 ChangeCurrentElement(llObjects(), *listGetPos)
                                 llObjects()\j = listDestSlot
                                 listStoreFound = #True
                              ElseIf llObjects()\code = #ljLSTORE_STRUCT Or llObjects()\code = #ljLSTORE Or llObjects()\code = #ljLSTOREF Or llObjects()\code = #ljLSTORES
                                 ; Found LOCAL STORE - capture offset with local flag
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
                        If collStructType <> "" And collStructSize > 0
                           llObjects()\code = #ljLIST_SET_STRUCT
                           llObjects()\i = collStructSize
                           Protected listSetFieldIdx.i = 0
                           llObjects()\n = GenerateStructTypeBitmap(collStructType, @listSetFieldIdx)
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
                  ChangeCurrentElement(llObjects(), *fetchInstr)
               EndIf

            Case #ljMAP_PUT, #ljMAP_GET, #ljMAP_VALUE
               *fetchInstr = @llObjects()
               maxSearchDepth = 20
               foundCollectionFetch = #False
               searchDepth = 0
               checkSlot = -1

               While PreviousElement(llObjects()) And searchDepth < maxSearchDepth
                  searchDepth + 1
                  If llObjects()\code = #ljFetch Or llObjects()\code = #ljLFETCH Or llObjects()\code = #ljPFETCH Or llObjects()\code = #ljPLFETCH
                     checkSlot = -1
                     If llObjects()\code = #ljLFETCH Or llObjects()\code = #ljPLFETCH
                        checkParamOffset = llObjects()\i
                        For searchLocalIdx = 0 To gnLastVariable - 1
                           If gVarMeta(searchLocalIdx)\paramOffset = checkParamOffset
                              pass8VarName = gVarMeta(searchLocalIdx)\name
                              If pass8FuncName <> "" And Left(pass8VarName, 1) <> "$"
                                 If LCase(Left(pass8VarName, Len(pass8FuncName) + 1)) = LCase(pass8FuncName + "_")
                                    checkSlot = searchLocalIdx
                                    Break
                                 EndIf
                              ElseIf pass8FuncName = ""
                                 checkSlot = searchLocalIdx
                                 Break
                              EndIf
                           EndIf
                        Next
                     Else
                        checkSlot = llObjects()\i
                     EndIf
                     If checkSlot >= 0 And checkSlot < gnLastVariable
                        If gVarMeta(checkSlot)\flags & (#C2FLAG_LIST | #C2FLAG_MAP)
                           foundCollectionFetch = #True
                           Break
                        EndIf
                     EndIf
                  EndIf
               Wend

               If foundCollectionFetch
                  collectionSlot = checkSlot
                  collectionType = 0
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
                        If mapStructType <> "" And mapStructSize > 0
                           llObjects()\code = #ljMAP_PUT_STRUCT_PTR
                           llObjects()\i = mapStructSize * 8
                        ElseIf collectionType & #C2FLAG_STR
                           llObjects()\code = #ljMAP_PUT_STR
                        ElseIf collectionType & #C2FLAG_FLOAT
                           llObjects()\code = #ljMAP_PUT_FLOAT
                        Else
                           llObjects()\code = #ljMAP_PUT_INT
                        EndIf
                        collTypedCount + 1
                     Case #ljMAP_GET
                        If mapStructType <> "" And mapStructSize > 0
                           llObjects()\code = #ljMAP_GET_STRUCT_PTR
                           llObjects()\i = mapStructSize * 8
                           ; V1.033.2: Find following STORE and set destination slot
                           Protected *mapGetPos = @llObjects()
                           Protected mapStoreFound.b = #False
                           Protected mapLookAhead.i = 0
                           While NextElement(llObjects()) And mapLookAhead < 3 And Not mapStoreFound
                              ; Check for any STORE variant (regular, struct, or local)
                              If llObjects()\code = #ljStore Or llObjects()\code = #ljSTOREF Or llObjects()\code = #ljSTORES Or llObjects()\code = #ljSTRUCT_STORE_INT Or llObjects()\code = #ljSTRUCT_STORE_FLOAT Or llObjects()\code = #ljSTRUCT_STORE_STR Or llObjects()\code = #ljSTORE_STRUCT
                                 ; Found global STORE - capture destination slot
                                 Protected mapDestSlot.i = llObjects()\i
                                 llObjects()\code = #ljNOOP  ; Remove STORE
                                 ; Go back to MAP_GET_STRUCT_PTR and set destination
                                 ChangeCurrentElement(llObjects(), *mapGetPos)
                                 llObjects()\j = mapDestSlot
                                 mapStoreFound = #True
                              ElseIf llObjects()\code = #ljLSTORE_STRUCT Or llObjects()\code = #ljLSTORE Or llObjects()\code = #ljLSTOREF Or llObjects()\code = #ljLSTORES
                                 ; Found LOCAL STORE - capture offset with local flag
                                 mapDestSlot = llObjects()\i | #C2_LOCAL_COLLECTION_FLAG
                                 llObjects()\code = #ljNOOP  ; Remove STORE
                                 ; Go back to MAP_GET_STRUCT_PTR and set destination with local flag
                                 ChangeCurrentElement(llObjects(), *mapGetPos)
                                 llObjects()\j = mapDestSlot
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
                              ; No STORE found - restore position
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
                        If mapStructType <> "" And mapStructSize > 0
                           llObjects()\code = #ljMAP_VALUE_STRUCT
                           llObjects()\i = mapStructSize
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

      ;- ========================================
      ;- BUILD VARIABLE PRELOADING TEMPLATES
      ;- ========================================
      CompilerIf #DEBUG
         Debug "    Building variable preloading templates..."
      CompilerEndIf

      If gnLastVariable > 0
         ReDim gGlobalTemplate.stVarTemplate(gnLastVariable - 1)
         Protected preloadCount.i = 0
         For i = 0 To gnLastVariable - 1
            If gVarMeta(i)\paramOffset = -1 And Not (gVarMeta(i)\flags & #C2FLAG_CONST)
               If gVarMeta(i)\flags & #C2FLAG_INT
                  gGlobalTemplate(i)\i = gVarMeta(i)\valueInt
               ElseIf gVarMeta(i)\flags & #C2FLAG_FLOAT
                  gGlobalTemplate(i)\f = gVarMeta(i)\valueFloat
               ElseIf gVarMeta(i)\flags & #C2FLAG_STR
                  gGlobalTemplate(i)\ss = gVarMeta(i)\valueString
               EndIf
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

      ; Build function templates
      maxFuncId = 0
      ForEach mapModules()
         If mapModules()\function >= #C2FUNCSTART
            If mapModules()\function > maxFuncId
               maxFuncId = mapModules()\function
            EndIf
         EndIf
      Next

      If maxFuncId >= #C2FUNCSTART
         gnFuncTemplateCount = maxFuncId + 1
         ReDim gFuncTemplates.stFuncTemplate(maxFuncId)

         ForEach mapModules()
            If mapModules()\function >= #C2FUNCSTART
               funcId = mapModules()\function
               funcName = MapKey(mapModules())
               funcPrefix = funcName + "_"
               nParams = mapModules()\nParams
               localCount = 0

               For i = 0 To gnLastVariable - 1
                  If gVarMeta(i)\paramOffset >= nParams
                     If Left(LCase(gVarMeta(i)\name), Len(funcPrefix)) = LCase(funcPrefix)
                        localCount + 1
                     EndIf
                  EndIf
               Next

               gFuncTemplates(funcId)\funcId = funcId
               gFuncTemplates(funcId)\localCount = localCount

               If localCount > 0
                  ReDim gFuncTemplates(funcId)\template.stVarTemplate(localCount - 1)

                  For i = 0 To gnLastVariable - 1
                     If gVarMeta(i)\paramOffset >= nParams
                        If Left(LCase(gVarMeta(i)\name), Len(funcPrefix)) = LCase(funcPrefix)
                           templateIdx = gVarMeta(i)\paramOffset - nParams
                           If templateIdx >= 0 And templateIdx < localCount
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
            EndIf
         Next
      EndIf

      CompilerIf #DEBUG
         Debug "=== PostProcessor V09 Complete ==="
      CompilerEndIf

   EndProcedure

   ; V1.033.8: Auto-calculate stack sizes based on compiled code
   ; This eliminates the need for manual #pragma GlobalStack, FunctionStack, EvalStack, LocalStack
   ; Called after compilation, sets pragmas in mapPragmas() if not already specified by user
   Procedure            CalculateStackSizes()
      Protected maxLocals.i = 0
      Protected maxParams.i = 0
      Protected totalFunctions.i = 0
      Protected calcGlobalStack.i
      Protected calcFunctionStack.i
      Protected calcEvalStack.i
      Protected calcLocalStack.i
      Protected maxTotalLocals.i = 0
      Protected funcLocals.i
      Protected needMargin.i = 64  ; Safety margin
      Protected fnParams.i
      Protected fnLocals.i

      ; Calculate function-related sizes from mapModules
      ForEach mapModules()
         totalFunctions + 1
         ; V1.033.8: Handle uninitialized nParams (-1)
         ; nParams is set to -1 during pre-parsing and updated later during AST processing
         fnParams = mapModules()\nParams
         fnLocals = mapModules()\nLocals
         If fnParams < 0 : fnParams = 0 : EndIf
         If fnLocals < 0 : fnLocals = 0 : EndIf

         ; nLocals includes both parameters and local variables for stack allocation
         funcLocals = fnParams + fnLocals
         If funcLocals > maxTotalLocals
            maxTotalLocals = funcLocals
         EndIf
         If fnParams > maxParams
            maxParams = fnParams
         EndIf
         If fnLocals > maxLocals
            maxLocals = fnLocals
         EndIf
      Next

      ; GlobalStack: gnGlobalVariables + margin (for arrays/strings/runtime allocations)
      ; Must accommodate all global variable slots
      calcGlobalStack = gnGlobalVariables + needMargin
      If calcGlobalStack < 256
         calcGlobalStack = 256  ; Minimum size
      EndIf

      ; FunctionStack: totalFunctions + recursion margin
      ; This is the call stack depth - needs margin for recursion
      calcFunctionStack = totalFunctions + needMargin
      If calcFunctionStack < 64
         calcFunctionStack = 64  ; Minimum size
      EndIf

      ; EvalStack: Estimate based on max expression depth
      ; Complex expressions with nested function calls need more stack
      ; Use: max(maxParams * 2, maxLocals) + margin for expression evaluation
      calcEvalStack = maxParams * 4 + maxLocals * 2 + needMargin
      If calcEvalStack < 256
         calcEvalStack = 256  ; Minimum size
      EndIf

      ; LocalStack: Total local variables across nested calls
      ; Need to accommodate deepest call chain * max locals per function
      ; Conservative estimate: maxTotalLocals * (recursion depth estimate)
      calcLocalStack = maxTotalLocals * 16 + needMargin
      If calcLocalStack < 128
         calcLocalStack = 128  ; Minimum size
      EndIf

      ; Only set pragmas if not already specified by user
      ; This allows user overrides via #pragma directives
      If mapPragmas("globalstack") = ""
         mapPragmas("globalstack") = Str(calcGlobalStack)
         CompilerIf #DEBUG
            Debug "V1.033.8: Auto-calculated GlobalStack = " + Str(calcGlobalStack) + " (gnGlobalVariables=" + Str(gnGlobalVariables) + ")"
         CompilerEndIf
      Else
         CompilerIf #DEBUG
            Debug "V1.033.8: Using user-specified GlobalStack = " + mapPragmas("globalstack")
         CompilerEndIf
      EndIf

      If mapPragmas("functionstack") = ""
         mapPragmas("functionstack") = Str(calcFunctionStack)
         CompilerIf #DEBUG
            Debug "V1.033.8: Auto-calculated FunctionStack = " + Str(calcFunctionStack) + " (totalFunctions=" + Str(totalFunctions) + ")"
         CompilerEndIf
      Else
         CompilerIf #DEBUG
            Debug "V1.033.8: Using user-specified FunctionStack = " + mapPragmas("functionstack")
         CompilerEndIf
      EndIf

      If mapPragmas("evalstack") = ""
         mapPragmas("evalstack") = Str(calcEvalStack)
         CompilerIf #DEBUG
            Debug "V1.033.8: Auto-calculated EvalStack = " + Str(calcEvalStack) + " (maxParams=" + Str(maxParams) + ", maxLocals=" + Str(maxLocals) + ")"
         CompilerEndIf
      Else
         CompilerIf #DEBUG
            Debug "V1.033.8: Using user-specified EvalStack = " + mapPragmas("evalstack")
         CompilerEndIf
      EndIf

      If mapPragmas("localstack") = ""
         mapPragmas("localstack") = Str(calcLocalStack)
         CompilerIf #DEBUG
            Debug "V1.033.8: Auto-calculated LocalStack = " + Str(calcLocalStack) + " (maxTotalLocals=" + Str(maxTotalLocals) + ")"
         CompilerEndIf
      Else
         CompilerIf #DEBUG
            Debug "V1.033.8: Using user-specified LocalStack = " + mapPragmas("localstack")
         CompilerEndIf
      EndIf

   EndProcedure

; IDE Options = PureBasic 6.21 (Windows - x64)
; EnableThread
; EnableXP
; CPU = 1
