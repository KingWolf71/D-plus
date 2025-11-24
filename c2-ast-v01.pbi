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
         ; In global scope
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

         Case #ljGETADDR  ; Address-of operator: &variable
            NextToken()
            *node = expr( gPreTable( #ljNOT )\Precedence )  ; Parse variable at high precedence
            *p = MakeNode( #ljGETADDR, *node, 0 )

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
                  ; Identifier followed by '(' but not a built-in or defined function - this is an error
                  SetError( "Undefined function '" + identName + "'", #C2ERR_UNDEFINED_FUNCTION )
                  ProcedureReturn 0
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

                  ; V1.20.22: Check for pointer field access on array element: arr[i]\i, arr[i]\f, arr[i]\s
                  If TOKEN()\TokenType = #ljBackslash
                     NextToken()  ; Skip '\'

                     ; Check for field type: i, f, or s
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
                        SetError( "Expected 'i', 'f', or 's' after '\' in pointer field access", #C2ERR_EXPECTED_PRIMARY )
                        ProcedureReturn 0
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
                     SetError( "Expected 'i', 'f', or 's' after '\' in pointer field access", #C2ERR_EXPECTED_PRIMARY )
                     ProcedureReturn 0
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

      ; V1.18.63: Check for cast syntax: (int), (float), (string)
      If TOKEN()\TokenExtra = #ljIDENT
         castType = LCase(TOKEN()\value)
         If castType = "int" Or castType = "float" Or castType = "string"
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

      ; CRITICAL: Initialize all pointers to null (they contain garbage otherwise!)
      *p = 0 : *v = 0 : *e = 0 : *r = 0 : *s = 0 : *s2 = 0 : *lhsCopy = 0

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
         ; In global scope
         gCurrentFunctionName = ""
      EndIf

      gStack + 1

      If gStack > #MAX_RECURSESTACK
         SetError( "Stack overflow", #C2ERR_STACK_OVERFLOW )
         gStack - 1
         ProcedureReturn 0
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

            ; Expect ;
            If TOKEN()\TokenType <> #ljSemi
               SetError("Expected ';' after array declaration", #C2ERR_EXPECTED_STATEMENT)
               gStack - 1
               ProcedureReturn 0
            EndIf
            NextToken()

            ; Register the array variable
            varSlot = FetchVarOffset(arrayName, 0, 0)
            gVarMeta(varSlot)\arraySize = arraySize
            gVarMeta(varSlot)\elementSize = 1  ; 1 for primitives

            ; Clear any existing type bits and set array flag + element type
            ; FetchVarOffset may have set INT as default, so clear type bits first
            gVarMeta(varSlot)\flags = (gVarMeta(varSlot)\flags & ~#C2FLAG_TYPE) | #C2FLAG_ARRAY

            CompilerIf #DEBUG
               Debug "Array declaration: " + arrayName + "[" + Str(arraySize) + "] -> varSlot=" + Str(varSlot) + ", stored arraySize=" + Str(gVarMeta(varSlot)\arraySize)
            CompilerEndIf

            ; Set element type based on type hint or pointer flag
            If isPointerArray
               ; Pointer array - elements are pointers (stored as slot indices)
               ; Just use INT type, no special POINTER flag needed
               gVarMeta(varSlot)\flags = gVarMeta(varSlot)\flags | #C2FLAG_INT
            ElseIf arrayTypeHint = #ljFLOAT
               gVarMeta(varSlot)\flags = gVarMeta(varSlot)\flags | #C2FLAG_FLOAT
            ElseIf arrayTypeHint = #ljSTRING
               gVarMeta(varSlot)\flags = gVarMeta(varSlot)\flags | #C2FLAG_STR
            Else
               gVarMeta(varSlot)\flags = gVarMeta(varSlot)\flags | #C2FLAG_INT
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
                     ; V1.18.0: Assign unique paramOffset for each local array (same as regular locals)
                     gVarMeta(varSlot)\paramOffset = gCodeGenLocalIndex
                     gCodeGenLocalIndex + 1
                     ; Store mapping: [functionId, localArrayIndex] -> varSlot
                     gFuncLocalArraySlots(stmtFunctionId, mapModules()\nLocalArrays) = varSlot
                     mapModules()\nLocalArrays + 1
                     ; Update nLocals count
                     mapModules()\nLocals = gCodeGenLocalIndex - mapModules()\nParams
                     Break
                  EndIf
               Next
            Else
               ; Global array - set paramOffset to -1
               gVarMeta(varSlot)\paramOffset = -1
            EndIf

            ; Return empty node (array declaration doesn't generate code itself)
            *p = 0

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
            ; Check if this is a function call, increment/decrement, or assignment
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

                  ; Check for field type: i, f, or s
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
                     SetError( "Expected 'i', 'f', or 's' after '\' in pointer field access", #C2ERR_EXPECTED_STATEMENT )
                     gStack - 1
                     ProcedureReturn 0
                  EndIf
               EndIf

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
               If *v\TypeHint = 0 And *e And assignOp = #ljASSIGN
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
