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
; Common Structures

; ======================================================================================================
;- Constants
; ======================================================================================================

;DisableDebugger
EnableDebugger  ; V1.031.109: Disabled for performance - Debug statements now suppressed

DeclareModule C2Common

   ;#DEBUG = 0
   XIncludeFile         "c2-inc-v16.pbi"
EndDeclareModule

Module C2Common
   ;Empty by design

EndModule

DeclareModule C2Lang
   EnableExplicit
   #WithEOL = 1
   UseModule C2Common

   Global               gExit
   Global               gszlastError.s
   Global NewList       gWarnings.s()       ; List to store all warnings during compilation
   Global NewList       gInfos.s()          ; V1.023.0: List for informational messages (preload optimizations)

   Structure stTree
      NodeType.i
      TypeHint.i       ; V1.022.71: Type annotation (.i/.f/.s) - non-zero inside function = local
      value.s
      paramCount.i     ; For function calls - actual parameter count
      *left.stTree
      *right.stTree
   EndStructure

   Declare.s            Error( *error.Integer )
   Declare              Compile()
   Declare              ListCode( gadget = 0 )
   Declare              LoadLJ( file.s )
EndDeclareModule

XIncludeFile            "c2-vm-V15.pb"

Module C2Lang
   EnableExplicit
   
; ======================================================================================================
;- Structures
; ======================================================================================================

   #C2REG_FLOATS        = 1
   #C2FUNCSTART         = 2
   #MAX_RECURSESTACK    = 150
      
   Structure stSymbols
      name.s
      TokenType.i
   EndStructure
   
   Structure stToken
      name.s
      TokenType.l
      TokenExtra.l
      value.s
      row.l
      col.l
      function.l
      typeHint.w          ; Type suffix: 0=none, #ljFLOAT, #ljSTRING
      hasDot.b            ; V1.030.16: True if identifier contains dot (e.g., "local.x")
   EndStructure
   
   Structure stPrec
      bRightAssociation.i
      bBinary.i
      bUnary.i
      Precedence.i
      NodeType.i
   EndStructure
   
   Structure stModInfo
      *code.stTree
      function.l
      params.s
      nParams.i
      nLocals.i       ; Number of local variables (non-parameters) in function
      nLocalArrays.i  ; Number of local array variables in function
      Index.l
      row.l
      nCall.u
      *NewPos
      bTypesLocked.i  ; Flag: Types locked on first call
      returnType.w    ; Return type flags (INT/FLOAT/STR)
      List paramTypes.w()  ; Parameter type flags (INT/FLOAT/STR) in order
   EndStructure
   
   Structure stMacro
      name.s
      body.s
      List llParams.s()
   EndStructure
   
   Structure stHole
      mode.l
      id.l
      *src
      *location
   EndStructure

   ; V1.024.0: Loop context for break/continue support
   Structure stLoopContext
      loopStart.i           ; Hole ID for continue target
      *loopStartPtr         ; Pointer to loop start NOOPIF
      *loopUpdatePtr        ; Pointer to update section (for FOR loops, continue jumps here)
      breakHoles.i[32]      ; Array of break hole IDs to fix at loop end
      breakCount.i          ; Number of break holes
      continueHoles.i[32]   ; V1.024.2: Array of continue hole IDs for FOR loops
      continueCount.i       ; V1.024.2: Number of continue holes
      isSwitch.b            ; True if this is a switch (break only, no continue)
      isForLoop.b           ; True if for loop (continue goes to update, not start)
   EndStructure

; ======================================================================================================
;- Functions
; ======================================================================================================
   
