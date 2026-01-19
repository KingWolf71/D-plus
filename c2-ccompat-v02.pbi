; ============================================================================
; C Compatibility Layer for LJ2 - V1.037.0
; ============================================================================
; Transforms C-style syntax to LJ2 equivalents
; Enabled via: #pragma ccompat on
;
; Features:
;   - Declaration transforms: int x = 5 → x.i = 5
;   - Function aliases: strlen() → len()
;   - Function transforms: strcpy(a,b) → a = b
;   - Include handling: #include → commented out
;   - Unsupported construct warnings
; ============================================================================

; Global flag for C compatibility mode
Global gCCompatEnabled.b = #False
Global gCCompatStrict.b = #False

; Warning collection
Global NewList llCCompatWarnings.s()

; Regex handles (created once, reused)
Global gRegex_IntDecl.i = 0
Global gRegex_IntDeclNoInit.i = 0
Global gRegex_FloatDecl.i = 0
Global gRegex_FloatDeclNoInit.i = 0
Global gRegex_DoubleDecl.i = 0
Global gRegex_CharDecl.i = 0
Global gRegex_Include.i = 0
Global gRegex_IntFunc.i = 0
Global gRegex_VoidFunc.i = 0
Global gRegex_FloatFunc.i = 0
Global gRegex_MainFunc.i = 0
Global gRegex_Strlen.i = 0
Global gRegex_Rand.i = 0
Global gRegex_Puts.i = 0
Global gRegex_Strcpy.i = 0
Global gRegex_Strcat.i = 0
Global gRegex_Atoi.i = 0
Global gRegex_Atof.i = 0

