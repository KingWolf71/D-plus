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
;  Compiler - PostProcessor V10
;- Type inference moved to c2-typeinfer-V01.pbi
;- This file contains only correctness passes (6-8) and supporting functions
;- Optimizations in c2-optimizer-V01.pbi
;
; V1.033.21: Split from c2-postprocessor-V09.pbi
;            - Passes 1-5 (type inference) moved to c2-typeinfer-V01.pbi
;            - Only correctness passes remain: 6 (implicit returns), 7 (return conversions), 8 (collections)

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

; V1.034.0: Mark function-end NOOPIFs BEFORE InitJumpTracker runs
; This ensures backward jumps correctly target implicit returns
; NOOPIFs marked with #INST_FLAG_IMPLICIT_RETURN will NOT be skipped in jump tracking
Procedure            MarkImplicitReturns()
   Protected inFunction.b = #False
   Protected *savedNoop
   Protected nextIsEnd.b

   ForEach llObjects()
      ; Track function boundaries
      If llObjects()\code = #ljFunction
         inFunction = #True
      EndIf

      ; Check if this NOOPIF will become RETURN at function end
      If (llObjects()\code = #ljNOOPIF Or llObjects()\code = #ljNOOP) And inFunction
         *savedNoop = @llObjects()
         nextIsEnd = #False

         If NextElement(llObjects())
            ; Check if next instruction is function boundary or HALT
            If llObjects()\code = #ljFunction Or llObjects()\code = #ljHALT
               nextIsEnd = #True
            EndIf
            ChangeCurrentElement(llObjects(), *savedNoop)
         Else
            ; End of code while in function - will become RETURN
            nextIsEnd = #True
            ChangeCurrentElement(llObjects(), *savedNoop)
         EndIf

         ; Mark this NOOPIF so InitJumpTracker won't skip it
         If nextIsEnd
            llObjects()\flags = llObjects()\flags | #INST_FLAG_IMPLICIT_RETURN
         EndIf
      EndIf
   Next
EndProcedure

Procedure            InitJumpTracker()
      ; V1.020.077: Initialize jump tracker BEFORE PostProcessor runs
      ; This allows optimization passes to call AdjustJumpsForNOOP() with populated tracker

      Protected         i, pos, pair
      Protected         srcPos.i
      Protected         offset.i
      Protected         *targetInstr.stType  ; V1.020.085: Store target instruction pointer
      Protected         *currentNoop         ; V1.022.98: For function-end NOOPIF check

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
            ; V1.034.0: Don't skip NOOPIFs marked as implicit returns
            While (llObjects()\code = #ljNOOPIF Or llObjects()\code = #ljNOOP) And Not (llObjects()\flags & #INST_FLAG_IMPLICIT_RETURN)
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
            ; V1.034.0: Don't skip NOOPIFs marked as implicit returns
            While (llObjects()\code = #ljNOOPIF Or llObjects()\code = #ljNOOP) And Not (llObjects()\flags & #INST_FLAG_IMPLICIT_RETURN)
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
            ; V1.034.0: Don't skip NOOPIFs marked as implicit returns
            While (llObjects()\code = #ljNOOPIF Or llObjects()\code = #ljNOOP) And Not (llObjects()\flags & #INST_FLAG_IMPLICIT_RETURN)
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
   EndProcedure

Procedure            FixJMP()
      ; V1.020.077: FixJMP now runs AFTER PostProcessor and uses pre-populated tracker

      Protected         i, pos, pair
      Protected         srcPos.i
      Protected         offset.i
      Protected         targetPos
      Protected         noopCount.i

      ; Convert all NOOPIF markers to NOOP
      ForEach llObjects()
         If llObjects()\code = #ljNOOPIF
            llObjects()\code = #ljNOOP
         EndIf
      Next

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
      ; V1.034.65: Also handle CALL_REC for recursive calls
      ForEach llObjects()
         If llObjects()\code = #ljCall Or llObjects()\code = #ljCALL0 Or llObjects()\code = #ljCALL1 Or llObjects()\code = #ljCALL2 Or llObjects()\code = #ljCALL_REC
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
      ; V1.033.21: PostProcessor now only handles correctness passes
      ; Type inference (passes 1-5) moved to c2-typeinfer-V01.pbi

      Protected n.i, i.i
      Protected opCode.i
      Protected varIdx.i
      Protected funcId.i
      Protected varName.s
      Protected flags.s
      Protected savedPos
      Protected funcName.s
      Protected funcPrefix.s
      Protected nParams.i
      Protected localCount.i
      Protected templateIdx.i
      Protected maxFuncId.i
      Protected needsReturn.i
      Protected foundEnd.i


      ;- ========================================
      ;- PASS 1: ADD IMPLICIT RETURNS (was Pass 6)
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

      ;- ========================================
      ;- PASS 2: RETURN VALUE TYPE CONVERSIONS (was Pass 7)
      ;- ========================================
      ForEach llObjects()
         Select llObjects()\code
            Case #ljreturn
               If PreviousElement(llObjects())
                  Select llObjects()\code
                     ; V1.034.24: LFETCHF eliminated - unified FETCHF uses j=1 for local
                     Case #ljPUSHF, #ljFETCHF
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
                     ; V1.034.24: LFETCH eliminated - unified FETCH uses j=1 for local
                     Case #ljPush, #ljFetch
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
                     ; V1.034.24: LFETCH eliminated - unified FETCH uses j=1 for local
                     Case #ljPush, #ljFetch
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
                     ; V1.034.24: LFETCHF eliminated - unified FETCHF uses j=1 for local
                     Case #ljPUSHF, #ljFETCHF
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

      ;- ========================================
      ;- PASS 3: COLLECTION OPCODE TYPING (was Pass 8)
      ;- ========================================
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
                  ; V1.034.24: LFETCH eliminated - unified FETCH uses j=1 for local
                  If llObjects()\code = #ljFetch Or llObjects()\code = #ljPFETCH
                     checkSlot = -1
                     ; Check j=1 for local (works for both FETCH and PFETCH)
                     If llObjects()\j = 1
                        checkParamOffset = llObjects()\i
                        ; V1.034.2: Use O(1) offset-based lookup
                        checkSlot = FindVariableSlotByOffset(checkParamOffset, pass8FuncName)
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
                              ; V1.034.24: Check for unified STORE variants (j=1 for local, j=0 for global)
                              If llObjects()\code = #ljStore Or llObjects()\code = #ljSTOREF Or llObjects()\code = #ljSTORES Or llObjects()\code = #ljSTORE_STRUCT Or llObjects()\code = #ljSTRUCT_STORE_INT Or llObjects()\code = #ljSTRUCT_STORE_FLOAT Or llObjects()\code = #ljSTRUCT_STORE_STR
                                 Protected listDestSlot.i = llObjects()\i
                                 If llObjects()\j = 1
                                    ; Found LOCAL STORE (j=1) - capture offset with local flag
                                    listDestSlot = listDestSlot | #C2_LOCAL_COLLECTION_FLAG
                                 EndIf
                                 llObjects()\code = #ljNOOP  ; Remove STORE
                                 ; Go back to LIST_GET_STRUCT_PTR and set destination
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
                  ; V1.034.24: LFETCH eliminated - unified FETCH uses j=1 for local
                  If llObjects()\code = #ljFetch Or llObjects()\code = #ljPFETCH
                     checkSlot = -1
                     ; Check j=1 for local (works for both FETCH and PFETCH)
                     If llObjects()\j = 1
                        checkParamOffset = llObjects()\i
                        ; V1.034.2: Use O(1) offset-based lookup
                        checkSlot = FindVariableSlotByOffset(checkParamOffset, pass8FuncName)
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
                              ; V1.034.24: Check for unified STORE variants (j=1 for local, j=0 for global)
                              If llObjects()\code = #ljStore Or llObjects()\code = #ljSTOREF Or llObjects()\code = #ljSTORES Or llObjects()\code = #ljSTORE_STRUCT Or llObjects()\code = #ljSTRUCT_STORE_INT Or llObjects()\code = #ljSTRUCT_STORE_FLOAT Or llObjects()\code = #ljSTRUCT_STORE_STR
                                 Protected mapDestSlot.i = llObjects()\i
                                 If llObjects()\j = 1
                                    ; Found LOCAL STORE (j=1) - capture offset with local flag
                                    mapDestSlot = mapDestSlot | #C2_LOCAL_COLLECTION_FLAG
                                 EndIf
                                 llObjects()\code = #ljNOOP  ; Remove STORE
                                 ; Go back to MAP_GET_STRUCT_PTR and set destination
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

      ; V1.033.49: Template building moved to BuildVariableTemplates()
      ; Called AFTER Optimizer() to ensure all constants from constant folding are included
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
      EndIf

      If mapPragmas("functionstack") = ""
         mapPragmas("functionstack") = Str(calcFunctionStack)
      EndIf

      If mapPragmas("evalstack") = ""
         mapPragmas("evalstack") = Str(calcEvalStack)
      EndIf

      If mapPragmas("localstack") = ""
         mapPragmas("localstack") = Str(calcLocalStack)
      EndIf

   EndProcedure

   ; V1.033.49: Build variable templates AFTER optimizer runs
   ; Previously this was in PostProcessor(), but the optimizer can add new constants
   ; for constant folding, causing gnLastVariable to grow after template was built.
   ; Now called after Optimizer() in c2-modules-V21.pb
   Procedure            BuildVariableTemplates()
      Protected i.i, maxFuncId.i, funcId.i, funcName.s, funcPrefix.s, nParams.i
      Protected localCount.i, templateIdx.i, preloadCount.i

      ;- ========================================
      ;- BUILD VARIABLE PRELOADING TEMPLATES
      ;- ========================================
      ; V1.033.46: Populate ALL variables so VM doesn't need gVarMeta
      If gnLastVariable > 0
         ReDim gGlobalTemplate.stVarTemplate(gnLastVariable - 1)
         preloadCount = 0
         For i = 0 To gnLastVariable - 1
            ; V1.033.46: Copy metadata for ALL variables (VM needs this)
            gGlobalTemplate(i)\flags = gVarMeta(i)\flags
            gGlobalTemplate(i)\elementSize = gVarMeta(i)\elementSize
            gGlobalTemplate(i)\paramOffset = gVarMeta(i)\paramOffset
            gGlobalTemplate(i)\arraySize = gVarMeta(i)\arraySize

            ; Copy initial values for global non-constant variables
            If gVarMeta(i)\paramOffset = -1 And Not (gVarMeta(i)\flags & #C2FLAG_CONST)
               If gVarMeta(i)\flags & #C2FLAG_INT
                  gGlobalTemplate(i)\i = gVarMeta(i)\valueInt
               ElseIf gVarMeta(i)\flags & #C2FLAG_FLOAT
                  gGlobalTemplate(i)\f = gVarMeta(i)\valueFloat
               ElseIf gVarMeta(i)\flags & #C2FLAG_STR
                  gGlobalTemplate(i)\ss = gVarMeta(i)\valueString
               EndIf
               If gVarMeta(i)\flags & #C2FLAG_PRELOAD
                  preloadCount + 1
               EndIf
            ; V1.033.46: Also copy constant values to template
            ElseIf gVarMeta(i)\flags & #C2FLAG_CONST
               gGlobalTemplate(i)\i = gVarMeta(i)\valueInt
               gGlobalTemplate(i)\f = gVarMeta(i)\valueFloat
               gGlobalTemplate(i)\ss = gVarMeta(i)\valueString
            EndIf
         Next
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
         ; V1.033.55: Don't ReDim gFuncNames - keep #C2MAXFUNCTIONS capacity for multi-run sessions

         ; V1.035.0: Track function index for slot assignment
         Protected funcIdx.i = 0

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
               ; V1.035.0: Pointer Array Architecture - assign slot and params
               ; V1.035.1: Use gnLastVariable (includes constants/literals) to avoid slot collision
               gFuncTemplates(funcId)\funcSlot = gnLastVariable + funcIdx
               gFuncTemplates(funcId)\nParams = nParams
               funcIdx + 1

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
   EndProcedure

; IDE Options = PureBasic 6.21 (Windows - x64)
; EnableThread
; EnableXP
; CPU = 1
