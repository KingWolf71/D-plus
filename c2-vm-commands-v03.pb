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
; VM Module
;- Library functions
Macro                   vm_DebugFunctionName()
   ;Debug #PB_Compiler_Procedure
EndMacro

; Macro for built-in functions: get parameter count
Macro                   vm_GetParamCount()
   _AR()\j
EndMacro

; Macro for built-in functions: pop N parameters from stack
Macro                   vm_PopParams(n)
   sp - n
EndMacro

; Macro for built-in functions: push integer result
Macro                   vm_PushInt(value)
   gVar(sp)\i = value
   gVar(sp)\flags = #C2FLAG_INT
   sp + 1
   pc + 1
EndMacro

;XIncludeFile            "C2-inc-v05.PBI"


Procedure.s             Capitalize( sz.s, option.i = 0 )
   Protected            i, j, flag
   Protected.s          new, char
   
   If option = 0
      ProcedureReturn UCase( sz )
   ElseIf option = 1
      ProcedureReturn LCase( sz )
   Else
      j = Len( sz )
      flag = 1
      
      For i = 1 To j
         char = Mid( sz, i, 1 )
         If flag
            new + UCase( char )
            flag = 0
         ElseIf char = " " Or char = #TAB$
            new + char
            flag = 1
         Else
            new + LCase( char )
         EndIf
      Next

      ProcedureReturn new
   EndIf
EndProcedure

Procedure.s             String( sz.s, size )
   Protected.s          new

   While size
      size - 1
      new + sz
   Wend

   ProcedureReturn new
EndProcedure
;- Jump Table Functions