; ============================================================================
; Initialize regex patterns - call once at startup
; ============================================================================
Procedure CCompat_Init()
   ; Declaration patterns - word boundary using (?<![a-zA-Z]) for start
   ; Pattern: int identifier = or int identifier;
   ; Note: PureBasic regex may not support \b, use explicit patterns

   ; Note: Regex-based transforms have been replaced with simpler string-based transforms
   ; The regex handles are kept for future enhancements (strcpy, strcat, atoi, atof)

   ; int x = value (at line start or after non-word char)
   gRegex_IntDecl = CreateRegularExpression(#PB_Any, "(^|[^a-zA-Z_])int\s+(\w+)\s*=")

   ; int x; (no init)
   gRegex_IntDeclNoInit = CreateRegularExpression(#PB_Any, "(^|[^a-zA-Z_])int\s+(\w+)\s*;")

   ; float x = value
   gRegex_FloatDecl = CreateRegularExpression(#PB_Any, "(^|[^a-zA-Z_])float\s+(\w+)\s*=")

   ; float x; (no init)
   gRegex_FloatDeclNoInit = CreateRegularExpression(#PB_Any, "(^|[^a-zA-Z_])float\s+(\w+)\s*;")

   ; double x = value (maps to float)
   gRegex_DoubleDecl = CreateRegularExpression(#PB_Any, "(^|[^a-zA-Z_])double\s+(\w+)\s*=")

   ; char x = value
   gRegex_CharDecl = CreateRegularExpression(#PB_Any, "(^|[^a-zA-Z_])char\s+(\w+)\s*=")

   ; #include <...> or #include "..."
   gRegex_Include = CreateRegularExpression(#PB_Any, ~"#include\\s*[<\"].*?[>\"]")

   ; Function definitions
   ; int funcname(...) {
   gRegex_IntFunc = CreateRegularExpression(#PB_Any, "(^|[^a-zA-Z_])int\s+(\w+)\s*\(([^)]*)\)\s*\{")

   ; void funcname(...) {
   gRegex_VoidFunc = CreateRegularExpression(#PB_Any, "(^|[^a-zA-Z_])void\s+(\w+)\s*\(([^)]*)\)\s*\{")

   ; float funcname(...) {
   gRegex_FloatFunc = CreateRegularExpression(#PB_Any, "(^|[^a-zA-Z_])float\s+(\w+)\s*\(([^)]*)\)\s*\{")

   ; int main(...) { - special case
   gRegex_MainFunc = CreateRegularExpression(#PB_Any, "(^|[^a-zA-Z_])int\s+main\s*\([^)]*\)\s*\{")

   ; Function call aliases
   gRegex_Strlen = CreateRegularExpression(#PB_Any, "(^|[^a-zA-Z_])strlen\s*\(")
   gRegex_Rand = CreateRegularExpression(#PB_Any, "(^|[^a-zA-Z_])rand\s*\(")
   gRegex_Puts = CreateRegularExpression(#PB_Any, "(^|[^a-zA-Z_])puts\s*\(")

   ; Function transforms - these need more careful handling
   ; strcpy(dest, src) - capture both args
   gRegex_Strcpy = CreateRegularExpression(#PB_Any, "(^|[^a-zA-Z_])strcpy\s*\(\s*(\w+)\s*,\s*([^)]+)\s*\)")

   ; strcat(dest, src)
   gRegex_Strcat = CreateRegularExpression(#PB_Any, "(^|[^a-zA-Z_])strcat\s*\(\s*(\w+)\s*,\s*([^)]+)\s*\)")

   ; atoi(str)
   gRegex_Atoi = CreateRegularExpression(#PB_Any, "(^|[^a-zA-Z_])atoi\s*\(\s*([^)]+)\s*\)")

   ; atof(str)
   gRegex_Atof = CreateRegularExpression(#PB_Any, "(^|[^a-zA-Z_])atof\s*\(\s*([^)]+)\s*\)")
EndProcedure

; ============================================================================
; Add a warning message
; ============================================================================
Procedure CCompat_AddWarning(lineNum.i, message.s)
   AddElement(llCCompatWarnings())
   llCCompatWarnings() = "[C-Compat] Line " + Str(lineNum) + ": " + message
EndProcedure

; ============================================================================
; Clear warnings list
; ============================================================================
Procedure CCompat_ClearWarnings()
   ClearList(llCCompatWarnings())
EndProcedure

; ============================================================================
; Get collected warnings
; ============================================================================
Procedure.s CCompat_GetWarnings()
   Protected result.s = ""
   ForEach llCCompatWarnings()
      result + llCCompatWarnings() + #LF$
   Next
   ProcedureReturn result
EndProcedure

; ============================================================================
; Check if position is inside a string literal
; ============================================================================
Procedure.b CCompat_IsInsideString(line.s, pos.i)
   Protected i.i, inString.b = #False, ch.s

   For i = 1 To pos - 1
      ch = Mid(line, i, 1)
      If ch = Chr(34) And (i = 1 Or Mid(line, i - 1, 1) <> "\")
         inString = ~inString
      EndIf
   Next

   ProcedureReturn inString
EndProcedure

; ============================================================================
; Transform C declarations to LJ2 style
; Uses simple string matching instead of regex for reliability
; ============================================================================
Procedure.s CCompat_TransformDeclarations(line.s)
   Protected result.s = line
   Protected trimmed.s = Trim(line)
   Protected varName.s, restOfLine.s
   Protected spacePos.i, eqPos.i, semiPos.i

   ; Strip qualifiers first: const, static, unsigned, signed, volatile, extern, register
   trimmed = ReplaceString(trimmed, "const ", "", #PB_String_NoCase)
   trimmed = ReplaceString(trimmed, "static ", "", #PB_String_NoCase)
   trimmed = ReplaceString(trimmed, "unsigned ", "", #PB_String_NoCase)
   trimmed = ReplaceString(trimmed, "signed ", "", #PB_String_NoCase)
   trimmed = ReplaceString(trimmed, "volatile ", "", #PB_String_NoCase)
   trimmed = ReplaceString(trimmed, "extern ", "", #PB_String_NoCase)
   trimmed = ReplaceString(trimmed, "register ", "", #PB_String_NoCase)
   trimmed = Trim(trimmed)

   ; Check for "int " at start
   If Left(LCase(trimmed), 4) = "int "
      restOfLine = Trim(Mid(trimmed, 5))
      ; Find variable name (up to = or ;)
      eqPos = FindString(restOfLine, "=")
      semiPos = FindString(restOfLine, ";")

      If eqPos > 0
         ; int x = value → x.i = value
         varName = Trim(Left(restOfLine, eqPos - 1))
         result = varName + ".i = " + Trim(Mid(restOfLine, eqPos + 1))
      ElseIf semiPos > 0
         ; int x; → x.i = 0;
         varName = Trim(Left(restOfLine, semiPos - 1))
         result = varName + ".i = 0;"
      EndIf
   ; Check for "float " at start
   ElseIf Left(LCase(trimmed), 6) = "float "
      restOfLine = Trim(Mid(trimmed, 7))
      eqPos = FindString(restOfLine, "=")
      semiPos = FindString(restOfLine, ";")

      If eqPos > 0
         varName = Trim(Left(restOfLine, eqPos - 1))
         result = varName + ".f = " + Trim(Mid(restOfLine, eqPos + 1))
      ElseIf semiPos > 0
         varName = Trim(Left(restOfLine, semiPos - 1))
         result = varName + ".f = 0.0;"
      EndIf
   ; Check for "double " at start (maps to float)
   ElseIf Left(LCase(trimmed), 7) = "double "
      restOfLine = Trim(Mid(trimmed, 8))
      eqPos = FindString(restOfLine, "=")
      semiPos = FindString(restOfLine, ";")

      If eqPos > 0
         varName = Trim(Left(restOfLine, eqPos - 1))
         result = varName + ".f = " + Trim(Mid(restOfLine, eqPos + 1))
      ElseIf semiPos > 0
         varName = Trim(Left(restOfLine, semiPos - 1))
         result = varName + ".f = 0.0;"
      EndIf
   ; Check for "char " at start (maps to int)
   ElseIf Left(LCase(trimmed), 5) = "char "
      restOfLine = Trim(Mid(trimmed, 6))
      eqPos = FindString(restOfLine, "=")
      semiPos = FindString(restOfLine, ";")

      If eqPos > 0
         varName = Trim(Left(restOfLine, eqPos - 1))
         result = varName + ".i = " + Trim(Mid(restOfLine, eqPos + 1))
      ElseIf semiPos > 0
         varName = Trim(Left(restOfLine, semiPos - 1))
         result = varName + ".i = 0;"
      EndIf
   ; Check for "long " at start (maps to int)
   ElseIf Left(LCase(trimmed), 5) = "long "
      restOfLine = Trim(Mid(trimmed, 6))
      eqPos = FindString(restOfLine, "=")
      semiPos = FindString(restOfLine, ";")

      If eqPos > 0
         varName = Trim(Left(restOfLine, eqPos - 1))
         result = varName + ".i = " + Trim(Mid(restOfLine, eqPos + 1))
      ElseIf semiPos > 0
         varName = Trim(Left(restOfLine, semiPos - 1))
         result = varName + ".i = 0;"
      EndIf
   ; Check for "short " at start (maps to int)
   ElseIf Left(LCase(trimmed), 6) = "short "
      restOfLine = Trim(Mid(trimmed, 7))
      eqPos = FindString(restOfLine, "=")
      semiPos = FindString(restOfLine, ";")

      If eqPos > 0
         varName = Trim(Left(restOfLine, eqPos - 1))
         result = varName + ".i = " + Trim(Mid(restOfLine, eqPos + 1))
      ElseIf semiPos > 0
         varName = Trim(Left(restOfLine, semiPos - 1))
         result = varName + ".i = 0;"
      EndIf
   ; Check for "char *" or "char*" at start (maps to string)
   ElseIf Left(LCase(trimmed), 6) = "char *" Or Left(LCase(trimmed), 5) = "char*"
      If Left(LCase(trimmed), 6) = "char *"
         restOfLine = Trim(Mid(trimmed, 7))
      Else
         restOfLine = Trim(Mid(trimmed, 6))
      EndIf
      eqPos = FindString(restOfLine, "=")
      semiPos = FindString(restOfLine, ";")

      If eqPos > 0
         varName = Trim(Left(restOfLine, eqPos - 1))
         result = varName + ".s = " + Trim(Mid(restOfLine, eqPos + 1))
      ElseIf semiPos > 0
         varName = Trim(Left(restOfLine, semiPos - 1))
         result = varName + ~".s = \"\";"
      EndIf
   ; Check for "string " at start (native string type)
   ElseIf Left(LCase(trimmed), 7) = "string "
      restOfLine = Trim(Mid(trimmed, 8))
      eqPos = FindString(restOfLine, "=")
      semiPos = FindString(restOfLine, ";")

      If eqPos > 0
         varName = Trim(Left(restOfLine, eqPos - 1))
         result = varName + ".s = " + Trim(Mid(restOfLine, eqPos + 1))
      ElseIf semiPos > 0
         varName = Trim(Left(restOfLine, semiPos - 1))
         result = varName + ~".s = \"\";"
      EndIf
   EndIf

   ProcedureReturn result
EndProcedure

; ============================================================================
; Transform C function definitions to LJ2 style
; Uses simple string matching for reliability
; ============================================================================
Procedure.s CCompat_TransformFunctionDefs(line.s)
   Protected result.s = line
   Protected trimmed.s = Trim(line)
   Protected funcName.s, params.s, restOfLine.s
   Protected parenPos.i, closeParenPos.i, bracePos.i
   Protected returnType.s = ""

   ; Look for function definition pattern: type funcname(params) {
   ; First check for return types
   If Left(LCase(trimmed), 4) = "int "
      returnType = ""  ; int returns don't need suffix in LJ2
      restOfLine = Trim(Mid(trimmed, 5))
   ElseIf Left(LCase(trimmed), 5) = "void "
      returnType = ""  ; void functions are just func
      restOfLine = Trim(Mid(trimmed, 6))
   ElseIf Left(LCase(trimmed), 6) = "float "
      returnType = ".f"
      restOfLine = Trim(Mid(trimmed, 7))
   ElseIf Left(LCase(trimmed), 7) = "double "
      returnType = ".f"
      restOfLine = Trim(Mid(trimmed, 8))
   Else
      ProcedureReturn result ; Not a C function definition
   EndIf

   ; Check for function definition pattern: funcname(params) {
   parenPos = FindString(restOfLine, "(")
   If parenPos = 0
      ProcedureReturn result  ; Not a function definition
   EndIf

   ; Extract function name
   funcName = Trim(Left(restOfLine, parenPos - 1))
   If funcName = ""
      ProcedureReturn result
   EndIf

   ; Check for main function
   If LCase(funcName) = "main"
      result = "func main() {"
      ProcedureReturn result
   EndIf

   ; Find closing paren and opening brace
   closeParenPos = FindString(restOfLine, ")", parenPos)
   bracePos = FindString(restOfLine, "{", closeParenPos)

   If closeParenPos = 0 Or bracePos = 0
      ProcedureReturn result  ; Not a complete function definition
   EndIf

   ; Extract parameters
   params = Mid(restOfLine, parenPos + 1, closeParenPos - parenPos - 1)

   ; Clean up parameter types
   params = ReplaceString(params, "int ", "")
   params = ReplaceString(params, "float ", "")
   params = ReplaceString(params, "double ", "")
   params = ReplaceString(params, "char ", "")
   params = ReplaceString(params, "void ", "")
   params = ReplaceString(params, "long ", "")
   params = ReplaceString(params, "short ", "")
   params = Trim(params)

   ; Build LJ2 function definition
   result = "func " + funcName + returnType + "(" + params + ") {"

   ProcedureReturn result
EndProcedure

; ============================================================================
; Transform C function calls to LJ2 equivalents
; Uses simple string replacement for reliability
; ============================================================================
Procedure.s CCompat_TransformFunctionCalls(line.s)
   Protected result.s = line

   ; Simple function call aliases using ReplaceString
   ; strlen( → len(
   result = ReplaceString(result, "strlen(", "len(")

   ; rand( → random(
   result = ReplaceString(result, "rand(", "random(")

   ; puts( → print(
   result = ReplaceString(result, "puts(", "print(")

   ; Note: strcpy, strcat, atoi, atof require more complex parsing
   ; These are left for a future enhancement or handled by regex if needed

   ProcedureReturn result
EndProcedure

; ============================================================================
; Transform C includes to comments
; ============================================================================
Procedure.s CCompat_TransformIncludes(line.s)
   Protected result.s = line

   If gRegex_Include And MatchRegularExpression(gRegex_Include, result)
      ; Comment out the include
      result = "// " + Trim(result) + "  // (C include - not needed in LJ2)"
   EndIf

   ProcedureReturn result
EndProcedure

; ============================================================================
; Check for unsupported constructs and add warnings
; ============================================================================
Procedure CCompat_CheckUnsupported(line.s, lineNum.i)
   Protected lowerLine.s = LCase(line)

   ; Skip if in comment
   If Left(Trim(line), 2) = "//" Or Left(Trim(line), 2) = "/*"
      ProcedureReturn
   EndIf

   ; Check for sizeof
   If FindString(lowerLine, "sizeof")
      CCompat_AddWarning(lineNum, "sizeof() not supported - use explicit size constants")
   EndIf

   ; Check for typedef
   If FindString(lowerLine, "typedef ")
      CCompat_AddWarning(lineNum, "typedef not supported - use struct instead")
   EndIf

   ; Check for union
   If FindString(lowerLine, "union ")
      CCompat_AddWarning(lineNum, "union not supported - use struct with largest member")
   EndIf

   ; Check for goto
   If FindString(lowerLine, "goto ")
      CCompat_AddWarning(lineNum, "goto not supported - restructure with loops/functions")
   EndIf

   ; Check for malloc/free
   If FindString(lowerLine, "malloc(") Or FindString(lowerLine, "malloc ")
      CCompat_AddWarning(lineNum, "malloc() not needed - variables auto-allocated")
   EndIf

   If FindString(lowerLine, "free(")
      CCompat_AddWarning(lineNum, "free() not needed - variables auto-freed")
   EndIf

   ; Check for scanf
   If FindString(lowerLine, "scanf(")
      CCompat_AddWarning(lineNum, "scanf() not supported - no console input")
   EndIf

   ; Check for file I/O
   If FindString(lowerLine, "fopen(") Or FindString(lowerLine, "fclose(") Or
      FindString(lowerLine, "fread(") Or FindString(lowerLine, "fwrite(") Or
      FindString(lowerLine, "fprintf(")
      CCompat_AddWarning(lineNum, "File I/O not yet implemented")
   EndIf

   ; Check for sprintf
   If FindString(lowerLine, "sprintf(")
      CCompat_AddWarning(lineNum, "sprintf() not implemented - use string concatenation with str()")
   EndIf

   ; Check for conditional compilation
   If FindString(lowerLine, "#ifdef") Or FindString(lowerLine, "#ifndef") Or
      FindString(lowerLine, "#endif") Or FindString(lowerLine, "#if ") Or
      FindString(lowerLine, "#else") Or FindString(lowerLine, "#elif")
      CCompat_AddWarning(lineNum, "Conditional compilation not supported")
   EndIf
EndProcedure

; ============================================================================
; Main transformation entry point - processes entire source
; ============================================================================
Procedure.s CCompat_Transform(source.s)
   Protected result.s = ""
   Protected line.s, transformedLine.s
   Protected lineNum.i = 0
   Protected i.i, lineCount.i

   If Not gCCompatEnabled
      ProcedureReturn source
   EndIf

   ; Clear previous warnings
   CCompat_ClearWarnings()

   ; Split source into lines
   lineCount = CountString(source, #LF$) + 1

   For i = 1 To lineCount
      lineNum = i
      line = StringField(source, i, #LF$)

      ; Remove CR if present (Windows line endings)
      If Right(line, 1) = #CR$
         line = Left(line, Len(line) - 1)
      EndIf

      transformedLine = line

      ; Skip empty lines and pure comments
      If Trim(line) <> "" And Left(Trim(line), 2) <> "//"

         ; Phase 1: Handle includes
         transformedLine = CCompat_TransformIncludes(transformedLine)

         ; Phase 2: Transform declarations (if not already transformed by include)
         If Left(Trim(transformedLine), 2) <> "//"
            transformedLine = CCompat_TransformDeclarations(transformedLine)
         EndIf

         ; Phase 3: Transform function definitions
         If Left(Trim(transformedLine), 2) <> "//"
            transformedLine = CCompat_TransformFunctionDefs(transformedLine)
         EndIf

         ; Phase 4: Transform function calls
         If Left(Trim(transformedLine), 2) <> "//"
            transformedLine = CCompat_TransformFunctionCalls(transformedLine)
         EndIf

         ; Phase 5: Check for unsupported constructs
         CCompat_CheckUnsupported(line, lineNum)
      EndIf

      ; Append transformed line with CRLF to match preprocessor convention
      If i > 1
         result + #CRLF$
      EndIf
      result + transformedLine
   Next

   ; Add trailing CRLF to match input format
   result + #CRLF$

   ProcedureReturn result
EndProcedure

; ============================================================================
; Enable/disable C compatibility mode
; ============================================================================
Procedure CCompat_Enable(enable.b = #True)
   gCCompatEnabled = enable
EndProcedure

Procedure CCompat_SetStrict(strict.b = #True)
   gCCompatStrict = strict
EndProcedure

Procedure.b CCompat_IsEnabled()
   ProcedureReturn gCCompatEnabled
EndProcedure

; IDE Options = PureBasic 6.10 LTS (Windows - x64)
; Folding = --
