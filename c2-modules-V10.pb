
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

DeclareModule C2Common

   XIncludeFile         "c2-inc-v06.pbi"
   XIncludeFile         "c2-builtins.pbi"
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
 
   Structure stTree
      NodeType.i
      TypeHint.i
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

XIncludeFile            "c2-vm-V05.pb"

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
      Index.l
      row.l
      nCall.u
      *NewPos
      bTypesLocked.i  ; Flag: Types locked on first call
      returnType.w    ; Return type flags (INT/FLOAT/STR)
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

; ======================================================================================================
;- Functions
; ======================================================================================================
   
Declare                 FetchVarOffset(text.s, *assignmentTree.stTree = 0, syntheticType.i = 0)
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
   Global NewMap        mapMacros.stMacro()
   Global NewMap        mapModules.stModInfo()
   Global NewMap        mapBuiltins.stBuiltinDef()

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
   Global               gCodeGenRecursionDepth
   Global               gCurrentFunctionName.s  ; Current function being compiled (for local variable scoping)
   Global               gLastExpandParamsCount  ; Last actual parameter count from expand_params() for built-ins
   Global               gIsNumberFlag
   Global               gEmitIntCmd.i
   Global               gEmitIntLastOp

   Global               gszFileText.s
   Global               gNextChar.s
   Global               gLastError
   Global               gszEOF.s          = Chr( 255 )
   
   CompilerIf #PB_OS_Linux
      Global            gszSep.s          = #LF$
   CompilerElse
      Global            gszSep.s          = #CRLF$
   CompilerEndIf
      
   ;Global              gszFloating.s = "^[+-]?([0-9]*[.])?[0-9]+$"
   Global               gszFloating.s = "^[+-]?(\d+(\.\d*)?|\.\d+)([eE][+-]?\d+)?$"
   
   CreateRegularExpression( #C2REG_FLOATS, gszFloating )
   
   Declare              paren_expr()
   ;- =====================================
   ;- Generic
   ;- =====================================
   Macro             TOKEN()
      llTokenList()
   EndMacro
   Macro             Install( symbolname, id  )
      AddElement( llSymbols() )
         llSymbols()\name        = symbolname
         llSymbols()\TokenType   = id
   EndMacro
   Macro                SetError( text, err )
      If err > 0 And err < 10
         gszlastError   = text + " on line " + Str( gLineNumber ) + ", col = " + Str( gCol )
      ElseIf err > 10
         gszlastError   = text + " on line " + Str( llTokenList()\row ) + ", col = " + Str( llTokenList()\col )
      Else
         gszlastError   = text
      EndIf
      
      gLastError     = err
      
      ProcedureReturn err
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
   Macro             par_AddTokenSimple( tkentype )
      AddElement( llTokenList() )
         llTokenList()\TokenType = tkentype
         llTokenList()\TokenExtra= tkentype
         llTokenList()\name      = gszATR( tkentype )\s
         llTokenList()\row       = gLineNumber
         llTokenList()\col       = gCol
         llTokenList()\function  = gCurrFunction
   EndMacro
   
   Macro             par_AddToken( tkentype, tkenextra, text, info )
      AddElement( llTokenList() )
         llTokenList()\TokenType = tkentype
         llTokenList()\TokenExtra= tkenextra
         llTokenList()\row       = gLineNumber
         llTokenList()\col       = gCol
         llTokenList()\function  = gCurrFunction
         
         If text = ""
            If tkentype = #ljSTRING
               gStrings + 1
               llTokenList()\name = "_str" + Str(gStrings)
            ElseIf tkentype = #ljINT
               gIntegers + 1
               llTokenList()\name = "_int" + Str(gIntegers)
            ElseIf tkentype = #ljFLOAT
               gFloats + 1
               llTokenList()\name = "_flt" + Str(gFloats)
            Else
               llTokenList()\name = gszATR( tkenextra )\s
            EndIf
         Else
            llTokenList()\name      = text
         EndIf
         
         llTokenList()\value    = info
   EndMacro
   Macro                par_NextCharacter()
      gNextChar = Mid( gszFileText, gPos, 1 )
      gPos + 1 : gCol + 1
      
      If gNextChar = #LF$
         gCol = 1
         gLineNumber + 1
         
         gNextChar = Mid( gszFileText, gPos, 1 )
         gPos + 1
      EndIf
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
      ; Register random()
      AddMapElement(mapBuiltins(), "random")
      mapBuiltins()\name = "random"
      mapBuiltins()\opcode = #ljBUILTIN_RANDOM
      mapBuiltins()\minParams = 0
      mapBuiltins()\maxParams = 2
      mapBuiltins()\returnType = #C2FLAG_INT

      ; Register abs()
      AddMapElement(mapBuiltins(), "abs")
      mapBuiltins()\name = "abs"
      mapBuiltins()\opcode = #ljBUILTIN_ABS
      mapBuiltins()\minParams = 1
      mapBuiltins()\maxParams = 1
      mapBuiltins()\returnType = #C2FLAG_INT

      ; Register min()
      AddMapElement(mapBuiltins(), "min")
      mapBuiltins()\name = "min"
      mapBuiltins()\opcode = #ljBUILTIN_MIN
      mapBuiltins()\minParams = 2
      mapBuiltins()\maxParams = 2
      mapBuiltins()\returnType = #C2FLAG_INT

      ; Register max()
      AddMapElement(mapBuiltins(), "max")
      mapBuiltins()\name = "max"
      mapBuiltins()\opcode = #ljBUILTIN_MAX
      mapBuiltins()\minParams = 2
      mapBuiltins()\maxParams = 2
      mapBuiltins()\returnType = #C2FLAG_INT
   EndProcedure
   CompilerEndIf

   ;-
   Procedure            Init()
      Protected         temp.s
      Protected         i, n, m
      Protected         verFile.i, verString.s

      For i = 0 To #C2MAXCONSTANTS
         gVar(i)\name   = ""
         gVar(i)\ss     = ""
         gVar(i)\p      = 0
         gVar(i)\i      = 0
         gVar(i)\f      = 0.0
         gVar(i)\flags  = 0
         gVar(i)\paramOffset = 0
      Next
      
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
      par_SetPre( #ljLESS,         0, 1, 0, 10 )
      par_SetPre( #ljLESSEQUAL,    0, 1, 0, 10 )
      par_SetPre( #ljGREATER,      0, 1, 0, 10 )
      par_SetPre( #ljGreaterEqual, 0, 1, 0, 10 )
      par_SetPre( #ljEQUAL,        0, 1, 0, 9 )
      par_SetPre( #ljNotEqual,     0, 1, 0, 9 )
      par_SetPre2( #ljASSIGN,      #ljASSIGN )
      par_SetPre( #ljAND,          0, 1, 0, 5 )
      par_SetPre( #ljOr,           0, 1, 0, 4 )
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
      ResetList( llObjects() )
      ClearList( llObjects() )
      ResetList( llTokenList() )
      ClearList( llTokenList() )
      ResetList( llSymbols() )
      ClearList( llSymbols() )
      ResetList( llHoles() )
      ClearList( llHoles() )
      ClearMap( mapPragmas() )
      ClearMap( mapMacros() )
      ClearMap( mapModules() )

      ; Add #LJ2_VERSION from _lj2.ver file
      verFile = ReadFile(#PB_Any, "_lj2.ver")
      If verFile
         verString = ReadString(verFile)
         CloseFile(verFile)
      Else
         verString = "0"  ; Default if file not found
      EndIf
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
      gnLastVariable          = 0
      gStrings                = 0
      gFloats                 = 0
      gIntegers               = 0
      gNextFunction           = #C2FUNCSTART
      gCodeGenFunction        = 0
      gCodeGenParamIndex      = -1
      gCodeGenRecursionDepth  = 0
      gCurrentFunctionName    = ""  ; Empty = global scope
      gLastExpandParamsCount  = 0
      gIsNumberFlag           = 0
      gEmitIntCmd             = #LJUnknown
      gEmitIntLastOp          = 0

      Install( "else", #ljElse )
      install( "if",    #ljIF )
      install( "print", #ljPRint )
      install( "putc",  #ljPRTC )
      install( "while", #ljWHILE )
      install( "func", #ljfunction )
      install( "return", #ljreturn )
      install( "call", #ljCall )

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
   
   
   ;- =====================================
   ;- Preprocessors
   ;- =====================================
   Macro                pre_FindNextWord( tsize, withinv, extra )
      p = Trim( Mid( p, tsize ) )
      
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
      Trim( Trim( string ), #TAB$ )
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

      ;Debug "Checking functions for line: " + line
      i     = 1 : j = 1
      p     = pre_TrimWhiteSpace( line )

      If FindString( p, "func", #PB_String_NoCase ) = 1
         ;It's probably a function
         i + 4
         pre_FindNextWord( 5, 0, "." )
         name  = Left( p, j - 1 )

         ; Extract return type from function name suffix (.f or .s)
         funcReturnType = #C2FLAG_INT  ; Default to INT
         baseName = name
         
         If Right(name, 2) = ".f" Or Right(name, 2) = ".d" 
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
         EndIf
      EndIf
   EndProcedure
   
   Procedure            ParseDefinitions( line.s )
      Protected         bInv, Bracket
      Protected         i, j
      Protected         tmpMod.stModInfo
      Protected.s       temp, nc, name, p, param
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
         pre_FindNextWord( 8, 0, "" )
         name  = Left( p, j - 1 )
         temp  = UCase( name )
         
         AddMapElement( mapMacros(), temp )
         p     = Trim( Mid( p, j ) )
          
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

      lenInput = Len( line )
      output   = ""
      
      If Mid( line, lenInput , 1 ) = #CR$
         lenInput - 1
      EndIf
      
      While p <= lenInput
         ; If identifier start
         If FindString( "#abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ_", Mid( line, p, 1 ), 1 )
            start = p
         
            While p <= lenInput And FindString( "#abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_", Mid( line, p, 1 ), 1 )
              p + 1
            Wend
            
            ident    = Mid( line, start, p - start )
            temp     = UCase( ident )
      
            ; Macro lookup
            If FindMapElement( mapMacros(), temp )
               m = mapMacros()
               
               ; If function-like, parse args
               If Left( Mid( line, p, 1 ), 1 ) = "(" And ListSize( m\llParams() )
                  ; Consume '('
                  p + 1 : depth = 0
                  argStart = p
                  ClearList( ll() )
      
                  ; Build argument list by counting parentheses
                  While p <= lenInput
                     If Mid( line, p, 1 ) = "(" : depth + 1
                     ElseIf Mid( line, p, 1 ) = ")" 
                        If depth = 0 : Break : EndIf
                        depth - 1
                     ElseIf Mid( line, p, 1 ) = "," And depth = 0
                        ; Split argument
                        AddElement( ll() )
                        ll() = Trim( Mid( line, argStart, p - argStart ) )
                        argStart = p + 1
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
            EndIf
            i + 1
            Continue
         EndIf

         ; Handle block comment
         If inBlockComment
            If char = "*" And nextChar = "/"
               inBlockComment = #False
               i + 2  ; Skip */
               Continue
            EndIf
            ; Replace comment content with space to preserve some formatting
            If char = #LF$ Or char = #CR$
               result + char  ; Preserve newlines for line numbering
            EndIf
            i + 1
            Continue
         EndIf

         ; Check for start of comments (only if not in string/char)
         If char = "/" And nextChar = "/"
            inLineComment = #True
            i + 2  ; Skip //
            Continue
         EndIf

         If char = "/" And nextChar = "*"
            inBlockComment = #True
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
      Protected.s       szNewBody = ""

      ; Strip all comments from source before processing
      gszFileText = StripComments(gszFileText)

      ; First we find and store our macros
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
            ;Debug mapMacros()\name + " --> " + mapMacros()\strparams + " --> " + mapMacros()\body
         EndIf
      ForEver
      
      ; Macro Expansion
      i = 0 : gszFileText = ""
      
      Repeat
         i + 1
         line = StringField( szNewBody, i, #LF$ )
         If line = "" : Break : EndIf
         
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
         
         If FindString( line, "func", #PB_String_NoCase )
            ParseFunctions( line, i )
         EndIf
      ForEver

      gMemSize = Len( gszFileText )
   EndProcedure
   ;- =====================================
   ;- Parser 
   ;- =====================================
   ; PureBasic procedure to detect if a string represents an Integer, Float, or neither (String)
   Macro                par_DebugParser()
      Debug "---[ Parser ]--------------"
   
      ForEach llTokenList()
         temp = RSet( Str(llTokenList()\row), 6 ) + "   " + RSet( Str(llTokenList()\col), 6 ) + "   "
         
         If llTokenList()\TokenExtra <> llTokenList()\TokenType
            temp + LSet( gszATR( llTokenList()\TokenType )\s + "_" + llTokenList()\name, 34 ) + llTokenList()\value
         Else
            temp + LSet( llTokenList()\name, 34 ) + llTokenList()\value
         EndIf
         
         If llTokenList()\function >= #C2FUNCSTART
            temp +  RSet( "{mod#" + Str( llTokenList()\function - #C2FUNCSTART + 1 ) + "}", 15 )
         EndIf
         
         Debug temp
      Next
   EndMacro             
   ;-
   Procedure            DetectType( Input.s )
      Protected.s       s = Trim(Input)
      Protected.s       c
      Protected.b       isInteger = #True
      Protected.i       i
      
      If s = ""
         ; Empty string considered as String type
         ProcedureReturn #ljSTRING
      EndIf

      ; Check integer: optional leading + or -, followed by digits only
   
      For i = 1 To Len(s)
         c = Mid( s, i, 1 )
         If i = 1 And ( c = "+" Or c = "-" )
            Continue ; sign is allowed at first position
         ElseIf c >= "0" And c <= "9"
            Continue ; digit is allowed
         Else
            isInteger = #False
            Break
         EndIf
      Next i
      
      If isInteger = #True
         ProcedureReturn #ljINT
      EndIf
   
      ; Check float: optional leading + or -, one decimal point, digits around it
      Protected         dotCount.i = 0
      Protected         digitCount.i = 0
      Protected         hasDigitBeforeDot.b = #False
      Protected         hasDigitAfterDot.b = #False
   
      For i = 1 To Len(s)
         c = Mid( s, i, 1 )
         If c = "."
            dotCount + 1
            If dotCount > 1
               ; more than one decimal point -> not a valid float
               dotCount = -1
               Break
            EndIf
         ElseIf i = 1 And ( c = "+" Or c = "-" )
            Continue ; sign allowed at first position
         ElseIf c >= "0" And c <= "9"
            digitCount + 1
            If dotCount = 0
               hasDigitBeforeDot = #True
            Else
               hasDigitAfterDot = #True
            EndIf
         Else
            ; invalid character for float
            dotCount = -1
            Break
         EndIf
      Next i
   
      If dotCount = 1 And hasDigitBeforeDot And hasDigitAfterDot
         ProcedureReturn #ljFLOAT
      EndIf
   
   ; If not integer or float, treat as string
   ProcedureReturn #ljSTRING
EndProcedure
   
   Procedure            IsNumber( init.i = 0 )
      If init
         gIsNumberFlag = 0
      Else
         If gNextChar >= "0" And gNextChar <= "9"
            ProcedureReturn 1
         ElseIf Not gIsNumberFlag And gNextChar = "."
            gIsNumberFlag + 1
            ProcedureReturn 1
         EndIf
      EndIf

      ProcedureReturn 0
   EndProcedure
   
   Procedure            IsAlpha()
      If ( gNextChar >= "a" And gNextChar <= "z" ) Or (gNextChar >= "A" And gNextChar <= "Z"  ) Or IsNumber()
         ProcedureReturn 1
      EndIf
      
      ProcedureReturn 0
   EndProcedure
   
   Procedure            Follow( expect.s, ifyes.i, ifno.i, *err.Integer )
      par_NextCharacter()
      
      If gNextChar = expect
         par_AddToken( #ljOP, ifyes, "", "" )
      Else
         If ifno = -1
            *err\i = #C2ERR_UNRECOGNIZED_CHAR
            SetError( "Unrecognized character sequence", #C2ERR_UNRECOGNIZED_CHAR )
         Else
            par_AddToken( #ljOP, ifno, "", ""  )
            gPos - 1
         EndIf
      EndIf
      
      ProcedureReturn 0
   EndProcedure
   ; Reads character by character creating tokens used by the syntax checker and code generator
   Procedure            Scanner()
      Protected         err, first, i
      Protected.i       dots, bFloat, e
      Protected.i       braces
      Protected.s       text, temp

      Debug "=== Scanner() called ==="
      Debug "gMemSize: " + Str(gMemSize)
      Debug "gszFileText length: " + Str(Len(gszFileText))

      gpos           = 1
      gCurrFunction  = 1

      While gPos <= gMemSize
         par_NextCharacter()
         
         Select gNextChar
            Case gszEOF
               par_AddTokenSimple( #ljEOF )
               Break

            Case " ", #CR$, #TAB$, ""
               Continue
            
            Case "{"
               braces + 1
               par_AddTokenSimple( #ljLeftBrace )
               
            Case "}"
               braces - 1
               par_AddTokenSimple( #ljRightBrace )
               If braces = 0 : gCurrFunction = 1 : EndIf
               
            Case "("
               par_AddTokenSimple( #ljLeftParent )
            Case ")"
               par_AddTokenSimple( #ljRightParent )
            Case "+"
               par_AddToken( #ljOP, #ljADD, "", "" )
            Case "-"
               par_AddToken( #ljOP, #ljSUBTRACT, "", "" )
            Case "*"
               par_AddToken( #ljOP, #ljMULTIPLY, "", "" )
            Case "%"    
               par_AddToken( #ljOP, #ljMOD, "", "" )
            Case ";"
               par_AddTokenSimple( #ljSemi )
            Case ","
               par_AddTokenSimple( #ljComma )
            Case "?"
               par_AddTokenSimple( #ljQUESTION )
            Case ":"
               par_AddTokenSimple( #ljCOLON )
            Case "/"
               ; Comments are already stripped in preprocessor, so just handle division
               par_AddToken( #ljOP, #ljDIVIDE, "", "" )
            Case "'"
               par_NextCharacter()


               If gNextChar = "'"
                  SetError( "Empty character literal", #C2ERR_EMPTY_CHAR_LITERAL )
               ElseIf gNextChar = "\"
                  par_NextCharacter()
                  
                  Select gNextChar
                     Case "'"
                        SetError( "Empty escape character literal", #C2ERR_EMPTY_CHAR_LITERAL )
                     Case "n"
                        first = 10
                     Case "r"
                        first = 13
                     Case "\"
                        first = 92
                     Default
                        SetError( "Invalid escape character", #C2ERR_INVALID_ESCAPE_CHAR )
                  EndSelect
               Else
                  first = Asc( gNextChar )
               EndIf
               
               par_NextCharacter()

               If gNextChar <> "'"
                  SetError( "Multi-character literal", #C2ERR_MULTI_CHAR_LITERAL )
               Else
                  par_AddToken( #ljINT, #ljINT, "", Str(first) )
               EndIf
               
            Case "<"
               If Follow( "=", #ljLESSEQUAL, #ljLESS, @err ) : ProcedureReturn err : EndIf
            Case ">"
               If Follow( "=", #ljGreaterEqual, #ljGREATER, @err ) : ProcedureReturn err : EndIf
            Case "!"
               If Follow( "=", #ljNotEqual, #ljNOT, @err ) : ProcedureReturn err : EndIf
            Case "="
               If Follow( "=", #ljEQUAL, #ljASSIGN, @err ) : ProcedureReturn err : EndIf
            Case "&"
               If Follow( "&", #ljAND, -1, @err ) : ProcedureReturn err : EndIf
            Case "|"
               If Follow( "|", #ljOr, -1, @err ) : ProcedureReturn err : EndIf
            Case "%"
               If Follow( "%%", #ljxOr, -1, @err ) : ProcedureReturn err : EndIf
            
            Case #INV$
               par_NextCharacter()
               text = gNextChar
               
               Repeat
                  par_NextCharacter()
                  
                  If gNextChar = #INV$
                     e = DetectType( text )
                     par_AddToken( e, e, "", text )
                     Break
                  ElseIf gNextChar = #CR$
                     SetError( "EOL in string", #C2ERR_EOL_IN_STRING )
                  Else
                     text + gNextChar
                  EndIf
               
               Until gPos >= gMemSize

               If gPos >= gMemSize
                  SetError( "EOF in string", #C2ERR_EOF_IN_STRING )
               EndIf
            Default
               ; Handle EOF character explicitly
               If gNextChar = gszEOF Or Asc(gNextChar) = 255
                  par_AddTokenSimple( #ljEOF )
                  Break
               EndIf

               IsNumber( 1 )        ; reset digit flag

               first    = IsNumber()
               text     = ""
               dots     = 0
               bFloat   = 0
               e        = 0
               
               While gPos < gMemSize And ( IsAlpha() Or gNextChar = "_" Or gNextChar = "." )
                  If gNextChar = "." : dots + 1 : EndIf
                  If gNextChar = "e" Or gNextChar = "E" : e + 1 : EndIf
                  If Not IsNumber() : first = 0 : EndIf
                  text + gNextChar
                  par_NextCharacter()
               Wend

               If gPos >= gMemSize
                  SetError( "EOL in identifier '" + text + "'", #C2ERR_EOL_IN_IDENTIFIER )
               EndIf

               If Len( text ) < 1
                  SetError( "Unknown sequence or identifier '" + text + "'", #C2ERR_UNKNOWN_SEQUENCE )
               EndIf
               
               gPos - 1
               i = 0
               
               If (dots Or e) And MatchRegularExpression( #C2REG_FLOATS , text )
                  bFloat = 1
                  ;Debug text + " is a float."
               Else
                  ;Debug text + " Not float."
               EndIf
               
               If bFloat
                  par_AddToken( #ljFLOAT, #ljFLOAT, "", text )
               Else
                  temp = LCase( text )

                  ; Check for type suffix (.f or .s)
                  Protected typeHint.w = 0
                  Protected varName.s = text

                  If Right(temp, 2) = ".f" Or Right(temp, 2) = ".d"
                     typeHint = #ljFLOAT
                     varName = Left(text, Len(text) - 2)
                     temp = LCase(varName)
                  ElseIf Right(temp, 2) = ".s"
                     typeHint = #ljSTRING
                     varName = Left(text, Len(text) - 2)
                     temp = LCase(varName)
                  EndIf
                  
                  If FindMapElement( mapModules(), "_" + temp )
                     If mapModules()\row = gLineNumber And TOKEN()\TokenType = #ljFunction
                        gCurrFunction     = mapModules()\function
                        TOKEN()\function  = gCurrFunction
                        TOKEN()\value     = Str( gCurrFunction )
                     Else
                        par_AddToken( #ljCall, #ljCall, "", Str( mapModules()\function ) )
                     EndIf
                  Else
                     ; NOTE: Don't check built-ins here - allows variables to shadow built-in names
                     ; Built-ins will be checked in parser when identifier is followed by '('
                     ForEach llSymbols()
                        i + 1

                        If llSymbols()\name = temp
                           ;Debug "SYMBOL: " + temp
                           par_AddToken( llSymbols()\TokenType, llSymbols()\TokenType, "", varName )
                           TOKEN()\typeHint = typeHint
                           i = -1
                           Break
                        EndIf
                     Next

                     If i > 0
                        If first
                           par_AddToken( #ljINT, #ljINT, "", text )
                        Else
                           par_AddToken( #ljIDENT, #ljIDENT, "", varName )
                           TOKEN()\typeHint = typeHint
                        EndIf
                     EndIf
                  EndIf
               EndIf
         EndSelect
      Wend
      
      ProcedureReturn 0
   
   EndProcedure
   Procedure            ReorderTokens()
      Protected NewList llTemp.stToken()
      
      CopyList( llTokenList(), lltemp() )
      ClearList( llTokenList() )
      ; We need to put non function tokens at the top so all functions start after code end
      
      ForEach llTemp()
         If llTemp()\TokenType = #ljEOF
            ;Skip
         ElseIf llTemp()\function < #C2FUNCSTART
            AddElement( llTokenList() )
            llTokenList() = llTemp()
         EndIf
      Next
   
      par_AddTokenSimple( #ljHalt )
   
      ForEach llTemp()
         If llTemp()\function >= #C2FUNCSTART
            AddElement( llTokenList() )
            llTokenList() = llTemp()
         EndIf
      Next
      
      par_AddTokenSimple( #ljEOF )
      par_AddToken( #ljINT,    #ljINT, "10",  "10" )
      par_AddToken( #ljSTRING, #ljSTRING, "NULL", "" )
      par_AddToken( #ljINT,    #ljINT, "-1", "-1" )
      par_AddToken( #ljINT,   #ljINT,   "0", "0" )
   EndProcedure
   ;- =====================================
   ;- Syntax Analyzer
   ;- =====================================  
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

      *p = AllocateStructure( stTree )

      If *p
         ; Set all fields explicitly (don't use ClearStructure with strings!)
         *p\NodeType = NodeType
         *p\TypeHint = 0
         *p\value    = value  ; This properly handles the string
         *p\left     = 0       ; Explicitly null
         *p\right    = 0       ; Explicitly null
      EndIf

      ProcedureReturn *p
   EndProcedure

   Procedure            expr( var )
      Protected.stTree  *p, *node, *r, *e, *trueExpr, *falseExpr, *branches
      Protected         op, q
      Protected         moduleId.i

      ;Debug "expr>" + RSet(Str(TOKEN()\row),4," ") + RSet(Str(TOKEN()\col),4," ") + "   " + TOKEN()\name + " --> " + gszATR( llTokenList()\TokenType )\s

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
            
         Case  #ljNOT
            NextToken()
            *p = MakeNode( #ljNOT, expr( gPreTable( #ljNOT )\Precedence ), 0 )
            
         Case #ljIDENT
            *p = Makeleaf( #ljIDENT, TOKEN()\value )
            *p\TypeHint = TOKEN()\typeHint
            NextToken()

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
      
      While gPreTable( TOKEN()\TokenExtra )\bBinary And gPreTable( TOKEN()\TokenExtra )\Precedence >= var
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
      Wend
      
      ProcedureReturn *p

   EndProcedure
   
   Procedure            paren_expr()
      Protected         *p.stTree
      
      Expect( "paren_expr", #ljLeftParent )
      *p = expr( 0 )
      Expect( "paren_expr", #ljRightParent )
      ProcedureReturn *p
   EndProcedure
   
   Procedure            expand_params( op = #ljpop, nModule = -1 )

      Protected.stTree  *p, *e, *v, *first, *last, *param
      Protected         nParams
      NewList           llParams.i()  ; FIXED: Store pointers (integers), not structures

      ; IMPORTANT: Initialize all pointers to null (they contain garbage otherwise!)
      *p = 0 : *e = 0 : *v = 0 : *first = 0 : *last = 0 : *param = 0

      Expect( "expand_params", #ljLeftParent )

      ; Build parameter list in correct order
      If TOKEN()\TokenExtra <> #ljRightParent
         Repeat
            *e = expr( 0 )

            If *e
               AddElement( llParams() )
               llParams() = *e  ; Store pointer value as integer
               nParams + 1
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
               *param.stTree = llParams()  ; Get pointer from list

               If *param\value > ""
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
         ForEach llParams()
            *param.stTree = llParams()  ; Get pointer from list

            If *p
               *p = MakeNode( #ljSEQ, *p, *param )
            Else
               *p = *param
            EndIf
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
      Protected.s       text, param
      Protected         printType.i
      Protected         varIdx.i
      Protected         moduleId.i

      ; CRITICAL: Initialize all pointers to null (they contain garbage otherwise!)
      *p = 0 : *v = 0 : *e = 0 : *r = 0 : *s = 0 : *s2 = 0

      gStack + 1
      
      If gStack > #MAX_RECURSESTACK
         NextToken()
         SetError( "Stack overflow", #C2ERR_STACK_OVERFLOW )
      EndIf
      
      Select TOKEN()\TokenType
         Case #ljIF
            NextToken()
            *e    = paren_expr()
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
            *v = Makeleaf( #ljIDENT, TOKEN()\value )
            *v\TypeHint = TOKEN()\typeHint
            NextToken()
            Expect( "Assign", #ljASSIGN )

            ; Parse right-hand side using expr() - handles all cases including nested calls
            *e = expr( 0 )
            *p = MakeNode( #ljASSIGN, *v, *e )

            Expect( "Assign", #ljSemi )
         Case #ljWHILE
            NextToken()
            *e = paren_expr()
            *s = stmt()
            *p = MakeNode( #ljWHILE, *e, *s )
            
         Case #ljLeftBrace
            Expect( "Left Bracket", #ljLeftBrace )
            
            While TOKEN()\TokenExtra <> #ljRightBrace And TOKEN()\TokenExtra <> #ljEOF
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
            NextToken() ; : NextToken()
            *e = expand_params( #ljPOP, n )
            *p = MakeNode( #ljSEQ, *v, *e )
         
         Case #ljCALL
            moduleId = Val(TOKEN()\value)
            *v = Makeleaf( #ljCall, TOKEN()\value )
            NextToken()
            *e = expand_params( #ljPush, moduleId )
            *v\paramCount = gLastExpandParamsCount  ; Store actual param count in node
            ; Statement-level calls need to pop unused return value
            *s = Makeleaf( #ljPOP, "?discard?" )
            *p = MakeNode( #ljSEQ, *e, MakeNode( #ljSEQ, *v, *s ) )
            
         Case #ljReturn
            NextToken()
            
            ; NEW CODE - generate expr, then return:
            If TOKEN()\TokenType = #ljSemi
               ; return with no value - push 0
               *e = Makeleaf( #ljINT, "0" )
               *v = MakeNode( #ljSEQ, *e, Makeleaf( #ljReturn, "0" ) )
               NextToken()
            Else
               ; return with value - evaluate expr, then return
               *e = expr(0)
               *v = MakeNode( #ljSEQ, *e, Makeleaf( #ljReturn, "0" ) )
               Expect( "Return", #ljSemi )
            EndIf

            *p = MakeNode( #ljSEQ, *p, *v )


         Default
            SetError( "Expecting beginning of a statement, found " + TOKEN()\name, #C2ERR_EXPECTED_STATEMENT )

      EndSelect
      
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
   ;- =====================================
   ;- Code Generator
   ;- =====================================
   Procedure            hole()
      gHoles + 1

      AddElement( llHoles() )
      llHoles()\location   = llObjects()
      llHoles()\mode       = 0
      llHoles()\id         = gHoles
      
      ProcedureReturn gHoles
   EndProcedure
   
   Procedure            fix( id, dst = -1 )
      
      AddElement( llHoles() )
      
      If dst = -1
         llHoles()\mode = 1
         llHoles()\id = id
         llHoles()\location = llObjects()
      Else                                   ; Used by blind JMP
         llHoles()\mode = 3
         llHoles()\location = LastElement( llObjects() )
         llHoles()\src = dst
      EndIf

   EndProcedure
    
   Procedure            EmitInt( op.i, nVar.i = -1 )
      If gEmitIntCmd = #ljpush And op = #ljStore
         ; Choose the appropriate MOV variant based on source variable type
         Protected sourceFlags.w = gVar( llObjects()\i )\flags

         If sourceFlags & #C2FLAG_STR
            llObjects()\code = #ljMOVS
            gVar( nVar )\flags = #C2FLAG_IDENT | #C2FLAG_STR
         ElseIf sourceFlags & #C2FLAG_FLOAT
            llObjects()\code = #ljMOVF
            gVar( nVar )\flags = #C2FLAG_IDENT | #C2FLAG_FLOAT
         Else
            llObjects()\code = #ljMOV
            gVar( nVar )\flags = #C2FLAG_IDENT | #C2FLAG_INT
         EndIf

         llObjects()\j = llObjects()\i
      ElseIf gEmitIntCmd = #ljfetch And op = #ljstore
         ; Choose the appropriate MOV variant based on source variable type
         Protected sourceFlags2.w = gVar( llObjects()\i )\flags

         If sourceFlags2 & #C2FLAG_STR
            llObjects()\code = #ljMOVS
         ElseIf sourceFlags2 & #C2FLAG_FLOAT
            llObjects()\code = #ljMOVF
         Else
            llObjects()\code = #ljMOV
         EndIf

         llObjects()\j = llObjects()\i
      Else
         gEmitIntLastOp = AddElement( llObjects() )
         llObjects()\code = op
      EndIf

      If nVar > -1
         llObjects()\i     = nVar
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

      j = -1

      ; Apply name mangling for local variables inside functions
      ; Synthetic variables (starting with $) and constants are never mangled
      If gCurrentFunctionName <> "" And Left(text, 1) <> "$" And syntheticType = 0
         ; Inside a function - first try to find as local variable (mangled)
         mangledName = gCurrentFunctionName + "_" + text
         searchName = mangledName

         ; Check if mangled (local) version exists
         For i = 0 To gnLastVariable - 1
            If gVar(i)\name = searchName
               ProcedureReturn i  ; Found local variable
            EndIf
         Next

         ; Not found as local - check if global exists
         ; If global exists, use it (unless we're creating a parameter)
         ; If global doesn't exist, create as local

         If gCodeGenParamIndex < 0
            ; Not processing parameters - check if global exists
            For i = 0 To gnLastVariable - 1
               If gVar(i)\name = text
                  ; Found as global - use it (for both read AND write)
                  ProcedureReturn i
               EndIf
            Next
         EndIf

         ; Global not found (or processing parameters) - create as local
         text = mangledName
      EndIf

      ; Check if variable already exists (with final name after mangling)
      For i = 0 To gnLastVariable - 1
         If gVar(i)\name = text
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

      gVar(gnLastVariable)\name  = text

      ; Check if this is a synthetic temporary variable (starts with $)
      If Left(text, 1) = "$"
         ; Synthetic variable - determine type from suffix or syntheticType parameter
         If syntheticType & #C2FLAG_FLOAT Or Right(text, 1) = "f"
            gVar(gnLastVariable)\f = 0.0
            gVar(gnLastVariable)\flags = #C2FLAG_IDENT | #C2FLAG_FLOAT
         ElseIf syntheticType & #C2FLAG_STR Or Right(text, 1) = "s"
            gVar(gnLastVariable)\ss = ""
            gVar(gnLastVariable)\flags = #C2FLAG_IDENT | #C2FLAG_STR
         Else
            gVar(gnLastVariable)\i = 0
            gVar(gnLastVariable)\flags = #C2FLAG_IDENT | #C2FLAG_INT
         EndIf
      ; Check if this is a synthetic constant (syntheticType passed in)
      ElseIf syntheticType = #ljINT
         gVar(gnLastVariable)\i = Val(text)
         gVar(gnLastVariable)\flags = #C2FLAG_CONST | #C2FLAG_INT
      ElseIf syntheticType = #ljFLOAT
         gVar(gnLastVariable)\f = ValF(text)
         gVar(gnLastVariable)\flags = #C2FLAG_CONST | #C2FLAG_FLOAT
      ElseIf syntheticType = #ljSTRING
         gVar(gnLastVariable)\ss = text
         gVar(gnLastVariable)\flags = #C2FLAG_CONST | #C2FLAG_STR
      Else
         ; Set type for constants (literals)
         If TOKEN()\TokenType = #ljINT
            gVar(gnLastVariable)\i = Val(text)
            gVar(gnLastVariable)\flags = #C2FLAG_CONST | #C2FLAG_INT
         ElseIf TOKEN()\TokenType = #ljSTRING
            gVar(gnLastVariable)\ss = text
            gVar(gnLastVariable)\flags = #C2FLAG_CONST | #C2FLAG_STR
         ElseIf TOKEN()\TokenType = #ljFLOAT
            gVar(gnLastVariable)\f = ValF(text)
            gVar(gnLastVariable)\flags = #C2FLAG_CONST | #C2FLAG_FLOAT
         ElseIf TOKEN()\TokenType = #ljIDENT
            ; NEW: Check for explicit type hint from suffix (.f or .s)
            If TOKEN()\typeHint = #ljFLOAT
               gVar(gnLastVariable)\flags = #C2FLAG_IDENT | #C2FLAG_FLOAT
            ElseIf TOKEN()\typeHint = #ljSTRING
               gVar(gnLastVariable)\flags = #C2FLAG_IDENT | #C2FLAG_STR
            Else
               ; No suffix - infer from assignment if provided
               inferredType = 0
               If *assignmentTree
                  ; Use the helper function to determine expression result type
                  inferredType = GetExprResultType(*assignmentTree)
               EndIf
   
               ; Default to INT if no inference possible
               If inferredType = 0
                  inferredType = #C2FLAG_INT
               EndIf
   
               gVar(gnLastVariable)\flags = #C2FLAG_IDENT | inferredType
            EndIf
            gVar(gnLastVariable)\i = gnLastVariable
   
         Else
            ;Debug ": " + text + " Not found"
            ;ProcedureReturn -1
         EndIf
      EndIf
      
      gnLastVariable + 1
      ProcedureReturn gnLastVariable - 1
   EndProcedure
  
   ; Helper: Determine the result type of an expression
   Procedure.w          GetExprResultType( *x.stTree, depth.i = 0 )
      Protected         n
      Protected         leftType.w, rightType.w

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
               If gVar(n)\name = searchName
                  ; Found the variable - return its type flags
                  ProcedureReturn gVar(n)\flags & #C2FLAG_TYPE
               EndIf
            Next

            ; If mangled name not found and we tried mangling, try global name
            If searchName <> *x\value
               For n = 0 To gnLastVariable - 1
                  If gVar(n)\name = *x\value
                     ; Found the global variable - return its type flags
                     ProcedureReturn gVar(n)\flags & #C2FLAG_TYPE
                  EndIf
               Next
            EndIf

            ; Variable not found yet - default to INT
            ProcedureReturn #C2FLAG_INT

         Case #ljAdd, #ljSUBTRACT, #ljMULTIPLY, #ljDIVIDE
            ; Arithmetic operations: result is string if any operand is string,
            ; else float if any operand is float, else int
            leftType = #C2FLAG_INT
            rightType = #C2FLAG_INT

            If *x\left
               leftType = GetExprResultType(*x\left, depth + 1)
            EndIf

            If *x\right
               rightType = GetExprResultType(*x\right, depth + 1)
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
      Protected         temp.s
      Protected         leftType.w
      Protected         rightType.w
      Protected         opType.w = #C2FLAG_INT
      Protected         negType.w = #C2FLAG_INT
      Protected         returnType.w
      Protected         funcId.i
      Protected         paramCount.i

      ; Reset state on top-level call
      If gCodeGenRecursionDepth = 0
         gCodeGenParamIndex = -1
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
            n = FetchVarOffset(*x\value)

            ; Check if this is a function parameter
            If gCodeGenParamIndex >= 0
               ; This is a function parameter - mark it and don't emit POP
               gVar( n )\flags = gVar( n )\flags | #C2FLAG_PARAM
               gVar( n )\paramOffset = gCodeGenParamIndex

               ; Set type flags
               If *x\typeHint = #ljFLOAT
                  gVar( n )\flags = gVar( n )\flags | #C2FLAG_FLOAT
               ElseIf *x\typeHint = #ljSTRING
                  gVar( n )\flags = gVar( n )\flags | #C2FLAG_STR
               Else
                  gVar( n )\flags = gVar( n )\flags | #C2FLAG_INT
               EndIf

               ; Decrement parameter index (parameters processed in reverse, last to first)
               gCodeGenParamIndex - 1

               ; Note: We DON'T emit POP - parameters stay on stack
            Else
               ; Regular variable assignment - emit POP as usual
               If *x\typeHint = #ljFLOAT
                  EmitInt( #ljPOPF, n )
                  gVar( n )\flags = #C2FLAG_IDENT | #C2FLAG_FLOAT
               ElseIf *x\typeHint = #ljSTRING
                  EmitInt( #ljPOPS, n )
                  gVar( n )\flags = #C2FLAG_IDENT | #C2FLAG_STR
               Else
                  EmitInt( #ljPOP, n )
                  gVar( n )\flags = #C2FLAG_IDENT | #C2FLAG_INT
               EndIf
            EndIf
         
         Case #ljIDENT
            n = FetchVarOffset(*x\value)
            ; Emit appropriate FETCH variant based on variable type
            If gVar(n)\flags & #C2FLAG_STR
               EmitInt( #ljFETCHS, n )
            ElseIf gVar(n)\flags & #C2FLAG_FLOAT
               EmitInt( #ljFETCHF, n )
            Else
               EmitInt( #ljFetch, n )
            EndIf
            gVar( n )\flags = gVar( n )\flags | #C2FLAG_IDENT
            
         Case #ljINT, #ljFLOAT, #ljSTRING
            n = FetchVarOffset( *x\value, 0, *x\NodeType )
            EmitInt( #ljPush, n )
            
         Case #ljASSIGN
            n = FetchVarOffset( *x\left\value, *x\right )

            ; Apply explicit type hint if provided
            If *x\left\TypeHint = #ljFLOAT And Not (gVar(n)\flags & #C2FLAG_FLOAT)
               gVar(n)\flags = (gVar(n)\flags & ~#C2FLAG_TYPE) | #C2FLAG_FLOAT
            ElseIf *x\left\TypeHint = #ljSTRING And Not (gVar(n)\flags & #C2FLAG_STR)
               gVar(n)\flags = (gVar(n)\flags & ~#C2FLAG_TYPE) | #C2FLAG_STR
            ElseIf Not *x\left\TypeHint
               ; No explicit hint - ensure type inference happened correctly
               rightType = GetExprResultType(*x\right)
               
               If rightType & #C2FLAG_FLOAT And Not (gVar(n)\flags & #C2FLAG_FLOAT)
                  gVar(n)\flags = (gVar(n)\flags & ~#C2FLAG_TYPE) | #C2FLAG_FLOAT
               ElseIf rightType & #C2FLAG_STR And Not (gVar(n)\flags & #C2FLAG_STR)
                  gVar(n)\flags = (gVar(n)\flags & ~#C2FLAG_TYPE) | #C2FLAG_STR
               EndIf
            EndIf

            CodeGenerator( *x\right )

            ; Emit appropriate STORE variant based on variable type
            If gVar(n)\flags & #C2FLAG_STR
               EmitInt( #ljSTORES, n )
            ElseIf gVar(n)\flags & #C2FLAG_FLOAT
               EmitInt( #ljSTOREF, n )
            Else
               EmitInt( #ljSTORE, n )
            EndIf

            ; Type propagation: If assigning a typed value to an untyped var, update the var
            If llObjects()\code <> #ljMOV And llObjects()\code <> #ljMOVS And llObjects()\code <> #ljMOVF
               ; Keep the variable's declared type (don't change it)
               ; Type checking could be added here later
            EndIf

         Case #ljReturn
            ; Note: The actual return type is determined at the SEQ level
            ; This case handles fallback for direct return processing
            EmitInt( #ljReturn )

         Case #ljIF
            CodeGenerator( *x\left )
            EmitInt( #ljJZ)
            p1 = hole()
            CodeGenerator( *x\right\left )

            If *x\right\right
               EmitInt( #ljJMP)
               p2 = hole()
            EndIf

            fix( p1 )

            If *x\right\right
               CodeGenerator( *x\right\right )
               fix( p2 )
            EndIf

         Case #ljTERNARY
            ; Ternary operator: condition ? true_expr : false_expr
            ; *x\left = condition
            ; *x\right = COLON node with true_expr in left, false_expr in right
            If *x\left And *x\right
               CodeGenerator( *x\left )          ; Evaluate condition
               EmitInt( #ljJZ )                  ; Jump if zero (false)
               p1 = hole()                       ; Remember jump location

               If *x\right\left
                  CodeGenerator( *x\right\left )    ; Evaluate true expression
               EndIf

               EmitInt( #ljJMP )                 ; Jump past false
               p2 = hole()
               fix( p1 )                         ; Fix JZ to here

               If *x\right\right
                  CodeGenerator( *x\right\right )   ; Evaluate false expression
               EndIf

               fix( p2 )                         ; Fix JMP to here
            EndIf

         Case #ljWHILE
            p1 = llObjects()
            CodeGenerator( *x\left )
            EmitInt( #ljJZ)
            p2 = Hole()
            CodeGenerator( *x\right )
            EmitInt( #ljJMP)
            fix( gHoles, p1 )
            fix( p2 )
            
         Case #ljSEQ
            ; Check if this is a return statement (SEQ with return as right node)
            If *x\right And *x\right\NodeType = #ljReturn
               ; Evaluate the expression being returned
               CodeGenerator( *x\left )

               ; Determine the type of the return expression and emit appropriate return opcode
               returnType = GetExprResultType(*x\left)

               If returnType & #C2FLAG_STR
                  EmitInt( #ljReturnS )
               ElseIf returnType & #C2FLAG_FLOAT
                  EmitInt( #ljReturnF )
               Else
                  EmitInt( #ljReturn )  ; Default to integer return
               EndIf
            Else
               ; Normal SEQ processing
               CodeGenerator( *x\left )
               CodeGenerator( *x\right )

               ; If left was ljFunction, we've finished processing the function
               If *x\left And *x\left\NodeType = #ljFunction
                  gCodeGenParamIndex = -1  ; Reset parameter tracking
                  ; Note: gCurrentFunctionName intentionally left set
                  ; It will be overwritten when next function is processed
                  ; Global code should be defined before functions to avoid scoping issues
               EndIf
            EndIf
            
         Case #ljFunction
            ForEach mapModules()
               If mapModules()\function = Val( *x\value )
                  mapModules()\Index = ListIndex( llObjects() ) + 1
                  ; Initialize parameter tracking
                  ; Parameters processed in reverse, so start from (nParams - 1) and decrement
                  gCodeGenParamIndex = mapModules()\nParams - 1
                  ; Set current function name for local variable scoping
                  gCurrentFunctionName = MapKey(mapModules())
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
            CodeGenerator( *x\right )

            ; Special handling for ADD with strings - use runtime type conversion
            If *x\NodeType = #ljAdd And (leftType & #C2FLAG_STR Or rightType & #C2FLAG_STR)
               EmitInt( #ljSTRADD )
            Else
               ; Standard arithmetic/comparison - determine result type
               opType = #C2FLAG_INT

               If leftType & #C2FLAG_FLOAT Or rightType & #C2FLAG_FLOAT
                  opType = #C2FLAG_FLOAT
               EndIf

               ; Emit correct opcode
               If opType & #C2FLAG_FLOAT And gszATR(*x\NodeType)\flttoken > 0
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
               negType = gVar(n)\flags & #C2FLAG_TYPE
            ElseIf *x\left\NodeType = #ljFLOAT
               negType = #C2FLAG_FLOAT
            EndIf

            If negType & #C2FLAG_FLOAT
               EmitInt( #ljFLOATNEG )
            Else
               EmitInt( #ljNEGATE )
            EndIf
            
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
               EmitInt( #ljCall, funcId )
               llObjects()\j = paramCount
            EndIf
            
         Case #ljHalt
            EmitInt( *x\NodeType, 0 )


         Default
            SetError("Error in CodeGenerator at node " + Str(*x\NodeType) + " " + *x\value + " ---> " + gszATR(*x\NodeType)\s, #C2ERR_CODEGEN_FAILED)

      EndSelect

      gCodeGenRecursionDepth - 1
   EndProcedure
    
   Procedure            FixJMP()
      Protected         i, pos, pair
   
      ForEach llHoles()
         If llHoles()\mode = 1
            PushListPosition( llHoles() )
               llHoles()\mode = 2
               pair  = llHoles()\id
               ChangeCurrentElement( llObjects(), llHoles()\location )
               pos   = ListIndex( llObjects() )
               i     = 0
               
               ForEach llHoles()
                  If llHoles()\mode = 0 And llHoles()\id = pair
                     llHoles()\mode = 2
                        ChangeCurrentElement( llObjects(), llHoles()\location )
                        llObjects()\i = (pos - ListIndex( llObjects() ) ) + 1
                     Break
                  EndIf
               Next
            PopListPosition( llHoles() )
         ElseIf llHoles()\mode = 3
            llHoles()\mode = 2
            ChangeCurrentElement( llObjects(), llHoles()\src )
            pos = ListIndex( llObjects() )
            ChangeCurrentElement( llObjects(), llHoles()\location )
            ; Perhaps, keep an eye on this
            llObjects()\i = (pos - ListIndex( llObjects() ) ) + 1
         EndIf
      Next
      
      ForEach llObjects()
         If llObjects()\code = #ljCall
            ForEach mapModules()
               If mapModules()\function = llObjects()\i
                  llObjects()\i = mapModules()\Index
                  ;Debug "Adjusted to " + Str( mapModules()\Index )
                  Break
               EndIf
            Next   
         EndIf
      Next
   EndProcedure
   
   Procedure            PostProcessor()
      Protected n.i
      Protected fetchVar.i
      Protected opCode.i
      Protected const1.i, const2.i, const2Idx.i
      Protected result.i
      Protected canFold.i
      Protected mulConst.i
      Protected newConstIdx.i
      Protected strIdx.i, str2Idx.i, newStrIdx.i
      Protected str1.s, str2.s, combinedStr.s

      ; Fix up opcodes based on actual variable types
      ; This handles cases where types weren't known at parse time
      ForEach llObjects()
         Select llObjects()\code
            Case #ljPush
               ; Check if this push should be typed
               n = llObjects()\i
               If n >= 0 And n < gnLastVariable
                  If gVar(n)\flags & #C2FLAG_FLOAT
                     llObjects()\code = #ljPUSHF
                  ElseIf gVar(n)\flags & #C2FLAG_STR
                     llObjects()\code = #ljPUSHS
                  EndIf
               EndIf
               
            Case #ljPRTI
               ; Check if print should use different type
               ; Look back to find what's being printed (previous FETCH/PUSH)
               If PreviousElement(llObjects())
                  If llObjects()\code = #ljFETCHF Or llObjects()\code = #ljPUSHF
                     ; Typed float fetch/push - change to PRTF
                     NextElement(llObjects())
                     llObjects()\code = #ljPRTF
                     PreviousElement(llObjects())
                  ElseIf llObjects()\code = #ljFETCHS Or llObjects()\code = #ljPUSHS
                     ; Typed string fetch/push - change to PRTS
                     NextElement(llObjects())
                     llObjects()\code = #ljPRTS
                     PreviousElement(llObjects())
                  ElseIf llObjects()\code = #ljFetch Or llObjects()\code = #ljPush
                     n = llObjects()\i
                     If n >= 0 And n < gnLastVariable
                        If gVar(n)\flags & #C2FLAG_FLOAT
                           NextElement(llObjects())  ; Move back to PRTI
                           llObjects()\code = #ljPRTF
                           PreviousElement(llObjects())  ; Stay positioned
                        ElseIf gVar(n)\flags & #C2FLAG_STR
                           NextElement(llObjects())  ; Move back to PRTI
                           llObjects()\code = #ljPRTS
                           PreviousElement(llObjects())
                        EndIf
                     EndIf
                  ElseIf llObjects()\code = #ljFLOATADD Or llObjects()\code = #ljFLOATSUB Or
                         llObjects()\code = #ljFLOATMUL Or llObjects()\code = #ljFLOATDIV Or
                         llObjects()\code = #ljFLOATNEG
                     ; Float operations always produce float results
                     NextElement(llObjects())  ; Move back to PRTI
                     llObjects()\code = #ljPRTF
                     PreviousElement(llObjects())  ; Stay positioned
                  ; Check if previous operation is a string operation
                  ElseIf llObjects()\code = #ljSTRADD
                     ; String operations always produce string results
                     NextElement(llObjects())  ; Move back to PRTI
                     llObjects()\code = #ljPRTS
                     PreviousElement(llObjects())  ; Stay positioned   
                  EndIf
                  NextElement(llObjects())  ; Return to PRTI position
               EndIf
               
            Case #ljPRTF
               ; Check if float print is actually int/string
               If PreviousElement(llObjects())
                  If llObjects()\code = #ljFetch Or llObjects()\code = #ljPush
                     n = llObjects()\i
                     If n >= 0 And n < gnLastVariable
                        If gVar(n)\flags & #C2FLAG_INT
                           NextElement(llObjects())
                           llObjects()\code = #ljPRTI
                           PreviousElement(llObjects())
                        ElseIf gVar(n)\flags & #C2FLAG_STR
                           NextElement(llObjects())
                           llObjects()\code = #ljPRTS
                           PreviousElement(llObjects())
                        EndIf
                     EndIf
                  EndIf
                  NextElement(llObjects())
               EndIf
               
            Case #ljPRTS
               ; Check if string print is actually int/float
               If PreviousElement(llObjects())
                  If llObjects()\code = #ljFetch Or llObjects()\code = #ljPush
                     n = llObjects()\i
                     If n >= 0 And n < gnLastVariable
                        If gVar(n)\flags & #C2FLAG_INT
                           NextElement(llObjects())
                           llObjects()\code = #ljPRTI
                           PreviousElement(llObjects())
                        ElseIf gVar(n)\flags & #C2FLAG_FLOAT
                           NextElement(llObjects())
                           llObjects()\code = #ljPRTF
                           PreviousElement(llObjects())
                        EndIf
                     EndIf
                  EndIf
                  NextElement(llObjects())
               EndIf
         EndSelect
      Next

      ;- ==================================================================
      ;- Enhanced Instruction Fusion Optimizations (backward compatible)
      ;- ==================================================================

      ; Pass 2: Redundant assignment elimination (x = x becomes NOP)
      ForEach llObjects()
         Select llObjects()\code
            Case #ljStore, #ljSTORES, #ljSTOREF
               ; Check if previous instruction fetches/pushes the same variable
               If PreviousElement(llObjects())
                  If (llObjects()\code = #ljFetch Or llObjects()\code = #ljFETCHS Or
                      llObjects()\code = #ljFETCHF Or llObjects()\code = #ljPush Or
                      llObjects()\code = #ljPUSHS Or llObjects()\code = #ljPUSHF)
                     ; Check if it's the same variable
                     fetchVar = llObjects()\i
                     NextElement(llObjects())  ; Back to STORE
                     If llObjects()\i = fetchVar
                        ; Redundant assignment: x = x
                        llObjects()\code = #ljNOOP
                        PreviousElement(llObjects())
                        llObjects()\code = #ljNOOP
                        NextElement(llObjects())
                     Else
                        ; Different variables, restore position
                     EndIf
                  Else
                     NextElement(llObjects())
                  EndIf
               EndIf
         EndSelect
      Next

      ; Pass 3: Dead code elimination (PUSH/FETCH followed immediately by POP)
      ForEach llObjects()
         Select llObjects()\code
            Case #ljPOP, #ljPOPS, #ljPOPF
               ; Check if previous instruction is PUSH/FETCH
               If PreviousElement(llObjects())
                  If (llObjects()\code = #ljFetch Or llObjects()\code = #ljFETCHS Or
                      llObjects()\code = #ljFETCHF Or llObjects()\code = #ljPush Or
                      llObjects()\code = #ljPUSHS Or llObjects()\code = #ljPUSHF)
                     ; Dead code: value pushed then immediately popped
                     llObjects()\code = #ljNOOP
                     NextElement(llObjects())  ; Back to POP
                     llObjects()\code = #ljNOOP
                  Else
                     NextElement(llObjects())
                  EndIf
               EndIf
         EndSelect
      Next

      ; Pass 4: Constant folding for integer arithmetic
      ForEach llObjects()
         Select llObjects()\code
            Case #ljADD, #ljSUBTRACT, #ljMULTIPLY, #ljDIVIDE, #ljMOD
               opCode = llObjects()\code
               ; Look back for two consecutive constant pushes
               If PreviousElement(llObjects())
                  If llObjects()\code = #ljPush And (gVar(llObjects()\i)\flags & #C2FLAG_CONST)
                     const2 = gVar(llObjects()\i)\i
                     const2Idx = llObjects()\i
                     If PreviousElement(llObjects())
                        If llObjects()\code = #ljPush And (gVar(llObjects()\i)\flags & #C2FLAG_CONST)
                           const1 = gVar(llObjects()\i)\i
                           canFold = #True

                           ; Compute the constant result
                           Select opCode
                              Case #ljADD
                                 result = const1 + const2
                              Case #ljSUBTRACT
                                 result = const1 - const2
                              Case #ljMULTIPLY
                                 result = const1 * const2
                              Case #ljDIVIDE
                                 If const2 <> 0
                                    result = const1 / const2
                                 Else
                                    canFold = #False  ; Don't fold division by zero
                                 EndIf
                              Case #ljMOD
                                 If const2 <> 0
                                    result = const1 % const2
                                 Else
                                    canFold = #False
                                 EndIf
                           EndSelect

                           If canFold
                              ; Create a new constant for the folded result
                              newConstIdx = gnLastVariable
                              gVar(newConstIdx)\name = "$fold" + Str(newConstIdx)
                              gVar(newConstIdx)\i = result
                              gVar(newConstIdx)\flags = #C2FLAG_CONST | #C2FLAG_INT
                              gnLastVariable + 1

                              ; Replace first PUSH with new constant, eliminate second PUSH and operation
                              llObjects()\i = newConstIdx
                              NextElement(llObjects())  ; Second PUSH
                              llObjects()\code = #ljNOOP
                              NextElement(llObjects())  ; Operation
                              llObjects()\code = #ljNOOP
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
         EndSelect
      Next

      ; Pass 5: Arithmetic identity optimizations
      ForEach llObjects()
         Select llObjects()\code
            Case #ljADD
               ; x + 0 = x, eliminate ADD and the constant 0 push
               If PreviousElement(llObjects())
                  If llObjects()\code = #ljPush And (gVar(llObjects()\i)\flags & #C2FLAG_CONST)
                     If gVar(llObjects()\i)\i = 0
                        llObjects()\code = #ljNOOP  ; Eliminate PUSH 0
                        NextElement(llObjects())     ; Back to ADD
                        llObjects()\code = #ljNOOP  ; Eliminate ADD
                     Else
                        NextElement(llObjects())
                     EndIf
                  Else
                     NextElement(llObjects())
                  EndIf
               EndIf

            Case #ljSUBTRACT
               ; x - 0 = x
               If PreviousElement(llObjects())
                  If llObjects()\code = #ljPush And (gVar(llObjects()\i)\flags & #C2FLAG_CONST)
                     If gVar(llObjects()\i)\i = 0
                        llObjects()\code = #ljNOOP
                        NextElement(llObjects())
                        llObjects()\code = #ljNOOP
                     Else
                        NextElement(llObjects())
                     EndIf
                  Else
                     NextElement(llObjects())
                  EndIf
               EndIf

            Case #ljMULTIPLY
               ; x * 1 = x, x * 0 = 0
               If PreviousElement(llObjects())
                  If llObjects()\code = #ljPush And (gVar(llObjects()\i)\flags & #C2FLAG_CONST)
                     mulConst = gVar(llObjects()\i)\i
                     If mulConst = 1
                        ; x * 1 = x, eliminate multiply and the constant
                        llObjects()\code = #ljNOOP
                        NextElement(llObjects())
                        llObjects()\code = #ljNOOP
                     ElseIf mulConst = 0
                        ; x * 0 = 0, keep the PUSH 0 but eliminate value below and multiply
                        ; This requires looking back 2 instructions
                        If PreviousElement(llObjects())
                           llObjects()\code = #ljNOOP  ; Eliminate the x value
                           NextElement(llObjects())     ; Back to PUSH 0
                           NextElement(llObjects())     ; To MULTIPLY
                           llObjects()\code = #ljNOOP  ; Eliminate MULTIPLY
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

            Case #ljDIVIDE
               ; x / 1 = x
               If PreviousElement(llObjects())
                  If llObjects()\code = #ljPush And (gVar(llObjects()\i)\flags & #C2FLAG_CONST)
                     If gVar(llObjects()\i)\i = 1
                        llObjects()\code = #ljNOOP
                        NextElement(llObjects())
                        llObjects()\code = #ljNOOP
                     Else
                        NextElement(llObjects())
                     EndIf
                  Else
                     NextElement(llObjects())
                  EndIf
               EndIf
         EndSelect
      Next

      ;- Pass 7: String identity optimization (str + "" → str)
      ForEach llObjects()
         If llObjects()\code = #ljSTRADD
            ; Check if previous instruction is PUSHS with empty string
            If PreviousElement(llObjects())
               If llObjects()\code = #ljPUSHS Or llObjects()\code = #ljPush
                  strIdx = llObjects()\i
                  If (gVar(strIdx)\flags & #C2FLAG_STR) And gVar(strIdx)\ss = ""
                     ; Empty string found - eliminate it and STRADD
                     llObjects()\code = #ljNOOP
                     NextElement(llObjects())  ; Back to STRADD
                     llObjects()\code = #ljNOOP
                  Else
                     NextElement(llObjects())
                  EndIf
               Else
                  NextElement(llObjects())
               EndIf
            EndIf
         EndIf
      Next

      ;- Pass 8: String constant folding ("a" + "b" → "ab")
      ForEach llObjects()
         If llObjects()\code = #ljSTRADD
            ; Look back for two consecutive string constant pushes
            If PreviousElement(llObjects())
               If (llObjects()\code = #ljPUSHS Or llObjects()\code = #ljPush) And (gVar(llObjects()\i)\flags & #C2FLAG_CONST)
                  str2Idx = llObjects()\i
                  str2 = gVar(str2Idx)\ss
                  If PreviousElement(llObjects())
                     If (llObjects()\code = #ljPUSHS Or llObjects()\code = #ljPush) And (gVar(llObjects()\i)\flags & #C2FLAG_CONST)
                        str1 = gVar(llObjects()\i)\ss
                        combinedStr = str1 + str2

                        ; Create new constant for combined string
                        newStrIdx = gnLastVariable
                        gVar(newStrIdx)\name = "$strfold" + Str(newStrIdx)
                        gVar(newStrIdx)\ss = combinedStr
                        gVar(newStrIdx)\flags = #C2FLAG_CONST | #C2FLAG_STR
                        gnLastVariable + 1

                        ; Replace first PUSH with combined string, eliminate second PUSH and STRADD
                        llObjects()\i = newStrIdx
                        NextElement(llObjects())  ; Second PUSH
                        llObjects()\code = #ljNOOP
                        NextElement(llObjects())  ; STRADD
                        llObjects()\code = #ljNOOP
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
         EndIf
      Next

      ;- Pass 9: Remove all NOOP instructions from the code stream
      ForEach llObjects()
         If llObjects()\code = #ljNOOP
            DeleteElement(llObjects())
         EndIf
      Next

   EndProcedure

   Procedure            ListCode( gadget = 0 )
      Protected         i
      Protected         flag
      Protected.s       temp, line, FullCode

      Debug ";--"
      Debug ";-- Variables & Constants --"
      Debug ";--"

      For i = 0 To gnLastVariable - 1
         If gVar(i)\flags & #C2FLAG_INT
            temp = "Integer"
         ElseIf gVar(i)\flags & #C2FLAG_FLOAT
            temp = "Float"
         ElseIf gVar(i)\flags & #C2FLAG_STR
            temp = "String"
         ElseIf gVar(i)\flags & #C2FLAG_IDENT
            temp = "Variable"
         EndIf

         If gVar(i)\flags & #C2FLAG_CONST
            temp + " constant"
         EndIf

         Debug RSet(Str(i),6, " ") + "   " + LSet(gVar(i)\name,20," ") + "  (" + temp + ")"
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
      SetClipboardText( FullCode )
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
      Preprocessor()

      If Scanner()
         Debug "Scanner failed with error: " + gszlastError
         ProcedureReturn 1
      EndIf

      ;par_DebugParser()
      ReorderTokens()
      FirstElement( TOKEN() )
      total = ListSize( TOKEN() ) - 1

      Repeat
         gStack = 0
         *p = MakeNode( #ljSEQ, *p, stmt() )

         If gLastError
            Debug gszlastError
            Debug "AST Error"
            gExit = -1
            Break
         EndIf

      Until ListIndex( TOKEN() ) >= total Or gExit

      If gExit >= 0
         ;- DisplayNode( *p )
         CodeGenerator( *p )

         FixJMP()

         ; Run optimizer passes (check pragma optimizecode - default ON)
         If FindMapElement(mapPragmas(), "optimizecode")
            ; Pragma found - check value
            If LCase(mapPragmas()) <> "off" And mapPragmas() <> "0"
               PostProcessor()
            EndIf
         Else
            ; No pragma - default is ON
            PostProcessor()
         EndIf

         vm_ListToArray( llObjects, arCode )

         ; List assembly if requested (check pragma listasm - default OFF)
         If FindMapElement(mapPragmas(), "listasm")
            If LCase(mapPragmas()) = "on" Or mapPragmas() = "1"
               ListCode()
            EndIf
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


   ;filename = ".\Examples\02 Simple while.lj"
   ;filename = ".\Examples\04 If Else.lj"
   ;filename = ".\Examples\06 Mandelbrot.lj"
   ;filename = ".\Examples\07 Floats and macros.lj"
   ;filename = ".\Examples\09 Functions2.lj"
   ;filename = ".\Examples\12 Floats and macros.lj"
   ;filename = ".\Examples\12 test functions.lj"
   ;filename = ".\Examples\0 test.lj"   
   ;filename = ".\Examples\12 test functions.lj"
   
   filename = ".\Examples\13 test functions more.lj"
   filename = ".\Examples\02 Simple While.lj"
   ;filename = ".\Examples\03 Complex while.lj"
   
   ;filename = ".\Examples\0 test.lj"   
   filename = OpenFileRequester( "Please choose source", ".\Examples\", "LJ Files|*.lj", 0 )

   If filename > ""
      If C2Lang::LoadLJ( filename )
         Debug "Error: " + C2Lang::Error( @err )
      Else
         C2Lang::Compile()
         ;C2Lang::ListCode()
         C2VM::RunVM()  ; Auto-run after compilation
         
         ;If C2Lang::gExit
         ;   Debug "Failed...."
         ;   Debug "gxit="+str*gExit)
         ;   
         ;   C2Lang::ListCode()
         ;Else
         ;   Debug "Executing..."
         ;   C2VM::RunVM()
         ;EndIf
      EndIf
   EndIf

CompilerEndIf


; IDE Options = PureBasic 6.21 (Windows - x64)
; CursorPosition = 16
; Folding = -----f-----
; Markers = 1071
; Optimizer
; EnableThread
; EnableXP
; CPU = 1
; EnableCompileCount = 347
; EnableBuildCount = 0
; EnableExeConstant
; IncludeVersionInfo