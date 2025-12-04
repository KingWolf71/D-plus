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

;#DEBUG = 0

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

; Macro for built-in functions: push float result
Macro                   vm_PushFloat(value)
   gVar( sp )\f = value
   sp + 1
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

;- Jump Table Functions

Procedure               C2FetchPush()
   vm_DebugFunctionName()

   ; V1.18.0: Direct global access, no intermediate variables for speed
   ; V1.20.27: Pointer metadata now handled by C2PFETCH opcode

   CompilerIf #DEBUG
      ; V1.020.064: Debug PUSH operations to track constant fetching
      ; V1.020.087: Temporarily disabled - too verbose for large arrays
      ; Debug "C2PUSH: pc=" + Str(pc) + " slot=" + Str(_AR()\i) + " value=" + Str(gVar(_AR()\i)\i) + " -> sp=" + Str(sp)
   CompilerEndIf

   gVar( sp )\i = gVar( _AR()\i )\i

   sp + 1
   pc + 1
EndProcedure

Procedure               C2FETCHS()
   vm_DebugFunctionName()

   ; V1.18.0: Direct global access, no intermediate variables for speed
   gVar( sp )\ss = gVar( _AR()\i )\ss

   sp + 1
   pc + 1
EndProcedure

Procedure               C2FETCHF()
   vm_DebugFunctionName()

   ; V1.18.0: Direct global access, no intermediate variables for speed
   gVar( sp )\f = gVar( _AR()\i )\f

   sp + 1
   pc + 1
EndProcedure

Procedure               C2POP()
   vm_DebugFunctionName()
   sp - 1

   ; V1.18.0: Direct global access, no intermediate variables for speed
   ; V1.20.27: Pointer metadata now handled by C2PPOP opcode
   gVar( _AR()\i )\i = gVar( sp )\i

   pc + 1
EndProcedure

Procedure               C2POPS()
   vm_DebugFunctionName()
   sp - 1

   ; V1.18.0: Direct global access, no intermediate variables for speed
   gVar( _AR()\i )\ss = gVar( sp )\ss

   pc + 1
EndProcedure

Procedure               C2POPF()
   vm_DebugFunctionName()
   sp - 1

   ; V1.18.0: Direct global access, no intermediate variables for speed
   gVar( _AR()\i )\f = gVar( sp )\f

   pc + 1
EndProcedure

Procedure               C2PUSHS()
   vm_DebugFunctionName()

   ; V1.18.0: Direct global access, no intermediate variables for speed
   gVar( sp )\ss = gVar( _AR()\i )\ss

   sp + 1
   pc + 1
EndProcedure

Procedure               C2PUSHF()
   vm_DebugFunctionName()

   ; V1.18.0: Direct global access, no intermediate variables for speed
   gVar( sp )\f = gVar( _AR()\i )\f

   sp + 1
   pc + 1
EndProcedure

Procedure               C2Store()
   vm_DebugFunctionName()
   sp - 1

   ; V1.18.0: Direct global access, no intermediate variables for speed
   ; V1.20.27: Pointer metadata now handled by C2PSTORE opcode
   gVar( _AR()\i )\i = gVar( sp )\i

   pc + 1
EndProcedure

Procedure               C2STORES()
   vm_DebugFunctionName()
   sp - 1

   ; V1.18.0: Direct global access, no intermediate variables for speed
   gVar( _AR()\i )\ss = gVar( sp )\ss

   pc + 1
EndProcedure

Procedure               C2STOREF()
   vm_DebugFunctionName()
   sp - 1

   ; V1.18.0: Direct global access, no intermediate variables for speed
   gVar( _AR()\i )\f = gVar( sp )\f

   pc + 1
EndProcedure

Procedure               C2MOV()
   vm_DebugFunctionName()

   ; V1.022.8: Debug output to trace struct initialization
   CompilerIf #DEBUG
      Debug "MOV: pc=" + Str(pc) + " src[" + Str(_AR()\j) + "]=" + Str(gVar(_AR()\j)\i) + " -> dest[" + Str(_AR()\i) + "]"
   CompilerEndIf

   ; V1.18.0: Direct global access, no intermediate variables for speed
   ; V1.20.27: Pointer metadata now handled by C2PMOV opcode
   gVar( _AR()\i )\i = gVar( _AR()\j )\i

   pc + 1
EndProcedure

Procedure               C2MOVS()
   vm_DebugFunctionName()

   ; V1.18.0: Direct global access, no intermediate variables for speed
   gVar( _AR()\i )\ss = gVar( _AR()\j )\ss

   pc + 1
EndProcedure

Procedure               C2MOVF()
   vm_DebugFunctionName()

   ; V1.18.0: Direct global access, no intermediate variables for speed
   gVar( _AR()\i )\f = gVar( _AR()\j )\f

   pc + 1
