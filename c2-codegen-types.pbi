; c2-codegen-types.pbi
; Expression type resolution and helper functions for code generation
; V1.035.10: Initial creation - extracted from c2-codegen-v08.pbi
;
; Contains:
; - GetExprResultType() - Determine result type of expression tree
; - GetExprSlotOrTemp() - Get slot for expression (slot-only optimization)
; - ContainsFunctionCall() - Detect if expression contains function call
; - CollectVariables() - Collect all variable references in expression
;
; Dependencies: c2-inc-v19.pbi, c2-codegen-vars.pbi (for FetchVarOffset)

   ; Forward declaration for CodeGenerator (defined in c2-codegen-v08.pbi)
   ; Required because GetExprSlotOrTemp calls CodeGenerator for complex expressions
   Declare CodeGenerator(*x.stTree, *link.stTree = 0)

   ; Helper: Determine the result type of an expression
   Procedure.w          GetExprResultType( *x.stTree, depth.i = 0 )
      Protected         n
      Protected         funcId
      Protected         leftType.w, rightType.w
      Protected         pointerBaseType.w
      Protected         *funcNode.stTree

      ; Prevent infinite recursion / stack overflow
      If depth > 100
         ProcedureReturn #C2FLAG_INT
      EndIf

      ; Check if pointer is valid
      If Not *x
         ProcedureReturn #C2FLAG_INT
      EndIf

      ; Additional safety: check if pointer looks obviously invalid
      ; (very small addresses are typically invalid)
      If *x < 4096  ; First page is typically unmapped
         ProcedureReturn #C2FLAG_INT
      EndIf

      ; V1.030.51: Debug slot 176 structType on EVERY GetExprResultType call
      Static gert176LastStructType.s = ""
      If gnLastVariable > 176 And gVarMeta(176)\structType <> gert176LastStructType
         Debug "V1.030.51: GetExprResultType ENTRY slot176 CHANGED! was '" + gert176LastStructType + "' now '" + gVarMeta(176)\structType + "' node=" + *x\nodeType + " value='" + *x\value + "'"
         gert176LastStructType = gVarMeta(176)\structType
      EndIf

      Select *x\NodeType
         ; UNUSED/0 will fall through to default case
         Case #ljUNUSED
            ProcedureReturn #C2FLAG_INT
         Case #ljSTRING
            ProcedureReturn #C2FLAG_STR

         Case #ljFLOAT
            ProcedureReturn #C2FLAG_FLOAT

         Case #ljINT
            ProcedureReturn #C2FLAG_INT

         Case #ljIDENT
            ; V1.023.35: Handle struct field access (e.g., "v1\x")
            ; Need to look up field type from struct definition
            Protected structFieldPos.i = FindString(*x\value, "\")
            If structFieldPos > 0
               Protected structVarName.s = Left(*x\value, structFieldPos - 1)
               Protected fieldName.s = Mid(*x\value, structFieldPos + 1)
               Protected structSlot.i = -1
               Protected structTypeName.s = ""

               ; Find the struct variable (try mangled name first for locals)
               If gCurrentFunctionName <> ""
                  Protected mangledStructName.s = gCurrentFunctionName + "_" + structVarName
                  For n = 0 To gnLastVariable - 1
                     If LCase(gVarMeta(n)\name) = LCase(mangledStructName) And (gVarMeta(n)\flags & #C2FLAG_STRUCT)
                        structSlot = n
                        structTypeName = gVarMeta(n)\structType
                        Break
                     EndIf
                  Next
               EndIf

               ; V1.030.42: Check for struct variable by structType (non-mangled name)
               ; Don't require paramOffset >= 0 - just check structType is set
               If structSlot < 0
                  For n = 0 To gnLastVariable - 1
                     If LCase(Trim(gVarMeta(n)\name)) = LCase(structVarName) And gVarMeta(n)\structType <> ""
                        structSlot = n
                        structTypeName = gVarMeta(n)\structType
                        Break
                     EndIf
                  Next
               EndIf

               ; Try global struct if not found as local or param
               If structSlot < 0
                  For n = 0 To gnLastVariable - 1
                     If LCase(gVarMeta(n)\name) = LCase(structVarName) And (gVarMeta(n)\flags & #C2FLAG_STRUCT)
                        structSlot = n
                        structTypeName = gVarMeta(n)\structType
                        Break
                     EndIf
                  Next
               EndIf

               ; V1.030.58: Look up field type from struct definition - handle nested field chains
               ; fieldName may be "bottomRight\x" for nested access, need to walk the chain
               If structTypeName <> "" And FindMapElement(mapStructDefs(), structTypeName)
                  Protected bsCurrentType.s = structTypeName
                  Protected bsFieldParts.i = CountString(fieldName, "\") + 1
                  Protected bsFieldIdx.i
                  Protected bsFinalType.w = #C2FLAG_INT  ; Default
                  Protected bsFound.i = #False

                  For bsFieldIdx = 1 To bsFieldParts
                     Protected bsCurrentField.s = StringField(fieldName, bsFieldIdx, "\")
                     If FindMapElement(mapStructDefs(), bsCurrentType)
                        ForEach mapStructDefs()\fields()
                           If LCase(mapStructDefs()\fields()\name) = LCase(bsCurrentField)
                              bsFinalType = mapStructDefs()\fields()\fieldType
                              bsFound = #True
                              ; Check if this field is a nested struct - continue walking
                              If mapStructDefs()\fields()\structType <> ""
                                 bsCurrentType = mapStructDefs()\fields()\structType
                              EndIf
                              Break
                           EndIf
                        Next
                     EndIf
                  Next
                  If bsFound
                     ProcedureReturn bsFinalType
                  EndIf
               EndIf
            EndIf

            ; V1.029.28: Handle DOT notation struct field names (e.g., "local.x" or "r.bottomRight.x")
            Protected dotPos.i = FindString(*x\value, ".")
            If dotPos > 0 And dotPos < Len(*x\value)
               Protected dotStructName.s = Trim(Left(*x\value, dotPos - 1))
               Protected dotFieldChain.s = Trim(Mid(*x\value, dotPos + 1))
               Protected dotStructSlot.i = -1
               Protected dotStructTypeName.s = ""

               Debug "V1.030.41: GetExprResultType DOT '" + *x\value + "' gCurrentFunctionName='" + gCurrentFunctionName + "'"

               ; Look for mangled local struct first
               If gCurrentFunctionName <> ""
                  Protected dotMangledName.s = gCurrentFunctionName + "_" + dotStructName
                  For n = 0 To gnLastVariable - 1
                     If LCase(Trim(gVarMeta(n)\name)) = LCase(dotMangledName) And (gVarMeta(n)\flags & #C2FLAG_STRUCT)
                        dotStructSlot = n
                        dotStructTypeName = gVarMeta(n)\structType
                        Debug "V1.030.41: GetExprResultType MANGLED FOUND slot=" + Str(n) + " structType='" + dotStructTypeName + "'"
                        Break
                     EndIf
                  Next
               EndIf

               ; Check for struct variable by structType (non-mangled name)
               ; V1.030.43: Dump all variables to understand what's stored
               If dotStructSlot < 0
                  Debug "V1.030.43: SEARCHING for struct '" + dotStructName + "' in " + Str(gnLastVariable) + " variables:"
                  For n = 0 To gnLastVariable - 1
                     If gVarMeta(n)\structType <> "" Or (gVarMeta(n)\flags & #C2FLAG_STRUCT)
                        Debug "  [" + Str(n) + "] name='" + gVarMeta(n)\name + "' structType='" + gVarMeta(n)\structType + "' paramOffset=" + Str(gVarMeta(n)\paramOffset)
                     EndIf
                     If LCase(Trim(gVarMeta(n)\name)) = LCase(dotStructName) And gVarMeta(n)\structType <> ""
                        dotStructSlot = n
                        dotStructTypeName = gVarMeta(n)\structType
                        Debug "V1.030.43: GetExprResultType STRUCT FOUND slot=" + Str(n) + " structType='" + dotStructTypeName + "'"
                        Break
                     EndIf
                  Next
               EndIf

               ; V1.030.44: Fallback - search for any mangled name ending with _dotStructName
               ; This handles case when gCurrentFunctionName is empty but param is mangled
               If dotStructSlot < 0
                  Protected dotSuffix.s = "_" + LCase(dotStructName)
                  Debug "V1.030.44: SUFFIX SEARCH for '" + dotStructName + "' suffix='" + dotSuffix + "' len=" + Str(Len(dotSuffix))
                  For n = 0 To gnLastVariable - 1
                     ; Debug all struct vars during suffix search
                     If gVarMeta(n)\structType <> "" Or (gVarMeta(n)\flags & #C2FLAG_STRUCT)
                        Protected suffixMatch.s = Right(LCase(gVarMeta(n)\name), Len(dotSuffix))
                        Debug "  [" + Str(n) + "] '" + gVarMeta(n)\name + "' Right='" + suffixMatch + "' structType='" + gVarMeta(n)\structType + "'"
                     EndIf
                     If Right(LCase(gVarMeta(n)\name), Len(dotSuffix)) = dotSuffix And gVarMeta(n)\structType <> ""
                        dotStructSlot = n
                        dotStructTypeName = gVarMeta(n)\structType
                        Debug "V1.030.44: SUFFIX MATCH FOUND slot=" + Str(n) + " name='" + gVarMeta(n)\name + "' structType='" + dotStructTypeName + "'"
                        Break
                     EndIf
                  Next
               EndIf

               If dotStructSlot < 0
                  Debug "V1.030.44: GetExprResultType struct NOT FOUND for '" + dotStructName + "'"
               EndIf

               ; Try global struct if not found as local or param
               If dotStructSlot < 0
                  For n = 0 To gnLastVariable - 1
                     If LCase(Trim(gVarMeta(n)\name)) = LCase(dotStructName) And (gVarMeta(n)\flags & #C2FLAG_STRUCT)
                        dotStructSlot = n
                        dotStructTypeName = gVarMeta(n)\structType
                        Debug "V1.030.44: GLOBAL STRUCT FOUND slot=" + Str(n) + " name='" + gVarMeta(n)\name + "'"
                        Break
                     EndIf
                  Next
               EndIf

               ; Resolve field chain to get final field type
               If dotStructTypeName <> "" And FindMapElement(mapStructDefs(), dotStructTypeName)
                  Protected dotCurrentType.s = dotStructTypeName
                  Protected dotFieldParts.i = CountString(dotFieldChain, ".") + 1
                  Protected dotFieldIdx.i
                  Protected dotFinalType.w = #C2FLAG_INT  ; Default

                  For dotFieldIdx = 1 To dotFieldParts
                     Protected dotCurrentField.s = StringField(dotFieldChain, dotFieldIdx, ".")
                     If FindMapElement(mapStructDefs(), dotCurrentType)
                        ForEach mapStructDefs()\fields()
                           If LCase(mapStructDefs()\fields()\name) = LCase(dotCurrentField)
                              dotFinalType = mapStructDefs()\fields()\fieldType
                              Debug "V1.030.41: GetExprResultType field '" + dotCurrentField + "' type=" + Str(dotFinalType) + " (FLOAT=" + Str(#C2FLAG_FLOAT) + ")"
                              ; Check if this field is a nested struct
                              If mapStructDefs()\fields()\structType <> ""
                                 dotCurrentType = mapStructDefs()\fields()\structType
                              EndIf
                              Break
                           EndIf
                        Next
                     EndIf
                  Next
                  Debug "V1.030.41: GetExprResultType RETURNING type=" + Str(dotFinalType) + " for '" + *x\value + "'"
                  ProcedureReturn dotFinalType
               EndIf
            EndIf

            ; Check variable type - search existing variables
            ; Apply name mangling for local variables (same logic as FetchVarOffset)
            Protected searchName.s = *x\value
            If gCurrentFunctionName <> "" And Left(*x\value, 1) <> "$"
               ; Try mangled name first (local variable)
               searchName = gCurrentFunctionName + "_" + *x\value
            EndIf

            ; V1.034.66: Use case-insensitive comparison (same as FetchVarOffset)
            For n = 0 To gnLastVariable - 1
               If LCase(gVarMeta(n)\name) = LCase(searchName)
                  ; Found the variable - return its type flags
                  ; V1.034.65: Include POINTER flag for pointer arithmetic detection
                  ProcedureReturn gVarMeta(n)\flags & (#C2FLAG_TYPE | #C2FLAG_POINTER)
               EndIf
            Next

            ; If mangled name not found and we tried mangling, try global name
            If searchName <> *x\value
               For n = 0 To gnLastVariable - 1
                  ; V1.035.18: Skip constants - string "X" should not match variable "x"
                  If gVarMeta(n)\flags & #C2FLAG_CONST
                     Continue
                  EndIf
                  If LCase(gVarMeta(n)\name) = LCase(*x\value)
                     ; Found the global variable - return its type flags
                     ; V1.034.65: Include POINTER flag for pointer arithmetic detection
                     ProcedureReturn gVarMeta(n)\flags & (#C2FLAG_TYPE | #C2FLAG_POINTER)
                  EndIf
               Next
            EndIf

            ; Variable not found in gVarMeta - might be a parameter during parsing
            ; Check current function's parameter types in mapModules
            If gCurrentFunctionName <> ""
               ForEach mapModules()
                  If MapKey(mapModules()) = gCurrentFunctionName
                     ; Parse the parameter string to find this parameter's type
                     Protected paramStr.s = mapModules()\params
                     Protected closeParenPos.i = FindString(paramStr, ")", 1)
                     If closeParenPos > 0
                        paramStr = Mid(paramStr, 2, closeParenPos - 2)
                     Else
                        paramStr = Mid(paramStr, 2)
                     EndIf
                     paramStr = Trim(paramStr)

                     If paramStr <> ""
                        Protected paramIdx.i
                        For paramIdx = 1 To CountString(paramStr, ",") + 1
                           Protected param.s = Trim(StringField(paramStr, paramIdx, ","))
                           ; Extract parameter name (before type suffix)
                           Protected paramName.s = param
                           If FindString(param, ".f", 1, #PB_String_NoCase)
                              paramName = Left(param, FindString(param, ".f", 1, #PB_String_NoCase) - 1)
                           ElseIf FindString(param, ".d", 1, #PB_String_NoCase)
                              paramName = Left(param, FindString(param, ".d", 1, #PB_String_NoCase) - 1)
                           ElseIf FindString(param, ".s", 1, #PB_String_NoCase)
                              paramName = Left(param, FindString(param, ".s", 1, #PB_String_NoCase) - 1)
                           EndIf

                           If LCase(paramName) = LCase(*x\value)
                              ; Found the parameter - return its type from paramTypes list
                              If SelectElement(mapModules()\paramTypes(), paramIdx - 1)
                                 ProcedureReturn mapModules()\paramTypes()
                              EndIf
                           EndIf
                        Next
                     EndIf
                     Break
                  EndIf
               Next
            EndIf

            ; Variable not found in gVarMeta or parameters
            ; Check mapVariableTypes (populated during parsing from typeHints)
            If FindMapElement(mapVariableTypes(), searchName)
               ProcedureReturn mapVariableTypes()
            EndIf

            ; If mangled name not found, try global name
            If searchName <> *x\value And FindMapElement(mapVariableTypes(), *x\value)
               ProcedureReturn mapVariableTypes()
            EndIf

            ; Variable not found anywhere - default to INT
            ProcedureReturn #C2FLAG_INT

         Case #ljAdd, #ljSUBTRACT, #ljMULTIPLY, #ljDIVIDE
            ; Arithmetic operations: result is string if any operand is string,
            ; else float if any operand is float, else int
            ; V1.20.28: Preserve POINTER flag for pointer arithmetic (ptr+int, ptr-int)
            leftType = #C2FLAG_INT
            rightType = #C2FLAG_INT

            If *x\left
               leftType = GetExprResultType(*x\left, depth + 1)
            EndIf

            If *x\right
               rightType = GetExprResultType(*x\right, depth + 1)
            EndIf

            ; V1.20.28: For ADD/SUBTRACT, preserve POINTER flag (pointer arithmetic)
            ; ptr + int, ptr - int, int + ptr all preserve pointer type
            If *x\NodeType = #ljAdd Or *x\NodeType = #ljSUBTRACT
               If leftType & #C2FLAG_POINTER Or rightType & #C2FLAG_POINTER
                  ; One operand is a pointer - result is also a pointer
                  ; Preserve the base type (INT/FLOAT/STR) from the pointer operand
                  pointerBaseType = #C2FLAG_INT
                  If leftType & #C2FLAG_POINTER
                     pointerBaseType = leftType & #C2FLAG_TYPE
                  ElseIf rightType & #C2FLAG_POINTER
                     pointerBaseType = rightType & #C2FLAG_TYPE
                  EndIf
                  ProcedureReturn #C2FLAG_POINTER | pointerBaseType
               EndIf
            EndIf

            If leftType & #C2FLAG_STR Or rightType & #C2FLAG_STR
               ProcedureReturn #C2FLAG_STR
            ElseIf leftType & #C2FLAG_FLOAT Or rightType & #C2FLAG_FLOAT
               ProcedureReturn #C2FLAG_FLOAT
            Else
               ProcedureReturn #C2FLAG_INT
            EndIf

         Case #ljNEGATE
            ; Negation preserves type
            If *x\left
               ProcedureReturn GetExprResultType(*x\left, depth + 1)
            EndIf
            ProcedureReturn #C2FLAG_INT

         Case #ljPRE_INC, #ljPRE_DEC, #ljPOST_INC, #ljPOST_DEC
            ; Increment/decrement operators preserve the variable's type
            If *x\left
               ProcedureReturn GetExprResultType(*x\left, depth + 1)
            EndIf
            ProcedureReturn #C2FLAG_INT

         ; Type conversion operators - return the target type
         Case #ljITOF, #ljSTOF
            ProcedureReturn #C2FLAG_FLOAT
         Case #ljFTOI, #ljSTOI
            ProcedureReturn #C2FLAG_INT
         Case #ljITOS, #ljFTOS
            ProcedureReturn #C2FLAG_STR

         ; Cast operators (V1.18.63) - return the target type
         Case #ljCAST_INT
            ProcedureReturn #C2FLAG_INT
         Case #ljCAST_FLOAT
            ProcedureReturn #C2FLAG_FLOAT
         Case #ljCAST_STRING
            ProcedureReturn #C2FLAG_STR
         Case #ljCAST_VOID  ; V1.033.11: Void cast returns void type
            ProcedureReturn #C2FLAG_VOID
         Case #ljCAST_PTR  ; V1.036.2: Pointer cast returns pointer type
            ProcedureReturn #C2FLAG_INT | #C2FLAG_POINTER

         ; Pointer operations (V1.19.3) - return type based on pointer's declared type
         Case #ljPTRFETCH
            ; V1.021.12: Determine result type from the pointer variable's declared type
            ; *x\left is the pointer variable being dereferenced (e.g., 'ptr' in '*ptr')
            If *x\left And *x\left\NodeType = #ljIDENT
               ; Look up the pointer variable's type in gVarMeta
               Protected ptrName.s = *x\left\value
               Protected mangledPtrName.s = ptrName
               If gCurrentFunctionName <> "" And Left(ptrName, 1) <> "$"
                  mangledPtrName = gCurrentFunctionName + "_" + ptrName
               EndIf

               For n = 0 To gnLastVariable - 1
                  If gVarMeta(n)\name = mangledPtrName Or gVarMeta(n)\name = ptrName
                     ; Found the variable - return its declared type (INT/FLOAT/STR)
                     ; The .i/.f/.s suffix indicates what type the pointer points to
                     ProcedureReturn gVarMeta(n)\flags & #C2FLAG_TYPE
                  EndIf
               Next
            EndIf
            ; Default to INT for unresolved cases
            ProcedureReturn #C2FLAG_INT

         ; V1.20.21: Pointer field access - return explicit types
         Case #ljPTRFIELD_I
            ProcedureReturn #C2FLAG_INT
         Case #ljPTRFIELD_F
            ProcedureReturn #C2FLAG_FLOAT
         Case #ljPTRFIELD_S
            ProcedureReturn #C2FLAG_STR

         ; V1.022.44: Struct array field access result types
         Case #nd_StructArrayField_I
            ProcedureReturn #C2FLAG_INT
         Case #nd_StructArrayField_F
            ProcedureReturn #C2FLAG_FLOAT
         Case #nd_StructArrayField_S
            ProcedureReturn #C2FLAG_STR

         Case #ljTERNARY
            ; Ternary operator: result type is determined by true/false branches
            ; *x\right is a COLON node with true_expr in left, false_expr in right
            If *x\right And *x\right\left And *x\right\right
               leftType = GetExprResultType(*x\right\left, depth + 1)    ; true branch
               rightType = GetExprResultType(*x\right\right, depth + 1)  ; false branch

               ; Result type is string if either branch is string
               If leftType & #C2FLAG_STR Or rightType & #C2FLAG_STR
                  ProcedureReturn #C2FLAG_STR
               ; Result type is float if either branch is float
               ElseIf leftType & #C2FLAG_FLOAT Or rightType & #C2FLAG_FLOAT
                  ProcedureReturn #C2FLAG_FLOAT
               Else
                  ProcedureReturn #C2FLAG_INT
               EndIf
            EndIf
            ; Default to INT if structure is invalid
            ProcedureReturn #C2FLAG_INT

         Case #ljCall, #ljSEQ
            ; Function call or SEQ node containing a call - look up function's return type

            ; For SEQ nodes, check if right child is a Call
            If *x\NodeType = #ljSEQ And *x\right And *x\right\NodeType = #ljCall
               *funcNode = *x\right
            ElseIf *x\NodeType = #ljCall
               *funcNode = *x
            Else
               ; SEQ without call - try to infer from left or right
               If *x\left
                  leftType = GetExprResultType(*x\left, depth + 1)
                  If leftType <> #C2FLAG_INT
                     ProcedureReturn leftType
                  EndIf
               EndIf
               If *x\right
                  ProcedureReturn GetExprResultType(*x\right, depth + 1)
               EndIf
               ProcedureReturn #C2FLAG_INT
            EndIf

            ; Look up the function's declared return type
            If *funcNode
               funcId = Val(*funcNode\value)

               ; Check if it's a built-in function
               ; V1.023.30: Check for type conversion opcodes first (str(), strf())
               ; V1.033.52: FIX - Use mapBuiltins lookup instead of >= comparison
               ; to avoid collision with user function IDs that exceed #ljBUILTIN_RANDOM
               If funcId = #ljITOS Or funcId = #ljFTOS
                  ProcedureReturn #C2FLAG_STR
               Else
                  ; First try mapBuiltins (built-in functions)
                  ForEach mapBuiltins()
                     If mapBuiltins()\opcode = funcId
                        ProcedureReturn mapBuiltins()\returnType
                     EndIf
                  Next
                  ; Then try mapModules (user-defined functions)
                  ForEach mapModules()
                     If mapModules()\function = funcId
                        ProcedureReturn mapModules()\returnType
                     EndIf
                  Next
               EndIf
            EndIf

            ProcedureReturn #C2FLAG_INT

         Case #ljLeftBracket
            ; Array element access - return the array's element type
            If *x\left And *x\left\NodeType = #ljIDENT
               ; Use FetchVarOffset to find the array variable (handles name mangling)
               n = FetchVarOffset(*x\left\value, 0, 0)
               If n >= 0
                  ; Found the array - return its element type
                  ProcedureReturn gVarMeta(n)\flags & #C2FLAG_TYPE
               EndIf
            EndIf
            ; Array not found - default to INT
            ProcedureReturn #C2FLAG_INT

         ; V1.037.2: Multi-dimensional array element access - return the array's element type
         Case #nd_MultiDimIndex
            ; *x\left is the array variable node (#ljIDENT)
            If *x\left And *x\left\NodeType = #ljIDENT
               ; Use FetchVarOffset to find the array variable (handles name mangling)
               n = FetchVarOffset(*x\left\value, 0, 0)
               If n >= 0
                  ; Found the array - return its element type
                  ProcedureReturn gVarMeta(n)\flags & #C2FLAG_TYPE
               EndIf
            EndIf
            ; Array not found - default to INT
            ProcedureReturn #C2FLAG_INT

         ; V1.20.25: Address-of operations return pointer types
         Case #ljGETADDR
            ; &variable or &arr[index] returns integer pointer
            ProcedureReturn #C2FLAG_POINTER | #C2FLAG_INT
         Case #ljGETADDRF
            ; &variable.f returns float pointer
            ProcedureReturn #C2FLAG_POINTER | #C2FLAG_FLOAT
         Case #ljGETADDRS
            ; &variable.s returns string pointer
            ProcedureReturn #C2FLAG_POINTER | #C2FLAG_STR
         Case #ljGETARRAYADDR
            ; &arr[index] returns integer array element pointer
            ProcedureReturn #C2FLAG_POINTER | #C2FLAG_INT
         Case #ljGETARRAYADDRF
            ; &arr.f[index] returns float array element pointer
            ProcedureReturn #C2FLAG_POINTER | #C2FLAG_FLOAT
         Case #ljGETARRAYADDRS
            ; &arr.s[index] returns string array element pointer
            ProcedureReturn #C2FLAG_POINTER | #C2FLAG_STR

         ; V1.023.21: Struct address returns pointer type
         Case #ljGETSTRUCTADDR
            ; &structVar returns struct pointer
            ProcedureReturn #C2FLAG_POINTER | #C2FLAG_INT

         Default
            ; Comparisons and other operations return INT
            ProcedureReturn #C2FLAG_INT
      EndSelect
   EndProcedure

   ; V1.022.20: Helper to get slot for expression (slot-only optimization)
   ; V1.022.31: Rewritten for recursion safety - no global temp slots
   ; For simple GLOBAL idents/constants: returns slot directly (no code emitted)
   ; For LOCAL variables: emits LFETCH (push to stack), returns -1
   ; For complex expressions: emits code (result on stack), returns -1
   ; Return value -1 signals array opcodes to use _STACK variants
   Procedure.i          GetExprSlotOrTemp(*expr.stTree)
      ; V1.022.31: Returns slot index for simple globals/constants
      ; V1.022.50: Always returns valid slot - never -1. Complex/local values stored in temp slot.
      ; V1.022.86: When inside function, use LOCAL temps for recursion safety
      ;            Return value encoding:
      ;            - positive or 0 = global slot → use _OPT opcodes
      ;            - -1 = reserved for STACK (not used by this function anymore)
      ;            - < -1 = local offset encoded as -(localOffset + 2) → use _LOPT opcodes
      ;            So -2 means LOCAL[0], -3 means LOCAL[1], etc.

      If Not *expr
         ProcedureReturn 0  ; Return slot 0 (discard) for null expressions
      EndIf

      Select *expr\NodeType
         Case #ljIDENT
            ; Simple variable - check if local or global
            Protected identSlot.i = FetchVarOffset(*expr\value)

            ; V1.022.50: Local variables - copy to temp slot
            If gVarMeta(identSlot)\paramOffset >= 0
               ; Local variable - emit LFETCH to push value, then LSTORE to local temp
               Protected localExprType.w = gVarMeta(identSlot)\flags

               ; V1.022.86: When inside a function, allocate LOCAL temp for recursion safety
               If gCodeGenFunction > 0
                  ; Allocate local temp offset
                  Protected localTempOffset.i = gCodeGenLocalIndex
                  gCodeGenLocalIndex + 1
                  ; Update nLocals in mapModules
                  ForEach mapModules()
                     If mapModules()\function = gCodeGenFunction
                        mapModules()\nLocals = gCodeGenLocalIndex - mapModules()\nParams
                        Break
                     EndIf
                  Next

                  ; V1.034.16: Emit FETCH with j=1 to push local variable value to stack
                  AddElement(llObjects())
                  If localExprType & #C2FLAG_FLOAT
                     llObjects()\code = #ljFETCHF
                  ElseIf localExprType & #C2FLAG_STR
                     llObjects()\code = #ljFETCHS
                  Else
                     llObjects()\code = #ljFetch
                  EndIf
                  llObjects()\j = 1   ; Mark as local
                  llObjects()\i = gVarMeta(identSlot)\paramOffset

                  ; V1.034.16: Emit STORE with j=1 to store to local temp
                  AddElement(llObjects())
                  If localExprType & #C2FLAG_FLOAT
                     llObjects()\code = #ljSTOREF
                  ElseIf localExprType & #C2FLAG_STR
                     llObjects()\code = #ljSTORES
                  Else
                     llObjects()\code = #ljStore
                  EndIf
                  llObjects()\j = 1   ; Mark as local
                  llObjects()\i = localTempOffset

                  ; Return negative value to signal local offset (< -1 to avoid conflict with STACK=-1)
                  ProcedureReturn -(localTempOffset + 2)
               EndIf

               ; V1.022.72: Global scope - use global temp (original behavior)
               Protected tempSlotType.i, tempPopOpcode.i
               If localExprType & #C2FLAG_FLOAT
                  tempSlotType = #ljFLOAT
                  tempPopOpcode = #ljPOPF
               ElseIf localExprType & #C2FLAG_STR
                  tempSlotType = #ljSTRING
                  tempPopOpcode = #ljPOPS
               Else
                  tempSlotType = #ljINT
                  tempPopOpcode = #ljPop
               EndIf
               Protected tempSlot.i = FetchVarOffset("$_idx_temp_" + Str(gnLastVariable), 0, tempSlotType)

               ; V1.034.16: Emit FETCH with j=1 for local variable
               AddElement(llObjects())
               If localExprType & #C2FLAG_FLOAT
                  llObjects()\code = #ljFETCHF
               ElseIf localExprType & #C2FLAG_STR
                  llObjects()\code = #ljFETCHS
               Else
                  llObjects()\code = #ljFetch
               EndIf
               llObjects()\j = 1   ; Mark as local
               llObjects()\i = gVarMeta(identSlot)\paramOffset

               ; V1.022.72: Pop to temp slot with type-specific opcode
               AddElement(llObjects())
               llObjects()\code = tempPopOpcode
               llObjects()\i = tempSlot

               ProcedureReturn tempSlot
            EndIf

            ; Global variable - return slot directly
            ProcedureReturn identSlot

         Case #ljINT
            ; Integer constant - get slot directly
            ProcedureReturn FetchVarOffset(*expr\value, 0, #ljINT)

         Case #ljFLOAT
            ; Float constant - get slot directly
            ProcedureReturn FetchVarOffset(*expr\value, 0, #ljFLOAT)

         Case #ljSTRING
            ; String constant - get slot directly
            ProcedureReturn FetchVarOffset(*expr\value, 0, #ljSTRING)

         ; V1.022.76: Removed #ljLeftBracket case - was causing array index corruption
         ; Float array POPF issue needs to be fixed elsewhere (in #ljIDENT case)

         Default
            ; V1.022.50: Complex expression - emit code to stack, then pop/store to temp
            ; V1.022.86: When inside function, use LOCAL temp for recursion safety
            ; V1.022.101: Detect expression result type to use correct store opcode
            Protected exprResultType.w = GetExprResultType(*expr)

            If gCodeGenFunction > 0
               ; Allocate local temp offset
               Protected complexLocalOffset.i = gCodeGenLocalIndex
               gCodeGenLocalIndex + 1
               ; Update nLocals in mapModules
               ForEach mapModules()
                  If mapModules()\function = gCodeGenFunction
                     mapModules()\nLocals = gCodeGenLocalIndex - mapModules()\nParams
                     Break
                  EndIf
               Next

               CodeGenerator(*expr)
               ; V1.034.16: Store result with type-correct opcode + j=1 for local
               AddElement(llObjects())
               If exprResultType & #C2FLAG_FLOAT
                  llObjects()\code = #ljSTOREF
                  CompilerIf #DEBUG
                     Debug "V1.034.16: Complex expr to LOCAL[" + Str(complexLocalOffset) + "] using STOREF j=1 (float)"
                  CompilerEndIf
               ElseIf exprResultType & #C2FLAG_STR
                  llObjects()\code = #ljSTORES
                  CompilerIf #DEBUG
                     Debug "V1.034.16: Complex expr to LOCAL[" + Str(complexLocalOffset) + "] using STORES j=1 (string)"
                  CompilerEndIf
               Else
                  llObjects()\code = #ljStore
               EndIf
               llObjects()\j = 1   ; Mark as local
               llObjects()\i = complexLocalOffset

               ; Return negative value to signal local offset (< -1 to avoid conflict with STACK=-1)
               ProcedureReturn -(complexLocalOffset + 2)
            EndIf

            ; Global scope - use global temp (original behavior)
            ; V1.022.101: Use appropriate type for temp slot and pop opcode
            Protected complexTempType.i, complexPopOpcode.i
            If exprResultType & #C2FLAG_FLOAT
               complexTempType = #ljFLOAT
               complexPopOpcode = #ljPOPF
            ElseIf exprResultType & #C2FLAG_STR
               complexTempType = #ljSTRING
               complexPopOpcode = #ljPOPS
            Else
               complexTempType = #ljINT
               complexPopOpcode = #ljPop
            EndIf
            Protected complexTempSlot.i = FetchVarOffset("$_idx_temp_" + Str(gnLastVariable), 0, complexTempType)
            CodeGenerator(*expr)
            ; Pop result to temp slot with type-correct opcode
            AddElement(llObjects())
            llObjects()\code = complexPopOpcode
            llObjects()\i = complexTempSlot
            ProcedureReturn complexTempSlot
      EndSelect
   EndProcedure

   ; Helper function to detect if an expression tree contains a function call
   Procedure.b          ContainsFunctionCall(*node.stTree)
      If Not *node
         ProcedureReturn #False
      EndIf

      If *node\NodeType = #ljCall
         ProcedureReturn #True
      EndIf

      ; Recursively check left and right subtrees
      If ContainsFunctionCall(*node\left)
         ProcedureReturn #True
      EndIf

      If ContainsFunctionCall(*node\right)
         ProcedureReturn #True
      EndIf

      ProcedureReturn #False
   EndProcedure

   ; Helper function to collect all variable references in an expression tree
   Procedure            CollectVariables(*node.stTree, List vars.s())
      If Not *node
         ProcedureReturn
      EndIf

      If *node\NodeType = #ljIDENT
         ; Add variable to list if not already there
         Protected found.b = #False
         ForEach vars()
            If vars() = *node\value
               found = #True
               Break
            EndIf
         Next
         If Not found
            AddElement(vars())
            vars() = *node\value
         EndIf
      EndIf

      CollectVariables(*node\left, vars())
      CollectVariables(*node\right, vars())
   EndProcedure
