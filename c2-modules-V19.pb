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

DisableDebugger
EnableDebugger

DeclareModule C2Common

   ;#DEBUG = 0
   XIncludeFile         "c2-inc-v15.pbi"
EndDeclareModule

Module C2Common
   ;Empty by design

EndModule

DeclareModule C2Lang
   EnableExplicit
   #WithEOL = 1
   #C2PROFILER = 0
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

XIncludeFile            "c2-vm-V13.pb"

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
   XIncludeFile         "c2-postprocessor-V06.pbi"

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
      InstallBuiltin( "sqrt",              #ljBUILTIN_SQRT,         1, 1, #C2FLAG_FLOAT )
      InstallBuiltin( "pow",               #ljBUILTIN_POW,          2, 2, #C2FLAG_FLOAT )
      InstallBuiltin( "len",               #ljBUILTIN_LEN,          1, 1, #C2FLAG_INT )
      ; V1.023.29: Add str() and strf() conversion functions
      InstallBuiltin( "str",               #ljITOS,                 1, 1, #C2FLAG_STR )
      InstallBuiltin( "strf",              #ljFTOS,                 1, 1, #C2FLAG_STR )
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
   XIncludeFile         "c2-ast-v04.pbi"
   XIncludeFile         "c2-codegen-v04.pbi"

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
      Protected.i       i, len, inString, inChar, inLineComment, inBlockComment
      Protected.i       escaped

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
               Debug "ExtractConstants: Found string token '" + constValue + "'"
               If Not FindMapElement(mapConstStr(), constValue)
                  slot = gnLastVariable
                  gVarMeta(slot)\name = constValue
                  gVarMeta(slot)\valueString = constValue
                  gVarMeta(slot)\flags = #C2FLAG_CONST | #C2FLAG_STR
                  gVarMeta(slot)\paramOffset = -1
                  gnLastVariable + 1
                  mapConstStr(constValue) = slot
                  constCount + 1
                  Debug "  -> Added to mapConstStr, slot=" + Str(slot)
               Else
                  Debug "  -> Already in mapConstStr, slot=" + Str(mapConstStr())
               EndIf
         EndSelect
      Next

      Debug " -- ExtractConstants: " + Str(constCount) + " unique constants pre-allocated"
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
         Debug " -- Code generator pass: Generating bytecode from AST..."
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
   Define.s       filename
   
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
   
   filename = ".\Examples\42 test switch.lj"
   ;filename = ".\Examples\bug fix2.lj"
   filename = OpenFileRequester( "Please choose source", ".\Examples\", "LJ Files|*.lj", 0 )

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
; CursorPosition = 1396
; FirstLine = 1376
; Folding = -------
; Markers = 570,719
; Optimizer
; EnableThread
; EnableXP
; CPU = 1
; EnableCompileCount = 1872
; EnableBuildCount = 0
; EnableExeConstant
; IncludeVersionInfo