Procedure               C2FetchPush()
   Protected varSlot.i
   Protected callerSp.i

   vm_DebugFunctionName()
   varSlot = _AR()\i

   ; Check if this is a stack-local parameter AND we're in a function
   If (gVar(varSlot)\flags & #C2FLAG_PARAM) And gFunctionDepth > 0
      ; Read from stack at callerSp + paramOffset
      callerSp = llStack()\sp
      gVar( sp ) = gVar( callerSp + gVar(varSlot)\paramOffset )
   Else
      ; Regular global variable
      gVar( sp ) = gVar( varSlot )
   EndIf

   sp + 1
   pc + 1
EndProcedure

Procedure               C2FETCHS()
   Protected varSlot.i
   Protected callerSp.i

   vm_DebugFunctionName()
   varSlot = _AR()\i

   ; Check if this is a stack-local parameter AND we're in a function
   If (gVar(varSlot)\flags & #C2FLAG_PARAM) And gFunctionDepth > 0
      ; Read from stack at callerSp + paramOffset
      callerSp = llStack()\sp
      gVar( sp ) = gVar( callerSp + gVar(varSlot)\paramOffset )
   Else
      ; Regular global variable
      gVar( sp ) = gVar( varSlot )
   EndIf

   ; Flag already set at compile time by PostProcessor

   sp + 1
   pc + 1
EndProcedure

Procedure               C2FETCHF()
   Protected varSlot.i
   Protected callerSp.i

   vm_DebugFunctionName()
   varSlot = _AR()\i

   ;Debug "FETCHF BEFORE: sp=" + Str(sp) + " fetching gVar(" + Str(varSlot) + ")[" + gVar(varSlot)\name + "] f=" + StrD(gVar(varSlot)\f, 6)

   ; Check if this is a stack-local parameter AND we're in a function
   If (gVar(varSlot)\flags & #C2FLAG_PARAM) And gFunctionDepth > 0
      ; Read from stack at callerSp + paramOffset
      callerSp = llStack()\sp
      gVar( sp ) = gVar( callerSp + gVar(varSlot)\paramOffset )
   Else
      ; Regular global variable
      gVar( sp ) = gVar( varSlot )
   EndIf

   ; Flag already set at compile time by PostProcessor

   ;Debug "FETCHF AFTER: pushed to gVar(" + Str(sp) + "), now incrementing sp"

   sp + 1
   pc + 1
EndProcedure

Procedure               C2POP()
   vm_DebugFunctionName()

   ; OLD CODE - was reading from wrong position AND copying entire structure:
   ; sp - 1
   ; gVar( _AR()\i ) = gVar( sp )  // This overwrites the variable name!

   ; NEW CODE - copy only the data fields, not the name:
   sp - 1
   gVar( _AR()\i )\i = gVar( sp )\i
   ;gVar( _AR()\i )\f = gVar( sp )\f
   ;gVar( _AR()\i )\ss = gVar( sp )\ss
   ;gVar( _AR()\i )\p = gVar( sp )\p
   ; Don't copy: name, flags (those are set by the compiler)

   pc + 1
EndProcedure

Procedure               C2POPS()
   vm_DebugFunctionName()
   ; Pop string value from stack
   sp - 1
   gVar( _AR()\i )\ss = gVar( sp )\ss
   pc + 1
EndProcedure

Procedure               C2POPF()
   vm_DebugFunctionName()
   ; Pop float value from stack
   sp - 1
   gVar( _AR()\i )\f = gVar( sp )\f
   pc + 1
EndProcedure

Procedure               C2PUSHS()
   vm_DebugFunctionName()
   ; Push string value onto stack
   gVar( sp ) = gVar( _AR()\i )
   sp + 1
   pc + 1
EndProcedure

Procedure               C2PUSHF()
   vm_DebugFunctionName()
   ; Push float value onto stack
   gVar( sp ) = gVar( _AR()\i )
   sp + 1
   pc + 1
EndProcedure

Procedure               C2Store()
   vm_DebugFunctionName()
   sp - 1

   ; OLD CODE - copied entire structure, overwriting name:
   ; gVar( _AR()\i ) = gVar( sp )

   ; NEW CODE - copy only data fields:
   gVar( _AR()\i )\i = gVar( sp )\i
   ; Flag already set at compile time by PostProcessor
   ;gVar( _AR()\i )\f = gVar( sp )\f
   ;gVar( _AR()\i )\ss = gVar( sp )\ss
   ;gVar( _AR()\i )\p = gVar( sp )\p

   pc + 1
EndProcedure

Procedure               C2STORES()
   vm_DebugFunctionName()
   sp - 1

   ; Copy data fields for string store
   gVar( _AR()\i )\ss = gVar( sp )\ss
   ; Flag already set at compile time by PostProcessor

   pc + 1
EndProcedure

Procedure               C2STOREF()
   vm_DebugFunctionName()
   sp - 1

   ; Copy data fields for float store
   gVar( _AR()\i )\f = gVar( sp )\f
   ; Flag already set at compile time by PostProcessor

   ;Debug "STOREF: Storing gVar(" + Str(sp) + ")\f=" + StrD(gVar(sp)\f, 6) + " to gVar(" + Str(_AR()\i) + ")[" + gVar(_AR()\i)\name + "]"

   pc + 1
EndProcedure

Procedure               C2MOV()
   vm_DebugFunctionName()

   ; OLD CODE - copied entire structure, overwriting name:
   ; gVar( _AR()\i ) = gVar( _AR()\j )

   ; NEW CODE - copy only data fields:
   gVar( _AR()\i )\i = gVar( _AR()\j )\i
   ;gVar( _AR()\i )\f = gVar( _AR()\j )\f
   ;gVar( _AR()\i )\ss = gVar( _AR()\j )\ss
   ;gVar( _AR()\i )\p = gVar( _AR()\j )\p
   ; Flag already set at compile time by PostProcessor

   pc + 1
EndProcedure

Procedure               C2MOVS()
   vm_DebugFunctionName()

   ; Copy data fields for string move
   gVar( _AR()\i )\ss = gVar( _AR()\j )\ss
   ; Flag already set at compile time by PostProcessor

   pc + 1
EndProcedure

Procedure               C2MOVF()
   vm_DebugFunctionName()

   ; Copy data fields for float move
   gVar( _AR()\i )\f = gVar( _AR()\j )\f
   ; Flag already set at compile time by PostProcessor

   pc + 1
EndProcedure

Procedure               C2JMP()
   vm_DebugFunctionName()
   pc + _AR()\i
EndProcedure

Procedure               C2JZ()
   vm_DebugFunctionName()
   sp - 1
   If Not gVar( sp )\i
      pc + _AR()\i
   Else
      pc + 1
   EndIf
EndProcedure

Procedure               C2ADD()
   vm_DebugFunctionName()
   vm_BitOperation( + )
EndProcedure

Procedure               C2ADDSTR()
   vm_DebugFunctionName()
   Protected leftStr.s, rightStr.s

   sp - 1

   ; Convert left operand (sp-1) to string based on its type
   If gVar(sp - 1)\flags & #C2FLAG_STR
      leftStr = gVar(sp - 1)\ss
   ElseIf gVar(sp - 1)\flags & #C2FLAG_FLOAT
      leftStr = StrD(gVar(sp - 1)\f, gDecs)
   Else
      leftStr = Str(gVar(sp - 1)\i)
   EndIf

   ; Convert right operand (sp) to string based on its type
   If gVar(sp)\flags & #C2FLAG_STR
      rightStr = gVar(sp)\ss
   ElseIf gVar(sp)\flags & #C2FLAG_FLOAT
      rightStr = StrD(gVar(sp)\f, gDecs)
   Else
      rightStr = Str(gVar(sp)\i)
   EndIf

   ; Concatenate and store result
   gVar(sp - 1)\ss = leftStr + rightStr
   ; Flag already set at compile time by PostProcessor

   pc + 1
EndProcedure

Procedure               C2FTOS()
   vm_DebugFunctionName()
   ; Convert float to string at stack top
   gVar(sp - 1)\ss = StrD(gVar(sp - 1)\f, gDecs)
   pc + 1
EndProcedure

Procedure               C2ITOS()
   vm_DebugFunctionName()
   ; Convert integer to string at stack top
   gVar(sp - 1)\ss = Str(gVar(sp - 1)\i)
   pc + 1
EndProcedure

Procedure               C2SUBTRACT()
   vm_DebugFunctionName()
   vm_BitOperation( - )
EndProcedure

Procedure               C2GREATER()
   vm_DebugFunctionName()
   vm_Comparators( > )
EndProcedure

Procedure               C2LESS()
   vm_DebugFunctionName()
   vm_Comparators( < )
EndProcedure

Procedure               C2LESSEQUAL()
   vm_DebugFunctionName()
   vm_Comparators( <= )
EndProcedure

Procedure               C2GREATEREQUAL()
   vm_DebugFunctionName()
   vm_Comparators( >= )
EndProcedure

Procedure               C2NOTEQUAL()
   vm_DebugFunctionName()
   vm_Comparators( <> )
EndProcedure

Procedure               C2EQUAL()
   vm_DebugFunctionName()
   vm_Comparators( = )
EndProcedure

Procedure               C2MULTIPLY()
   vm_DebugFunctionName()
   vm_BitOperation( * )
EndProcedure

Procedure               C2AND()
   vm_DebugFunctionName()
   vm_BitOperation( & )
EndProcedure

Procedure               C2OR()
   vm_DebugFunctionName()
   vm_BitOperation( | )
EndProcedure

Procedure               C2XOR()
   vm_DebugFunctionName()
   vm_BitOperation( ! )
EndProcedure

Procedure               C2NOT()
   vm_DebugFunctionName()
   gVar( sp - 1 )\i = Bool(Not gVar( sp - 1 )\i )
   pc + 1
EndProcedure

Procedure               C2NEGATE()
   vm_DebugFunctionName()
   gVar( sp - 1 )\i = -gVar( sp -1 )\i
   pc + 1
EndProcedure

Procedure               C2DIVIDE()
   vm_DebugFunctionName()
   vm_BitOperation( / )
EndProcedure

Procedure               C2MOD()
   vm_DebugFunctionName()
   vm_BitOperation( % )
EndProcedure

Procedure               C2PRTS()
   vm_DebugFunctionName()
   sp - 1
   CompilerIf #PB_Compiler_ExecutableFormat = #PB_Compiler_Console
      gBatchOutput + gVar(sp)\ss
      Print(gVar(sp)\ss)  ; Echo to console
   CompilerElse
      cline = cline + gVar(sp)\ss
      SetGadgetItemText( #edConsole, cy, cline )
   CompilerEndIf
   pc + 1
EndProcedure

Procedure               C2PRTI()
   vm_DebugFunctionName()
   sp - 1
   CompilerIf #PB_Compiler_ExecutableFormat = #PB_Compiler_Console
      gBatchOutput + Str( gVar( sp )\i )
      Print(Str( gVar( sp )\i ))  ; Echo to console
   CompilerElse
      cline = cline + Str( gVar( sp )\i )
      SetGadgetItemText( #edConsole, cy, cline )
   CompilerEndIf
   pc + 1
EndProcedure

Procedure               C2PRTF()
   vm_DebugFunctionName()
   sp - 1
   CompilerIf #PB_Compiler_ExecutableFormat = #PB_Compiler_Console
      gBatchOutput + StrD( gVar( sp )\f, gDecs )
      Print(StrD( gVar( sp )\f, gDecs ))  ; Echo to console
   CompilerElse
      cline = cline + StrD( gVar( sp )\f, gDecs )
      SetGadgetItemText( #edConsole, cy, cline)
   CompilerEndIf
   pc + 1
EndProcedure

Procedure               C2PRTC()
   vm_DebugFunctionName()
   sp - 1

   CompilerIf #PB_Compiler_ExecutableFormat = #PB_Compiler_Console
      gBatchOutput + Chr( gVar( sp )\i )
      If gVar( sp )\i = 10 : PrintN( "" ) : EndIf
   CompilerElse
      If gVar( sp )\i = 10
         cy + 1
         cline = ""
         AddGadgetItem( #edConsole, -1, "" )
      Else
         cline = cline + Chr( gVar( sp )\i )
         SetGadgetItemText( #edConsole, cy, cline )
      EndIf
   CompilerEndIf
   pc + 1
EndProcedure

Procedure               C2FLOATNEGATE()
   vm_DebugFunctionName()
   gVar(sp-1)\f = -gVar(sp-1)\f
   pc + 1
EndProcedure

Procedure               C2FLOATDIVIDE()
   vm_DebugFunctionName()
   vm_FloatOperation( / )
EndProcedure

Procedure               C2FLOATMUL()
   vm_DebugFunctionName()
   vm_FloatOperation( * )
EndProcedure

Procedure               C2FLOATADD()
   vm_FloatOperation( + )
EndProcedure

Procedure               C2FLOATSUB()
   vm_DebugFunctionName()
   vm_FloatOperation( - )
EndProcedure

Procedure               C2FLOATGREATER()
   vm_DebugFunctionName()
   vm_FloatComparators( > )
EndProcedure

Procedure               C2FLOATLESS()
   vm_DebugFunctionName()
   vm_FloatComparators( < )
EndProcedure

Procedure               C2FLOATLESSEQUAL()
   vm_DebugFunctionName()
   vm_FloatComparators( <= )
EndProcedure

Procedure               C2FLOATGREATEREQUAL()
   vm_DebugFunctionName()
   vm_FloatComparators( >= )
EndProcedure

Procedure               C2FLOATNOTEQUAL()
   vm_DebugFunctionName()
   vm_FloatComparators( <> )
EndProcedure

Procedure               C2FLOATEQUAL()
   vm_DebugFunctionName()
   vm_FloatComparators( = )
EndProcedure

Procedure               C2CALL()
   vm_DebugFunctionName()
   Protected nParams.i

   nParams = _AR()\j  ; Get parameter count from instruction

   ; User-defined function - create stack frame and jump to bytecode address
   AddElement( llStack() )
   llStack()\pc = pc + 1
   llStack()\sp = sp - nParams  ; Save sp BEFORE params were pushed (FIX: prevents stack leak)
   pc = _AR()\i
   gFunctionDepth + 1  ; Increment function depth counter

   ;Debug "CALL pc=" + Str(pc) + " with " + Str(nParams) + " params, sp=" + Str(sp) + " saving callerSp=" + Str(llStack()\sp)
   ;Debug "s=" + gVar( sp - 3 )\ss + " d=" + Str( gVar( sp - 3 )\i ) + " f=" + StrD( gVar( sp - 3 )\f, 3 )
   ;Debug "s=" + gVar( sp - 2 )\ss + " d=" + Str( gVar( sp - 2 )\i ) + " f=" + StrD( gVar( sp - 2 )\f, 3 )
   ;Debug "s=" + gVar( sp - 1 )\ss + " d=" + Str( gVar( sp - 1 )\i ) + " f=" + StrD( gVar( sp - 1 )\f, 3 )
EndProcedure

Procedure               C2Return()
   vm_DebugFunctionName()

   ; OLD CODE - didn't preserve return value:
   ; pc = llStack()\pc
   ; sp = llStack()\sp
   ; DeleteElement( llStack() )

   ; NEW CODE - preserve return value on stack:
   ; The return value (if any) is at sp-1
   ; We need to copy it to the caller's stack position before restoring sp
   Protected returnValue.stVT
   Protected callerSp.i

   ; Initialize to default integer 0 (prevents uninitialized returns)
   returnValue\i = 0
   returnValue\flags = #C2FLAG_INT

   ; Save caller's stack pointer
   callerSp = llStack()\sp

   ; Save return value from top of stack (sp-1) if there's anything on function's stack
   If sp > callerSp
      returnValue = gVar(sp - 1)
   EndIf

   ; Restore caller's program counter and stack pointer
   pc = llStack()\pc
   sp = callerSp
   DeleteElement( llStack() )
   gFunctionDepth - 1  ; Decrement function depth counter

   ; Push return value onto caller's stack
   gVar(sp) = returnValue
   sp + 1
EndProcedure

Procedure               C2ReturnF()
   vm_DebugFunctionName()

   ; Float return - preserves float return value from stack
   Protected returnValue.stVT
   Protected callerSp.i

   ; Initialize to default float 0.0
   returnValue\f = 0.0
   returnValue\flags = #C2FLAG_FLOAT

   ; Save caller's stack pointer
   callerSp = llStack()\sp

   ; Save float return value from top of stack (sp-1) if there's anything on function's stack
   If sp > callerSp
      returnValue = gVar(sp - 1)
   EndIf

   ; Restore caller's program counter and stack pointer
   pc = llStack()\pc
   sp = callerSp
   DeleteElement( llStack() )
   gFunctionDepth - 1  ; Decrement function depth counter

   ; Push float return value onto caller's stack
   gVar(sp) = returnValue
   sp + 1
EndProcedure

Procedure               C2ReturnS()
   vm_DebugFunctionName()

   ; String return - preserves string return value from stack
   Protected returnValue.stVT
   Protected callerSp.i

   ; Initialize to default empty string
   returnValue\ss = ""
   returnValue\flags = #C2FLAG_STR

   ; Save caller's stack pointer
   callerSp = llStack()\sp

   ; Save string return value from top of stack (sp-1) if there's anything on function's stack
   If sp > callerSp
      returnValue = gVar(sp - 1)
   EndIf

   ; Restore caller's program counter and stack pointer
   pc = llStack()\pc
   sp = callerSp
   DeleteElement( llStack() )
   gFunctionDepth - 1  ; Decrement function depth counter

   ; Push string return value onto caller's stack
   gVar(sp) = returnValue
   sp + 1
EndProcedure

;-
;- Built-in Functions (VM Handlers)
;-

; random() - Returns random integer
; random()         -> 0 to maxint
; random(max)      -> 0 to max-1
; random(min, max) -> min to max-1
Procedure C2BUILTIN_RANDOM()
   vm_DebugFunctionName()
   Protected paramCount.i = vm_GetParamCount()
   Protected minVal.i, maxVal.i, result.i

   Select paramCount
      Case 0
         result = Random(2147483647)
      Case 1
         maxVal = gVar(sp - 1)\i
         If maxVal <= 0 : maxVal = 1 : EndIf
         result = Random(maxVal - 1)
         vm_PopParams(1)
      Case 2
         maxVal = gVar(sp - 1)\i
         minVal = gVar(sp - 2)\i
         If maxVal <= minVal : maxVal = minVal + 1 : EndIf
         result = Random(maxVal - minVal - 1) + minVal
         vm_PopParams(2)
      Default
         result = 0
         vm_PopParams(paramCount)
   EndSelect

   vm_PushInt(result)
EndProcedure

; abs(x) - Absolute value
Procedure C2BUILTIN_ABS()
   vm_DebugFunctionName()
   Protected paramCount.i = vm_GetParamCount()
   Protected result.i

   If paramCount > 0
      result = Abs(gVar(sp - 1)\i)
      vm_PopParams(paramCount)
   Else
      result = 0
   EndIf

   vm_PushInt(result)
EndProcedure

; min(a, b) - Minimum of two values
Procedure C2BUILTIN_MIN()
   vm_DebugFunctionName()
   Protected paramCount.i = vm_GetParamCount()
   Protected a.i, b.i, result.i

   If paramCount >= 2
      b = gVar(sp - 1)\i
      a = gVar(sp - 2)\i
      If a < b
         result = a
      Else
         result = b
      EndIf
      vm_PopParams(paramCount)
   Else
      result = 0
      vm_PopParams(paramCount)
   EndIf

   vm_PushInt(result)
EndProcedure

; max(a, b) - Maximum of two values
Procedure C2BUILTIN_MAX()
   vm_DebugFunctionName()
   Protected paramCount.i = vm_GetParamCount()
   Protected a.i, b.i, result.i

   If paramCount >= 2
      b = gVar(sp - 1)\i
      a = gVar(sp - 2)\i
      If a > b
         result = a
      Else
         result = b
      EndIf
      vm_PopParams(paramCount)
   Else
      result = 0
      vm_PopParams(paramCount)
   EndIf

   vm_PushInt(result)
EndProcedure

Procedure               C2HALT()
   vm_DebugFunctionName()
   ; Do nothing - the VM loop checks for HALT and exits
   pc + 1
EndProcedure

;- End VM functions
; IDE Options = PureBasic 6.21 (Windows - x64)
; CursorPosition = 463
; FirstLine = 459
; Folding = ------------
; EnableAsm
; EnableThread
; EnableXP
; CPU = 1
; EnablePurifier
; EnableCompileCount = 0
; EnableBuildCount = 0
; EnableExeConstant