Declare                 FetchVarOffset(text.s, *assignmentTree.stTree = 0, syntheticType.i = 0, forceLocal.i = #False)
Declare.w               GetExprResultType( *x.stTree, depth.i = 0 )   
Declare                 expand_params( op = #ljpop, nModule = -1 )
   
; ======================================================================================================
;- Globals
; ======================================================================================================
  
   Global Dim           gPreTable.stPrec( #C2TOKENCOUNT )
   
   Global NewList       llSymbols.stSymbols()
   Global NewList       llTokenList.stToken()
   Global NewList       llHoles.stHole()
   Global NewList       llObjects.stType()
   Global NewList       llJumpTracker.stJumpTracker()  ; V1.020.073: Track jumps for NOOP adjustment
   Global NewList       llLoopContext.stLoopContext()  ; V1.024.0: Loop context stack for break/continue
   Global NewMap        mapMacros.stMacro()
   Global NewMap        mapModules.stModInfo()
   Global NewMap        mapBuiltins.stBuiltinDef()
   Global NewMap        mapVariableTypes.w()  ; Track variable types during parsing (name → type flags)

   Global               gLineNumber
   Global               gStack
   Global               gCol
   Global               gMemSize
   Global               gPos
   Global               gHoles
   Global               gFileFormat
   Global               gFloats
   Global               gIntegers
   Global               gStrings
   Global               gNextFunction
   Global               gCurrFunction
   Global               gCodeGenFunction
   Global               gCodeGenParamIndex
   Global               gCodeGenLocalIndex      ; Current local variable offset (nParams + local count)
   Global               gCodeGenRecursionDepth
   Global               gCurrentFunctionName.s  ; Current function being compiled (for local variable scoping)
   Global               gLastExpandParamsCount  ; Last actual parameter count from expand_params() for built-ins
   Global               gIsNumberFlag
   Global               gEmitIntCmd.i
   Global               gEmitIntLastOp
   Global               gInTernary.b      ; Flag to disable PUSH/FETCH→MOV optimization inside ternary

   Global               gszFileText.s
   Global               gszOriginalSource.s  ; Original source before comment stripping
   Global Dim           gSourceLines.s(0)     ; Array of source lines for efficient lookup
   Global               gNextChar.s
   Global               gLastError
   Global               gszEOF.s          = Chr( 255 )
   
   CompilerIf #PB_OS_Linux
      Global            gszSep.s          = #LF$
   CompilerElse
      Global            gszSep.s          = #CRLF$
   CompilerEndIf
      
   Global               gszFloating.s = "^[+-]?(\d+(\.\d*)?|\.\d+)([eE][+-]?\d+)?$"

   ; V1.023.0: Info messages macro (defined early for postprocessor access)
   Macro                SetInfo( text )
      AddElement( gInfos() )
      gInfos() = "Info: " + text
   EndMacro

   ;- =====================================
   ;- Add compiler parts
   ;- =====================================
   XIncludeFile         "c2-postprocessor-V07.pbi"

   CreateRegularExpression( #C2REG_FLOATS, gszFloating )
   
   Declare              paren_expr()
   ;- =====================================
   ;- Generic Macros
   ;- =====================================
   Macro             TOKEN()
      llTokenList()
   EndMacro
   Macro             Install( symbolname, id  )
      AddElement( llSymbols() )
         llSymbols()\name        = LCase(symbolname)
         llSymbols()\TokenType   = id
   EndMacro

   Macro             InstallBuiltin( funcName, funcOpcode, funcMinP, funcMaxP, funcRetType )
      AddMapElement(mapBuiltins(), LCase(funcName))
      mapBuiltins()\name       = funcName
      mapBuiltins()\opcode     = funcOpcode
      mapBuiltins()\minParams  = funcMinP
      mapBuiltins()\maxParams  = funcMaxP
      mapBuiltins()\returnType = funcRetType
   EndMacro

   Procedure.s          GetSourceLine( lineNum.i )
      ; Use array for O(1) lookup instead of parsing string each time
      If lineNum >= 1 And lineNum <= ArraySize(gSourceLines())
         ProcedureReturn Trim(gSourceLines(lineNum))
      EndIf
      
      ProcedureReturn ""
   EndProcedure
   
   Macro                SetError( text, err )
      If err > 0 And err < 10
         gszlastError = text + " on line " + Str( gLineNumber ) + ", col = " + Str( gCol )
         If GetSourceLine(gLineNumber) <> ""
            gszlastError + #CRLF$ + ">> " + GetSourceLine(gLineNumber)
         EndIf
      ElseIf err >= 10
         gszlastError = text + " on line " + Str(llTokenList()\row) + ", col = " + Str(llTokenList()\col)
         If GetSourceLine(llTokenList()\row) <> ""
            gszlastError + #CRLF$ + ">> " + GetSourceLine(llTokenList()\row)
         EndIf
      Else
         gszlastError = text
      EndIf

      gLastError = err

      ProcedureReturn err
   EndMacro

   Macro                SetWarning( text, useToken = #False )
      AddElement( gWarnings() )

      If useToken
         gWarnings() = "Warning: " + text + " on line " + Str(llTokenList()\row) + ", col = " + Str(llTokenList()\col)
         If GetSourceLine(llTokenList()\row) <> ""
            gWarnings() + #CRLF$ + ">> " + GetSourceLine(llTokenList()\row)
         EndIf
      Else
         gWarnings() = "Warning: " + text + " on line " + Str( gLineNumber ) + ", col = " + Str( gCol )
         If GetSourceLine(gLineNumber) <> ""
            gWarnings() + #CRLF$ + ">> " + GetSourceLine(gLineNumber)
         EndIf
      EndIf
   EndMacro

   Macro             NextToken()
      ;Debug "---[ " + #PB_Compiler_Procedure + " ]---"
      ;Debug Str( ListIndex( llTokenList() ) ) + "   " + llTokenList()\name
      NextElement( llTokenList() )
   EndMacro
   ;-
   Procedure.s          Error( *error.Integer )
      Protected         szerror.s
   
      If gLastError
         
         *error\i       = gLastError
         szerror        = gszlastError
         gLastError     = 0
         gszlastError   = ""
   
         ProcedureReturn szerror
      EndIf
      
      *error\i = 0
      ProcedureReturn ""
   EndProcedure
   
   Procedure            Logging( id, Text.s, pos = -1, UseDebug = 1 )
      If UseDebug
         Debug text
      EndIf
   EndProcedure
   ;- =====================================
   ;- Compiler init   
   ;- =====================================
   Macro                par_AddMacro( vname, value )
      AddMapElement( mapMacros(), vname )
         mapMacros()\name  = vname
         mapMacros()\body  = value
   EndMacro
   Macro                par_SetPre2( id, op )
      gPreTable( id )\bRightAssociation   = 0
      gPreTable( id )\bBinary             = 0
      gPreTable( id )\bUnary              = 0
      gPreTable( id )\Precedence          = -1
      gPreTable( id )\NodeType            = op
   EndMacro
   Macro                par_SetPre( id, right, bi, un, prec )
      gPreTable( id )\NodeType            = id
      gPreTable( id )\bRightAssociation   = right
      gPreTable( id )\bBinary             = bi
      gPreTable( id )\bUnary              = un
      gPreTable( id )\Precedence          = prec
   EndMacro

   ;-
   ;- Built-in Functions Registration
   ;-

   CompilerIf #True  ; Enable built-in functions
   ; Helper: Check if a function name is a built-in
   Procedure.i IsBuiltinFunction(name.s)
      ProcedureReturn FindMapElement(mapBuiltins(), LCase(name))
   EndProcedure

   ; Helper: Get built-in opcode by name
   Procedure.i GetBuiltinOpcode(name.s)
      If FindMapElement(mapBuiltins(), LCase(name))
         ProcedureReturn mapBuiltins()\opcode
      EndIf
      ProcedureReturn 0
   EndProcedure

   ; Register all built-in functions with the compiler
   Procedure RegisterBuiltins()
      InstallBuiltin( "random",            #ljBUILTIN_RANDOM,       0, 2, #C2FLAG_INT )
      InstallBuiltin( "abs",               #ljBUILTIN_ABS,          1, 1, #C2FLAG_INT )
      InstallBuiltin( "min",               #ljBUILTIN_MIN,          2, 2, #C2FLAG_INT )
      InstallBuiltin( "max",               #ljBUILTIN_MAX,          2, 2, #C2FLAG_INT )
      InstallBuiltin( "assertEqual",       #ljBUILTIN_ASSERT_EQUAL, 2, 2, 0 )
      InstallBuiltin( "assertFloatEqual",  #ljBUILTIN_ASSERT_FLOAT, 2, 3, 0 )
      InstallBuiltin( "assertStringEqual", #ljBUILTIN_ASSERT_STRING,2, 2, 0 )
      InstallBuiltin( "assertEqualStr",    #ljBUILTIN_ASSERT_STRING,2, 2, 0 )  ; Alias
      InstallBuiltin( "sqrt",              #ljBUILTIN_SQRT,         1, 1, #C2FLAG_FLOAT )
      InstallBuiltin( "pow",               #ljBUILTIN_POW,          2, 2, #C2FLAG_FLOAT )
      InstallBuiltin( "len",               #ljBUILTIN_LEN,          1, 1, #C2FLAG_INT )
      InstallBuiltin( "strlen",            #ljBUILTIN_LEN,          1, 1, #C2FLAG_INT )  ; Alias for len
      ; V1.027.12: String comparison and character access
      InstallBuiltin( "strcmp",            #ljBUILTIN_STRCMP,       2, 2, #C2FLAG_INT )  ; Returns -1/0/1
      InstallBuiltin( "getc",              #ljBUILTIN_GETC,         2, 2, #C2FLAG_INT )  ; Get char code at index
      ; V1.023.29: Add str() and strf() conversion functions
      InstallBuiltin( "str",               #ljITOS,                 1, 1, #C2FLAG_STR )
      InstallBuiltin( "strf",              #ljFTOS,                 1, 1, #C2FLAG_STR )

      ; V1.026.0: List built-in functions
      InstallBuiltin( "listAdd",           #ljLIST_ADD,             2, 2, 0 )
      InstallBuiltin( "listInsert",        #ljLIST_INSERT,          2, 2, 0 )
      InstallBuiltin( "listDelete",        #ljLIST_DELETE,          1, 1, 0 )
      InstallBuiltin( "listClear",         #ljLIST_CLEAR,           1, 1, 0 )
      InstallBuiltin( "listSize",          #ljLIST_SIZE,            1, 1, #C2FLAG_INT )
      InstallBuiltin( "listFirst",         #ljLIST_FIRST,           1, 1, #C2FLAG_INT )
      InstallBuiltin( "listLast",          #ljLIST_LAST,            1, 1, #C2FLAG_INT )
      InstallBuiltin( "listNext",          #ljLIST_NEXT,            1, 1, #C2FLAG_INT )
      InstallBuiltin( "listPrev",          #ljLIST_PREV,            1, 1, #C2FLAG_INT )
      InstallBuiltin( "listSelect",        #ljLIST_SELECT,          2, 2, #C2FLAG_INT )
      InstallBuiltin( "listIndex",         #ljLIST_INDEX,           1, 1, #C2FLAG_INT )
      InstallBuiltin( "listGet",           #ljLIST_GET,             1, 1, 0 )  ; Return type depends on list type
      InstallBuiltin( "listSet",           #ljLIST_SET,             2, 2, 0 )
      InstallBuiltin( "listReset",         #ljLIST_RESET,           1, 1, 0 )
      InstallBuiltin( "listSort",          #ljLIST_SORT,            1, 2, 0 )  ; 1 param = ascending, 2 params = direction

      ; V1.026.0: Map built-in functions
      InstallBuiltin( "mapPut",            #ljMAP_PUT,              3, 3, 0 )  ; mapPut(map, key, value)
      InstallBuiltin( "mapGet",            #ljMAP_GET,              2, 2, 0 )  ; Return type depends on map type
      InstallBuiltin( "mapDelete",         #ljMAP_DELETE,           2, 2, 0 )
      InstallBuiltin( "mapClear",          #ljMAP_CLEAR,            1, 1, 0 )
      InstallBuiltin( "mapSize",           #ljMAP_SIZE,             1, 1, #C2FLAG_INT )
      InstallBuiltin( "mapContains",       #ljMAP_CONTAINS,         2, 2, #C2FLAG_INT )
      InstallBuiltin( "mapReset",          #ljMAP_RESET,            1, 1, 0 )
      InstallBuiltin( "mapNext",           #ljMAP_NEXT,             1, 1, #C2FLAG_INT )
      InstallBuiltin( "mapKey",            #ljMAP_KEY,              1, 1, #C2FLAG_STR )
      InstallBuiltin( "mapValue",          #ljMAP_VALUE,            1, 1, 0 )  ; Return type depends on map type
   EndProcedure
   CompilerEndIf

   ;-
   Procedure            Init()
      Protected         temp.s
      Protected         i, n, m
      Protected         verFile.i, verString.s

      For i = 0 To #C2MAXCONSTANTS
         gVarMeta(i)\name   = ""
         gVarMeta(i)\flags  = 0
         gVarMeta(i)\paramOffset = -1  ; -1 means unassigned
         ; V1.022.39: Clear value fields to prevent stale constants between compiles
         gVarMeta(i)\valueInt = 0
         gVarMeta(i)\valueFloat = 0.0
         gVarMeta(i)\valueString = ""
         gVarMeta(i)\arraySize = 0
         gVarMeta(i)\elementSize = 0
         gVarMeta(i)\typeSpecificIndex = 0
         gVarMeta(i)\structType = ""
         ; V1.022.121: CRITICAL - Initialize pointsToStructType to prevent garbage matching
         ; Without this, uninitialized memory could cause AST to incorrectly match
         ; variables as struct pointers when searching for ptr\field patterns
         gVarMeta(i)\pointsToStructType = ""
         ; V1.029.37: Initialize struct field metadata for \ptr storage
         gVarMeta(i)\structFieldBase = -1   ; -1 means not a struct field
         gVarMeta(i)\structFieldOffset = 0
         ; V1.030.3: CRITICAL - Reset structAllocEmitted to prevent stale state between compiles
         ; Without this, subsequent runs skip STRUCT_ALLOC_LOCAL because flag is still True
         gVarMeta(i)\structAllocEmitted = #False
      Next

      ; Reserve slot 0 as the discard slot for unused return values
      gVarMeta(0)\name = "?discard?"
      gVarMeta(0)\flags = #C2FLAG_IDENT | #C2FLAG_INT
      gVarMeta(0)\paramOffset = -1  ; Global variable
      gnGlobalVariables = 1  ; V1.020.059: Count slot 0 as first global variable

      ;Read tokens
      gnTotalTokens = 0
      Restore c2tokens
      
      Repeat
         Read.s temp
         If temp = "-" : Break : EndIf
         gszATR(gnTotalTokens)\s = temp
         Read m
         Read n
         
         gszATR(gnTotalTokens)\strtoken = n
         gszATR(gnTotalTokens)\flttoken = m
         
         gnTotalTokens + 1
      ForEver

      ; Ensure arrays are large enough for both runtime count and compile-time enum values
      If gnTotalTokens < #C2TOKENCOUNT
         gnTotalTokens = #C2TOKENCOUNT
      EndIf

      ReDim gPreTable.stPrec(gnTotalTokens)
      ReDim gszATR(gnTotalTokens)
   
      par_SetPre2( #ljEOF, -1 )
      par_SetPre( #ljMULTIPLY,     0, 1, 0, 13 )
      par_SetPre( #ljDIVIDE,       0, 1, 0, 13 )
      par_SetPre( #ljMOD,          0, 1, 0, 13 )
      par_SetPre( #ljADD,          0, 1, 0, 12 )
      par_SetPre( #ljSUBTRACT,     0, 1, 0, 12 )
      par_SetPre( #ljNEGATE,       0, 0, 1, 14 )
      par_SetPre( #ljNOT,          0, 0, 1, 14 )

      ; Increment/decrement operators - not traditional binary/unary in precedence table
      ; These are handled specially in expr() loop
      par_SetPre2( #ljINC, -1 )
      par_SetPre2( #ljDEC, -1 )
      par_SetPre2( #ljPRE_INC, -1 )
      par_SetPre2( #ljPRE_DEC, -1 )
      par_SetPre2( #ljPOST_INC, -1 )
      par_SetPre2( #ljPOST_DEC, -1 )

      ; Compound assignment operators - not binary operators
      par_SetPre2( #ljADD_ASSIGN, -1 )
      par_SetPre2( #ljSUB_ASSIGN, -1 )
      par_SetPre2( #ljMUL_ASSIGN, -1 )
      par_SetPre2( #ljDIV_ASSIGN, -1 )
      par_SetPre2( #ljMOD_ASSIGN, -1 )

      par_SetPre( #ljLESS,         0, 1, 0, 10 )
      par_SetPre( #ljLESSEQUAL,    0, 1, 0, 10 )
      par_SetPre( #ljGREATER,      0, 1, 0, 10 )
      par_SetPre( #ljGreaterEqual, 0, 1, 0, 10 )
      par_SetPre( #ljEQUAL,        0, 1, 0, 9 )
      par_SetPre( #ljNotEqual,     0, 1, 0, 9 )
      par_SetPre2( #ljASSIGN,      #ljASSIGN )
      par_SetPre( #ljAND,          0, 1, 0, 5 )
      par_SetPre( #ljXOR,          0, 1, 0, 6 )   ; V1.021.4: Bitwise XOR (^) precedence 6
      par_SetPre( #ljOr,           0, 1, 0, 4 )
      ; NOTE: Single & is address-of operator, not bitwise AND
      ; Use && for AND operations (both logical and bitwise for integers)
      par_SetPre( #ljQUESTION,     1, 1, 0, 3 )  ; Ternary: right-assoc, binary-like, precedence 3
      par_SetPre2( #ljIF,          #ljIF )
      
      par_SetPre2( #ljElse,        -1 )
      par_SetPre2( #ljWHILE,       #ljWHILE )
      par_SetPre2( #ljPRTS,        -1 )
      par_SetPre2( #ljPRTI,        -1 )
      par_SetPre2( #ljPRTC,        -1 )
      par_SetPre2( #ljLeftParent,  -1 )
      par_SetPre2( #ljLeftBrace,   -1 )
      par_SetPre2( #ljRightParent,  -1 )
      par_SetPre2( #ljRightBrace, -1 )
      par_SetPre2( #ljComma,  -1 )
      par_SetPre2( #ljSemi,  -1 )
      par_SetPre2( #ljfunction,  -1 )
      par_SetPre2( #ljreturn,  -1 )
      par_SetPre2( #ljIDENT,  #ljIDENT )
      par_SetPre2( #ljINT,    #ljINT )
      par_SetPre2( #ljSTRING, #ljSTRING )
      par_SetPre2( #ljFLOAT,    #ljFLOAT )
      
      ; Reset list positions before clearing
      
      ClearList( llObjects() )
      ClearList( llTokenList() )
      ClearList( llSymbols() )
      ClearList( llHoles() )
      ClearList( llJumpTracker() )  ; V1.020.073: Clear jump tracker
      ClearList( llLoopContext() )  ; V1.024.0: Clear loop context stack
      ClearList( gWarnings() )
      ClearList( gInfos() )        ; V1.023.0: Clear info messages
      ClearMap( mapPragmas() )
      ClearMap( mapMacros() )
      ClearMap( mapModules() )
      ClearMap( mapVariableTypes() )

      ; Add #LJ2_VERSION from _lj2.ver file
      verFile = ReadFile(#PB_Any, "_lj2.ver")
      If verFile
         verString = ReadString(verFile)
         CloseFile(verFile)
      Else
         verString = "0"  ; Default if file not found
      EndIf
      
      Debug "Running version [" + verString + "]"
      
      AddMapElement(mapMacros(), "#LJ2_VERSION")
      mapMacros()\name = "#LJ2_VERSION"
      mapMacros()\body = verString

      ReDim arCode(1)
      ; Clear the code array by putting HALT at position 0
      arCode(0)\code = #ljHALT
      arCode(0)\i = 0
      arCode(0)\j = 0

      gLineNumber             = 1
      gCol                    = 1
      gPos                    = 1
      gStack                  = 0
      gExit                   = 0
      gszlastError            = ""
      gLastError              = 0
      gHoles                  = 0
      gnLastVariable          = 1  ; Slot 0 is reserved for ?discard?
      gStrings                = 0
      gFloats                 = 0
      gIntegers               = 0
      gNextFunction           = #C2FUNCSTART
      gCodeGenFunction        = 0
      gCodeGenParamIndex      = -1
      gCodeGenLocalIndex      = 0
      gCodeGenRecursionDepth  = 0
      gCurrentFunctionName    = ""  ; Empty = global scope
      gLastExpandParamsCount  = 0
      gIsNumberFlag           = 0
      gEmitIntCmd             = #LJUnknown
      gEmitIntLastOp          = 0
      gInTernary              = #False

      Install( "array", #ljArray )
      Install( "arr", #ljArray )       ; V1.024.27: Alias for array
      Install( "struct", #ljStruct )   ; V1.021.0: Structure support
      Install( "list", #ljList )       ; V1.026.0: Linked list support
      Install( "map", #ljMap )         ; V1.026.0: Map support
      ; V1.022.71: 'local' keyword removed - type annotation (.i/.f/.s) creates local automatically
      Install( "else", #ljElse )
      install( "if",    #ljIF )
      install( "print", #ljPRint )
      install( "putc",  #ljPRTC )
      install( "while", #ljWHILE )
      install( "func", #ljfunction )
      install( "function", #ljfunction )  ; Alias for func
      install( "return", #ljreturn )
      install( "call", #ljCall )

      ; V1.024.0: C-style control flow
      install( "for", #ljFOR )
      install( "switch", #ljSWITCH )
      install( "case", #ljCASE )
      install( "default", #ljDEFAULT_CASE )
      install( "break", #ljBREAK )
      install( "continue", #ljCONTINUE )

      ; Register built-in functions (random, abs, min, max, etc.)
      RegisterBuiltins()

      mapPragmas("console") = "on"
      mapPragmas("appname") = "Untitled"
      mapPragmas("consolesize") = "600x420"
      
      par_AddMacro( "#True", "1" )
      par_AddMacro( "#False", "0" )
      par_AddMacro( "#PI", "3.14159265359" )

   EndProcedure
   
   Procedure            LoadLJ( filename.s )
      Protected         f, *mem

      gMemSize = FileSize( filename )
      
      If gMemSize > 0
         f = ReadFile( #PB_Any, filename, #PB_File_NoBuffering )
         gFileFormat = ReadStringFormat( f )    
         
         If Not f
            SetError( "Could not open file", #C2ERR_FILE_OPEN_FAILED )
         EndIf
         
         If gFileFormat <> #PB_Ascii And gFileFormat <> #PB_UTF8 And gFileFormat <> #PB_Unicode
            gFileFormat = #PB_Unicode
         EndIf
         
         *Mem = AllocateMemory( gMemSize + 16 )
         ReadData( f, *Mem, gMemSize )
         CloseFile( f )
         
         CompilerIf( #WithEOL = 1 )
            gszFileText = PeekS( *mem, -1, gFileFormat ) + gszEOF
         CompilerElse
            gszFileText = PeekS( *mem, -1, gFileFormat )
         CompilerEndIf   
            
         gMemSize = Len( gszFileText )
         FreeMemory( *mem )
         ProcedureReturn 0
      EndIf

      SetError( "Invalid file", #C2ERR_INVALID_FILE )
   EndProcedure

   XIncludeFile         "c2-scanner-v04.pbi"
   XIncludeFile         "c2-ast-v05.pbi"
   XIncludeFile         "c2-codegen-v05.pbi"

   ;- =====================================
   ;- Preprocessors
   ;- =====================================
   Macro                pre_FindNextWord( tsize, withinv, extra )
      p = pre_TrimWhiteSpace( Mid( p, tsize ) )
      
      CompilerIf withinv
         temp = "_abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789" + #INV$ + extra
      CompilerElse
         temp = "_abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789" + extra
      CompilerEndIf  
      
      Repeat
         If Not FindString( temp, Mid( p, j, 1 ), #PB_String_NoCase ) : Break : EndIf   
         j + 1
      ForEver
   EndMacro
   Macro                pre_TrimWhiteSpace( string )
      Trim( Trim( Trim( string ), #TAB$ ), #CR$ )
   EndMacro
   Macro                par_AddModule( modname, mparams )
      
      If FindMapElement( mapModules(), modname )
         SetError( "Function already declared", #C2ERR_FUNCTION_REDECLARED )
      Else
         AddMapElement( mapModules(), modname )
         mapModules()\function      = gNextFunction
         mapModules()\NewPos        = 0
         mapModules()\params        = mparams
         mapModules()\nParams       = -1
         gNextFunction + 1
      EndIf
   EndMacro
   ;-
   ; We parse for #pragmas and function calls as well as macros
   Procedure            ParseFunctions( line.s, row.i )
      Protected.s       temp, nc, name, p, params, baseName
      Protected         i, j, funcReturnType.w
      Protected         skipChars.i

      ;Debug "Checking functions for line: " + line
      i     = 1 : j = 1
      p     = pre_TrimWhiteSpace( line )

      skipChars = 0
      If FindString( p, "function", #PB_String_NoCase ) = 1
         skipChars = 8
      ElseIf FindString( p, "func", #PB_String_NoCase ) = 1
         skipChars = 4
      EndIf

      If skipChars > 0
         ;It's probably a function
         i + skipChars
         pre_FindNextWord( skipChars + 1, 0, "." )
         name  = Left( p, j - 1 )

         ; Extract return type from function name suffix (.i, .f, or .s)
         funcReturnType = #C2FLAG_INT  ; Default to INT
         baseName = name

         If Right(name, 2) = ".i"
            funcReturnType = #C2FLAG_INT
            baseName = Left(name, Len(name) - 2)
         ElseIf Right(name, 2) = ".f" Or Right(name, 2) = ".d"
            funcReturnType = #C2FLAG_FLOAT
            baseName = Left(name, Len(name) - 2)
         ElseIf Right(name, 2) = ".s"
            funcReturnType = #C2FLAG_STR
            baseName = Left(name, Len(name) - 2)
         EndIf

         temp  = "_" + LCase( baseName )
         p     = Mid( p, j )
         i = Len( p )

         If Mid( p, i, 1 ) = #CR$
            p = Left( p, i - 1 )
         EndIf

         p = pre_TrimWhiteSpace( p )

         If Mid( p, 1, 1) = "("
            ;Debug " - Found function: " + temp + " (" + name + ")"
            ; definetely a function
            par_AddModule( temp, p )
            mapModules()\row = row
            mapModules()\returnType = funcReturnType

            ; Parse parameter types from params string
            Protected paramStr.s = p
            Protected paramType.w, paramIdx.i
            Protected closeParenPos.i

            ; Find the closing parenthesis and extract only what's between ( and )
            paramStr = Trim(paramStr)
            If Left(paramStr, 1) = "("
               closeParenPos = FindString(paramStr, ")", 1)
               If closeParenPos > 0
                  ; Extract substring between ( and )
                  paramStr = Mid(paramStr, 2, closeParenPos - 2)
               Else
                  ; No closing paren found, skip opening paren
                  paramStr = Mid(paramStr, 2)
               EndIf
            EndIf
            paramStr = Trim(paramStr)

            ; Parse each parameter
            If paramStr <> ""
               For paramIdx = 1 To CountString(paramStr, ",") + 1
                  Protected param.s = Trim(StringField(paramStr, paramIdx, ","))
                  paramType = #C2FLAG_INT  ; Default

                  ; Check for type suffix (case-insensitive)
                  Protected paramLower.s = LCase(param)
                  If Right(paramLower, 2) = ".i"
                     paramType = #C2FLAG_INT
                  ElseIf Right(paramLower, 2) = ".f" Or Right(paramLower, 2) = ".d"
                     paramType = #C2FLAG_FLOAT
                  ElseIf Right(paramLower, 2) = ".s"
                     paramType = #C2FLAG_STR
                  EndIf

                  AddElement(mapModules()\paramTypes())
                  mapModules()\paramTypes() = paramType
               Next
            EndIf
         EndIf
      EndIf
   EndProcedure
   
   Procedure            ParseDefinitions( line.s )
      Protected         bInv, Bracket
      Protected         i, j
      Protected         tmpMod.stModInfo
      Protected.s       temp, nc, name, p, param, macroKey
      Protected         depth = 0, start = 2
      Protected         mret = #True
      
      i     = 1 : j = 1
      p     = pre_TrimWhiteSpace( line )
      
      ; It has to be at the beginning 
      If FindString( p, "#pragma", #PB_String_NoCase ) = 1
         pre_FindNextWord( 8, 1, "" )
         name  = LCase( Trim( Left( p, j - 1 ), #INV$ ) )
         p = Mid( p, j + 1 )
         i = Len( p )
         
         If Mid( p, i, 1 ) = #CR$
            p = Trim( Left( p, i - 1 ) )
         EndIf
         
         p = pre_TrimWhiteSpace( p )
         param = Trim( p, #INV$ )
         AddMapElement( mapPragmas(), name )
         If param = "" : param = "-" : EndIf
         mapPragmas() = param
         mret         = #False
         ;Debug name + " --> [" + param + "]," + Str(Len( param))
      ; It has to be at the beginning
      ElseIf FindString( p, "#define", #PB_String_NoCase ) = 1
         j = 1  ; Reset j before finding next word
         pre_FindNextWord( 8, 0, "" )
         name = Left( p, j - 1 )

         AddMapElement( mapMacros(), name )
         p     = pre_TrimWhiteSpace( Mid( p, j ) )
          
         If Left( p, 1 ) = "("
            Repeat
               i + 1
               nc = Mid( p, i, 1 )
               If nc = "" : Break : EndIf
               If nc = "(" : depth + 1
               ElseIf nc = ")" : depth - 1
               EndIf
            Until depth < 0

            ; params between positions 2 and i-2
            temp = Trim( Mid( p, 2, i - 2 ) )
            j = 1
                 
            Repeat
               nc = StringField( temp, j, "," )
               If nc = "" : Break : EndIf
               AddElement( mapMacros()\llParams() )
               mapMacros()\llParams() = Trim( nc )
               j + 1
            ForEver
            
            ;mapMacros()\strparams = temp
            p = Trim ( Mid( p, i + 1 ) ) ; remainder after ')'
         EndIf
         
         mapMacros()\name  = name
         mapMacros()\body  = p
         Debug "Macro stored - Key: [" + name + "] Name: [" + name + "] Body: [" + p + "]"
         mret              = #False
      EndIf
      
      ProcedureReturn mret
   EndProcedure
   
   Procedure.s          ExpandMacros( line.s )
      Protected.s       output, temp
      Protected.s       ident, expanded
      Protected.i       depth, argStart
      Protected.i       i
      Protected         m.stMacro
      Protected         p = 1
      Protected         lenInput, start
      Protected NewList ll.s()
      Protected.i       inString = #False
      Protected.i       escaped = #False
      Protected.s       currentChar
      Protected.i       argInString = #False
      Protected.i       argEscaped = #False
      Protected.s       argChar

      lenInput = Len( line )
      output   = ""

      If Mid( line, lenInput , 1 ) = #CR$
         lenInput - 1
      EndIf

      While p <= lenInput
         currentChar = Mid( line, p, 1 )

         ; Handle escape sequences
         If escaped
            output + currentChar
            escaped = #False
            p + 1
            Continue
         EndIf

         ; Check for backslash (escape character)
         If currentChar = "\"
            escaped = #True
            output + currentChar
            p + 1
            Continue
         EndIf

         ; Track string literals (don't expand macros inside strings)
         If currentChar = #DQUOTE$
            inString = 1 - inString  ; Toggle
            output + currentChar
            p + 1
            Continue
         EndIf

         ; If we're inside a string, just copy characters
         If inString
            output + currentChar
            p + 1
            Continue
         EndIf

         ; If identifier start
         If FindString( "#abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ_", currentChar, 1 )
            start = p

            While p <= lenInput And FindString( "#abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_", Mid( line, p, 1 ), 1 )
              p + 1
            Wend

            ident    = Mid( line, start, p - start )

            ; Macro lookup (case-sensitive)
            If FindMapElement( mapMacros(), ident )
               m = mapMacros()
               
               ; If function-like, parse args
               If Left( Mid( line, p, 1 ), 1 ) = "(" And ListSize( m\llParams() )
                  ; Consume '('
                  p + 1 : depth = 0
                  argStart = p
                  ClearList( ll() )
                  argInString = #False
                  argEscaped = #False

                  ; Build argument list by counting parentheses (respecting strings)
                  While p <= lenInput
                     argChar = Mid( line, p, 1 )

                     ; Handle escape sequences in argument strings
                     If argEscaped
                        argEscaped = #False
                        p + 1
                        Continue
                     EndIf

                     If argChar = "\"
                        argEscaped = #True
                        p + 1
                        Continue
                     EndIf

                     ; Track string state within arguments
                     If argChar = #DQUOTE$
                        argInString = 1 - argInString
                        p + 1
                        Continue
                     EndIf

                     ; Only count parentheses and commas outside of strings
                     If Not argInString
                        If argChar = "(" : depth + 1
                        ElseIf argChar = ")"
                           If depth = 0 : Break : EndIf
                           depth - 1
                        ElseIf argChar = "," And depth = 0
                           ; Split argument
                           AddElement( ll() )
                           ll() = Trim( Mid( line, argStart, p - argStart ) )
                           argStart = p + 1
                        EndIf
                     EndIf

                     p + 1
                  Wend
                  
                  ; Last argument
                  AddElement( ll() )
                  ll() = Trim( Mid( line, argStart, p - argStart ) )
                  ; Substitute parameters in body
                  expanded = m\body
                  FirstElement( m\llParams() )
                  
                  ForEach ll()
                     expanded = ReplaceString( expanded, m\llParams(), ll() )
                     NextElement( m\llParams() )
                  Next
                  
                  ; Recursively expand inside
                  expanded = ExpandMacros( expanded )
                  output + expanded
                  p + 1 ; skip ')'
                 Continue
               Else
                  ; Object-like macro or no args
                  output + ExpandMacros( m\body )
                  Continue
               EndIf
            EndIf
      
            ; Not a macro: just copy the identifier
            output + ident
            Continue
         EndIf
      
         ; Otherwise copy single character
         output + Mid( line, p, 1 )
         p + 1
      Wend

      ; Replace any newlines in the expanded output with spaces
      ; to preserve line number alignment with original source
      output = ReplaceString(output, #LF$, " ")
      output = ReplaceString(output, #CR$, " ")

      ;Debug output + "<--"
      ProcedureReturn output
   EndProcedure

   ; Strip comments from source while preserving strings
   Procedure.s          StripComments( source.s )
      Protected.s       result, char, nextChar
      Protected.i       i6, len, inString, inChar, inLineComment, inBlockComment
      Protected.i       escaped, i

      result = ""
      len = Len(source)
      i = 1

      While i <= len
         char = Mid(source, i, 1)
         nextChar = ""

         If i < len
            nextChar = Mid(source, i + 1, 1)
         EndIf

         ; Handle escape sequences
         If escaped
            If Not inLineComment And Not inBlockComment
               result + char
            EndIf
            escaped = #False
            i + 1
            Continue
         EndIf

         If char = "\"
            escaped = #True
            If Not inLineComment And Not inBlockComment
               result + char
            EndIf
            i + 1
            Continue
         EndIf

         ; Track string state (ignore comment markers inside strings)
         If Not inLineComment And Not inBlockComment And Not inChar
            If char = #DQUOTE$
               inString = 1 - inString  ; Toggle
               result + char
               i + 1
               Continue
            EndIf
         EndIf

         ; Track character literal state
         If Not inLineComment And Not inBlockComment And Not inString
            If char = "'"
               inChar = 1 - inChar  ; Toggle
               result + char
               i + 1
               Continue
            EndIf
         EndIf

         ; Don't process comment markers if we're inside a string or char
         If inString Or inChar
            result + char
            i + 1
            Continue
         EndIf

         ; Handle end of line comment
         If inLineComment
            If char = #LF$ Or char = #CR$
               inLineComment = #False
               result + char  ; Preserve newline
            Else
               result + " "   ; Replace comment chars with space to preserve column position
            EndIf
            i + 1
            Continue
         EndIf

         ; Handle block comment
         If inBlockComment
            If char = "*" And nextChar = "/"
               inBlockComment = #False
               result + "  "  ; Replace */ with spaces to preserve column position
               i + 2  ; Skip */
               Continue
            EndIf
            ; Replace comment content with space or newline to preserve positioning
            If char = #LF$ Or char = #CR$
               result + char  ; Preserve newlines for line numbering
            Else
               result + " "   ; Replace comment chars with space to preserve column position
            EndIf
            i + 1
            Continue
         EndIf

         ; Check for start of comments (only if not in string/char)
         If char = "/" And nextChar = "/"
            inLineComment = #True
            result + "  "  ; Replace // with spaces to preserve column position
            i + 2  ; Skip //
            Continue
         EndIf

         If char = "/" And nextChar = "*"
            inBlockComment = #True
            result + "  "  ; Replace /* with spaces to preserve column position
            i + 2  ; Skip /*
            Continue
         EndIf

         ; Normal character - add to result
         result + char
         i + 1
      Wend

      ProcedureReturn result
   EndProcedure

   ; V1.029.91: Auto-declare struct variables at function start
   ; Scans token stream for struct variable uses and inserts declarations
   Procedure            AutoDeclareStructVars()
      Protected.i funcStartIdx, funcEndIdx, tokenIdx, insertIdx
      Protected.s varName, typeName, funcName
      Protected NewMap structTypes.b()
      Protected NewMap declaredVars.b()
      Protected NewList varsToDecl.s()
      Protected.i braceDepth, inFunction

      ; Pass 1: Collect struct type names
      ForEach llTokenList()
         If llTokenList()\TokenType = #ljSTRUCT
            ; Next token should be the struct name
            NextElement(llTokenList())
            If llTokenList()\TokenType = #ljIDENT
               structTypes(llTokenList()\value) = #True
               CompilerIf #DEBUG
                  Debug "V1.029.91: Found struct type: " + llTokenList()\value
               CompilerEndIf
            EndIf
         EndIf
      Next

      ; Pass 2: Process each function
      ForEach llTokenList()
         If llTokenList()\TokenType = #ljfunction
            funcStartIdx = ListIndex(llTokenList())
            ClearList(varsToDecl())
            ClearMap(declaredVars())

            ; Get function name
            NextElement(llTokenList())
            If llTokenList()\TokenType = #ljIDENT
               funcName = llTokenList()\value
               CompilerIf #DEBUG
                  Debug "V1.029.91: Processing function: " + funcName
               CompilerEndIf
            EndIf

            ; Find function body (between opening { and closing })
            braceDepth = 0
            inFunction = #False

            While NextElement(llTokenList())
               If llTokenList()\TokenType = #ljLeftBrace
                  braceDepth + 1
                  If braceDepth = 1
                     inFunction = #True
                     insertIdx = ListIndex(llTokenList()) + 1  ; Insert after opening brace
                  EndIf
               ElseIf llTokenList()\TokenType = #ljRightBrace
                  braceDepth - 1
                  If braceDepth = 0
                     ; End of function
                     Break
                  EndIf
               EndIf

               ; Look for identifier.StructType patterns (tokenized as single IDENT)
               If inFunction And llTokenList()\TokenType = #ljIDENT
                  Protected.s fullName = llTokenList()\value
                  Protected.i dotPos = FindString(fullName, ".")

                  ; Check if this IDENT contains a dot (varName.TypeName pattern)
                  If dotPos > 0
                     varName = Left(fullName, dotPos - 1)
                     typeName = Mid(fullName, dotPos + 1)

                     ; Check if TypeName is a known struct type
                     If FindMapElement(structTypes(), typeName)
                        ; Check if followed by semicolon (manual declaration)
                        Protected.i isManualDecl = #False
                        tokenIdx = ListIndex(llTokenList())

                        If NextElement(llTokenList())
                           If llTokenList()\TokenType = #ljSemi
                              isManualDecl = #True
                              declaredVars(varName) = #True
                              CompilerIf #DEBUG
                                 Debug "V1.029.91: Found manual declaration: " + fullName
                              CompilerEndIf
                           EndIf
                           SelectElement(llTokenList(), tokenIdx)  ; Restore position
                        EndIf

                        ; If not manually declared and not yet in list, add to varsToDecl
                        If Not isManualDecl And Not FindMapElement(declaredVars(), varName)
                           AddElement(varsToDecl())
                           varsToDecl() = fullName
                           declaredVars(varName) = #True
                           CompilerIf #DEBUG
                              Debug "V1.029.91: Will auto-declare: " + fullName
                           CompilerEndIf
                        EndIf
                     EndIf
                  EndIf
               EndIf
            Wend

            ; Insert declarations at start of function
            If ListSize(varsToDecl()) > 0
               SelectElement(llTokenList(), insertIdx)
               ForEach varsToDecl()
                  ; Insert: varName.TypeName; (two tokens: IDENT + SEMICOLON)

                  ; Insert SEMICOLON
                  InsertElement(llTokenList())
                  llTokenList()\TokenType = #ljSemi
                  llTokenList()\TokenExtra = #ljSemi
                  llTokenList()\name = ";"
                  llTokenList()\value = ";"
                  llTokenList()\function = #C2FUNCSTART + funcStartIdx

                  ; Insert IDENT with full varName.TypeName
                  InsertElement(llTokenList())
                  llTokenList()\TokenType = #ljIDENT
                  llTokenList()\TokenExtra = #ljIDENT
                  llTokenList()\name = varsToDecl()
                  llTokenList()\value = varsToDecl()
                  llTokenList()\function = #C2FUNCSTART + funcStartIdx

                  CompilerIf #DEBUG
                     Debug "V1.029.91: Inserted auto-declaration: " + varsToDecl() + ";"
                  CompilerEndIf
               Next
            EndIf

            ; Reset to function start to continue outer loop
            SelectElement(llTokenList(), funcStartIdx)
         EndIf
      Next
   EndProcedure

   ; Finds and expands macros and functions
   Procedure            Preprocessor()
      Protected         i
      Protected         bFlag
      Protected.s       line
      Protected.s       szNewBody
      Protected.i       sizeBeforeStrip, sizeAfterStrip, sizeAfterMacros
      Protected         lineCount.i, lineIdx.i

      sizeBeforeStrip = Len(gszFileText)
      gszOriginalSource = gszFileText
      ; Populate source lines array for efficient line lookup
      
      lineCount = CountString(gszOriginalSource, #LF$) + 1
      ReDim gSourceLines(lineCount)
      
      For lineIdx = 1 To lineCount
         gSourceLines(lineIdx) = StringField(gszOriginalSource, lineIdx, #LF$)
      Next
      
      ; Strip all comments from source before processing
      gszFileText = StripComments(gszFileText)
      sizeAfterStrip = Len(gszFileText)
      szNewBody = ""

      ; First we find and store our macros
      ; IMPORTANT: Preserve blank lines to maintain line number alignment with original source
      Repeat
         i + 1 : bFlag = #True
         line = StringField( gszFileText, i, gszSep )
         If line = "" : Break : EndIf

         If FindString( line, "#define", #PB_String_NoCase ) Or FindString( line, "#pragma", #PB_String_NoCase )
            bFlag = ParseDefinitions( line )
         EndIf

         If bFlag = #True
            szNewBody + line + #LF$
         Else
            ; Replace #define and #pragma lines with blank lines to preserve line numbering
            szNewBody + " " + #LF$
            ;Debug mapMacros()\name + " --> " + mapMacros()\strparams + " --> " + mapMacros()\body
         EndIf
      ForEver
      
      ; Macro Expansion
      i = 0 : gszFileText = ""

      Repeat
         i + 1
         line = StringField( szNewBody, i, #LF$ )
         If line = "" : Break : EndIf

         ;- I don't know why the below line works - but it does
         Line = ExpandMacros( line) + #CRLF$
         ;Line = ExpandMacros( line) + #LF$
         gszFileText + line
      ForEver

      szNewBody = gszFileText
      gszFileText = "" : i = 0

      Repeat
         i + 1
         line = StringField( szNewBody, i, #LF$ )
         If line = "" : Break : EndIf

         ; V1.030.16: Convert DOT notation to backslash for struct field access
         ; Convert patterns like "local.x" to "local\x", but preserve:
         ; - Decimal numbers (10.5)
         ; - Type suffixes (.i, .f, .s, .d)
         ; - Type annotations (local.Point = where Point starts with capital)
         Protected convertedLine.s = ""
         Protected charIdx.i, ch.s, nextCh.s, prevCh.s
         Protected inString.b = #False, inChar.b = #False
         For charIdx = 1 To Len(line)
            ch = Mid(line, charIdx, 1)
            If charIdx < Len(line)
               nextCh = Mid(line, charIdx + 1, 1)
            Else
               nextCh = ""
            EndIf
            If charIdx > 1
               prevCh = Mid(line, charIdx - 1, 1)
            Else
               prevCh = ""
            EndIf

            ; Track string/char literals
            If ch = Chr(34) And prevCh <> "\"  ; Double quote
               inString = ~inString
            ElseIf ch = "'" And prevCh <> "\"
               inChar = ~inChar
            EndIf

            ; Convert dot to backslash if:
            ; - Not in string/char literal
            ; - Not a decimal (prev/next not digit)
            ; - Not a type suffix (.i .f .s .d followed by space/semicolon/operator)
            ; - Not a type annotation (.TypeName where TypeName starts with capital)
            If ch = "." And Not inString And Not inChar
               Protected isDecimal.b = #False
               Protected isTypeSuffix.b = #False
               Protected isTypeAnnotation.b = #False

               ; Check if decimal number
               ; V1.030.23: Fixed decimal detection - require digit AFTER dot (fractional part)
               ; Old check was too broad: rect1.topLeft matched because prevCh="1" is digit
               ; Correct: 10.5 (nextCh="5"), .5 (nextCh="5") are decimals
               ; Not decimal: rect1.topLeft (nextCh="t"), arr1.field (nextCh="f")
               If nextCh >= "0" And nextCh <= "9"
                  isDecimal = #True
               EndIf

               ; Check if type suffix (.i .f .s .d)
               If (LCase(nextCh) = "i" Or LCase(nextCh) = "f" Or LCase(nextCh) = "s" Or LCase(nextCh) = "d")
                  Protected charAfterSuffix.s = ""
                  If charIdx + 1 < Len(line)
                     charAfterSuffix = Mid(line, charIdx + 2, 1)
                  EndIf
                  ; V1.030.17: Added "[" for array declarations like data.i[5]
                  ; V1.030.22: Added "(" for function return types like func name.f(params)
                  If charAfterSuffix = "" Or charAfterSuffix = " " Or charAfterSuffix = ";" Or charAfterSuffix = "=" Or charAfterSuffix = ")" Or charAfterSuffix = "," Or charAfterSuffix = "+" Or charAfterSuffix = "-" Or charAfterSuffix = "*" Or charAfterSuffix = "/" Or charAfterSuffix = "<" Or charAfterSuffix = ">" Or charAfterSuffix = "!" Or charAfterSuffix = "&" Or charAfterSuffix = "|" Or charAfterSuffix = "[" Or charAfterSuffix = "("
                     isTypeSuffix = #True
                  EndIf
               EndIf

               ; V1.030.18/V1.030.19/V1.030.20/V1.030.21/V1.030.22: Check if type annotation (.TypeName where first letter is uppercase)
               ; Preserve if followed by '=', ';', '[', ')', or ',' (declarations and function parameters)
               ; Convert to backslash otherwise (field access like point.x where x is lowercase)
               If nextCh >= "A" And nextCh <= "Z"
                  ; Look ahead to see if this type annotation is followed by delimiter
                  ; Scan forward from current position to find delimiter
                  Protected lookAheadIdx.i = charIdx + 2  ; Start after the capital letter
                  Protected foundTypeDelim.b = #False
                  While lookAheadIdx <= Len(line)
                     Protected lookCh.s = Mid(line, lookAheadIdx, 1)
                     ; V1.030.22: Added ')' and ',' for function parameters like func foo(r.Rectangle, p.Point)
                     ; V1.031.23: Added '\' for auto-declare syntax like rect.Rectangle\pos\x = 10
                     If lookCh = "=" Or lookCh = ";" Or lookCh = "[" Or lookCh = ")" Or lookCh = "," Or lookCh = "\"
                        foundTypeDelim = #True
                        Break
                     ElseIf lookCh = " " Or lookCh = Chr(9)  ; Space or tab - skip
                        lookAheadIdx + 1
                     ElseIf (lookCh >= "A" And lookCh <= "Z") Or (lookCh >= "a" And lookCh <= "z") Or (lookCh >= "0" And lookCh <= "9") Or lookCh = "_"
                        ; Part of identifier - continue
                        lookAheadIdx + 1
                     Else
                        ; Hit delimiter that's not a valid type terminator - stop looking
                        Break
                     EndIf
                  Wend

                  ; V1.030.22: Preserve dot for type annotations (declarations AND function parameters)
                  ; Only convert to backslash for field access (lowercase after dot)
                  If foundTypeDelim
                     isTypeAnnotation = #True
                  EndIf
               EndIf

               If Not isDecimal And Not isTypeSuffix And Not isTypeAnnotation
                  convertedLine + "\"  ; Replace dot with backslash
               Else
                  convertedLine + ch
               EndIf
            Else
               convertedLine + ch
            EndIf
         Next
         line = convertedLine

         gszFileText + line + #LF$

         If FindString( line, "func", #PB_String_NoCase ) Or FindString( line, "function", #PB_String_NoCase )
            ParseFunctions( line, i )
         EndIf
      ForEver

      gMemSize = Len( gszFileText )
      sizeAfterMacros = gMemSize
   EndProcedure
   ;- =====================================
   ;- Parser
   ;- =====================================
   ;-
   ;- Scanner procedures moved to c2-scanner-v01.pbi
   ;- AST/Syntax Analyzer procedures moved to c2-ast-v01.pbi
   ;- Code Generator procedures moved to c2-codegen-v01.pbi
   ;-
   ;- =====================================
   ;- Constant Extraction Pass
   ;- =====================================
   ; V1.022.21: Pre-allocate slots for all constants before codegen
   ; This enables slot-only optimization (no stack-based value passing)
   Procedure         ExtractConstants()
      Protected slot.i
      Protected constValue.s
      Protected constCount.i = 0

      ; Clear maps from previous compilation
      ClearMap(mapConstInt())
      ClearMap(mapConstFloat())
      ClearMap(mapConstStr())

      ; Scan all tokens for constants
      ; V1.023.27: Debug - show all string tokens being processed
      Debug "ExtractConstants: Scanning " + Str(ListSize(TOKEN())) + " tokens..."
      ForEach TOKEN()
         Select TOKEN()\TokenType
            Case #ljINT
               constValue = TOKEN()\value
               ; Check if already registered
               If Not FindMapElement(mapConstInt(), constValue)
                  ; Allocate new slot for this constant
                  slot = gnLastVariable
                  gVarMeta(slot)\name = constValue
                  gVarMeta(slot)\valueInt = Val(constValue)
                  gVarMeta(slot)\flags = #C2FLAG_CONST | #C2FLAG_INT
                  gVarMeta(slot)\paramOffset = -1
                  gnLastVariable + 1
                  ; Register in map
                  mapConstInt(constValue) = slot
                  constCount + 1
               EndIf

            Case #ljFLOAT
               constValue = TOKEN()\value
               If Not FindMapElement(mapConstFloat(), constValue)
                  slot = gnLastVariable
                  gVarMeta(slot)\name = constValue
                  gVarMeta(slot)\valueFloat = ValF(constValue)
                  gVarMeta(slot)\flags = #C2FLAG_CONST | #C2FLAG_FLOAT
                  gVarMeta(slot)\paramOffset = -1
                  gnLastVariable + 1
                  mapConstFloat(constValue) = slot
                  constCount + 1
               EndIf

            Case #ljSTRING
               constValue = TOKEN()\value
               ; V1.023.27: Debug - trace string constant extraction
               CompilerIf #DEBUG
                  Debug "ExtractConstants: Found string token '" + constValue + "'"
               CompilerEndIf
               If Not FindMapElement(mapConstStr(), constValue)
                  slot = gnLastVariable
                  gVarMeta(slot)\name = constValue
                  gVarMeta(slot)\valueString = constValue
                  gVarMeta(slot)\flags = #C2FLAG_CONST | #C2FLAG_STR
                  gVarMeta(slot)\paramOffset = -1
                  gnLastVariable + 1
                  mapConstStr(constValue) = slot
                  constCount + 1
                  CompilerIf #DEBUG
                     Debug "  -> Added to mapConstStr, slot=" + Str(slot)
                  CompilerEndIf
               Else
                  CompilerIf #DEBUG
                     Debug "  -> Already in mapConstStr, slot=" + Str(mapConstStr())
                  CompilerEndIf
               EndIf
         EndSelect
      Next

      CompilerIf #DEBUG
         Debug " -- ExtractConstants: " + Str(constCount) + " unique constants pre-allocated"
      CompilerEndIf
   EndProcedure

   ;- =====================================
   ;- Compiler
   ;- =====================================
   Procedure         Compile()
      Protected      i
      Protected      err
      Protected      *p.stTree
      Protected      total
      Protected.s    temp

      Init()
      Debug " -- Preprocessing source..."
      Preprocessor()

      Debug " -- Scanner pass: Lexical analysis and tokenization..."
      If Scanner()
         Debug "Scanner failed with error: " + gszlastError
         ProcedureReturn 1
      EndIf

      ; V1.022.21: Pre-allocate slots for all constants (enables slot-only optimization)
      ExtractConstants()

      ; V1.029.91: Auto-declare struct variables at function start
      Debug " -- Auto-declaring struct variables..."
      AutoDeclareStructVars()

      ;par_DebugParser()
      Debug " -- AST pass: Building abstract syntax tree..."
      ReorderTokens()

      FirstElement( TOKEN() )
      total = ListSize( TOKEN() ) - 1

      Repeat
         gStack = 0
         *p = MakeNode( #ljSEQ, *p, stmt() )

         If gLastError
            Debug "AST Error > " + gszlastError
            gExit = -1
            Break
         EndIf

      Until ListIndex( TOKEN() ) >= total Or gExit

      If gExit >= 0
         ;- DisplayNode( *p )
         ; V1.030.0: Run variable metadata verification pass before codegen
         ; This catches and auto-fixes common issues like missing STRUCT flags
         VerifyVariableMetadata()

         CodeGenerator( *p )

         ; V1.023.26: Check for errors after code generation (e.g., type conflicts)
         If gLastError
            Debug "CodeGen Error > " + gszlastError
            gExit = -1
         EndIf
      EndIf

      If gExit >= 0
         ; V1.020.077: Initialize jump tracker BEFORE optimization passes
         ; This allows PostProcessor to call AdjustJumpsForNOOP() with populated tracker
         Debug " -- InitJumpTracker: Calculating initial jump offsets..."
         InitJumpTracker()

         ; PostProcessor does type fixups AND optimizations
         ; Type fixups are necessary, so we always run it
         ; The pragma controls optimization passes within PostProcessor
         ; Optimization passes will call AdjustJumpsForNOOP() to adjust offsets incrementally
         Debug " -- Postprocessor: Optimizing and fixing bytecode..."
         PostProcessor()

         ; V1.020.077: FixJMP now just applies adjusted offsets and patches functions
         ; Jump tracker was already populated by InitJumpTracker() before optimization
         Debug " -- FixJMP: Applying adjusted offsets and patching functions..."
         FixJMP()
         LastElement( llObjects() )
         EmitInt( #LJEOF )

         ;- This is a "hack" to merge with VM
         vm_ListToArray( llObjects, arCode )

         ; V1.030.9: Debug - verify STRUCT_*_LOCAL opcodes in arCode after conversion
         Debug "=== ARCODE: Checking STRUCT_*_LOCAL opcodes ==="
         Protected acCheckIdx.i
         For acCheckIdx = 0 To ArraySize(arCode()) - 1
            Select arCode(acCheckIdx)\code
               Case #ljSTRUCT_ALLOC_LOCAL
                  Debug "  [" + Str(acCheckIdx) + "] STRUCT_ALLOC_LOCAL .i=" + Str(arCode(acCheckIdx)\i) + " .j=" + Str(arCode(acCheckIdx)\j)
               Case #ljSTRUCT_FETCH_INT_LOCAL
                  Debug "  [" + Str(acCheckIdx) + "] STRUCT_FETCH_INT_LOCAL .i=" + Str(arCode(acCheckIdx)\i) + " .j=" + Str(arCode(acCheckIdx)\j)
               Case #ljSTRUCT_FETCH_FLOAT_LOCAL
                  Debug "  [" + Str(acCheckIdx) + "] STRUCT_FETCH_FLOAT_LOCAL .i=" + Str(arCode(acCheckIdx)\i) + " .j=" + Str(arCode(acCheckIdx)\j)
               Case #ljSTRUCT_FETCH_STR_LOCAL
                  Debug "  [" + Str(acCheckIdx) + "] STRUCT_FETCH_STR_LOCAL .i=" + Str(arCode(acCheckIdx)\i) + " .j=" + Str(arCode(acCheckIdx)\j)
               Case #ljSTRUCT_STORE_INT_LOCAL
                  Debug "  [" + Str(acCheckIdx) + "] STRUCT_STORE_INT_LOCAL .i=" + Str(arCode(acCheckIdx)\i) + " .j=" + Str(arCode(acCheckIdx)\j)
               Case #ljSTRUCT_STORE_FLOAT_LOCAL
                  Debug "  [" + Str(acCheckIdx) + "] STRUCT_STORE_FLOAT_LOCAL .i=" + Str(arCode(acCheckIdx)\i) + " .j=" + Str(arCode(acCheckIdx)\j)
               Case #ljSTRUCT_STORE_STR_LOCAL
                  Debug "  [" + Str(acCheckIdx) + "] STRUCT_STORE_STR_LOCAL .i=" + Str(arCode(acCheckIdx)\i) + " .j=" + Str(arCode(acCheckIdx)\j)
            EndSelect
         Next
         Debug "=== END ARCODE CHECK ==="

         ; List assembly if requested (check pragma listasm - default OFF)
         If FindMapElement(mapPragmas(), "dumpasm")
            If LCase(mapPragmas()) = "on" Or mapPragmas() = "1" Or mapPragmas() = "true"
               ListCode()
            EndIf
         EndIf

         ; Display any warnings that were collected during compilation
         If ListSize(gWarnings()) > 0
            Debug "=== Compilation Warnings ==="
            ForEach gWarnings()
               Debug gWarnings()
            Next
            Debug "=== End of Warnings ==="
         EndIf

         ; V1.023.0: Display any info messages (preload optimizations)
         If ListSize(gInfos()) > 0
            Debug "=== Optimization Info ==="
            ForEach gInfos()
               Debug gInfos()
            Next
            Debug "=== End of Info ==="
         EndIf

         ; Successful compilation - reset gExit to 0
         gExit = 0
      Else
         Debug "gExit=" + Str(gExit)
      EndIf

      ProcedureReturn gExit
   EndProcedure
EndModule

CompilerIf #PB_Compiler_IsMainFile
   ; -- Module demo
   EnableExplicit   

   Define         err
   Define.s       filename, lookpath
   
   lookpath  = ".\Examples\"
   
   ;filename = ".\Examples\07 floats and macros.lj"
   ;filename = ".\Examples\00 comprehensive test.lj"
   ;filename = ".\Examples\20 array sort stress test.lj"
   ;filename = ".\Examples\22 array comprehensive.lj"
   ;filename = ".\Examples\50 full test suite.lj"
   
   ;filename = ".\Examples\23 test increment operators.lj"
   ;filename = ".\Examples\29 test type inference comprehensive.lj"
   ;filename = ".\Examples\31 test advanced pointers.lj":n
   ;filename = ".\Examples\32 test advanced pointers working.lj" 
   ;filename = ".\Examples\33 test mixed type pointers.lj"
   
   ;filename = ".\Examples\28 test pointers comprehensive.lj"
   ;filename = ".\Examples\27 test function pointers.lj"
   ;filename = ".\Examples\38 test struct arrays.lj"
   ;filename = ".\Examples\106 address book.lj"
   
   filename = ".\Examples\001 Simple while.lj"
   ;filename = ".\Examples\002 if else.lj"
   filename = ".\Examples\200 opcode benchmark.lj"
   
   ; V1.031.32: Command line argument support
   ; V1.031.117: Added --test flag for console output without GUI
   Define paramCount.i
   Define paramIdx.i
   Define param.s

   If CountProgramParameters() > 0
      paramCount = CountProgramParameters()

      For paramIdx = 0 To paramCount - 1
         param = ProgramParameter(paramIdx)
         If param = "--test" Or param = "-t"
            C2VM::gTestMode = #True
         ElseIf Left(param, 1) <> "-"
            ; Not a flag - must be filename
            filename = param
         EndIf
      Next
   Else
      ; V1.031.28: Cross-platform path handling (default test file)
      CompilerIf #PB_Compiler_OS <> #PB_OS_Windows
          filename = ReplaceString( filename, "\", "/" )
          lookpath = ReplaceString( lookpath, "\", "/" )
      CompilerEndIf
   EndIf
   ;filename = ".\Examples\bug fix2.lj"
   ;filename = OpenFileRequester( "Please choose source", lookpath, "LJ Files|*.lj", 0 )

   If filename > ""
      Debug "==========================================="
      Debug "Executing: " + filename
      Debug "==========================================="
      
      If C2Lang::LoadLJ( filename )
         Debug "Error: " + C2Lang::Error( @err )
      Else
         C2VM::gModuleName = filename
         ; V1.023.26: Only run VM if compilation succeeds (returns 0)
         ; Compile returns: 0=success, 1=scanner error, -1=AST/CodeGen error
         If C2Lang::Compile() = 0
            C2VM::RunVM()
         Else
            Debug "Compilation failed - VM not started"
         EndIf
      EndIf
   EndIf

CompilerEndIf
; IDE Options = PureBasic 6.21 (Windows - x64)
; CursorPosition = 12
; Folding = --------
; Markers = 569,718
; Optimizer
; EnableThread
; EnableXP
; CPU = 1
; LinkerOptions = linker.txt
; CompileSourceDirectory
; Warnings = Display
; EnableCompileCount = 2380
; EnableBuildCount = 0
; EnableExeConstant
; IncludeVersionInfo