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
; Built-in Functions Module
; Version: 01
;
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
;- Built-in Functions (VM Handlers)

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

; assertEqual(expected, actual) - Assert integers are equal
Procedure C2BUILTIN_ASSERT_EQUAL()
   vm_DebugFunctionName()
   Protected paramCount.i = vm_GetParamCount()
   Protected expected.i, actual.i, result.i
   Protected message.s

   If paramCount >= 2
      actual = gVar(sp - 1)\i
      expected = gVar(sp - 2)\i

      If expected = actual
         message = "[PASS] assertEqual: " + Str(expected) + " == " + Str(actual)
         result = 1
      Else
         message = "[FAIL] assertEqual: expected " + Str(expected) + " but got " + Str(actual)
         result = 0
      EndIf

      vm_PopParams(paramCount)
   Else
      message = "[FAIL] assertEqual: requires 2 parameters"
      result = 0
      vm_PopParams(paramCount)
   EndIf

   vm_AssertPrint( message )
   pc + 1  ; V1.020.053: Assertions don't return values (statement-level calls only)
EndProcedure

; assertFloatEqual(expected, actual, tolerance) - Assert floats are equal within tolerance
; If tolerance is omitted, uses #pragma floattolerance value (default: 0.00001)
Procedure C2BUILTIN_ASSERT_FLOAT()
   vm_DebugFunctionName()
   Protected paramCount.i = vm_GetParamCount()
   Protected expected.d, actual.d, tolerance.d, result.i
   Protected message.s

   If paramCount >= 2
      If paramCount >= 3
         tolerance = gVar(sp - 1)\f
         actual = gVar(sp - 2)\f
         expected = gVar(sp - 3)\f
      Else
         tolerance = gFloatTolerance
         actual = gVar(sp - 1)\f
         expected = gVar(sp - 2)\f
      EndIf

      If Abs(expected - actual) <= tolerance
         message = "[PASS] assertFloatEqual: " + StrD(expected, gDecs) + " ~= " + StrD(actual, gDecs) + " (tol=" + StrD(tolerance, gDecs) + ")"
         result = 1
      Else
         message = "[FAIL] assertFloatEqual: expected " + StrD(expected, gDecs) + " but got " + StrD(actual, gDecs) + " (diff=" + StrD(Abs(expected - actual), gDecs) + ", tol=" + StrD(tolerance, gDecs) + ")"
         result = 0
      EndIf

      vm_PopParams(paramCount)
   Else
      message = "[FAIL] assertFloatEqual: requires 2-3 parameters"
      result = 0
      vm_PopParams(paramCount)
   EndIf

   vm_AssertPrint( message )
   pc + 1  ; V1.020.053: Assertions don't return values (statement-level calls only)
EndProcedure

; assertStringEqual(expected, actual) - Assert strings are equal
Procedure C2BUILTIN_ASSERT_STRING()
   vm_DebugFunctionName()
   Protected paramCount.i = vm_GetParamCount()
   Protected expected.s, actual.s, result.i
   Protected message.s

   If paramCount >= 2
      actual = gVar(sp - 1)\ss
      expected = gVar(sp - 2)\ss

      If expected = actual
         message = ~"[PASS] assertStringEqual: \"" + expected + ~"\" == \"" + actual + ~"\""
         result = 1
      Else
         message = ~"[FAIL] assertStringEqual: expected \"" + expected + ~"\" but got \"" + actual + ~"\""
         result = 0
      EndIf

      vm_PopParams(paramCount)
   Else
      message = "[FAIL] assertStringEqual: requires 2 parameters"
      result = 0
      vm_PopParams(paramCount)
   EndIf

   vm_AssertPrint( message )
   pc + 1  ; V1.020.053: Assertions don't return values (statement-level calls only)
EndProcedure

; sqrt(x) - Square root (returns float)
Procedure C2BUILTIN_SQRT()
   vm_DebugFunctionName()
   Protected paramCount.i = vm_GetParamCount()
   Protected result.d

   If paramCount > 0
      result = Sqr(gVar(sp - 1)\f)
      vm_PopParams(paramCount)
   Else
      result = 0.0
   EndIf

   vm_PushFloat(result)
EndProcedure

; pow(base, exp) - Power function (returns float)
Procedure C2BUILTIN_POW()
   vm_DebugFunctionName()
   Protected paramCount.i = vm_GetParamCount()
   Protected base.d, exp.d, result.d

   If paramCount >= 2
      exp = gVar(sp - 1)\f
      base = gVar(sp - 2)\f
      result = Pow(base, exp)
      vm_PopParams(paramCount)
   Else
      result = 0.0
      vm_PopParams(paramCount)
   EndIf

   vm_PushFloat(result)
EndProcedure

; len(s) - String length (returns integer)
Procedure C2BUILTIN_LEN()
   vm_DebugFunctionName()
   Protected paramCount.i = vm_GetParamCount()
   Protected result.i

   If paramCount > 0
      result = Len(gVar(sp - 1)\ss)
      vm_PopParams(paramCount)
   Else
      result = 0
   EndIf

   vm_PushInt(result)
EndProcedure

;- End Built-in Functions

; IDE Options = PureBasic 6.21 (Windows - x64)
; CursorPosition = 22
; FirstLine = 4
; Folding = --
; EnableAsm
; EnableThread
; EnableXP
; CPU = 1
; EnablePurifier
; EnableCompileCount = 0
; EnableBuildCount = 0
; EnableExeConstant