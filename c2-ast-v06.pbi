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
; AST - Abstract Syntax Tree / Syntax Analyzer
;- Procedures for building and managing the Abstract Syntax Tree

   Procedure            Expect( function.s, TokenType )

      ;Debug "--Expect--"
      ;Debug TOKEN()\name + " --> " + gszATR( TokenType )

      If TOKEN()\TokenExtra = TokenType
         NextToken()
         ProcedureReturn 0
      EndIf

      SetError( "Expecting " + gszATR( TokenType )\s + " but found " + gszATR( TOKEN()\TokenExtra )\s + " for " + function, #C2ERR_SYNTAX_EXPECTED )

   EndProcedure

   Procedure            MakeNode( NodeType, *left.stTree, *right.stTree )
      Protected         *p.stTree

      *p = AllocateStructure( stTree )

      If *p
         ; Set all fields explicitly (don't use ClearStructure with strings!)
         *p\NodeType = NodeType
         *p\TypeHint = 0
         *p\value    = ""  ; This properly initializes the string
         *p\left     = *left
         *p\right    = *right
      EndIf

      ProcedureReturn *p
   EndProcedure

   Procedure            Makeleaf( NodeType, value.s )
      Protected         *p.stTree
      Protected         savedIndex.i

      *p = AllocateStructure( stTree )

      If *p
         ; Set all fields explicitly (don't use ClearStructure with strings!)
         *p\NodeType = NodeType

         ; V1.18.12: Look up TOKEN to get typeHint (.f, .d, or .s suffix)
         *p\TypeHint = 0  ; Default
         savedIndex = ListIndex(TOKEN())
         ForEach TOKEN()
            If TOKEN()\value = value
               *p\TypeHint = TOKEN()\typeHint  ; Copy typeHint from TOKEN
               Break
            EndIf
         Next
         If savedIndex >= 0
            SelectElement(TOKEN(), savedIndex)
         EndIf

         *p\value    = value  ; This properly handles the string
         *p\left     = 0       ; Explicitly null
         *p\right    = 0       ; Explicitly null
      EndIf

      ProcedureReturn *p
   EndProcedure

   Procedure            expr( var )
      Protected.stTree  *p, *node, *r, *e, *trueExpr, *falseExpr, *branches, *oldP
      Protected         op, q
      Protected         moduleId.i

      ;Debug "expr>" + RSet(Str(TOKEN()\row),4," ") + RSet(Str(TOKEN()\col),4," ") + "   " + TOKEN()\name + " --> " + gszATR( llTokenList()\TokenType )\s

      ; Set gCurrentFunctionName based on TOKEN()\function for local variable lookups
      If TOKEN()\function >= #C2FUNCSTART
         ; Inside a function - find the function name from mapModules
         ForEach mapModules()
            If mapModules()\function = TOKEN()\function
               gCurrentFunctionName = MapKey(mapModules())
               Break
            EndIf
         Next
      Else
         ; At global scope - clear function name
         gCurrentFunctionName = ""
      EndIf

      Select TOKEN()\TokenExtra
         Case #ljLeftParent
            *p = paren_expr()

         Case #ljSUBTRACT, #ljADD
            op = TOKEN()\TokenExtra
            NextToken()
            *node = expr( gPreTable( #ljNEGATE )\Precedence )

            If op = #ljSUBTRACT
               *p = MakeNode( #ljNEGATE, *node, 0 )
            Else
               *p = *Node
            EndIf

         Case #ljINC  ; Pre-increment: ++var
            NextToken()
            *node = expr( gPreTable( #ljNEGATE )\Precedence )  ; Parse variable
            ; Create a PRE_INC node - will be handled in code generator
            *p = MakeNode( #ljPRE_INC, *node, 0 )
            ; Preserve type hint from variable
            If *node\TypeHint
               *p\TypeHint = *node\TypeHint
            EndIf

         Case #ljDEC  ; Pre-decrement: --var
            NextToken()
            *node = expr( gPreTable( #ljNEGATE )\Precedence )  ; Parse variable
            ; Create a PRE_DEC node - will be handled in code generator
            *p = MakeNode( #ljPRE_DEC, *node, 0 )
            ; Preserve type hint from variable
            If *node\TypeHint
               *p\TypeHint = *node\TypeHint
            EndIf

         Case  #ljNOT
            NextToken()
            *p = MakeNode( #ljNOT, expr( gPreTable( #ljNOT )\Precedence ), 0 )

         Case #ljAND  ; V1.021.10: Address-of in unary context: &variable or &function
            ; In unary position, & is address-of operator
            ; In binary position (handled by expr()), & is bitwise AND
            NextToken()

            ; V1.020.099: Check if operand is a function name (marked as CALL by scanner)
            If TOKEN()\TokenType = #ljCALL Or TOKEN()\TokenExtra = #ljCALL
               ; This is &function - create identifier leaf without calling expr()
               ; expr() would try to parse it as function call with expand_params()
               *node = Makeleaf( #ljIDENT, TOKEN()\value )
               ; V1.020.100: Validate node creation succeeded
               If Not *node Or *node < 4096
                  SetError( "Failed to create identifier node for function address", #C2ERR_MEMORY_ALLOCATION )
                  ProcedureReturn 0
               EndIf
               *p = MakeNode( #ljGETADDR, *node, 0 )
               ; V1.020.100: Validate node creation succeeded
               If Not *p Or *p < 4096
                  SetError( "Failed to create GETADDR node for function pointer", #C2ERR_MEMORY_ALLOCATION )
                  ProcedureReturn 0
               EndIf
               NextToken()
            Else
               ; Regular address-of variable/array
               *node = expr( gPreTable( #ljNOT )\Precedence )  ; Parse variable at high precedence
               *p = MakeNode( #ljGETADDR, *node, 0 )
            EndIf

         Case #ljMULTIPLY  ; Could be dereference operator: *ptr (when in unary position)
            ; In unary context, this is pointer dereference
            NextToken()
            *node = expr( gPreTable( #ljNOT )\Precedence )  ; Parse pointer expression
            *p = MakeNode( #ljPTRFETCH, *node, 0 )

         Case #ljPTRFETCH  ; Pointer dereference detected by scanner: *identifier
            ; Scanner has already identified this as dereference (not multiply)
            NextToken()
            *node = expr( gPreTable( #ljNOT )\Precedence )  ; Parse identifier/expression
            *p = MakeNode( #ljPTRFETCH, *node, 0 )

         Case #ljIDENT
            ; Check if this is a built-in function call (identifier followed by '(')
            If FindMapElement(mapBuiltins(), LCase(TOKEN()\value))
               ; Peek at next token to see if it's '('
               ; Save current position in token list
               Protected savedListIndex.i = ListIndex(llTokenList())
               NextToken()

               If TOKEN()\TokenExtra = #ljLeftParent
                  ; It's a built-in function call
                  Protected builtinOpcode.i = mapBuiltins()\opcode
                  *e = expand_params(#ljPush, -1)  ; -1 for built-ins

                  ; V1.026.8: PUSH_SLOT wrapping removed - collection functions now use
                  ; typed opcodes that pop pool slot directly from stack via FETCH/LFETCH.
                  ; For list/map variables, gVar[slot]\i or LOCAL[offset] stores pool index.
                  ; Postprocessor converts generic opcodes to typed based on collection type.

                  *node = Makeleaf(#ljCall, Str(builtinOpcode))  ; Use #ljCall with opcode as value
                  *node\paramCount = gLastExpandParamsCount
                  *p = MakeNode(#ljSEQ, *e, *node)
               Else
                  ; Not a function call, restore position and treat as variable
                  SelectElement(llTokenList(), savedListIndex)
                  *p = Makeleaf( #ljIDENT, TOKEN()\value )
                  *p\TypeHint = TOKEN()\typeHint
                  NextToken()
               EndIf
            Else
               ; Not a built-in - check if it looks like a function call (identifier followed by '(')
               ; OR array indexing (identifier followed by '[')
               Protected savedListIndex2.i = ListIndex(llTokenList())
               Protected identName.s = TOKEN()\value
               Protected identTypeHint.w = TOKEN()\typeHint
               NextToken()

               If TOKEN()\TokenExtra = #ljLeftParent
                  ; V1.020.100: Identifier followed by '(' - could be function pointer call
                  ; Create a Call node with identifier name (value = "0" for function pointer)
                  ; Codegen will check if it's a variable (function pointer) or error
                  *e = expand_params(#ljPush, 0)  ; 0 for potential function pointer
                  *node = Makeleaf(#ljCall, identName)  ; Use identifier name as value
                  *node\paramCount = gLastExpandParamsCount
                  *p = MakeNode(#ljSEQ, *e, *node)
               ElseIf TOKEN()\TokenType = #ljLeftBracket
                  ; Array indexing: identifier[index]
                  NextToken()  ; Skip '['
                  Protected *indexExpr.stTree = expr(0)  ; Parse index expression

                  If TOKEN()\TokenType <> #ljRightBracket
                     SetError( "Expected ']' after array index", #C2ERR_EXPECTED_PRIMARY )
                     ProcedureReturn 0
                  EndIf
                  NextToken()  ; Skip ']'

                  ; Create array index node: left=array var, right=index expression
                  ; We'll use a special node type for array indexing
                  Protected *arrayVar.stTree = Makeleaf( #ljIDENT, identName )
                  *arrayVar\TypeHint = identTypeHint
                  *p = MakeNode( #ljLeftBracket, *arrayVar, *indexExpr )  ; Use LeftBracket as array index operator

                  ; V1.020.101: Check for function call on array element: arr[i](args)
                  If TOKEN()\TokenExtra = #ljLeftParent
                     ; Array element is a function pointer being called
                     ; *p currently holds the array access node
                     ; We need to create a Call node that calls this expression
                     Protected *arrayAccessNode.stTree = *p
                     *e = expand_params(#ljPush, 0)  ; 0 for function pointer
                     *node = Makeleaf(#ljCall, "_arrayFuncPtr_")  ; Placeholder name
                     *node\paramCount = gLastExpandParamsCount
                     ; Store array access in left child of Call node for codegen to handle
                     *node\left = *arrayAccessNode
                     *p = MakeNode(#ljSEQ, *e, *node)
                  EndIf

                  ; V1.20.22: Check for pointer field access on array element: arr[i]\i, arr[i]\f, arr[i]\s
                  If TOKEN()\TokenType = #ljBackslash
                     NextToken()  ; Skip '\'

                     ; Check for field type: i, f, or s (pointer fields)
                     If TOKEN()\value = "i"
                        ; Wrap array access in PTRFIELD_I node
                        *p = MakeNode( #ljPTRFIELD_I, *p, 0 )
                        NextToken()
                     ElseIf TOKEN()\value = "f"
                        ; Wrap array access in PTRFIELD_F node
                        *p = MakeNode( #ljPTRFIELD_F, *p, 0 )
                        NextToken()
                     ElseIf TOKEN()\value = "s"
                        ; Wrap array access in PTRFIELD_S node
                        *p = MakeNode( #ljPTRFIELD_S, *p, 0 )
                        NextToken()
                     Else
                        ; V1.022.44: Check for struct array field access: arr[i]\fieldName
                        ; V1.022.49: Extended to support nested struct fields: arr[i]\nestedStruct\field
                        ; Look up the array variable to check if it's a struct array
                        Protected saFieldName.s = TOKEN()\value
                        Protected saVarSlot.i = -1
                        Protected saStructTypeName.s = ""
                        Protected saFieldOffset.i = -1
                        Protected saFieldType.w = #C2FLAG_INT
                        Protected saFoundField.b = #False
                        Protected saFieldStructType.s = ""  ; V1.022.49: For nested structs

                        ; Find array variable slot
                        Protected saIdx.i
                        For saIdx = 0 To gnLastVariable - 1
                           If LCase(gVarMeta(saIdx)\name) = LCase(identName)
                              saVarSlot = saIdx
                              Break
                           EndIf
                        Next

                        ; Check if it's a struct array
                        If saVarSlot >= 0 And gVarMeta(saVarSlot)\structType <> ""
                           saStructTypeName = gVarMeta(saVarSlot)\structType
                           ; Look up field in struct definition
                           If FindMapElement(mapStructDefs(), saStructTypeName)
                              ResetList(mapStructDefs()\fields())
                              ForEach mapStructDefs()\fields()
                                 If LCase(mapStructDefs()\fields()\name) = LCase(saFieldName)
                                    saFieldOffset = mapStructDefs()\fields()\offset
                                    saFieldType = mapStructDefs()\fields()\fieldType
                                    saFieldStructType = mapStructDefs()\fields()\structType  ; V1.022.49
                                    saFoundField = #True
                                    Break
                                 EndIf
                              Next
                           EndIf
                        EndIf

                        If saFoundField
                           NextToken()  ; Move past field name

                           ; V1.022.49: Handle nested struct chains (arr[i]\nestedStruct\field)
                           While saFieldStructType <> "" And TOKEN()\TokenType = #ljBackslash
                              NextToken()  ; Move past backslash
                              If TOKEN()\TokenType = #ljIDENT
                                 Protected saNestedFieldName.s = TOKEN()\value
                                 Protected saNestedFoundField.b = #False

                                 If FindMapElement(mapStructDefs(), saFieldStructType)
                                    ForEach mapStructDefs()\fields()
                                       If LCase(mapStructDefs()\fields()\name) = LCase(saNestedFieldName)
                                          saFieldOffset = saFieldOffset + mapStructDefs()\fields()\offset
                                          saFieldType = mapStructDefs()\fields()\fieldType
                                          saFieldStructType = mapStructDefs()\fields()\structType
                                          saNestedFoundField = #True
                                          Break
                                       EndIf
                                    Next
                                 EndIf

                                 If Not saNestedFoundField
                                    SetError("Field '" + saNestedFieldName + "' not found in nested struct", #C2ERR_EXPECTED_PRIMARY)
                                    ProcedureReturn 0
                                 EndIf
                                 NextToken()  ; Move past nested field name
                              Else
                                 SetError("Expected field name after '\\'", #C2ERR_EXPECTED_PRIMARY)
                                 ProcedureReturn 0
                              EndIf
                           Wend

                           ; Create struct array field access node
                           ; V1.022.45: Store elementSize|fieldOffset in value field (stTree has no i/j fields)
                           Protected saElementSize.i = gVarMeta(saVarSlot)\elementSize
                           Protected *saFieldNode.stTree
                           ; Use appropriate node type based on field type
                           If saFieldType & #C2FLAG_FLOAT
                              *saFieldNode = MakeNode(#nd_StructArrayField_F, *p, 0)
                           ElseIf saFieldType & #C2FLAG_STR
                              *saFieldNode = MakeNode(#nd_StructArrayField_S, *p, 0)
                           Else
                              *saFieldNode = MakeNode(#nd_StructArrayField_I, *p, 0)
                           EndIf
                           ; Encode: "elementSize|fieldOffset" in value field
                           *saFieldNode\value = Str(saElementSize) + "|" + Str(saFieldOffset)
                           *p = *saFieldNode
                        Else
                           SetError("Expected 'i', 'f', 's' or struct field name after '\\' (field '" + saFieldName + "' not found)", #C2ERR_EXPECTED_PRIMARY)
                           ProcedureReturn 0
                        EndIf
                     EndIf
                  EndIf

               ElseIf TOKEN()\TokenType = #ljBackslash
                  ; V1.20.25: Pointer field access: ptr\i, ptr\f, ptr\s
                  ; Validate that the identifier is actually a pointer type
                  Protected searchKey.s = identName
                  Protected isPointer.b = #False
                  Protected isParameter.b = #False
                  Protected isKnownNonPointer.b = #False

                  ; Check in mapVariableTypes if this variable is marked as a pointer
                  If gCurrentFunctionName <> "" And Left(identName, 1) <> "$"
                     ; Try mangled name first (local variable)
                     searchKey = gCurrentFunctionName + "_" + identName
                  EndIf

                  If FindMapElement(mapVariableTypes(), searchKey)
                     If mapVariableTypes() & #C2FLAG_POINTER
                        isPointer = #True
                     EndIf
                     ; V1.20.34: Don't mark as "known non-pointer" based on inferred types
                     ; The postprocessor will properly track pointer types after parsing
                  ElseIf searchKey <> identName And FindMapElement(mapVariableTypes(), identName)
                     ; Try global name if mangled name not found
                     If mapVariableTypes() & #C2FLAG_POINTER
                        isPointer = #True
                     EndIf
                     ; V1.20.34: Don't mark as "known non-pointer" based on inferred types
                  EndIf

                  ; V1.20.28: Check if variable is a function parameter (if not found in mapVariableTypes)
                  If Not isPointer And Not isKnownNonPointer And gCurrentFunctionName <> ""
                     ; Check if this is a parameter of the current function
                     ForEach mapModules()
                        If MapKey(mapModules()) = gCurrentFunctionName
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
                                 Protected paramName.s = param

                                 ; Extract parameter name (strip type suffix if present)
                                 If FindString(param, ".f", 1, #PB_String_NoCase)
                                    paramName = Left(param, FindString(param, ".f", 1, #PB_String_NoCase) - 1)
                                 ElseIf FindString(param, ".d", 1, #PB_String_NoCase)
                                    paramName = Left(param, FindString(param, ".d", 1, #PB_String_NoCase) - 1)
                                 ElseIf FindString(param, ".s", 1, #PB_String_NoCase)
                                    paramName = Left(param, FindString(param, ".s", 1, #PB_String_NoCase) - 1)
                                 ElseIf FindString(param, ".i", 1, #PB_String_NoCase)
                                    paramName = Left(param, FindString(param, ".i", 1, #PB_String_NoCase) - 1)
                                 EndIf

                                 If LCase(paramName) = LCase(identName)
                                    isParameter = #True
                                    Break
                                 EndIf
                              Next
                           EndIf
                           Break
                        EndIf
                     Next
                  EndIf

                  ; V1.20.28: Allow pointer field access for:
                  ; 1. Variables explicitly marked as pointers
                  ; 2. Function parameters (type determined at runtime)
                  ; Reject for variables known to NOT be pointers
                  If isKnownNonPointer
                     SetError("Variable '" + identName + "' is not a pointer - cannot use pointer field access (\i, \f, \s)", #C2ERR_EXPECTED_PRIMARY)
                     ProcedureReturn 0
                  EndIf

                  NextToken()  ; Skip '\'

                  ; Check for field type: i, f, or s
                  If TOKEN()\value = "i"
                     *p = Makeleaf( #ljPTRFIELD_I, identName )
                     NextToken()
                  ElseIf TOKEN()\value = "f"
                     *p = Makeleaf( #ljPTRFIELD_F, identName )
                     NextToken()
                  ElseIf TOKEN()\value = "s"
                     *p = Makeleaf( #ljPTRFIELD_S, identName )
                     NextToken()
                  Else
                     ; V1.021.0: Check if this is struct field access (structVar\fieldName)
                     Protected structFieldName.s = TOKEN()\value
                     Protected structVarSlot.i = -1
                     Protected structVarIdx.i
                     Protected mangledStructName.s = ""

                     ; V1.022.123: Search for struct variable - LOCAL (mangled) name FIRST, then global
                     ; Skip slot 0 (reserved for ?discard?)
                     If gCurrentFunctionName <> ""
                        mangledStructName = gCurrentFunctionName + "_" + identName
                        For structVarIdx = 1 To gnLastVariable - 1
                           If LCase(gVarMeta(structVarIdx)\name) = LCase(mangledStructName) And (gVarMeta(structVarIdx)\flags & #C2FLAG_STRUCT)
                              structVarSlot = structVarIdx
                              Break
                           EndIf
                        Next
                     EndIf

                     ; V1.022.123: If not found as local, search for global struct (skip slot 0)
                     If structVarSlot < 0
                        CompilerIf #DEBUG
                           Debug "AST struct field search: looking for '" + identName + "' with STRUCT flag in slots 1 to " + Str(gnLastVariable - 1)
                        CompilerEndIf
                        For structVarIdx = 1 To gnLastVariable - 1
                           If LCase(gVarMeta(structVarIdx)\name) = LCase(identName) And (gVarMeta(structVarIdx)\flags & #C2FLAG_STRUCT)
                              structVarSlot = structVarIdx
                              CompilerIf #DEBUG
                                 Debug "AST struct field search: FOUND at slot " + Str(structVarSlot) + " structType='" + gVarMeta(structVarSlot)\structType + "'"
                              CompilerEndIf
                              Break
                           EndIf
                        Next
                        CompilerIf #DEBUG
                           If structVarSlot < 0
                              Debug "AST struct field search: NOT FOUND - checking if name exists without STRUCT flag..."
                              For structVarIdx = 1 To gnLastVariable - 1
                                 If LCase(gVarMeta(structVarIdx)\name) = LCase(identName)
                                    Debug "  Found name at slot " + Str(structVarIdx) + " but flags=" + Str(gVarMeta(structVarIdx)\flags) + " (STRUCT=" + Str(#C2FLAG_STRUCT) + ")"
                                 EndIf
                              Next
                           EndIf
                        CompilerEndIf
                     EndIf

                     If structVarSlot >= 0
                        ; Found struct variable - look up field
                        Protected structTypeNameLookup.s = gVarMeta(structVarSlot)\structType

                        If FindMapElement(mapStructDefs(), structTypeNameLookup)
                           Protected fieldFoundOffset.i = -1
                           Protected fieldFoundType.w = 0
                           Protected fieldFoundIsArray.b = #False
                           Protected fieldFoundArraySize.i = 0

                           ForEach mapStructDefs()\fields()
                              If LCase(mapStructDefs()\fields()\name) = LCase(structFieldName)
                                 fieldFoundOffset = mapStructDefs()\fields()\offset
                                 fieldFoundType = mapStructDefs()\fields()\fieldType
                                 fieldFoundIsArray = mapStructDefs()\fields()\isArray
                                 fieldFoundArraySize = mapStructDefs()\fields()\arraySize
                                 Break
                              EndIf
                           Next

                           If fieldFoundOffset >= 0
                              NextToken()  ; Move past field name

                              ; V1.022.0: Check if this is an array field access
                              If fieldFoundIsArray
                                 ; Array field - must have [index]
                                 If TOKEN()\TokenType = #ljLeftBracket
                                    NextToken()  ; Move past '['

                                    ; Parse array index expression
                                    Protected *arrayIdxExpr = expr(0)

                                    If TOKEN()\TokenType <> #ljRightBracket
                                       SetError("Expected ']' after array index in struct field access", #C2ERR_EXPECTED_PRIMARY)
                                       ProcedureReturn 0
                                    EndIf
                                    NextToken()  ; Move past ']'

                                    ; V1.022.0: Generate struct array field access
                                    ; Uses gVar[baseSlot + index] (contiguous slots)
                                    ; V1.022.2: Support local and global structs
                                    Protected structArrayFieldName.s = identName + "\" + structFieldName
                                    Protected structArrayNodeType.i

                                    ; Choose node type based on field type
                                    If fieldFoundType & #C2FLAG_FLOAT
                                       structArrayNodeType = #ljSTRUCTARRAY_FETCH_FLOAT
                                    ElseIf fieldFoundType & #C2FLAG_STR
                                       structArrayNodeType = #ljSTRUCTARRAY_FETCH_STR
                                    Else
                                       structArrayNodeType = #ljSTRUCTARRAY_FETCH_INT
                                    EndIf

                                    ; Create struct array access node
                                    ; Store struct var slot in value for codegen lookup
                                    ; Format: "structVarSlot|fieldOffset|fieldName"
                                    *p = MakeNode(structArrayNodeType, *arrayIdxExpr, 0)
                                    *p\value = Str(structVarSlot) + "|" + Str(fieldFoundOffset) + "|" + structArrayFieldName

                                    ; Set type hint based on field type
                                    If fieldFoundType & #C2FLAG_FLOAT
                                       *p\TypeHint = #ljFLOAT
                                    ElseIf fieldFoundType & #C2FLAG_STR
                                       *p\TypeHint = #ljSTRING
                                    Else
                                       *p\TypeHint = #ljINT
                                    EndIf
                                 Else
                                    ; Array field without index - error for now
                                    SetError("Array field '" + structFieldName + "' requires index [n]", #C2ERR_EXPECTED_PRIMARY)
                                    ProcedureReturn 0
                                 EndIf
                              Else
                                 ; Regular scalar field access
                                 ; V1.022.47: May be nested struct - handle field chains
                                 Protected actualFieldSlot.i = structVarSlot + fieldFoundOffset
                                 Protected fieldVarName.s = identName + "\" + structFieldName
                                 Protected fieldStructTypeName.s = ""
                                 Protected chainedFieldType.w = fieldFoundType
                                 Protected chainDone.b = #False

                                 ; Check if this field is a nested struct
                                 ForEach mapStructDefs()\fields()
                                    If LCase(mapStructDefs()\fields()\name) = LCase(structFieldName)
                                       fieldStructTypeName = mapStructDefs()\fields()\structType
                                       Break
                                    EndIf
                                 Next

                                 ; V1.022.47: Handle nested struct field chains (outer\inner\field)
                                 While fieldStructTypeName <> "" And Not chainDone
                                    ; Check if there's another backslash for nested field access
                                    If TOKEN()\TokenType = #ljBackslash
                                       NextToken()  ; Move past '\'

                                       If TOKEN()\TokenType = #ljIDENT
                                          Protected nestedFieldName.s = TOKEN()\value
                                          NextToken()  ; Move past field name

                                          ; Look up the nested struct definition
                                          If FindMapElement(mapStructDefs(), fieldStructTypeName)
                                             Protected nestedFieldFound.b = #False
                                             ForEach mapStructDefs()\fields()
                                                If LCase(mapStructDefs()\fields()\name) = LCase(nestedFieldName)
                                                   ; Found the nested field
                                                   actualFieldSlot = actualFieldSlot + mapStructDefs()\fields()\offset
                                                   chainedFieldType = mapStructDefs()\fields()\fieldType
                                                   fieldVarName = fieldVarName + "\" + nestedFieldName
                                                   fieldStructTypeName = mapStructDefs()\fields()\structType  ; For further nesting
                                                   nestedFieldFound = #True
                                                   Break
                                                EndIf
                                             Next

                                             If Not nestedFieldFound
                                                SetError("Unknown field '" + nestedFieldName + "' in nested struct '" + fieldStructTypeName + "'", #C2ERR_EXPECTED_PRIMARY)
                                                ProcedureReturn 0
                                             EndIf
                                          Else
                                             SetError("Nested struct type '" + fieldStructTypeName + "' not defined", #C2ERR_EXPECTED_PRIMARY)
                                             ProcedureReturn 0
                                          EndIf
                                       Else
                                          SetError("Expected field name after '\\' in nested struct access", #C2ERR_EXPECTED_PRIMARY)
                                          ProcedureReturn 0
                                       EndIf
                                    Else
                                       ; No more backslashes - chain is done
                                       ; If we're here and fieldStructTypeName is set, user tried to access whole nested struct
                                       ; which is not supported - need a field
                                       chainDone = #True
                                    EndIf
                                 Wend

                                 ; V1.029.42: REMOVED field slot metadata writing - incompatible with V1.029.40 \ptr storage
                                 ; With \ptr storage, each struct uses only 1 slot. Field access is handled
                                 ; through the base slot's structType lookup in codegen/FetchVarOffset.

                                 *p = Makeleaf(#ljIDENT, fieldVarName)

                                 ; Set type hint based on field type
                                 If chainedFieldType & #C2FLAG_FLOAT
                                    *p\TypeHint = #ljFLOAT
                                 ElseIf chainedFieldType & #C2FLAG_STR
                                    *p\TypeHint = #ljSTRING
                                 Else
                                    *p\TypeHint = #ljINT
                                 EndIf
                              EndIf
                           Else
                              SetError("Unknown field '" + structFieldName + "' in struct '" + structTypeNameLookup + "'", #C2ERR_EXPECTED_PRIMARY)
                              ProcedureReturn 0
                           EndIf
                        Else
                           SetError("Struct type '" + structTypeNameLookup + "' not defined", #C2ERR_EXPECTED_PRIMARY)
                           ProcedureReturn 0
                        EndIf
                     Else
                        ; V1.022.54: Check if this is a struct pointer (ptr\field)
                        Protected ptrVarSlot.i = -1
                        Protected ptrStructTypeName.s = ""
                        Protected mangledPtrName.s = ""

                        ; V1.022.121: Inside functions, ALWAYS use deferred format
                        ; Local pointer variables won't exist in gVarMeta during AST building
                        ; (they're only created during codegen). Searching here can match
                        ; wrong slots due to uninitialized data. Codegen will resolve correctly.
                        If gCurrentFunctionName = ""
                           ; Global scope: search for GLOBAL pointer/struct variables only
                           For structVarIdx = 1 To gnLastVariable - 1  ; Skip slot 0 (reserved)
                              If LCase(gVarMeta(structVarIdx)\name) = LCase(identName)
                                 ; V1.029.40: Check for struct pointer OR struct variable
                                 If gVarMeta(structVarIdx)\pointsToStructType <> ""
                                    ; Struct pointer: ptr\field
                                    ptrVarSlot = structVarIdx
                                    ptrStructTypeName = gVarMeta(structVarIdx)\pointsToStructType
                                    Break
                                 ElseIf gVarMeta(structVarIdx)\structType <> ""
                                    ; Struct variable: var\field (direct field access)
                                    ptrVarSlot = structVarIdx
                                    ptrStructTypeName = gVarMeta(structVarIdx)\structType
                                    Break
                                 EndIf
                              EndIf
                           Next
                        EndIf
                        ; Inside functions: ptrVarSlot stays -1, forcing deferred path

                        If ptrVarSlot >= 0
                           ; Struct pointer found - look up field in struct type
                           If FindMapElement(mapStructDefs(), ptrStructTypeName)
                              Protected ptrFieldOffset.i = -1
                              Protected ptrFieldType.w = 0

                              ForEach mapStructDefs()\fields()
                                 If LCase(mapStructDefs()\fields()\name) = LCase(structFieldName)
                                    ptrFieldOffset = mapStructDefs()\fields()\offset
                                    ptrFieldType = mapStructDefs()\fields()\fieldType
                                    Break
                                 EndIf
                              Next

                              If ptrFieldOffset >= 0
                                 NextToken()  ; Move past field name

                                 ; Generate PTRSTRUCTFETCH node
                                 Protected ptrFetchNodeType.i
                                 If ptrFieldType & #C2FLAG_FLOAT
                                    ptrFetchNodeType = #ljPTRSTRUCTFETCH_FLOAT
                                 ElseIf ptrFieldType & #C2FLAG_STR
                                    ptrFetchNodeType = #ljPTRSTRUCTFETCH_STR
                                 Else
                                    ptrFetchNodeType = #ljPTRSTRUCTFETCH_INT
                                 EndIf

                                 ; Create node: value = "ptrVarSlot|fieldOffset"
                                 *p = Makeleaf(ptrFetchNodeType, Str(ptrVarSlot) + "|" + Str(ptrFieldOffset))

                                 ; Set type hint based on field type
                                 If ptrFieldType & #C2FLAG_FLOAT
                                    *p\TypeHint = #ljFLOAT
                                 ElseIf ptrFieldType & #C2FLAG_STR
                                    *p\TypeHint = #ljSTRING
                                 Else
                                    *p\TypeHint = #ljINT
                                 EndIf

                              Else
                                 SetError("Unknown field '" + structFieldName + "' in struct type '" + ptrStructTypeName + "'", #C2ERR_EXPECTED_PRIMARY)
                                 ProcedureReturn 0
                              EndIf
                           Else
                              SetError("Struct type '" + ptrStructTypeName + "' not defined", #C2ERR_EXPECTED_PRIMARY)
                              ProcedureReturn 0
                           EndIf
                        Else
                           ; V1.022.55: Unknown at parse time - create deferred struct pointer node
                           ; This will be resolved during codegen when pointsToStructType is known
                           ; Store as "identName|fieldName" for codegen to resolve
                           NextToken()  ; Move past field name

                           ; Create a deferred struct pointer fetch node (use INT as default, codegen will fix)
                           *p = Makeleaf(#ljPTRSTRUCTFETCH_INT, identName + "|" + structFieldName)
                           *p\TypeHint = #ljINT  ; Default, codegen will determine actual type
                        EndIf
                     EndIf
                  EndIf

               Else
                  ; Regular identifier, restore position
                  SelectElement(llTokenList(), savedListIndex2)
                  *p = Makeleaf( #ljIDENT, TOKEN()\value )
                  *p\TypeHint = TOKEN()\typeHint
                  NextToken()
               EndIf
            EndIf

         Case #ljINT
            *p = Makeleaf( #ljINT, TOKEN()\value )
            *p\TypeHint = TOKEN()\typeHint
            NextToken()

         Case #ljFLOAT
            *p = Makeleaf( #ljFLOAT, TOKEN()\value )
            *p\TypeHint = TOKEN()\typeHint
            NextToken()

         Case #ljSTRING
            *p = Makeleaf( #ljSTRING, TOKEN()\value )
            *p\TypeHint = TOKEN()\typeHint
            NextToken()

         Case #ljCALL
            ; Handle function calls in expressions
            moduleId = Val(TOKEN()\value)
            *node = Makeleaf( #ljCall, TOKEN()\value )
            NextToken()
            *e = expand_params( #ljPush, moduleId )
            *node\paramCount = gLastExpandParamsCount  ; Store actual param count in node
            *p = MakeNode( #ljSEQ, *e, *node )


         Default
            SetError( "Expecting a primary, found " + TOKEN()\name, #C2ERR_EXPECTED_PRIMARY )

      EndSelect

      ; Main operator parsing loop - handles both postfix and infix operators
      While #True
         ; First check for postfix operators (highest precedence)
         If (TOKEN()\TokenExtra = #ljINC Or TOKEN()\TokenExtra = #ljDEC)
            op = TOKEN()\TokenExtra
            NextToken()

            ; Create POST_INC or POST_DEC node
            *oldP = *p
            If op = #ljINC
               *p = MakeNode( #ljPOST_INC, *oldP, 0 )
            Else
               *p = MakeNode( #ljPOST_DEC, *oldP, 0 )
            EndIf
            ; Preserve type hint from variable
            If *oldP\TypeHint
               *p\TypeHint = *oldP\TypeHint
            EndIf
            ; Continue loop to check for more operators

         ElseIf gPreTable( TOKEN()\TokenExtra )\bBinary And gPreTable( TOKEN()\TokenExtra )\Precedence >= var
            ; Handle infix operators
            op = TOKEN()\TokenExtra

            ; Special handling for ternary operator
            If op = #ljQUESTION
               NextToken()  ; Skip ?
               *trueExpr = expr( 0 )  ; Parse true expression

               If gLastError
                  ProcedureReturn *p
               EndIf

               Expect( "ternary", #ljCOLON )  ; Expect :

               If gLastError
                  ProcedureReturn *p
               EndIf

               *falseExpr = expr( gPreTable( op )\Precedence )  ; Parse false expression (right-assoc)

               If gLastError
                  ProcedureReturn *p
               EndIf

               ; Create ternary node: left=condition, right=node containing true/false branches
               ; Only create the node if we have valid pointers
               If *trueExpr And *falseExpr And *p
                  *branches = MakeNode( #ljCOLON, *trueExpr, *falseExpr )

                  ; Validate the created node
                  If Not *branches
                     SetError( "Failed to allocate memory for ternary branches", #C2ERR_MEMORY_ALLOCATION )
                     ProcedureReturn *p
                  EndIf

                  *p = MakeNode( #ljTERNARY, *p, *branches )

                  ; Validate the final ternary node
                  If Not *p
                     SetError( "Failed to allocate memory for ternary node", #C2ERR_MEMORY_ALLOCATION )
                     ProcedureReturn 0
                  EndIf
               EndIf
            Else
               NextToken()

               q = gPreTable( op )\Precedence

               If Not gPreTable( op )\bRightAssociation
                  q + 1
               EndIf

               *node = expr( q )
               *p = MakeNode( gPreTable( op )\NodeType, *p, *node )
            EndIf
            ; Continue loop to check for more operators

         Else
            ; No more operators to handle, exit loop
            Break
         EndIf
      Wend

      ProcedureReturn *p

   EndProcedure

   Procedure            paren_expr()
      Protected         *p.stTree
      Protected         castType.s
      Protected         *castExpr.stTree

      Expect( "paren_expr", #ljLeftParent )

      ; V1.18.63: Check for cast syntax: (int), (float), (string), (void)
      If TOKEN()\TokenExtra = #ljIDENT
         castType = LCase(TOKEN()\value)
         If castType = "int" Or castType = "float" Or castType = "string" Or castType = "void"
            ; This is a cast expression
            NextToken()  ; Consume the type name
            Expect( "paren_expr", #ljRightParent )

            ; Parse the expression to be cast at high precedence (unary operator level)
            *castExpr = expr( gPreTable( #ljNOT )\Precedence )

            ; Create cast node based on type - codegen will emit appropriate conversion opcode
            Select castType
               Case "int"
                  *p = MakeNode( #ljCAST_INT, *castExpr, 0 )
               Case "float"
                  *p = MakeNode( #ljCAST_FLOAT, *castExpr, 0 )
               Case "string"
                  *p = MakeNode( #ljCAST_STRING, *castExpr, 0 )
               Case "void"  ; V1.033.11: Discard return value
                  *p = MakeNode( #ljCAST_VOID, *castExpr, 0 )
            EndSelect

            ProcedureReturn *p
         EndIf
      EndIf

      ; Not a cast, parse as regular parenthesized expression
      *p = expr( 0 )
      Expect( "paren_expr", #ljRightParent )
      ProcedureReturn *p
   EndProcedure

   Procedure            expand_params( op = #ljpop, nModule = -1 )

      Protected.stTree  *p, *e, *v, *first, *last, *param
      Protected         nParams
      ; V1.18.15: Type conversion variables (must be at procedure start)
      Protected.w       expectedType, actualType
      Protected.i       paramIndex
      Protected.stTree  *convertedParam
      Protected.b       hasParamTypes
      Protected.s       targetFuncName
      NewList           llParams.i()  ; List of integers holding pointer values

      ; IMPORTANT: Initialize all pointers to null (they contain garbage otherwise!)
      *p = 0 : *e = 0 : *v = 0 : *first = 0 : *last = 0 : *param = 0 : *convertedParam = 0
      paramIndex = 0 : hasParamTypes = #False : targetFuncName = ""

      Expect( "expand_params", #ljLeftParent )

      ; Build parameter list in correct order
      If TOKEN()\TokenExtra <> #ljRightParent
         Repeat
            *e = expr( 0 )

            ; V1.18.16: Only store if pointer looks valid (>65536 indicates heap allocation)
            If *e And *e > 65536
               AddElement( llParams() )
               llParams() = *e  ; Store pointer as integer
               nParams + 1

               ; V1.029.82: For function definitions (op=#ljPOP), pre-create struct parameter variables
               ; With \ptr storage model, struct params use 1 slot (NOT inflated by field count)
               If op = #ljPOP And *e\NodeType = #ljIDENT And *e\value <> ""
                  Protected epStructDotPos.i = FindString(*e\value, ".")
                  Debug "V1.030.45: expand_params IDENT value='" + *e\value + "' dotPos=" + Str(epStructDotPos)
                  If epStructDotPos > 0 And epStructDotPos < Len(*e\value)
                     Protected epStructTypeName.s = Mid(*e\value, epStructDotPos + 1)
                     Debug "V1.030.45: expand_params structTypeName='" + epStructTypeName + "' gCurrentFunctionName='" + gCurrentFunctionName + "'"
                     ; Check if suffix is a known struct type (not primitive .i, .f, .s, .d)
                     If LCase(epStructTypeName) <> "i" And LCase(epStructTypeName) <> "f" And LCase(epStructTypeName) <> "s" And LCase(epStructTypeName) <> "d"
                        Debug "V1.030.45: expand_params checking mapStructDefs for '" + epStructTypeName + "' exists=" + Str(Bool(FindMapElement(mapStructDefs(), epStructTypeName)))
                        If FindMapElement(mapStructDefs(), epStructTypeName)
                           ; V1.029.82: Get struct size for metadata but DON'T inflate nParams
                           ; With \ptr storage, struct params use 1 slot (pass by reference)
                           Protected epStructSize.i = mapStructDefs()\totalSize

                           ; V1.029.19: Pre-create struct parameter variable with proper flags
                           ; This allows DOT handler to find struct params when parsing function body
                           Protected epBaseName.s = Left(*e\value, epStructDotPos - 1)
                           Protected epMangledName.s = ""
                           Protected epBaseSlot.i

                           ; Apply mangling for local parameters (inside function)
                           If gCurrentFunctionName <> ""
                              epMangledName = gCurrentFunctionName + "_" + epBaseName
                           Else
                              epMangledName = epBaseName
                           EndIf

                           ; Check if variable already exists (case-insensitive)
                           epBaseSlot = -1
                           Protected epSearchIdx.i
                           For epSearchIdx = 0 To gnLastVariable - 1
                              If LCase(gVarMeta(epSearchIdx)\name) = LCase(epMangledName)
                                 epBaseSlot = epSearchIdx
                                 Break
                              EndIf
                           Next

                           ; Create if not exists
                           If epBaseSlot < 0
                              epBaseSlot = gnLastVariable
                              gnLastVariable + 1
                              gVarMeta(epBaseSlot)\name = epMangledName
                              gVarMeta(epBaseSlot)\structFieldBase = -1  ; V1.029.44: Init to -1
                              gVarMeta(epBaseSlot)\paramOffset = -1      ; V1.029.44: Init to -1
                           EndIf

                           ; Set struct flags so DOT handler can find it
                           gVarMeta(epBaseSlot)\flags = #C2FLAG_STRUCT | #C2FLAG_IDENT | #C2FLAG_PARAM
                           gVarMeta(epBaseSlot)\structType = epStructTypeName
                           gVarMeta(epBaseSlot)\elementSize = epStructSize
                           Debug "V1.030.45: expand_params SET structType='" + epStructTypeName + "' for slot=" + Str(epBaseSlot) + " name='" + gVarMeta(epBaseSlot)\name + "'"
                           ; paramOffset will be set properly in codegen

                           ; V1.029.82: With \ptr storage, DON'T reserve field slots
                           ; Struct data accessed via pointer, not through gVar slots
                           ; (Field slot reservation removed)
                        EndIf
                     EndIf
                  EndIf
               EndIf
            ElseIf *e And *e <= 65536
               ; DEBUG: Invalid small pointer value detected
               SetError( "expand_params: expr() returned suspicious pointer value: " + Str(*e), #C2ERR_EXPECTED_PRIMARY )
            EndIf

            If TOKEN()\TokenExtra = #ljComma
               NextToken()
            Else
               Break
            EndIf
         ForEver
      EndIf

      Expect( "expand_params", #ljRightParent )

      ; Generate code based on operation mode
      If op = #ljPOP

         If LastElement( llParams() )
            Repeat
               ; V1.18.15: Get pointer from integer list
               *param = llParams()

               ; Access structure members
               If *param And *param\value > ""
                  *e = Makeleaf( #ljPOP, *param\value )
                  *e\typeHint = *param\typeHint
               Else
                  *e = Makeleaf( #ljPOP, "?unknown?" )
               EndIf

               If *p
                  *p = MakeNode( #ljSEQ, *p, *e )
               Else
                  *p = *e
               EndIf

            Until Not PreviousElement( llParams() )
         EndIf
      Else
         ; For function calls: PUSH params onto stack (forward order)
         ; Apply type conversions if function signature is known
         paramIndex = 0
         hasParamTypes = #False
         targetFuncName = ""

         ; Try to find function signature for type checking
         If nModule > -1
            ForEach mapModules()
               If mapModules()\function = nModule
                  targetFuncName = MapKey(mapModules())
                  FirstElement(mapModules()\paramTypes())
                  hasParamTypes = #True
                  Break
               EndIf
            Next
         EndIf

         ForEach llParams()
            ; V1.18.15: Get pointer from integer list
            *param = llParams()
            *convertedParam = *param

            ; Insert type conversion if needed
            If hasParamTypes And SelectElement(mapModules()\paramTypes(), paramIndex)
               expectedType = mapModules()\paramTypes()
               actualType = GetExprResultType(*param)

               ; Insert conversion node if types don't match
               If expectedType <> actualType
                  If (expectedType & #C2FLAG_FLOAT) And (actualType & #C2FLAG_INT)
                     ; INT to FLOAT conversion
                     *convertedParam = MakeNode(#ljITOF, *param, 0)
                  ElseIf (expectedType & #C2FLAG_INT) And (actualType & #C2FLAG_FLOAT)
                     ; FLOAT to INT conversion
                     *convertedParam = MakeNode(#ljFTOI, *param, 0)
                  ElseIf (expectedType & #C2FLAG_STR) And (actualType & #C2FLAG_INT)
                     ; INT to STRING conversion
                     *convertedParam = MakeNode(#ljITOS, *param, 0)
                  ElseIf (expectedType & #C2FLAG_STR) And (actualType & #C2FLAG_FLOAT)
                     ; FLOAT to STRING conversion
                     *convertedParam = MakeNode(#ljFTOS, *param, 0)
                  EndIf
               EndIf
            EndIf

            If *p
               *p = MakeNode( #ljSEQ, *p, *convertedParam )
            Else
               *p = *convertedParam
            EndIf

            paramIndex + 1
         Next
      EndIf

      ; Store parameter count in module info
      If nModule > -1
         ForEach mapModules()
            If mapModules()\function = nModule
               mapModules()\nParams = nParams
               Break
            EndIf
         Next
      EndIf

      ; Store actual parameter count for validation/built-ins
      gLastExpandParamsCount = nParams

      ProcedureReturn *p
   EndProcedure

   Procedure            stmt()
      Protected.i       i, n
      Protected.stTree  *p, *v, *e, *r, *s, *s2
      Protected.s       text, param, macroKey, macroBody
      Protected         printType.i
      Protected         varIdx.i
      Protected         moduleId.i
      Protected         stmtFunctionId.i
      ; V1.18.13: Type inference variables
      Protected.w       inferredType, inferredHint
      Protected.s       inferredKey, inferredMangledKey
      ; V1.020.033: Pointer tracking variables
      Protected.s       rhsIdentKey
      Protected.b       rhsIdentFound, shouldStoreInferredType
      ; V1.18.13: Compound assignment variables
      Protected.stTree  *lhsCopy
      Protected.i       binaryOp
      ; V1.024.0: FOR loop and SWITCH statement variables
      Protected.i       hasParen
      Protected.stTree  *init, *cond, *update, *updateBody, *condUpdateBody
      Protected.stTree  *cases, *caseVal, *caseBody, *caseNode, *defaultBody, *defaultNode
      ; V1.024.1: FOR init declaration handling
      Protected.stTree  *forVar, *forVal
      Protected.s       forVarKey, forMangledKey
      Protected.w       forVarTypeFlags

      ; CRITICAL: Initialize all pointers to null (they contain garbage otherwise!)
      *p = 0 : *v = 0 : *e = 0 : *r = 0 : *s = 0 : *s2 = 0 : *lhsCopy = 0
      *init = 0 : *cond = 0 : *update = 0 : *updateBody = 0 : *condUpdateBody = 0
      *forVar = 0 : *forVal = 0 : forVarKey = "" : forMangledKey = "" : forVarTypeFlags = 0
      *cases = 0 : *caseVal = 0 : *caseBody = 0 : *caseNode = 0 : *defaultBody = 0 : *defaultNode = 0

      ; Capture function context at start of stmt() before any NextToken() calls
      stmtFunctionId = TOKEN()\function

      ; Set gCurrentFunctionName based on TOKEN()\function for local variable lookups
      If stmtFunctionId >= #C2FUNCSTART
         ; Inside a function - find the function name from mapModules
         ForEach mapModules()
            If mapModules()\function = stmtFunctionId
               gCurrentFunctionName = MapKey(mapModules())
               Break
            EndIf
         Next
      Else
         ; At global scope - clear function name
         gCurrentFunctionName = ""
      EndIf

      gStack + 1

      If gStack > #MAX_RECURSESTACK
         SetError( "Stack overflow", #C2ERR_STACK_OVERFLOW )
         gStack - 1
         ProcedureReturn 0
      EndIf

      ; V1.029.86: Auto-initialize struct declarations: var.Struct; becomes var.Struct = {}
      ; Check if current token is identifier with struct type annotation followed by semicolon
      If TOKEN()\TokenType = #ljIDENT
         Protected autoInitIdentName.s = TOKEN()\value
         Protected autoInitDotPos.i = FindString(autoInitIdentName, ".")
         If autoInitDotPos > 0
            Protected autoInitStructType.s = Mid(autoInitIdentName, autoInitDotPos + 1)
            ; Check if it's a known struct type (not primitive .i, .f, .s, .d)
            If LCase(autoInitStructType) <> "i" And LCase(autoInitStructType) <> "f" And LCase(autoInitStructType) <> "s" And LCase(autoInitStructType) <> "d"
               If FindMapElement(mapStructDefs(), autoInitStructType)
                  ; Peek ahead to see if next token is semicolon
                  Protected autoInitSavedIndex.i = ListIndex(llTokenList())
                  NextToken()
                  If TOKEN()\TokenType = #ljSemi
                     ; This is var.Struct; pattern - transform to var.Struct = {}
                     ; Restore position and create assignment AST node
                     SelectElement(llTokenList(), autoInitSavedIndex)
                     Protected *autoInitLHS.stTree = Makeleaf(#ljIDENT, autoInitIdentName)
                     Protected *autoInitRHS.stTree = Makeleaf(#ljStructInit, "")
                     *p = MakeNode(#ljAssign, *autoInitLHS, *autoInitRHS)
                     NextToken()  ; Skip identifier
                     NextToken()  ; Skip semicolon
                     gStack - 1
                     ProcedureReturn *p
                  Else
                     ; Not followed by semicolon - restore and continue normal parsing
                     SelectElement(llTokenList(), autoInitSavedIndex)
                  EndIf
               EndIf
            EndIf
         EndIf
      EndIf

      Select TOKEN()\TokenType
         Case #ljArray
            ; Array declaration: array varname.type[size]; or array *varname[size]; (pointer array)
            ; Declare all protected variables at top of Case block
            Protected isPointerArray.i
            Protected errMsg.s
            Protected arrayName.s
            Protected arrayTypeHint.w
            Protected arraySize.i
            Protected varSlot.i

            ; IMPORTANT: Initialize isPointerArray on every execution
            isPointerArray = #False

            NextToken()

            ; Check for pointer array: array *name[size]
            ; Note: Scanner converts * to PTRFETCH when followed by identifier
            If TOKEN()\TokenType = #ljOP And (TOKEN()\TokenExtra = #ljMULTIPLY Or TOKEN()\TokenExtra = #ljPTRFETCH)
               isPointerArray = #True
               NextToken()
            EndIf

            If TOKEN()\TokenType <> #ljIDENT
               If isPointerArray
                  errMsg = "Expected identifier after 'array *'"
               Else
                  errMsg = "Expected identifier after 'array'"
               EndIf
               SetError(errMsg, #C2ERR_EXPECTED_STATEMENT)
               gStack - 1
               ProcedureReturn 0
            EndIf

            arrayName = TOKEN()\value
            arrayTypeHint = TOKEN()\typeHint

            NextToken()

            ; Expect [
            If TOKEN()\TokenType <> #ljLeftBracket
               SetError("Expected '[' after array name", #C2ERR_EXPECTED_STATEMENT)
               gStack - 1
               ProcedureReturn 0
            EndIf
            NextToken()

            ; Parse size (must be integer constant or macro constant)
            If TOKEN()\TokenType = #ljINT
               arraySize = Val(TOKEN()\value)
            ElseIf TOKEN()\TokenType = #ljIDENT
               ; Try to resolve as macro constant (case-sensitive)
               macroKey = TOKEN()\value
               Debug "Array size lookup - Token: [" + TOKEN()\value + "]"
               Debug "Available macros: " + Str(MapSize(mapMacros()))
               ForEach mapMacros()
                  Debug "  Key: [" + MapKey(mapMacros()) + "] Body: [" + mapMacros()\body + "]"
               Next
               If FindMapElement(mapMacros(), macroKey)
                  macroBody = Trim(mapMacros()\body)
                  ; Verify the macro body is a numeric constant
                  If macroBody <> "" And Val(macroBody) > 0
                     arraySize = Val(macroBody)
                  Else
                     SetError("Array size macro '" + TOKEN()\value + "' must be a positive integer constant", #C2ERR_EXPECTED_STATEMENT)
                     gStack - 1
                     ProcedureReturn 0
                  EndIf
               Else
                  SetError("Array size must be integer constant (identifier '" + TOKEN()\value + "' is not defined)", #C2ERR_EXPECTED_STATEMENT)
                  gStack - 1
                  ProcedureReturn 0
               EndIf
            Else
               SetError("Array size must be integer constant or macro constant", #C2ERR_EXPECTED_STATEMENT)
               gStack - 1
               ProcedureReturn 0
            EndIf
            NextToken()

            ; Expect ]
            If TOKEN()\TokenType <> #ljRightBracket
               SetError("Expected ']' after array size", #C2ERR_EXPECTED_STATEMENT)
               gStack - 1
               ProcedureReturn 0
            EndIf
            NextToken()

            ; V1.022.44: Check for struct array type (e.g., array points.Point[10])
            ; If arrayName contains a dot followed by a struct type name, this is a struct array
            Protected arrayStructType.s = ""
            Protected arrayDotPos.i = FindString(arrayName, ".")
            If arrayDotPos > 0 And arrayTypeHint = 0
               ; May be struct type - extract and check
               Protected possibleStructType.s = Mid(arrayName, arrayDotPos + 1)
               If FindMapElement(mapStructDefs(), possibleStructType)
                  ; This is a struct array
                  arrayStructType = possibleStructType
                  arrayName = Left(arrayName, arrayDotPos - 1)  ; Use only base name
                  ; V1.022.80: Set struct type hint for cleaner forceLocal check
                  arrayTypeHint = #ljStructType
               EndIf
            EndIf

            ; V1.022.64: Check if array already exists (for resize operation)
            ; If array exists with same type, this is a resize; different type is error
            Protected isArrayResize.i = #False
            Protected existingSlot.i = -1
            Protected existingTypeFlags.w
            Protected newTypeFlag.w
            Protected searchArrayName.s
            Protected mangledArrayName.s

            ; Determine the new type flag from typeHint or pointer flag
            If isPointerArray
               newTypeFlag = #C2FLAG_INT
            ElseIf arrayTypeHint = #ljFLOAT
               newTypeFlag = #C2FLAG_FLOAT
            ElseIf arrayTypeHint = #ljSTRING
               newTypeFlag = #C2FLAG_STR
            Else
               newTypeFlag = #C2FLAG_INT
            EndIf

            ; V1.022.79: Search for existing array to resize
            ; When inside a function, only check for local arrays (mangled names)
            ; When at global scope, check for global arrays (paramOffset = -1)
            ; A local array declaration should NOT match a global array - it shadows it
            searchArrayName = arrayName
            If gCurrentFunctionName <> ""
               ; Inside a function - only check for existing LOCAL array with same name
               mangledArrayName = gCurrentFunctionName + "_" + arrayName
               For i = 0 To gnLastVariable - 1
                  If LCase(gVarMeta(i)\name) = LCase(mangledArrayName)
                     existingSlot = i
                     Break
                  EndIf
               Next
               ; NOTE: We do NOT check global arrays here - local arrays shadow globals
            Else
               ; At global scope - check for existing global array
               For i = 0 To gnLastVariable - 1
                  If LCase(gVarMeta(i)\name) = LCase(searchArrayName) And gVarMeta(i)\paramOffset = -1
                     existingSlot = i
                     Break
                  EndIf
               Next
            EndIf

            ; If variable exists, check if it's an array and validate types
            If existingSlot >= 0
               If gVarMeta(existingSlot)\flags & #C2FLAG_ARRAY
                  ; Existing array found - check type compatibility
                  existingTypeFlags = gVarMeta(existingSlot)\flags & #C2FLAG_TYPE
                  If existingTypeFlags = newTypeFlag
                     ; Same type - this is a resize operation
                     isArrayResize = #True
                     varSlot = existingSlot
                  Else
                     ; Type mismatch error - cannot resize array with different type
                     SetError("Cannot resize array '" + arrayName + "' - declared as different type (resize requires same type)", #C2ERR_EXPECTED_STATEMENT)
                     gStack - 1
                     ProcedureReturn 0
                  EndIf
               Else
                  ; Variable exists but is not an array - error
                  SetError("Variable '" + arrayName + "' already exists and is not an array", #C2ERR_EXPECTED_STATEMENT)
                  gStack - 1
                  ProcedureReturn 0
               EndIf
            Else
               ; New array - register it
               ; V1.022.80: When inside function with explicit type annotation, force local creation
               ; Explicit type = arrayTypeHint <> 0 (covers .i/.f/.s and .StructType)
               ; Without explicit type, check for existing global array first (consistent with regular variables)
               If gCurrentFunctionName <> "" And arrayTypeHint <> 0
                  varSlot = FetchVarOffset(arrayName, 0, 0, #True)
               Else
                  varSlot = FetchVarOffset(arrayName, 0, 0)
               EndIf
            EndIf

            ; V1.021.0: Check for array initialization: array data.i[5] = {1, 2, 3, 4, 5};
            Protected hasArrayInit.i = #False
            If TOKEN()\TokenExtra = #ljASSIGN
               hasArrayInit = #True
               NextToken()

               If TOKEN()\TokenType <> #ljLeftBrace
                  SetError("Expected '{' for array initialization", #C2ERR_EXPECTED_STATEMENT)
                  gStack - 1
                  ProcedureReturn 0
               EndIf
               NextToken()

               ; Parse initializer values
               Protected arrInitIdx.i = 0
               *p = 0

               While TOKEN()\TokenType <> #ljRightBrace And arrInitIdx < arraySize
                  ; Parse value expression
                  Protected *arrInitVal.stTree = expr(0)

                  ; Create array store node: arr[initIdx] = value
                  Protected *arrIdxLeaf.stTree = Makeleaf(#ljINT, Str(arrInitIdx))
                  Protected *arrVarLeaf.stTree = Makeleaf(#ljIDENT, arrayName)
                  *arrVarLeaf\TypeHint = arrayTypeHint
                  Protected *arrIndexNode.stTree = MakeNode(#ljLeftBracket, *arrVarLeaf, *arrIdxLeaf)
                  Protected *arrStoreNode.stTree = MakeNode(#ljASSIGN, *arrIndexNode, *arrInitVal)

                  If *p = 0
                     *p = *arrStoreNode
                  Else
                     *p = MakeNode(#ljSEQ, *p, *arrStoreNode)
                  EndIf

                  arrInitIdx + 1

                  ; Expect comma or closing brace
                  If TOKEN()\TokenType = #ljComma
                     NextToken()
                  EndIf
               Wend

               If TOKEN()\TokenType <> #ljRightBrace
                  SetError("Expected '}' to close array initialization", #C2ERR_EXPECTED_STATEMENT)
                  gStack - 1
                  ProcedureReturn 0
               EndIf
               NextToken()
            EndIf

            ; Expect ;
            If TOKEN()\TokenType <> #ljSemi
               SetError("Expected ';' after array declaration", #C2ERR_EXPECTED_STATEMENT)
               gStack - 1
               ProcedureReturn 0
            EndIf
            NextToken()

            ; V1.022.64: Handle array resize vs new declaration
            If isArrayResize
               ; Array resize - update metadata size and create resize node
               ; NOTE: Struct array resize not yet supported
               If arrayStructType <> ""
                  SetError("Cannot resize struct array '" + arrayName + "' - not yet supported", #C2ERR_EXPECTED_STATEMENT)
                  gStack - 1
                  ProcedureReturn 0
               EndIf

               ; Update metadata size (for bounds checking in future accesses)
               gVarMeta(varSlot)\arraySize = arraySize

               CompilerIf #DEBUG
                  Debug "Array resize: " + arrayName + "[" + Str(arraySize) + "] -> varSlot=" + Str(varSlot)
               CompilerEndIf

               ; Check if this is a local array
               Protected resizeIsLocal.i = #False
               If gVarMeta(varSlot)\paramOffset >= 0
                  resizeIsLocal = #True
               EndIf

               ; Create AST node for ARRAYRESIZE operation
               ; Use existing stTree fields:
               ;   value = array name
               ;   paramCount = new array size
               ;   TypeHint = isLocal flag (0=global, 1=local)
               ; Codegen will look up varSlot by name
               *p = Makeleaf(#ljARRAYRESIZE, arrayName)
               *p\paramCount = arraySize
               *p\TypeHint = resizeIsLocal

               ; Array initialization not supported on resize
               If hasArrayInit
                  SetError("Cannot initialize array during resize", #C2ERR_EXPECTED_STATEMENT)
                  gStack - 1
                  ProcedureReturn 0
               EndIf
            Else
               ; New array declaration - set up metadata
               gVarMeta(varSlot)\arraySize = arraySize

               ; Clear any existing type bits and set array flag + element type
               ; FetchVarOffset may have set INT as default, so clear type bits first
               gVarMeta(varSlot)\flags = (gVarMeta(varSlot)\flags & ~#C2FLAG_TYPE) | #C2FLAG_ARRAY

               ; V1.022.44: Handle struct arrays - set elementSize and allocate slots
               If arrayStructType <> ""
                  ; Struct array - each element is a full struct
                  Protected structArrayDef.stStructDef
                  CopyStructure(mapStructDefs(), @structArrayDef, stStructDef)
                  gVarMeta(varSlot)\elementSize = structArrayDef\totalSize
                  gVarMeta(varSlot)\structType = arrayStructType
                  gVarMeta(varSlot)\flags = gVarMeta(varSlot)\flags | #C2FLAG_STRUCT

                  ; Allocate additional slots: total = arraySize * elementSize
                  ; varSlot is already allocated (1 slot), need (arraySize * elementSize - 1) more
                  Protected totalStructSlots.i = arraySize * structArrayDef\totalSize
                  Protected extraSlots.i = totalStructSlots - 1
                  While extraSlots > 0
                     gnLastVariable + 1
                     extraSlots - 1
                  Wend

               Else
                  ; Primitive array - 1 slot per element
                  gVarMeta(varSlot)\elementSize = 1

                  CompilerIf #DEBUG
                     Debug "Array declaration: " + arrayName + "[" + Str(arraySize) + "] -> varSlot=" + Str(varSlot) + ", stored arraySize=" + Str(gVarMeta(varSlot)\arraySize)
                  CompilerEndIf

                  ; Set element type based on type hint or pointer flag
                  If isPointerArray
                     ; V1.033.44: Pointer array - mark with POINTER flag so type inference knows
                     ; elements contain pointers (ARRAY|POINTER|INT = pointer array)
                     gVarMeta(varSlot)\flags = gVarMeta(varSlot)\flags | #C2FLAG_INT | #C2FLAG_POINTER
                  ElseIf arrayTypeHint = #ljFLOAT
                     gVarMeta(varSlot)\flags = gVarMeta(varSlot)\flags | #C2FLAG_FLOAT
                  ElseIf arrayTypeHint = #ljSTRING
                     gVarMeta(varSlot)\flags = gVarMeta(varSlot)\flags | #C2FLAG_STR
                  Else
                     gVarMeta(varSlot)\flags = gVarMeta(varSlot)\flags | #C2FLAG_INT
                  EndIf
               EndIf

               ; Check if this is a local or global array based on name mangling
               Protected isLocalArray.i = #False
               If gCurrentFunctionName <> "" And stmtFunctionId >= #C2FUNCSTART
                  ; Check if FetchVarOffset created a mangled name (local variable)
                  If LCase(Left(gVarMeta(varSlot)\name, Len(gCurrentFunctionName) + 1)) = LCase(gCurrentFunctionName + "_")
                     isLocalArray = #True
                  EndIf
               EndIf

               ; If inside function and array is local, assign local array index and set paramOffset
               If isLocalArray
                  ForEach mapModules()
                     If mapModules()\function = stmtFunctionId
                        gVarMeta(varSlot)\typeSpecificIndex = mapModules()\nLocalArrays
                        ; V1.022.78: Fixed paramOffset calculation - must be per-function, not global
                        ; Local arrays get paramOffset = nParams + nLocalArrays (0-indexed within function)
                        gVarMeta(varSlot)\paramOffset = mapModules()\nParams + mapModules()\nLocalArrays
                        ; Store mapping: [functionId, localArrayIndex] -> varSlot
                        ; V1.033.50: Ensure array capacity for this function ID
                        EnsureFuncArrayCapacity(stmtFunctionId)
                        gFuncLocalArraySlots(stmtFunctionId, mapModules()\nLocalArrays) = varSlot
                        mapModules()\nLocalArrays + 1
                        ; Update nLocals count - now simply equals nLocalArrays (other locals added during codegen)
                        mapModules()\nLocals = mapModules()\nLocalArrays
                        Break
                     EndIf
                  Next
               Else
                  ; Global array - set paramOffset to -1
                  gVarMeta(varSlot)\paramOffset = -1
               EndIf

               ; V1.021.0: Return initialization code if present, otherwise empty node
               If Not hasArrayInit
                  *p = 0
               EndIf
               ; If hasArrayInit is true, *p already contains the initialization sequence
            EndIf

         Case #ljStruct
            ; V1.021.0: Structure definition: struct Name { field1.type; field2.type; ... }
            ; V1.022.0: Extended for array fields: field.type[size];
            ; V1.022.47: Extended for nested struct fields: inner.StructType;
            ; Declare all protected variables at top of Case block
            Protected structName.s
            Protected fieldName.s
            Protected fieldType.w
            Protected fieldOffset.i
            Protected fieldIsArray.b
            Protected fieldArraySize.i
            Protected fieldStructType.s      ; V1.022.47: Nested struct type name (empty for primitives)
            Protected fieldDotPos.i          ; V1.022.47: Position of '.' in field name
            Protected nestedStructSize.i     ; V1.022.47: Size of nested struct

            NextToken()

            ; Expect structure name
            If TOKEN()\TokenType <> #ljIDENT
               SetError("Expected structure name after 'struct'", #C2ERR_EXPECTED_STATEMENT)
               gStack - 1
               ProcedureReturn 0
            EndIf

            structName = TOKEN()\value
            NextToken()

            ; Expect opening brace
            If TOKEN()\TokenType <> #ljLeftBrace
               SetError("Expected '{' after structure name", #C2ERR_EXPECTED_STATEMENT)
               gStack - 1
               ProcedureReturn 0
            EndIf
            NextToken()

            ; Create new structure definition
            AddMapElement(mapStructDefs(), structName)
            mapStructDefs()\name = structName
            fieldOffset = 0

            ; Parse fields until closing brace
            While TOKEN()\TokenType <> #ljRightBrace And TOKEN()\TokenType <> #ljEOF
               ; Expect field name with type hint
               If TOKEN()\TokenType <> #ljIDENT
                  SetError("Expected field name in structure", #C2ERR_EXPECTED_STATEMENT)
                  gStack - 1
                  ProcedureReturn 0
               EndIf

               fieldName = TOKEN()\value
               fieldType = TOKEN()\typeHint
               fieldStructType = ""  ; V1.022.47: Reset nested struct type
               nestedStructSize = 0

               ; V1.022.47: Check for nested struct type (inner.StructType where typeHint=0)
               ; V1.022.49: Fixed map position bug - must restore position after lookup
               If fieldType = 0
                  fieldDotPos = FindString(fieldName, ".")
                  If fieldDotPos > 0
                     ; Split into field name and potential struct type
                     Protected nestedTypeName.s = Mid(fieldName, fieldDotPos + 1)
                     fieldName = Left(fieldName, fieldDotPos - 1)

                     ; Check if it's a known struct type
                     If FindMapElement(mapStructDefs(), nestedTypeName)
                        ; It's a nested struct field
                        fieldStructType = nestedTypeName
                        fieldType = 0  ; 0 indicates nested struct (not INT/FLOAT/STR)
                        nestedStructSize = mapStructDefs()\totalSize
                        ; V1.022.49: Restore map position to struct being defined
                        FindMapElement(mapStructDefs(), structName)
                     Else
                        ; Unknown type after dot - default to int
                        fieldType = #C2FLAG_INT
                        ; V1.022.49: Restore map position (FindMapElement returns 0 but changes position)
                        FindMapElement(mapStructDefs(), structName)
                     EndIf
                  Else
                     ; No dot, default to integer
                     fieldType = #C2FLAG_INT
                  EndIf
               ElseIf fieldType = #ljINT
                  fieldType = #C2FLAG_INT
               ElseIf fieldType = #ljFLOAT
                  fieldType = #C2FLAG_FLOAT
               ElseIf fieldType = #ljSTRING
                  fieldType = #C2FLAG_STR
               Else
                  fieldType = #C2FLAG_INT
               EndIf

               NextToken()

               ; V1.022.0: Check for array field syntax [size]
               fieldIsArray = #False
               fieldArraySize = 0

               If TOKEN()\TokenType = #ljLeftBracket
                  ; This is an array field
                  fieldIsArray = #True
                  NextToken()

                  ; Expect array size (integer constant)
                  If TOKEN()\TokenType = #ljINT
                     fieldArraySize = Val(TOKEN()\value)
                     If fieldArraySize <= 0
                        SetError("Array size must be positive in struct field", #C2ERR_EXPECTED_STATEMENT)
                        gStack - 1
                        ProcedureReturn 0
                     EndIf
                     NextToken()
                  Else
                     SetError("Expected array size in struct field", #C2ERR_EXPECTED_STATEMENT)
                     gStack - 1
                     ProcedureReturn 0
                  EndIf

                  ; Expect closing bracket
                  If TOKEN()\TokenType <> #ljRightBracket
                     SetError("Expected ']' after array size in struct field", #C2ERR_EXPECTED_STATEMENT)
                     gStack - 1
                     ProcedureReturn 0
                  EndIf
                  NextToken()
               EndIf

               ; Add field to structure definition
               AddElement(mapStructDefs()\fields())
               mapStructDefs()\fields()\name = fieldName
               ; fieldType is already converted to #C2FLAG_* format at lines 1613-1621 above
               mapStructDefs()\fields()\fieldType = fieldType
               mapStructDefs()\fields()\offset = fieldOffset
               mapStructDefs()\fields()\isArray = fieldIsArray
               mapStructDefs()\fields()\arraySize = fieldArraySize
               mapStructDefs()\fields()\structType = fieldStructType  ; V1.022.47: Nested struct type

               ; V1.022.0: Increment offset by array size or 1 for scalar
               ; V1.022.47: For nested structs, use nested struct size
               If fieldStructType <> ""
                  ; Nested struct field - takes nestedStructSize slots
                  fieldOffset + nestedStructSize
               ElseIf fieldIsArray
                  fieldOffset + fieldArraySize
               Else
                  fieldOffset + 1
               EndIf

               ; Expect semicolon after field
               If TOKEN()\TokenType <> #ljSemi
                  SetError("Expected ';' after field declaration", #C2ERR_EXPECTED_STATEMENT)
                  gStack - 1
                  ProcedureReturn 0
               EndIf
               NextToken()
            Wend

            ; Store total size
            mapStructDefs()\totalSize = fieldOffset

            ; Expect closing brace
            If TOKEN()\TokenType <> #ljRightBrace
               SetError("Expected '}' to close structure definition", #C2ERR_EXPECTED_STATEMENT)
               gStack - 1
               ProcedureReturn 0
            EndIf
            NextToken()

            ; Optional semicolon after struct definition
            If TOKEN()\TokenType = #ljSemi
               NextToken()
            EndIf

            CompilerIf #DEBUG
               Debug "Struct definition: " + structName + " with " + Str(fieldOffset) + " fields"
               ForEach mapStructDefs()\fields()
                  Debug "  Field: " + mapStructDefs()\fields()\name + " offset=" + Str(mapStructDefs()\fields()\offset)
               Next
            CompilerEndIf

            ; Return empty node (struct definition doesn't generate code itself)
            *p = 0

         ; V1.026.0: List declaration: list myList.type;
         Case #ljList
            Protected listName.s
            Protected listTypeHint.w
            Protected listVarSlot.i
            Protected listStructType.s = ""

            NextToken()

            If TOKEN()\TokenType <> #ljIDENT
               SetError("Expected identifier after 'list'", #C2ERR_EXPECTED_STATEMENT)
               gStack - 1
               ProcedureReturn 0
            EndIf

            listName = TOKEN()\value
            listTypeHint = TOKEN()\typeHint

            ; V1.029.14: Check for struct type suffix (e.g., list pointList.Point)
            Protected listDotPos.i = FindString(listName, ".")
            If listDotPos > 0 And listTypeHint = 0
               listStructType = Mid(listName, listDotPos + 1)
               listName = Left(listName, listDotPos - 1)
               If FindMapElement(mapStructDefs(), listStructType)
                  listTypeHint = #ljStructType
               EndIf
            EndIf

            ; Default to integer if no type specified
            If listTypeHint = 0
               listTypeHint = #ljINT
            EndIf

            NextToken()

            ; Expect semicolon
            If TOKEN()\TokenType <> #ljSemi
               SetError("Expected ';' after list declaration", #C2ERR_EXPECTED_STATEMENT)
               gStack - 1
               ProcedureReturn 0
            EndIf
            NextToken()

            ; Create variable slot for the list
            listVarSlot = FetchVarOffset(listName, 0, 0)
            gVarMeta(listVarSlot)\flags = #C2FLAG_LIST
            If listTypeHint = #ljFLOAT
               gVarMeta(listVarSlot)\flags = gVarMeta(listVarSlot)\flags | #C2FLAG_FLOAT
            ElseIf listTypeHint = #ljSTRING
               gVarMeta(listVarSlot)\flags = gVarMeta(listVarSlot)\flags | #C2FLAG_STR
            ElseIf listTypeHint = #ljStructType
               ; V1.029.14: Struct list - set STRUCT flag and struct type
               gVarMeta(listVarSlot)\flags = gVarMeta(listVarSlot)\flags | #C2FLAG_STRUCT
               gVarMeta(listVarSlot)\structType = listStructType
               gVarMeta(listVarSlot)\elementSize = mapStructDefs()\totalSize
            Else
               gVarMeta(listVarSlot)\flags = gVarMeta(listVarSlot)\flags | #C2FLAG_INT
            EndIf

            ; Create LIST_NEW AST node
            *p = Makeleaf(#ljLIST_NEW, listName)
            *p\TypeHint = listTypeHint
            ; V1.029.14: Store struct type info in AST for codegen
            If listStructType <> ""
               *p\value = listName
               ; Use paramCount to store element size for struct lists
               *p\paramCount = gVarMeta(listVarSlot)\elementSize
            EndIf

         ; V1.026.0: Map declaration: map myMap.type;
         Case #ljMap
            Protected mapName.s
            Protected mapTypeHint.w
            Protected mapVarSlot.i
            Protected mapStructType.s = ""

            NextToken()

            If TOKEN()\TokenType <> #ljIDENT
               SetError("Expected identifier after 'map'", #C2ERR_EXPECTED_STATEMENT)
               gStack - 1
               ProcedureReturn 0
            EndIf

            mapName = TOKEN()\value
            mapTypeHint = TOKEN()\typeHint

            ; V1.029.14: Check for struct type suffix (e.g., map pointMap.Point)
            Protected mapDotPos.i = FindString(mapName, ".")
            If mapDotPos > 0 And mapTypeHint = 0
               mapStructType = Mid(mapName, mapDotPos + 1)
               mapName = Left(mapName, mapDotPos - 1)
               If FindMapElement(mapStructDefs(), mapStructType)
                  mapTypeHint = #ljStructType
               EndIf
            EndIf

            ; Default to integer if no type specified
            If mapTypeHint = 0
               mapTypeHint = #ljINT
            EndIf

            NextToken()

            ; Expect semicolon
            If TOKEN()\TokenType <> #ljSemi
               SetError("Expected ';' after map declaration", #C2ERR_EXPECTED_STATEMENT)
               gStack - 1
               ProcedureReturn 0
            EndIf
            NextToken()

            ; Create variable slot for the map
            mapVarSlot = FetchVarOffset(mapName, 0, 0)
            gVarMeta(mapVarSlot)\flags = #C2FLAG_MAP
            If mapTypeHint = #ljFLOAT
               gVarMeta(mapVarSlot)\flags = gVarMeta(mapVarSlot)\flags | #C2FLAG_FLOAT
            ElseIf mapTypeHint = #ljSTRING
               gVarMeta(mapVarSlot)\flags = gVarMeta(mapVarSlot)\flags | #C2FLAG_STR
            ElseIf mapTypeHint = #ljStructType
               ; V1.029.14: Struct map - set STRUCT flag and struct type
               gVarMeta(mapVarSlot)\flags = gVarMeta(mapVarSlot)\flags | #C2FLAG_STRUCT
               gVarMeta(mapVarSlot)\structType = mapStructType
               gVarMeta(mapVarSlot)\elementSize = mapStructDefs()\totalSize
            Else
               gVarMeta(mapVarSlot)\flags = gVarMeta(mapVarSlot)\flags | #C2FLAG_INT
            EndIf

            ; Create MAP_NEW AST node
            *p = Makeleaf(#ljMAP_NEW, mapName)
            *p\TypeHint = mapTypeHint
            ; V1.029.14: Store struct type info in AST for codegen
            If mapStructType <> ""
               *p\value = mapName
               ; Use paramCount to store element size for struct maps
               *p\paramCount = gVarMeta(mapVarSlot)\elementSize
            EndIf

         ; V1.022.71: 'local' keyword removed - type annotation creates local automatically

         Case #ljIF
            NextToken()
            ; Allow optional parentheses around condition
            If TOKEN()\TokenExtra = #ljLeftParent
               *e = paren_expr()
            Else
               *e = expr(0)
            EndIf
            *s    = stmt()
            *s2   = 0

            If TOKEN()\TokenType = #ljElse
               NextToken()
               *s2 = stmt()
            EndIf

            *p = MakeNode( #ljIF, *e, MakeNode( #ljIF, *s, *s2 ) )

         Case #ljPRTC
            NextToken()
            *e    = paren_expr()
            *p    = MakeNode( #ljPRTC, *e, 0 )
            expect( "putc", #ljSemi )

         Case #ljPrint
            NextToken()
            expect( "print", #ljLeftParent )

            Repeat
               printType = #ljPRTI

               If TOKEN()\TokenExtra = #ljSTRING
                  *r = Makeleaf( #ljSTRING, TOKEN()\value )
                  printType = #ljPRTS
                  NextToken()
               ElseIf TOKEN()\TokenExtra = #ljFLOAT
                  *r = expr( 0 )
                  printType = #ljPRTF
               Else
                  ; Handle all other expressions (variables, arithmetic, etc.)
                  *r = expr( 0 )
                  ; Determine type from the expression tree
                  Protected exprType.w = GetExprResultType(*r)
                  If exprType & #C2FLAG_FLOAT
                     printType = #ljPRTF
                  ElseIf exprType & #C2FLAG_STR
                     printType = #ljPRTS
                  EndIf
               EndIf

               *e = MakeNode( printType, *r, 0 )
               *p = MakeNode( #ljSEQ, *p, *e )

               If TOKEN()\TokenType <> #ljComma
                  Break
               EndIf

               expect( "print", #ljComma )

            Until TOKEN()\TokenType = #ljEOF

            ; Add LineFeed as end of string
            *r = Makeleaf( #ljINT, "10" )
            *e = MakeNode( #ljPRTC, *r, 0 )
            *p = MakeNode( #ljSEQ, *p, *e )

            ;*r = Makeleaf( #ljSTRING, gszNL, llTokenList()\ModID )
            ;*e = MakeNode( #ljPRTS, *r, 0, llTokenList()\ModID )
            ;*p = MakeNode( #ljSEQ, *p, *e, llTokenList()\ModID )

            Expect( "Print", #ljRightParent )
            Expect( "Print", #ljSemi )

         Case #ljSemi
            NextToken()

         Case #ljIDENT
            ; V1.022.48: Flag for auto-declared struct on first use
            Protected autoDeclarredStruct.b = #False

            ; V1.021.0: Check if identifier contains '.' with struct type (p1.Point = {...})
            Protected stmtDotPos.i = FindString(TOKEN()\value, ".")
            If stmtDotPos > 0 And TOKEN()\typeHint = 0
               ; Check if part after '.' is a struct type name
               Protected structVarName.s = Left(TOKEN()\value, stmtDotPos - 1)
               Protected structTypeName.s = Mid(TOKEN()\value, stmtDotPos + 1)

               If FindMapElement(mapStructDefs(), structTypeName)
                  ; This is: varName.StructType = {values}; OR varName.StructType\field = value;
                  Protected structDef.stStructDef
                  CopyStructure(mapStructDefs(), @structDef, stStructDef)
                  NextToken()

                  ; V1.022.48: Check for field access (auto-declaration on first use)
                  ; Syntax: varName.StructType\field = value
                  If TOKEN()\TokenType = #ljBackslash
                     ; Auto-declare struct variable and handle field assignment
                     ; V1.029.89: Force local creation when struct type annotation present
                     ; V1.030.14: Debug - check gCurrentFunctionName during AST struct creation
                     Debug "V1.030.14: AST STRUCT FIELD - structVarName='" + structVarName + "' gCurrentFunctionName='" + gCurrentFunctionName + "' gCodeGenFunction=" + Str(gCodeGenFunction) + " TOKEN().function=" + Str(TOKEN()\function)
                     Protected autoDeclBaseSlot.i = FetchVarOffset(structVarName, 0, 0, #True)
                     Debug "V1.030.14: AST STRUCT CREATED at slot=" + Str(autoDeclBaseSlot) + " name='" + gVarMeta(autoDeclBaseSlot)\name + "' paramOffset=" + Str(gVarMeta(autoDeclBaseSlot)\paramOffset)
                     gVarMeta(autoDeclBaseSlot)\flags = #C2FLAG_STRUCT | #C2FLAG_IDENT
                     gVarMeta(autoDeclBaseSlot)\structType = structTypeName
                     gVarMeta(autoDeclBaseSlot)\elementSize = structDef\totalSize

                     ; V1.029.42: REMOVED multi-slot allocation - incompatible with V1.029.40 \ptr storage
                     ; With \ptr storage, each struct uses only 1 slot (base slot stores pointer to data).
                     ; Field access is handled through the base slot's structType lookup.

                     CompilerIf #DEBUG
                        Debug "V1.022.48: Auto-declared struct '" + structVarName + "' of type '" + structTypeName + "' at slot " + Str(autoDeclBaseSlot)
                     CompilerEndIf

                     ; Move past backslash
                     NextToken()

                     ; Parse field name (may be chained: field\subfield\...)
                     If TOKEN()\TokenType <> #ljIDENT
                        SetError("Expected field name after '\\'", #C2ERR_EXPECTED_STATEMENT)
                        gStack - 1
                        ProcedureReturn 0
                     EndIf

                     Protected autoDeclFieldName.s = TOKEN()\value
                     Protected autoDeclFieldOffset.i = -1
                     Protected autoDeclFieldType.w = #C2FLAG_INT
                     Protected autoDeclFieldStructType.s = ""
                     Protected autoDeclActualSlot.i = autoDeclBaseSlot
                     Protected autoDeclFullName.s = structVarName + "\" + autoDeclFieldName
                     Protected autoDeclCurrentStructType.s = structTypeName

                     ; Look up field in struct definition
                     If FindMapElement(mapStructDefs(), autoDeclCurrentStructType)
                        ForEach mapStructDefs()\fields()
                           If LCase(mapStructDefs()\fields()\name) = LCase(autoDeclFieldName)
                              autoDeclFieldOffset = mapStructDefs()\fields()\offset
                              autoDeclFieldType = mapStructDefs()\fields()\fieldType
                              autoDeclFieldStructType = mapStructDefs()\fields()\structType
                              Break
                           EndIf
                        Next
                     EndIf

                     If autoDeclFieldOffset < 0
                        SetError("Unknown field '" + autoDeclFieldName + "' in struct '" + autoDeclCurrentStructType + "'", #C2ERR_EXPECTED_STATEMENT)
                        gStack - 1
                        ProcedureReturn 0
                     EndIf

                     autoDeclActualSlot = autoDeclBaseSlot + autoDeclFieldOffset
                     NextToken()  ; Move past field name

                     ; Handle nested struct chains (outer\inner\field)
                     While autoDeclFieldStructType <> ""
                        If TOKEN()\TokenType = #ljBackslash
                           NextToken()  ; Move past '\'
                           If TOKEN()\TokenType = #ljIDENT
                              Protected autoDeclNestedField.s = TOKEN()\value
                              NextToken()

                              If FindMapElement(mapStructDefs(), autoDeclFieldStructType)
                                 Protected autoDeclNestedFound.b = #False
                                 ForEach mapStructDefs()\fields()
                                    If LCase(mapStructDefs()\fields()\name) = LCase(autoDeclNestedField)
                                       autoDeclActualSlot = autoDeclActualSlot + mapStructDefs()\fields()\offset
                                       autoDeclFieldType = mapStructDefs()\fields()\fieldType
                                       autoDeclFullName = autoDeclFullName + "\" + autoDeclNestedField
                                       autoDeclFieldStructType = mapStructDefs()\fields()\structType
                                       autoDeclNestedFound = #True
                                       Break
                                    EndIf
                                 Next
                                 If Not autoDeclNestedFound
                                    SetError("Unknown field '" + autoDeclNestedField + "' in nested struct", #C2ERR_EXPECTED_STATEMENT)
                                    gStack - 1
                                    ProcedureReturn 0
                                 EndIf
                              EndIf
                           Else
                              SetError("Expected field name after '\\'", #C2ERR_EXPECTED_STATEMENT)
                              gStack - 1
                              ProcedureReturn 0
                           EndIf
                        Else
                           Break  ; No more backslashes
                        EndIf
                     Wend

                     ; Set up field metadata
                     If autoDeclActualSlot <> autoDeclBaseSlot
                        gVarMeta(autoDeclActualSlot)\name = autoDeclFullName
                        gVarMeta(autoDeclActualSlot)\flags = autoDeclFieldType | #C2FLAG_IDENT
                        gVarMeta(autoDeclActualSlot)\paramOffset = -1
                     EndIf

                     ; Create lvalue node
                     *v = Makeleaf(#ljIDENT, autoDeclFullName)
                     If autoDeclFieldType & #C2FLAG_FLOAT
                        *v\TypeHint = #ljFLOAT
                     ElseIf autoDeclFieldType & #C2FLAG_STR
                        *v\TypeHint = #ljSTRING
                     Else
                        *v\TypeHint = #ljINT
                     EndIf

                     ; Expect assignment operator
                     Protected autoDeclAssignOp.i = TOKEN()\TokenExtra
                     If autoDeclAssignOp <> #ljASSIGN And autoDeclAssignOp <> #ljADD_ASSIGN And autoDeclAssignOp <> #ljSUB_ASSIGN And autoDeclAssignOp <> #ljMUL_ASSIGN And autoDeclAssignOp <> #ljDIV_ASSIGN And autoDeclAssignOp <> #ljMOD_ASSIGN
                        SetError("Expected assignment operator", #C2ERR_EXPECTED_STATEMENT)
                        gStack - 1
                        ProcedureReturn 0
                     EndIf
                     NextToken()

                     ; Parse RHS
                     *e = expr(0)

                     ; Handle compound assignment
                     If autoDeclAssignOp <> #ljASSIGN
                        Protected *autoDeclLhsCopy.stTree = Makeleaf(#ljIDENT, autoDeclFullName)
                        *autoDeclLhsCopy\TypeHint = *v\TypeHint
                        Protected autoDeclBinaryOp.i
                        Select autoDeclAssignOp
                           Case #ljADD_ASSIGN : autoDeclBinaryOp = #ljADD
                           Case #ljSUB_ASSIGN : autoDeclBinaryOp = #ljSUBTRACT
                           Case #ljMUL_ASSIGN : autoDeclBinaryOp = #ljMULTIPLY
                           Case #ljDIV_ASSIGN : autoDeclBinaryOp = #ljDIVIDE
                           Case #ljMOD_ASSIGN : autoDeclBinaryOp = #ljMOD
                        EndSelect
                        *e = MakeNode(autoDeclBinaryOp, *autoDeclLhsCopy, *e)
                     EndIf

                     *p = MakeNode(#ljASSIGN, *v, *e)
                     Expect("struct field assignment", #ljSemi)

                     ; Set flag to skip rest of identifier handling
                     autoDeclarredStruct = #True
                  ElseIf TOKEN()\TokenExtra = #ljASSIGN
                     ; Traditional: varName.StructType = {...} or struct copy: varName.StructType = srcStruct
                     NextToken()

                     ; V1.023.24: Support struct copy syntax: v2.StructType = v1
                     ; V1.029.2: Also support function call: v.StructType = funcCall()
                     If TOKEN()\TokenType = #ljIDENT
                        ; Peek ahead to see if it's a function call
                        Protected copyStructSrcName.s = TOKEN()\value
                        Protected savedCopyIdx.i = ListIndex(llTokenList())
                        NextToken()

                        If TOKEN()\TokenExtra = #ljLeftParent
                           ; V1.029.2: It's a function call - parse as expression
                           ; Restore position and parse full expression
                           SelectElement(llTokenList(), savedCopyIdx)

                           ; Allocate base slot for destination struct first
                           ; V1.029.89: Force local creation when struct type annotation present
                           Protected funcCallStructSlot.i = FetchVarOffset(structVarName, 0, 0, #True)

                           ; V1.029.87: Struct variables should ONLY have STRUCT + IDENT flags
                           ; Do NOT include first field's primitive type - that was causing "(String)" display
                           gVarMeta(funcCallStructSlot)\flags = #C2FLAG_STRUCT | #C2FLAG_IDENT
                           gVarMeta(funcCallStructSlot)\structType = structTypeName
                           gVarMeta(funcCallStructSlot)\elementSize = structDef\totalSize

                           ; V1.029.42: REMOVED field slot metadata writing - incompatible with V1.029.40 \ptr storage
                           ; With \ptr storage, each struct uses only 1 slot. Field access is handled
                           ; through the base slot's structType lookup in codegen/FetchVarOffset.

                           ; Parse function call as expression
                           Protected *funcCallExpr.stTree = expr(0)

                           ; Create assignment: structVar = funcCallResult
                           Protected *funcCallDest.stTree = Makeleaf(#ljIDENT, structVarName)
                           *p = MakeNode(#ljASSIGN, *funcCallDest, *funcCallExpr)

                           Expect("struct init from function", #ljSemi)
                           autoDeclarredStruct = #True
                        Else
                           ; Regular struct copy: varName.StructType = srcStruct

                        ; Allocate base slot for destination struct
                        ; V1.029.89: Force local creation when struct type annotation present
                        Protected copyStructDestSlot.i = FetchVarOffset(structVarName, 0, 0, #True)

                        ; V1.029.87: Struct variables should ONLY have STRUCT + IDENT flags
                        ; Do NOT include first field's primitive type - that was causing "(String)" display
                        gVarMeta(copyStructDestSlot)\flags = #C2FLAG_STRUCT | #C2FLAG_IDENT
                        gVarMeta(copyStructDestSlot)\structType = structTypeName
                        gVarMeta(copyStructDestSlot)\elementSize = structDef\totalSize

                        ; V1.029.42: REMOVED field slot metadata writing - incompatible with V1.029.40 \ptr storage
                        ; With \ptr storage, each struct uses only 1 slot. Field access is handled
                        ; through the base slot's structType lookup in codegen/FetchVarOffset.

                        ; Create assignment node: destStruct = srcStruct
                        ; Codegen will detect this is struct-to-struct and emit STRUCTCOPY
                        Protected *copyStructDest.stTree = Makeleaf(#ljIDENT, structVarName)
                        Protected *copyStructSrc.stTree = Makeleaf(#ljIDENT, copyStructSrcName)
                        *p = MakeNode(#ljASSIGN, *copyStructDest, *copyStructSrc)

                        Expect("struct copy", #ljSemi)
                        autoDeclarredStruct = #True
                        EndIf  ; End of If function call / Else struct copy
                     ElseIf TOKEN()\TokenType <> #ljLeftBrace
                        SetError("Expected '{' for struct initialization or identifier for struct copy", #C2ERR_EXPECTED_STATEMENT)
                        gStack - 1
                        ProcedureReturn 0
                     Else
                     NextToken()

                     ; Allocate base slot for struct
                     ; V1.029.89: Force local creation when struct type annotation present
                     Protected structBaseSlot.i = FetchVarOffset(structVarName, 0, 0, #True)
                     ; V1.029.87: Struct variables should ONLY have STRUCT + IDENT flags (no primitive type)
                     gVarMeta(structBaseSlot)\flags = #C2FLAG_STRUCT | #C2FLAG_IDENT
                     gVarMeta(structBaseSlot)\structType = structTypeName
                     gVarMeta(structBaseSlot)\elementSize = structDef\totalSize

                     ; V1.029.40: With \ptr storage, only 1 slot needed (data stored in \ptr)
                     ; Codegen will emit STRUCT_ALLOC lazily on first field access via EmitInt
                     ; V1.029.89: Check if local by variable name (mangled), not paramOffset
                     ; During AST phase, paramOffset may not be assigned yet (happens in codegen)
                     Protected structIsLocal.i = Bool(gCurrentFunctionName <> "" And LCase(Left(gVarMeta(structBaseSlot)\name, Len(gCurrentFunctionName) + 1)) = LCase(gCurrentFunctionName + "_"))
                     Protected structBaseParamOffset.i = gVarMeta(structBaseSlot)\paramOffset

                     ; Build initialization sequence (STRUCT_ALLOC emitted lazily by codegen)
                     *p = 0
                     Protected initSlotOffset.i = 0  ; V1.022.0: Track actual slot offset, not field index

                     ForEach structDef\fields()
                     If TOKEN()\TokenType = #ljRightBrace
                        Break
                     EndIf

                     ; V1.022.0: Handle array field initialization
                     ; V1.022.4: BUG FIX - use structDef\fields() not mapStructDefs()\fields() in loop
                     If structDef\fields()\isArray
                        ; Array field - expect nested {v1, v2, ...} or flat values
                        Protected fieldStoreArrayName.s = structVarName + "\" + structDef\fields()\name
                        Protected baseArrayFieldSlot.i = structBaseSlot + initSlotOffset

                        ; V1.022.14: Preserve struct base slot metadata for offset 0
                        ; STRUCTARRAY_STORE uses embedded slot info, not FetchVarOffset
                        If initSlotOffset > 0
                           gVarMeta(baseArrayFieldSlot)\name = fieldStoreArrayName
                           gVarMeta(baseArrayFieldSlot)\flags = structDef\fields()\fieldType | #C2FLAG_IDENT | #C2FLAG_ARRAY
                           gVarMeta(baseArrayFieldSlot)\paramOffset = -1
                           gVarMeta(baseArrayFieldSlot)\arraySize = structDef\fields()\arraySize
                           gVarMeta(baseArrayFieldSlot)\elementSize = 1
                        EndIf

                        ; Check for nested braces
                        If TOKEN()\TokenType = #ljLeftBrace
                           NextToken()  ; Move past '{'

                           ; Initialize array elements
                           Protected arrElemIdx.i = 0
                           While arrElemIdx < structDef\fields()\arraySize And TOKEN()\TokenType <> #ljRightBrace
                              Protected *arrElemVal.stTree = expr(0)

                              ; Store to array element slot
                              Protected arrElemSlot.i = baseArrayFieldSlot + arrElemIdx
                              Protected arrElemVarName.s = fieldStoreArrayName + "[" + Str(arrElemIdx) + "]"

                              ; V1.022.13: Always set element metadata (array elements never at offset 0)
                              gVarMeta(arrElemSlot)\name = arrElemVarName
                              gVarMeta(arrElemSlot)\flags = structDef\fields()\fieldType | #C2FLAG_IDENT
                              gVarMeta(arrElemSlot)\paramOffset = -1

                              ; V1.022.10: Use STRUCTARRAY_STORE instead of ASSIGN to use correct slots
                              ; Choose store node type based on field type
                              Protected structArrStoreNodeType.i
                              If structDef\fields()\fieldType & #C2FLAG_FLOAT
                                 structArrStoreNodeType = #ljSTRUCTARRAY_STORE_FLOAT
                              ElseIf structDef\fields()\fieldType & #C2FLAG_STR
                                 structArrStoreNodeType = #ljSTRUCTARRAY_STORE_STR
                              Else
                                 structArrStoreNodeType = #ljSTRUCTARRAY_STORE_INT
                              EndIf

                              ; Create index expression (constant for init)
                              Protected *arrIdxExpr.stTree = Makeleaf(#ljINT, Str(arrElemIdx))

                              ; Create struct array store node with embedded slot info
                              ; Format: "structVarSlot|fieldOffset|fieldName"
                              Protected *structArrStoreNode.stTree = MakeNode(structArrStoreNodeType, *arrIdxExpr, *arrElemVal)
                              *structArrStoreNode\value = Str(structBaseSlot) + "|" + Str(initSlotOffset) + "|" + arrElemVarName

                              If *p = 0
                                 *p = *structArrStoreNode
                              Else
                                 *p = MakeNode(#ljSEQ, *p, *structArrStoreNode)
                              EndIf

                              arrElemIdx + 1

                              If TOKEN()\TokenType = #ljComma
                                 NextToken()
                              EndIf
                           Wend

                           If TOKEN()\TokenType <> #ljRightBrace
                              SetError("Expected '}' to close array initialization in struct", #C2ERR_EXPECTED_STATEMENT)
                              gStack - 1
                              ProcedureReturn 0
                           EndIf
                           NextToken()  ; Move past '}'
                        Else
                           SetError("Array field '" + structDef\fields()\name + "' requires {...} initialization", #C2ERR_EXPECTED_STATEMENT)
                           gStack - 1
                           ProcedureReturn 0
                        EndIf

                        initSlotOffset + structDef\fields()\arraySize
                     Else
                        ; Regular scalar field - parse value expression
                        Protected *initVal.stTree = expr(0)

                        ; Create store to field slot using backslash notation
                        ; V1.029.40: With \ptr storage, codegen will emit STRUCT_STORE_* lazily
                        Protected fieldSlot.i = structBaseSlot + initSlotOffset
                        Protected fieldStoreVarName.s = structVarName + "\" + structDef\fields()\name

                        ; V1.029.42: REMOVED field slot metadata writing - incompatible with V1.029.40 \ptr storage
                        ; With \ptr storage, each struct uses only 1 slot (base slot stores pointer to data).
                        ; Writing to base+offset slots was corrupting subsequent struct variables.
                        ; Field access is now handled through the base slot's structType lookup.
                        ; The old code (V1.022.14) wrote to fieldSlot = structBaseSlot + initSlotOffset
                        ; which overwrote the next struct's slot when initSlotOffset > 0.

                        Protected *storeNode.stTree = MakeNode(#ljASSIGN, Makeleaf(#ljIDENT, fieldStoreVarName), *initVal)

                        If *p = 0
                           *p = *storeNode
                        Else
                           *p = MakeNode(#ljSEQ, *p, *storeNode)
                        EndIf

                        initSlotOffset + 1
                     EndIf

                     ; Expect comma or closing brace
                     If TOKEN()\TokenType = #ljComma
                        NextToken()
                     EndIf
                  Next

                  If TOKEN()\TokenType <> #ljRightBrace
                     SetError("Expected '}' to close struct initialization", #C2ERR_EXPECTED_STATEMENT)
                     gStack - 1
                     ProcedureReturn 0
                  EndIf
                  NextToken()

                  ; V1.030.64: If no fields were initialized (empty braces {}), create ASSIGN with #ljStructInit
                  ; This tells codegen to emit STRUCT_ALLOC only, without any store operation
                  ; Previously (V1.029.88), we created a fake field assignment which caused unwanted stores
                  ; The ASSIGN wrapper is needed so codegen's #ljASSIGN handler can process the struct init
                  If *p = 0
                     Protected *structInitLHS.stTree = Makeleaf(#ljIDENT, structVarName)
                     Protected *structInitRHS.stTree = Makeleaf(#ljStructInit, "")
                     *p = MakeNode(#ljASSIGN, *structInitLHS, *structInitRHS)
                  EndIf

                  Expect("struct init", #ljSemi)

                  CompilerIf #DEBUG
                     Debug "Struct variable: " + structVarName + " of type " + structTypeName + " at slot " + Str(structBaseSlot)
                  CompilerEndIf
                     EndIf  ; End of If IDENT / ElseIf not LeftBrace / Else LeftBrace
                  Else
                     ; V1.022.48: Neither backslash nor assignment - error
                     SetError("Expected '\\' for field access or '=' for initialization after '" + structVarName + "." + structTypeName + "'", #C2ERR_EXPECTED_STATEMENT)
                     gStack - 1
                     ProcedureReturn 0
                  EndIf  ; End of If backslash / ElseIf assign
               Else
                  ; Not a struct type after '.', fall through to normal identifier handling
               EndIf
            EndIf

            ; Normal identifier handling (not struct declaration)
            ; Check if this is a function call, increment/decrement, or assignment
            If *p = 0 And Not autoDeclarredStruct
               ; Peek ahead to see if next token is '(', '++', '--', or assignment op
               Protected identName.s = TOKEN()\value
               Protected savedListIndex2.i = ListIndex(llTokenList())
               NextToken()

               If TOKEN()\TokenExtra = #ljLeftParent
               ; It's a function call - parse as expression statement (result is discarded)
               SelectElement(llTokenList(), savedListIndex2)
               *e = expr(0)
               *p = *e
               Expect("Statement", #ljSemi)
            ElseIf TOKEN()\TokenExtra = #ljINC Or TOKEN()\TokenExtra = #ljDEC
               ; It's standalone increment/decrement - parse as expression and discard result
               SelectElement(llTokenList(), savedListIndex2)
               *e = expr(0)
               ; Wrap in SEQ with POP to discard the result value
               *p = MakeNode(#ljSEQ, *e, Makeleaf(#ljPOP, "0"))
               Expect("Statement", #ljSemi)
            Else
               ; It's an assignment statement - restore position and parse normally
               SelectElement(llTokenList(), savedListIndex2)

               *v = Makeleaf( #ljIDENT, TOKEN()\value )
               *v\TypeHint = TOKEN()\typeHint

               ; Track variable type for later lookups in GetExprResultType()
               If *v\TypeHint <> 0
                  Protected varTypeFlags.w = #C2FLAG_INT  ; Default
                  Protected varKey.s = *v\value

                  ; Convert typeHint to type flags
                  If *v\TypeHint = #ljINT
                     varTypeFlags = #C2FLAG_INT
                  ElseIf *v\TypeHint = #ljFLOAT
                     varTypeFlags = #C2FLAG_FLOAT
                  ElseIf *v\TypeHint = #ljSTRING
                     varTypeFlags = #C2FLAG_STR
                  EndIf

                  ; Store both global name and mangled name (if in function)
                  AddMapElement(mapVariableTypes(), varKey)
                  mapVariableTypes() = varTypeFlags

                  If gCurrentFunctionName <> ""
                     Protected mangledKey.s = gCurrentFunctionName + "_" + varKey
                     AddMapElement(mapVariableTypes(), mangledKey)
                     mapVariableTypes() = varTypeFlags
                  EndIf
               EndIf

               NextToken()

               ; Check if this is array indexing
               If TOKEN()\TokenType = #ljLeftBracket
                  ; Array assignment: arr[index] = value
                  NextToken()  ; Skip '['
                  Protected *indexExpr.stTree = expr(0)  ; Parse index expression

                  If TOKEN()\TokenType <> #ljRightBracket
                     SetError( "Expected ']' after array index", #C2ERR_EXPECTED_STATEMENT )
                     gStack - 1
                     ProcedureReturn 0
                  EndIf
                  NextToken()  ; Skip ']'

                  ; Create array index node: left=array var, right=index
                  *v = MakeNode( #ljLeftBracket, *v, *indexExpr )
               EndIf

               ; V1.20.25: Check for pointer field access on lvalue (ptr\i, arr[i]\f, etc.)
               If TOKEN()\TokenType = #ljBackslash
                  ; V1.20.25: Validate pointer type for simple identifiers
                  If *v\NodeType = #ljIDENT
                     Protected ptrSearchKey.s = *v\value
                     Protected ptrIsPointer.b = #False
                     Protected ptrIsParameter.b = #False
                     Protected ptrIsKnownNonPointer.b = #False

                     ; Check in mapVariableTypes if this variable is marked as a pointer
                     If gCurrentFunctionName <> "" And Left(*v\value, 1) <> "$"
                        ; Try mangled name first (local variable)
                        ptrSearchKey = gCurrentFunctionName + "_" + *v\value
                     EndIf

                     If FindMapElement(mapVariableTypes(), ptrSearchKey)
                        If mapVariableTypes() & #C2FLAG_POINTER
                           ptrIsPointer = #True
                        EndIf
                        ; V1.20.34: Don't mark as "known non-pointer" based on inferred types
                     ElseIf ptrSearchKey <> *v\value And FindMapElement(mapVariableTypes(), *v\value)
                        ; Try global name if mangled name not found
                        If mapVariableTypes() & #C2FLAG_POINTER
                           ptrIsPointer = #True
                        EndIf
                        ; V1.20.34: Don't mark as "known non-pointer" based on inferred types
                     EndIf

                     ; V1.20.28: Check if variable is a function parameter
                     If Not ptrIsPointer And Not ptrIsKnownNonPointer And gCurrentFunctionName <> ""
                        ForEach mapModules()
                           If MapKey(mapModules()) = gCurrentFunctionName
                              Protected ptrParamStr.s = mapModules()\params
                              Protected ptrCloseParenPos.i = FindString(ptrParamStr, ")", 1)
                              If ptrCloseParenPos > 0
                                 ptrParamStr = Mid(ptrParamStr, 2, ptrCloseParenPos - 2)
                              Else
                                 ptrParamStr = Mid(ptrParamStr, 2)
                              EndIf
                              ptrParamStr = Trim(ptrParamStr)

                              If ptrParamStr <> ""
                                 Protected ptrParamIdx.i
                                 For ptrParamIdx = 1 To CountString(ptrParamStr, ",") + 1
                                    Protected ptrParam.s = Trim(StringField(ptrParamStr, ptrParamIdx, ","))
                                    Protected ptrParamName.s = ptrParam

                                    ; Extract parameter name (strip type suffix if present)
                                    If FindString(ptrParam, ".f", 1, #PB_String_NoCase)
                                       ptrParamName = Left(ptrParam, FindString(ptrParam, ".f", 1, #PB_String_NoCase) - 1)
                                    ElseIf FindString(ptrParam, ".d", 1, #PB_String_NoCase)
                                       ptrParamName = Left(ptrParam, FindString(ptrParam, ".d", 1, #PB_String_NoCase) - 1)
                                    ElseIf FindString(ptrParam, ".s", 1, #PB_String_NoCase)
                                       ptrParamName = Left(ptrParam, FindString(ptrParam, ".s", 1, #PB_String_NoCase) - 1)
                                    ElseIf FindString(ptrParam, ".i", 1, #PB_String_NoCase)
                                       ptrParamName = Left(ptrParam, FindString(ptrParam, ".i", 1, #PB_String_NoCase) - 1)
                                    EndIf

                                    If LCase(ptrParamName) = LCase(*v\value)
                                       ptrIsParameter = #True
                                       Break
                                    EndIf
                                 Next
                              EndIf
                              Break
                           EndIf
                        Next
                     EndIf

                     ; V1.20.28: Require pointer type for simple identifiers
                     ; Allow for function parameters (type determined at runtime)
                     If ptrIsKnownNonPointer
                        SetError("Variable '" + *v\value + "' is not a pointer - cannot use pointer field access (\i, \f, \s)", #C2ERR_EXPECTED_STATEMENT)
                        gStack - 1
                        ProcedureReturn 0
                     EndIf
                  EndIf
                  ; Note: For array indexing expressions (*v\NodeType = #ljLeftBracket),
                  ; we allow the syntax and rely on runtime type checking

                  NextToken()  ; Skip '\'

                  ; Check for field type: i, f, s (pointer) or struct field name
                  If TOKEN()\value = "i"
                     *v = MakeNode( #ljPTRFIELD_I, *v, 0 )
                     NextToken()
                  ElseIf TOKEN()\value = "f"
                     *v = MakeNode( #ljPTRFIELD_F, *v, 0 )
                     NextToken()
                  ElseIf TOKEN()\value = "s"
                     *v = MakeNode( #ljPTRFIELD_S, *v, 0 )
                     NextToken()
                  Else
                     ; V1.022.45: Check for array of structs assignment: arr[i]\field = value
                     ; If *v is an array access node (#ljLeftBracket), check if underlying array is struct array
                     If *v\NodeType = #ljLeftBracket And *v\left And *v\left\NodeType = #ljIDENT
                        Protected aosStmtFieldName.s = TOKEN()\value
                        Protected aosStmtArrayName.s = *v\left\value
                        Protected aosStmtArraySlot.i = -1
                        Protected aosStmtStructType.s = ""
                        Protected aosStmtIdx.i

                        ; Find array variable
                        For aosStmtIdx = 0 To gnLastVariable - 1
                           If LCase(gVarMeta(aosStmtIdx)\name) = LCase(aosStmtArrayName)
                              aosStmtArraySlot = aosStmtIdx
                              Break
                           EndIf
                        Next

                        ; Check if it's a struct array
                        If aosStmtArraySlot >= 0 And gVarMeta(aosStmtArraySlot)\structType <> ""
                           aosStmtStructType = gVarMeta(aosStmtArraySlot)\structType

                           ; Look up field in struct definition
                           If FindMapElement(mapStructDefs(), aosStmtStructType)
                              Protected aosStmtFieldOffset.i = -1
                              Protected aosStmtFieldType.w = #C2FLAG_INT
                              Protected aosStmtFoundField.b = #False
                              Protected aosStmtFieldStructType.s = ""  ; V1.022.49: For nested structs

                              ForEach mapStructDefs()\fields()
                                 If LCase(mapStructDefs()\fields()\name) = LCase(aosStmtFieldName)
                                    aosStmtFieldOffset = mapStructDefs()\fields()\offset
                                    aosStmtFieldType = mapStructDefs()\fields()\fieldType
                                    aosStmtFieldStructType = mapStructDefs()\fields()\structType  ; V1.022.49
                                    aosStmtFoundField = #True
                                    Break
                                 EndIf
                              Next

                              If aosStmtFoundField
                                 NextToken()  ; Move past field name

                                 ; V1.022.49: Handle nested struct chains (arr[i]\nestedStruct\field)
                                 While aosStmtFieldStructType <> "" And TOKEN()\TokenType = #ljBackslash
                                    NextToken()  ; Move past backslash
                                    If TOKEN()\TokenType = #ljIDENT
                                       Protected aosNestedFieldName.s = TOKEN()\value
                                       Protected aosNestedFoundField.b = #False

                                       If FindMapElement(mapStructDefs(), aosStmtFieldStructType)
                                          ForEach mapStructDefs()\fields()
                                             If LCase(mapStructDefs()\fields()\name) = LCase(aosNestedFieldName)
                                                aosStmtFieldOffset = aosStmtFieldOffset + mapStructDefs()\fields()\offset
                                                aosStmtFieldType = mapStructDefs()\fields()\fieldType
                                                aosStmtFieldStructType = mapStructDefs()\fields()\structType
                                                aosNestedFoundField = #True
                                                Break
                                             EndIf
                                          Next
                                       EndIf

                                       If Not aosNestedFoundField
                                          SetError("Field '" + aosNestedFieldName + "' not found in nested struct", #C2ERR_EXPECTED_STATEMENT)
                                          gStack - 1
                                          ProcedureReturn 0
                                       EndIf
                                       NextToken()  ; Move past nested field name
                                    Else
                                       SetError("Expected field name after '\\'", #C2ERR_EXPECTED_STATEMENT)
                                       gStack - 1
                                       ProcedureReturn 0
                                    EndIf
                                 Wend

                                 ; Create struct array field node for assignment
                                 Protected aosStmtElementSize.i = gVarMeta(aosStmtArraySlot)\elementSize
                                 Protected *aosStmtFieldNode.stTree

                                 If aosStmtFieldType & #C2FLAG_FLOAT
                                    *aosStmtFieldNode = MakeNode(#nd_StructArrayField_F, *v, 0)
                                 ElseIf aosStmtFieldType & #C2FLAG_STR
                                    *aosStmtFieldNode = MakeNode(#nd_StructArrayField_S, *v, 0)
                                 Else
                                    *aosStmtFieldNode = MakeNode(#nd_StructArrayField_I, *v, 0)
                                 EndIf
                                 *aosStmtFieldNode\value = Str(aosStmtElementSize) + "|" + Str(aosStmtFieldOffset)
                                 *v = *aosStmtFieldNode
                              Else
                                 SetError("Field '" + aosStmtFieldName + "' not found in struct type '" + aosStmtStructType + "'", #C2ERR_EXPECTED_STATEMENT)
                                 gStack - 1
                                 ProcedureReturn 0
                              EndIf
                           Else
                              SetError("Struct type '" + aosStmtStructType + "' not defined", #C2ERR_EXPECTED_STATEMENT)
                              gStack - 1
                              ProcedureReturn 0
                           EndIf
                        Else
                           ; Not a struct array - continue with existing logic below
                        EndIf
                     EndIf

                     ; V1.021.0: Check if this is struct field access (skip if we already handled array of structs)
                     If *v\NodeType <> #nd_StructArrayField_I And *v\NodeType <> #nd_StructArrayField_F And *v\NodeType <> #nd_StructArrayField_S
                        Protected stmtStructFieldName.s = TOKEN()\value
                        Protected stmtStructVarSlot.i = -1
                        Protected stmtStructVarIdx.i
                        Protected stmtStructVarName.s = *v\value
                        Protected stmtMangledStructName.s = ""

                        ; V1.030.37: Handle combined declaration+field access (e.g., "rect.Rectangle\x")
                        ; If stmtStructVarName contains a DOT, it's a type annotation that needs auto-creation
                        Protected stmtTypeAnnotationDot.i = FindString(stmtStructVarName, ".")
                        If stmtTypeAnnotationDot > 0 And stmtTypeAnnotationDot < Len(stmtStructVarName)
                           Protected stmtTypeBaseName.s = Left(stmtStructVarName, stmtTypeAnnotationDot - 1)
                           Protected stmtTypeTypeName.s = Mid(stmtStructVarName, stmtTypeAnnotationDot + 1)
                           ; Check if type part is a known struct type (not primitive .i, .f, .s, .d)
                           If LCase(stmtTypeTypeName) <> "i" And LCase(stmtTypeTypeName) <> "f" And LCase(stmtTypeTypeName) <> "s" And LCase(stmtTypeTypeName) <> "d"
                              If FindMapElement(mapStructDefs(), stmtTypeTypeName)
                                 ; This IS a struct type annotation - auto-create the struct variable
                                 Protected stmtAutoCreateName.s = stmtTypeBaseName
                                 If gCurrentFunctionName <> ""
                                    stmtAutoCreateName = gCurrentFunctionName + "_" + stmtTypeBaseName
                                 EndIf
                                 ; Check if variable already exists
                                 Protected stmtAutoSlot.i = -1
                                 Protected stmtAutoIdx.i
                                 For stmtAutoIdx = 1 To gnLastVariable - 1
                                    If LCase(gVarMeta(stmtAutoIdx)\name) = LCase(stmtAutoCreateName)
                                       stmtAutoSlot = stmtAutoIdx
                                       Break
                                    EndIf
                                 Next
                                 ; Create if not exists
                                 If stmtAutoSlot < 0
                                    stmtAutoSlot = gnLastVariable
                                    gnLastVariable + 1
                                    gVarMeta(stmtAutoSlot)\name = stmtAutoCreateName
                                    gVarMeta(stmtAutoSlot)\flags = #C2FLAG_STRUCT | #C2FLAG_IDENT
                                    gVarMeta(stmtAutoSlot)\structType = stmtTypeTypeName
                                    gVarMeta(stmtAutoSlot)\elementSize = mapStructDefs()\totalSize
                                    gVarMeta(stmtAutoSlot)\structFieldBase = -1
                                    gVarMeta(stmtAutoSlot)\paramOffset = -1
                                    CompilerIf #DEBUG
                                       Debug "V1.030.37: Auto-created struct '" + stmtAutoCreateName + "' of type " + stmtTypeTypeName + " at slot " + Str(stmtAutoSlot)
                                    CompilerEndIf
                                 EndIf
                                 ; Update stmtStructVarName to just the base name for subsequent lookup
                                 stmtStructVarName = stmtTypeBaseName
                              EndIf
                           EndIf
                        EndIf

                        ; V1.022.123: Search for struct variable - LOCAL (mangled) name FIRST, then global
                        ; Skip slot 0 (reserved for ?discard?)
                        If gCurrentFunctionName <> ""
                           stmtMangledStructName = gCurrentFunctionName + "_" + stmtStructVarName
                           For stmtStructVarIdx = 1 To gnLastVariable - 1
                              If LCase(gVarMeta(stmtStructVarIdx)\name) = LCase(stmtMangledStructName) And (gVarMeta(stmtStructVarIdx)\flags & #C2FLAG_STRUCT)
                                 stmtStructVarSlot = stmtStructVarIdx
                                 Break
                              EndIf
                           Next
                        EndIf

                        ; V1.022.123: If not found as local, search for global struct (skip slot 0)
                        If stmtStructVarSlot < 0
                           For stmtStructVarIdx = 1 To gnLastVariable - 1
                              If LCase(gVarMeta(stmtStructVarIdx)\name) = LCase(stmtStructVarName) And (gVarMeta(stmtStructVarIdx)\flags & #C2FLAG_STRUCT)
                                 stmtStructVarSlot = stmtStructVarIdx
                                 Break
                              EndIf
                           Next
                        EndIf

                        If stmtStructVarSlot >= 0
                        ; Found struct variable - look up field
                        Protected stmtStructTypeName.s = gVarMeta(stmtStructVarSlot)\structType

                        If FindMapElement(mapStructDefs(), stmtStructTypeName)
                           Protected stmtFieldOffset.i = -1
                           Protected stmtFieldType.w = 0
                           Protected stmtFieldIsArray.b = #False
                           Protected stmtFieldArraySize.i = 0

                           ForEach mapStructDefs()\fields()
                              If LCase(mapStructDefs()\fields()\name) = LCase(stmtStructFieldName)
                                 stmtFieldOffset = mapStructDefs()\fields()\offset
                                 stmtFieldType = mapStructDefs()\fields()\fieldType
                                 stmtFieldIsArray = mapStructDefs()\fields()\isArray
                                 stmtFieldArraySize = mapStructDefs()\fields()\arraySize
                                 Break
                              EndIf
                           Next

                           If stmtFieldOffset >= 0
                              NextToken()  ; Move past field name

                              ; V1.022.4: Check if this is an array field assignment
                              If stmtFieldIsArray
                                 ; Array field - must have [index]
                                 If TOKEN()\TokenType = #ljLeftBracket
                                    NextToken()  ; Move past '['

                                    ; Parse array index expression
                                    Protected *stmtArrayIdxExpr.stTree = expr(0)

                                    If TOKEN()\TokenType <> #ljRightBracket
                                       SetError("Expected ']' after array index in struct field assignment", #C2ERR_EXPECTED_STATEMENT)
                                       gStack - 1
                                       ProcedureReturn 0
                                    EndIf
                                    NextToken()  ; Move past ']'

                                    ; Check for assignment operator
                                    Protected stmtArrayAssignOp.i = TOKEN()\TokenExtra
                                    If stmtArrayAssignOp <> #ljASSIGN And stmtArrayAssignOp <> #ljADD_ASSIGN And stmtArrayAssignOp <> #ljSUB_ASSIGN And stmtArrayAssignOp <> #ljMUL_ASSIGN And stmtArrayAssignOp <> #ljDIV_ASSIGN And stmtArrayAssignOp <> #ljMOD_ASSIGN
                                       SetError("Expected assignment operator after struct array field", #C2ERR_EXPECTED_STATEMENT)
                                       gStack - 1
                                       ProcedureReturn 0
                                    EndIf
                                    NextToken()  ; Move past assignment operator

                                    ; Parse RHS expression
                                    Protected *stmtArrayRHS.stTree = expr(0)

                                    ; Handle compound assignment for struct array fields
                                    If stmtArrayAssignOp <> #ljASSIGN
                                       ; Compound assignment - need to read current value first
                                       Protected stmtArrayFetchNodeType.i
                                       If stmtFieldType & #C2FLAG_FLOAT
                                          stmtArrayFetchNodeType = #ljSTRUCTARRAY_FETCH_FLOAT
                                       ElseIf stmtFieldType & #C2FLAG_STR
                                          stmtArrayFetchNodeType = #ljSTRUCTARRAY_FETCH_STR
                                       Else
                                          stmtArrayFetchNodeType = #ljSTRUCTARRAY_FETCH_INT
                                       EndIf

                                       ; Create fetch node to get current value (need duplicate index)
                                       Protected *stmtArrayIdxExprCopy.stTree = MakeNode(*stmtArrayIdxExpr\NodeType, *stmtArrayIdxExpr\left, *stmtArrayIdxExpr\right)
                                       *stmtArrayIdxExprCopy\value = *stmtArrayIdxExpr\value
                                       *stmtArrayIdxExprCopy\TypeHint = *stmtArrayIdxExpr\TypeHint

                                       Protected *stmtArrayFetchNode.stTree = MakeNode(stmtArrayFetchNodeType, *stmtArrayIdxExprCopy, 0)
                                       *stmtArrayFetchNode\value = Str(stmtStructVarSlot) + "|" + Str(stmtFieldOffset) + "|" + stmtStructVarName + "\" + stmtStructFieldName

                                       ; Apply compound operation
                                       Protected compoundOp.i
                                       Select stmtArrayAssignOp
                                          Case #ljADD_ASSIGN : compoundOp = #ljADD
                                          Case #ljSUB_ASSIGN : compoundOp = #ljSUBTRACT
                                          Case #ljMUL_ASSIGN : compoundOp = #ljMULTIPLY
                                          Case #ljDIV_ASSIGN : compoundOp = #ljDIVIDE
                                          Case #ljMOD_ASSIGN : compoundOp = #ljMOD
                                       EndSelect

                                       *stmtArrayRHS = MakeNode(compoundOp, *stmtArrayFetchNode, *stmtArrayRHS)
                                    EndIf

                                    ; Generate struct array field store
                                    Protected stmtArrayStoreNodeType.i
                                    If stmtFieldType & #C2FLAG_FLOAT
                                       stmtArrayStoreNodeType = #ljSTRUCTARRAY_STORE_FLOAT
                                    ElseIf stmtFieldType & #C2FLAG_STR
                                       stmtArrayStoreNodeType = #ljSTRUCTARRAY_STORE_STR
                                    Else
                                       stmtArrayStoreNodeType = #ljSTRUCTARRAY_STORE_INT
                                    EndIf

                                    ; Create struct array store node
                                    ; Format: value = "structVarSlot|fieldOffset|fieldName"
                                    ; Left child = index expr, Right child = value to store
                                    *p = MakeNode(stmtArrayStoreNodeType, *stmtArrayIdxExpr, *stmtArrayRHS)
                                    *p\value = Str(stmtStructVarSlot) + "|" + Str(stmtFieldOffset) + "|" + stmtStructVarName + "\" + stmtStructFieldName

                                    Expect("struct array field assignment", #ljSemi)

                                 Else
                                    SetError("Array field '" + stmtStructFieldName + "' requires index [n]", #C2ERR_EXPECTED_STATEMENT)
                                    gStack - 1
                                    ProcedureReturn 0
                                 EndIf
                              Else
                                 ; Regular scalar field assignment
                                 ; V1.022.47: May be nested struct - handle field chains
                                 Protected stmtActualFieldSlot.i = stmtStructVarSlot + stmtFieldOffset
                                 Protected stmtFieldVarName.s = stmtStructVarName + "\" + stmtStructFieldName
                                 Protected stmtFieldStructType.s = ""
                                 Protected stmtChainedFieldType.w = stmtFieldType
                                 Protected stmtChainDone.b = #False

                                 ; Check if this field is a nested struct
                                 ForEach mapStructDefs()\fields()
                                    If LCase(mapStructDefs()\fields()\name) = LCase(stmtStructFieldName)
                                       stmtFieldStructType = mapStructDefs()\fields()\structType
                                       Break
                                    EndIf
                                 Next

                                 ; V1.022.47: Handle nested struct field chains (outer\inner\field)
                                 While stmtFieldStructType <> "" And Not stmtChainDone
                                    ; Check if there's another backslash for nested field access
                                    If TOKEN()\TokenType = #ljBackslash
                                       NextToken()  ; Move past '\'

                                       If TOKEN()\TokenType = #ljIDENT
                                          Protected stmtNestedFieldName.s = TOKEN()\value
                                          NextToken()  ; Move past field name

                                          ; Look up the nested struct definition
                                          If FindMapElement(mapStructDefs(), stmtFieldStructType)
                                             Protected stmtNestedFieldFound.b = #False
                                             ForEach mapStructDefs()\fields()
                                                If LCase(mapStructDefs()\fields()\name) = LCase(stmtNestedFieldName)
                                                   ; Found the nested field
                                                   stmtActualFieldSlot = stmtActualFieldSlot + mapStructDefs()\fields()\offset
                                                   stmtChainedFieldType = mapStructDefs()\fields()\fieldType
                                                   stmtFieldVarName = stmtFieldVarName + "\" + stmtNestedFieldName
                                                   stmtFieldStructType = mapStructDefs()\fields()\structType  ; For further nesting
                                                   stmtNestedFieldFound = #True
                                                   Break
                                                EndIf
                                             Next

                                             If Not stmtNestedFieldFound
                                                SetError("Unknown field '" + stmtNestedFieldName + "' in nested struct '" + stmtFieldStructType + "'", #C2ERR_EXPECTED_STATEMENT)
                                                gStack - 1
                                                ProcedureReturn 0
                                             EndIf
                                          Else
                                             SetError("Nested struct type '" + stmtFieldStructType + "' not defined", #C2ERR_EXPECTED_STATEMENT)
                                             gStack - 1
                                             ProcedureReturn 0
                                          EndIf
                                       Else
                                          SetError("Expected field name after '\\' in nested struct access", #C2ERR_EXPECTED_STATEMENT)
                                          gStack - 1
                                          ProcedureReturn 0
                                       EndIf
                                    Else
                                       ; No more backslashes - chain is done
                                       stmtChainDone = #True
                                    EndIf
                                 Wend

                                 ; Ensure field slot has metadata
                                 If gVarMeta(stmtActualFieldSlot)\name = ""
                                    gVarMeta(stmtActualFieldSlot)\name = stmtFieldVarName
                                    gVarMeta(stmtActualFieldSlot)\flags = stmtChainedFieldType | #C2FLAG_IDENT
                                    gVarMeta(stmtActualFieldSlot)\paramOffset = -1
                                 EndIf

                                 ; Replace *v with field identifier
                                 *v = Makeleaf(#ljIDENT, stmtFieldVarName)
                                 If stmtChainedFieldType & #C2FLAG_FLOAT
                                    *v\TypeHint = #ljFLOAT
                                 ElseIf stmtChainedFieldType & #C2FLAG_STR
                                    *v\TypeHint = #ljSTRING
                                 Else
                                    *v\TypeHint = #ljINT
                                 EndIf
                              EndIf
                           Else
                              SetError("Unknown field '" + stmtStructFieldName + "' in struct '" + stmtStructTypeName + "'", #C2ERR_EXPECTED_STATEMENT)
                              gStack - 1
                              ProcedureReturn 0
                           EndIf
                        Else
                           SetError("Struct type '" + stmtStructTypeName + "' not defined", #C2ERR_EXPECTED_STATEMENT)
                           gStack - 1
                           ProcedureReturn 0
                        EndIf
                     Else
                        ; V1.022.56: Deferred struct pointer field access for assignment LHS
                        ; Variable not found as struct at parse time - create deferred node
                        ; Will be resolved during codegen when pointsToStructType is known
                        NextToken()  ; Move past field name

                        ; Create deferred struct pointer node for assignment LHS
                        ; V1.022.59: Set TypeHint = 0 to prevent premature type conversion
                        ; Codegen will determine actual type from struct definition
                        *v = Makeleaf(#ljPTRSTRUCTFETCH_INT, stmtStructVarName + "|" + stmtStructFieldName)
                        *v\TypeHint = 0  ; Unknown at parse time - codegen will resolve
                     EndIf
                  EndIf
               EndIf
               EndIf  ; V1.022.45: Close backslash check (If TOKEN()\TokenType = #ljBackslash at line 1624)

               ; V1.022.4: Skip normal assignment if we already handled struct array field assignment
               If *p = 0
               ; Check for assignment or compound assignment (=, +=, -=, *=, /=, %=)
               Protected assignOp.i = TOKEN()\TokenExtra
               If assignOp <> #ljASSIGN And assignOp <> #ljADD_ASSIGN And assignOp <> #ljSUB_ASSIGN And assignOp <> #ljMUL_ASSIGN And assignOp <> #ljDIV_ASSIGN And assignOp <> #ljMOD_ASSIGN
                  SetError("Expected assignment operator (=, +=, -=, *=, /=, %=)", #C2ERR_EXPECTED_STATEMENT)
                  gStack - 1
                  ProcedureReturn 0
               EndIf
               NextToken()  ; Skip assignment operator

               ; Parse right-hand side using expr() - handles all cases including nested calls
               *e = expr( 0 )

               ; V1.18.13: Type inference - if variable has no explicit type suffix, infer from RHS
               ; V1.020.033: Only store type inference for variables assigned from KNOWN sources
               ; Don't store type for variables assigned from unknown identifiers (could be pointers)
               ; V1.020.100: Skip type inference for pointer operations (GETADDR, PTRFETCH, etc.)
               ; V1.020.100: Validate *e is a proper heap pointer (> 4096) before accessing fields
               If *v\TypeHint = 0 And *e And *e > 4096 And assignOp = #ljASSIGN
                  ; V1.020.100: Skip type inference for pointer/address operations
                  If *e\NodeType = #ljGETADDR Or *e\NodeType = #ljGETADDRF Or *e\NodeType = #ljGETADDRS Or *e\NodeType = #ljGETARRAYADDR Or *e\NodeType = #ljGETARRAYADDRF Or *e\NodeType = #ljGETARRAYADDRS Or *e\NodeType = #ljPTRFETCH Or *e\NodeType = #ljPTRFIELD_I Or *e\NodeType = #ljPTRFIELD_F Or *e\NodeType = #ljPTRFIELD_S
                     ; Skip type inference - these are pointer operations
                  Else
                     inferredType = GetExprResultType(*e)
                     inferredHint = 0
                     inferredKey = *v\value

                  ; Convert type flags to typeHint
                  If inferredType & #C2FLAG_FLOAT
                     inferredHint = #ljFLOAT
                  ElseIf inferredType & #C2FLAG_STR
                     inferredHint = #ljSTRING
                  Else
                     inferredHint = #ljINT
                  EndIf

                  ; V1.020.033: Only store inferred type if RHS is NOT an unknown identifier
                  ; If RHS is unknown (like function parameter), don't lock the type - allows pointer operations later
                  shouldStoreInferredType = #True

                  ; Check if RHS is a simple identifier that's not in mapVariableTypes
                  If *e\NodeType = #ljIDENT And (inferredType & #C2FLAG_POINTER) = 0
                     rhsIdentKey = *e\value
                     rhsIdentFound = #False

                     ; Check if RHS identifier exists in mapVariableTypes
                     If gCurrentFunctionName <> "" And Left(*e\value, 1) <> "$"
                        rhsIdentKey = gCurrentFunctionName + "_" + *e\value
                     EndIf

                     If FindMapElement(mapVariableTypes(), rhsIdentKey)
                        rhsIdentFound = #True
                     ElseIf rhsIdentKey <> *e\value And FindMapElement(mapVariableTypes(), *e\value)
                        rhsIdentFound = #True
                     EndIf

                     ; If RHS is unknown, don't store LHS type (leave it unknown for flexibility)
                     If Not rhsIdentFound
                        shouldStoreInferredType = #False
                     EndIf
                  EndIf

                  ; Store inferred type in mapVariableTypes ONLY on first assignment
                  ; (for simple variables only, not arrays)
                  ; Only if we're confident about the type (not from unknown source)
                  If *v\NodeType = #ljIDENT And shouldStoreInferredType
                     ; Check if this variable has already been type-inferred
                     If Not FindMapElement(mapVariableTypes(), inferredKey)
                        ; First assignment - store inferred type (locks the type)
                        AddMapElement(mapVariableTypes(), inferredKey)
                        mapVariableTypes() = inferredType
                     EndIf

                     If gCurrentFunctionName <> ""
                        inferredMangledKey = gCurrentFunctionName + "_" + inferredKey
                        If Not FindMapElement(mapVariableTypes(), inferredMangledKey)
                           ; First assignment - store inferred type (locks the type)
                           AddMapElement(mapVariableTypes(), inferredMangledKey)
                           mapVariableTypes() = inferredType
                        EndIf
                     EndIf

                     ; NOTE: Do NOT set *v\TypeHint here! TypeHint should ONLY reflect explicit
                     ; type suffixes from source code (.f, .s, .i), not inferred types.
                     ; Type conversion logic uses gVarMeta flags, not TypeHint.
                  EndIf
                  EndIf  ; V1.020.100: End of Else block for pointer operations check
               EndIf

               ; For compound assignments, expand to: var = var OP rhs
               If assignOp <> #ljASSIGN
                  ; Create copy of LHS for the binary operation
                  ; For simple vars, just create another leaf node
                  ; For arrays (arr[idx]), need to duplicate the whole subtree
                  If *v\NodeType = #ljLeftBracket
                     ; Array indexing - need to duplicate: arr[idx] OP= rhs becomes arr[idx] = arr[idx] OP rhs
                     ; We already have arr[idx] in *v, need to make a copy for RHS
                     *lhsCopy = MakeNode(#ljLeftBracket, Makeleaf(#ljIDENT, *v\left\value), *v\right)
                     *lhsCopy\left\TypeHint = *v\left\TypeHint
                  Else
                     ; Simple variable
                     *lhsCopy = Makeleaf(#ljIDENT, *v\value)
                     *lhsCopy\TypeHint = *v\TypeHint
                  EndIf

                  ; Determine binary operator based on compound assignment
                  Select assignOp
                     Case #ljADD_ASSIGN
                        binaryOp = #ljADD
                     Case #ljSUB_ASSIGN
                        binaryOp = #ljSUBTRACT
                     Case #ljMUL_ASSIGN
                        binaryOp = #ljMULTIPLY
                     Case #ljDIV_ASSIGN
                        binaryOp = #ljDIVIDE
                     Case #ljMOD_ASSIGN
                        binaryOp = #ljMOD
                  EndSelect

                  ; Create binary operation: lhsCopy OP rhs
                  *e = MakeNode(binaryOp, *lhsCopy, *e)
               EndIf

               ; Insert automatic type conversion for assignment if needed
               If *v\TypeHint <> 0 And *e
                  Protected lhsType.w = #C2FLAG_INT
                  Protected rhsType.w = GetExprResultType(*e)

                  ; Convert LHS typeHint to type flags
                  If *v\TypeHint = #ljFLOAT
                     lhsType = #C2FLAG_FLOAT
                  ElseIf *v\TypeHint = #ljSTRING
                     lhsType = #C2FLAG_STR
                  EndIf

                  ; Insert conversion node if types don't match
                  If lhsType <> rhsType
                     If (lhsType & #C2FLAG_FLOAT) And (rhsType & #C2FLAG_INT)
                        ; INT to FLOAT conversion
                        *e = MakeNode(#ljITOF, *e, 0)
                     ElseIf (lhsType & #C2FLAG_INT) And (rhsType & #C2FLAG_FLOAT)
                        ; FLOAT to INT conversion
                        *e = MakeNode(#ljFTOI, *e, 0)
                     ElseIf (lhsType & #C2FLAG_STR) And (rhsType & #C2FLAG_INT)
                        ; INT to STRING conversion
                        *e = MakeNode(#ljITOS, *e, 0)
                     ElseIf (lhsType & #C2FLAG_STR) And (rhsType & #C2FLAG_FLOAT)
                        ; FLOAT to STRING conversion
                        *e = MakeNode(#ljFTOS, *e, 0)
                     EndIf
                  EndIf
               EndIf

               *p = MakeNode( #ljASSIGN, *v, *e )

               Expect( "Assign", #ljSemi )
            EndIf
            EndIf  ; V1.022.4: End of If/ElseIf/Else chain (1559-1572)
            EndIf  ; End of If *p = 0 check (line 1553)

         Case #ljOP
            ; Check if this is a pointer dereference assignment: *ptr = value;
            ; Scanner changes * to PTRFETCH when followed by identifier
            If TOKEN()\TokenExtra = #ljPTRFETCH Or TOKEN()\TokenExtra = #ljMULTIPLY
               ; This is parsed as an expression and then checked for assignment
               Protected *ptrDerefExpr.stTree = expr(0)

               ; Must be followed by assignment operator
               If TOKEN()\TokenExtra <> #ljASSIGN
                  SetError("Expected '=' after pointer dereference", #C2ERR_EXPECTED_STATEMENT)
                  gStack - 1
                  ProcedureReturn 0
               EndIf
               NextToken()  ; Skip '='

               ; Parse right-hand side
               *e = expr(0)

               ; Create assignment node: *ptrDerefExpr = *e
               *p = MakeNode(#ljASSIGN, *ptrDerefExpr, *e)

               Expect("Pointer assignment", #ljSemi)
            Else
               SetError("Unexpected operator at beginning of statement", #C2ERR_EXPECTED_STATEMENT)
               gStack - 1
               ProcedureReturn 0
            EndIf

         Case #ljWHILE
            NextToken()
            ; Allow optional parentheses around condition
            If TOKEN()\TokenExtra = #ljLeftParent
               *e = paren_expr()
            Else
               *e = expr(0)
            EndIf
            *s = stmt()
            *p = MakeNode( #ljWHILE, *e, *s )

         ; V1.024.0: C-style for loop
         Case #ljFOR
            NextToken()
            ; Expect: for (init; cond; update) body
            ; OR: for init; cond; update body (LJ style without parens)
            hasParen = #False
            If TOKEN()\TokenExtra = #ljLeftParent
               hasParen = #True
               NextToken()
            EndIf

            ; Parse init expression (can be empty)
            ; V1.024.1: Handle variable declarations with type suffix (i.i = 0)
            *init = 0
            If TOKEN()\TokenExtra <> #ljSemi
               ; Check if this is a variable declaration with type suffix
               If TOKEN()\TokenType = #ljIDENT And TOKEN()\typeHint <> 0
                  ; Handle like stmt() does for typed variable declarations
                  *forVar = Makeleaf(#ljIDENT, TOKEN()\value)
                  *forVar\TypeHint = TOKEN()\typeHint

                  ; Track variable type in mapVariableTypes
                  forVarKey = *forVar\value
                  forVarTypeFlags = #C2FLAG_INT  ; Default
                  If *forVar\TypeHint = #ljINT
                     forVarTypeFlags = #C2FLAG_INT
                  ElseIf *forVar\TypeHint = #ljFLOAT
                     forVarTypeFlags = #C2FLAG_FLOAT
                  ElseIf *forVar\TypeHint = #ljSTRING
                     forVarTypeFlags = #C2FLAG_STR
                  EndIf

                  AddMapElement(mapVariableTypes(), forVarKey)
                  mapVariableTypes() = forVarTypeFlags

                  If gCurrentFunctionName <> ""
                     forMangledKey = gCurrentFunctionName + "_" + forVarKey
                     AddMapElement(mapVariableTypes(), forMangledKey)
                     mapVariableTypes() = forVarTypeFlags
                  EndIf

                  NextToken()

                  ; Expect assignment operator
                  If TOKEN()\TokenExtra = #ljASSIGN
                     NextToken()
                     *forVal = expr(0)
                     *init = MakeNode(#ljASSIGN, *forVar, *forVal)
                  Else
                     ; Just the variable reference without assignment
                     *init = *forVar
                  EndIf
               Else
                  ; Regular expression (no type suffix)
                  ; V1.024.23: Handle identifier = value assignments like stmt() does
                  ; expr(0) doesn't handle ASSIGN because it's not a binary operator
                  If TOKEN()\TokenType = #ljIDENT
                     Protected *forIdent.stTree = Makeleaf(#ljIDENT, TOKEN()\value)
                     Protected savedForIdx.i = ListIndex(llTokenList())
                     NextToken()
                     If TOKEN()\TokenExtra = #ljASSIGN
                        ; It's an assignment: ident = value
                        NextToken()
                        *init = MakeNode(#ljASSIGN, *forIdent, expr(0))
                     Else
                        ; Not an assignment, restore and parse as expression
                        SelectElement(llTokenList(), savedForIdx)
                        *init = expr(0)
                     EndIf
                  Else
                     *init = expr(0)
                  EndIf
               EndIf
            EndIf
            Expect("for init", #ljSemi)

            ; Parse condition expression (can be empty - means infinite loop)
            *cond = 0
            If TOKEN()\TokenExtra <> #ljSemi
               *cond = expr(0)
            EndIf
            Expect("for condition", #ljSemi)

            ; Parse update expression (can be empty)
            ; V1.024.26: Handle identifier = value and compound assignments (+=, -=, etc.)
            *update = 0
            If hasParen
               If TOKEN()\TokenExtra <> #ljRightParent
                  ; Check if this is an assignment: ident = value or ident += value, etc.
                  If TOKEN()\TokenType = #ljIDENT
                     Protected *updateIdent.stTree = Makeleaf(#ljIDENT, TOKEN()\value)
                     Protected savedUpdateIdx.i = ListIndex(llTokenList())
                     NextToken()
                     Protected updateAssignOp.i = TOKEN()\TokenExtra
                     If updateAssignOp = #ljASSIGN Or updateAssignOp = #ljADD_ASSIGN Or updateAssignOp = #ljSUB_ASSIGN Or updateAssignOp = #ljMUL_ASSIGN Or updateAssignOp = #ljDIV_ASSIGN Or updateAssignOp = #ljMOD_ASSIGN
                        NextToken()
                        Protected *updateRhs.stTree = expr(0)
                        ; Handle compound assignment: transform i += 100 into i = i + 100
                        If updateAssignOp <> #ljASSIGN
                           Protected *updateIdentCopy.stTree = Makeleaf(#ljIDENT, *updateIdent\value)
                           Protected updateBinaryOp.i
                           Select updateAssignOp
                              Case #ljADD_ASSIGN : updateBinaryOp = #ljADD
                              Case #ljSUB_ASSIGN : updateBinaryOp = #ljSUBTRACT
                              Case #ljMUL_ASSIGN : updateBinaryOp = #ljMULTIPLY
                              Case #ljDIV_ASSIGN : updateBinaryOp = #ljDIVIDE
                              Case #ljMOD_ASSIGN : updateBinaryOp = #ljMOD
                           EndSelect
                           *updateRhs = MakeNode(updateBinaryOp, *updateIdentCopy, *updateRhs)
                        EndIf
                        *update = MakeNode(#ljASSIGN, *updateIdent, *updateRhs)
                     Else
                        ; Not an assignment, restore and parse as expression
                        SelectElement(llTokenList(), savedUpdateIdx)
                        *update = expr(0)
                     EndIf
                  Else
                     *update = expr(0)
                  EndIf
               EndIf
               Expect("for update", #ljRightParent)
            Else
               ; Without parens, update ends at { or first statement
               If TOKEN()\TokenExtra <> #ljLeftBrace
                  ; Check if this is an assignment: ident = value or ident += value, etc.
                  If TOKEN()\TokenType = #ljIDENT
                     Protected *updateIdent2.stTree = Makeleaf(#ljIDENT, TOKEN()\value)
                     Protected savedUpdateIdx2.i = ListIndex(llTokenList())
                     NextToken()
                     Protected updateAssignOp2.i = TOKEN()\TokenExtra
                     If updateAssignOp2 = #ljASSIGN Or updateAssignOp2 = #ljADD_ASSIGN Or updateAssignOp2 = #ljSUB_ASSIGN Or updateAssignOp2 = #ljMUL_ASSIGN Or updateAssignOp2 = #ljDIV_ASSIGN Or updateAssignOp2 = #ljMOD_ASSIGN
                        NextToken()
                        Protected *updateRhs2.stTree = expr(0)
                        ; Handle compound assignment: transform i += 100 into i = i + 100
                        If updateAssignOp2 <> #ljASSIGN
                           Protected *updateIdentCopy2.stTree = Makeleaf(#ljIDENT, *updateIdent2\value)
                           Protected updateBinaryOp2.i
                           Select updateAssignOp2
                              Case #ljADD_ASSIGN : updateBinaryOp2 = #ljADD
                              Case #ljSUB_ASSIGN : updateBinaryOp2 = #ljSUBTRACT
                              Case #ljMUL_ASSIGN : updateBinaryOp2 = #ljMULTIPLY
                              Case #ljDIV_ASSIGN : updateBinaryOp2 = #ljDIVIDE
                              Case #ljMOD_ASSIGN : updateBinaryOp2 = #ljMOD
                           EndSelect
                           *updateRhs2 = MakeNode(updateBinaryOp2, *updateIdentCopy2, *updateRhs2)
                        EndIf
                        *update = MakeNode(#ljASSIGN, *updateIdent2, *updateRhs2)
                     Else
                        ; Not an assignment, restore and parse as expression
                        SelectElement(llTokenList(), savedUpdateIdx2)
                        *update = expr(0)
                     EndIf
                  Else
                     *update = expr(0)
                  EndIf
               EndIf
            EndIf

            ; Parse body
            *s = stmt()

            ; Build FOR AST: left = init, right = (cond, (update, body))
            ; This allows codegen to easily access all parts
            *updateBody = MakeNode(#ljSEQ, *update, *s)
            *condUpdateBody = MakeNode(#ljSEQ, *cond, *updateBody)
            *p = MakeNode(#ljFOR, *init, *condUpdateBody)

         ; V1.024.0: switch statement
         Case #ljSWITCH
            NextToken()
            ; Parse switch expression
            If TOKEN()\TokenExtra = #ljLeftParent
               *e = paren_expr()
            Else
               *e = expr(0)
            EndIf

            ; Expect opening brace
            If TOKEN()\TokenExtra <> #ljLeftBrace
               SetError("Expected '{' after switch expression", #C2ERR_EXPECTED_STATEMENT)
               gStack - 1
               ProcedureReturn 0
            EndIf
            NextToken()

            ; Parse case labels and statements
            *cases = 0
            While TOKEN()\TokenExtra <> #ljRightBrace And TOKEN()\TokenExtra <> #ljEOF And Not gLastError
               Select TOKEN()\TokenExtra
                  Case #ljCASE
                     NextToken()
                     ; Parse case value (must be constant expression)
                     *caseVal = expr(0)
                     Expect("case value", #ljCOLON)
                     ; Parse statements until next case/default/}
                     *caseBody = 0
                     While TOKEN()\TokenExtra <> #ljCASE And TOKEN()\TokenExtra <> #ljDEFAULT_CASE And TOKEN()\TokenExtra <> #ljRightBrace And TOKEN()\TokenExtra <> #ljEOF And Not gLastError
                        *caseBody = MakeNode(#ljSEQ, *caseBody, stmt())
                     Wend
                     ; Create case node: left = value, right = body
                     *caseNode = MakeNode(#ljCASE, *caseVal, *caseBody)
                     *cases = MakeNode(#ljSEQ, *cases, *caseNode)

                  Case #ljDEFAULT_CASE
                     NextToken()
                     Expect("default", #ljCOLON)
                     ; Parse statements until next case/}
                     *defaultBody = 0
                     While TOKEN()\TokenExtra <> #ljCASE And TOKEN()\TokenExtra <> #ljRightBrace And TOKEN()\TokenExtra <> #ljEOF And Not gLastError
                        *defaultBody = MakeNode(#ljSEQ, *defaultBody, stmt())
                     Wend
                     ; Create default node (no value, just body)
                     *defaultNode = MakeNode(#ljDEFAULT_CASE, 0, *defaultBody)
                     *cases = MakeNode(#ljSEQ, *cases, *defaultNode)

                  Default
                     SetError("Expected 'case' or 'default' in switch", #C2ERR_EXPECTED_STATEMENT)
                     gStack - 1
                     ProcedureReturn 0
               EndSelect
            Wend

            Expect("switch body", #ljRightBrace)
            ; Build SWITCH AST: left = expression, right = cases
            *p = MakeNode(#ljSWITCH, *e, *cases)

         ; V1.024.0: break statement
         Case #ljBREAK
            NextToken()
            *p = MakeNode(#ljBREAK, 0, 0)
            ; Semicolon is optional but consumed if present
            If TOKEN()\TokenExtra = #ljSemi
               NextToken()
            EndIf

         ; V1.024.0: continue statement
         Case #ljCONTINUE
            NextToken()
            *p = MakeNode(#ljCONTINUE, 0, 0)
            ; Semicolon is optional but consumed if present
            If TOKEN()\TokenExtra = #ljSemi
               NextToken()
            EndIf

         ; V1.024.0: case/default outside switch - error
         Case #ljCASE, #ljDEFAULT_CASE
            SetError("'case' and 'default' only allowed inside switch", #C2ERR_EXPECTED_STATEMENT)
            gStack - 1
            ProcedureReturn 0

         Case #ljLeftBrace
            Expect( "Left Bracket", #ljLeftBrace )

            While TOKEN()\TokenExtra <> #ljRightBrace And TOKEN()\TokenExtra <> #ljEOF And Not gLastError
               *p = MakeNode( #ljSEQ, *p, stmt() )
            Wend

            Expect( "Left Bracket", #ljRightBrace )

         Case #ljEOF
            gExit = 1

         Case #ljHalt
            NextToken()
            *p = MakeNode( #ljHalt, *p, 0 )

         Case #ljFunction
            *v = Makeleaf( #ljFunction, TOKEN()\value )
            n = Val( TOKEN()\value )
            NextToken()  ; Advance past function token

            ; V1.18.19: Skip return type suffix token if present
            ; After NextToken(), we should be at '('. If not, skip one more token.
            If TOKEN()\TokenExtra <> #ljLeftParent
               NextToken()  ; Skip the return type suffix token
            EndIf

            *e = expand_params( #ljPOP, n )
            *p = MakeNode( #ljSEQ, *v, *e )

         Case #ljCALL
            moduleId = Val(TOKEN()\value)
            *v = Makeleaf( #ljCall, TOKEN()\value )
            NextToken()
            *e = expand_params( #ljPush, moduleId )
            *v\paramCount = gLastExpandParamsCount  ; Store actual param count in node
            ; Statement-level calls need to pop unused return value into reserved slot 0
            *s = Makeleaf( #ljPOP, "0" )  ; Use slot 0 directly
            *p = MakeNode( #ljSEQ, *e, MakeNode( #ljSEQ, *v, *s ) )

         Case #ljreturn
            NextToken()

            ; NEW CODE - generate expr, then return:
            If TOKEN()\TokenType = #ljSemi
               ; return with no value - push 0
               *e = Makeleaf( #ljINT, "0" )
               *v = MakeNode( #ljSEQ, *e, Makeleaf( #ljreturn, "0" ) )
               NextToken()
            Else
               ; return with value - evaluate expr, then return
               *e = expr(0)

               ; NOTE: Return type conversion removed from parser
               ; Type conversions should be added by postprocessor when type info is accurate
               ; The VM handles return types via RETF/RETS/RET opcodes

               *v = MakeNode( #ljSEQ, *e, Makeleaf( #ljreturn, "0" ) )
               Expect( "Return", #ljSemi )
            EndIf

            *p = MakeNode( #ljSEQ, *p, *v )


         Default
            SetError( "Expecting beginning of a statement, found " + TOKEN()\name, #C2ERR_EXPECTED_STATEMENT )

      EndSelect

      gStack - 1
      ProcedureReturn *p
   EndProcedure

   Procedure            DisplayNode( *p.stTree )
      If *p
         If *p\NodeType = #ljIDENT Or *p\NodeType = #ljINT Or *p\NodeType = #ljSTRING
            Debug LSet( gszATR( *p\NodeType )\s, 30 ) + *p\value
         Else
            Debug LSet( gszATR( *p\NodeType )\s, 30 )
            DisplayNode( *p\left )
            DisplayNode( *p\right )
         EndIf
      Else
         Debug ";"
      EndIf
   EndProcedure

; IDE Options = PureBasic 6.21 (Windows - x64)
; CursorPosition = 1358
; FirstLine = 1348
; Folding = --
; EnableAsm
; EnableThread
; EnableXP
; CPU = 1
; EnablePurifier
; EnableCompileCount = 0
; EnableBuildCount = 0
; EnableExeConstant