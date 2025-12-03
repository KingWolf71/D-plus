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
; Scanner - Lexical Analysis
;- Macros for token handling and scanning


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
      gPos + 1

      If gNextChar = #LF$
         gLineNumber + 1
         gCol = 1
      Else
         gCol + 1
      EndIf
   EndMacro

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
   ; PureBasic procedure to detect if a string represents an Integer, Float, or neither (String)
   Procedure            DetectType( Input.s )
      Protected.s       s = Trim(Input)
      Protected.s       c
      Protected.b       isInteger = #True
      Protected.i       i
      Protected.b       hasDigit = #False  ; V1.022.40: Track if we have at least one digit

      If s = ""
         ; Empty string considered as String type
         ProcedureReturn #ljSTRING
      EndIf

      ; Check integer: optional leading + or -, followed by digits only
      ; V1.022.40: Must have at least one digit (+ or - alone is NOT an integer)

      For i = 1 To Len(s)
         c = Mid( s, i, 1 )
         If i = 1 And ( c = "+" Or c = "-" )
            Continue ; sign is allowed at first position
         ElseIf c >= "0" And c <= "9"
            hasDigit = #True  ; V1.022.40: Found at least one digit
            Continue ; digit is allowed
         Else
            isInteger = #False
            Break
         EndIf
      Next i

      ; V1.022.40: Require at least one digit for integer (+ or - alone is a string)
      If isInteger = #True And hasDigit = #True
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

   Procedure            par_CheckPreviousTokenForPointer()
      ; When we encounter an identifier, check if previous token was * or &
      ; to determine if it's a pointer dereference or address-of operation
      Protected prevTokenType.i
      Protected prevTokenExtra.i
      Protected tokenBeforeOp.i

      ; Save current position and go to previous token
      If PreviousElement(llTokenList())
         prevTokenType = llTokenList()\TokenType
         prevTokenExtra = llTokenList()\TokenExtra

         ; Check if previous token was * (MULTIPLY) - change to PTRFETCH only if in unary context
         If prevTokenType = #ljOP And prevTokenExtra = #ljMULTIPLY
            ; Check token BEFORE the * to determine if * is unary or binary
            ; If token before * is ), ], identifier, or literal, then * is binary (multiplication)
            ; Otherwise, * is unary (pointer dereference)
            If PreviousElement(llTokenList())
               tokenBeforeOp = llTokenList()\TokenExtra
               NextElement(llTokenList())  ; Return to * token

               ; Only convert to PTRFETCH if * is in unary position
               ; Binary context: value/identifier/closing-bracket followed by *
               If tokenBeforeOp = #ljRightParent Or tokenBeforeOp = #ljRightBracket Or
                  tokenBeforeOp = #ljIDENT Or tokenBeforeOp = #ljINT Or
                  tokenBeforeOp = #ljFLOAT Or tokenBeforeOp = #ljSTRING
                  ; This is binary multiplication - do NOT convert to PTRFETCH
               Else
                  ; This is unary dereference - convert to PTRFETCH
                  llTokenList()\TokenExtra = #ljPTRFETCH
                  llTokenList()\name = gszATR(#ljPTRFETCH)\s
               EndIf
            Else
               ; No token before *, so it's unary (start of expression)
               llTokenList()\TokenExtra = #ljPTRFETCH
               llTokenList()\name = gszATR(#ljPTRFETCH)\s
            EndIf
         EndIf
         ; Note: & (GETADDR) is already correctly set in scanner

         ; Return to current token
         NextElement(llTokenList())
      EndIf
   EndProcedure
   ; Reads character by character creating tokens used by the syntax checker and code generator
   Procedure            Scanner()
      Protected         err, first, i
      Protected.i       dots, bFloat, e
      Protected.i       braces
      Protected.s       text, temp

      gpos           = 1
      gCurrFunction  = 1

      While gPos <= gMemSize
         par_NextCharacter()

         Select gNextChar
            Case gszEOF
               par_AddTokenSimple( #ljEOF )
               Break

            Case " ", #CR$, #LF$, #TAB$, ""
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
            Case "["
               par_AddTokenSimple( #ljLeftBracket )
            Case "]"
               par_AddTokenSimple( #ljRightBracket )
            Case "+"
               ; Check for ++ or +=
               par_NextCharacter()
               If gNextChar = "+"
                  par_AddToken( #ljOP, #ljINC, "", "" )
               ElseIf gNextChar = "="
                  par_AddToken( #ljOP, #ljADD_ASSIGN, "", "" )
               Else
                  par_AddToken( #ljOP, #ljADD, "", "" )
                  gPos - 1
               EndIf
            Case "-"
               ; Check for -- or -=
               par_NextCharacter()
               If gNextChar = "-"
                  par_AddToken( #ljOP, #ljDEC, "", "" )
               ElseIf gNextChar = "="
                  par_AddToken( #ljOP, #ljSUB_ASSIGN, "", "" )
               Else
                  par_AddToken( #ljOP, #ljSUBTRACT, "", "" )
                  gPos - 1
               EndIf
            Case "*"
               ; Check for *= or dereference (context-sensitive)
               par_NextCharacter()
               If gNextChar = "="
                  par_AddToken( #ljOP, #ljMUL_ASSIGN, "", "" )
               Else
                  ; Scanner emits MULTIPLY - parser will determine if it's dereference based on context
                  par_AddToken( #ljOP, #ljMULTIPLY, "", "" )
                  gPos - 1
               EndIf
            Case "%"
               ; Check for %=
               par_NextCharacter()
               If gNextChar = "="
                  par_AddToken( #ljOP, #ljMOD_ASSIGN, "", "" )
               Else
                  par_AddToken( #ljOP, #ljMOD, "", "" )
                  gPos - 1
               EndIf
            Case ";"
               par_AddTokenSimple( #ljSemi )
            Case ","
               par_AddTokenSimple( #ljComma )
            Case "\"
               par_AddTokenSimple( #ljBackslash )  ; V1.20.21: Pointer field accessor
            Case "?"
               par_AddTokenSimple( #ljQUESTION )
            Case ":"
               par_AddTokenSimple( #ljCOLON )
            Case "/"
               ; Check for /=
               par_NextCharacter()
               If gNextChar = "="
                  par_AddToken( #ljOP, #ljDIV_ASSIGN, "", "" )
               Else
                  par_AddToken( #ljOP, #ljDIVIDE, "", "" )
                  gPos - 1
               EndIf
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
               ; V1.021.10: Both & and && emit #ljAND
               ; Single & in unary position = address-of (handled by AST)
               ; Single & in binary position = bitwise AND
               ; && = same as & (logical AND)
               par_NextCharacter()
               If gNextChar = "&"
                  par_AddToken( #ljOP, #ljAND, "", "" )
               Else
                  ; Single & - context determines meaning (AST handles unary vs binary)
                  par_AddToken( #ljOP, #ljAND, "", "" )
                  gPos - 1
               EndIf
            Case "|"
               ; Check for || (logical OR) or single | (bitwise OR) - V1.021.4
               par_NextCharacter()
               If gNextChar = "|"
                  par_AddToken( #ljOP, #ljOr, "", "" )
               Else
                  ; Single | is bitwise OR (same opcode)
                  par_AddToken( #ljOP, #ljOr, "", "" )
                  gPos - 1
               EndIf
            Case "^"
               ; Bitwise XOR - V1.021.4
               par_AddToken( #ljOP, #ljXOR, "", "" )

            Case #INV$
               par_NextCharacter()

               ; Check for empty string
               If gNextChar = #INV$
                  par_AddToken( #ljSTRING, #ljSTRING, "", "" )
               Else
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

                  ; Check for type suffix (.i, .f, .d, or .s)
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
                  ElseIf Right(temp, 2) = ".i"
                     typeHint = #ljINT
                     varName = Left(text, Len(text) - 2)
                     temp = LCase(varName)
                  EndIf

                  ; Check keywords FIRST (before functions) - keywords have priority
                  ForEach llSymbols()
                     i + 1

                     If LCase(llSymbols()\name) = temp
                        par_AddToken( llSymbols()\TokenType, llSymbols()\TokenType, "", varName )
                        TOKEN()\typeHint = typeHint
                        i = -1
                        Break
                     EndIf
                  Next

                  If i > 0
                     ; Not a keyword - check if it's a function
                     If FindMapElement( mapModules(), "_" + temp )
                        If mapModules()\row = gLineNumber And TOKEN()\TokenType = #ljFunction
                           gCurrFunction     = mapModules()\function
                           TOKEN()\function  = gCurrFunction
                           TOKEN()\value     = Str( gCurrFunction )
                        Else
                           par_AddToken( #ljCall, #ljCall, "", Str( mapModules()\function ) )
                           par_CheckPreviousTokenForPointer()
                        EndIf
                     Else
                        ; NOTE: Don't check built-ins here - allows variables to shadow built-in names
                        ; Built-ins will be checked in parser when identifier is followed by '('

                        ; Not a keyword or function - check if it's a number or identifier
                        If first
                           par_AddToken( #ljINT, #ljINT, "", text )
                        Else
                           par_AddToken( #ljIDENT, #ljIDENT, "", varName )
                           TOKEN()\typeHint = typeHint
                           par_CheckPreviousTokenForPointer()
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

; IDE Options = PureBasic 6.21 (Windows - x64)
; CursorPosition = 14
; Folding = --
; EnableAsm
; EnableThread
; EnableXP
; CPU = 1
; EnablePurifier
; EnableCompileCount = 0
; EnableBuildCount = 0
; EnableExeConstant