EndProcedure

;- Local Variable Opcodes (V1.18.0: Use unified gVar[] with localSlotStart, no intermediate vars for speed)
Procedure               C2LMOV()
   vm_DebugFunctionName()
   ; V1.18.0: Direct access to gVar[localSlotStart + offset]
   gVar( gStack(gStackDepth)\localSlotStart + _AR()\i )\i = gVar( _AR()\j )\i
   pc + 1
EndProcedure

Procedure               C2LMOVS()
   vm_DebugFunctionName()
   ; V1.18.0: Direct access to gVar[localSlotStart + offset]
   gVar( gStack(gStackDepth)\localSlotStart + _AR()\i )\ss = gVar( _AR()\j )\ss
   pc + 1
EndProcedure

Procedure               C2LMOVF()
   vm_DebugFunctionName()
   ; V1.18.0: Direct access to gVar[localSlotStart + offset]
   gVar( gStack(gStackDepth)\localSlotStart + _AR()\i )\f = gVar( _AR()\j )\f
   pc + 1
EndProcedure

;- V1.022.31: Local-to-Global MOV opcodes (LGMOV)
; Source is local (localSlotStart + j), Destination is global (i)
Procedure               C2LGMOV()
   vm_DebugFunctionName()
   gVar( _AR()\i )\i = gVar( gStack(gStackDepth)\localSlotStart + _AR()\j )\i
   pc + 1
EndProcedure

Procedure               C2LGMOVS()
   vm_DebugFunctionName()
   gVar( _AR()\i )\ss = gVar( gStack(gStackDepth)\localSlotStart + _AR()\j )\ss
   pc + 1
EndProcedure

Procedure               C2LGMOVF()
   vm_DebugFunctionName()
   gVar( _AR()\i )\f = gVar( gStack(gStackDepth)\localSlotStart + _AR()\j )\f
   pc + 1
EndProcedure

;- V1.022.31: Local-to-Local MOV opcodes (LLMOV)
; Both source (j) and destination (i) are local offsets
Procedure               C2LLMOV()
   vm_DebugFunctionName()
   Protected localBase.i = gStack(gStackDepth)\localSlotStart
   gVar( localBase + _AR()\i )\i = gVar( localBase + _AR()\j )\i
   pc + 1
EndProcedure

Procedure               C2LLMOVS()
   vm_DebugFunctionName()
   Protected localBase.i = gStack(gStackDepth)\localSlotStart
   gVar( localBase + _AR()\i )\ss = gVar( localBase + _AR()\j )\ss
   pc + 1
EndProcedure

Procedure               C2LLMOVF()
   vm_DebugFunctionName()
   Protected localBase.i = gStack(gStackDepth)\localSlotStart
   gVar( localBase + _AR()\i )\f = gVar( localBase + _AR()\j )\f
   pc + 1
EndProcedure

Procedure               C2LFETCH()
   vm_DebugFunctionName()
   ; V1.18.0: Fetch from gVar[localSlotStart + offset] to stack
   ; V1.20.27: Pointer metadata now handled by C2PLFETCH opcode
   ; V1.022.102: Inline slot calculation for speed (avoid Protected overhead)
   CompilerIf #DEBUG
      ; V1.022.93: Debug LFETCH at high recursion depth (quicksort debugging)
      If gStackDepth >= 6
         Debug "  LFETCH: depth=" + Str(gStackDepth) + " localStart=" + Str(gStack(gStackDepth)\localSlotStart) + " offset=" + Str(_AR()\i) + " srcSlot=" + Str(gStack(gStackDepth)\localSlotStart + _AR()\i) + " value=" + Str(gVar(gStack(gStackDepth)\localSlotStart + _AR()\i)\i) + " pc=" + Str(pc) + " sp=" + Str(sp)
      EndIf
   CompilerEndIf
   gVar( sp )\i = gVar( gStack(gStackDepth)\localSlotStart + _AR()\i )\i
   sp + 1
   pc + 1
EndProcedure

Procedure               C2LFETCHS()
   vm_DebugFunctionName()
   ; V1.18.0: Fetch string from gVar[localSlotStart + offset] to stack
   gVar( sp )\ss = gVar( gStack(gStackDepth)\localSlotStart + _AR()\i )\ss
   sp + 1
   pc + 1
EndProcedure

Procedure               C2LFETCHF()
   vm_DebugFunctionName()
   ; V1.18.0: Fetch float from gVar[localSlotStart + offset] to stack
   gVar( sp )\f = gVar( gStack(gStackDepth)\localSlotStart + _AR()\i )\f
   sp + 1
   pc + 1
EndProcedure

