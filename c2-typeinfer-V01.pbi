; -- LJ2 Compiler - Type Inference Module
; PBx64 v6.20+
;
; Based on c2-postprocessor-V09.pbi type passes
; Distribute and use freely
;
; Kingwolf71 December/2025
;
; V1.033.20: New unified type inference module
;            - Consolidates 8 type passes into 2-phase single-pass
;            - Phase A: Quick pointer type discovery
;            - Phase B: All type transformations in one iteration
;            - Separates type inference from postprocessor correctness passes

;- ========================================
;- TYPE INFERENCE MODULE
;- ========================================
; This module handles ALL type-related opcode specialization:
; - Pointer type tracking and opcode conversion
; - Variable type specialization (INT/FLOAT/STR)
; - Array type specialization (36 variants)
; - Print opcode type matching
; - Return value type conversions
;
; Called AFTER code generation, BEFORE postprocessor FixJMP

Procedure TypeInference()
   ; All definitions at procedure start (per rule #3)
   Protected n.i, varSlot.i, srcVar.i, dstVar.i, varIdx.i
   Protected ptrVarSlot.i, ptrVarKey.s, searchKey.s, varName.s
   Protected pointerBaseType.w, getAddrType.i, ptrOpcode.i
   Protected isArrayElementPointer.b, isPointer.b, sourceIsPointer.b, sourceIsArrayPointer.b
   Protected currentFunctionName.s, funcId.i, srcSlot.i, srcVarKey.s
   Protected isFetch.i, isLocalPointer.b, isArrayPointer.b
   Protected *savedPos, foundGetAddr.b
   Protected funcReturnType.i, currentFuncId.i
   Protected prevArraySlot.i       ; V1.033.44: For pointer array detection
   Protected localPtrSlot.i        ; V1.033.45: For PPOP pointer detection
   Protected dstSlot.i, dstVarKey.s, srcPtrType.w  ; V1.033.45: For A8/A9 phases


   ;- ========================================
   ;- PHASE A: POINTER TYPE DISCOVERY
   ;- ========================================
   ; Quick scan to identify all pointer variables and populate mapVariableTypes
   ; This MUST run first so Phase B can make type decisions

   ClearMap(mapVariableTypes())
   currentFunctionName = ""   ; V1.033.24: Track function context for local variable lookup

   ForEach llObjects()
      ; V1.033.24: Track current function for local variable matching
      If llObjects()\code = #ljfunction
         funcId = llObjects()\i
         If funcId >= 0 And funcId < 512
            currentFunctionName = gFuncNames(funcId)
         Else
            currentFunctionName = ""
         EndIf
      ElseIf llObjects()\code = #ljreturn Or llObjects()\code = #ljreturnF Or llObjects()\code = #ljreturnS
         currentFunctionName = ""
      EndIf

      Select llObjects()\code
         ;- A1: Variables assigned from address operations are pointers
         Case #ljGETADDR, #ljGETADDRF, #ljGETADDRS, #ljGETARRAYADDR, #ljGETARRAYADDRF, #ljGETARRAYADDRS, #ljGETSTRUCTADDR,
              #ljGETLOCALADDR, #ljGETLOCALADDRF, #ljGETLOCALADDRS, #ljGETLOCALARRAYADDR, #ljGETLOCALARRAYADDRF, #ljGETLOCALARRAYADDRS
            getAddrType = llObjects()\code
            If NextElement(llObjects())
               ; Global store opcodes use variable slot directly
               If llObjects()\code = #ljStore Or llObjects()\code = #ljSTORES Or llObjects()\code = #ljSTOREF Or llObjects()\code = #ljSTORE_STRUCT Or
                  llObjects()\code = #ljPOP Or llObjects()\code = #ljPOPS Or llObjects()\code = #ljPOPF
                  ptrVarSlot = llObjects()\i
                  If ptrVarSlot >= 0 And ptrVarSlot < gnLastVariable
                     ptrVarKey = gVarMeta(ptrVarSlot)\name
                     isArrayElementPointer = #False
                     Select getAddrType
                        Case #ljGETADDRF, #ljGETLOCALADDRF
                           pointerBaseType = #C2FLAG_FLOAT
                        Case #ljGETARRAYADDRF, #ljGETLOCALARRAYADDRF
                           pointerBaseType = #C2FLAG_FLOAT
                           isArrayElementPointer = #True
                        Case #ljGETADDRS, #ljGETLOCALADDRS
                           pointerBaseType = #C2FLAG_STR
                        Case #ljGETARRAYADDRS, #ljGETLOCALARRAYADDRS
                           pointerBaseType = #C2FLAG_STR
                           isArrayElementPointer = #True
                        Case #ljGETARRAYADDR, #ljGETLOCALARRAYADDR
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
               ; Local store opcodes use paramOffset - need to find variable by offset AND function context
               ElseIf llObjects()\code = #ljLSTORE Or llObjects()\code = #ljLSTORES Or llObjects()\code = #ljLSTOREF
                  ptrVarSlot = llObjects()\i  ; This is the local stack offset
                  ptrVarKey = ""
                  ; V1.033.24: Find variable by paramOffset AND function prefix match
                  For varIdx = 0 To gnLastVariable - 1
                     If gVarMeta(varIdx)\paramOffset = ptrVarSlot
                        ; Verify this variable belongs to current function
                        ; V1.033.42: Handle leading underscore in variable names
                        If currentFunctionName <> "" And (LCase(Left(gVarMeta(varIdx)\name, Len(currentFunctionName) + 1)) = LCase(currentFunctionName + "_") Or LCase(Left(gVarMeta(varIdx)\name, Len(currentFunctionName) + 2)) = LCase("_" + currentFunctionName + "_"))
                           ptrVarKey = gVarMeta(varIdx)\name
                           Break
                        ; Synthetic temps ($) also match
                        ElseIf Left(gVarMeta(varIdx)\name, 1) = "$"
                           ptrVarKey = gVarMeta(varIdx)\name
                           Break
                        EndIf
                     EndIf
                  Next
                  If ptrVarKey <> ""
                     isArrayElementPointer = #False
                     Select getAddrType
                        Case #ljGETADDRF, #ljGETLOCALADDRF
                           pointerBaseType = #C2FLAG_FLOAT
                        Case #ljGETARRAYADDRF, #ljGETLOCALARRAYADDRF
                           pointerBaseType = #C2FLAG_FLOAT
                           isArrayElementPointer = #True
                        Case #ljGETADDRS, #ljGETLOCALADDRS
                           pointerBaseType = #C2FLAG_STR
                        Case #ljGETARRAYADDRS, #ljGETLOCALARRAYADDRS
                           pointerBaseType = #C2FLAG_STR
                           isArrayElementPointer = #True
                        Case #ljGETARRAYADDR, #ljGETLOCALARRAYADDR
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

         ;- A2: Variables assigned from pointer arithmetic
         Case #ljPTRADD, #ljPTRSUB
            If NextElement(llObjects())
               ; Global store opcodes
               If llObjects()\code = #ljStore Or llObjects()\code = #ljSTORES Or llObjects()\code = #ljSTOREF Or llObjects()\code = #ljSTORE_STRUCT Or
                  llObjects()\code = #ljPOP Or llObjects()\code = #ljPOPS Or llObjects()\code = #ljPOPF
                  ptrVarSlot = llObjects()\i
                  If ptrVarSlot >= 0 And ptrVarSlot < gnLastVariable
                     ptrVarKey = gVarMeta(ptrVarSlot)\name
                     mapVariableTypes(ptrVarKey) = #C2FLAG_POINTER | #C2FLAG_INT | #C2FLAG_ARRAYPTR
                  EndIf
               ; Local store opcodes - find by paramOffset AND function context
               ElseIf llObjects()\code = #ljLSTORE Or llObjects()\code = #ljLSTORES Or llObjects()\code = #ljLSTOREF
                  ptrVarSlot = llObjects()\i
                  ptrVarKey = ""
                  ; V1.033.24: Match function prefix for local variables
                  For varIdx = 0 To gnLastVariable - 1
                     If gVarMeta(varIdx)\paramOffset = ptrVarSlot
                        ; V1.033.42: Handle leading underscore in variable names
                        If currentFunctionName <> "" And (LCase(Left(gVarMeta(varIdx)\name, Len(currentFunctionName) + 1)) = LCase(currentFunctionName + "_") Or LCase(Left(gVarMeta(varIdx)\name, Len(currentFunctionName) + 2)) = LCase("_" + currentFunctionName + "_"))
                           ptrVarKey = gVarMeta(varIdx)\name
                           Break
                        ElseIf Left(gVarMeta(varIdx)\name, 1) = "$"
                           ptrVarKey = gVarMeta(varIdx)\name
                           Break
                        EndIf
                     EndIf
                  Next
                  If ptrVarKey <> ""
                     mapVariableTypes(ptrVarKey) = #C2FLAG_POINTER | #C2FLAG_INT | #C2FLAG_ARRAYPTR
                  EndIf
               EndIf
               PreviousElement(llObjects())
            EndIf

         ;- A3: Variables assigned from other pointers via MOV
         Case #ljMOV, #ljPMOV, #ljLMOV, #ljLLMOV
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

         ;- A4: Variables used with PTRFETCH/PTRSTORE operations
         Case #ljPTRFETCH_INT, #ljPTRFETCH_FLOAT, #ljPTRFETCH_STR, #ljPTRSTORE_INT, #ljPTRSTORE_FLOAT, #ljPTRSTORE_STR
            ptrOpcode = llObjects()\code
            If PreviousElement(llObjects())
               If llObjects()\code = #ljFetch Or llObjects()\code = #ljPFETCH Or llObjects()\code = #ljLFETCH Or llObjects()\code = #ljPLFETCH
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

   ;- A5: Track pointer parameters via PTRFETCH usage (second scan for function context)
   ; V1.033.35: Use gFuncNames() like Phase A and B for consistent naming (without leading underscore)
   currentFunctionName = ""
   ForEach llObjects()
      If llObjects()\code = #ljFUNCTION
         funcId = llObjects()\i
         ; V1.033.35: Use gFuncNames for consistent naming with Phase A and B
         If funcId >= 0 And funcId < #C2MAXFUNCTIONS And gFuncNames(funcId) <> ""
            currentFunctionName = gFuncNames(funcId)
         Else
            currentFunctionName = ""
         EndIf
      EndIf
      If llObjects()\code = #ljPLFETCH Or llObjects()\code = #ljLFETCH
         srcSlot = llObjects()\i
         srcVarKey = ""
         For varIdx = 0 To gnLastVariable - 1
            If gVarMeta(varIdx)\paramOffset = srcSlot
               varName = gVarMeta(varIdx)\name
               If currentFunctionName <> "" And Left(varName, 1) <> "$"
                  ; V1.033.42: Handle leading underscore in variable names
                  ; Variables can be named "funcname_varname" or "_funcname_varname"
                  If LCase(Left(varName, Len(currentFunctionName) + 1)) = LCase(currentFunctionName + "_") Or LCase(Left(varName, Len(currentFunctionName) + 2)) = LCase("_" + currentFunctionName + "_")
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


   ;- A6: Propagate pointer types through local-to-local copies (LFETCH+LSTORE)
   ; V1.033.42: When a known pointer is copied to another local, mark destination as pointer too
   ; This handles cases like: p = ptr (where ptr is already marked as pointer)
   ; V1.033.45: Variables declared at top (dstSlot, dstVarKey, srcPtrType)
   currentFunctionName = ""
   ForEach llObjects()
      If llObjects()\code = #ljFUNCTION
         funcId = llObjects()\i
         If funcId >= 0 And funcId < #C2MAXFUNCTIONS And gFuncNames(funcId) <> ""
            currentFunctionName = gFuncNames(funcId)
         Else
            currentFunctionName = ""
         EndIf
      EndIf
      If llObjects()\code = #ljLFETCH
         srcSlot = llObjects()\i
         srcVarKey = ""
         ; Find source variable by paramOffset AND function context
         For varIdx = 0 To gnLastVariable - 1
            If gVarMeta(varIdx)\paramOffset = srcSlot
               varName = gVarMeta(varIdx)\name
               If currentFunctionName <> "" And Left(varName, 1) <> "$"
                  ; V1.033.42: Handle leading underscore in variable names
                  If LCase(Left(varName, Len(currentFunctionName) + 1)) = LCase(currentFunctionName + "_") Or LCase(Left(varName, Len(currentFunctionName) + 2)) = LCase("_" + currentFunctionName + "_")
                     srcVarKey = varName
                     Break
                  EndIf
               ElseIf currentFunctionName = ""
                  srcVarKey = varName
                  Break
               EndIf
            EndIf
         Next
         ; Check if source is a known pointer
         If srcVarKey <> "" And FindMapElement(mapVariableTypes(), srcVarKey)
            If mapVariableTypes() & #C2FLAG_POINTER
               srcPtrType = mapVariableTypes()
               ; Check if next instruction is LSTORE (local-to-local copy)
               If NextElement(llObjects())
                  If llObjects()\code = #ljLSTORE
                     dstSlot = llObjects()\i
                     dstVarKey = ""
                     ; Find destination variable
                     For varIdx = 0 To gnLastVariable - 1
                        If gVarMeta(varIdx)\paramOffset = dstSlot
                           varName = gVarMeta(varIdx)\name
                           If currentFunctionName <> "" And Left(varName, 1) <> "$"
                              ; V1.033.42: Handle leading underscore in variable names
                              If LCase(Left(varName, Len(currentFunctionName) + 1)) = LCase(currentFunctionName + "_") Or LCase(Left(varName, Len(currentFunctionName) + 2)) = LCase("_" + currentFunctionName + "_")
                                 dstVarKey = varName
                                 Break
                              EndIf
                           ElseIf Left(varName, 1) = "$"
                              dstVarKey = varName
                              Break
                           ElseIf currentFunctionName = ""
                              dstVarKey = varName
                              Break
                           EndIf
                        EndIf
                     Next
                     ; Mark destination as pointer with same type as source
                     If dstVarKey <> ""
                        mapVariableTypes(dstVarKey) = srcPtrType
                     EndIf
                  EndIf
                  PreviousElement(llObjects())
               EndIf
            EndIf
         EndIf
      EndIf
   Next

   ;- A7: Detect pointer locals via LINCV/LDECV + POP pattern
   ; V1.033.45: When a local increment/decrement is followed by POP (stack cleanup),
   ; the local is being used as a pointer (e.g., left++ in pointer traversal)
   ; Pattern: LINCV_POST/LDECV_POST + POP indicates pointer type
   currentFunctionName = ""
   ForEach llObjects()
      If llObjects()\code = #ljFUNCTION
         funcId = llObjects()\i
         If funcId >= 0 And funcId < #C2MAXFUNCTIONS And gFuncNames(funcId) <> ""
            currentFunctionName = gFuncNames(funcId)
         Else
            currentFunctionName = ""
         EndIf
      EndIf
      If llObjects()\code = #ljLINC_VAR_POST Or llObjects()\code = #ljLDEC_VAR_POST
         localPtrSlot = llObjects()\i
         If NextElement(llObjects())
            ; V1.033.45: At this point, POP hasn't been converted to PPOP yet
            ; Look for POP following LINCV/LDECV as evidence of pointer operation
            If llObjects()\code = #ljPOP
               ; This local is used as a pointer - find and mark it
               For varIdx = 0 To gnLastVariable - 1
                  If gVarMeta(varIdx)\paramOffset = localPtrSlot
                     varName = gVarMeta(varIdx)\name
                     If currentFunctionName <> "" And Left(varName, 1) <> "$"
                        If LCase(Left(varName, Len(currentFunctionName) + 1)) = LCase(currentFunctionName + "_") Or LCase(Left(varName, Len(currentFunctionName) + 2)) = LCase("_" + currentFunctionName + "_")
                           mapVariableTypes(varName) = #C2FLAG_POINTER | #C2FLAG_INT | #C2FLAG_ARRAYPTR
                           Break
                        EndIf
                     EndIf
                  EndIf
               Next
            EndIf
            PreviousElement(llObjects())
         EndIf
      EndIf
   Next

   ;- A8: Backward propagation - mark source params/locals as pointers
   ; V1.033.45: If a local is a pointer (from A7), trace LFETCH+LSTORE to find source
   ; This marks function parameters as pointers when they're assigned to pointer locals
   currentFunctionName = ""
   ForEach llObjects()
      If llObjects()\code = #ljFUNCTION
         funcId = llObjects()\i
         If funcId >= 0 And funcId < #C2MAXFUNCTIONS And gFuncNames(funcId) <> ""
            currentFunctionName = gFuncNames(funcId)
         Else
            currentFunctionName = ""
         EndIf
      EndIf
      If llObjects()\code = #ljLFETCH
         srcSlot = llObjects()\i
         If NextElement(llObjects())
            If llObjects()\code = #ljLSTORE
               dstSlot = llObjects()\i
               dstVarKey = ""
               ; Find destination variable
               For varIdx = 0 To gnLastVariable - 1
                  If gVarMeta(varIdx)\paramOffset = dstSlot
                     varName = gVarMeta(varIdx)\name
                     If currentFunctionName <> "" And Left(varName, 1) <> "$"
                        If LCase(Left(varName, Len(currentFunctionName) + 1)) = LCase(currentFunctionName + "_") Or LCase(Left(varName, Len(currentFunctionName) + 2)) = LCase("_" + currentFunctionName + "_")
                           dstVarKey = varName
                           Break
                        EndIf
                     EndIf
                  EndIf
               Next
               ; If destination is a known pointer, mark source as pointer too
               If dstVarKey <> "" And FindMapElement(mapVariableTypes(), dstVarKey)
                  If mapVariableTypes() & #C2FLAG_POINTER
                     srcVarKey = ""
                     ; Find source variable
                     For varIdx = 0 To gnLastVariable - 1
                        If gVarMeta(varIdx)\paramOffset = srcSlot
                           varName = gVarMeta(varIdx)\name
                           If currentFunctionName <> "" And Left(varName, 1) <> "$"
                              If LCase(Left(varName, Len(currentFunctionName) + 1)) = LCase(currentFunctionName + "_") Or LCase(Left(varName, Len(currentFunctionName) + 2)) = LCase("_" + currentFunctionName + "_")
                                 srcVarKey = varName
                                 Break
                              EndIf
                           EndIf
                        EndIf
                     Next
                     If srcVarKey <> ""
                        mapVariableTypes(srcVarKey) = mapVariableTypes(dstVarKey)
                     EndIf
                  EndIf
               EndIf
            EndIf
            PreviousElement(llObjects())
         EndIf
      EndIf
   Next

   ;- A9: Re-run A6 to propagate pointer types now that source params are marked
   ; V1.033.45: After A8 marks source params as pointers, propagate to all assignments
   currentFunctionName = ""
   ForEach llObjects()
      If llObjects()\code = #ljFUNCTION
         funcId = llObjects()\i
         If funcId >= 0 And funcId < #C2MAXFUNCTIONS And gFuncNames(funcId) <> ""
            currentFunctionName = gFuncNames(funcId)
         Else
            currentFunctionName = ""
         EndIf
      EndIf
      If llObjects()\code = #ljLFETCH
         srcSlot = llObjects()\i
         srcVarKey = ""
         For varIdx = 0 To gnLastVariable - 1
            If gVarMeta(varIdx)\paramOffset = srcSlot
               varName = gVarMeta(varIdx)\name
               If currentFunctionName <> "" And Left(varName, 1) <> "$"
                  If LCase(Left(varName, Len(currentFunctionName) + 1)) = LCase(currentFunctionName + "_") Or LCase(Left(varName, Len(currentFunctionName) + 2)) = LCase("_" + currentFunctionName + "_")
                     srcVarKey = varName
                     Break
                  EndIf
               ElseIf currentFunctionName = ""
                  srcVarKey = varName
                  Break
               EndIf
            EndIf
         Next
         If srcVarKey <> "" And FindMapElement(mapVariableTypes(), srcVarKey)
            If mapVariableTypes() & #C2FLAG_POINTER
               srcPtrType = mapVariableTypes()
               If NextElement(llObjects())
                  If llObjects()\code = #ljLSTORE
                     dstSlot = llObjects()\i
                     dstVarKey = ""
                     For varIdx = 0 To gnLastVariable - 1
                        If gVarMeta(varIdx)\paramOffset = dstSlot
                           varName = gVarMeta(varIdx)\name
                           If currentFunctionName <> "" And Left(varName, 1) <> "$"
                              If LCase(Left(varName, Len(currentFunctionName) + 1)) = LCase(currentFunctionName + "_") Or LCase(Left(varName, Len(currentFunctionName) + 2)) = LCase("_" + currentFunctionName + "_")
                                 dstVarKey = varName
                                 Break
                              EndIf
                           ElseIf Left(varName, 1) = "$"
                              dstVarKey = varName
                              Break
                           ElseIf currentFunctionName = ""
                              dstVarKey = varName
                              Break
                           EndIf
                        EndIf
                     Next
                     If dstVarKey <> ""
                        mapVariableTypes(dstVarKey) = srcPtrType
                     EndIf
                  EndIf
                  PreviousElement(llObjects())
               EndIf
            EndIf
         EndIf
      EndIf
   Next

   ;- ========================================
   ;- PHASE B: UNIFIED TYPE APPLICATION
   ;- ========================================
   ; Single pass through all instructions applying ALL type transformations

   currentFunctionName = ""   ; V1.033.24: Track function context for Phase B

   ForEach llObjects()
      ; V1.033.24: Track current function for local variable matching
      If llObjects()\code = #ljfunction
         funcId = llObjects()\i
         If funcId >= 0 And funcId < 512
            currentFunctionName = gFuncNames(funcId)
         Else
            currentFunctionName = ""
         EndIf
      ElseIf llObjects()\code = #ljreturn Or llObjects()\code = #ljreturnF Or llObjects()\code = #ljreturnS
         currentFunctionName = ""
      EndIf

      Select llObjects()\code

         ;- B1: PUSH type specialization
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

         ;- B2: GETADDR type specialization
         Case #ljGETADDR
            n = llObjects()\i
            If n >= 0 And n < gnLastVariable
               If gVarMeta(n)\flags & #C2FLAG_FLOAT
                  llObjects()\code = #ljGETADDRF
               ElseIf gVarMeta(n)\flags & #C2FLAG_STR
                  llObjects()\code = #ljGETADDRS
               EndIf
            EndIf

         ;- B3: FETCH pointer conversion
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

         ;- B4: STORE pointer conversion
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

         ;- B5: POP pointer conversion
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

         ;- B6: MOV pointer conversion
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

         ;- B7: LFETCH pointer conversion (uses function context)
         Case #ljLFETCH
            n = llObjects()\i
            isPointer = #False

            ; V1.033.35: Check if this LFETCH is followed by a pointer operation
            ; May need to skip PUSH_IMM for compound assignments (pInt += 3 generates LFETCH + PUSH_IMM + PTRADD)
            If NextElement(llObjects())
               Select llObjects()\code
                  Case #ljPTRFETCH_INT, #ljPTRFETCH_FLOAT, #ljPTRFETCH_STR,
                       #ljPTRSTORE_INT, #ljPTRSTORE_FLOAT, #ljPTRSTORE_STR,
                       #ljPTRADD, #ljPTRSUB
                     isPointer = #True
                  Case #ljPUSH_IMM, #ljPush, #ljPUSHF, #ljPUSHS
                     ; V1.033.35: Skip the push and check what's after it
                     If NextElement(llObjects())
                        Select llObjects()\code
                           Case #ljPTRADD, #ljPTRSUB
                              isPointer = #True
                        EndSelect
                        PreviousElement(llObjects())  ; Go back to PUSH
                     EndIf
               EndSelect
               PreviousElement(llObjects())  ; Go back to LFETCH
            EndIf

            ; V1.033.35: If next opcode is pointer op, convert to PLFETCH
            If isPointer
               llObjects()\code = #ljPLFETCH
            Else
               ; V1.033.24: Fallback - Match function prefix for local variables
               For varIdx = 0 To gnLastVariable - 1
                  If gVarMeta(varIdx)\paramOffset = n
                     ; Verify this variable belongs to current function
                     ; V1.033.42: Handle leading underscore in variable names
                     If currentFunctionName <> "" And (LCase(Left(gVarMeta(varIdx)\name, Len(currentFunctionName) + 1)) = LCase(currentFunctionName + "_") Or LCase(Left(gVarMeta(varIdx)\name, Len(currentFunctionName) + 2)) = LCase("_" + currentFunctionName + "_"))
                        searchKey = gVarMeta(varIdx)\name
                        If FindMapElement(mapVariableTypes(), searchKey)
                           If mapVariableTypes() & #C2FLAG_POINTER
                              llObjects()\code = #ljPLFETCH
                              Break
                           EndIf
                        EndIf
                     ElseIf Left(gVarMeta(varIdx)\name, 1) = "$"
                        searchKey = gVarMeta(varIdx)\name
                        If FindMapElement(mapVariableTypes(), searchKey)
                           If mapVariableTypes() & #C2FLAG_POINTER
                              llObjects()\code = #ljPLFETCH
                              Break
                           EndIf
                        EndIf
                     EndIf
                  EndIf
               Next
            EndIf

         ;- B8: LSTORE pointer conversion (uses function context)
         Case #ljLSTORE
            n = llObjects()\i
            ; V1.033.24: Match function prefix for local variables
            For varIdx = 0 To gnLastVariable - 1
               If gVarMeta(varIdx)\paramOffset = n
                  ; Verify this variable belongs to current function
                  ; V1.033.42: Handle leading underscore in variable names
                  If currentFunctionName <> "" And (LCase(Left(gVarMeta(varIdx)\name, Len(currentFunctionName) + 1)) = LCase(currentFunctionName + "_") Or LCase(Left(gVarMeta(varIdx)\name, Len(currentFunctionName) + 2)) = LCase("_" + currentFunctionName + "_"))
                     searchKey = gVarMeta(varIdx)\name
                     If FindMapElement(mapVariableTypes(), searchKey)
                        If mapVariableTypes() & #C2FLAG_POINTER
                           llObjects()\code = #ljPLSTORE
                           Break
                        EndIf
                     EndIf
                  ElseIf Left(gVarMeta(varIdx)\name, 1) = "$"
                     searchKey = gVarMeta(varIdx)\name
                     If FindMapElement(mapVariableTypes(), searchKey)
                        If mapVariableTypes() & #C2FLAG_POINTER
                           llObjects()\code = #ljPLSTORE
                           Break
                        EndIf
                     EndIf
                  EndIf
               EndIf
            Next

         ;- B9: INC_VAR pointer specialization
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

         ;- B10: DEC_VAR pointer specialization
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

         ;- B11: INC_VAR_PRE/POST pointer specialization
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

         ;- B12: DEC_VAR_PRE/POST pointer specialization
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

         ;- B13: Local pointer increment/decrement
         ; V1.033.25: REMOVED conversion - there are no local typed pointer increment opcodes.
         ; The regular LINC_VAR/LDEC_VAR opcodes increment by 1 which is correct for
         ; array element index pointers. Local pointer arithmetic is handled by the
         ; regular local variable increment operations.
         ; The global typed opcodes (PTRINC_ARRAY etc) use gVar() not gLocal()
         ; so converting local ops to those would access wrong memory.

         ;- B14: ADD to pointer arithmetic conversion
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

         ;- B15: SUB to pointer arithmetic conversion
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

         ;- B16: PRTI print type fixup (look at previous instruction)
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

         ;- B17: ARRAYFETCH/ARRAYSTORE type specialization
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

   ;- ========================================
   ;- PHASE B2: ARRAY VARIANT SPECIALIZATION
   ;- ========================================
   ; Second sub-pass for array GLOBAL/LOCAL × OPT/LOPT/STACK variants
   ; This needs the base type (INT/FLOAT/STR) to be set first


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

   ;- ========================================
   ;- PHASE B3: PTRFETCH SPECIALIZATION
   ;- ========================================

   ForEach llObjects()
      If llObjects()\code = #ljPTRFETCH
         If PreviousElement(llObjects())
            If llObjects()\code = #ljFetch Or llObjects()\code = #ljFETCHF Or llObjects()\code = #ljFETCHS Or llObjects()\code = #ljLFETCH Or llObjects()\code = #ljLFETCHF Or llObjects()\code = #ljLFETCHS Or llObjects()\code = #ljPFETCH Or llObjects()\code = #ljPLFETCH
               varSlot = llObjects()\i
               *savedPos = @llObjects()
               foundGetAddr = #False
               isArrayPointer = #False
               isLocalPointer = #False
               getAddrType = #ljGETADDR

               While PreviousElement(llObjects())
                  If (llObjects()\code = #ljStore Or llObjects()\code = #ljPOP Or llObjects()\code = #ljLSTORE Or llObjects()\code = #ljPSTORE Or llObjects()\code = #ljPLSTORE) And llObjects()\i = varSlot
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
                        ; Local variable address
                        ElseIf llObjects()\code = #ljGETLOCALADDR Or llObjects()\code = #ljGETLOCALADDRF Or llObjects()\code = #ljGETLOCALADDRS
                           getAddrType = llObjects()\code
                           foundGetAddr = #True
                           isLocalPointer = #True
                           Break
                        ; Local array address
                        ElseIf llObjects()\code = #ljGETLOCALARRAYADDR Or llObjects()\code = #ljGETLOCALARRAYADDRF Or llObjects()\code = #ljGETLOCALARRAYADDRS
                           getAddrType = llObjects()\code
                           isArrayPointer = #True
                           isLocalPointer = #True
                           Break
                        ElseIf llObjects()\code = #ljPTRADD Or llObjects()\code = #ljPTRSUB
                           isArrayPointer = #True
                           Break
                        EndIf
                        NextElement(llObjects())
                     EndIf
                  ElseIf llObjects()\code = #ljFUNCTION
                     Break
                  EndIf
               Wend

               ChangeCurrentElement(llObjects(), *savedPos)
               NextElement(llObjects())  ; Back to PTRFETCH

               ; Specialize based on source type
               If foundGetAddr And Not isArrayPointer
                  ; Simple variable pointer
                  If isLocalPointer
                     Select getAddrType
                        Case #ljGETLOCALADDRF
                           llObjects()\code = #ljPTRFETCH_LVAR_FLOAT
                        Case #ljGETLOCALADDRS
                           llObjects()\code = #ljPTRFETCH_LVAR_STR
                        Default
                           llObjects()\code = #ljPTRFETCH_LVAR_INT
                     EndSelect
                  Else
                     Select getAddrType
                        Case #ljGETADDRF
                           llObjects()\code = #ljPTRFETCH_VAR_FLOAT
                        Case #ljGETADDRS
                           llObjects()\code = #ljPTRFETCH_VAR_STR
                        Default
                           llObjects()\code = #ljPTRFETCH_VAR_INT
                     EndSelect
                  EndIf
               ElseIf isArrayPointer
                  ; Array element pointer
                  If isLocalPointer
                     Select getAddrType
                        Case #ljGETLOCALARRAYADDRF
                           llObjects()\code = #ljPTRFETCH_LARREL_FLOAT
                        Case #ljGETLOCALARRAYADDRS
                           llObjects()\code = #ljPTRFETCH_LARREL_STR
                        Default
                           llObjects()\code = #ljPTRFETCH_LARREL_INT
                     EndSelect
                  Else
                     Select getAddrType
                        Case #ljGETARRAYADDRF
                           llObjects()\code = #ljPTRFETCH_ARREL_FLOAT
                        Case #ljGETARRAYADDRS
                           llObjects()\code = #ljPTRFETCH_ARREL_STR
                        Default
                           llObjects()\code = #ljPTRFETCH_ARREL_INT
                     EndSelect
                  EndIf
               EndIf
            Else
               NextElement(llObjects())
            EndIf
         EndIf
      EndIf
   Next

   ;- ========================================
   ;- PHASE B4: PRINT TYPE FIXUPS (PTRFETCH variants)
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

   ;- ========================================
   ;- PHASE B5: POINTER ARRAY POP CONVERSION
   ;- ========================================
   ; V1.033.44: When a POP follows an array fetch from a pointer array,
   ; convert POP to PPOP to preserve pointer metadata

   ForEach llObjects()
      ; Check for array fetch opcodes from INT arrays (pointer arrays are INT-typed)
      Select llObjects()\code
         Case #ljARRAYFETCH_INT_GLOBAL_OPT, #ljARRAYFETCH_INT_GLOBAL_STACK, #ljARRAYFETCH_INT_GLOBAL_LOPT,
              #ljARRAYFETCH_INT_LOCAL_OPT, #ljARRAYFETCH_INT_LOCAL_STACK, #ljARRAYFETCH_INT_LOCAL_LOPT
            prevArraySlot = llObjects()\i
            ; V1.033.44: Check if this is a pointer array (ARRAY | POINTER flags)
            If prevArraySlot >= 0 And prevArraySlot < gnLastVariable
               If (gVarMeta(prevArraySlot)\flags & #C2FLAG_ARRAY) And (gVarMeta(prevArraySlot)\flags & #C2FLAG_POINTER)
                  ; Next instruction could be a POP to store the pointer value
                  If NextElement(llObjects())
                     If llObjects()\code = #ljPOP
                        llObjects()\code = #ljPPOP
                     EndIf
                     PreviousElement(llObjects())
                  EndIf
               EndIf
            EndIf
      EndSelect
   Next


EndProcedure

; IDE Options = PureBasic 6.10 LTS (Windows - x64)
; EnableThread
; EnableXP
; CPU = 1
