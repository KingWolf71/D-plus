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
; V1.31.0: Push to gEvalStack[] (isolated variable system)
Macro                   vm_PushInt(value)
   gEvalStack(sp)\i = value
   sp + 1
   CompilerIf #DEBUG
      ;If sp % 100 = 0
      ;   Debug "Stack pointer at: " + Str(sp) + " / " + Str(#C2MAXEVALSTACK)
      ;EndIf
   CompilerEndIf
   pc + 1
EndMacro

; Macro for built-in functions: push float result
; V1.31.0: Push to gEvalStack[] (isolated variable system)
Macro                   vm_PushFloat(value)
   gEvalStack(sp)\f = value
   sp + 1
   pc + 1
EndMacro

Macro                   vm_AssertPrint( tmsg )
   CompilerIf #PB_Compiler_ExecutableFormat = #PB_Compiler_Console
      gBatchOutput = gBatchOutput + tmsg + #LF$
      PrintN(tmsg)
   CompilerElse
      ; V1.031.39: Use thread-safe macro for Linux
      vm_SetGadgetText(#edConsole, cy, tmsg)
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
			;*Adjustment = gtk_scrolled_window_get_vadjustment_(gtk_widget_get_parent_(GadgetID(pbGadgetID)))
			;*Adjustment\value = *Adjustment\upper
			;gtk_adjustment_value_changed_(*Adjustment)
	CompilerEndSelect 
EndMacro

;- Jump Table Functions

Procedure               C2FetchPush()
   vm_DebugFunctionName()
   ; V1.31.0: GS - Global to Stack: gVar[slot] -> gEvalStack[sp]
   gEvalStack(sp)\i = gVar(_AR()\i)\i
   sp + 1
   pc + 1
EndProcedure

; V1.026.0: Push slot index (not value) for collection function first parameter
Procedure               C2PUSH_SLOT()
   vm_DebugFunctionName()
   ; Push the slot index itself, not the value at that slot
   ; V1.31.0: Push to gEvalStack[]
   gEvalStack(sp)\i = _AR()\i
   sp + 1
   pc + 1
EndProcedure

Procedure               C2FETCHS()
   vm_DebugFunctionName()
   ; V1.31.0: GS - Global to Stack: gVar[slot].ss -> gEvalStack[sp].ss
   gEvalStack(sp)\ss = gVar(_AR()\i)\ss
   sp + 1
   pc + 1
EndProcedure

Procedure               C2FETCHF()
   vm_DebugFunctionName()
   ; V1.31.0: GS - Global to Stack: gVar[slot].f -> gEvalStack[sp].f
   gEvalStack(sp)\f = gVar(_AR()\i)\f
   sp + 1
   pc + 1
EndProcedure

Procedure               C2POP()
   vm_DebugFunctionName()
   sp - 1
   ; V1.31.0: SG - Stack to Global: gEvalStack[sp] -> gVar[slot]
   gVar(_AR()\i)\i = gEvalStack(sp)\i
   pc + 1
EndProcedure

Procedure               C2POPS()
   vm_DebugFunctionName()
   sp - 1
   ; V1.31.0: SG - Stack to Global: gEvalStack[sp].ss -> gVar[slot].ss
   gVar(_AR()\i)\ss = gEvalStack(sp)\ss
   pc + 1
EndProcedure

Procedure               C2POPF()
   vm_DebugFunctionName()
   sp - 1
   ; V1.31.0: SG - Stack to Global: gEvalStack[sp].f -> gVar[slot].f
   gVar(_AR()\i)\f = gEvalStack(sp)\f
   pc + 1
EndProcedure

Procedure               C2PUSHS()
   vm_DebugFunctionName()
   ; V1.31.0: GS - Global to Stack: gVar[slot].ss -> gEvalStack[sp].ss
   gEvalStack(sp)\ss = gVar(_AR()\i)\ss
   sp + 1
   pc + 1
EndProcedure

Procedure               C2PUSHF()
   vm_DebugFunctionName()
   ; V1.31.0: GS - Global to Stack: gVar[slot].f -> gEvalStack[sp].f
   gEvalStack(sp)\f = gVar(_AR()\i)\f
   sp + 1
   pc + 1
EndProcedure

Procedure               C2Store()
   vm_DebugFunctionName()
   sp - 1
   ; V1.31.0: SG - Stack to Global: gEvalStack[sp] -> gVar[slot]
   gVar(_AR()\i)\i = gEvalStack(sp)\i
   pc + 1
EndProcedure

Procedure               C2STORES()
   vm_DebugFunctionName()
   sp - 1
   ; V1.31.0: SG - Stack to Global: gEvalStack[sp].ss -> gVar[slot].ss
   gVar(_AR()\i)\ss = gEvalStack(sp)\ss
   pc + 1
EndProcedure

Procedure               C2STOREF()
   vm_DebugFunctionName()
   sp - 1
   ; V1.31.0: SG - Stack to Global: gEvalStack[sp].f -> gVar[slot].f
   gVar(_AR()\i)\f = gEvalStack(sp)\f
   pc + 1
EndProcedure

; V1.029.84: Store to struct variable - copies both \i and \ptr
; This fixes the issue where regular STORE only copies \i but StructGetStr accesses \ptr
; The stVT structure has separate \i and \ptr fields (not a union)
; Used when storing function return values to struct variables: p.Person = listGet(...)
; V1.31.0: Read from gEvalStack[] (isolated variable system)
Procedure               C2STORE_STRUCT()
   vm_DebugFunctionName()
   sp - 1

   ; Copy both integer value AND pointer field (since they're separate in stVT)
   gVar( _AR()\i )\i = gEvalStack(sp)\i
   gVar( _AR()\i )\ptr = gEvalStack(sp)\i  ; Copy \i to \ptr for pointer semantics

   pc + 1
EndProcedure

; V1.031.32: Local variant of STORE_STRUCT - stores to gLocal[offset] instead of gVar[]
; Used for local struct variables inside functions: p.Person = listGet(...)
Procedure               C2LSTORE_STRUCT()
   vm_DebugFunctionName()
   sp - 1

   ; Copy both integer value AND pointer field to local variable
   gLocal( _AR()\i )\i = gEvalStack(sp)\i
   gLocal( _AR()\i )\ptr = gEvalStack(sp)\i

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

;- V1.31.0: Local Variable Opcodes (Isolated Variable System)
;  LMOV (GL - Global to Local): gVar[j] -> gLocal[gLocalBase + i]
;  LGMOV (LG - Local to Global): gLocal[gLocalBase + j] -> gVar[i]
;  LLMOV (LL - Local to Local): gLocal[gLocalBase + j] -> gLocal[gLocalBase + i]

Procedure               C2LMOV()
   vm_DebugFunctionName()
   ; V1.31.0: GL - Global to Local: gVar[j] -> gLocal[gLocalBase + i]
   gLocal(gLocalBase + _AR()\i)\i = gVar(_AR()\j)\i
   pc + 1
EndProcedure

Procedure               C2LMOVS()
   vm_DebugFunctionName()
   ; V1.31.0: GL - Global to Local: gVar[j] -> gLocal[gLocalBase + i]
   gLocal(gLocalBase + _AR()\i)\ss = gVar(_AR()\j)\ss
   pc + 1
EndProcedure

Procedure               C2LMOVF()
   vm_DebugFunctionName()
   ; V1.31.0: GL - Global to Local: gVar[j] -> gLocal[gLocalBase + i]
   gLocal(gLocalBase + _AR()\i)\f = gVar(_AR()\j)\f
   pc + 1
EndProcedure

;- V1.31.0: Local-to-Global MOV opcodes (LGMOV - LG)
Procedure               C2LGMOV()
   vm_DebugFunctionName()
   ; V1.31.0: LG - Local to Global: gLocal[gLocalBase + j] -> gVar[i]
   gVar(_AR()\i)\i = gLocal(gLocalBase + _AR()\j)\i
   pc + 1
EndProcedure

Procedure               C2LGMOVS()
   vm_DebugFunctionName()
   ; V1.31.0: LG - Local to Global: gLocal[gLocalBase + j] -> gVar[i]
   gVar(_AR()\i)\ss = gLocal(gLocalBase + _AR()\j)\ss
   pc + 1
EndProcedure

Procedure               C2LGMOVF()
   vm_DebugFunctionName()
   ; V1.31.0: LG - Local to Global: gLocal[gLocalBase + j] -> gVar[i]
   gVar(_AR()\i)\f = gLocal(gLocalBase + _AR()\j)\f
   pc + 1
EndProcedure

;- V1.31.0: Local-to-Local MOV opcodes (LLMOV - LL)
Procedure               C2LLMOV()
   vm_DebugFunctionName()
   ; V1.31.0: LL - Local to Local: gLocal[gLocalBase + j] -> gLocal[gLocalBase + i]
   gLocal(gLocalBase + _AR()\i)\i = gLocal(gLocalBase + _AR()\j)\i
   pc + 1
EndProcedure

Procedure               C2LLMOVS()
   vm_DebugFunctionName()
   ; V1.31.0: LL - Local to Local: gLocal[gLocalBase + j] -> gLocal[gLocalBase + i]
   gLocal(gLocalBase + _AR()\i)\ss = gLocal(gLocalBase + _AR()\j)\ss
   pc + 1
EndProcedure

Procedure               C2LLMOVF()
   vm_DebugFunctionName()
   ; V1.31.0: LL - Local to Local: gLocal[gLocalBase + j] -> gLocal[gLocalBase + i]
   gLocal(gLocalBase + _AR()\i)\f = gLocal(gLocalBase + _AR()\j)\f
   pc + 1
EndProcedure

Procedure               C2LFETCH()
   vm_DebugFunctionName()
   ; V1.31.0: Fetch from gLocal[gLocalBase + offset] to gEvalStack[]
   CompilerIf #DEBUG
      If gStackDepth >= 6
         Debug "  LFETCH: depth=" + Str(gStackDepth) + " gLocalBase=" + Str(gLocalBase) + " offset=" + Str(_AR()\i) + " value=" + Str(gLocal(gLocalBase + _AR()\i)\i) + " pc=" + Str(pc) + " sp=" + Str(sp)
      EndIf
   CompilerEndIf
   gEvalStack(sp)\i = gLocal(gLocalBase + _AR()\i)\i
   sp + 1
   pc + 1
EndProcedure

Procedure               C2LFETCHS()
   vm_DebugFunctionName()
   ; V1.31.0: Fetch string from gLocal[gLocalBase + offset] to gEvalStack[]
   gEvalStack(sp)\ss = gLocal(gLocalBase + _AR()\i)\ss
   sp + 1
   pc + 1
EndProcedure

Procedure               C2LFETCHF()
   vm_DebugFunctionName()
   ; V1.31.0: Fetch float from gLocal[gLocalBase + offset] to gEvalStack[]
   CompilerIf #DEBUG
      Debug "VM LFETCHF: sp=" + Str(sp) + " gLocalBase=" + Str(gLocalBase) + " offset=" + Str(_AR()\i) + " floatVal=" + StrD(gLocal(gLocalBase + _AR()\i)\f)
   CompilerEndIf
   gEvalStack(sp)\f = gLocal(gLocalBase + _AR()\i)\f
   sp + 1
   pc + 1
EndProcedure

Procedure               C2LSTORE()
   vm_DebugFunctionName()
   sp - 1
   ; V1.31.0: Store to gLocal[gLocalBase + offset] from gEvalStack[]
   ; V1.031.27: Added bounds checking to diagnose array index errors
   Protected localIdx.i = gLocalBase + _AR()\i
   If sp < 0 Or sp >= #C2MAXEVALSTACK
      Debug "*** LSTORE ERROR: sp=" + Str(sp) + " out of bounds [0.." + Str(#C2MAXEVALSTACK-1) + "] at pc=" + Str(pc)
      gExitApplication = #True
      ProcedureReturn
   EndIf
   If localIdx < 0 Or localIdx >= #C2MAXLOCALS
      Debug "*** LSTORE ERROR: gLocal index=" + Str(localIdx) + " (gLocalBase=" + Str(gLocalBase) + " offset=" + Str(_AR()\i) + ") out of bounds [0.." + Str(#C2MAXLOCALS-1) + "] at pc=" + Str(pc)
      gExitApplication = #True
      ProcedureReturn
   EndIf
   CompilerIf #DEBUG
      Debug "VM LSTORE: gLocalBase=" + Str(gLocalBase) + " offset=" + Str(_AR()\i) + " value=" + Str(gEvalStack(sp)\i)
   CompilerEndIf
   gLocal(localIdx)\i = gEvalStack(sp)\i
   pc + 1
EndProcedure

Procedure               C2LSTORES()
   vm_DebugFunctionName()
   sp - 1
   ; V1.31.0: Store string to gLocal[gLocalBase + offset] from gEvalStack[]
   ; V1.031.27: Added bounds checking
   Protected localIdx.i = gLocalBase + _AR()\i
   If sp < 0 Or sp >= #C2MAXEVALSTACK
      Debug "*** LSTORES ERROR: sp=" + Str(sp) + " out of bounds at pc=" + Str(pc)
      gExitApplication = #True
      ProcedureReturn
   EndIf
   If localIdx < 0 Or localIdx >= #C2MAXLOCALS
      Debug "*** LSTORES ERROR: gLocal index=" + Str(localIdx) + " out of bounds at pc=" + Str(pc)
      gExitApplication = #True
      ProcedureReturn
   EndIf
   gLocal(localIdx)\ss = gEvalStack(sp)\ss
   pc + 1
EndProcedure

Procedure               C2LSTOREF()
   vm_DebugFunctionName()
   sp - 1
   ; V1.31.0: Store float to gLocal[gLocalBase + offset] from gEvalStack[]
   ; V1.031.27: Added bounds checking
   Protected localIdx.i = gLocalBase + _AR()\i
   If sp < 0 Or sp >= #C2MAXEVALSTACK
      Debug "*** LSTOREF ERROR: sp=" + Str(sp) + " out of bounds at pc=" + Str(pc)
      gExitApplication = #True
      ProcedureReturn
   EndIf
   If localIdx < 0 Or localIdx >= #C2MAXLOCALS
      Debug "*** LSTOREF ERROR: gLocal index=" + Str(localIdx) + " out of bounds at pc=" + Str(pc)
      gExitApplication = #True
      ProcedureReturn
   EndIf
   CompilerIf #DEBUG
      Debug "VM LSTOREF: sp=" + Str(sp) + " gLocalBase=" + Str(gLocalBase) + " offset=" + Str(_AR()\i) + " value=" + StrD(gEvalStack(sp)\f)
   CompilerEndIf
   gLocal(localIdx)\f = gEvalStack(sp)\f
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
   ; V1.31.0: Pre-increment global: increment and push new value to gEvalStack[]
   vm_DebugFunctionName()
   gVar(_AR()\i)\i + 1
   gEvalStack(sp)\i = gVar(_AR()\i)\i
   sp + 1
   pc + 1
EndProcedure

Procedure               C2DEC_VAR_PRE()
   ; V1.31.0: Pre-decrement global: decrement and push new value to gEvalStack[]
   vm_DebugFunctionName()
   gVar(_AR()\i)\i - 1
   gEvalStack(sp)\i = gVar(_AR()\i)\i
   sp + 1
   pc + 1
EndProcedure

Procedure               C2INC_VAR_POST()
   ; V1.31.0: Post-increment global: push old value to gEvalStack[] and increment
   vm_DebugFunctionName()
   gEvalStack(sp)\i = gVar(_AR()\i)\i
   gVar(_AR()\i)\i + 1
   sp + 1
   pc + 1
EndProcedure

Procedure               C2DEC_VAR_POST()
   ; V1.31.0: Post-decrement global: push old value to gEvalStack[] and decrement
   vm_DebugFunctionName()
   gEvalStack(sp)\i = gVar(_AR()\i)\i
   gVar(_AR()\i)\i - 1
   sp + 1
   pc + 1
EndProcedure

Procedure               C2LINC_VAR()
   ; V1.31.0: Increment local in gLocal[gLocalBase + offset]
   vm_DebugFunctionName()
   gLocal(gLocalBase + _AR()\i)\i + 1
   pc + 1
EndProcedure

Procedure               C2LDEC_VAR()
   ; V1.31.0: Decrement local in gLocal[gLocalBase + offset]
   vm_DebugFunctionName()
   gLocal(gLocalBase + _AR()\i)\i - 1
   pc + 1
EndProcedure

Procedure               C2LINC_VAR_PRE()
   ; V1.31.0: Pre-increment local and push to gEvalStack[]
   vm_DebugFunctionName()
   gLocal(gLocalBase + _AR()\i)\i + 1
   gEvalStack(sp)\i = gLocal(gLocalBase + _AR()\i)\i
   sp + 1
   pc + 1
EndProcedure

Procedure               C2LDEC_VAR_PRE()
   ; V1.31.0: Pre-decrement local and push to gEvalStack[]
   vm_DebugFunctionName()
   gLocal(gLocalBase + _AR()\i)\i - 1
   gEvalStack(sp)\i = gLocal(gLocalBase + _AR()\i)\i
   sp + 1
   pc + 1
EndProcedure

Procedure               C2LINC_VAR_POST()
   ; V1.31.0: Push old value to gEvalStack[] then increment local
   vm_DebugFunctionName()
   gEvalStack(sp)\i = gLocal(gLocalBase + _AR()\i)\i
   gLocal(gLocalBase + _AR()\i)\i + 1
   sp + 1
   pc + 1
EndProcedure

Procedure               C2LDEC_VAR_POST()
   ; V1.31.0: Push old value to gEvalStack[] then decrement local
   vm_DebugFunctionName()
   gEvalStack(sp)\i = gLocal(gLocalBase + _AR()\i)\i
   gLocal(gLocalBase + _AR()\i)\i - 1
   sp + 1
   pc + 1
EndProcedure

;- In-place compound assignment operations (pop stack, operate, store - no push)

Procedure               C2ADD_ASSIGN_VAR()
   ; V1.31.0: Pop value from gEvalStack[], add to global, store back (no push)
   vm_DebugFunctionName()
   sp - 1
   gVar(_AR()\i)\i + gEvalStack(sp)\i
   pc + 1
EndProcedure

Procedure               C2SUB_ASSIGN_VAR()
   ; V1.31.0: Pop value from gEvalStack[], subtract from global, store back (no push)
   vm_DebugFunctionName()
   sp - 1
   gVar(_AR()\i)\i - gEvalStack(sp)\i
   pc + 1
EndProcedure

Procedure               C2MUL_ASSIGN_VAR()
   ; V1.31.0: Pop value from gEvalStack[], multiply global, store back (no push)
   vm_DebugFunctionName()
   sp - 1
   gVar(_AR()\i)\i * gEvalStack(sp)\i
   pc + 1
EndProcedure

Procedure               C2DIV_ASSIGN_VAR()
   ; V1.31.0: Pop value from gEvalStack[], divide global, store back (no push)
   vm_DebugFunctionName()
   sp - 1
   gVar(_AR()\i)\i / gEvalStack(sp)\i
   pc + 1
EndProcedure

Procedure               C2MOD_ASSIGN_VAR()
   ; V1.31.0: Pop value from gEvalStack[], modulo global, store back (no push)
   vm_DebugFunctionName()
   sp - 1
   gVar(_AR()\i)\i % gEvalStack(sp)\i
   pc + 1
EndProcedure

Procedure               C2FLOATADD_ASSIGN_VAR()
   ; V1.31.0: Pop value from gEvalStack[], float add to global, store back (no push)
   vm_DebugFunctionName()
   sp - 1
   gVar(_AR()\i)\f + gEvalStack(sp)\f
   pc + 1
EndProcedure

Procedure               C2FLOATSUB_ASSIGN_VAR()
   ; V1.31.0: Pop value from gEvalStack[], float subtract from global, store back (no push)
   vm_DebugFunctionName()
   sp - 1
   gVar(_AR()\i)\f - gEvalStack(sp)\f
   pc + 1
EndProcedure

Procedure               C2FLOATMUL_ASSIGN_VAR()
   ; V1.31.0: Pop value from gEvalStack[], float multiply global, store back (no push)
   vm_DebugFunctionName()
   sp - 1
   gVar(_AR()\i)\f * gEvalStack(sp)\f
   pc + 1
EndProcedure

Procedure               C2FLOATDIV_ASSIGN_VAR()
   ; V1.31.0: Pop value from gEvalStack[], float divide global, store back (no push)
   vm_DebugFunctionName()
   sp - 1
   gVar(_AR()\i)\f / gEvalStack(sp)\f
   pc + 1
EndProcedure

Procedure               C2JMP()
   vm_DebugFunctionName()
   pc + _AR()\i
EndProcedure

Procedure               C2JZ()
   vm_DebugFunctionName()
   sp - 1
   ; V1.31.0: Read from gEvalStack[]
   CompilerIf #DEBUG
      If gStackDepth >= 6
         Debug "C2JZ: pc=" + Str(pc) + " sp=" + Str(sp) + " value=" + Str(gEvalStack(sp)\i) + " offset=" + Str(_AR()\i) + " depth=" + Str(gStackDepth)
      EndIf
   CompilerEndIf
   If Not gEvalStack(sp)\i
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
   ; V1.31.0: Ternary IF - use gEvalStack[]
   vm_DebugFunctionName()
   sp - 1
   If Not gEvalStack(sp)\i
      pc + _AR()\i
   Else
      pc + 1
   EndIf
EndProcedure

Procedure               C2TENELSE()
   ; Ternary ELSE: Unconditional jump past false branch
   vm_DebugFunctionName()
   pc + _AR()\i
EndProcedure

; V1.024.0: New opcodes for switch statement support
; V1.31.0: Updated for gEvalStack[]
Procedure               C2DUP()
   vm_DebugFunctionName()
   gEvalStack(sp)\i = gEvalStack(sp - 1)\i
   gEvalStack(sp)\f = gEvalStack(sp - 1)\f
   gEvalStack(sp)\ss = gEvalStack(sp - 1)\ss
   sp + 1
   pc + 1
EndProcedure

Procedure               C2DUP_I()
   vm_DebugFunctionName()
   gEvalStack(sp)\i = gEvalStack(sp - 1)\i
   sp + 1
   pc + 1
EndProcedure

Procedure               C2DUP_F()
   vm_DebugFunctionName()
   gEvalStack(sp)\f = gEvalStack(sp - 1)\f
   sp + 1
   pc + 1
EndProcedure

Procedure               C2DUP_S()
   vm_DebugFunctionName()
   gEvalStack(sp)\ss = gEvalStack(sp - 1)\ss
   sp + 1
   pc + 1
EndProcedure

Procedure               C2JNZ()
   ; V1.31.0: Use gEvalStack[]
   vm_DebugFunctionName()
   sp - 1
   If gEvalStack(sp)\i
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
   ; V1.31.0: String concatenation on gEvalStack[]
   gEvalStack(sp - 1)\ss = gEvalStack(sp - 1)\ss + gEvalStack(sp)\ss
   pc + 1
EndProcedure

Procedure               C2FTOS()
   vm_DebugFunctionName()
   ; V1.31.0: Convert float to string at gEvalStack[] top
   gEvalStack(sp - 1)\ss = StrD(gEvalStack(sp - 1)\f, gDecs)
   pc + 1
EndProcedure

Procedure               C2ITOS()
   vm_DebugFunctionName()
   ; V1.31.0: Convert integer to string at gEvalStack[] top
   gEvalStack(sp - 1)\ss = Str(gEvalStack(sp - 1)\i)
   pc + 1
EndProcedure

Procedure               C2ITOF()
   vm_DebugFunctionName()
   ; V1.31.0: Convert integer to float at gEvalStack[] top
   gEvalStack(sp - 1)\f = gEvalStack(sp - 1)\i
   gEvalStack(sp - 1)\ptr = 0
   gEvalStack(sp - 1)\ptrtype = 0
   pc + 1
EndProcedure

Procedure               C2FTOI_ROUND()
   vm_DebugFunctionName()
   ; V1.31.0: Convert float to integer at gEvalStack[] top (round to nearest)
   gEvalStack(sp - 1)\i = gEvalStack(sp - 1)\f
   pc + 1
EndProcedure

Procedure               C2FTOI_TRUNCATE()
   vm_DebugFunctionName()
   ; V1.31.0: Convert float to integer at gEvalStack[] top (truncate towards zero)
   gEvalStack(sp - 1)\i = Int(gEvalStack(sp - 1)\f)
   pc + 1
EndProcedure

Procedure               C2STOF()
   vm_DebugFunctionName()
   ; V1.31.0: Convert string to float at gEvalStack[] top
   gEvalStack(sp - 1)\f = ValD(gEvalStack(sp - 1)\ss)
   pc + 1
EndProcedure

Procedure               C2STOI()
   vm_DebugFunctionName()
   ; V1.31.0: Convert string to integer at gEvalStack[] top
   gEvalStack(sp - 1)\i = Val(gEvalStack(sp - 1)\ss)
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
; V1.31.0: Updated for gEvalStack[]
Procedure               C2STREQ()
   vm_DebugFunctionName()
   sp - 1
   If gEvalStack(sp-1)\ss = gEvalStack(sp)\ss
      gEvalStack(sp-1)\i = 1
   Else
      gEvalStack(sp-1)\i = 0
   EndIf
   pc + 1
EndProcedure

Procedure               C2STRNE()
   vm_DebugFunctionName()
   sp - 1
   If gEvalStack(sp-1)\ss <> gEvalStack(sp)\ss
      gEvalStack(sp-1)\i = 1
   Else
      gEvalStack(sp-1)\i = 0
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
   ; V1.31.0: Use gEvalStack[]
   gEvalStack(sp - 1)\i = Bool(Not gEvalStack(sp - 1)\i)
   pc + 1
EndProcedure

Procedure               C2NEGATE()
   vm_DebugFunctionName()
   ; V1.31.0: Use gEvalStack[]
   gEvalStack(sp - 1)\i = -gEvalStack(sp - 1)\i
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

; V1.31.0: Print operations updated for gEvalStack[]
Procedure               C2PRTS()
   vm_DebugFunctionName()
   sp - 1
   CompilerIf #PB_Compiler_ExecutableFormat = #PB_Compiler_Console
      gBatchOutput + gEvalStack(sp)\ss
      Print(gEvalStack(sp)\ss)
   CompilerElse
      cline = cline + gEvalStack(sp)\ss
      If gFastPrint = #False
         vm_SetGadgetText( #edConsole, cy, cline )
      EndIf
   CompilerEndIf
   pc + 1
EndProcedure

Procedure               C2PRTPTR()
   vm_DebugFunctionName()
   sp - 1

   Select gEvalStack(sp)\ptrtype
      Case #PTR_INT, #PTR_ARRAY_INT
         CompilerIf #PB_Compiler_ExecutableFormat = #PB_Compiler_Console
            gBatchOutput + Str(gEvalStack(sp)\i)
            Print(Str(gEvalStack(sp)\i))
         CompilerElse
            cline = cline + Str(gEvalStack(sp)\i)
            If gFastPrint = #False
               vm_SetGadgetText( #edConsole, cy, cline )
            EndIf
         CompilerEndIf

      Case #PTR_FLOAT, #PTR_ARRAY_FLOAT
         CompilerIf #PB_Compiler_ExecutableFormat = #PB_Compiler_Console
            gBatchOutput + StrD(gEvalStack(sp)\f, gDecs)
            Print(StrD(gEvalStack(sp)\f, gDecs))
         CompilerElse
            cline = cline + StrD(gEvalStack(sp)\f, gDecs)
            If gFastPrint = #False
               vm_SetGadgetText( #edConsole, cy, cline )
            EndIf
         CompilerEndIf

      Case #PTR_STRING, #PTR_ARRAY_STRING
         CompilerIf #PB_Compiler_ExecutableFormat = #PB_Compiler_Console
            gBatchOutput + gEvalStack(sp)\ss
            Print(gEvalStack(sp)\ss)
         CompilerElse
            cline = cline + gEvalStack(sp)\ss
            If gFastPrint = #False
               vm_SetGadgetText( #edConsole, cy, cline )
            EndIf
         CompilerEndIf

      Default
         CompilerIf #DEBUG
            Debug "Invalid pointer type in PRTPTR: " + Str(gEvalStack(sp)\ptrtype) + " at pc=" + Str(pc)
         CompilerEndIf
   EndSelect

   pc + 1
EndProcedure

Procedure               C2PRTI()
   vm_DebugFunctionName()
   sp - 1
   CompilerIf #PB_Compiler_ExecutableFormat = #PB_Compiler_Console
      gBatchOutput + Str(gEvalStack(sp)\i)
      Print(Str(gEvalStack(sp)\i))
   CompilerElse
      cline = cline + Str(gEvalStack(sp)\i)
      If gFastPrint = #False
         vm_SetGadgetText( #edConsole, cy, cline )
      EndIf
   CompilerEndIf
   pc + 1
EndProcedure

Procedure               C2PRTF()
   vm_DebugFunctionName()
   sp - 1
   CompilerIf #PB_Compiler_ExecutableFormat = #PB_Compiler_Console
      gBatchOutput + StrD(gEvalStack(sp)\f, gDecs)
      Print(StrD(gEvalStack(sp)\f, gDecs))
   CompilerElse
      cline = cline + StrD(gEvalStack(sp)\f, gDecs)
      If gFastPrint = #False
         vm_SetGadgetText( #edConsole, cy, cline )
      EndIf
   CompilerEndIf
   pc + 1
EndProcedure

Procedure               C2PRTC()
   vm_DebugFunctionName()
   sp - 1

   CompilerIf #PB_Compiler_ExecutableFormat = #PB_Compiler_Console
      gBatchOutput + Chr(gEvalStack(sp)\i)
      If gEvalStack(sp)\i = 10 : PrintN( "" ) : EndIf
   CompilerElse
      If gEvalStack(sp)\i = 10
         If gFastPrint = #True
            vm_SetGadgetText( #edConsole, cy, cline )
         EndIf

         cy + 1
         cline = ""
         vm_AddGadgetLine( #edConsole, "" )
         vm_ScrollToBottom( #edConsole )
         vm_ScrollGadget( #edConsole )
      Else
         cline = cline + Chr(gEvalStack(sp)\i)
         If gFastPrint = #False
            vm_SetGadgetText( #edConsole, cy, cline )
         EndIf
      EndIf
   CompilerEndIf
   pc + 1
EndProcedure

Procedure               C2FLOATNEGATE()
   vm_DebugFunctionName()
   ; V1.31.0: Use gEvalStack[]
   gEvalStack(sp - 1)\f = -gEvalStack(sp - 1)\f
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
   ; V1.31.0: Tolerance-based float inequality using gEvalStack[]
   vm_DebugFunctionName()
   sp - 1
   ; Tolerance-based float inequality: NOT equal if difference > tolerance
   If Abs(gEvalStack(sp - 1)\f - gEvalStack(sp)\f) > gFloatTolerance
      gEvalStack(sp - 1)\i = 1
   Else
      gEvalStack(sp - 1)\i = 0
   EndIf
   pc + 1
EndProcedure

Procedure               C2FLOATEQUAL()
   ; V1.31.0: Tolerance-based float equality using gEvalStack[]
   vm_DebugFunctionName()
   sp - 1
   ; Tolerance-based float equality: equal if difference <= tolerance
   If Abs(gEvalStack(sp - 1)\f - gEvalStack(sp)\f) <= gFloatTolerance
      gEvalStack(sp - 1)\i = 1
   Else
      gEvalStack(sp - 1)\i = 0
   EndIf
   pc + 1
EndProcedure

Procedure               C2CALL()
   vm_DebugFunctionName()
   Protected nParams.l, nLocals.l, totalVars.l, nLocalArrays.l
   Protected i.l, funcId.l, pcAddr.l, varSlot.l, arraySize.l
   Protected arrayOffset.l, actualSlot.l, swapIdx.l
   Protected savedLocalBase.l  ; V1.31.0: Save caller's localBase
   ; V1.022.37: Temp storage for parameter swap
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

   ; V1.31.0 ISOLATED VARIABLE SYSTEM
   ; - Local variables stored in gLocal[] (separate from gVar[] and gEvalStack[])
   ; - Parameters copied from gEvalStack[] to gLocal[]
   ; - No overlap possible between locals and evaluation stack

   ; Increment stack depth (create new frame)
   gStackDepth = gStackDepth + 1

   If gStackDepth >= gMaxStackDepth
      Debug "*** FATAL ERROR: Stack overflow - max depth " + Str(gMaxStackDepth) + " exceeded at pc=" + Str(pc) + " funcId=" + Str(funcId)
      End
   EndIf

   If gLocalTop + totalVars >= #C2MAXLOCALS
      Debug "*** FATAL ERROR: Local variable overflow - max " + Str(#C2MAXLOCALS) + " exceeded at pc=" + Str(pc) + " funcId=" + Str(funcId)
      End
   EndIf

   ; V1.31.0: Save caller's localBase and set new frame base
   savedLocalBase = gLocalBase
   gLocalBase = gLocalTop  ; New frame starts at current top

   ; Save stack frame info
   gStack(gStackDepth)\pc = pc + 1
   gStack(gStackDepth)\sp = sp - nParams  ; Save sp BEFORE params were pushed (for return value)
   gStack(gStackDepth)\localBase = savedLocalBase  ; Caller's localBase for restoration
   gStack(gStackDepth)\localCount = totalVars

   CompilerIf #DEBUG
      Debug "C2CALL: depth=" + Str(gStackDepth) + " pcAddr=" + Str(pcAddr) + " nParams=" + Str(nParams) + " sp=" + Str(sp) + " gLocalBase=" + Str(gLocalBase) + " gLocalTop=" + Str(gLocalTop)
   CompilerEndIf

   ; V1.31.0: Copy parameters from gEvalStack[] to gLocal[]
   ; Parameters are at gEvalStack[sp-nParams..sp-1], need to reverse into LOCAL[0..nParams-1]
   ; Codegen assigns: last declared param → LOCAL[0], first declared → LOCAL[N-1]
   ; Caller pushes in declaration order, so we copy in reverse order
   For i = 0 To nParams - 1
      ; Copy from stack position (last pushed = sp-1) to LOCAL[i]
      ; Param i comes from stack position sp - nParams + (nParams - 1 - i) = sp - 1 - i
      gLocal(gLocalBase + i)\i = gEvalStack(sp - 1 - i)\i
      gLocal(gLocalBase + i)\f = gEvalStack(sp - 1 - i)\f
      gLocal(gLocalBase + i)\ss = gEvalStack(sp - 1 - i)\ss
      gLocal(gLocalBase + i)\ptr = gEvalStack(sp - 1 - i)\ptr
      gLocal(gLocalBase + i)\ptrtype = gEvalStack(sp - 1 - i)\ptrtype
      CompilerIf #DEBUG
         Debug "  Copy param[" + Str(i) + "]: gEvalStack[" + Str(sp - 1 - i) + "] -> gLocal[" + Str(gLocalBase + i) + "] i=" + Str(gLocal(gLocalBase + i)\i)
      CompilerEndIf
   Next

   ; Pop parameters from evaluation stack (they've been copied to gLocal[])
   sp = sp - nParams

   CompilerIf #DEBUG
      If nParams >= 3 And gStackDepth >= 6
         Debug "  Params in gLocal: LOCAL[0]=" + Str(gLocal(gLocalBase+0)\i) + " LOCAL[1]=" + Str(gLocal(gLocalBase+1)\i) + " LOCAL[2]=" + Str(gLocal(gLocalBase+2)\i) + " depth=" + Str(gStackDepth)
      EndIf
   CompilerEndIf

   ; V1.023.0: Preload non-parameter locals from function template
   ; Template covers LOCAL[nParams..totalVars-1] - the actual local variables
   ; Parameters are at LOCAL[0..nParams-1], already copied from stack
   If funcId >= 0 And funcId <= ArraySize(gFuncTemplates())
      templateCount = gFuncTemplates(funcId)\localCount
      If templateCount > 0
         dstStart = gLocalBase + nParams
         For i = 0 To templateCount - 1
            ; Copy template values to gLocal[] slots AFTER parameters
            gLocal(dstStart + i)\i = gFuncTemplates(funcId)\template(i)\i
            gLocal(dstStart + i)\f = gFuncTemplates(funcId)\template(i)\f
            gLocal(dstStart + i)\ss = gFuncTemplates(funcId)\template(i)\ss
            gLocal(dstStart + i)\ptr = gFuncTemplates(funcId)\template(i)\ptr
            gLocal(dstStart + i)\ptrtype = gFuncTemplates(funcId)\template(i)\ptrtype
         Next
         CompilerIf #DEBUG
            Debug "  Preloaded " + Str(templateCount) + " locals from template for funcId=" + Str(funcId)
         CompilerEndIf
      EndIf
   EndIf

   ; V1.31.0: Allocate local slots (advance gLocalTop)
   gLocalTop = gLocalTop + totalVars

   ; Allocate local arrays in their respective gLocal[] slots
   If nLocalArrays > 0
      CompilerIf #DEBUG
         Debug "  Allocating " + Str(nLocalArrays) + " local arrays, funcId=" + Str(funcId)
      CompilerEndIf
      For i = 0 To nLocalArrays - 1
         varSlot = gFuncLocalArraySlots(funcId, i)
         arrayOffset = gVarMeta(varSlot)\paramOffset  ; Offset within local variables
         actualSlot = gLocalBase + arrayOffset
         arraySize = gVarMeta(varSlot)\arraySize

         CompilerIf #DEBUG
            Debug "  LocalArray[" + Str(i) + "]: varSlot=" + Str(varSlot) + " arrayOffset=" + Str(arrayOffset) + " actualSlot=" + Str(actualSlot) + " arraySize=" + Str(arraySize)
         CompilerEndIf

         If arraySize > 0
            ReDim gLocal(actualSlot)\dta\ar(arraySize - 1)
            gLocal(actualSlot)\dta\size = arraySize
            CompilerIf #DEBUG
               Debug "    Allocated array at gLocal(" + Str(actualSlot) + ") with size " + Str(arraySize)
            CompilerEndIf
         EndIf
      Next
   EndIf

   ; V1.31.0: No sp adjustment needed - gEvalStack[] is completely isolated from gLocal[]
   ; sp remains where it was after popping parameters

   pc = pcAddr  ; Jump to function address
   gFunctionDepth = gFunctionDepth + 1  ; Increment function depth counter

EndProcedure

Procedure               C2Return()
   vm_DebugFunctionName()
   Protected returnValue.i, callerSp.i, i.l
   Protected localBase.l, localCount.l

   ; V1.31.0 ISOLATED VARIABLE SYSTEM
   ; Return value from gEvalStack[], locals in gLocal[]

   ; Initialize to default integer 0 (prevents uninitialized returns)
   returnValue = 0
   callerSp = gStack(gStackDepth)\sp

   ; Save return value from top of gEvalStack[] (sp-1) if there's anything on stack
   If sp > 0
      returnValue = gEvalStack(sp - 1)\i
      CompilerIf #DEBUG
         Debug "C2Return: sp=" + Str(sp) + " returnValue=" + Str(returnValue) + " from gEvalStack(" + Str(sp-1) + ") depth=" + Str(gStackDepth)
      CompilerEndIf
   Else
      CompilerIf #DEBUG
         Debug "C2Return: WARNING! sp=" + Str(sp) + " - using default returnValue=0 depth=" + Str(gStackDepth)
      CompilerEndIf
   EndIf

   ; Restore caller's program counter and stack pointer
   pc = gStack(gStackDepth)\pc
   sp = callerSp

   ; V1.31.0: Clear gLocal[] slots (strings and arrays for memory management)
   localBase = gLocalBase
   localCount = gStack(gStackDepth)\localCount

   For i = 0 To localCount - 1
      gLocal(localBase + i)\ss = ""  ; MUST clear for PureBasic string garbage collection
      ; Clear array data if present
      If gLocal(localBase + i)\dta\size > 0
         ReDim gLocal(localBase + i)\dta\ar(0)
         gLocal(localBase + i)\dta\size = 0
      EndIf
   Next

   ; V1.31.0: Restore gLocalBase and gLocalTop from saved frame
   gLocalTop = gLocalBase  ; Deallocate this frame's local slots
   gLocalBase = gStack(gStackDepth)\localBase  ; Restore caller's localBase

   ; Delete current stack frame (decrement depth)
   gStackDepth = gStackDepth - 1
   gFunctionDepth = gFunctionDepth - 1  ; Decrement function depth counter

   ; Push return value onto caller's gEvalStack[]
   gEvalStack(sp)\i = returnValue
   sp + 1
EndProcedure

Procedure               C2ReturnF()
   vm_DebugFunctionName()
   Protected returnValue.f, callerSp.i, i.l
   Protected localBase.l, localCount.l

   ; V1.31.0 ISOLATED VARIABLE SYSTEM

   ; Initialize to default float 0.0
   returnValue = 0.0
   callerSp = gStack(gStackDepth)\sp

   ; Save float return value from top of gEvalStack[] (sp-1) if there's anything on stack
   If sp > 0
      returnValue = gEvalStack(sp - 1)\f
   EndIf

   ; Restore caller's program counter and stack pointer
   pc = gStack(gStackDepth)\pc
   sp = callerSp

   ; V1.31.0: Clear gLocal[] slots (strings and arrays for memory management)
   localBase = gLocalBase
   localCount = gStack(gStackDepth)\localCount

   For i = 0 To localCount - 1
      gLocal(localBase + i)\ss = ""  ; MUST clear for PureBasic string garbage collection
      ; Clear array data if present
      If gLocal(localBase + i)\dta\size > 0
         ReDim gLocal(localBase + i)\dta\ar(0)
         gLocal(localBase + i)\dta\size = 0
      EndIf
   Next

   ; V1.31.0: Restore gLocalBase and gLocalTop from saved frame
   gLocalTop = gLocalBase  ; Deallocate this frame's local slots
   gLocalBase = gStack(gStackDepth)\localBase  ; Restore caller's localBase

   ; Delete current stack frame (decrement depth)
   gStackDepth = gStackDepth - 1
   gFunctionDepth = gFunctionDepth - 1  ; Decrement function depth counter

   ; Push float return value onto caller's gEvalStack[]
   gEvalStack(sp)\f = returnValue
   sp + 1
EndProcedure

Procedure               C2ReturnS()
   vm_DebugFunctionName()
   Protected returnValue.s, callerSp.i, i.l
   Protected localBase.l, localCount.l

   ; V1.31.0 ISOLATED VARIABLE SYSTEM

   ; Initialize to default empty string
   returnValue = ""
   callerSp = gStack(gStackDepth)\sp

   ; Save string return value from top of gEvalStack[] (sp-1) if there's anything on stack
   If sp > 0
      returnValue = gEvalStack(sp - 1)\ss
   EndIf

   ; Restore caller's program counter and stack pointer
   pc = gStack(gStackDepth)\pc
   sp = callerSp

   ; V1.31.0: Clear gLocal[] slots (strings and arrays for memory management)
   localBase = gLocalBase
   localCount = gStack(gStackDepth)\localCount

   For i = 0 To localCount - 1
      gLocal(localBase + i)\ss = ""  ; MUST clear for PureBasic string garbage collection
      ; Clear array data if present
      If gLocal(localBase + i)\dta\size > 0
         ReDim gLocal(localBase + i)\dta\ar(0)
         gLocal(localBase + i)\dta\size = 0
      EndIf
   Next

   ; V1.31.0: Restore gLocalBase and gLocalTop from saved frame
   gLocalTop = gLocalBase  ; Deallocate this frame's local slots
   gLocalBase = gStack(gStackDepth)\localBase  ; Restore caller's localBase

   ; Delete current stack frame (decrement depth)
   gStackDepth = gStackDepth - 1
   gFunctionDepth = gFunctionDepth - 1  ; Decrement function depth counter

   ; Push string return value onto caller's gEvalStack[]
   gEvalStack(sp)\ss = returnValue
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
XIncludeFile "c2-builtins-v05.pbi"

;- Include Array Operations Module
XIncludeFile "c2-arrays-v04.pbi"

;- Include Pointer Operations Module
XIncludeFile "c2-pointers-v04.pbi"

;- Include Collections Module (V1.028.0 - Unified in gVar)
XIncludeFile "c2-collections-v02.pbi"

;- End VM functions

; IDE Options = PureBasic 6.21 (Linux - x64)
; CursorPosition = 75
; FirstLine = 62
; Folding = ------------------------
; EnableAsm
; EnableThread
; EnableXP
; CPU = 1
; EnablePurifier
; EnableCompileCount = 0
; EnableBuildCount = 0
; EnableExeConstant