Procedure               C2LSTORE()
   vm_DebugFunctionName()
   sp - 1
   ; V1.18.0: Store to gVar[localSlotStart + offset] from stack
   ; V1.20.27: Pointer metadata now handled by C2PLSTORE opcode
   ; V1.022.102: Inline slot calculation for speed (avoid Protected overhead)
   CompilerIf #DEBUG
      ; V1.022.101: Add depth check to reduce debug overhead (like LFETCH)
      If gStackDepth >= 6
         Debug "  LSTORE: depth=" + Str(gStackDepth) + " localStart=" + Str(gStack(gStackDepth)\localSlotStart) + " offset=" + Str(_AR()\i) + " dstSlot=" + Str(gStack(gStackDepth)\localSlotStart + _AR()\i) + " value=" + Str(gVar(sp)\i) + " pc=" + Str(pc)
      EndIf
   CompilerEndIf
   gVar( gStack(gStackDepth)\localSlotStart + _AR()\i )\i = gVar( sp )\i
   pc + 1
EndProcedure

Procedure               C2LSTORES()
   vm_DebugFunctionName()
   sp - 1
   ; V1.18.0: Store string to gVar[localSlotStart + offset] from stack
   gVar( gStack(gStackDepth)\localSlotStart + _AR()\i )\ss = gVar( sp )\ss
   pc + 1
EndProcedure

Procedure               C2LSTOREF()
   vm_DebugFunctionName()
   sp - 1
   ; V1.18.0: Store float to gVar[localSlotStart + offset] from stack
   ; V1.022.102: Inline slot calculation for speed (avoid Protected overhead)
   CompilerIf #DEBUG
      ; V1.022.101: Add depth check to reduce debug overhead (StrF is expensive)
      If gStackDepth >= 6
         Debug "  LSTOREF: depth=" + Str(gStackDepth) + " localStart=" + Str(gStack(gStackDepth)\localSlotStart) + " offset=" + Str(_AR()\i) + " dstSlot=" + Str(gStack(gStackDepth)\localSlotStart + _AR()\i) + " value=" + StrF(gVar(sp)\f, 2) + " pc=" + Str(pc)
      EndIf
   CompilerEndIf
   gVar( gStack(gStackDepth)\localSlotStart + _AR()\i )\f = gVar( sp )\f
   pc + 1
EndProcedure

;- In-place increment/decrement operations (efficient, no multi-operation sequences)

Procedure               C2INC_VAR()
   ; Increment global variable in place (no stack operation)
   vm_DebugFunctionName()
   gVar(_AR()\i)\i + 1
   pc + 1
EndProcedure

Procedure               C2DEC_VAR()
   ; Decrement global variable in place (no stack operation)
   vm_DebugFunctionName()
   gVar(_AR()\i)\i - 1
   pc + 1
EndProcedure

Procedure               C2INC_VAR_PRE()
   ; Pre-increment global: increment and push new value
   vm_DebugFunctionName()
   gVar(_AR()\i)\i + 1
   gVar(sp)\i = gVar(_AR()\i)\i
   sp + 1
   pc + 1
EndProcedure

Procedure               C2DEC_VAR_PRE()
   ; Pre-decrement global: decrement and push new value
   vm_DebugFunctionName()
   gVar(_AR()\i)\i - 1
   gVar(sp)\i = gVar(_AR()\i)\i
   sp + 1
   pc + 1
EndProcedure

Procedure               C2INC_VAR_POST()
   ; Post-increment global: push old value and increment
   vm_DebugFunctionName()
   gVar(sp)\i = gVar(_AR()\i)\i
   gVar(_AR()\i)\i + 1
   sp + 1
   pc + 1
EndProcedure

Procedure               C2DEC_VAR_POST()
   ; Post-decrement global: push old value and decrement
   vm_DebugFunctionName()
   gVar(sp)\i = gVar(_AR()\i)\i
   gVar(_AR()\i)\i - 1
   sp + 1
   pc + 1
EndProcedure

Procedure               C2LINC_VAR()
   ; V1.18.0: Increment local in gVar[localSlotStart + offset], no intermediate vars
   vm_DebugFunctionName()
   gVar( gStack(gStackDepth)\localSlotStart + _AR()\i )\i + 1
   pc + 1
EndProcedure

Procedure               C2LDEC_VAR()
   ; V1.18.0: Decrement local in gVar[localSlotStart + offset], no intermediate vars
   vm_DebugFunctionName()
   gVar( gStack(gStackDepth)\localSlotStart + _AR()\i )\i - 1
   pc + 1
EndProcedure

Procedure               C2LINC_VAR_PRE()
   ; V1.18.0: Pre-increment local and push
   vm_DebugFunctionName()
   gVar( gStack(gStackDepth)\localSlotStart + _AR()\i )\i + 1
   gVar(sp)\i = gVar( gStack(gStackDepth)\localSlotStart + _AR()\i )\i
   sp + 1
   pc + 1
EndProcedure

