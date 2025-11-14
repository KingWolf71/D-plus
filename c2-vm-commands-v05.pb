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

#DEBUG = 0

Macro                   vm_DebugFunctionName()
   ;Debug #PB_Compiler_Procedure
EndMacro

; Macro for built-in functions: get parameter count
Macro                   vm_GetParamCount()
   _AR()\j
EndMacro

; Macro for built-in functions: pop N parameters from stack
Macro                   vm_PopParams(n)
   sp - (n)
EndMacro

; Macro for built-in functions: push integer result
Macro                   vm_PushInt(value)
   gVar( sp )\i = value
   sp + 1
   CompilerIf #DEBUG
      ;If sp % 100 = 0
      ;   Debug "Stack pointer at: " + Str(sp) + " / " + Str(#C2MAXCONSTANTS)
      ;EndIf
   CompilerEndIf
   pc + 1
EndMacro

Macro                   vm_AssertPrint( tmsg )
   CompilerIf #PB_Compiler_ExecutableFormat = #PB_Compiler_Console
      gBatchOutput = gBatchOutput + tmsg + #LF$
      PrintN(tmsg)
   CompilerElse
      AddGadgetItem(#edConsole, cy, tmsg)
      cy + 1
      cline = ""
   CompilerEndIf
EndMacro
Macro                   vm_ScrollToBottom( pbGadgetID )
   CompilerSelect #PB_Compiler_OS
		CompilerCase #PB_OS_Windows
			Select GadgetType(pbGadgetID)
				Case #PB_GadgetType_ListView
					SendMessage_(GadgetID(pbGadgetID), #LB_SETTOPINDEX, CountGadgetItems(pbGadgetID) - 1, #Null)
				Case #PB_GadgetType_ListIcon
					SendMessage_(GadgetID(pbGadgetID), #LVM_ENSUREVISIBLE, CountGadgetItems(pbGadgetID) - 1, #False)
				Case #PB_GadgetType_Editor
					SendMessage_(GadgetID(pbGadgetID), #EM_SCROLLCARET, #SB_BOTTOM, 0)
			EndSelect
		CompilerCase #PB_OS_Linux
			Protected *Adjustment.GtkAdjustment
			*Adjustment = gtk_scrolled_window_get_vadjustment_(gtk_widget_get_parent_(GadgetID(pbGadgetID)))
			*Adjustment\value = *Adjustment\upper
			gtk_adjustment_value_changed_(*Adjustment)
	CompilerEndSelect 
EndMacro


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

   vm_DebugFunctionName()
   varSlot = _AR()\i

   ; Generic FETCH - only copy integer value (compiler should use FETCHS/FETCHF for typed variables)
   If gVarMeta(varSlot)\paramOffset >= 0 And gFunctionDepth > 0
      ; Read from Local array using paramOffset
      gVar( sp )\i = gStack(gStackDepth)\LocalInt(gVarMeta(varSlot)\paramOffset)
   Else
      ; Regular global variable
      gVar( sp )\i = gVar( varSlot )\i
   EndIf

   sp + 1
   pc + 1
EndProcedure

Procedure               C2FETCHS()
   Protected varSlot.i

   vm_DebugFunctionName()
   varSlot = _AR()\i

   ; Check if this is a parameter/local variable AND we're in a function
   If gVarMeta(varSlot)\paramOffset >= 0 And gFunctionDepth > 0
      ; Read from Local array using paramOffset
      gVar( sp )\ss = gStack(gStackDepth)\LocalString(gVarMeta(varSlot)\paramOffset)
   Else
      ; Regular global variable
      gVar( sp )\ss = gVar( varSlot )\ss
   EndIf

   sp + 1
   pc + 1
EndProcedure

Procedure               C2FETCHF()
   Protected varSlot.i

   vm_DebugFunctionName()
   varSlot = _AR()\i

   ; Check if this is a parameter/local variable AND we're in a function
   If gVarMeta(varSlot)\paramOffset >= 0 And gFunctionDepth > 0
      ; Read from Local array using paramOffset
      gVar( sp )\f = gStack(gStackDepth)\LocalFloat(gVarMeta(varSlot)\paramOffset)
   Else
      ; Regular global variable
      gVar( sp )\f = gVar( varSlot )\f
   EndIf

   sp + 1
   pc + 1
EndProcedure

Procedure               C2POP()
   Protected varSlot.i

   vm_DebugFunctionName()
   sp - 1
   varSlot = _AR()\i

   ; Check if this is a parameter/local variable AND we're in a function
   If gVarMeta(varSlot)\paramOffset >= 0 And gFunctionDepth > 0
      ; Write to Local array using paramOffset
      gStack(gStackDepth)\LocalInt(gVarMeta(varSlot)\paramOffset) = gVar( sp )\i
   Else
      ; Regular global variable - write to variable slot
      gVar( varSlot )\i = gVar( sp )\i
   EndIf

   pc + 1
EndProcedure

Procedure               C2POPS()
   Protected varSlot.i

   vm_DebugFunctionName()
   sp - 1
   varSlot = _AR()\i

   ; Check if this is a parameter/local variable AND we're in a function
   If gVarMeta(varSlot)\paramOffset >= 0 And gFunctionDepth > 0
      ; Write to Local array using paramOffset
      gStack(gStackDepth)\LocalString(gVarMeta(varSlot)\paramOffset) = gVar( sp )\ss
   Else
      ; Regular global variable - write to variable slot
      gVar( varSlot )\ss = gVar( sp )\ss
   EndIf

   pc + 1
EndProcedure

Procedure               C2POPF()
   Protected varSlot.i

   vm_DebugFunctionName()
   sp - 1
   varSlot = _AR()\i

   ; Check if this is a parameter/local variable AND we're in a function
   If gVarMeta(varSlot)\paramOffset >= 0 And gFunctionDepth > 0
      ; Write to Local array using paramOffset
      gStack(gStackDepth)\LocalFloat(gVarMeta(varSlot)\paramOffset) = gVar( sp )\f
   Else
      ; Regular global variable - write to variable slot
      gVar( varSlot )\f = gVar( sp )\f
   EndIf

   pc + 1
EndProcedure

Procedure               C2PUSHS()
   Protected varSlot.i

   vm_DebugFunctionName()
   varSlot = _AR()\i

   ; Check if this is a parameter/local variable AND we're in a function
   If gVarMeta(varSlot)\paramOffset >= 0 And gFunctionDepth > 0
      ; Read from Local array using paramOffset
      gVar( sp )\ss = gStack(gStackDepth)\LocalString(gVarMeta(varSlot)\paramOffset)
   Else
      ; Regular global variable
      gVar( sp )\ss = gVar( varSlot )\ss
   EndIf

   sp + 1
   pc + 1
EndProcedure

Procedure               C2PUSHF()
   Protected varSlot.i

   vm_DebugFunctionName()
   varSlot = _AR()\i

   ; Check if this is a parameter/local variable AND we're in a function
   If gVarMeta(varSlot)\paramOffset >= 0 And gFunctionDepth > 0
      ; Read from Local array using paramOffset
      gVar( sp )\f = gStack(gStackDepth)\LocalFloat(gVarMeta(varSlot)\paramOffset)
   Else
      ; Regular global variable
      gVar( sp )\f = gVar( varSlot )\f
   EndIf

   sp + 1
   pc + 1
EndProcedure

Procedure               C2Store()
   Protected varSlot.i

   vm_DebugFunctionName()
   sp - 1
   varSlot = _AR()\i

   ; Check if this is a parameter/local variable AND we're in a function
   If gVarMeta(varSlot)\paramOffset >= 0 And gFunctionDepth > 0
      ; Write to Local array using paramOffset
      gStack(gStackDepth)\LocalInt(gVarMeta(varSlot)\paramOffset) = gVar( sp )\i
   Else
      ; Regular global variable - write to variable slot
      gVar( varSlot )\i = gVar( sp )\i
   EndIf

   pc + 1
EndProcedure

Procedure               C2STORES()
   Protected varSlot.i

   vm_DebugFunctionName()
   sp - 1
   varSlot = _AR()\i

   ; Check if this is a parameter/local variable AND we're in a function
   If gVarMeta(varSlot)\paramOffset >= 0 And gFunctionDepth > 0
      ; Write to Local array using paramOffset
      gStack(gStackDepth)\LocalString(gVarMeta(varSlot)\paramOffset) = gVar( sp )\ss
   Else
      ; Regular global variable - write to variable slot
      gVar( varSlot )\ss = gVar( sp )\ss
   EndIf

   pc + 1
EndProcedure

Procedure               C2STOREF()
   Protected varSlot.i

   vm_DebugFunctionName()
   sp - 1
   varSlot = _AR()\i

   ; Check if this is a parameter/local variable AND we're in a function
   If gVarMeta(varSlot)\paramOffset >= 0 And gFunctionDepth > 0
      ; Write to Local array using paramOffset
      gStack(gStackDepth)\LocalFloat(gVarMeta(varSlot)\paramOffset) = gVar( sp )\f
   Else
      ; Regular global variable - write to variable slot
      gVar( varSlot )\f = gVar( sp )\f
   EndIf

   pc + 1
EndProcedure

Procedure               C2MOV()
   vm_DebugFunctionName()
   gVar( _AR()\i )\i = gVar( _AR()\j )\i
   pc + 1
EndProcedure

Procedure               C2MOVS()
   vm_DebugFunctionName()
   gVar( _AR()\i )\ss = gVar( _AR()\j )\ss
   pc + 1
EndProcedure

Procedure               C2MOVF()
   vm_DebugFunctionName()
   gVar( _AR()\i )\f = gVar( _AR()\j )\f
   pc + 1
EndProcedure

;- Local Variable Opcodes (use LocalVars array, no flag checks)
Procedure               C2LMOV()
   vm_DebugFunctionName()
   ; Copy from global to local: LocalInt(offset) = gVarInt(global_index)
   If _AR()\i < 0 Or _AR()\i > ArraySize(gStack(gStackDepth)\LocalInt())
      Debug "*** ERROR LMOV at pc=" + Str(pc) + " INVALID INDEX: _AR()\i=" + Str(_AR()\i) + " but LocalInt ArraySize=" + Str(ArraySize(gStack(gStackDepth)\LocalInt())) + " (valid: 0-" + Str(ArraySize(gStack(gStackDepth)\LocalInt())) + ") _AR()\j=" + Str(_AR()\j) + " gStackDepth=" + Str(gStackDepth)
      ProcedureReturn
   EndIf
   gStack(gStackDepth)\LocalInt(_AR()\i) = gVar( _AR()\j )\i
   pc + 1
EndProcedure

Procedure               C2LMOVS()
   vm_DebugFunctionName()
   If _AR()\i < 0 Or _AR()\i > ArraySize(gStack(gStackDepth)\LocalString())
      Debug "*** ERROR LMOVS at pc=" + Str(pc) + " INVALID INDEX: _AR()\i=" + Str(_AR()\i) + " but LocalString ArraySize=" + Str(ArraySize(gStack(gStackDepth)\LocalString())) + " (valid: 0-" + Str(ArraySize(gStack(gStackDepth)\LocalString())) + ") _AR()\j=" + Str(_AR()\j) + " gStackDepth=" + Str(gStackDepth)
      ProcedureReturn
   EndIf
   gStack(gStackDepth)\LocalString(_AR()\i) = gVar( _AR()\j )\ss
   pc + 1
EndProcedure

Procedure               C2LMOVF()
   vm_DebugFunctionName()
   If _AR()\i < 0 Or _AR()\i > ArraySize(gStack(gStackDepth)\LocalFloat())
      Debug "*** ERROR LMOVF at pc=" + Str(pc) + " INVALID INDEX: _AR()\i=" + Str(_AR()\i) + " but LocalFloat ArraySize=" + Str(ArraySize(gStack(gStackDepth)\LocalFloat())) + " (valid: 0-" + Str(ArraySize(gStack(gStackDepth)\LocalFloat())) + ") _AR()\j=" + Str(_AR()\j) + " gStackDepth=" + Str(gStackDepth)
      ProcedureReturn
   EndIf
   gStack(gStackDepth)\LocalFloat(_AR()\i) = gVar( _AR()\j )\f
   pc + 1
EndProcedure

Procedure               C2LFETCH()
   vm_DebugFunctionName()
   ; Fetch local integer variable to stack
   gVar( sp )\i = gStack(gStackDepth)\LocalInt(_AR()\i)
   sp + 1
   pc + 1
EndProcedure

Procedure               C2LFETCHS()
   vm_DebugFunctionName()
   gVar( sp )\ss = gStack(gStackDepth)\LocalString(_AR()\i)
   sp + 1
   pc + 1
EndProcedure

Procedure               C2LFETCHF()
   vm_DebugFunctionName()
   gVar( sp )\f = gStack(gStackDepth)\LocalFloat(_AR()\i)
   sp + 1
   pc + 1
EndProcedure

Procedure               C2LSTORE()
   vm_DebugFunctionName()
   ; Store from stack to local variable
   sp - 1
   ; Validate index - only show error if invalid
   If _AR()\i < 0 Or _AR()\i > ArraySize(gStack(gStackDepth)\LocalInt())
      Debug "*** ERROR LSTORE at pc=" + Str(pc) + " INVALID INDEX: _AR()\i=" + Str(_AR()\i) + " but LocalInt ArraySize=" + Str(ArraySize(gStack(gStackDepth)\LocalInt())) + " (valid: 0-" + Str(ArraySize(gStack(gStackDepth)\LocalInt())) + ") sp=" + Str(sp) + " gStackDepth=" + Str(gStackDepth)
      End
   EndIf
   gStack(gStackDepth)\LocalInt(_AR()\i) = gVar( sp )\i
   pc + 1
EndProcedure

Procedure               C2LSTORES()
   vm_DebugFunctionName()
   sp - 1
   ; Validate index - only show error if invalid
   If _AR()\i < 0 Or _AR()\i > ArraySize(gStack(gStackDepth)\LocalString())
      Debug "*** ERROR LSTORES at pc=" + Str(pc) + " INVALID INDEX: _AR()\i=" + Str(_AR()\i) + " but LocalString ArraySize=" + Str(ArraySize(gStack(gStackDepth)\LocalString())) + " (valid: 0-" + Str(ArraySize(gStack(gStackDepth)\LocalString())) + ") sp=" + Str(sp)
      End
   EndIf
   gStack(gStackDepth)\LocalString(_AR()\i) = gVar( sp )\ss
   pc + 1
EndProcedure

Procedure               C2LSTOREF()
   vm_DebugFunctionName()
   sp - 1
   ; Validate index - only show error if invalid
   If _AR()\i < 0 Or _AR()\i > ArraySize(gStack(gStackDepth)\LocalFloat())
      Debug "*** ERROR LSTOREF at pc=" + Str(pc) + " INVALID INDEX: _AR()\i=" + Str(_AR()\i) + " but LocalFloat ArraySize=" + Str(ArraySize(gStack(gStackDepth)\LocalFloat())) + " (valid: 0-" + Str(ArraySize(gStack(gStackDepth)\LocalFloat())) + ") sp=" + Str(sp)
      End
   EndIf
   gStack(gStackDepth)\LocalFloat(_AR()\i) = gVar( sp )\f
   pc + 1
EndProcedure

Procedure               C2JMP()
   vm_DebugFunctionName()
   pc + _AR()\i
EndProcedure

Procedure               C2JZ()
   vm_DebugFunctionName()
   sp - 1
   If Not gVar(sp)\i
      pc + _AR()\i
   Else
      pc + 1
   EndIf
EndProcedure

Procedure               C2TENIF()
   ; Ternary IF: Jump if condition is false (0)
   ; Identical to C2JZ but with distinct opcode for ternary expressions
   vm_DebugFunctionName()
   sp - 1
   If Not gVar(sp)\i
      pc + _AR()\i
   Else
      pc + 1
   EndIf
EndProcedure

Procedure               C2TENELSE()
   ; Ternary ELSE: Unconditional jump past false branch
   ; Identical to C2JMP but with distinct opcode for ternary expressions
   vm_DebugFunctionName()
   pc + _AR()\i
EndProcedure

Procedure               C2ADD()
   vm_DebugFunctionName()
   vm_BitOperation( + )
EndProcedure

Procedure               C2ADDSTR()
   vm_DebugFunctionName()

   sp - 1

   ; Both operands are guaranteed to be strings by PostProcessor conversions
   ; Simply concatenate the two string fields
   gVar(sp - 1)\ss = gVar(sp - 1)\ss + gVar(sp)\ss

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

Procedure               C2ITOF()
   vm_DebugFunctionName()
   ; Convert integer to float at stack top
   gVar(sp - 1)\f = gVar(sp - 1)\i
   pc + 1
EndProcedure

Procedure               C2FTOI()
   vm_DebugFunctionName()
   ; Convert float to integer at stack top
   gVar(sp - 1)\i = gVar(sp - 1)\f
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
   gVar( sp - 1 )\i = -gVar( sp - 1 )\i
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
      If gFastPrint = #False
         SetGadgetItemText( #edConsole, cy, cline )
      EndIf
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
      If gFastPrint = #False
         SetGadgetItemText( #edConsole, cy, cline )
      EndIf
   CompilerEndIf
   pc + 1
EndProcedure

Procedure               C2PRTF()
   vm_DebugFunctionName()
   sp - 1
   CompilerIf #PB_Compiler_ExecutableFormat = #PB_Compiler_Console
      gBatchOutput + StrD( gVar(sp)\f, gDecs )
      Print(StrD( gVar(sp)\f, gDecs ))  ; Echo to console
   CompilerElse
      cline = cline + StrD( gVar(sp)\f, gDecs )
      If gFastPrint = #False
         SetGadgetItemText( #edConsole, cy, cline )
      EndIf
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
         If gFastPrint = #True
            SetGadgetItemText( #edConsole, cy, cline )
         EndIf
         
         cy + 1
         cline = ""
         AddGadgetItem( #edConsole, -1, "" )
         vm_ScrollToBottom( #edConsole )
      Else
         cline = cline + Chr( gVar( sp )\i )
         If gFastPrint = #False
            SetGadgetItemText( #edConsole, cy, cline )
         EndIf
      EndIf
   CompilerEndIf
   pc + 1
EndProcedure

Procedure               C2FLOATNEGATE()
   vm_DebugFunctionName()
   gVar(sp - 1)\f = -gVar(sp - 1)\f
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
   sp - 1
   ; Tolerance-based float inequality: NOT equal if difference > tolerance
   If Abs(gVar(sp - 1)\f - gVar( sp )\f) > gFloatTolerance
      gVar(sp - 1)\i = 1
   Else
      gVar(sp - 1)\i = 0
   EndIf
   pc + 1
EndProcedure

Procedure               C2FLOATEQUAL()
   vm_DebugFunctionName()
   sp - 1
   ; Tolerance-based float equality: equal if difference <= tolerance
   If Abs(gVar(sp - 1)\f - gVar(sp)\f ) <= gFloatTolerance
      gVar( sp - 1)\i = 1
   Else
      gVar(sp - 1)\i = 0
   EndIf
   pc + 1
EndProcedure

Procedure               C2CALL()
   vm_DebugFunctionName()
   Protected nParams.l, nLocals.l, totalVars.l, nLocalArrays.l
   Protected i.l, paramSp.l, funcId.l, pcAddr.l, varSlot.l, arraySize.l
   Protected prevStackDepth.i

   ; Read nParams, nLocals, and nLocalArrays from instruction fields
   nParams = _AR()\j
   nLocals = _AR()\n
   nLocalArrays = _AR()\ndx
   totalVars = nParams + nLocals
   pcAddr = _AR()\i  ; PC address for jumping
   funcId = _AR()\flags  ; Function ID for gFuncLocalArraySlots lookup

   ; User-defined function - create stack frame and jump to bytecode address
   prevStackDepth = gStackDepth

   ; Increment stack depth (create new frame)
   gStackDepth = gStackDepth + 1

   If gStackDepth >= gMaxStackDepth
      Debug "*** FATAL ERROR: Stack overflow - max depth " + Str(gMaxStackDepth) + " exceeded at pc=" + Str(pc) + " funcId=" + Str(funcId)
      End
   EndIf

   gStack(gStackDepth)\pc = pc + 1
   gStack(gStackDepth)\sp = sp - nParams  ; Save sp BEFORE params were pushed (FIX: prevents stack leak)

   ; Allocate separate Local arrays for this function call (params + locals)
   If totalVars > 0
      ;Debug "CALL: Allocating Local arrays - nParams=" + Str(nParams) + " nLocals=" + Str(nLocals) + " totalVars=" + Str(totalVars) + " -> ReDim(" + Str(totalVars-1) + ") funcId=" + Str(funcId)
      ReDim gStack(gStackDepth)\LocalInt(totalVars - 1)
      ReDim gStack(gStackDepth)\LocalFloat(totalVars - 1)
      ReDim gStack(gStackDepth)\LocalString(totalVars - 1)
      ;Debug "CALL: After ReDim - ArraySize(LocalInt)=" + Str(ArraySize(gStack(gStackDepth)\LocalInt())) + " ArraySize(LocalFloat)=" + Str(ArraySize(gStack(gStackDepth)\LocalFloat())) + " gStackDepth=" + Str(gStackDepth)

      ; Copy parameters from stack into Local arrays
      paramSp = sp - nParams
      For i = 0 To nParams - 1
         gStack(gStackDepth)\LocalInt(i) = gVar(paramSp + i)\i
         gStack(gStackDepth)\LocalFloat(i) = gVar(paramSp + i)\f
         gStack(gStackDepth)\LocalString(i) = gVar(paramSp + i)\ss
      Next
   EndIf

   ; Allocate and initialize local arrays for this function

   If nLocalArrays > 0
      ReDim gStack(gStackDepth)\LocalArrays(nLocalArrays - 1)

      ; Initialize each local array with proper size and type
      ; funcId is the parsing function ID from _AR()\flags (gFuncLocalArraySlots is indexed by function ID, not PC address)
      For i = 0 To nLocalArrays - 1
         varSlot = gFuncLocalArraySlots(funcId, i)
         arraySize = gVarMeta(varSlot)\arraySize

         CompilerIf #DEBUG
            ;Debug "VM: Allocating local array[" + Str(i) + "] varSlot=" + Str(varSlot) + ", name=" + gVarMeta(varSlot)\name + ", arraySize=" + Str(arraySize)
         CompilerEndIf

         If arraySize > 0
            ReDim gStack(gStackDepth)\LocalArrays(i)\dta\ar(arraySize - 1)
            gStack(gStackDepth)\LocalArrays(i)\dta\size = arraySize  ; Store size in structure
         EndIf
      Next
   EndIf

   pc = pcAddr  ; Jump to function address (pcAddr from _AR()\i field)
   gFunctionDepth = gFunctionDepth + 1  ; Increment function depth counter

   ;If gFunctionDepth > 200
   ;   Debug "*** WARNING: Function depth exceeds 200! depth=" + Str(gFunctionDepth) + " gStackDepth=" + Str(gStackDepth)
   ;EndIf

EndProcedure

Procedure               C2Return()
   vm_DebugFunctionName()
   Protected returnValue.i
   Protected callerSp.i

   ; Initialize to default integer 0 (prevents uninitialized returns)
   returnValue = 0
   callerSp = gStack(gStackDepth)\sp

   ; Save return value from top of stack (sp-1) if there's anything on function's stack
   If sp > callerSp
      returnValue = gVar(sp - 1)\i
   EndIf

   ; Restore caller's program counter and stack pointer
   pc = gStack(gStackDepth)\pc
   sp = callerSp

   ; Cleanup local arrays (ReDim to 0 to free memory)
   ReDim gStack(gStackDepth)\LocalArrays(0)

   ; Delete current stack frame (decrement depth)
   ;Debug "RET at pc=" + Str(pc) + ": Decrementing gStackDepth from " + Str(gStackDepth) + " to " + Str(gStackDepth - 1)
   gStackDepth = gStackDepth - 1
   gFunctionDepth = gFunctionDepth - 1  ; Decrement function depth counter

   ; Push return value onto caller's stack
   gVar( sp )\i = returnValue
   sp + 1
EndProcedure

Procedure               C2ReturnF()
   vm_DebugFunctionName()

   ; Float return - preserves float return value from stack
   Protected returnValue.f
   Protected callerSp.i

   ; Initialize to default float 0.0
   returnValue = 0.0

   ; Save caller's stack pointer
   callerSp = gStack(gStackDepth)\sp

   ; Save float return value from top of stack (sp-1) if there's anything on function's stack
   If sp > callerSp
      returnValue = gVar(sp - 1)\f
   EndIf

   ; Restore caller's program counter and stack pointer
   pc = gStack(gStackDepth)\pc
   sp = callerSp

   ; Cleanup local arrays (ReDim to 0 to free memory)
   ReDim gStack(gStackDepth)\LocalArrays(0)

   ; Delete current stack frame (decrement depth)
   ;Debug "RETF at pc=" + Str(pc) + ": Decrementing gStackDepth from " + Str(gStackDepth) + " to " + Str(gStackDepth - 1)
   gStackDepth = gStackDepth - 1
   gFunctionDepth = gFunctionDepth - 1  ; Decrement function depth counter

   ; Push float return value onto caller's stack
   gVar( sp )\f = returnValue
   sp + 1
EndProcedure

Procedure               C2ReturnS()
   vm_DebugFunctionName()

   ; String return - preserves string return value from stack
   Protected returnValue.s
   Protected callerSp.i

   ; Initialize to default empty string
   returnValue = ""

   ; Save caller's stack pointer
   callerSp = gStack(gStackDepth)\sp

   ; Save string return value from top of stack (sp-1) if there's anything on function's stack
   If sp > callerSp
      returnValue = gVar(sp - 1)\ss
   EndIf

   ; Restore caller's program counter and stack pointer
   pc = gStack(gStackDepth)\pc
   sp = callerSp

   ; Cleanup local arrays (ReDim to 0 to free memory)
   ReDim gStack(gStackDepth)\LocalArrays(0)

   ; Delete current stack frame (decrement depth)
   ;Debug "RETS at pc=" + Str(pc) + ": Decrementing gStackDepth from " + Str(gStackDepth) + " to " + Str(gStackDepth - 1)
   gStackDepth = gStackDepth - 1
   gFunctionDepth = gFunctionDepth - 1  ; Decrement function depth counter

   ; Push string return value onto caller's stack
   gVar( sp )\ss = returnValue
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
   pc + 1
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
   pc + 1
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
   pc + 1
EndProcedure

;- Array Operations

Procedure               C2ARRAYINDEX()
   ; Compute array element index
   ; _AR()\i = array variable slot
   ; _AR()\j = element size (slots per element, usually 1 for primitives)
   ; _AR()\n = (available for future use - size now in structure)
   ; Stack: index → computed element index

   Protected arrSlot.i, index.i, elementSize.i

   vm_DebugFunctionName()

   arrSlot = _AR()\i
   elementSize = _AR()\j

   sp - 1
   index = gVar(sp)\i            ; Pop index from stack

   ; Optional bounds checking
   CompilerIf #DEBUG
      If index < 0 Or index >= _AR()\n
         ; TODO: Add runtime error handling
         Debug "Array index out of bounds: " + Str(index) + " (size: " + Str(_AR()\n) + ")"
      EndIf
   CompilerEndIf

   ; Push computed index back to stack (just the index, not the base)
   gVar(sp)\i = index
   sp + 1
   pc + 1
EndProcedure

Procedure               C2ARRAYFETCH()
   ; Generic array fetch (copies entire stVT)
   ; _AR()\i = array index (global varSlot OR local array index)
   ; _AR()\j = 0 for global, 1 for local
   ; _AR()\n = (available for future use - size now in structure)
   ; _AR()\ndx = index variable slot (if ndx >= 0, optimized path)

   Protected arrIdx.i, index.i

   vm_DebugFunctionName()

   arrIdx = _AR()\i

   ; Get index from ndx field (optimized) or stack
   If _AR()\ndx >= 0
      index = gVar(_AR()\ndx)\i
   Else
      sp - 1
      index = gVar(sp)\i
   EndIf

   ; Bounds checking - read size from structure
   CompilerIf #DEBUG
      Protected arraySize.i
      If _AR()\j
         arraySize = gStack(gStackDepth)\LocalArrays(arrIdx)\dta\size
      Else
         arraySize = gVar(arrIdx)\dta\size
      EndIf
      If index < 0 Or index >= arraySize
         Debug "Array index out of bounds: " + Str(index) + " (size: " + Str(arraySize) + ") at pc=" + Str(pc)
         gExitApplication = #True  ; Force halt on error
         ProcedureReturn
      EndIf
   CompilerEndIf

   ; Copy entire stVT - j=1 for local, j=0 for global
   If _AR()\j
      CopyStructure( gVar(sp), gStack(gStackDepth)\LocalArrays(arrIdx)\dta\ar(index), stVTSimple )
   Else
      CopyStructure( gVar(sp), gVar(arrIdx)\dta\ar(index), stVTSimple )
   EndIf

   sp + 1
   pc + 1
EndProcedure

Procedure               C2ARRAYSTORE()
   ; Generic array store (copies entire stVT)
   ; _AR()\i = array index (global varSlot OR local array index)
   ; _AR()\j = 0 for global, 1 for local
   ; _AR()\n = (available for future use - size now in structure)
   ; _AR()\ndx = index variable slot (if ndx >= 0, optimized path)

   Protected arrIdx.i, index.i

   vm_DebugFunctionName()

   arrIdx = _AR()\i

   ; Get index from ndx field (optimized) or stack
   If _AR()\ndx >= 0
      index = gVar(_AR()\ndx)\i
      sp - 1
   Else
      sp - 1
      index = gVar(sp)\i
      sp - 1
   EndIf

   ; Bounds checking
   CompilerIf #DEBUG
      If index < 0 Or index >= _AR()\n
         Debug "Array index out of bounds: " + Str(index) + " (size: " + Str(_AR()\n) + ") at pc=" + Str(pc)
         gExitApplication = #True  ; Force halt on error
         ProcedureReturn
      EndIf
   CompilerEndIf

   ; Copy entire stVT - j=1 for local, j=0 for global
   If _AR()\j
      CopyStructure( gStack(gStackDepth)\LocalArrays(arrIdx)\dta\ar(index), gVar(sp), stVTSimple )
   Else
      CopyStructure( gVar(arrIdx)\dta\ar(index), gVar(sp), stVTSimple )
   EndIf

   pc + 1
EndProcedure

;- Specialized ARRAYFETCH handlers (no runtime branching)

Procedure               C2ARRAYFETCH_INT_GLOBAL_OPT()
   ; Integer array fetch - global array, optimized index
   Protected arrIdx.i, index.i
   vm_DebugFunctionName()
   arrIdx = _AR()\i
   index = gVar(_AR()\ndx)\i
   CompilerIf #DEBUG
      Protected arraySize.i = gVar(arrIdx)\dta\size
      If index < 0 Or index >= arraySize
         Debug "Array index out of bounds: " + Str(index) + " (size: " + Str(arraySize) + ") at pc=" + Str(pc)
         gExitApplication = #True
         ProcedureReturn
      EndIf
   CompilerEndIf
   gVar(sp)\f = 0.0
   gVar(sp)\i = gVar(arrIdx)\dta\ar(index)\i
   sp + 1
   pc + 1
EndProcedure

Procedure               C2ARRAYFETCH_INT_GLOBAL_STACK()
   ; Integer array fetch - global array, stack index
   Protected arrIdx.i, index.i
   vm_DebugFunctionName()
   arrIdx = _AR()\i
   sp - 1
   index = gVar(sp)\i
   CompilerIf #DEBUG
      Protected arraySize.i = gVar(arrIdx)\dta\size
      If index < 0 Or index >= arraySize
         Debug "Array index out of bounds: " + Str(index) + " (size: " + Str(arraySize) + ") at pc=" + Str(pc)
         gExitApplication = #True
         ProcedureReturn
      EndIf
   CompilerEndIf
   gVar(sp)\f = 0.0
   gVar(sp)\i = gVar(arrIdx)\dta\ar(index)\i
   sp + 1
   pc + 1
EndProcedure

Procedure               C2ARRAYFETCH_INT_LOCAL_OPT()
   ; Integer array fetch - local array, optimized index
   Protected arrIdx.i, index.i
   vm_DebugFunctionName()
   arrIdx = _AR()\i
   index = gVar(_AR()\ndx)\i
   CompilerIf #DEBUG
      Protected arraySize.i = gStack(gStackDepth)\LocalArrays(arrIdx)\dta\size
      If index < 0 Or index >= arraySize
         Debug "Array index out of bounds: " + Str(index) + " (size: " + Str(arraySize) + ") at pc=" + Str(pc)
         gExitApplication = #True
         ProcedureReturn
      EndIf
   CompilerEndIf
   gVar(sp)\f = 0.0
   gVar(sp)\i = gStack(gStackDepth)\LocalArrays(arrIdx)\dta\ar(index)\i
   sp + 1
   pc + 1
EndProcedure

Procedure               C2ARRAYFETCH_INT_LOCAL_STACK()
   ; Integer array fetch - local array, stack index
   Protected arrIdx.i, index.i
   vm_DebugFunctionName()
   arrIdx = _AR()\i
   sp - 1
   index = gVar(sp)\i
   CompilerIf #DEBUG
      Protected arraySize.i = gStack(gStackDepth)\LocalArrays(arrIdx)\dta\size
      If index < 0 Or index >= arraySize
         Debug "Array index out of bounds: " + Str(index) + " (size: " + Str(arraySize) + ") at pc=" + Str(pc)
         gExitApplication = #True
         ProcedureReturn
      EndIf
   CompilerEndIf
   gVar(sp)\f = 0.0
   gVar(sp)\i = gStack(gStackDepth)\LocalArrays(arrIdx)\dta\ar(index)\i
   sp + 1
   pc + 1
EndProcedure

Procedure               C2ARRAYFETCH_FLOAT_GLOBAL_OPT()
   ; Float array fetch - global array, optimized index
   Protected arrIdx.i, index.i
   vm_DebugFunctionName()
   arrIdx = _AR()\i
   index = gVar(_AR()\ndx)\i
   CompilerIf #DEBUG
      Protected arraySize.i = gVar(arrIdx)\dta\size
      If index < 0 Or index >= arraySize
         Debug "Array index out of bounds: " + Str(index) + " (size: " + Str(arraySize) + ") at pc=" + Str(pc)
         gExitApplication = #True
         ProcedureReturn
      EndIf
   CompilerEndIf
   gVar(sp)\i = 0
   gVar(sp)\f = gVar(arrIdx)\dta\ar(index)\f
   sp + 1
   pc + 1
EndProcedure

Procedure               C2ARRAYFETCH_FLOAT_GLOBAL_STACK()
   ; Float array fetch - global array, stack index
   Protected arrIdx.i, index.i
   vm_DebugFunctionName()
   arrIdx = _AR()\i
   sp - 1
   index = gVar(sp)\i
   CompilerIf #DEBUG
      Protected arraySize.i = gVar(arrIdx)\dta\size
      If index < 0 Or index >= arraySize
         Debug "Array index out of bounds: " + Str(index) + " (size: " + Str(arraySize) + ") at pc=" + Str(pc)
         gExitApplication = #True
         ProcedureReturn
      EndIf
   CompilerEndIf
   gVar(sp)\i = 0
   gVar(sp)\f = gVar(arrIdx)\dta\ar(index)\f
   sp + 1
   pc + 1
EndProcedure

Procedure               C2ARRAYFETCH_FLOAT_LOCAL_OPT()
   ; Float array fetch - local array, optimized index
   Protected arrIdx.i, index.i
   vm_DebugFunctionName()
   arrIdx = _AR()\i
   index = gVar(_AR()\ndx)\i
   CompilerIf #DEBUG
      Protected arraySize.i = gStack(gStackDepth)\LocalArrays(arrIdx)\dta\size
      If index < 0 Or index >= arraySize
         Debug "Array index out of bounds: " + Str(index) + " (size: " + Str(arraySize) + ") at pc=" + Str(pc)
         gExitApplication = #True
         ProcedureReturn
      EndIf
   CompilerEndIf
   gVar(sp)\i = 0
   gVar(sp)\f = gStack(gStackDepth)\LocalArrays(arrIdx)\dta\ar(index)\f
   sp + 1
   pc + 1
EndProcedure

Procedure               C2ARRAYFETCH_FLOAT_LOCAL_STACK()
   ; Float array fetch - local array, stack index
   Protected arrIdx.i, index.i
   vm_DebugFunctionName()
   arrIdx = _AR()\i
   sp - 1
   index = gVar(sp)\i
   CompilerIf #DEBUG
      Protected arraySize.i = gStack(gStackDepth)\LocalArrays(arrIdx)\dta\size
      If index < 0 Or index >= arraySize
         Debug "Array index out of bounds: " + Str(index) + " (size: " + Str(arraySize) + ") at pc=" + Str(pc)
         gExitApplication = #True
         ProcedureReturn
      EndIf
   CompilerEndIf
   gVar(sp)\i = 0
   gVar(sp)\f = gStack(gStackDepth)\LocalArrays(arrIdx)\dta\ar(index)\f
   sp + 1
   pc + 1
EndProcedure

Procedure               C2ARRAYFETCH_STR_GLOBAL_OPT()
   ; String array fetch - global array, optimized index
   Protected arrIdx.i, index.i
   vm_DebugFunctionName()
   arrIdx = _AR()\i
   index = gVar(_AR()\ndx)\i
   CompilerIf #DEBUG
      Protected arraySize.i = gVar(arrIdx)\dta\size
      If index < 0 Or index >= arraySize
         Debug "Array index out of bounds: " + Str(index) + " (size: " + Str(arraySize) + ") at pc=" + Str(pc)
         gExitApplication = #True
         ProcedureReturn
      EndIf
   CompilerEndIf
   gVar(sp)\i = 0
   gVar(sp)\f = 0.0
   gVar(sp)\ss = gVar(arrIdx)\dta\ar(index)\ss
   sp + 1
   pc + 1
EndProcedure

Procedure               C2ARRAYFETCH_STR_GLOBAL_STACK()
   ; String array fetch - global array, stack index
   Protected arrIdx.i, index.i
   vm_DebugFunctionName()
   arrIdx = _AR()\i
   sp - 1
   index = gVar(sp)\i
   CompilerIf #DEBUG
      Protected arraySize.i = gVar(arrIdx)\dta\size
      If index < 0 Or index >= arraySize
         Debug "Array index out of bounds: " + Str(index) + " (size: " + Str(arraySize) + ") at pc=" + Str(pc)
         gExitApplication = #True
         ProcedureReturn
      EndIf
   CompilerEndIf
   gVar(sp)\i = 0
   gVar(sp)\f = 0.0
   gVar(sp)\ss = gVar(arrIdx)\dta\ar(index)\ss
   sp + 1
   pc + 1
EndProcedure

Procedure               C2ARRAYFETCH_STR_LOCAL_OPT()
   ; String array fetch - local array, optimized index
   Protected arrIdx.i, index.i
   vm_DebugFunctionName()
   arrIdx = _AR()\i
   index = gVar(_AR()\ndx)\i
   CompilerIf #DEBUG
      Protected arraySize.i = gStack(gStackDepth)\LocalArrays(arrIdx)\dta\size
      If index < 0 Or index >= arraySize
         Debug "Array index out of bounds: " + Str(index) + " (size: " + Str(arraySize) + ") at pc=" + Str(pc)
         gExitApplication = #True
         ProcedureReturn
      EndIf
   CompilerEndIf
   gVar(sp)\i = 0
   gVar(sp)\f = 0.0
   gVar(sp)\ss = gStack(gStackDepth)\LocalArrays(arrIdx)\dta\ar(index)\ss
   sp + 1
   pc + 1
EndProcedure

Procedure               C2ARRAYFETCH_STR_LOCAL_STACK()
   ; String array fetch - local array, stack index
   Protected arrIdx.i, index.i
   vm_DebugFunctionName()
   arrIdx = _AR()\i
   sp - 1
   index = gVar(sp)\i
   CompilerIf #DEBUG
      Protected arraySize.i = gStack(gStackDepth)\LocalArrays(arrIdx)\dta\size
      If index < 0 Or index >= arraySize
         Debug "Array index out of bounds: " + Str(index) + " (size: " + Str(arraySize) + ") at pc=" + Str(pc)
         gExitApplication = #True
         ProcedureReturn
      EndIf
   CompilerEndIf
   gVar(sp)\i = 0
   gVar(sp)\f = 0.0
   gVar(sp)\ss = gStack(gStackDepth)\LocalArrays(arrIdx)\dta\ar(index)\ss
   sp + 1
   pc + 1
EndProcedure

;- Specialized ARRAYSTORE handlers (no runtime branching)

Procedure               C2ARRAYSTORE_INT_GLOBAL_OPT_OPT()
   ; Integer array store - global array, optimized index, optimized value
   Protected arrIdx.i, index.i, value.i
   vm_DebugFunctionName()
   arrIdx = _AR()\i
   index = gVar(_AR()\ndx)\i
   value = gVar(_AR()\n)\i
   CompilerIf #DEBUG
      Protected arraySize.i = gVar(arrIdx)\dta\size
      If index < 0 Or index >= arraySize
         Debug "Array index out of bounds: " + Str(index) + " (size: " + Str(arraySize) + ") at pc=" + Str(pc)
         gExitApplication = #True
         ProcedureReturn
      EndIf
   CompilerEndIf
   gVar(arrIdx)\dta\ar(index)\i = value
   pc + 1
EndProcedure

Procedure               C2ARRAYSTORE_INT_GLOBAL_OPT_STACK()
   ; Integer array store - global array, optimized index, stack value
   Protected arrIdx.i, index.i, value.i
   vm_DebugFunctionName()
   arrIdx = _AR()\i
   index = gVar(_AR()\ndx)\i
   sp - 1
   value = gVar(sp)\i
   CompilerIf #DEBUG
      Protected arraySize.i = gVar(arrIdx)\dta\size
      If index < 0 Or index >= arraySize
         Debug "Array index out of bounds: " + Str(index) + " (size: " + Str(arraySize) + ") at pc=" + Str(pc)
         gExitApplication = #True
         ProcedureReturn
      EndIf
   CompilerEndIf
   gVar(arrIdx)\dta\ar(index)\i = value
   pc + 1
EndProcedure

Procedure               C2ARRAYSTORE_INT_GLOBAL_STACK_OPT()
   ; Integer array store - global array, stack index, optimized value
   Protected arrIdx.i, index.i, value.i
   vm_DebugFunctionName()
   arrIdx = _AR()\i
   sp - 1
   index = gVar(sp)\i
   value = gVar(_AR()\n)\i
   CompilerIf #DEBUG
      Protected arraySize.i = gVar(arrIdx)\dta\size
      If index < 0 Or index >= arraySize
         Debug "Array index out of bounds: " + Str(index) + " (size: " + Str(arraySize) + ") at pc=" + Str(pc)
         gExitApplication = #True
         ProcedureReturn
      EndIf
   CompilerEndIf
   gVar(arrIdx)\dta\ar(index)\i = value
   pc + 1
EndProcedure

Procedure               C2ARRAYSTORE_INT_GLOBAL_STACK_STACK()
   ; Integer array store - global array, stack index, stack value
   Protected arrIdx.i, index.i, value.i
   vm_DebugFunctionName()
   arrIdx = _AR()\i
   sp - 1
   index = gVar(sp)\i
   sp - 1
   value = gVar(sp)\i
   CompilerIf #DEBUG
      Protected arraySize.i = gVar(arrIdx)\dta\size
      If index < 0 Or index >= arraySize
         Debug "Array index out of bounds: " + Str(index) + " (size: " + Str(arraySize) + ") at pc=" + Str(pc)
         gExitApplication = #True
         ProcedureReturn
      EndIf
   CompilerEndIf
   gVar(arrIdx)\dta\ar(index)\i = value
   pc + 1
EndProcedure

Procedure               C2ARRAYSTORE_INT_LOCAL_OPT_OPT()
   ; Integer array store - local array, optimized index, optimized value
   Protected arrIdx.i, index.i, value.i
   vm_DebugFunctionName()
   arrIdx = _AR()\i
   index = gVar(_AR()\ndx)\i
   value = gVar(_AR()\n)\i
   CompilerIf #DEBUG
      Protected arraySize.i = gStack(gStackDepth)\LocalArrays(arrIdx)\dta\size
      If index < 0 Or index >= arraySize
         Debug "Array index out of bounds: " + Str(index) + " (size: " + Str(arraySize) + ") at pc=" + Str(pc)
         gExitApplication = #True
         ProcedureReturn
      EndIf
   CompilerEndIf
   gStack(gStackDepth)\LocalArrays(arrIdx)\dta\ar(index)\i = value
   pc + 1
EndProcedure

Procedure               C2ARRAYSTORE_INT_LOCAL_OPT_STACK()
   ; Integer array store - local array, optimized index, stack value
   Protected arrIdx.i, index.i, value.i
   vm_DebugFunctionName()
   arrIdx = _AR()\i
   index = gVar(_AR()\ndx)\i
   sp - 1
   value = gVar(sp)\i
   CompilerIf #DEBUG
      Protected arraySize.i = gStack(gStackDepth)\LocalArrays(arrIdx)\dta\size
      If index < 0 Or index >= arraySize
         Debug "Array index out of bounds: " + Str(index) + " (size: " + Str(arraySize) + ") at pc=" + Str(pc)
         gExitApplication = #True
         ProcedureReturn
      EndIf
   CompilerEndIf
   gStack(gStackDepth)\LocalArrays(arrIdx)\dta\ar(index)\i = value
   pc + 1
EndProcedure

Procedure               C2ARRAYSTORE_INT_LOCAL_STACK_OPT()
   ; Integer array store - local array, stack index, optimized value
   Protected arrIdx.i, index.i, value.i
   vm_DebugFunctionName()
   arrIdx = _AR()\i
   sp - 1
   index = gVar(sp)\i
   value = gVar(_AR()\n)\i
   CompilerIf #DEBUG
      Protected arraySize.i = gStack(gStackDepth)\LocalArrays(arrIdx)\dta\size
      If index < 0 Or index >= arraySize
         Debug "Array index out of bounds: " + Str(index) + " (size: " + Str(arraySize) + ") at pc=" + Str(pc)
         gExitApplication = #True
         ProcedureReturn
      EndIf
   CompilerEndIf
   gStack(gStackDepth)\LocalArrays(arrIdx)\dta\ar(index)\i = value
   pc + 1
EndProcedure

Procedure               C2ARRAYSTORE_INT_LOCAL_STACK_STACK()
   ; Integer array store - local array, stack index, stack value
   Protected arrIdx.i, index.i, value.i
   vm_DebugFunctionName()
   arrIdx = _AR()\i
   sp - 1
   index = gVar(sp)\i
   sp - 1
   value = gVar(sp)\i
   CompilerIf #DEBUG
      Protected arraySize.i = gStack(gStackDepth)\LocalArrays(arrIdx)\dta\size
      If index < 0 Or index >= arraySize
         Debug "Array index out of bounds: " + Str(index) + " (size: " + Str(arraySize) + ") at pc=" + Str(pc)
         gExitApplication = #True
         ProcedureReturn
      EndIf
   CompilerEndIf
   gStack(gStackDepth)\LocalArrays(arrIdx)\dta\ar(index)\i = value
   pc + 1
EndProcedure

Procedure               C2ARRAYSTORE_FLOAT_GLOBAL_OPT_OPT()
   ; Float array store - global array, optimized index, optimized value
   Protected arrIdx.i, index.i
   Protected value.f
   vm_DebugFunctionName()
   arrIdx = _AR()\i
   index = gVar(_AR()\ndx)\i
   value = gVar(_AR()\n)\f
   CompilerIf #DEBUG
      Protected arraySize.i = gVar(arrIdx)\dta\size
      If index < 0 Or index >= arraySize
         Debug "Array index out of bounds: " + Str(index) + " (size: " + Str(arraySize) + ") at pc=" + Str(pc)
         gExitApplication = #True
         ProcedureReturn
      EndIf
   CompilerEndIf
   gVar(arrIdx)\dta\ar(index)\f = value
   pc + 1
EndProcedure

Procedure               C2ARRAYSTORE_FLOAT_GLOBAL_OPT_STACK()
   ; Float array store - global array, optimized index, stack value
   Protected arrIdx.i, index.i
   Protected value.f
   vm_DebugFunctionName()
   arrIdx = _AR()\i
   index = gVar(_AR()\ndx)\i
   sp - 1
   value = gVar(sp)\f
   CompilerIf #DEBUG
      Protected arraySize.i = gVar(arrIdx)\dta\size
      If index < 0 Or index >= arraySize
         Debug "Array index out of bounds: " + Str(index) + " (size: " + Str(arraySize) + ") at pc=" + Str(pc)
         gExitApplication = #True
         ProcedureReturn
      EndIf
   CompilerEndIf
   gVar(arrIdx)\dta\ar(index)\f = value
   pc + 1
EndProcedure

Procedure               C2ARRAYSTORE_FLOAT_GLOBAL_STACK_OPT()
   ; Float array store - global array, stack index, optimized value
   Protected arrIdx.i, index.i
   Protected value.f
   vm_DebugFunctionName()
   arrIdx = _AR()\i
   sp - 1
   index = gVar(sp)\i
   value = gVar(_AR()\n)\f
   CompilerIf #DEBUG
      Protected arraySize.i = gVar(arrIdx)\dta\size
      If index < 0 Or index >= arraySize
         Debug "Array index out of bounds: " + Str(index) + " (size: " + Str(arraySize) + ") at pc=" + Str(pc)
         gExitApplication = #True
         ProcedureReturn
      EndIf
   CompilerEndIf
   gVar(arrIdx)\dta\ar(index)\f = value
   pc + 1
EndProcedure

Procedure               C2ARRAYSTORE_FLOAT_GLOBAL_STACK_STACK()
   ; Float array store - global array, stack index, stack value
   Protected arrIdx.i, index.i
   Protected value.f
   vm_DebugFunctionName()
   arrIdx = _AR()\i
   sp - 1
   index = gVar(sp)\i
   sp - 1
   value = gVar(sp)\f
   CompilerIf #DEBUG
      Protected arraySize.i = gVar(arrIdx)\dta\size
      If index < 0 Or index >= arraySize
         Debug "Array index out of bounds: " + Str(index) + " (size: " + Str(arraySize) + ") at pc=" + Str(pc)
         gExitApplication = #True
         ProcedureReturn
      EndIf
   CompilerEndIf
   gVar(arrIdx)\dta\ar(index)\f = value
   pc + 1
EndProcedure

Procedure               C2ARRAYSTORE_FLOAT_LOCAL_OPT_OPT()
   ; Float array store - local array, optimized index, optimized value
   Protected arrIdx.i, index.i
   Protected value.f
   vm_DebugFunctionName()
   arrIdx = _AR()\i
   index = gVar(_AR()\ndx)\i
   value = gVar(_AR()\n)\f
   CompilerIf #DEBUG
      Protected arraySize.i = gStack(gStackDepth)\LocalArrays(arrIdx)\dta\size
      If index < 0 Or index >= arraySize
         Debug "Array index out of bounds: " + Str(index) + " (size: " + Str(arraySize) + ") at pc=" + Str(pc)
         gExitApplication = #True
         ProcedureReturn
      EndIf
   CompilerEndIf
   gStack(gStackDepth)\LocalArrays(arrIdx)\dta\ar(index)\f = value
   pc + 1
EndProcedure

Procedure               C2ARRAYSTORE_FLOAT_LOCAL_OPT_STACK()
   ; Float array store - local array, optimized index, stack value
   Protected arrIdx.i, index.i
   Protected value.f
   vm_DebugFunctionName()
   arrIdx = _AR()\i
   index = gVar(_AR()\ndx)\i
   sp - 1
   value = gVar(sp)\f
   CompilerIf #DEBUG
      Protected arraySize.i = gStack(gStackDepth)\LocalArrays(arrIdx)\dta\size
      If index < 0 Or index >= arraySize
         Debug "Array index out of bounds: " + Str(index) + " (size: " + Str(arraySize) + ") at pc=" + Str(pc)
         gExitApplication = #True
         ProcedureReturn
      EndIf
   CompilerEndIf
   gStack(gStackDepth)\LocalArrays(arrIdx)\dta\ar(index)\f = value
   pc + 1
EndProcedure

Procedure               C2ARRAYSTORE_FLOAT_LOCAL_STACK_OPT()
   ; Float array store - local array, stack index, optimized value
   Protected arrIdx.i, index.i
   Protected value.f
   vm_DebugFunctionName()
   arrIdx = _AR()\i
   sp - 1
   index = gVar(sp)\i
   value = gVar(_AR()\n)\f
   CompilerIf #DEBUG
      Protected arraySize.i = gStack(gStackDepth)\LocalArrays(arrIdx)\dta\size
      If index < 0 Or index >= arraySize
         Debug "Array index out of bounds: " + Str(index) + " (size: " + Str(arraySize) + ") at pc=" + Str(pc)
         gExitApplication = #True
         ProcedureReturn
      EndIf
   CompilerEndIf
   gStack(gStackDepth)\LocalArrays(arrIdx)\dta\ar(index)\f = value
   pc + 1
EndProcedure

Procedure               C2ARRAYSTORE_FLOAT_LOCAL_STACK_STACK()
   ; Float array store - local array, stack index, stack value
   Protected arrIdx.i, index.i
   Protected value.f
   vm_DebugFunctionName()
   arrIdx = _AR()\i
   sp - 1
   index = gVar(sp)\i
   sp - 1
   value = gVar(sp)\f
   CompilerIf #DEBUG
      Protected arraySize.i = gStack(gStackDepth)\LocalArrays(arrIdx)\dta\size
      If index < 0 Or index >= arraySize
         Debug "Array index out of bounds: " + Str(index) + " (size: " + Str(arraySize) + ") at pc=" + Str(pc)
         gExitApplication = #True
         ProcedureReturn
      EndIf
   CompilerEndIf
   gStack(gStackDepth)\LocalArrays(arrIdx)\dta\ar(index)\f = value
   pc + 1
EndProcedure

Procedure               C2ARRAYSTORE_STR_GLOBAL_OPT_OPT()
   ; String array store - global array, optimized index, optimized value
   Protected arrIdx.i, index.i
   Protected value.s
   vm_DebugFunctionName()
   arrIdx = _AR()\i
   index = gVar(_AR()\ndx)\i
   value = gVar(_AR()\n)\ss
   CompilerIf #DEBUG
      Protected arraySize.i = gVar(arrIdx)\dta\size
      If index < 0 Or index >= arraySize
         Debug "Array index out of bounds: " + Str(index) + " (size: " + Str(arraySize) + ") at pc=" + Str(pc)
         gExitApplication = #True
         ProcedureReturn
      EndIf
   CompilerEndIf
   gVar(arrIdx)\dta\ar(index)\ss = value
   pc + 1
EndProcedure

Procedure               C2ARRAYSTORE_STR_GLOBAL_OPT_STACK()
   ; String array store - global array, optimized index, stack value
   Protected arrIdx.i, index.i
   Protected value.s
   vm_DebugFunctionName()
   arrIdx = _AR()\i
   index = gVar(_AR()\ndx)\i
   sp - 1
   value = gVar(sp)\ss
   CompilerIf #DEBUG
      Protected arraySize.i = gVar(arrIdx)\dta\size
      If index < 0 Or index >= arraySize
         Debug "Array index out of bounds: " + Str(index) + " (size: " + Str(arraySize) + ") at pc=" + Str(pc)
         gExitApplication = #True
         ProcedureReturn
      EndIf
   CompilerEndIf
   gVar(arrIdx)\dta\ar(index)\ss = value
   pc + 1
EndProcedure

Procedure               C2ARRAYSTORE_STR_GLOBAL_STACK_OPT()
   ; String array store - global array, stack index, optimized value
   Protected arrIdx.i, index.i
   Protected value.s
   vm_DebugFunctionName()
   arrIdx = _AR()\i
   sp - 1
   index = gVar(sp)\i
   value = gVar(_AR()\n)\ss
   CompilerIf #DEBUG
      Protected arraySize.i = gVar(arrIdx)\dta\size
      If index < 0 Or index >= arraySize
         Debug "Array index out of bounds: " + Str(index) + " (size: " + Str(arraySize) + ") at pc=" + Str(pc)
         gExitApplication = #True
         ProcedureReturn
      EndIf
   CompilerEndIf
   gVar(arrIdx)\dta\ar(index)\ss = value
   pc + 1
EndProcedure

Procedure               C2ARRAYSTORE_STR_GLOBAL_STACK_STACK()
   ; String array store - global array, stack index, stack value
   Protected arrIdx.i, index.i
   Protected value.s
   vm_DebugFunctionName()
   arrIdx = _AR()\i
   sp - 1
   index = gVar(sp)\i
   sp - 1
   value = gVar(sp)\ss
   CompilerIf #DEBUG
      Protected arraySize.i = gVar(arrIdx)\dta\size
      If index < 0 Or index >= arraySize
         Debug "Array index out of bounds: " + Str(index) + " (size: " + Str(arraySize) + ") at pc=" + Str(pc)
         gExitApplication = #True
         ProcedureReturn
      EndIf
   CompilerEndIf
   gVar(arrIdx)\dta\ar(index)\ss = value
   pc + 1
EndProcedure

Procedure               C2ARRAYSTORE_STR_LOCAL_OPT_OPT()
   ; String array store - local array, optimized index, optimized value
   Protected arrIdx.i, index.i
   Protected value.s
   vm_DebugFunctionName()
   arrIdx = _AR()\i
   index = gVar(_AR()\ndx)\i
   value = gVar(_AR()\n)\ss
   CompilerIf #DEBUG
      Protected arraySize.i = gStack(gStackDepth)\LocalArrays(arrIdx)\dta\size
      If index < 0 Or index >= arraySize
         Debug "Array index out of bounds: " + Str(index) + " (size: " + Str(arraySize) + ") at pc=" + Str(pc)
         gExitApplication = #True
         ProcedureReturn
      EndIf
   CompilerEndIf
   gStack(gStackDepth)\LocalArrays(arrIdx)\dta\ar(index)\ss = value
   pc + 1
EndProcedure

Procedure               C2ARRAYSTORE_STR_LOCAL_OPT_STACK()
   ; String array store - local array, optimized index, stack value
   Protected arrIdx.i, index.i
   Protected value.s
   vm_DebugFunctionName()
   arrIdx = _AR()\i
   index = gVar(_AR()\ndx)\i
   sp - 1
   value = gVar(sp)\ss
   CompilerIf #DEBUG
      Protected arraySize.i = gStack(gStackDepth)\LocalArrays(arrIdx)\dta\size
      If index < 0 Or index >= arraySize
         Debug "Array index out of bounds: " + Str(index) + " (size: " + Str(arraySize) + ") at pc=" + Str(pc)
         gExitApplication = #True
         ProcedureReturn
      EndIf
   CompilerEndIf
   gStack(gStackDepth)\LocalArrays(arrIdx)\dta\ar(index)\ss = value
   pc + 1
EndProcedure

Procedure               C2ARRAYSTORE_STR_LOCAL_STACK_OPT()
   ; String array store - local array, stack index, optimized value
   Protected arrIdx.i, index.i
   Protected value.s
   vm_DebugFunctionName()
   arrIdx = _AR()\i
   sp - 1
   index = gVar(sp)\i
   value = gVar(_AR()\n)\ss
   CompilerIf #DEBUG
      Protected arraySize.i = gStack(gStackDepth)\LocalArrays(arrIdx)\dta\size
      If index < 0 Or index >= arraySize
         Debug "Array index out of bounds: " + Str(index) + " (size: " + Str(arraySize) + ") at pc=" + Str(pc)
         gExitApplication = #True
         ProcedureReturn
      EndIf
   CompilerEndIf
   gStack(gStackDepth)\LocalArrays(arrIdx)\dta\ar(index)\ss = value
   pc + 1
EndProcedure

Procedure               C2ARRAYSTORE_STR_LOCAL_STACK_STACK()
   ; String array store - local array, stack index, stack value
   Protected arrIdx.i, index.i
   Protected value.s
   vm_DebugFunctionName()
   arrIdx = _AR()\i
   sp - 1
   index = gVar(sp)\i
   sp - 1
   value = gVar(sp)\ss
   CompilerIf #DEBUG
      Protected arraySize.i = gStack(gStackDepth)\LocalArrays(arrIdx)\dta\size
      If index < 0 Or index >= arraySize
         Debug "Array index out of bounds: " + Str(index) + " (size: " + Str(arraySize) + ") at pc=" + Str(pc)
         gExitApplication = #True
         ProcedureReturn
      EndIf
   CompilerEndIf
   gStack(gStackDepth)\LocalArrays(arrIdx)\dta\ar(index)\ss = value
   pc + 1
EndProcedure

Procedure               C2NOOP()
   vm_DebugFunctionName()
   ; No operation - just advance program counter
   pc + 1
EndProcedure

Procedure               C2HALT()
   vm_DebugFunctionName()
   ; Do nothing - the VM loop checks for HALT and exits
   pc + 1
EndProcedure

;- End VM functions
; IDE Options = PureBasic 6.21 (Windows - x64)
; CursorPosition = 66
; FirstLine = 47
; Folding = ----------------------------
; Markers = 625
; EnableAsm
; EnableThread
; EnableXP
; CPU = 1
; EnablePurifier
; EnableCompileCount = 0
; EnableBuildCount = 0
; EnableExeConstant