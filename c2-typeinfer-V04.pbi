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
         CompilerIf #DEBUG : Debug "FUNCTRACK: Found #ljfunction funcId=" + Str(funcId) : CompilerEndIf
         ; V1.034.41: Fixed to use #C2MAXFUNCTIONS (was 512, now 8192)
         If funcId >= 0 And funcId < #C2MAXFUNCTIONS
            currentFunctionName = gFuncNames(funcId)
            CompilerIf #DEBUG : Debug "FUNCTRACK: Set currentFunctionName=" + currentFunctionName : CompilerEndIf
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
                  ; V1.034.1: Use O(1) lookup by offset instead of O(N) scan
                  varIdx = FindVariableSlotByOffset(ptrVarSlot, currentFunctionName)
                  If varIdx >= 0
                     ptrVarKey = gVarMeta(varIdx)\name
                  EndIf
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
                  ; V1.034.1: Use O(1) lookup by offset instead of O(N) scan
                  varIdx = FindVariableSlotByOffset(ptrVarSlot, currentFunctionName)
                  If varIdx >= 0
                     ptrVarKey = gVarMeta(varIdx)\name
                  EndIf
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
            CompilerIf #DEBUG
               Debug "A3 DEBUG: MOV src=" + Str(srcVar) + " dst=" + Str(dstVar) + " code=" + Str(llObjects()\code)
               If srcVar >= 0 And srcVar < gnLastVariable
                  Debug "  srcName=[" + gVarMeta(srcVar)\name + "] srcFlags=" + Str(gVarMeta(srcVar)\flags)
               EndIf
               If dstVar >= 0 And dstVar < gnLastVariable
                  Debug "  dstName=[" + gVarMeta(dstVar)\name + "] dstFlags=" + Str(gVarMeta(dstVar)\flags)
               EndIf
            CompilerEndIf
            sourceIsPointer = #False
            sourceIsArrayPointer = #False
            searchKey = ""

            ; V1.034.2: Handle LLMOV (local-to-local) - use FindVariableSlotByOffset for locals
            If llObjects()\code = #ljLLMOV
               ; For LLMOV, srcVar is a local offset, not a gVarMeta index
               varIdx = FindVariableSlotByOffset(srcVar, currentFunctionName)
               If varIdx >= 0
                  searchKey = gVarMeta(varIdx)\name
                  If FindMapElement(mapVariableTypes(), searchKey)
                     If mapVariableTypes() & #C2FLAG_POINTER
                        sourceIsPointer = #True
                        pointerBaseType = mapVariableTypes() & #C2FLAG_TYPE
                        sourceIsArrayPointer = Bool((mapVariableTypes() & #C2FLAG_ARRAYPTR) <> 0)
                     EndIf
                  EndIf
                  ; V1.034.40: Removed incorrect param=pointer assumption
                  ; Parameters are only pointers if explicitly assigned from pointers
                  ; or used with pointer operations (PTRFETCH/PTRSTORE)
               EndIf
            Else
               ; For MOV/PMOV/LMOV, srcVar is a gVarMeta slot
               If srcVar >= 0 And srcVar < gnLastVariable
                  searchKey = gVarMeta(srcVar)\name
                  If FindMapElement(mapVariableTypes(), searchKey)
                     If mapVariableTypes() & #C2FLAG_POINTER
                        sourceIsPointer = #True
                        pointerBaseType = mapVariableTypes() & #C2FLAG_TYPE
                        sourceIsArrayPointer = Bool((mapVariableTypes() & #C2FLAG_ARRAYPTR) <> 0)
                     EndIf
                  EndIf
                  ; V1.034.40: Removed incorrect param=pointer assumption
                  ; Constants like "0" can have #C2FLAG_PARAM incorrectly set
                  ; causing innocent variables like "i" to be marked as pointers
               EndIf
            EndIf

            ; Handle destination variable
            If sourceIsPointer
               ptrVarKey = ""
               ; V1.034.2: For LLMOV, dstVar is also a local offset
               If llObjects()\code = #ljLLMOV
                  varIdx = FindVariableSlotByOffset(dstVar, currentFunctionName)
                  If varIdx >= 0
                     ptrVarKey = gVarMeta(varIdx)\name
                  EndIf
               Else
                  If dstVar >= 0 And dstVar < gnLastVariable
                     ptrVarKey = gVarMeta(dstVar)\name
                  EndIf
               EndIf

               If ptrVarKey <> ""
                  If sourceIsArrayPointer
                     CompilerIf #DEBUG : Debug "A3 ADDING TO MAP: " + ptrVarKey + " = " + Str(#C2FLAG_POINTER | pointerBaseType | #C2FLAG_ARRAYPTR) + " (sourceIsPointer from " + searchKey + ")" : CompilerEndIf
                     mapVariableTypes(ptrVarKey) = #C2FLAG_POINTER | pointerBaseType | #C2FLAG_ARRAYPTR
                  Else
                     CompilerIf #DEBUG : Debug "A3 ADDING TO MAP: " + ptrVarKey + " = " + Str(#C2FLAG_POINTER | pointerBaseType) + " (sourceIsPointer from " + searchKey + ")" : CompilerEndIf
                     mapVariableTypes(ptrVarKey) = #C2FLAG_POINTER | pointerBaseType
                  EndIf
                  ; V1.034.21: Convert MOV to unified PMOV with n-field encoding
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
                  EndSelect
               EndIf
            EndIf

         ;- A4: Variables used with PTRFETCH/PTRSTORE operations
         ; V1.034.41: Fixed A4 to handle local variables (LFETCH and PFETCH with j=1)
         ; For locals, use FindVariableSlotByOffset instead of treating i as gVarMeta slot
         Case #ljPTRFETCH_INT, #ljPTRFETCH_FLOAT, #ljPTRFETCH_STR, #ljPTRSTORE_INT, #ljPTRSTORE_FLOAT, #ljPTRSTORE_STR
            ptrOpcode = llObjects()\code
            If PreviousElement(llObjects())
               If llObjects()\code = #ljFetch Or llObjects()\code = #ljPFETCH Or llObjects()\code = #ljLFETCH
                  ptrVarSlot = llObjects()\i
                  ptrVarKey = ""
                  CompilerIf #DEBUG : Debug "A4 FETCH CHECK: code=" + Str(llObjects()\code) + " j=" + Str(llObjects()\j) + " #ljPFETCH=" + Str(#ljPFETCH) + " #ljLFETCH=" + Str(#ljLFETCH) : CompilerEndIf
                  ; V1.034.41: Check if this is a local fetch (LFETCH, PFETCH with j=1, or unified Fetch with j=1)
                  ; V1.034.42: Fixed - unified Fetch/PUSH opcodes use j=1 for locals, not separate PFETCH opcode
                  If llObjects()\code = #ljLFETCH Or (llObjects()\code = #ljPFETCH And llObjects()\j = 1) Or (llObjects()\code = #ljFetch And llObjects()\j = 1)
                     ; Local variable - use FindVariableSlotByOffset
                     CompilerIf #DEBUG : Debug "A4 LOCAL BRANCH: ptrVarSlot=" + Str(ptrVarSlot) + " func=" + currentFunctionName : CompilerEndIf
                     varIdx = FindVariableSlotByOffset(ptrVarSlot, currentFunctionName)
                     If varIdx >= 0
                        ptrVarKey = gVarMeta(varIdx)\name
                     EndIf
                  Else
                     ; Global variable - ptrVarSlot is the gVarMeta slot
                     If ptrVarSlot >= 0 And ptrVarSlot < gnLastVariable
                        ptrVarKey = gVarMeta(ptrVarSlot)\name
                     EndIf
                  EndIf
                  If ptrVarKey <> ""
                     If Not FindMapElement(mapVariableTypes(), ptrVarKey)
                        AddMapElement(mapVariableTypes(), ptrVarKey)
                     EndIf
                     If (mapVariableTypes() & #C2FLAG_POINTER) = 0
                        Select ptrOpcode
                           Case #ljPTRFETCH_INT, #ljPTRSTORE_INT
                              CompilerIf #DEBUG : Debug "A4 ADDING TO MAP: " + ptrVarKey + " = " + Str(#C2FLAG_POINTER | #C2FLAG_INT) + " (slot=" + Str(ptrVarSlot) + " func=" + currentFunctionName + " fetchCode=" + Str(llObjects()\code) + " j=" + Str(llObjects()\j) + ")" : CompilerEndIf
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
      If (llObjects()\code = #ljPFETCH And llObjects()\j = 1) Or llObjects()\code = #ljLFETCH
         srcSlot = llObjects()\i
         srcVarKey = ""
         ; V1.034.1: Use O(1) lookup by offset instead of O(N) scan
         varIdx = FindVariableSlotByOffset(srcSlot, currentFunctionName)
         If varIdx >= 0
            srcVarKey = gVarMeta(varIdx)\name
         EndIf
         If srcVarKey <> "" And NextElement(llObjects())
            Select llObjects()\code
               Case #ljPTRFETCH_INT, #ljPTRFETCH_FLOAT, #ljPTRFETCH_STR, #ljPTRSTORE_INT, #ljPTRSTORE_FLOAT, #ljPTRSTORE_STR
                  If Not FindMapElement(mapVariableTypes(), srcVarKey)
                     AddMapElement(mapVariableTypes(), srcVarKey)
                  EndIf
                  If (mapVariableTypes() & #C2FLAG_POINTER) = 0
                     Select llObjects()\code
                        Case #ljPTRFETCH_INT, #ljPTRSTORE_INT
                           CompilerIf #DEBUG : Debug "A5 ADDING TO MAP: " + srcVarKey + " = " + Str(#C2FLAG_POINTER | #C2FLAG_INT) : CompilerEndIf
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
   ; V1.034.69: Also check for unified Fetch (j=1) and PFETCH (j=1) for locals
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
      ; V1.034.69: Check for local fetch opcodes: LFETCH, Fetch with j=1, PFETCH with j=1
      If llObjects()\code = #ljLFETCH Or (llObjects()\code = #ljFetch And llObjects()\j = 1) Or (llObjects()\code = #ljPFETCH And llObjects()\j = 1)
         srcSlot = llObjects()\i
         srcVarKey = ""
         ; V1.034.1: Use O(1) lookup by offset instead of O(N) scan
         varIdx = FindVariableSlotByOffset(srcSlot, currentFunctionName)
         If varIdx >= 0
            srcVarKey = gVarMeta(varIdx)\name
         EndIf
         ; Check if source is a known pointer
         If srcVarKey <> "" And FindMapElement(mapVariableTypes(), srcVarKey)
            If mapVariableTypes() & #C2FLAG_POINTER
               srcPtrType = mapVariableTypes()
               ; Check if next instruction is LSTORE (local-to-local copy)
               If NextElement(llObjects())
                  ; V1.034.43: Check for LSTORE or unified Store with j=1 (local)
                  If llObjects()\code = #ljLSTORE Or (llObjects()\code = #ljStore And llObjects()\j = 1)
                     dstSlot = llObjects()\i
                     dstVarKey = ""
                     ; V1.034.1: Use O(1) lookup by offset instead of O(N) scan
                     varIdx = FindVariableSlotByOffset(dstSlot, currentFunctionName)
                     If varIdx >= 0
                        dstVarKey = gVarMeta(varIdx)\name
                     EndIf
                     ; Mark destination as pointer with same type as source
                     If dstVarKey <> ""
                        CompilerIf #DEBUG : Debug "A6 ADDING TO MAP: " + dstVarKey + " = " + Str(srcPtrType) + " (from " + srcVarKey + ")" : CompilerEndIf
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
               ; V1.034.1: Use O(1) lookup by offset instead of O(N) scan
               varIdx = FindVariableSlotByOffset(localPtrSlot, currentFunctionName)
               If varIdx >= 0
                  CompilerIf #DEBUG : Debug "A7 ADDING TO MAP: " + gVarMeta(varIdx)\name + " = " + Str(#C2FLAG_POINTER | #C2FLAG_INT | #C2FLAG_ARRAYPTR) + " (LINCV/LDECV+POP pattern)" : CompilerEndIf
                  mapVariableTypes(gVarMeta(varIdx)\name) = #C2FLAG_POINTER | #C2FLAG_INT | #C2FLAG_ARRAYPTR
               EndIf
            EndIf
            PreviousElement(llObjects())
         EndIf
      EndIf
   Next

   ;- A7b: Detect pointer locals passed as function arguments
   ; V1.034.69: When a local is fetched right before CALL2/CALL to a function whose
   ; corresponding parameter is used with PTRFETCH, mark that local as pointer
   ; This handles cases like: swap(left, right) where swap uses a\i and b\i
   ; First, collect all function parameter pointer info from A4 results
   Protected NewMap funcParamIsPointer.i()  ; "funcName_paramOffset" -> 1 if pointer
   currentFunctionName = ""
   ForEach mapVariableTypes()
      ; Parameter variables have names like "funcName_paramName"
      ; Check if this is a pointer and extract function name
      If mapVariableTypes() & #C2FLAG_POINTER
         Protected ptrVarName.s = MapKey(mapVariableTypes())
         Protected underscorePos.i = FindString(ptrVarName, "_")
         If underscorePos > 0
            Protected funcNamePart.s = Left(ptrVarName, underscorePos - 1)
            ; Find the variable's offset in gVarMeta
            For n = 0 To gnLastVariable - 1
               If gVarMeta(n)\name = ptrVarName And gVarMeta(n)\paramOffset >= 0
                  ; This is a parameter - record its offset within the function
                  funcParamIsPointer(funcNamePart + "_" + Str(gVarMeta(n)\paramOffset)) = 1
                  CompilerIf #DEBUG : Debug "A7b: funcParamIsPointer(" + funcNamePart + "_" + Str(gVarMeta(n)\paramOffset) + ") = 1" : CompilerEndIf
                  Break
               EndIf
            Next
         EndIf
      EndIf
   Next

   ; Now scan for FETCH + CALL patterns and mark locals that are passed to pointer parameters
   Protected callArgSlots.i
   Protected Dim callArgs.i(8)  ; Track up to 8 arguments before CALL
   Protected callArgCount.i
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

      ; When we see a CALL2, look back at the previous FETCH operations
      If llObjects()\code = #ljCALL2 Or llObjects()\code = #ljCALL
         Protected callTargetFuncId.i = llObjects()\j
         Protected calledFuncName.s = ""
         If callTargetFuncId >= 0 And callTargetFuncId < #C2MAXFUNCTIONS
            calledFuncName = gFuncNames(callTargetFuncId)
         EndIf

         ; Look back for FETCH operations that provide arguments
         If calledFuncName <> ""
            Protected argIdx.i = 0
            Protected *callPos = @llObjects()
            While PreviousElement(llObjects()) And argIdx < 8
               ; Stop at function boundary or other non-fetch ops
               If llObjects()\code = #ljFUNCTION Or llObjects()\code = #ljRETURN
                  Break
               EndIf
               ; Check for local FETCH (j=1) - these are arguments
               If (llObjects()\code = #ljFetch And llObjects()\j = 1) Or llObjects()\code = #ljLFETCH Or (llObjects()\code = #ljPFETCH And llObjects()\j = 1)
                  ; This is a local being passed as argument
                  Protected argLocalSlot.i = llObjects()\i
                  ; Check if corresponding parameter in called function is a pointer
                  ; Arguments are pushed in order, so first FETCH = first param (offset 0)
                  ; But we're scanning backwards, so we need to track position
                  callArgs(argIdx) = argLocalSlot
                  argIdx + 1
               ElseIf llObjects()\code = #ljPUSH_IMM Or llObjects()\code = #ljPUSH
                  ; Immediate or global value pushed - not a local, skip
                  argIdx + 1
               ElseIf llObjects()\code = #ljCALL2 Or llObjects()\code = #ljCALL
                  ; Another call - stop looking back
                  Break
               EndIf
            Wend
            ; Restore position
            ChangeCurrentElement(llObjects(), *callPos)

            ; Now check each argument against function's parameter types
            ; Arguments are in reverse order (last arg pushed first when scanning back)
            Protected paramOffset.i
            For paramOffset = 0 To argIdx - 1
               ; Reverse index to get correct param offset
               Protected actualArgIdx.i = argIdx - 1 - paramOffset
               If FindMapElement(funcParamIsPointer(), calledFuncName + "_" + Str(paramOffset))
                  ; This parameter is used as a pointer in the called function
                  ; Mark the corresponding argument local as a pointer
                  varIdx = FindVariableSlotByOffset(callArgs(actualArgIdx), currentFunctionName)
                  If varIdx >= 0
                     ptrVarKey = gVarMeta(varIdx)\name
                     If Not FindMapElement(mapVariableTypes(), ptrVarKey)
                        CompilerIf #DEBUG : Debug "A7b ADDING TO MAP: " + ptrVarKey + " = " + Str(#C2FLAG_POINTER | #C2FLAG_INT) + " (passed to " + calledFuncName + " param " + Str(paramOffset) + ")" : CompilerEndIf
                        mapVariableTypes(ptrVarKey) = #C2FLAG_POINTER | #C2FLAG_INT
                     EndIf
                  EndIf
               EndIf
            Next
         EndIf
      EndIf
   Next

   ;- A7c: Detect pointer locals via assignment-from-local + increment/decrement pattern
   ; V1.034.69: If a local is assigned from another local and later incremented/decremented,
   ; it's likely being used for pointer arithmetic (e.g., left = ptr; ... left++)
   ; First pass: track which locals are assigned from other locals
   Protected NewMap localFromLocal.i()  ; "funcName_localOffset" -> source local offset
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
      ; Look for FETCH local + STORE local pattern (covers all local-to-local assignments)
      ; Check multiple FETCH opcode types that access locals
      If (llObjects()\code = #ljFetch And llObjects()\j = 1) Or llObjects()\code = #ljLFETCH Or (llObjects()\code = #ljPFETCH And llObjects()\j = 1)
         Protected a7cSrcSlot.i = llObjects()\i
         If NextElement(llObjects())
            If (llObjects()\code = #ljStore And llObjects()\j = 1) Or llObjects()\code = #ljLSTORE
               Protected a7cDstSlot.i = llObjects()\i
               ; Record that this local (dstSlot) was assigned from another local (srcSlot)
               localFromLocal(currentFunctionName + "_" + Str(a7cDstSlot)) = a7cSrcSlot
               CompilerIf #DEBUG : Debug "A7c: localFromLocal(" + currentFunctionName + "_" + Str(a7cDstSlot) + ") = " + Str(a7cSrcSlot) : CompilerEndIf
            EndIf
            PreviousElement(llObjects())
         EndIf
      EndIf
   Next

   ; Second pass: if a local that came from another local is incremented/decremented, mark it as pointer
   ; This is a strong heuristic: local vars assigned from params and then inc/dec'd are almost always pointers
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
      ; Check for INC_VAR_POST/PRE or DEC_VAR_POST/PRE with j=1 (local)
      ; V1.034.70: TypeInference runs BEFORE optimizer, so we see _POST/_PRE forms, not optimized INC_VAR/DEC_VAR
      If (llObjects()\code = #ljINC_VAR_POST Or llObjects()\code = #ljINC_VAR_PRE Or llObjects()\code = #ljDEC_VAR_POST Or llObjects()\code = #ljDEC_VAR_PRE) And llObjects()\j = 1
         Protected a7cIncSlot.i = llObjects()\i
         If FindMapElement(localFromLocal(), currentFunctionName + "_" + Str(a7cIncSlot))
            ; This local was assigned from another local and is being incremented/decremented
            ; This is a strong indicator it's a pointer
            varIdx = FindVariableSlotByOffset(a7cIncSlot, currentFunctionName)
            If varIdx >= 0
               ptrVarKey = gVarMeta(varIdx)\name
               If Not FindMapElement(mapVariableTypes(), ptrVarKey)
                  CompilerIf #DEBUG : Debug "A7c ADDING TO MAP: " + ptrVarKey + " = " + Str(#C2FLAG_POINTER | #C2FLAG_INT) + " (assigned from local, then inc/dec)" : CompilerEndIf
                  mapVariableTypes(ptrVarKey) = #C2FLAG_POINTER | #C2FLAG_INT
               EndIf
            EndIf
            ; Also mark the source local as pointer (it's likely a parameter)
            Protected a7cSrcLocalSlot.i = localFromLocal()
            varIdx = FindVariableSlotByOffset(a7cSrcLocalSlot, currentFunctionName)
            If varIdx >= 0
               ptrVarKey = gVarMeta(varIdx)\name
               If Not FindMapElement(mapVariableTypes(), ptrVarKey)
                  CompilerIf #DEBUG : Debug "A7c ADDING TO MAP: " + ptrVarKey + " = " + Str(#C2FLAG_POINTER | #C2FLAG_INT) + " (source of inc/dec local)" : CompilerEndIf
                  mapVariableTypes(ptrVarKey) = #C2FLAG_POINTER | #C2FLAG_INT
               EndIf
            EndIf
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
               ; V1.034.1: Use O(1) lookup by offset instead of O(N) scan
               varIdx = FindVariableSlotByOffset(dstSlot, currentFunctionName)
               If varIdx >= 0
                  dstVarKey = gVarMeta(varIdx)\name
               EndIf
               ; If destination is a known pointer, mark source as pointer too
               If dstVarKey <> "" And FindMapElement(mapVariableTypes(), dstVarKey)
                  If mapVariableTypes() & #C2FLAG_POINTER
                     srcVarKey = ""
                     ; V1.034.1: Use O(1) lookup by offset instead of O(N) scan
                     varIdx = FindVariableSlotByOffset(srcSlot, currentFunctionName)
                     If varIdx >= 0
                        srcVarKey = gVarMeta(varIdx)\name
                     EndIf
                     If srcVarKey <> ""
                        CompilerIf #DEBUG : Debug "A8 ADDING TO MAP: " + srcVarKey + " = " + Str(mapVariableTypes(dstVarKey)) + " (backprop from " + dstVarKey + ")" : CompilerEndIf
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
   ; V1.034.43: Handle unified Fetch/Store opcodes with j=1 for locals
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
      ; V1.034.43: Check for LFETCH or unified Fetch with j=1 (local)
      If llObjects()\code = #ljLFETCH Or (llObjects()\code = #ljFetch And llObjects()\j = 1)
         srcSlot = llObjects()\i
         srcVarKey = ""
         ; V1.034.1: Use O(1) lookup by offset instead of O(N) scan
         varIdx = FindVariableSlotByOffset(srcSlot, currentFunctionName)
         If varIdx >= 0
            srcVarKey = gVarMeta(varIdx)\name
         EndIf
         If srcVarKey <> "" And FindMapElement(mapVariableTypes(), srcVarKey)
            If mapVariableTypes() & #C2FLAG_POINTER
               srcPtrType = mapVariableTypes()
               If NextElement(llObjects())
                  ; V1.034.43: Check for LSTORE or unified Store with j=1 (local)
                  If llObjects()\code = #ljLSTORE Or (llObjects()\code = #ljStore And llObjects()\j = 1)
                     dstSlot = llObjects()\i
                     dstVarKey = ""
                     ; V1.034.1: Use O(1) lookup by offset instead of O(N) scan
                     varIdx = FindVariableSlotByOffset(dstSlot, currentFunctionName)
                     If varIdx >= 0
                        dstVarKey = gVarMeta(varIdx)\name
                     EndIf
                     If dstVarKey <> ""
                        CompilerIf #DEBUG : Debug "A9 ADDING TO MAP: " + dstVarKey + " = " + Str(srcPtrType) + " (re-propagate from " + srcVarKey + ")" : CompilerEndIf
                        mapVariableTypes(dstVarKey) = srcPtrType
                     EndIf
                  EndIf
                  PreviousElement(llObjects())
               EndIf
            EndIf
         EndIf
      EndIf
   Next

   ;- A10: Convert LLMOV to LLPMOV for pointer copies
   ; V1.034.2: Now that all pointer types are discovered (A5-A9), convert MOV opcodes
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
      If llObjects()\code = #ljLLMOV
         srcSlot = llObjects()\j
         srcVarKey = ""
         varIdx = FindVariableSlotByOffset(srcSlot, currentFunctionName)
         If varIdx >= 0
            srcVarKey = gVarMeta(varIdx)\name
         EndIf
         If srcVarKey <> "" And FindMapElement(mapVariableTypes(), srcVarKey)
            If mapVariableTypes() & #C2FLAG_POINTER
               ; V1.034.21: Use unified PMOV with n=3 for LL
               llObjects()\code = #ljPMOV
               llObjects()\n = 3
            EndIf
         EndIf
      EndIf
   Next

   ;- A11: Convert INC/DEC opcodes for pointer variables to PTRADD/PTRSUB
   ; V1.034.69: Pointer increment/decrement must use PTRADD/PTRSUB (scales by element size)
   ; Convert INC_VAR_POST/PRE and DEC_VAR_POST/PRE when variable is a known pointer
   ; For locals: j=1 indicates local variable, i is the offset
   ; For globals: j=0 (or absent), i is the gVarMeta slot
   ; V1.034.71: Skip A11 entirely if no pointer variables were detected
   Protected hasPointerVars.i = #False
   ForEach mapVariableTypes()
      If mapVariableTypes() & #C2FLAG_POINTER
         hasPointerVars = #True
         Break
      EndIf
   Next

   If hasPointerVars
   Protected ptrIncDecSlot.i, ptrIncDecVarKey.s, ptrIncDecIsLocal.i
   Protected *insertPos, ptrIncDecType.w
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

      ; Check for local post-increment: INC_VAR_POST with j=1
      If llObjects()\code = #ljINC_VAR_POST And llObjects()\j = 1
         ptrIncDecSlot = llObjects()\i
         ptrIncDecVarKey = ""
         varIdx = FindVariableSlotByOffset(ptrIncDecSlot, currentFunctionName)
         If varIdx >= 0
            ptrIncDecVarKey = gVarMeta(varIdx)\name
         EndIf
         If ptrIncDecVarKey <> "" And FindMapElement(mapVariableTypes(), ptrIncDecVarKey)
            If mapVariableTypes() & #C2FLAG_POINTER
               CompilerIf #DEBUG : Debug "A11: Converting LINC_VAR_POST to pointer ops for " + ptrIncDecVarKey : CompilerEndIf
               ; Convert INC_VAR_POST to: PFETCH (old), PFETCH, PUSH 1, PTRADD, PSTORE
               ; First instruction becomes PFETCH (push old value for return)
               llObjects()\code = #ljPFETCH
               ; llObjects()\i already has the offset, llObjects()\j already 1
               ; Add remaining instructions after this one
               *insertPos = @llObjects()
               AddElement(llObjects())
               MoveElement(llObjects(), #PB_List_After, *insertPos)
               llObjects()\code = #ljPFETCH : llObjects()\i = ptrIncDecSlot : llObjects()\j = 1
               *insertPos = @llObjects()
               AddElement(llObjects())
               MoveElement(llObjects(), #PB_List_After, *insertPos)
               llObjects()\code = #ljPUSH_IMM : llObjects()\i = 1
               *insertPos = @llObjects()
               AddElement(llObjects())
               MoveElement(llObjects(), #PB_List_After, *insertPos)
               llObjects()\code = #ljPTRADD
               *insertPos = @llObjects()
               AddElement(llObjects())
               MoveElement(llObjects(), #PB_List_After, *insertPos)
               llObjects()\code = #ljPSTORE : llObjects()\i = ptrIncDecSlot : llObjects()\j = 1
            EndIf
         EndIf
      EndIf

      ; Check for local post-decrement: DEC_VAR_POST with j=1
      If llObjects()\code = #ljDEC_VAR_POST And llObjects()\j = 1
         ptrIncDecSlot = llObjects()\i
         ptrIncDecVarKey = ""
         varIdx = FindVariableSlotByOffset(ptrIncDecSlot, currentFunctionName)
         If varIdx >= 0
            ptrIncDecVarKey = gVarMeta(varIdx)\name
         EndIf
         If ptrIncDecVarKey <> "" And FindMapElement(mapVariableTypes(), ptrIncDecVarKey)
            If mapVariableTypes() & #C2FLAG_POINTER
               CompilerIf #DEBUG : Debug "A11: Converting LDEC_VAR_POST to pointer ops for " + ptrIncDecVarKey : CompilerEndIf
               ; Convert DEC_VAR_POST to: PFETCH (old), PFETCH, PUSH 1, PTRSUB, PSTORE
               llObjects()\code = #ljPFETCH
               *insertPos = @llObjects()
               AddElement(llObjects())
               MoveElement(llObjects(), #PB_List_After, *insertPos)
               llObjects()\code = #ljPFETCH : llObjects()\i = ptrIncDecSlot : llObjects()\j = 1
               *insertPos = @llObjects()
               AddElement(llObjects())
               MoveElement(llObjects(), #PB_List_After, *insertPos)
               llObjects()\code = #ljPUSH_IMM : llObjects()\i = 1
               *insertPos = @llObjects()
               AddElement(llObjects())
               MoveElement(llObjects(), #PB_List_After, *insertPos)
               llObjects()\code = #ljPTRSUB
               *insertPos = @llObjects()
               AddElement(llObjects())
               MoveElement(llObjects(), #PB_List_After, *insertPos)
               llObjects()\code = #ljPSTORE : llObjects()\i = ptrIncDecSlot : llObjects()\j = 1
            EndIf
         EndIf
      EndIf

      ; Check for local pre-increment: INC_VAR_PRE with j=1
      If llObjects()\code = #ljINC_VAR_PRE And llObjects()\j = 1
         ptrIncDecSlot = llObjects()\i
         ptrIncDecVarKey = ""
         varIdx = FindVariableSlotByOffset(ptrIncDecSlot, currentFunctionName)
         If varIdx >= 0
            ptrIncDecVarKey = gVarMeta(varIdx)\name
         EndIf
         If ptrIncDecVarKey <> "" And FindMapElement(mapVariableTypes(), ptrIncDecVarKey)
            If mapVariableTypes() & #C2FLAG_POINTER
               CompilerIf #DEBUG : Debug "A11: Converting LINC_VAR_PRE to pointer ops for " + ptrIncDecVarKey : CompilerEndIf
               ; Convert INC_VAR_PRE to: PFETCH, PUSH 1, PTRADD, DUP, PSTORE
               llObjects()\code = #ljPFETCH
               *insertPos = @llObjects()
               AddElement(llObjects())
               MoveElement(llObjects(), #PB_List_After, *insertPos)
               llObjects()\code = #ljPUSH_IMM : llObjects()\i = 1
               *insertPos = @llObjects()
               AddElement(llObjects())
               MoveElement(llObjects(), #PB_List_After, *insertPos)
               llObjects()\code = #ljPTRADD
               *insertPos = @llObjects()
               AddElement(llObjects())
               MoveElement(llObjects(), #PB_List_After, *insertPos)
               llObjects()\code = #ljDUP
               *insertPos = @llObjects()
               AddElement(llObjects())
               MoveElement(llObjects(), #PB_List_After, *insertPos)
               llObjects()\code = #ljPSTORE : llObjects()\i = ptrIncDecSlot : llObjects()\j = 1
            EndIf
         EndIf
      EndIf

      ; Check for local pre-decrement: DEC_VAR_PRE with j=1
      If llObjects()\code = #ljDEC_VAR_PRE And llObjects()\j = 1
         ptrIncDecSlot = llObjects()\i
         ptrIncDecVarKey = ""
         varIdx = FindVariableSlotByOffset(ptrIncDecSlot, currentFunctionName)
         If varIdx >= 0
            ptrIncDecVarKey = gVarMeta(varIdx)\name
         EndIf
         If ptrIncDecVarKey <> "" And FindMapElement(mapVariableTypes(), ptrIncDecVarKey)
            If mapVariableTypes() & #C2FLAG_POINTER
               CompilerIf #DEBUG : Debug "A11: Converting LDEC_VAR_PRE to pointer ops for " + ptrIncDecVarKey : CompilerEndIf
               ; Convert DEC_VAR_PRE to: PFETCH, PUSH 1, PTRSUB, DUP, PSTORE
               llObjects()\code = #ljPFETCH
               *insertPos = @llObjects()
               AddElement(llObjects())
               MoveElement(llObjects(), #PB_List_After, *insertPos)
               llObjects()\code = #ljPUSH_IMM : llObjects()\i = 1
               *insertPos = @llObjects()
               AddElement(llObjects())
               MoveElement(llObjects(), #PB_List_After, *insertPos)
               llObjects()\code = #ljPTRSUB
               *insertPos = @llObjects()
               AddElement(llObjects())
               MoveElement(llObjects(), #PB_List_After, *insertPos)
               llObjects()\code = #ljDUP
               *insertPos = @llObjects()
               AddElement(llObjects())
               MoveElement(llObjects(), #PB_List_After, *insertPos)
               llObjects()\code = #ljPSTORE : llObjects()\i = ptrIncDecSlot : llObjects()\j = 1
            EndIf
         EndIf
      EndIf

      ; V1.034.70: INC_VAR/DEC_VAR only appear after optimizer, which runs AFTER TypeInference
      ; So A11 only handles INC_VAR_POST/PRE and DEC_VAR_POST/PRE forms (see above)
      ; This section kept for reference but optimizer forms won't be seen here
      If llObjects()\code = #ljINC_VAR And llObjects()\j = 1
         ptrIncDecSlot = llObjects()\i
         ptrIncDecVarKey = ""
         varIdx = FindVariableSlotByOffset(ptrIncDecSlot, currentFunctionName)
         If varIdx >= 0
            ptrIncDecVarKey = gVarMeta(varIdx)\name
         EndIf
         If ptrIncDecVarKey <> "" And FindMapElement(mapVariableTypes(), ptrIncDecVarKey)
            If mapVariableTypes() & #C2FLAG_POINTER
               CompilerIf #DEBUG : Debug "A11: Converting LINC_VAR to pointer ops for " + ptrIncDecVarKey : CompilerEndIf
               ; Convert INC_VAR to: PFETCH, PUSH 1, PTRADD, PSTORE (no value pushed)
               llObjects()\code = #ljPFETCH
               *insertPos = @llObjects()
               AddElement(llObjects())
               MoveElement(llObjects(), #PB_List_After, *insertPos)
               llObjects()\code = #ljPUSH_IMM : llObjects()\i = 1
               *insertPos = @llObjects()
               AddElement(llObjects())
               MoveElement(llObjects(), #PB_List_After, *insertPos)
               llObjects()\code = #ljPTRADD
               *insertPos = @llObjects()
               AddElement(llObjects())
               MoveElement(llObjects(), #PB_List_After, *insertPos)
               llObjects()\code = #ljPSTORE : llObjects()\i = ptrIncDecSlot : llObjects()\j = 1
            EndIf
         EndIf
      EndIf

      ; Check for local optimized decrement: DEC_VAR with j=1
      If llObjects()\code = #ljDEC_VAR And llObjects()\j = 1
         ptrIncDecSlot = llObjects()\i
         ptrIncDecVarKey = ""
         varIdx = FindVariableSlotByOffset(ptrIncDecSlot, currentFunctionName)
         If varIdx >= 0
            ptrIncDecVarKey = gVarMeta(varIdx)\name
         EndIf
         If ptrIncDecVarKey <> "" And FindMapElement(mapVariableTypes(), ptrIncDecVarKey)
            If mapVariableTypes() & #C2FLAG_POINTER
               CompilerIf #DEBUG : Debug "A11: Converting LDEC_VAR to pointer ops for " + ptrIncDecVarKey : CompilerEndIf
               ; Convert DEC_VAR to: PFETCH, PUSH 1, PTRSUB, PSTORE (no value pushed)
               llObjects()\code = #ljPFETCH
               *insertPos = @llObjects()
               AddElement(llObjects())
               MoveElement(llObjects(), #PB_List_After, *insertPos)
               llObjects()\code = #ljPUSH_IMM : llObjects()\i = 1
               *insertPos = @llObjects()
               AddElement(llObjects())
               MoveElement(llObjects(), #PB_List_After, *insertPos)
               llObjects()\code = #ljPTRSUB
               *insertPos = @llObjects()
               AddElement(llObjects())
               MoveElement(llObjects(), #PB_List_After, *insertPos)
               llObjects()\code = #ljPSTORE : llObjects()\i = ptrIncDecSlot : llObjects()\j = 1
            EndIf
         EndIf
      EndIf
   Next
   EndIf  ; V1.034.71: End of hasPointerVars check for A11

   ;- ========================================
   ;- PHASE A DEBUG: Dumping mapVariableTypes
   ;- ========================================
   CompilerIf #DEBUG
      Debug "PHASE A DEBUG: Dumping mapVariableTypes after Phase A"
      ForEach mapVariableTypes()
         Debug "  Variable: [" + MapKey(mapVariableTypes()) + "] = " + Str(mapVariableTypes()) + " (pointer=" + Str(Bool(mapVariableTypes() & #C2FLAG_POINTER)) + ")"
      Next
   CompilerEndIf

   ;- ========================================
   ;- PHASE B: UNIFIED TYPE APPLICATION
   ;- ========================================
   ; Single pass through all instructions applying ALL type transformations

   currentFunctionName = ""   ; V1.033.24: Track function context for Phase B

   ForEach llObjects()
      ; V1.033.24: Track current function for local variable matching
      ; V1.034.2: Fixed limit to use #C2MAXFUNCTIONS instead of 512
      If llObjects()\code = #ljfunction
         funcId = llObjects()\i
         If funcId >= 0 And funcId < #C2MAXFUNCTIONS
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
         ; V1.034.45: Handle both global (j=0) and local (j=1) variables
         Case #ljFetch
            n = llObjects()\i
            searchKey = ""
            If llObjects()\j = 1
               ; Local variable - use FindVariableSlotByOffset
               varIdx = FindVariableSlotByOffset(n, currentFunctionName)
               If varIdx >= 0
                  searchKey = gVarMeta(varIdx)\name
               EndIf
            Else
               ; Global variable - use slot directly
               If n >= 0 And n < gnLastVariable
                  searchKey = gVarMeta(n)\name
               EndIf
            EndIf
            If searchKey <> "" And FindMapElement(mapVariableTypes(), searchKey)
               If mapVariableTypes() & #C2FLAG_POINTER
                  llObjects()\code = #ljPFETCH
               EndIf
            EndIf

         ;- B4: STORE pointer conversion
         ; V1.034.45: Handle both global (j=0) and local (j=1) variables
         Case #ljStore
            n = llObjects()\i
            searchKey = ""
            If llObjects()\j = 1
               ; Local variable - use FindVariableSlotByOffset
               varIdx = FindVariableSlotByOffset(n, currentFunctionName)
               If varIdx >= 0
                  searchKey = gVarMeta(varIdx)\name
               EndIf
            Else
               ; Global variable - use slot directly
               If n >= 0 And n < gnLastVariable
                  searchKey = gVarMeta(n)\name
               EndIf
            EndIf
            If searchKey <> "" And FindMapElement(mapVariableTypes(), searchKey)
               If mapVariableTypes() & #C2FLAG_POINTER
                  llObjects()\code = #ljPSTORE
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

            ; V1.034.21: If next opcode is pointer op, convert to unified PFETCH with j=1
            If isPointer
               llObjects()\code = #ljPFETCH
               llObjects()\j = 1   ; local
            Else
               ; V1.034.1: Use O(1) lookup by offset instead of O(N) scan
               varIdx = FindVariableSlotByOffset(n, currentFunctionName)
               If varIdx >= 0
                  searchKey = gVarMeta(varIdx)\name
                  If FindMapElement(mapVariableTypes(), searchKey)
                     If mapVariableTypes() & #C2FLAG_POINTER
                        ; V1.034.21: Use unified PFETCH with j=1 for local
                        llObjects()\code = #ljPFETCH
                        llObjects()\j = 1
                     EndIf
                  EndIf
               EndIf
            EndIf

         ;- B8: LSTORE pointer conversion (uses function context)
         ; V1.034.2: Fixed - now uses correct function context for local variable lookup
         Case #ljLSTORE
            n = llObjects()\i
            ; V1.034.1: Use O(1) lookup by offset instead of O(N) scan
            varIdx = FindVariableSlotByOffset(n, currentFunctionName)
            If varIdx >= 0
               searchKey = gVarMeta(varIdx)\name
               If FindMapElement(mapVariableTypes(), searchKey)
                  If mapVariableTypes() & #C2FLAG_POINTER
                     ; V1.034.21: Use unified PSTORE with j=1 for local
                     llObjects()\code = #ljPSTORE
                     llObjects()\j = 1
                  EndIf
               EndIf
            EndIf

         ;- B9: INC_VAR pointer specialization
         ; V1.034.43: Handle both global (j=0) and local (j=1) variables
         Case #ljINC_VAR
            n = llObjects()\i
            searchKey = ""
            If llObjects()\j = 1
               ; Local variable - use FindVariableSlotByOffset
               varIdx = FindVariableSlotByOffset(n, currentFunctionName)
               If varIdx >= 0
                  searchKey = gVarMeta(varIdx)\name
               EndIf
            Else
               ; Global variable - use slot directly
               If n >= 0 And n < gnLastVariable
                  searchKey = gVarMeta(n)\name
               EndIf
            EndIf
            If searchKey <> "" And FindMapElement(mapVariableTypes(), searchKey)
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

         ;- B10: DEC_VAR pointer specialization
         ; V1.034.43: Handle both global (j=0) and local (j=1) variables
         Case #ljDEC_VAR
            n = llObjects()\i
            searchKey = ""
            If llObjects()\j = 1
               ; Local variable - use FindVariableSlotByOffset
               varIdx = FindVariableSlotByOffset(n, currentFunctionName)
               If varIdx >= 0
                  searchKey = gVarMeta(varIdx)\name
               EndIf
            Else
               ; Global variable - use slot directly
               If n >= 0 And n < gnLastVariable
                  searchKey = gVarMeta(n)\name
               EndIf
            EndIf
            If searchKey <> "" And FindMapElement(mapVariableTypes(), searchKey)
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

         ;- B11: INC_VAR_PRE/POST pointer specialization
         ; V1.034.44: Handle both global (j=0) and local (j=1) variables
         Case #ljINC_VAR_PRE, #ljINC_VAR_POST
            n = llObjects()\i
            searchKey = ""
            If llObjects()\j = 1
               ; Local variable - use FindVariableSlotByOffset
               varIdx = FindVariableSlotByOffset(n, currentFunctionName)
               If varIdx >= 0
                  searchKey = gVarMeta(varIdx)\name
               EndIf
            Else
               ; Global variable - use slot directly
               If n >= 0 And n < gnLastVariable
                  searchKey = gVarMeta(n)\name
               EndIf
            EndIf
            If searchKey <> "" And FindMapElement(mapVariableTypes(), searchKey)
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

         ;- B12: DEC_VAR_PRE/POST pointer specialization
         ; V1.034.44: Handle both global (j=0) and local (j=1) variables
         Case #ljDEC_VAR_PRE, #ljDEC_VAR_POST
            n = llObjects()\i
            searchKey = ""
            If llObjects()\j = 1
               ; Local variable - use FindVariableSlotByOffset
               varIdx = FindVariableSlotByOffset(n, currentFunctionName)
               If varIdx >= 0
                  searchKey = gVarMeta(varIdx)\name
               EndIf
            Else
               ; Global variable - use slot directly
               If n >= 0 And n < gnLastVariable
                  searchKey = gVarMeta(n)\name
               EndIf
            EndIf
            If searchKey <> "" And FindMapElement(mapVariableTypes(), searchKey)
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

         ;- B13: REMOVED V1.034.45 - Duplicate Case blocks merged into B3/B4 above
         ; B3 now handles FETCH to PFETCH for both global (j=0) and local (j=1) variables
         ; B4 now handles STORE to PSTORE for both global (j=0) and local (j=1) variables

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
                  ; V1.034.21: For local variables (j=1), 'i' is a local slot offset, NOT a gVarMeta index
                  ; Only look up gVarMeta for global variables (j=0)
                  If llObjects()\j = 0  ; Global variable
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
                  EndIf
                  ; For local variables (j=1), the type was already set in AST from paramTypes
                  ; No additional fixup needed - keep the original PRTI
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
            If llObjects()\code = #ljFetch Or llObjects()\code = #ljFETCHF Or llObjects()\code = #ljFETCHS Or llObjects()\code = #ljLFETCH Or llObjects()\code = #ljLFETCHF Or llObjects()\code = #ljLFETCHS Or llObjects()\code = #ljPFETCH
               varSlot = llObjects()\i
               *savedPos = @llObjects()
               foundGetAddr = #False
               isArrayPointer = #False
               isLocalPointer = #False
               getAddrType = #ljGETADDR

               While PreviousElement(llObjects())
                  If (llObjects()\code = #ljStore Or llObjects()\code = #ljPOP Or llObjects()\code = #ljLSTORE Or llObjects()\code = #ljPSTORE) And llObjects()\i = varSlot
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