Procedure               C2LDEC_VAR_PRE()
   ; V1.18.0: Pre-decrement local and push
   vm_DebugFunctionName()
   gVar( gStack(gStackDepth)\localSlotStart + _AR()\i )\i - 1
   gVar(sp)\i = gVar( gStack(gStackDepth)\localSlotStart + _AR()\i )\i
   sp + 1
   pc + 1
EndProcedure

Procedure               C2LINC_VAR_POST()
   ; V1.18.0: Push old value then increment local
   vm_DebugFunctionName()
   gVar(sp)\i = gVar( gStack(gStackDepth)\localSlotStart + _AR()\i )\i
   gVar( gStack(gStackDepth)\localSlotStart + _AR()\i )\i + 1
   sp + 1
   pc + 1
EndProcedure

Procedure               C2LDEC_VAR_POST()
   ; V1.18.0: Push old value then decrement local
   vm_DebugFunctionName()
   gVar(sp)\i = gVar( gStack(gStackDepth)\localSlotStart + _AR()\i )\i
   gVar( gStack(gStackDepth)\localSlotStart + _AR()\i )\i - 1
   sp + 1
   pc + 1
EndProcedure

;- In-place compound assignment operations (pop stack, operate, store - no push)

Procedure               C2ADD_ASSIGN_VAR()
   ; Pop value from stack, add to variable, store back (no push)
   vm_DebugFunctionName()
   sp - 1
   gVar(_AR()\i)\i + gVar(sp)\i
   pc + 1
EndProcedure

Procedure               C2SUB_ASSIGN_VAR()
   ; Pop value from stack, subtract from variable, store back (no push)
   vm_DebugFunctionName()
   sp - 1
   gVar(_AR()\i)\i - gVar(sp)\i
   pc + 1
EndProcedure

Procedure               C2MUL_ASSIGN_VAR()
   ; Pop value from stack, multiply variable, store back (no push)
   vm_DebugFunctionName()
   sp - 1
   gVar(_AR()\i)\i * gVar(sp)\i
   pc + 1
EndProcedure

Procedure               C2DIV_ASSIGN_VAR()
   ; Pop value from stack, divide variable, store back (no push)
   vm_DebugFunctionName()
   sp - 1
   gVar(_AR()\i)\i / gVar(sp)\i
   pc + 1
EndProcedure

Procedure               C2MOD_ASSIGN_VAR()
   ; Pop value from stack, modulo variable, store back (no push)
   vm_DebugFunctionName()
   sp - 1
   gVar(_AR()\i)\i % gVar(sp)\i
   pc + 1
EndProcedure

Procedure               C2FLOATADD_ASSIGN_VAR()
   ; Pop value from stack, float add to variable, store back (no push)
   vm_DebugFunctionName()
   sp - 1
   gVar(_AR()\i)\f + gVar(sp)\f
   pc + 1
EndProcedure

Procedure               C2FLOATSUB_ASSIGN_VAR()
   ; Pop value from stack, float subtract from variable, store back (no push)
   vm_DebugFunctionName()
   sp - 1
   gVar(_AR()\i)\f - gVar(sp)\f
   pc + 1
EndProcedure

Procedure               C2FLOATMUL_ASSIGN_VAR()
   ; Pop value from stack, float multiply variable, store back (no push)
   vm_DebugFunctionName()
   sp - 1
   gVar(_AR()\i)\f * gVar(sp)\f
   pc + 1
EndProcedure

Procedure               C2FLOATDIV_ASSIGN_VAR()
   ; Pop value from stack, float divide variable, store back (no push)
   vm_DebugFunctionName()
   sp - 1
   gVar(_AR()\i)\f / gVar(sp)\f
   pc + 1
EndProcedure

Procedure               C2JMP()
   vm_DebugFunctionName()
   pc + _AR()\i
EndProcedure

Procedure               C2JZ()
   vm_DebugFunctionName()
   sp - 1
   CompilerIf #DEBUG
      ; V1.020.094: Debug JZ at high recursion depth (quicksort debugging)
      ; V1.022.93: Removed PC range restriction
      If gStackDepth >= 6
         Debug "C2JZ: pc=" + Str(pc) + " sp=" + Str(sp) + " value=" + Str(gVar(sp)\i) + " offset=" + Str(_AR()\i) + " depth=" + Str(gStackDepth)
      EndIf
   CompilerEndIf
   If Not gVar(sp)\i
      CompilerIf #DEBUG
         If gStackDepth >= 6
            Debug "  → JUMPING to pc=" + Str(pc + _AR()\i)
         EndIf
      CompilerEndIf
      pc + _AR()\i
   Else
      CompilerIf #DEBUG
         If gStackDepth >= 6
            Debug "  → NOT jumping, continuing to pc=" + Str(pc + 1)
         EndIf
      CompilerEndIf
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

