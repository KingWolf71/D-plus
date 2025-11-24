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
; Code Generator
;- Procedures for generating VM bytecode from AST

   Procedure            hole()
      gHoles + 1

      AddElement( llHoles() )
      llHoles()\location   = llObjects()
      llHoles()\mode       = #C2HOLE_START
      llHoles()\id         = gHoles
      
      ProcedureReturn gHoles
   EndProcedure
   
   Procedure            fix( id, dst = -1 )

      AddElement( llHoles() )

      If dst = -1
         llHoles()\mode = #C2HOLE_DEFAULT
         llHoles()\id = id
         llHoles()\location = llObjects()
      Else                                   ; Used by blind JMP
         llHoles()\mode = #C2HOLE_BLIND
         LastElement( llObjects() )              ; Move to last element (JMP instruction)
         llHoles()\location = llObjects()        ; Save pointer to current element
         llHoles()\src = dst
      EndIf

   EndProcedure
    
   ; Helper: Check if variable should use local opcodes (LocalVars array)
   ; Returns true for both parameters and local variables in functions
   Procedure.b          IsLocalVar(varIndex.i)
      If varIndex < 0 Or varIndex >= gnLastVariable
         ProcedureReturn #False
      EndIf

      ; Parameters use LocalVars array
      If gVarMeta(varIndex)\flags & #C2FLAG_PARAM
         ProcedureReturn #True
      EndIf

      ; Non-parameter locals: check if name is mangled with function name OR synthetic ($temp)
      If gCurrentFunctionName <> ""
         If LCase(Left(gVarMeta(varIndex)\name, Len(gCurrentFunctionName) + 1)) = LCase(gCurrentFunctionName + "_")
            ProcedureReturn #True
         EndIf
         ; Synthetic temporaries (starting with $) are also local when inside a function
         If Left(gVarMeta(varIndex)\name, 1) = "$"
            ProcedureReturn #True
         EndIf
      EndIf

      ProcedureReturn #False
   EndProcedure

   Procedure            EmitInt( op.i, nVar.i = -1 )
      Protected         sourceFlags.w, destFlags.w
      Protected         isSourceLocal.b, isDestLocal.b
      Protected         sourceFlags2.w, destFlags2.w
      Protected         localOffset.i, localOffset2.i, localOffset3.i, localOffset4.i
      Protected         savedSource.i, savedSrc2.i
      Protected         inTernary2.b
      Protected         currentCode.i

      If gEmitIntCmd = #ljpush And op = #ljStore
         ; PUSH+STORE optimization
         ; Don't optimize inside ternary expressions - both branches need stack values
         ; Check if PUSH instruction is marked as part of ternary
         Protected inTernary.b = (llObjects()\flags & #INST_FLAG_TERNARY)

         sourceFlags = gVarMeta( llObjects()\i )\flags
         destFlags = gVarMeta( nVar )\flags
         isSourceLocal = IsLocalVar(llObjects()\i)
         isDestLocal = IsLocalVar(nVar)

         ; Only optimize to MOV if BOTH are not local (globals can use MOV)
         ; Or if destination is local (use LMOV)
         If Not inTernary And Not ((sourceFlags & #C2FLAG_PARAM) Or (destFlags & #C2FLAG_PARAM))
            ; Neither is parameter - can optimize to MOV
            If isDestLocal
               ; Destination is local - use LMOV
               ; For LMOV: i = paramOffset (destination), j = source varIndex
               savedSource = llObjects()\i  ; Save source BEFORE overwriting
               localOffset = gVarMeta(nVar)\paramOffset

               ; Safety check: Ensure paramOffset is valid (should be >= 0 and < 20)
               ; If paramOffset looks invalid (too large - likely a slot number), fall back to PUSH+STORE
               If localOffset < 0 Or localOffset >= 20
                  ; paramOffset not set or suspiciously large - fall back to PUSH+STORE
                  gEmitIntLastOp = AddElement( llObjects() )
                  If destFlags & #C2FLAG_STR
                     llObjects()\code = #ljSTORES
                  ElseIf destFlags & #C2FLAG_FLOAT
                     llObjects()\code = #ljSTOREF
                  Else
                     llObjects()\code = #ljSTORE
                  EndIf
                  llObjects()\i = nVar
               Else
                  If sourceFlags & #C2FLAG_STR
                     llObjects()\code = #ljLMOVS
                  ElseIf sourceFlags & #C2FLAG_FLOAT
                     llObjects()\code = #ljLMOVF
                  Else
                     llObjects()\code = #ljLMOV
                  EndIf
                  llObjects()\j = savedSource  ; j = source varIndex
                  llObjects()\i = localOffset  ; i = destination paramOffset
               EndIf
            Else
               ; Global destination - use regular MOV
               If sourceFlags & #C2FLAG_STR
                  llObjects()\code = #ljMOVS
                  gVarMeta( nVar )\flags = #C2FLAG_IDENT | #C2FLAG_STR
               ElseIf sourceFlags & #C2FLAG_FLOAT
                  llObjects()\code = #ljMOVF
                  gVarMeta( nVar )\flags = #C2FLAG_IDENT | #C2FLAG_FLOAT
               Else
                  llObjects()\code = #ljMOV
                  gVarMeta( nVar )\flags = #C2FLAG_IDENT | #C2FLAG_INT
               EndIf
               llObjects()\j = llObjects()\i
            EndIf
         Else
            ; One is a parameter - keep as PUSH+STORE but use local version if dest is local
            gEmitIntLastOp = AddElement( llObjects() )
            If isDestLocal
               localOffset3 = gVarMeta(nVar)\paramOffset

               ; Safety check: Ensure paramOffset is valid (should be >= 0 and < 20)
               If localOffset3 >= 0 And localOffset3 < 20
                  If destFlags & #C2FLAG_STR
                     llObjects()\code = #ljLSTORES
                  ElseIf destFlags & #C2FLAG_FLOAT
                     llObjects()\code = #ljLSTOREF
                  Else
                     llObjects()\code = #ljLSTORE
                  EndIf
                  ; Set the local variable index (paramOffset)
                  llObjects()\i = localOffset3
               Else
                  ; paramOffset not set - use global STORE
                  If destFlags & #C2FLAG_STR
                     llObjects()\code = #ljSTORES
                  ElseIf destFlags & #C2FLAG_FLOAT
                     llObjects()\code = #ljSTOREF
                  Else
                     llObjects()\code = #ljSTORE
                  EndIf
                  llObjects()\i = nVar
               EndIf
            Else
               llObjects()\code = op
            EndIf
         EndIf
      ElseIf gEmitIntCmd = #ljfetch And op = #ljstore
         ; FETCH+STORE optimization
         ; Don't optimize inside ternary expressions - both branches need stack values
         ; Check if FETCH instruction is marked as part of ternary
         inTernary2 = (llObjects()\flags & #INST_FLAG_TERNARY)

         sourceFlags2 = gVarMeta( llObjects()\i )\flags
         destFlags2 = gVarMeta( nVar )\flags
         isSourceLocal = IsLocalVar(llObjects()\i)
         isDestLocal = IsLocalVar(nVar)

         If Not inTernary2 And Not ((sourceFlags2 & #C2FLAG_PARAM) Or (destFlags2 & #C2FLAG_PARAM))
            ; Can optimize to MOV or LMOV
            If isDestLocal
               ; Use LMOV for local destination
               localOffset2 = gVarMeta(nVar)\paramOffset

               ; Safety check: Ensure paramOffset is valid (should be >= 0 and < 20)
               If localOffset2 < 0 Or localOffset2 >= 20
                  ; paramOffset not set - fall back to FETCH+STORE
                  gEmitIntLastOp = AddElement( llObjects() )
                  If destFlags2 & #C2FLAG_STR
                     llObjects()\code = #ljSTORES
                  ElseIf destFlags2 & #C2FLAG_FLOAT
                     llObjects()\code = #ljSTOREF
                  Else
                     llObjects()\code = #ljSTORE
                  EndIf
                  llObjects()\i = nVar
               Else
                  If sourceFlags2 & #C2FLAG_STR
                     llObjects()\code = #ljLMOVS
                  ElseIf sourceFlags2 & #C2FLAG_FLOAT
                     llObjects()\code = #ljLMOVF
                  Else
                     llObjects()\code = #ljLMOV
                  EndIf
                  savedSrc2 = llObjects()\i
                  llObjects()\i = localOffset2
                  llObjects()\j = savedSrc2
               EndIf
            Else
               ; Use regular MOV for global destination
               If sourceFlags2 & #C2FLAG_STR
                  llObjects()\code = #ljMOVS
               ElseIf sourceFlags2 & #C2FLAG_FLOAT
                  llObjects()\code = #ljMOVF
               Else
                  llObjects()\code = #ljMOV
               EndIf
               llObjects()\j = llObjects()\i
            EndIf
         Else
            ; Keep as FETCH+STORE but use local version if appropriate
            gEmitIntLastOp = AddElement( llObjects() )
            If isDestLocal
               localOffset4 = gVarMeta(nVar)\paramOffset

               ; Safety check: Ensure paramOffset is valid (should be >= 0 and < 20)
               If localOffset4 >= 0 And localOffset4 < 20
                  If destFlags2 & #C2FLAG_STR
                     llObjects()\code = #ljLSTORES
                  ElseIf destFlags2 & #C2FLAG_FLOAT
                     llObjects()\code = #ljLSTOREF
                  Else
                     llObjects()\code = #ljLSTORE
                  EndIf
                  ; Set the local variable index (paramOffset)
                  llObjects()\i = localOffset4
               Else
                  ; paramOffset not set - use global STORE
                  If destFlags2 & #C2FLAG_STR
                     llObjects()\code = #ljSTORES
                  ElseIf destFlags2 & #C2FLAG_FLOAT
                     llObjects()\code = #ljSTOREF
                  Else
                     llObjects()\code = #ljSTORE
                  EndIf
                  llObjects()\i = nVar
               EndIf
            Else
               llObjects()\code = op
            EndIf
         EndIf
      Else
         ; Standard emission - check if we should use local opcode
         gEmitIntLastOp = AddElement( llObjects() )

         If nVar >= 0 And IsLocalVar(nVar)
            ; This is a local variable - convert to local opcode and translate index
            Select op
               Case #ljFetch
                  llObjects()\code = #ljLFETCH
                  llObjects()\i = gVarMeta(nVar)\paramOffset
               Case #ljFETCHS
                  llObjects()\code = #ljLFETCHS
                  llObjects()\i = gVarMeta(nVar)\paramOffset
               Case #ljFETCHF
                  llObjects()\code = #ljLFETCHF
                  llObjects()\i = gVarMeta(nVar)\paramOffset
               Case #ljStore
                  llObjects()\code = #ljLSTORE
                  llObjects()\i = gVarMeta(nVar)\paramOffset
               Case #ljSTORES
                  llObjects()\code = #ljLSTORES
                  llObjects()\i = gVarMeta(nVar)\paramOffset
               Case #ljSTOREF
                  llObjects()\code = #ljLSTOREF
                  llObjects()\i = gVarMeta(nVar)\paramOffset
               Default
                  llObjects()\code = op
            EndSelect
         Else
            llObjects()\code = op
         EndIf
      EndIf

      ; Only set llObjects()\i for variable-related opcodes
      ; Skip this for opcodes that don't operate on variables (CALL uses funcId, not varSlot)
      ; Note: For local opcodes (LFETCH, LSTORE, etc.), \i was already set in optimization paths above
      If nVar > -1
         ; Check if this is an opcode that operates on variables
         currentCode = llObjects()\code
         Select currentCode
            ; Local opcodes - \i already set to paramOffset in optimization code above, don't touch
            Case #ljLFETCH, #ljLFETCHS, #ljLFETCHF, #ljLSTORE, #ljLSTORES, #ljLSTOREF, #ljLMOV, #ljLMOVS, #ljLMOVF
               ; Do nothing - \i already contains correct paramOffset from optimization paths

            ; Global opcodes - need to set \i to variable slot
            Case #ljFetch, #ljFETCHS, #ljFETCHF, #ljStore, #ljSTORES, #ljSTOREF,
                 #ljPush, #ljPUSHS, #ljPUSHF, #ljPOP, #ljPOPS, #ljPOPF
               llObjects()\i = nVar

            Default
               ; Non-variable opcode (CALL, JMP, etc.) - store nVar as-is
               llObjects()\i = nVar
         EndSelect
      EndIf

      ; Mark instruction if inside ternary expression
      If gInTernary
         llObjects()\flags = llObjects()\flags | #INST_FLAG_TERNARY
      EndIf

      gEmitIntCmd = llObjects()\code
   EndProcedure
   
   Procedure            FetchVarOffset(text.s, *assignmentTree.stTree = 0, syntheticType.i = 0)
      Protected         i, j
      Protected         temp.s
      Protected         inferredType.w
      Protected         savedIndex
      Protected         tokenFound.i = #False
      Protected         searchName.s
      Protected         mangledName.s
      Protected         isLocal.i

      j = -1

      ; Apply name mangling for local variables inside functions
      ; Synthetic variables (starting with $) and constants are never mangled
      If gCurrentFunctionName <> "" And Left(text, 1) <> "$" And syntheticType = 0
         ; Inside a function - first try to find as local variable (mangled)
         mangledName = gCurrentFunctionName + "_" + text
         searchName = mangledName

         ; Check if mangled (local) version exists
         For i = 0 To gnLastVariable - 1
            If gVarMeta(i)\name = searchName
               ProcedureReturn i  ; Found local variable
            EndIf
         Next

         ; Not found as local - check if global exists
         ; If global exists: use it for READ, but create local for WRITE
         ; If global doesn't exist, create as local

         If gCodeGenParamIndex < 0
            ; Not processing parameters - check if global exists
            If Not *assignmentTree
               ; Reading a variable - use global if it exists
               For i = 0 To gnLastVariable - 1
                  If gVarMeta(i)\name = text
                     ; Found as global - use it for READ
                     ProcedureReturn i
                  EndIf
               Next
            EndIf
            ; Assigning to variable (*assignmentTree <> 0) - always create local
         EndIf

         ; Global not found (or assigning) - create as local
         text = mangledName
      EndIf

      ; Check if variable already exists (with final name after mangling)
      For i = 0 To gnLastVariable - 1
         If gVarMeta(i)\name = text
            ; Variable exists - check if it's a local variable that needs an offset assigned
            If gCurrentFunctionName <> "" And gCodeGenParamIndex < 0 And gCodeGenFunction > 0
               If gVarMeta(i)\paramOffset < 0
                  ; This is a local variable without an offset - assign one
                  If LCase(Left(text, Len(gCurrentFunctionName) + 1)) = LCase(gCurrentFunctionName + "_") Or Left(text, 1) = "$"
                     gVarMeta(i)\paramOffset = gCodeGenLocalIndex
                     gCodeGenLocalIndex + 1

                     ; Update nLocals in mapModules immediately
                     ForEach mapModules()
                        If mapModules()\function = gCodeGenFunction
                           mapModules()\nLocals = gCodeGenLocalIndex - mapModules()\nParams
                           Break
                        EndIf
                     Next
                  EndIf
               EndIf
            EndIf
            ProcedureReturn i
         EndIf
      Next

      ; New variable - find token (unless it's a synthetic $ variable)
      i = -1
      savedIndex = ListIndex(TOKEN())

      ; Don't look up synthetic variables (starting with $) in token list
      If Left(text, 1) <> "$"
         ForEach TOKEN()
            If TOKEN()\value = text
               i = ListIndex( TOKEN() )
               Break
            EndIf
         Next

         If savedIndex >= 0
            SelectElement(TOKEN(), savedIndex)
         EndIf
      EndIf

      gVarMeta(gnLastVariable)\name  = text

      ; Check if this is a synthetic temporary variable (starts with $)
      If Left(text, 1) = "$"
         ; Synthetic variable - determine type from suffix or syntheticType parameter
         If syntheticType & #C2FLAG_FLOAT Or Right(text, 1) = "f"
            ;gVarFloat(gnLastVariable) = 0.0
            gVarMeta(gnLastVariable)\flags = #C2FLAG_IDENT | #C2FLAG_FLOAT
         ElseIf syntheticType & #C2FLAG_STR Or Right(text, 1) = "s"
            ;gVarString(gnLastVariable) = ""
            gVarMeta(gnLastVariable)\flags = #C2FLAG_IDENT | #C2FLAG_STR
         Else
            ;gVarInt(gnLastVariable) = 0
            gVarMeta(gnLastVariable)\flags = #C2FLAG_IDENT | #C2FLAG_INT
         EndIf
      ; Check if this is a synthetic constant (syntheticType passed in)
      ElseIf syntheticType = #ljINT
         gVarMeta(gnLastVariable)\valueInt = Val(text)
         gVarMeta(gnLastVariable)\flags = #C2FLAG_CONST | #C2FLAG_INT
      ElseIf syntheticType = #ljFLOAT
         gVarMeta(gnLastVariable)\valueFloat = ValF(text)
         gVarMeta(gnLastVariable)\flags = #C2FLAG_CONST | #C2FLAG_FLOAT
      ElseIf syntheticType = #ljSTRING
         gVarMeta(gnLastVariable)\valueString = text
         gVarMeta(gnLastVariable)\flags = #C2FLAG_CONST | #C2FLAG_STR
      Else
         ; Set type for constants (literals)
         If TOKEN()\TokenType = #ljINT
            gVarMeta(gnLastVariable)\valueInt = Val(text)
            gVarMeta(gnLastVariable)\flags = #C2FLAG_CONST | #C2FLAG_INT
         ElseIf TOKEN()\TokenType = #ljSTRING
            gVarMeta(gnLastVariable)\valueString = text
            gVarMeta(gnLastVariable)\flags = #C2FLAG_CONST | #C2FLAG_STR
         ElseIf TOKEN()\TokenType = #ljFLOAT
            gVarMeta(gnLastVariable)\valueFloat = ValF(text)
            gVarMeta(gnLastVariable)\flags = #C2FLAG_CONST | #C2FLAG_FLOAT
         ElseIf TOKEN()\TokenType = #ljIDENT
            ; NEW: Check for explicit type hint from suffix (.f or .s)
            If TOKEN()\typeHint = #ljFLOAT
               gVarMeta(gnLastVariable)\flags = #C2FLAG_IDENT | #C2FLAG_FLOAT
            ElseIf TOKEN()\typeHint = #ljSTRING
               gVarMeta(gnLastVariable)\flags = #C2FLAG_IDENT | #C2FLAG_STR
            Else
               ; No suffix - default to INT (no type inference from assignment)
               ; Type conversion will be handled during code generation
               gVarMeta(gnLastVariable)\flags = #C2FLAG_IDENT | #C2FLAG_INT
            EndIf
            ;gVarInt(gnLastVariable) = gnLastVariable
   
         Else
            ;Debug ": " + text + " Not found"
            ;ProcedureReturn -1
         EndIf
      EndIf

      ; If we're creating a local variable (inside a function, not a parameter),
      ; assign it an offset and update nLocals count
      ; This includes both mangled variables (funcname_varname) and synthetic variables ($temp)
      isLocal = #False
      If gCurrentFunctionName <> "" And gCodeGenParamIndex < 0 And gCodeGenFunction > 0
         If LCase(Left(text, Len(gCurrentFunctionName) + 1)) = LCase(gCurrentFunctionName + "_") Or Left(text, 1) = "$"
            ; This is a new local variable (mangled name or synthetic temporary)
            gVarMeta(gnLastVariable)\paramOffset = gCodeGenLocalIndex
            gCodeGenLocalIndex + 1
            isLocal = #True

            ; Update nLocals in mapModules immediately
            ForEach mapModules()
               If mapModules()\function = gCodeGenFunction
                  mapModules()\nLocals = gCodeGenLocalIndex - mapModules()\nParams
                  Break
               EndIf
            Next
         EndIf
      EndIf

      gnLastVariable + 1

      ; V1.020.059: Increment gnGlobalVariables ONLY for global-scope variables
      ; MUST be at global scope (gCodeGenFunction = 0)
      ; AND not a parameter (gCodeGenParamIndex < 0)
      ; AND not a local variable (Not isLocal)
      If gCodeGenFunction = 0 And gCodeGenParamIndex < 0 And Not isLocal
         gnGlobalVariables + 1
         CompilerIf #DEBUG
         Debug "[gnGlobalVariables=" + Str(gnGlobalVariables) + "] Counted: '" + text + "' (slot " + Str(gnLastVariable - 1) + ", gCodeGenFunction=" + Str(gCodeGenFunction) + ", gCodeGenParamIndex=" + Str(gCodeGenParamIndex) + ", isLocal=" + Str(isLocal) + ")"
         CompilerEndIf
      Else
         CompilerIf #DEBUG
         Debug "[SKIPPED] Not counted: '" + text + "' (slot " + Str(gnLastVariable - 1) + ", gCodeGenFunction=" + Str(gCodeGenFunction) + ", gCodeGenParamIndex=" + Str(gCodeGenParamIndex) + ", isLocal=" + Str(isLocal) + ")"
         CompilerEndIf
      EndIf

      ProcedureReturn gnLastVariable - 1
   EndProcedure

   ; Helper: Get type name string from type flags
   Procedure.s          GetTypeNameFromFlags( typeFlags.w )
      If typeFlags & #C2FLAG_FLOAT
         ProcedureReturn "float"
      ElseIf typeFlags & #C2FLAG_STR
         ProcedureReturn "string"
      ElseIf typeFlags & #C2FLAG_INT
         ProcedureReturn "int"
      Else
         ProcedureReturn "unknown"
      EndIf
   EndProcedure

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
            ; Check variable type - search existing variables
            ; Apply name mangling for local variables (same logic as FetchVarOffset)
            Protected searchName.s = *x\value
            If gCurrentFunctionName <> "" And Left(*x\value, 1) <> "$"
               ; Try mangled name first (local variable)
               searchName = gCurrentFunctionName + "_" + *x\value
            EndIf

            For n = 0 To gnLastVariable - 1
               If gVarMeta(n)\name = searchName
                  ; Found the variable - return its type flags
                  ProcedureReturn gVarMeta(n)\flags & #C2FLAG_TYPE
               EndIf
            Next

            ; If mangled name not found and we tried mangling, try global name
            If searchName <> *x\value
               For n = 0 To gnLastVariable - 1
                  If gVarMeta(n)\name = *x\value
                     ; Found the global variable - return its type flags
                     ProcedureReturn gVarMeta(n)\flags & #C2FLAG_TYPE
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

         ; Pointer operations (V1.19.3) - default to INT, arithmetic handles specially
         Case #ljPTRFETCH
            ; PTRFETCH can return any type at runtime based on pointer metadata
            ; Default to INT for assignments and comparisons (most common case)
            ; Arithmetic operations will detect PTRFETCH and use FLOAT ops for safety
            ProcedureReturn #C2FLAG_INT

         ; V1.20.21: Pointer field access - return explicit types
         Case #ljPTRFIELD_I
            ProcedureReturn #C2FLAG_INT
         Case #ljPTRFIELD_F
            ProcedureReturn #C2FLAG_FLOAT
         Case #ljPTRFIELD_S
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
               If funcId >= #ljBUILTIN_RANDOM
                  ; Built-in functions - look up in mapBuiltins for return type
                  ForEach mapBuiltins()
                     If mapBuiltins()\opcode = funcId
                        ProcedureReturn mapBuiltins()\returnType
                     EndIf
                  Next
                  ; Default for unknown built-ins
                  ProcedureReturn #C2FLAG_INT
               Else
                  ; User-defined function - look up in mapModules
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

         Default
            ; Comparisons and other operations return INT
            ProcedureReturn #C2FLAG_INT
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

   Procedure            CodeGenerator( *x.stTree, *link.stTree = 0 )
      Protected         p1, p2, n
      Protected         *pJmp                 ; V1.18.54: Pointer to JMP instruction for while loops
      Protected         temp.s
      Protected         leftType.w
      Protected         rightType.w
      Protected         opType.w = #C2FLAG_INT
      Protected         negType.w = #C2FLAG_INT
      Protected         returnType.w
      Protected         funcId.i
      Protected         paramCount.i
      Protected         isReturnSeq.i
      Protected         *returnExpr.stTree
      Protected         isPointerArithmetic.i
      Protected         ptrVarOffset.i
      Protected         s.s, s2.s, existingTypeName.s
      Protected         isLiteral.i, literalValue.s, convertedIntVal.i, convertedFloatVal.d, constIdx.i, decimalPlaces.i
      Protected         hasExplicitTypeSuffix.i, explicitTypeFlag.w, varNameLower.s  ; V1.20.3: For PTRFETCH explicit typing
      Protected         explicitType.w  ; V1.20.6: Explicit type from variable suffix
      Protected         hasReturnType.b, callReturnType.w  ; V1.020.053: For unused return value handling

      ; Reset state on top-level call
      If gCodeGenRecursionDepth = 0
         gCodeGenParamIndex = -1
         gCodeGenFunction = 0
         gCodeGenLocalIndex = 0
         gCurrentFunctionName = ""
      EndIf
      gCodeGenRecursionDepth + 1

      ; If no node, return immediately
      If Not *x
         gCodeGenRecursionDepth - 1
         ProcedureReturn
      EndIf
   
      ;Debug gszATR( *x\NodeType )\s + " --> " + *x\value
      
      Select *x\NodeType
         Case #ljEOF
            gCodeGenRecursionDepth - 1
            ProcedureReturn
         Case #ljPOP
            ; Check if this is a direct slot reference (for ?discard? slot 0)
            If *x\value = "0"
               n = 0  ; Use reserved slot 0 directly
               EmitInt( #ljPOP, 0 )  ; Always emit as global INT
            Else
               n = FetchVarOffset(*x\value)

               ; Check if this is a function parameter
               If gCodeGenParamIndex >= 0
                  ; This is a function parameter - mark it and don't emit POP
                  ; IMPORTANT: Clear existing type flags before setting parameter type
                  ; Parameters may have been created by FetchVarOffset with wrong inferred types
                  gVarMeta( n )\flags = (gVarMeta( n )\flags & ~#C2FLAG_TYPE) | #C2FLAG_PARAM
                  gVarMeta( n )\paramOffset = gCodeGenParamIndex

                  ; Set type flags (type bits already cleared above)
                  If *x\typeHint = #ljFLOAT
                     gVarMeta( n )\flags = gVarMeta( n )\flags | #C2FLAG_FLOAT
                  ElseIf *x\typeHint = #ljSTRING
                     gVarMeta( n )\flags = gVarMeta( n )\flags | #C2FLAG_STR
                  Else
                     gVarMeta( n )\flags = gVarMeta( n )\flags | #C2FLAG_INT
                  EndIf

                  ; Decrement parameter index (parameters processed in reverse, last to first)
                  gCodeGenParamIndex - 1

                  ; Note: We DON'T emit POP - parameters stay on stack
               ElseIf gCurrentFunctionName <> ""
                  ; Local variable inside a function - assign offset and emit POP
                  gVarMeta( n )\paramOffset = gCodeGenLocalIndex
                  gCodeGenLocalIndex + 1  ; Increment for next local

                  ; Update nLocals in mapModules immediately
                  ForEach mapModules()
                     If mapModules()\function = gCodeGenFunction
                        mapModules()\nLocals = gCodeGenLocalIndex - mapModules()\nParams
                        Break
                     EndIf
                  Next

                  ; Set type flags
                  If *x\typeHint = #ljFLOAT
                     EmitInt( #ljPOPF, n )
                     gVarMeta( n )\flags = #C2FLAG_IDENT | #C2FLAG_FLOAT
                  ElseIf *x\typeHint = #ljSTRING
                     EmitInt( #ljPOPS, n )
                     gVarMeta( n )\flags = #C2FLAG_IDENT | #C2FLAG_STR
                  Else
                     EmitInt( #ljPOP, n )
                     gVarMeta( n )\flags = #C2FLAG_IDENT | #C2FLAG_INT
                  EndIf
               Else
                  ; Global variable - emit POP as usual
                  If *x\typeHint = #ljFLOAT
                     EmitInt( #ljPOPF, n )
                     gVarMeta( n )\flags = #C2FLAG_IDENT | #C2FLAG_FLOAT
                  ElseIf *x\typeHint = #ljSTRING
                     EmitInt( #ljPOPS, n )
                     gVarMeta( n )\flags = #C2FLAG_IDENT | #C2FLAG_STR
                  Else
                     EmitInt( #ljPOP, n )
                     gVarMeta( n )\flags = #C2FLAG_IDENT | #C2FLAG_INT
                  EndIf
               EndIf
            EndIf
         
         Case #ljIDENT
            n = FetchVarOffset(*x\value)
            ; Emit appropriate FETCH variant based on variable type
            If gVarMeta(n)\flags & #C2FLAG_STR
               EmitInt( #ljFETCHS, n )
            ElseIf gVarMeta(n)\flags & #C2FLAG_FLOAT
               EmitInt( #ljFETCHF, n )
            Else
               EmitInt( #ljFetch, n )
            EndIf
            gVarMeta( n )\flags = gVarMeta( n )\flags | #C2FLAG_IDENT

         ; V1.20.21: Pointer field access (ptr\i, ptr\f, ptr\s)
         ; V1.20.22: Can be either simple variable (leaf) or array element (node with left child)
         Case #ljPTRFIELD_I
            If *x\left
               ; Array element pointer field: arr[i]\i
               CodeGenerator( *x\left )  ; Generate array access (leaves pointer on stack)
            Else
               ; Simple variable pointer field: ptr\i
               n = FetchVarOffset(*x\value)
               EmitInt( #ljFetch, n )    ; Fetch pointer variable
               gVarMeta( n )\flags = gVarMeta( n )\flags | #C2FLAG_IDENT
            EndIf
            EmitInt( #ljPTRFETCH_INT )   ; Dereference as integer

         Case #ljPTRFIELD_F
            If *x\left
               ; Array element pointer field: arr[i]\f
               CodeGenerator( *x\left )  ; Generate array access (leaves pointer on stack)
            Else
               ; Simple variable pointer field: ptr\f
               n = FetchVarOffset(*x\value)
               EmitInt( #ljFetch, n )    ; Fetch pointer variable
               gVarMeta( n )\flags = gVarMeta( n )\flags | #C2FLAG_IDENT
            EndIf
            EmitInt( #ljPTRFETCH_FLOAT ) ; Dereference as float

         Case #ljPTRFIELD_S
            If *x\left
               ; Array element pointer field: arr[i]\s
               CodeGenerator( *x\left )  ; Generate array access (leaves pointer on stack)
            Else
               ; Simple variable pointer field: ptr\s
               n = FetchVarOffset(*x\value)
               EmitInt( #ljFetch, n )    ; Fetch pointer variable
               gVarMeta( n )\flags = gVarMeta( n )\flags | #C2FLAG_IDENT
            EndIf
            EmitInt( #ljPTRFETCH_STR )   ; Dereference as string

         Case #ljINT, #ljFLOAT, #ljSTRING
            n = FetchVarOffset( *x\value, 0, *x\NodeType )
            EmitInt( #ljPush, n )

         Case #ljLeftBracket
            ; Array indexing: arr[index]
            ; *x\left = array variable (ljIDENT)
            ; *x\right = index expression
            ; Emit index expression, then generic ARRAYFETCH
            ; Postprocessor will optimize and type this

            If *x\left And *x\left\NodeType = #ljIDENT
               n = FetchVarOffset(*x\left\value)

               ; Always emit index expression (postprocessor will optimize)
               CodeGenerator( *x\right )

               ; Determine if array is local or global at compile time
               Protected isLocal.i, arrayIndex.i
               isLocal = 0
               arrayIndex = n  ; Default to global varSlot

               If gVarMeta(n)\paramOffset >= 0
                  ; V1.18.0: Local array - use paramOffset for unified gVar[] slot calculation
                  isLocal = 1
                  arrayIndex = gVarMeta(n)\paramOffset
               EndIf

               ; Emit generic ARRAYFETCH (postprocessor will type it)
               EmitInt( #ljARRAYFETCH, arrayIndex )
               ; Encode local/global in j field: 0=global, 1=local
               llObjects()\j = isLocal
               ; ndx = -1 signals postprocessor to optimize
               llObjects()\ndx = -1
               ; Store varSlot in n field for postprocessor typing
               llObjects()\n = n
            EndIf

         Case #ljASSIGN
            ; V1.20.21: Check if left side is pointer field access (ptr\i, ptr\f, ptr\s)
            ; V1.20.22: Can be simple variable or array element
            If *x\left And (*x\left\NodeType = #ljPTRFIELD_I Or *x\left\NodeType = #ljPTRFIELD_F Or *x\left\NodeType = #ljPTRFIELD_S)
               ; Pointer field store: ptr\i = value, arr[i]\f = value, etc.
               ; *x\left\left = array access node (if array element) OR null (if simple var)
               ; *x\left\value = pointer variable name (if simple var)
               ; *x\right = value expression
               ; Emit value first, then pointer expression, then typed PTRSTORE

               CodeGenerator( *x\right )  ; Push value to stack

               If *x\left\left
                  ; Array element pointer field: arr[i]\i = value
                  CodeGenerator( *x\left\left )  ; Generate array access (leaves pointer on stack)
               Else
                  ; Simple variable pointer field: ptr\i = value
                  n = FetchVarOffset(*x\left\value)
                  EmitInt( #ljFetch, n )         ; Fetch pointer variable
               EndIf

               ; Emit typed PTRSTORE based on field type
               Select *x\left\NodeType
                  Case #ljPTRFIELD_I
                     EmitInt( #ljPTRSTORE_INT )    ; Store integer through pointer
                  Case #ljPTRFIELD_F
                     EmitInt( #ljPTRSTORE_FLOAT )  ; Store float through pointer
                  Case #ljPTRFIELD_S
                     EmitInt( #ljPTRSTORE_STR )    ; Store string through pointer
               EndSelect

            ; Check if left side is pointer dereference
            ElseIf *x\left And *x\left\NodeType = #ljPTRFETCH
               ; Pointer store: *ptr = value
               ; *x\left\left = pointer expression
               ; *x\right = value expression
               ; Emit value first, then pointer expression, then PTRSTORE

               CodeGenerator( *x\right )  ; Push value to stack
               CodeGenerator( *x\left\left )  ; Push pointer (slot index) to stack
               EmitInt( #ljPTRSTORE )  ; Generic pointer store

            ; Check if left side is array indexing
            ElseIf *x\left And *x\left\NodeType = #ljLeftBracket
               ; Array assignment: arr[index] = value
               ; *x\left\left = array variable
               ; *x\left\right = index expression
               ; *x\right = value expression
               ; Emit value, then index, then generic ARRAYSTORE
               ; Postprocessor will optimize and type this

               n = FetchVarOffset(*x\left\left\value)

               ; Emit value expression first (pushes value to stack)
               CodeGenerator( *x\right )

               ; Always emit index expression (postprocessor will optimize)
               CodeGenerator( *x\left\right )

               ; Determine if array is local or global at compile time
               Protected isLocalStore.i, arrayIndexStore.i
               isLocalStore = 0
               arrayIndexStore = n  ; Default to global varSlot

               If gVarMeta(n)\paramOffset >= 0
                  ; V1.18.0: Local array - use paramOffset for unified gVar[] slot calculation
                  isLocalStore = 1
                  arrayIndexStore = gVarMeta(n)\paramOffset
               EndIf

               ; Emit generic ARRAYSTORE (postprocessor will type it)
               ; Stack: [value] [index] -> ARRAYSTORE pops both
               EmitInt( #ljARRAYSTORE, arrayIndexStore )
               ; Encode local/global in j field: 0=global, 1=local
               llObjects()\j = isLocalStore
               ; ndx = -1 signals postprocessor to optimize
               llObjects()\ndx = -1
               ; Store varSlot in n field for postprocessor typing
               llObjects()\n = n
            Else
               ; Regular variable assignment
               n = FetchVarOffset( *x\left\value, *x\right )

               ; Check if right-hand side is a pointer expression and propagate pointer flag
               If *x\right
                  If *x\right\NodeType = #ljGETADDR Or
                     *x\right\NodeType = #ljPTRADD Or
                     *x\right\NodeType = #ljPTRSUB
                     ; Right side is a pointer expression - mark destination as pointer
                     gVarMeta(n)\flags = gVarMeta(n)\flags | #C2FLAG_POINTER
                  ElseIf *x\right\NodeType = #ljIDENT
                     ; Check if source variable is a pointer
                     ptrVarOffset = FetchVarOffset(*x\right\value)
                     If ptrVarOffset >= 0 And ptrVarOffset < ArraySize(gVarMeta())
                        If gVarMeta(ptrVarOffset)\flags & #C2FLAG_POINTER
                           ; Source is a pointer - mark destination as pointer
                           gVarMeta(n)\flags = gVarMeta(n)\flags | #C2FLAG_POINTER
                        EndIf
                     EndIf
                  EndIf
               EndIf

               ; V1.18.42: Get the type of the right-hand expression WITHOUT generating code yet
               ; This allows us to do compile-time conversion optimization for literals
               rightType = GetExprResultType(*x\right)

               ; V1.18.30: Implement proper LJ type system
               ; Variables are type-inferred on first assignment, then locked (static typing)

               If Not (gVarMeta(n)\flags & #C2FLAG_CHG)
                  ; FIRST ASSIGNMENT - Type inference with locking

                  ; V1.20.12: Check if RHS is PTRFETCH (possibly wrapped in type conversion)
                  ; Parser may insert ITOF/FTOI wrapper, so check both direct and wrapped cases
                  Protected *ptrFetchNode.stTree = #Null

                  If *x\right
                     ; Direct PTRFETCH
                     If *x\right\NodeType = #ljPTRFETCH
                        *ptrFetchNode = *x\right
                     ; PTRFETCH wrapped in type conversion (ITOF or FTOI)
                     ElseIf (*x\right\NodeType = #ljITOF Or *x\right\NodeType = #ljFTOI) And *x\right\left
                        If *x\right\left\NodeType = #ljPTRFETCH
                           *ptrFetchNode = *x\right\left
                        EndIf
                     EndIf
                  EndIf

                  ; V1.20.12: If RHS is PTRFETCH (direct or wrapped) with explicit type annotation, bypass conversion
                  If *ptrFetchNode And *x\left And *x\left\TypeHint <> 0
                     ; Convert TypeHint to type flag
                     Select *x\left\TypeHint
                        Case #ljFLOAT
                           explicitTypeFlag = #C2FLAG_FLOAT
                        Case #ljSTRING
                           explicitTypeFlag = #C2FLAG_STR
                        Case #ljINT
                           explicitTypeFlag = #C2FLAG_INT
                        Default
                           explicitTypeFlag = #C2FLAG_INT
                     EndSelect

                     ; Use explicit type from TypeHint
                     gVarMeta(n)\flags = (gVarMeta(n)\flags & ~#C2FLAG_TYPE) | explicitTypeFlag

                     ; Emit appropriate warning
                     If explicitTypeFlag = #C2FLAG_FLOAT
                        AddElement(gWarnings())
                        s = "Variable '" + *x\left\value + "' declared as float (PTRFETCH with TypeHint)"
                        gWarnings() = s
                     ElseIf explicitTypeFlag = #C2FLAG_STR
                        AddElement(gWarnings())
                        s = "Variable '" + *x\left\value + "' declared as string (PTRFETCH with TypeHint)"
                        gWarnings() = s
                     EndIf

                     ; Mark variable as assigned (locks the type)
                     gVarMeta(n)\flags = gVarMeta(n)\flags | #C2FLAG_CHG

                     ; V1.20.5: Set expected type for PTRFETCH to emit specialized opcode
                     gPtrFetchExpectedType = explicitTypeFlag

                     ; V1.20.12: Generate PTRFETCH directly, bypassing type conversion wrapper
                     ; This ensures we emit FPTRFETCH/IPTRFETCH instead of PTRFETCH+ITOF
                     CodeGenerator( *ptrFetchNode )
                  Else
                     ; Normal type inference path

                     ; Check for explicit type suffix conflict with inferred type
                     If *x\left\TypeHint = #ljFLOAT And Not (rightType & #C2FLAG_FLOAT)
                        s = "Type conflict: variable '" + *x\left\value + "' has explicit suffix .f (float) but is assigned " + #CRLF$
                        s + GetTypeNameFromFlags(rightType)
                        SetError( s, #True )
                     ElseIf *x\left\TypeHint = #ljSTRING And Not (rightType & #C2FLAG_STR)
                        s = "Type conflict: variable '" + *x\left\value + "' has explicit suffix .s (string) but is assigned " + #CRLF$
                        s + GetTypeNameFromFlags(rightType)
                        SetError( s, #True )
                     ElseIf *x\left\TypeHint = #ljINT And Not (rightType & #C2FLAG_INT)
                        s = "Type conflict: variable '" + *x\left\value + "' has explicit suffix (int) but is assigned " + #CRLF$
                        s + GetTypeNameFromFlags(rightType)
                        SetError( s, #True )
                     EndIf

                     ; V1.20.10: Use AST TypeHint field to force explicit type
                     ; The TypeHint is set during parsing and is reliable, unlike TOKEN().typeHint during codegen
                     If *x\left\TypeHint = #ljFLOAT
                        ; Explicit .f suffix - FORCE float type
                        gVarMeta(n)\flags = (gVarMeta(n)\flags & ~#C2FLAG_TYPE) | #C2FLAG_FLOAT
                     ElseIf *x\left\TypeHint = #ljSTRING
                        ; Explicit .s suffix - FORCE string type
                        gVarMeta(n)\flags = (gVarMeta(n)\flags & ~#C2FLAG_TYPE) | #C2FLAG_STR
                     ElseIf *x\left\TypeHint = #ljINT
                        ; Explicit .i suffix - FORCE int type
                        gVarMeta(n)\flags = (gVarMeta(n)\flags & ~#C2FLAG_TYPE) | #C2FLAG_INT
                     Else
                        ; No explicit suffix - infer from right-hand side
                        If rightType & #C2FLAG_FLOAT
                           gVarMeta(n)\flags = (gVarMeta(n)\flags & ~#C2FLAG_TYPE) | #C2FLAG_FLOAT
                        ElseIf rightType & #C2FLAG_STR
                           gVarMeta(n)\flags = (gVarMeta(n)\flags & ~#C2FLAG_TYPE) | #C2FLAG_STR
                        Else
                           ; INT type (default)
                           gVarMeta(n)\flags = (gVarMeta(n)\flags & ~#C2FLAG_TYPE) | #C2FLAG_INT
                        EndIf
                     EndIf

                     ; Mark variable as assigned (locks the type)
                     gVarMeta(n)\flags = gVarMeta(n)\flags | #C2FLAG_CHG

                     ; V1.20.5: Set expected type for PTRFETCH to emit specialized opcode
                     If *x\right And *x\right\NodeType = #ljPTRFETCH
                        gPtrFetchExpectedType = gVarMeta(n)\flags & #C2FLAG_TYPE
                     EndIf

                     ; Generate code for right-hand expression (no conversion needed on first assignment)
                     CodeGenerator( *x\right )
                  EndIf

               Else
                  ; SUBSEQUENT ASSIGNMENT - Type checking and conversion

                  ; Check for explicit type suffix conflict with existing type
                  If *x\left\TypeHint = #ljFLOAT And Not (gVarMeta(n)\flags & #C2FLAG_FLOAT)
                     existingTypeName = ""
                     If gVarMeta(n)\flags & #C2FLAG_INT
                        existingTypeName = "int"
                     ElseIf gVarMeta(n)\flags & #C2FLAG_STR
                        existingTypeName = "string"
                     EndIf
                     s2 = "Variable '" + *x\left\value + "' is already declared as " + existingTypeName
                     SetError( s2, #True )
                  ElseIf *x\left\TypeHint = #ljSTRING And Not (gVarMeta(n)\flags & #C2FLAG_STR)
                     existingTypeName = ""
                     If gVarMeta(n)\flags & #C2FLAG_INT
                        existingTypeName = "int"
                     ElseIf gVarMeta(n)\flags & #C2FLAG_FLOAT
                        existingTypeName = "float"
                     EndIf
                     s2 = "Variable '" + *x\left\value + "' is already declared as " + existingTypeName
                     SetError( s2, #True )
                  ElseIf *x\left\TypeHint = #ljINT And Not (gVarMeta(n)\flags & #C2FLAG_INT)
                     existingTypeName = ""
                     If gVarMeta(n)\flags & #C2FLAG_FLOAT
                        existingTypeName = "float"
                     ElseIf gVarMeta(n)\flags & #C2FLAG_STR
                        existingTypeName = "string"
                     EndIf
                     s2 = "Variable '" + *x\left\value + "' is already declared as " + existingTypeName
                     SetError( s2, #True )
                  EndIf

                  ; V1.18.42: Type conversion optimization - compile-time vs runtime
                  ; Check if RHS is a literal (can do compile-time conversion)
                  isLiteral = #False
                  literalValue = ""

                  ; Get decimal places from pragma settings (default to 2 if not set)
                  decimalPlaces = 2
                  If mapPragmas("decimals") <> ""
                     decimalPlaces = Val(mapPragmas("decimals"))
                  EndIf

                  If *x\right\NodeType = #ljFLOAT Or *x\right\NodeType = #ljINT Or *x\right\NodeType = #ljSTRING
                     isLiteral = #True
                     literalValue = *x\right\value
                  EndIf

                  ; V1.20.5: If RHS is PTRFETCH, set expected type and skip conversion
                  ; PTRFETCH uses specialized opcodes to fetch into correct field
                  If *x\right And *x\right\NodeType = #ljPTRFETCH
                     ; Set expected type for specialized PTRFETCH opcode
                     gPtrFetchExpectedType = gVarMeta(n)\flags & #C2FLAG_TYPE
                     CodeGenerator( *x\right )
                     ; Skip all type conversion logic - specialized PTRFETCH handles it
                  Else
                     ; Check for type mismatch and handle conversion
                  ; INT to FLOAT conversion
                  ; V1.19.4: Skip conversion if RHS is PTRFETCH (it handles typing internally)
                  If ((gVarMeta(n)\flags & #C2FLAG_FLOAT) <> 0) And ((rightType & #C2FLAG_INT) <> 0)
                     If isLiteral
                        convertedFloatVal = ValD(literalValue)
                        constIdx = FetchVarOffset( StrD(convertedFloatVal, decimalPlaces), 0, #ljFLOAT )
                        EmitInt( #ljPush, constIdx )
                        AddElement(gWarnings())
                        s2 = "Converting int to float (compile-time) for variable '" + *x\left\value + "'"
                        gWarnings() = s2
                     Else
                        CodeGenerator( *x\right )
                        EmitInt( #ljITOF, 0 )
                        AddElement(gWarnings())
                        s2 = "Converting int to float (runtime) for variable '" + *x\left\value + "'"
                        gWarnings() = s2
                     EndIf

                  ; FLOAT to INT conversion
                  ; V1.19.5: Skip conversion if RHS is PTRFETCH (it handles typing internally)
                  ElseIf ((gVarMeta(n)\flags & #C2FLAG_INT) <> 0) And ((rightType & #C2FLAG_FLOAT) <> 0)
                     If isLiteral
                        convertedFloatVal = ValD(literalValue)
                        ; Apply ftoi pragma setting (truncate or round)
                        If mapPragmas("ftoi") = "truncate"
                           convertedIntVal = Int(convertedFloatVal)
                        Else
                           convertedIntVal = Round(convertedFloatVal, #PB_Round_Nearest)
                        EndIf
                        ; Add to constant pool and emit PUSH
                        constIdx = FetchVarOffset( Str(convertedIntVal), 0, #ljINT )
                        EmitInt( #ljPush, constIdx )
                        AddElement(gWarnings())
                        s2 = "Converting float to int (compile-time) for variable '" + *x\left\value + "'"
                        gWarnings() = s2
                     Else
                        ; V1.19.5: Check if RHS is PTRFETCH - if so, no conversion needed
                        Define isPtrFetch2.i = #False
                        If *x\right And *x\right\NodeType = #ljPTRFETCH
                           isPtrFetch2 = #True
                        EndIf

                        CodeGenerator( *x\right )

                        If Not isPtrFetch2
                           EmitInt( #ljFTOI, 0 )
                           AddElement(gWarnings())
                           s2 = "Converting float to int (runtime) for variable '" + *x\left\value + "'"
                           gWarnings() = s2
                        EndIf
                     EndIf

                  ; FLOAT to STRING conversion
                  ElseIf ((gVarMeta(n)\flags & #C2FLAG_STR) <> 0) And ((rightType & #C2FLAG_FLOAT) <> 0)
                     If isLiteral
                        constIdx = FetchVarOffset( literalValue, 0, #ljSTRING )
                        EmitInt( #ljPush, constIdx )
                        AddElement(gWarnings())
                        s2 = "Converting float to string (compile-time) for variable '" + *x\left\value + "'"
                        gWarnings() = s2
                     Else
                        CodeGenerator( *x\right )
                        EmitInt( #ljFTOS )
                        AddElement(gWarnings())
                        s2 = "Converting float to string (runtime) for variable '" + *x\left\value + "'"
                        gWarnings() = s2
                     EndIf

                  ; INT to STRING conversion
                  ElseIf ((gVarMeta(n)\flags & #C2FLAG_STR) <> 0) And ((rightType & #C2FLAG_INT) <> 0)
                     If isLiteral
                        constIdx = FetchVarOffset( literalValue, 0, #ljSTRING )
                        EmitInt( #ljPush, constIdx )
                        AddElement(gWarnings())
                        s2 = "Converting int to string (compile-time) for variable '" + *x\left\value + "'"
                        gWarnings() = s2
                     Else
                        CodeGenerator( *x\right )
                        EmitInt( #ljITOS )
                        AddElement(gWarnings())
                        s2 = "Converting int to string (runtime) for variable '" + *x\left\value + "'"
                        gWarnings() = s2
                     EndIf

                  ; STRING to FLOAT conversion
                  ElseIf ((gVarMeta(n)\flags & #C2FLAG_FLOAT) <> 0) And ((rightType & #C2FLAG_STR) <> 0)
                     If isLiteral
                        convertedFloatVal = ValD(literalValue)
                        constIdx = FetchVarOffset( StrD(convertedFloatVal, decimalPlaces), 0, #ljFLOAT )
                        EmitInt( #ljPush, constIdx )
                        AddElement(gWarnings())
                        s2 = "Converting string to float (compile-time) for variable '" + *x\left\value + "'"
                        gWarnings() = s2
                     Else
                        CodeGenerator( *x\right )
                        EmitInt( #ljSTOF )
                        AddElement(gWarnings())
                        s2 = "Converting string to float (runtime) for variable '" + *x\left\value + "'"
                        gWarnings() = s2
                     EndIf

                  ; STRING to INT conversion
                  ElseIf ((gVarMeta(n)\flags & #C2FLAG_INT) <> 0) And ((rightType & #C2FLAG_STR) <> 0)
                     If isLiteral
                        constIdx = FetchVarOffset( Str(Val(literalValue)), 0, #ljINT )
                        EmitInt( #ljPush, constIdx )
                        AddElement(gWarnings())
                        s2 = "Converting string to int (compile-time) for variable '" + *x\left\value + "'"
                        gWarnings() = s2
                     Else
                        CodeGenerator( *x\right )
                        EmitInt( #ljSTOI )
                        AddElement(gWarnings())
                        s2 = "Converting string to int (runtime) for variable '" + *x\left\value + "'"
                        gWarnings() = s2
                     EndIf
                  Else
                     ; No conversion needed - generate RHS code normally
                     CodeGenerator( *x\right )

                     ; V1.19.1: Warn if untyped variable is assigned from PTRFETCH
                     If *x\right And *x\right\NodeType = #ljPTRFETCH
                        ; Check if variable has explicit type annotation
                        Protected hasExplicitType.i = #False
                        If (gVarMeta(n)\flags & #C2FLAG_FLOAT) Or (gVarMeta(n)\flags & #C2FLAG_STR)
                           hasExplicitType = #True
                        ElseIf (gVarMeta(n)\flags & #C2FLAG_INT)
                           ; Check if it was explicitly typed or defaulted to INT
                           ; Variables with explicit .i suffix would have been marked
                           ; For now, we'll warn if RHS is PTRFETCH and var is INT (could be implicit)
                           ; This is conservative - may warn on some explicitly typed vars
                        EndIf

                        If Not hasExplicitType
                           AddElement(gWarnings())
                           s2 = "Warning: Untyped variable '" + *x\left\value + "' assigned from pointer dereference. " +
                                "Consider adding explicit type annotation (e.g., var.f = *ptr)"
                           gWarnings() = s2
                        EndIf
                     EndIf
                  EndIf
                  EndIf  ; End of V1.20.0 PTRFETCH explicit typing check
               EndIf

               ; Emit appropriate STORE variant based on variable type
               If gVarMeta(n)\flags & #C2FLAG_STR
                  EmitInt( #ljSTORES, n )
               ElseIf gVarMeta(n)\flags & #C2FLAG_FLOAT
                  EmitInt( #ljSTOREF, n )
               Else
                  EmitInt( #ljSTORE, n )
               EndIf

               ; Type propagation: If assigning a typed value to an untyped var, update the var
               If llObjects()\code <> #ljMOV And llObjects()\code <> #ljMOVS And llObjects()\code <> #ljMOVF And
                  llObjects()\code <> #ljLMOV And llObjects()\code <> #ljLMOVS And llObjects()\code <> #ljLMOVF
                  ; Keep the variable's declared type (don't change it)
                  ; Type checking could be added here later
               EndIf
            EndIf

         Case #ljPRE_INC
            ; Pre-increment: ++var (integers only)
            ; Increments variable in place and pushes new value
            ; Uses single efficient opcode
            If *x\left And *x\left\NodeType = #ljIDENT
               n = FetchVarOffset(*x\left\value)

               ; Check if local or global variable
               If gVarMeta(n)\paramOffset >= 0
                  ; Local variable - use local increment
                  EmitInt( #ljLINC_VAR_PRE, gVarMeta(n)\paramOffset )
               Else
                  ; Global variable
                  EmitInt( #ljINC_VAR_PRE, n )
               EndIf
            EndIf

         Case #ljPRE_DEC
            ; Pre-decrement: --var (integers only)
            ; Decrements variable in place and pushes new value
            ; Uses single efficient opcode
            If *x\left And *x\left\NodeType = #ljIDENT
               n = FetchVarOffset(*x\left\value)

               ; Check if local or global variable
               If gVarMeta(n)\paramOffset >= 0
                  ; Local variable - use local decrement
                  EmitInt( #ljLDEC_VAR_PRE, gVarMeta(n)\paramOffset )
               Else
                  ; Global variable
                  EmitInt( #ljDEC_VAR_PRE, n )
               EndIf
            EndIf

         Case #ljPOST_INC
            ; Post-increment: var++ (integers only)
            ; Pushes old value to stack, then increments variable in place
            ; Uses single efficient opcode
            If *x\left And *x\left\NodeType = #ljIDENT
               n = FetchVarOffset(*x\left\value)

               ; Check if local or global variable
               If gVarMeta(n)\paramOffset >= 0
                  ; Local variable - use local increment
                  EmitInt( #ljLINC_VAR_POST, gVarMeta(n)\paramOffset )
               Else
                  ; Global variable
                  EmitInt( #ljINC_VAR_POST, n )
               EndIf
            EndIf

         Case #ljPOST_DEC
            ; Post-decrement: var-- (integers only)
            ; Pushes old value to stack, then decrements variable in place
            ; Uses single efficient opcode
            If *x\left And *x\left\NodeType = #ljIDENT
               n = FetchVarOffset(*x\left\value)

               ; Check if local or global variable
               If gVarMeta(n)\paramOffset >= 0
                  ; Local variable - use local decrement
                  EmitInt( #ljLDEC_VAR_POST, gVarMeta(n)\paramOffset )
               Else
                  ; Global variable
                  EmitInt( #ljDEC_VAR_POST, n )
               EndIf
            EndIf

         Case #ljreturn
            ; Note: The actual return type is determined at the SEQ level
            ; This case should not normally be reached since SEQ handler processes returns
            EmitInt( #ljreturn )

         Case #ljIF
            CodeGenerator( *x\left )
            EmitInt( #ljJZ)
            p1 = hole()
            CodeGenerator( *x\right\left )

            If *x\right\right
               EmitInt( #ljJMP)
               p2 = hole()
            EndIf

            EmitInt( #ljNOOPIF )   ; Marker after if-body for JZ target
            fix( p1 )

            If *x\right\right
               CodeGenerator( *x\right\right )
               EmitInt( #ljNOOPIF )   ; Marker after else-body for JMP target
               fix( p2 )
            EndIf

         Case #ljTERNARY
            ; Ternary operator: condition ? true_expr : false_expr
            ; *x\left = condition
            ; *x\right = COLON node with true_expr in left, false_expr in right
            ; Using dedicated TENIF/TENELSE opcodes for cleaner implementation
            If *x\left And *x\right
               gInTernary = #True                ; Disable PUSH/FETCH→MOV optimization

               CodeGenerator( *x\left )          ; Evaluate condition
               EmitInt( #ljTENIF )               ; Ternary IF: Jump if condition false
               p1 = hole()                       ; Remember jump location for false branch

               If *x\right\left
                  CodeGenerator( *x\right\left )    ; Evaluate true expression
               EndIf

               EmitInt( #ljTENELSE )             ; Ternary ELSE: Jump past false branch
               p2 = hole()

               ; Emit NOOPIF marker at false branch start - makes offset calculation trivial
               EmitInt( #ljNOOPIF )
               fix( p1 )                         ; Fix TENIF to NOOPIF marker position

               If *x\right\right
                  CodeGenerator( *x\right\right )   ; Evaluate false expression
               EndIf

               ; Emit NOOPIF marker after false branch - target for TENELSE jump
               EmitInt( #ljNOOPIF )
               fix( p2 )                         ; Fix TENELSE to NOOPIF marker position

               gInTernary = #False               ; Re-enable optimization
            EndIf

         Case #ljWHILE
            ; V1.18.54: Save JMP pointer explicitly to avoid LastElement() cursor issues in nested loops
            EmitInt( #ljNOOPIF )            ; Emit marker at loop start
            p1 = llObjects()                ; Save pointer to NOOP marker (current element)
            CodeGenerator( *x\left )        ; Generate condition
            EmitInt( #ljJZ)                 ; Jump if condition false
            p2 = Hole()                     ; Save JZ hole for fixing later
            CodeGenerator( *x\right )       ; Generate loop body
            EmitInt( #ljJMP)                ; Jump back to loop start
            *pJmp = llObjects()             ; Save JMP pointer immediately after EmitInt

            ; Manually create hole entry for backward JMP (mode 3) instead of calling fix()
            AddElement( llHoles() )
            llHoles()\mode = 3
            llHoles()\location = *pJmp      ; Use saved pointer instead of LastElement()
            llHoles()\src = p1

            EmitInt( #ljNOOPIF )            ; Emit marker at loop end
            fix( p2 )                       ; Fix JZ hole to point to end marker
            
         Case #ljSEQ
            ; Check if this SEQ eventually leads to a return statement
            ; Patterns: SEQ(?, SEQ(expr, #ljreturn)) or SEQ(?, SEQ(?, SEQ(expr, #ljreturn)))
            isReturnSeq = #False
            *returnExpr = 0

            If *x\right And *x\right\NodeType = #ljSEQ
               ; Check for two-level pattern: SEQ(?, SEQ(expr, #ljreturn))
               If *x\right\right And *x\right\right\NodeType = #ljreturn
                  isReturnSeq = #True
                  *returnExpr = *x\right\left
               ; Check for three-level pattern: SEQ(?, SEQ(?, SEQ(expr, #ljreturn)))
               ElseIf *x\right\right And *x\right\right\NodeType = #ljSEQ
                  If *x\right\right\right And *x\right\right\right\NodeType = #ljreturn
                     isReturnSeq = #True
                     *returnExpr = *x\right\right\left
                  EndIf
               EndIf
            EndIf

            If isReturnSeq
               ; This is a return statement - handle specially
               ; Process left (previous statements) if any
               If *x\left
                  CodeGenerator( *x\left )
               EndIf

               ; Process return expression
               If *returnExpr
                  CodeGenerator( *returnExpr )
               EndIf

               ; Emit appropriate return opcode based on function type
               returnType = #C2FLAG_INT
               If gCodeGenFunction > 0
                  ForEach mapModules()
                     If mapModules()\function = gCodeGenFunction
                        returnType = mapModules()\returnType
                        Break
                     EndIf
                  Next
               EndIf

               If returnType & #C2FLAG_STR
                  EmitInt( #ljreturnS )
               ElseIf returnType & #C2FLAG_FLOAT
                  EmitInt( #ljreturnF )
               Else
                  EmitInt( #ljreturn )
               EndIf
            Else
               ; Normal SEQ processing
               If *x\left
                  CodeGenerator( *x\left )
               EndIf
               If *x\right
                  CodeGenerator( *x\right )

                  ; V1.020.053: Pop unused values from statement-level operations
                  ; POST_INC and POST_DEC push old value, PRE_INC and PRE_DEC push new value
                  ; When used as statements, these values are unused and must be popped
                  If *x\right\NodeType = #ljPOST_INC Or *x\right\NodeType = #ljPOST_DEC Or
                     *x\right\NodeType = #ljPRE_INC Or *x\right\NodeType = #ljPRE_DEC
                     EmitInt( #ljPOP )
                  EndIf
               EndIf
            EndIf

            ; NOTE: Don't reset gCodeGenFunction here!
            ; The AST has nested SEQ nodes, and resetting here happens too early.
            ; Function body may continue in outer SEQ nodes.
            ; Like gCurrentFunctionName, gCodeGenFunction will be overwritten when next function starts.
            ; The nLocals count is updated incrementally in FetchVarOffset as variables are created.
            
         Case #ljFunction
            ; Emit function marker for postprocessor (implicit return insertion)
            EmitInt( #ljfunction )
            ForEach mapModules()
               If mapModules()\function = Val( *x\value )
                  ; Store BOTH index and pointer to list element for post-optimization fixup
                  mapModules()\Index = ListIndex( llObjects() ) + 1
                  mapModules()\NewPos = @llObjects()  ; Store pointer to element
                  ; Initialize parameter tracking
                  ; Parameters processed in reverse, so start from (nParams - 1) and decrement
                  gCodeGenParamIndex = mapModules()\nParams - 1
                  ; Local variables start after parameters
                  gCodeGenLocalIndex = mapModules()\nParams
                  ; Set current function name for local variable scoping
                  gCurrentFunctionName = MapKey(mapModules())
                  ; Track current function ID for nLocals counting
                  gCodeGenFunction = mapModules()\function
                  Break
               EndIf
            Next
            
         Case #ljPRTC, #ljPRTI, #ljPRTS, #ljPRTF, #ljprint
            CodeGenerator( *x\left )
            EmitInt( *x\NodeType )

         Case #ljLESS, #ljGREATER, #ljLESSEQUAL, #ljGreaterEqual, #ljEQUAL, #ljNotEqual,
              #ljAdd, #ljSUBTRACT, #ljDIVIDE, #ljMULTIPLY

            leftType    = GetExprResultType(*x\left)
            rightType   = GetExprResultType(*x\right)

            ; With proper stack frames, parameters are stack-local and won't be corrupted
            ; No need for temp variables or special handling
            CodeGenerator( *x\left )
            
            ; For string addition, convert left operand to string if needed
            If *x\NodeType = #ljAdd And (leftType & #C2FLAG_STR Or rightType & #C2FLAG_STR)
               If Not (leftType & #C2FLAG_STR)
                  ; Left is not a string - emit conversion
                  If leftType & #C2FLAG_FLOAT
                     EmitInt( #ljFTOS )
                  Else
                     EmitInt( #ljITOS )
                  EndIf
               EndIf
            ElseIf leftType & #C2FLAG_FLOAT And Not (rightType & #C2FLAG_FLOAT) And rightType & #C2FLAG_INT
               ; Left is float, right will be int - no conversion needed yet (convert right after it's pushed)
            ElseIf leftType & #C2FLAG_INT And rightType & #C2FLAG_FLOAT
               ; Left is int, right will be float - convert left to float now
               EmitInt( #ljITOF )
            EndIf
            
            CodeGenerator( *x\right )

            ; Special handling for ADD with strings - emit type conversions
            If *x\NodeType = #ljAdd And (leftType & #C2FLAG_STR Or rightType & #C2FLAG_STR)
               ; Convert right operand to string if needed
               If Not (rightType & #C2FLAG_STR)
                  If rightType & #C2FLAG_FLOAT
                     EmitInt( #ljFTOS )
                  Else
                     EmitInt( #ljITOS )
                  EndIf
               EndIf
               ; Now both operands are strings - emit STRADD
               EmitInt( #ljSTRADD )
            Else
               ; Standard arithmetic/comparison - determine result type
               opType = #C2FLAG_INT

               ; V1.19.3: PTRFETCH safety - use FLOAT ops when pointers involved
               ; This handles mixed-type pointer arrays without runtime overhead
               Protected hasPtrFetch.i = #False
               If *x\left And *x\left\NodeType = #ljPTRFETCH
                  hasPtrFetch = #True
               EndIf
               If *x\right And *x\right\NodeType = #ljPTRFETCH
                  hasPtrFetch = #True
               EndIf

               If leftType & #C2FLAG_FLOAT Or rightType & #C2FLAG_FLOAT Or hasPtrFetch
                  opType = #C2FLAG_FLOAT
                  ; Convert right operand to float if needed
                  If rightType & #C2FLAG_INT And Not (rightType & #C2FLAG_FLOAT)
                     EmitInt( #ljITOF )
                  EndIf
               EndIf

               ; Check if left operand is a pointer for pointer arithmetic
               isPointerArithmetic = #False
               If (*x\NodeType = #ljAdd Or *x\NodeType = #ljSUBTRACT) And *x\left
                  ; Check if left operand is an identifier with pointer flag
                  If *x\left\NodeType = #ljIDENT
                     ptrVarOffset = FetchVarOffset(*x\left\value)
                     If ptrVarOffset >= 0 And ptrVarOffset < ArraySize(gVarMeta())
                        If gVarMeta(ptrVarOffset)\flags & #C2FLAG_POINTER
                           isPointerArithmetic = #True
                        EndIf
                     EndIf
                  ; Also check if left is a pointer fetch result (*ptr)
                  ElseIf *x\left\NodeType = #ljPTRFETCH
                     isPointerArithmetic = #True
                  ; Or if left is GETADDR (&var or &arr[i])
                  ElseIf *x\left\NodeType = #ljGETADDR
                     isPointerArithmetic = #True
                  ; Or if left is another pointer arithmetic operation
                  ElseIf *x\left\NodeType = #ljPTRADD Or *x\left\NodeType = #ljPTRSUB
                     isPointerArithmetic = #True
                  EndIf
               EndIf

               ; Emit correct opcode
               If isPointerArithmetic
                  ; Emit pointer arithmetic opcodes that preserve metadata
                  If *x\NodeType = #ljAdd
                     EmitInt( #ljPTRADD )
                  Else  ; #ljSUBTRACT
                     EmitInt( #ljPTRSUB )
                  EndIf
               ElseIf opType & #C2FLAG_FLOAT And gszATR(*x\NodeType)\flttoken > 0
                  EmitInt( gszATR(*x\NodeType)\flttoken )
               Else
                  EmitInt( *x\NodeType )
               EndIf
            EndIf

         Case #ljOr, #ljAND, #ljMOD, #ljXOR
            CodeGenerator( *x\left )
            CodeGenerator( *x\right )
            EmitInt( *x\NodeType)

         Case #ljNOT
            CodeGenerator( *x\left )
            EmitInt( *x\NodeType)

         Case #ljNEGATE
            CodeGenerator( *x\left )

            If *x\left\NodeType = #ljIDENT
               n = FetchVarOffset(*x\left\value)
               negType = gVarMeta(n)\flags & #C2FLAG_TYPE
            ElseIf *x\left\NodeType = #ljFLOAT
               negType = #C2FLAG_FLOAT
            EndIf

            If negType & #C2FLAG_FLOAT
               EmitInt( #ljFLOATNEG )
            Else
               EmitInt( #ljNEGATE )
            EndIf

         Case #ljGETADDR  ; Address-of operator: &variable or &arr[index]
            ; Check if this is an array element: &arr[index]
            If *x\left And *x\left\NodeType = #ljLeftBracket
               ; Array element pointer: &arr[index]
               ; *x\left\left = array variable (ljIDENT)
               ; *x\left\right = index expression

               If *x\left\left And *x\left\left\NodeType = #ljIDENT
                  n = FetchVarOffset(*x\left\left\value)

                  ; Emit index expression first (pushes index to stack)
                  CodeGenerator( *x\left\right )

                  ; Determine opcode based on array type from metadata (not TypeHint)
                  ; Use gVarMeta flags like normal array indexing does
                  Protected arrayOpcode.i = #ljGETARRAYADDR  ; Default to integer
                  Protected arrayType.i = gVarMeta(n)\flags & #C2FLAG_TYPE
                  If arrayType = #C2FLAG_STR
                     arrayOpcode = #ljGETARRAYADDRS
                  ElseIf arrayType = #C2FLAG_FLOAT
                     arrayOpcode = #ljGETARRAYADDRF
                  EndIf

                  ; Emit GETARRAYADDR with array slot
                  EmitInt( arrayOpcode, n )
               Else
                  SetError( "Address-of array operator requires array variable", #C2ERR_EXPECTED_PRIMARY )
               EndIf

            ; Regular variable pointer: &var
            ElseIf *x\left And *x\left\NodeType = #ljIDENT
               n = FetchVarOffset(*x\left\value)

               ; Mark variable as having its address taken (for pointer metadata)
               gVarMeta(n)\flags = gVarMeta(n)\flags | #C2FLAG_POINTER

               ; Emit type-specific GETADDR based on variable type hint
               Protected opcode.i = #ljGETADDR  ; Default to integer
               If *x\left\TypeHint = #ljSTRING
                  opcode = #ljGETADDRS
               ElseIf *x\left\TypeHint = #ljFLOAT
                  opcode = #ljGETADDRF
               EndIf

               EmitInt( opcode, n )
            Else
               SetError( "Address-of operator requires a variable or array element", #C2ERR_EXPECTED_PRIMARY )
            EndIf

         Case #ljPTRFETCH  ; Pointer dereference: *ptr
            ; Emit code to evaluate pointer expression (should be slot index)
            CodeGenerator( *x\left )

            ; V1.20.5: Emit specialized PTRFETCH if expected type is set
            If gPtrFetchExpectedType & #C2FLAG_FLOAT
               EmitInt( #ljPTRFETCH_FLOAT )
            ElseIf gPtrFetchExpectedType & #C2FLAG_STR
               EmitInt( #ljPTRFETCH_STR )
            ElseIf gPtrFetchExpectedType & #C2FLAG_INT
               EmitInt( #ljPTRFETCH_INT )
            Else
               ; No expected type - emit generic PTRFETCH (will be typed by postprocessor or at runtime)
               EmitInt( #ljPTRFETCH )
            EndIf

            ; Clear expected type after use
            gPtrFetchExpectedType = 0

         Case #ljCall
            funcId = Val( *x\value )
            paramCount = *x\paramCount  ; Get actual param count from tree node

            ; Check if this is a built-in function (opcode >= #ljBUILTIN_RANDOM)
            If funcId >= #ljBUILTIN_RANDOM
               ; Built-in function - emit opcode directly
               EmitInt( funcId )
               llObjects()\j = paramCount
            Else
               ; User-defined function - emit CALL with function ID
               ; Store nParams in j and nLocals in n (no packing)
               Protected nLocals.l, nLocalArrays.l
               EmitInt( #ljCall, funcId )

               ; Find nLocals and nLocalArrays for this function
               ForEach mapModules()
                  If mapModules()\function = funcId
                     nLocals = mapModules()\nLocals
                     nLocalArrays = mapModules()\nLocalArrays
                     Break
                  EndIf
               Next

               ; Store separately: j = nParams, n = nLocals, ndx = nLocalArrays, funcid = function ID
               llObjects()\j = paramCount
               llObjects()\n = nLocals
               llObjects()\ndx = nLocalArrays
               llObjects()\funcid = funcId
            EndIf
            
         Case #ljHalt
            EmitInt( *x\NodeType, 0 )

         ; Type conversion operators (unary - operate on left child)
         Case #ljITOF, #ljFTOI, #ljITOS, #ljFTOS, #ljSTOF, #ljSTOI
            CodeGenerator( *x\left )
            EmitInt( *x\NodeType )

         ; Cast operators (V1.18.63) - smart type conversion based on source and target
         Case #ljCAST_INT, #ljCAST_FLOAT, #ljCAST_STRING
            ; Generate code for the expression to be cast
            CodeGenerator( *x\left )

            ; Determine source type
            Protected sourceType.w = GetExprResultType(*x\left)

            ; Emit appropriate conversion based on source and target types
            Select *x\NodeType
               Case #ljCAST_INT
                  ; Cast to int
                  If sourceType & #C2FLAG_FLOAT
                     EmitInt( #ljFTOI )  ; float -> int
                  ElseIf sourceType & #C2FLAG_STR
                     EmitInt( #ljSTOI )  ; string -> int
                  EndIf
                  ; If already int, no conversion needed

               Case #ljCAST_FLOAT
                  ; Cast to float
                  If sourceType & #C2FLAG_INT
                     EmitInt( #ljITOF )  ; int -> float
                  ElseIf sourceType & #C2FLAG_STR
                     EmitInt( #ljSTOF )  ; string -> float
                  EndIf
                  ; If already float, no conversion needed

               Case #ljCAST_STRING
                  ; Cast to string
                  If sourceType & #C2FLAG_INT
                     EmitInt( #ljITOS )  ; int -> string
                  ElseIf sourceType & #C2FLAG_FLOAT
                     EmitInt( #ljFTOS )  ; float -> string
                  EndIf
                  ; If already string, no conversion needed
            EndSelect

         Default
            SetError("Error in CodeGenerator at node " + Str(*x\NodeType) + " " + *x\value + " ---> " + gszATR(*x\NodeType)\s, #C2ERR_CODEGEN_FAILED)

      EndSelect

      gCodeGenRecursionDepth - 1

      ; Reset code generation state when returning from root level
      ; This ensures clean state for next compilation even if Init() isn't called
      If gCodeGenRecursionDepth = 0
         gCodeGenFunction = 0
         gCodeGenParamIndex = -1
         gCodeGenLocalIndex = 0
         gCurrentFunctionName = ""
      EndIf
   EndProcedure
    
   Procedure            ListCode( gadget = 0 )
      Protected         i
      Protected         flag
      Protected.s       temp, line, FullCode

      Debug ";--"
      Debug ";-- Variables & Constants --"
      Debug ";--"

      For i = 0 To gnLastVariable - 1
         If gVarMeta(i)\flags & #C2FLAG_INT
            temp = "Integer"
         ElseIf gVarMeta(i)\flags & #C2FLAG_FLOAT
            temp = "Float"
         ElseIf gVarMeta(i)\flags & #C2FLAG_STR
            temp = "String"
         ElseIf gVarMeta(i)\flags & #C2FLAG_IDENT
            temp = "Variable"
         EndIf

         If gVarMeta(i)\flags & #C2FLAG_CONST
            temp + " constant"
         EndIf

         Debug RSet(Str(i),6, " ") + "   " + LSet(gVarMeta(i)\name,20," ") + "  (" + temp + ")"
      Next

      Debug ";--"
      Debug ";--     Code Section      --"
      Debug ";--"

      ForEach llObjects()
         ASMLine( llObjects(),0 )
         Debug Line
         FullCode + Line +  #CRLF$
      Next

      Debug ";--"
      Debug ";--     End Program       --"
      Debug ";--"
      ;SetClipboardText( FullCode )
   EndProcedure

; IDE Options = PureBasic 6.21 (Windows - x64)
; CursorPosition = 1587
; FirstLine = 1632
; Folding = ---
; EnableAsm
; EnableThread
; EnableXP
; CPU = 1
; EnablePurifier
; EnableCompileCount = 1
; EnableBuildCount = 0
; EnableExeConstant