; V1.024.0: New opcodes for switch statement support
Procedure               C2DUP()
   ; Duplicate top of stack (all fields - generic, slower)
   vm_DebugFunctionName()
   gVar(sp)\i = gVar(sp - 1)\i
   gVar(sp)\f = gVar(sp - 1)\f
   gVar(sp)\ss = gVar(sp - 1)\ss
   sp + 1
   pc + 1
EndProcedure

; V1.024.4: Typed DUP opcodes for speed
Procedure               C2DUP_I()
   ; Duplicate integer (also pointers, arrays, structs)
   vm_DebugFunctionName()
   gVar(sp)\i = gVar(sp - 1)\i
   sp + 1
   pc + 1
EndProcedure

Procedure               C2DUP_F()
   ; Duplicate float
   vm_DebugFunctionName()
   gVar(sp)\f = gVar(sp - 1)\f
   sp + 1
   pc + 1
EndProcedure

Procedure               C2DUP_S()
   ; Duplicate string
   vm_DebugFunctionName()
   gVar(sp)\ss = gVar(sp - 1)\ss
   sp + 1
   pc + 1
EndProcedure

Procedure               C2JNZ()
   ; Jump if Not Zero (opposite of JZ)
   vm_DebugFunctionName()
   sp - 1
   If gVar(sp)\i
      pc + _AR()\i
   Else
      pc + 1
   EndIf
EndProcedure

; V1.024.6: DROP - discard top of stack without storing
Procedure               C2DROP()
   vm_DebugFunctionName()
   sp - 1
   pc + 1
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
   ; V1.18.63.10: Clear pointer metadata (value is now a float, not a pointer)
   gVar(sp - 1)\ptr = 0
   gVar(sp - 1)\ptrtype = 0
   pc + 1
EndProcedure

Procedure               C2FTOI_ROUND()
   vm_DebugFunctionName()
   ; Convert float to integer at stack top (round to nearest)
   gVar(sp - 1)\i = gVar(sp - 1)\f
   pc + 1
EndProcedure

Procedure               C2FTOI_TRUNCATE()
   vm_DebugFunctionName()
   ; Convert float to integer at stack top (truncate towards zero)
   gVar(sp - 1)\i = Int(gVar(sp - 1)\f)
   pc + 1
EndProcedure

Procedure               C2STOF()
   vm_DebugFunctionName()
   ; Convert string to float at stack top
   gVar(sp - 1)\f = ValD(gVar(sp - 1)\ss)
   pc + 1
EndProcedure

Procedure               C2STOI()
   vm_DebugFunctionName()
   ; Convert string to integer at stack top
   gVar(sp - 1)\i = Val(gVar(sp - 1)\ss)
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

; V1.023.30: String comparison - compare \ss string fields
Procedure               C2STREQ()
   vm_DebugFunctionName()
   sp - 1
   If gVar(sp-1)\ss = gVar(sp)\ss
      gVar(sp-1)\i = 1
   Else
      gVar(sp-1)\i = 0
   EndIf
   pc + 1
EndProcedure

Procedure               C2STRNE()
   vm_DebugFunctionName()
   sp - 1
   If gVar(sp-1)\ss <> gVar(sp)\ss
      gVar(sp-1)\i = 1
   Else
      gVar(sp-1)\i = 0
   EndIf
   pc + 1
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

Procedure               C2PRTPTR()
   ; Print value after generic pointer dereference
   ; Examines ptrtype field to determine which field to print
   vm_DebugFunctionName()
   sp - 1

   Select gVar(sp)\ptrtype
      Case #PTR_INT, #PTR_ARRAY_INT
         CompilerIf #PB_Compiler_ExecutableFormat = #PB_Compiler_Console
            gBatchOutput + Str( gVar( sp )\i )
            Print(Str( gVar( sp )\i ))
         CompilerElse
            cline = cline + Str( gVar( sp )\i )
            If gFastPrint = #False
               SetGadgetItemText( #edConsole, cy, cline )
            EndIf
         CompilerEndIf

      Case #PTR_FLOAT, #PTR_ARRAY_FLOAT
         CompilerIf #PB_Compiler_ExecutableFormat = #PB_Compiler_Console
            gBatchOutput + StrD( gVar(sp)\f, gDecs )
            Print(StrD( gVar(sp)\f, gDecs ))
         CompilerElse
            cline = cline + StrD( gVar(sp)\f, gDecs )
            If gFastPrint = #False
               SetGadgetItemText( #edConsole, cy, cline )
            EndIf
         CompilerEndIf

      Case #PTR_STRING, #PTR_ARRAY_STRING
         CompilerIf #PB_Compiler_ExecutableFormat = #PB_Compiler_Console
            gBatchOutput + gVar(sp)\ss
            Print(gVar(sp)\ss)
         CompilerElse
            cline = cline + gVar(sp)\ss
            If gFastPrint = #False
               SetGadgetItemText( #edConsole, cy, cline )
            EndIf
         CompilerEndIf

      Default
         CompilerIf #DEBUG
            Debug "Invalid pointer type in PRTPTR: " + Str(gVar(sp)\ptrtype) + " at pc=" + Str(pc)
         CompilerEndIf
   EndSelect

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
   Protected localSlotStart.l, arrayOffset.l, actualSlot.l, swapIdx.l
   ; V1.022.37: Temp storage for in-place swap (needed because localSlotStart == paramSp)
   Protected tempI.i, tempF.d, tempS.s, tempPtr, tempPtrType.w
   ; V1.023.0: Variables for function template preloading
   Protected templateCount.l, dstStart.l

   ; Read nParams, nLocals, and nLocalArrays from instruction fields
   nParams = _AR()\j
   nLocals = _AR()\n
   nLocalArrays = _AR()\ndx
   totalVars = nParams + nLocals
   pcAddr = _AR()\i  ; PC address for jumping
   funcId = _AR()\funcid  ; Function ID for gFuncLocalArraySlots lookup

   ; V1.18.0 UNIFIED VARIABLE SYSTEM
   ; Allocate gVar[] slots for this function's local variables (params + locals)

   ; Increment stack depth (create new frame)
   gStackDepth = gStackDepth + 1

   If gStackDepth >= gMaxStackDepth
      Debug "*** FATAL ERROR: Stack overflow - max depth " + Str(gMaxStackDepth) + " exceeded at pc=" + Str(pc) + " funcId=" + Str(funcId)
      End
   EndIf

   ; V1.18.0: CRITICAL FIX - Allocate locals starting from parameter position on stack
   ; This prevents overlap with caller's evaluation stack
   ; Parameters are already at (sp - nParams), so start locals there
   localSlotStart = sp - nParams
   gCurrentMaxLocal = localSlotStart + totalVars  ; Reserve slots for this call

   ; Save stack frame info
   gStack(gStackDepth)\pc = pc + 1
   gStack(gStackDepth)\sp = sp - nParams  ; Save sp BEFORE params were pushed
   gStack(gStackDepth)\localSlotStart = localSlotStart
   gStack(gStackDepth)\localSlotCount = totalVars

   CompilerIf #DEBUG
      Debug "C2CALL: depth=" + Str(gStackDepth) + " pcAddr=" + Str(pcAddr) + " nParams=" + Str(nParams) + " sp=" + Str(sp) + " localSlotStart=" + Str(localSlotStart)
   CompilerEndIf

   ; V1.022.37: REVERSE parameters in-place using proper swapping
   ; Since localSlotStart == paramSp (they overlap), we must swap from both ends
   ; Codegen assigns: last declared param → LOCAL[0], first declared → LOCAL[N-1]
   ; Caller pushes in declaration order, so stack has: first @ localSlotStart, last @ localSlotStart+N-1
   ; After reverse: LOCAL[0] = last pushed, LOCAL[N-1] = first pushed
   If nParams > 1
      ; Swap from both ends toward middle (only need nParams/2 swaps)
      For i = 0 To (nParams / 2) - 1
         swapIdx = nParams - 1 - i
         ; Save slot i to temp
         tempI = gVar(localSlotStart + i)\i
         tempF = gVar(localSlotStart + i)\f
         tempS = gVar(localSlotStart + i)\ss
         tempPtr = gVar(localSlotStart + i)\ptr
         tempPtrType = gVar(localSlotStart + i)\ptrtype
         ; Copy slot swapIdx to slot i
         gVar(localSlotStart + i)\i = gVar(localSlotStart + swapIdx)\i
         gVar(localSlotStart + i)\f = gVar(localSlotStart + swapIdx)\f
         gVar(localSlotStart + i)\ss = gVar(localSlotStart + swapIdx)\ss
         gVar(localSlotStart + i)\ptr = gVar(localSlotStart + swapIdx)\ptr
         gVar(localSlotStart + i)\ptrtype = gVar(localSlotStart + swapIdx)\ptrtype
         ; Copy temp to slot swapIdx
         gVar(localSlotStart + swapIdx)\i = tempI
         gVar(localSlotStart + swapIdx)\f = tempF
         gVar(localSlotStart + swapIdx)\ss = tempS
         gVar(localSlotStart + swapIdx)\ptr = tempPtr
         gVar(localSlotStart + swapIdx)\ptrtype = tempPtrType
         CompilerIf #DEBUG
            Debug "  Swap Param[" + Str(i) + "] <-> Param[" + Str(swapIdx) + "]"
         CompilerEndIf
      Next
   EndIf

   CompilerIf #DEBUG
      ; V1.022.93: Show parameters after swap for quicksort debugging (3 params at depth 6+)
      If nParams = 3 And gStackDepth >= 6
         Debug "  Params after swap: LOCAL[0]=" + Str(gVar(localSlotStart+0)\i) + " LOCAL[1]=" + Str(gVar(localSlotStart+1)\i) + " LOCAL[2]=" + Str(gVar(localSlotStart+2)\i) + " depth=" + Str(gStackDepth)
      EndIf
   CompilerEndIf

   ; V1.023.0: Preload non-parameter locals from function template
   ; Template covers LOCAL[nParams..totalVars-1] - the actual local variables
   ; Parameters are at LOCAL[0..nParams-1], already set from caller's stack
   ; Templates are indexed by funcId directly (wastes a few cells, but faster than subtraction)
   If funcId >= 0 And funcId <= ArraySize(gFuncTemplates())
      templateCount = gFuncTemplates(funcId)\localCount
      If templateCount > 0
         dstStart = localSlotStart + nParams
         For i = 0 To templateCount - 1
            ; Copy template values to local slots AFTER parameters
            gVar(dstStart + i)\i = gFuncTemplates(funcId)\template(i)\i
            gVar(dstStart + i)\f = gFuncTemplates(funcId)\template(i)\f
            gVar(dstStart + i)\ss = gFuncTemplates(funcId)\template(i)\ss
            gVar(dstStart + i)\ptr = gFuncTemplates(funcId)\template(i)\ptr
            gVar(dstStart + i)\ptrtype = gFuncTemplates(funcId)\template(i)\ptrtype
         Next
         CompilerIf #DEBUG
            Debug "  Preloaded " + Str(templateCount) + " locals from template for funcId=" + Str(funcId)
         CompilerEndIf
      EndIf
   EndIf

   ; Allocate local arrays in their respective gVar[] slots
   If nLocalArrays > 0
      CompilerIf #DEBUG
         Debug "  Allocating " + Str(nLocalArrays) + " local arrays, funcId=" + Str(funcId)
      CompilerEndIf
      For i = 0 To nLocalArrays - 1
         varSlot = gFuncLocalArraySlots(funcId, i)
         arrayOffset = gVarMeta(varSlot)\paramOffset  ; Offset within local variables
         actualSlot = localSlotStart + arrayOffset
         arraySize = gVarMeta(varSlot)\arraySize

         CompilerIf #DEBUG
            Debug "  LocalArray[" + Str(i) + "]: varSlot=" + Str(varSlot) + " arrayOffset=" + Str(arrayOffset) + " actualSlot=" + Str(actualSlot) + " arraySize=" + Str(arraySize)
         CompilerEndIf

         If arraySize > 0
            ReDim gVar(actualSlot)\dta\ar(arraySize - 1)
            gVar(actualSlot)\dta\size = arraySize
            CompilerIf #DEBUG
               Debug "    Allocated array at gVar(" + Str(actualSlot) + ") with size " + Str(arraySize)
            CompilerEndIf
         EndIf
      Next
   EndIf

   ; V1.18.0: CRITICAL FIX - Reset sp to start of evaluation stack
   ; This prevents overlap between caller's evaluation stack and callee's local variables
   ; Per UNIFIED_VARIABLE_SYSTEM.md: evaluation stack starts at gCurrentMaxLocal
   sp = gCurrentMaxLocal

   pc = pcAddr  ; Jump to function address
   gFunctionDepth = gFunctionDepth + 1  ; Increment function depth counter

EndProcedure

Procedure               C2Return()
   vm_DebugFunctionName()
   Protected returnValue.i, callerSp.i, i.l
   Protected localSlotStart.l, localSlotCount.l

   ; Initialize to default integer 0 (prevents uninitialized returns)
   returnValue = 0
   callerSp = gStack(gStackDepth)\sp

   ; Save return value from top of stack (sp-1) if there's anything on function's stack
   If sp > callerSp
      returnValue = gVar(sp - 1)\i
      CompilerIf #DEBUG
         Debug "C2Return: sp=" + Str(sp) + " callerSp=" + Str(callerSp) + " returnValue=" + Str(returnValue) + " from gVar(" + Str(sp-1) + ") depth=" + Str(gStackDepth)
      CompilerEndIf
   Else
      CompilerIf #DEBUG
         Debug "C2Return: WARNING! sp=" + Str(sp) + " NOT > callerSp=" + Str(callerSp) + " - using default returnValue=0 depth=" + Str(gStackDepth)
      CompilerEndIf
   EndIf

   ; Restore caller's program counter and stack pointer
   pc = gStack(gStackDepth)\pc
   sp = callerSp

   ; V1.18.0 UNIFIED VARIABLE SYSTEM
   ; Clear local variable slots (only strings and arrays for memory management)
   localSlotStart = gStack(gStackDepth)\localSlotStart
   localSlotCount = gStack(gStackDepth)\localSlotCount

   For i = 0 To localSlotCount - 1
      gVar(localSlotStart + i)\ss = ""  ; MUST clear for PureBasic string garbage collection
      ; Clear array data if present
      If gVar(localSlotStart + i)\dta\size > 0
         ReDim gVar(localSlotStart + i)\dta\ar(0)
         gVar(localSlotStart + i)\dta\size = 0
      EndIf
   Next

   ; Deallocate local slots (restore gCurrentMaxLocal to start of this frame's locals)
   gCurrentMaxLocal = localSlotStart

   ; Delete current stack frame (decrement depth)
   gStackDepth = gStackDepth - 1
   gFunctionDepth = gFunctionDepth - 1  ; Decrement function depth counter

   ; Push return value onto caller's stack
   gVar( sp )\i = returnValue
   sp + 1
EndProcedure

Procedure               C2ReturnF()
   vm_DebugFunctionName()
   Protected returnValue.f, callerSp.i, i.l
   Protected localSlotStart.l, localSlotCount.l

   ; Initialize to default float 0.0
   returnValue = 0.0
   callerSp = gStack(gStackDepth)\sp

   ; Save float return value from top of stack (sp-1) if there's anything on function's stack
   If sp > callerSp
      returnValue = gVar(sp - 1)\f
   EndIf

   ; Restore caller's program counter and stack pointer
   pc = gStack(gStackDepth)\pc
   sp = callerSp

   ; V1.18.0 UNIFIED VARIABLE SYSTEM
   ; Clear local variable slots (only strings and arrays for memory management)
   localSlotStart = gStack(gStackDepth)\localSlotStart
   localSlotCount = gStack(gStackDepth)\localSlotCount

   For i = 0 To localSlotCount - 1
      gVar(localSlotStart + i)\ss = ""  ; MUST clear for PureBasic string garbage collection
      ; Clear array data if present
      If gVar(localSlotStart + i)\dta\size > 0
         ReDim gVar(localSlotStart + i)\dta\ar(0)
         gVar(localSlotStart + i)\dta\size = 0
      EndIf
   Next

   ; Deallocate local slots (restore gCurrentMaxLocal to start of this frame's locals)
   gCurrentMaxLocal = localSlotStart

   ; Delete current stack frame (decrement depth)
   gStackDepth = gStackDepth - 1
   gFunctionDepth = gFunctionDepth - 1  ; Decrement function depth counter

   ; Push float return value onto caller's stack
   gVar( sp )\f = returnValue
   sp + 1
EndProcedure

Procedure               C2ReturnS()
   vm_DebugFunctionName()
   Protected returnValue.s, callerSp.i, i.l
   Protected localSlotStart.l, localSlotCount.l

   ; Initialize to default empty string
   returnValue = ""
   callerSp = gStack(gStackDepth)\sp

   ; Save string return value from top of stack (sp-1) if there's anything on function's stack
   If sp > callerSp
      returnValue = gVar(sp - 1)\ss
   EndIf

   ; Restore caller's program counter and stack pointer
   pc = gStack(gStackDepth)\pc
   sp = callerSp

   ; V1.18.0 UNIFIED VARIABLE SYSTEM
   ; Clear local variable slots (only strings and arrays for memory management)
   localSlotStart = gStack(gStackDepth)\localSlotStart
   localSlotCount = gStack(gStackDepth)\localSlotCount

   For i = 0 To localSlotCount - 1
      gVar(localSlotStart + i)\ss = ""  ; MUST clear for PureBasic string garbage collection
      ; Clear array data if present
      If gVar(localSlotStart + i)\dta\size > 0
         ReDim gVar(localSlotStart + i)\dta\ar(0)
         gVar(localSlotStart + i)\dta\size = 0
      EndIf
   Next

   ; Deallocate local slots (restore gCurrentMaxLocal to start of this frame's locals)
   gCurrentMaxLocal = localSlotStart

   ; Delete current stack frame (decrement depth)
   gStackDepth = gStackDepth - 1
   gFunctionDepth = gFunctionDepth - 1  ; Decrement function depth counter

   ; Push string return value onto caller's stack
   gVar( sp )\ss = returnValue
   sp + 1
EndProcedure


;- Helper procedures (end markers)

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

;- Include Built-in Functions Module
XIncludeFile "c2-builtins-v04.pbi"

;- Include Array Operations Module
XIncludeFile "c2-arrays-v04.pbi"

;- Include Pointer Operations Module
XIncludeFile "c2-pointers-v04.pbi"

;- End VM functions


; IDE Options = PureBasic 6.21 (Windows - x64)
; CursorPosition = 15
; Folding = ------------------
; EnableAsm
; EnableThread
; EnableXP
; CPU = 1
; EnablePurifier
; EnableCompileCount = 0
; EnableBuildCount = 0
; EnableExeConstant