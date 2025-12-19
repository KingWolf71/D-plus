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

; ============================================================================
; V1.031.106: VM MACROS FOR OPCODE PROCEDURES
; ============================================================================
; These macros eliminate temporary variables and improve code readability.
; Use these instead of Protected/Define local variables where possible.
; See CLAUDE.md rule 16: "Don't use intermediate variables in VM code"
;
; INSTRUCTION FIELD ACCESS:
;   _NPARAMS      - Number of parameters (CALL: j field)
;   _NLOCALS      - Number of local variables (CALL: n field)
;   _NLOCALARRAYS - Number of local arrays (CALL: ndx field)
;   _FUNCID       - Function ID for template lookup (CALL: funcid field)
;   _PCADDR       - PC address for jump (i field)
;   _ARRSLOT      - Array variable slot (i field)
;   _ISLOCAL      - Is local flag: 0=global, 1=local (j field)
;   _IDXSLOT      - Index variable slot for optimized paths (ndx field)
;
; STACK OPERATIONS (gEvalStack):
;   _POPI         - Peek integer at top of stack (sp-1)
;   _POPF         - Peek float at top of stack
;   _POPS         - Peek string at top of stack
;   _STACKI(n)    - Stack integer at offset n from top
;   _STACKF(n)    - Stack float at offset n from top
;   _STACKS(n)    - Stack string at offset n from top
;
; LOCAL VARIABLE ACCESS (gLocal with gLocalBase):
;   _LOCALSLOT(offset) - Compute actual slot: gLocalBase + offset
;   _LOCALI(offset)    - Local integer at offset
;   _LOCALF(offset)    - Local float at offset
;   _LOCALS(offset)    - Local string at offset
;
; ARRAYINFO INLINE OPCODES (for local array allocation):
;   _ARRAYINFO_OFFSET(i) - Param offset from i-th ARRAYINFO opcode
;   _ARRAYINFO_SIZE(i)   - Array size from i-th ARRAYINFO opcode
; ============================================================================

; Instruction field access macros
Macro _NPARAMS : _AR()\j : EndMacro
Macro _NLOCALS : _AR()\n : EndMacro
Macro _NLOCALARRAYS : _AR()\ndx : EndMacro
Macro _FUNCID : _AR()\funcid : EndMacro
Macro _PCADDR : _AR()\i : EndMacro
Macro _ARRSLOT : _AR()\i : EndMacro
Macro _ISLOCAL : _AR()\j : EndMacro
Macro _IDXSLOT : _AR()\ndx : EndMacro

; Stack operation macros
Macro _POPI : gEvalStack(sp - 1)\i : EndMacro
Macro _POPF : gEvalStack(sp - 1)\f : EndMacro
Macro _POPS : gEvalStack(sp - 1)\ss : EndMacro
Macro _STACKI(n) : gEvalStack(sp - 1 - (n))\i : EndMacro
Macro _STACKF(n) : gEvalStack(sp - 1 - (n))\f : EndMacro
Macro _STACKS(n) : gEvalStack(sp - 1 - (n))\ss : EndMacro

; Local variable access macros
Macro _LOCALSLOT(offset) : (gLocalBase + (offset)) : EndMacro
Macro _LOCALI(offset) : gLocal(gLocalBase + (offset))\i : EndMacro
Macro _LOCALF(offset) : gLocal(gLocalBase + (offset))\f : EndMacro
Macro _LOCALS(offset) : gLocal(gLocalBase + (offset))\ss : EndMacro

; ARRAYINFO inline opcode access (pc+1+i for i-th array)
Macro _ARRAYINFO_OFFSET(i) : arCode(pc + 1 + (i))\i : EndMacro
Macro _ARRAYINFO_SIZE(i) : arCode(pc + 1 + (i))\j : EndMacro

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
      ;   Debug "Stack pointer at: " + Str(sp) + " / " + Str(gMaxEvalStack)
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
      ; V1.031.106: Added logging support for console mode
      If gCreateLog
         WriteStringN(gLogfn, tmsg)
      EndIf
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

; V1.031.113: Push immediate integer value directly (no gVar lookup)
Procedure               C2PUSH_IMM()
   vm_DebugFunctionName()
   ; Push the operand value directly to stack - bypasses gVar[] lookup
   gEvalStack(sp)\i = _AR()\i
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
   Protected localIdx.i = gLocalBase + _AR()\i
   CompilerIf #DEBUG
      ; V1.031.27: Bounds checking for debug builds
      If sp < 0 Or sp >= gMaxEvalStack
         Debug "*** LSTORE ERROR: sp=" + Str(sp) + " out of bounds [0.." + Str(gMaxEvalStack-1) + "] at pc=" + Str(pc)
         gExitApplication = #True
         ProcedureReturn
      EndIf
      If localIdx < 0 Or localIdx >= gLocalStack
         Debug "*** LSTORE ERROR: gLocal index=" + Str(localIdx) + " (gLocalBase=" + Str(gLocalBase) + " offset=" + Str(_AR()\i) + ") out of bounds [0.." + Str(gLocalStack-1) + "] at pc=" + Str(pc)
         gExitApplication = #True
         ProcedureReturn
      EndIf
      Debug "VM LSTORE: gLocalBase=" + Str(gLocalBase) + " offset=" + Str(_AR()\i) + " value=" + Str(gEvalStack(sp)\i)
   CompilerEndIf
   gLocal(localIdx)\i = gEvalStack(sp)\i
   pc + 1
EndProcedure

Procedure               C2LSTORES()
   vm_DebugFunctionName()
   sp - 1
   ; V1.31.0: Store string to gLocal[gLocalBase + offset] from gEvalStack[]
   Protected localIdx.i = gLocalBase + _AR()\i
   CompilerIf #DEBUG
      If sp < 0 Or sp >= gMaxEvalStack
         Debug "*** LSTORES ERROR: sp=" + Str(sp) + " out of bounds at pc=" + Str(pc)
         gExitApplication = #True
         ProcedureReturn
      EndIf
      If localIdx < 0 Or localIdx >= gLocalStack
         Debug "*** LSTORES ERROR: gLocal index=" + Str(localIdx) + " out of bounds at pc=" + Str(pc)
         gExitApplication = #True
         ProcedureReturn
      EndIf
   CompilerEndIf
   gLocal(localIdx)\ss = gEvalStack(sp)\ss
   pc + 1
EndProcedure

Procedure               C2LSTOREF()
   vm_DebugFunctionName()
   sp - 1
   ; V1.31.0: Store float to gLocal[gLocalBase + offset] from gEvalStack[]
   Protected localIdx.i = gLocalBase + _AR()\i
   CompilerIf #DEBUG
      If sp < 0 Or sp >= gMaxEvalStack
         Debug "*** LSTOREF ERROR: sp=" + Str(sp) + " out of bounds at pc=" + Str(pc)
         gExitApplication = #True
         ProcedureReturn
      EndIf
      If localIdx < 0 Or localIdx >= gLocalStack
         Debug "*** LSTOREF ERROR: gLocal index=" + Str(localIdx) + " out of bounds at pc=" + Str(pc)
         gExitApplication = #True
         ProcedureReturn
      EndIf
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
      gConsoleLine + gEvalStack(sp)\ss    ; V1.031.106: Track line for logging
      Print(gEvalStack(sp)\ss)
   CompilerElse
      ; V1.031.117: Test mode - output to allocated console
      If gTestMode = #True
         Print(gEvalStack(sp)\ss)
      Else
         cline = cline + gEvalStack(sp)\ss
         If gFastPrint = #False
            vm_SetGadgetText( #edConsole, cy, cline )
         EndIf
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
            gConsoleLine + Str(gEvalStack(sp)\i)    ; V1.031.106: Track line for logging
            Print(Str(gEvalStack(sp)\i))
         CompilerElse
            ; V1.031.117: Test mode - output to allocated console
            If gTestMode = #True
               Print(Str(gEvalStack(sp)\i))
            Else
               cline = cline + Str(gEvalStack(sp)\i)
               If gFastPrint = #False
                  vm_SetGadgetText( #edConsole, cy, cline )
               EndIf
            EndIf
         CompilerEndIf

      Case #PTR_FLOAT, #PTR_ARRAY_FLOAT
         CompilerIf #PB_Compiler_ExecutableFormat = #PB_Compiler_Console
            gBatchOutput + StrD(gEvalStack(sp)\f, gDecs)
            gConsoleLine + StrD(gEvalStack(sp)\f, gDecs)    ; V1.031.106: Track line for logging
            Print(StrD(gEvalStack(sp)\f, gDecs))
         CompilerElse
            ; V1.031.117: Test mode - output to allocated console
            If gTestMode = #True
               Print(StrD(gEvalStack(sp)\f, gDecs))
            Else
               cline = cline + StrD(gEvalStack(sp)\f, gDecs)
               If gFastPrint = #False
                  vm_SetGadgetText( #edConsole, cy, cline )
               EndIf
            EndIf
         CompilerEndIf

      Case #PTR_STRING, #PTR_ARRAY_STRING
         CompilerIf #PB_Compiler_ExecutableFormat = #PB_Compiler_Console
            gBatchOutput + gEvalStack(sp)\ss
            gConsoleLine + gEvalStack(sp)\ss    ; V1.031.106: Track line for logging
            Print(gEvalStack(sp)\ss)
         CompilerElse
            ; V1.031.117: Test mode - output to allocated console
            If gTestMode = #True
               Print(gEvalStack(sp)\ss)
            Else
               cline = cline + gEvalStack(sp)\ss
               If gFastPrint = #False
                  vm_SetGadgetText( #edConsole, cy, cline )
               EndIf
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
      gConsoleLine + Str(gEvalStack(sp)\i)    ; V1.031.106: Track line for logging
      Print(Str(gEvalStack(sp)\i))
   CompilerElse
      ; V1.031.117: Test mode - output to allocated console
      If gTestMode = #True
         Print(Str(gEvalStack(sp)\i))
      Else
         cline = cline + Str(gEvalStack(sp)\i)
         If gFastPrint = #False
            vm_SetGadgetText( #edConsole, cy, cline )
         EndIf
      EndIf
   CompilerEndIf
   pc + 1
EndProcedure

Procedure               C2PRTF()
   vm_DebugFunctionName()
   sp - 1
   CompilerIf #PB_Compiler_ExecutableFormat = #PB_Compiler_Console
      gBatchOutput + StrD(gEvalStack(sp)\f, gDecs)
      gConsoleLine + StrD(gEvalStack(sp)\f, gDecs)    ; V1.031.106: Track line for logging
      Print(StrD(gEvalStack(sp)\f, gDecs))
   CompilerElse
      ; V1.031.117: Test mode - output to allocated console
      If gTestMode = #True
         Print(StrD(gEvalStack(sp)\f, gDecs))
      Else
         cline = cline + StrD(gEvalStack(sp)\f, gDecs)
         If gFastPrint = #False
            vm_SetGadgetText( #edConsole, cy, cline )
         EndIf
      EndIf
   CompilerEndIf
   pc + 1
EndProcedure

Procedure               C2PRTC()
   vm_DebugFunctionName()
   sp - 1

   CompilerIf #PB_Compiler_ExecutableFormat = #PB_Compiler_Console
      gBatchOutput + Chr(gEvalStack(sp)\i)
      If gEvalStack(sp)\i = 10
         PrintN("")
         ; V1.031.106: Log complete line when newline is encountered
         If gCreateLog
            WriteStringN(gLogfn, gConsoleLine)
         EndIf
         gConsoleLine = ""
      Else
         gConsoleLine + Chr(gEvalStack(sp)\i)
      EndIf
   CompilerElse
      ; V1.031.117: Test mode - output to allocated console
      If gTestMode = #True
         If gEvalStack(sp)\i = 10
            PrintN("")
         Else
            Print(Chr(gEvalStack(sp)\i))
         EndIf
      Else
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
   ; V1.031.106: Refactored to use macros, removed unused variables
   vm_DebugFunctionName()
   Define i.l  ; Loop counter only

   ; V1.31.0 ISOLATED VARIABLE SYSTEM
   ; - Local variables stored in gLocal[] (separate from gVar[] and gEvalStack[])
   ; - Parameters copied from gEvalStack[] to gLocal[]
   ; - No overlap possible between locals and evaluation stack

   ; Increment stack depth (create new frame)
   gStackDepth + 1

   CompilerIf #DEBUG
      If gStackDepth >= gFunctionStack
         Debug "*** FATAL ERROR: Stack overflow at pc=" + Str(pc) + " funcId=" + Str(_FUNCID)
         End
      EndIf
      If gLocalTop + _NPARAMS + _NLOCALS > gLocalStack
         Debug "*** FATAL ERROR: Local variable overflow at pc=" + Str(pc)
         End
      EndIf
   CompilerEndIf

   ; Save stack frame info
   ; V1.031.105: Skip over ARRAYINFO opcodes when saving return address
   gStack(gStackDepth)\pc = pc + 1 + _NLOCALARRAYS
   gStack(gStackDepth)\sp = sp - _NPARAMS       ; Save sp BEFORE params were pushed
   gStack(gStackDepth)\localBase = gLocalBase   ; Caller's localBase for restoration
   gStack(gStackDepth)\localCount = _NPARAMS + _NLOCALS

   ; V1.31.0: Set new frame base
   gLocalBase = gLocalTop  ; New frame starts at current top

   CompilerIf #DEBUG
      Debug "C2CALL: depth=" + Str(gStackDepth) + " pcAddr=" + Str(_PCADDR) + " nParams=" + Str(_NPARAMS) + " sp=" + Str(sp)
   CompilerEndIf

   ; V1.31.0: Copy parameters from gEvalStack[] to gLocal[] (reverse order)
   For i = 0 To _NPARAMS - 1
      CopyStructure(gEvalStack(sp - 1 - i), gLocal(gLocalBase + i), stVTSimple)
      CompilerIf #DEBUG
         Debug "  Copy param[" + Str(i) + "]: gEvalStack[" + Str(sp - 1 - i) + "] -> gLocal[" + Str(gLocalBase + i) + "]"
      CompilerEndIf
   Next

   ; Pop parameters from evaluation stack
   sp - _NPARAMS

   ; V1.023.0: Preload non-parameter locals from function template
   If _FUNCID >= 0 And _FUNCID <= ArraySize(gFuncTemplates())
      If gFuncTemplates(_FUNCID)\localCount > 0
         For i = 0 To gFuncTemplates(_FUNCID)\localCount - 1
            CopyStructure(gFuncTemplates(_FUNCID)\template(i), gLocal(gLocalBase + _NPARAMS + i), stVTSimple)
         Next
         CompilerIf #DEBUG
            Debug "  Preloaded " + Str(gFuncTemplates(_FUNCID)\localCount) + " locals from template"
         CompilerEndIf
      EndIf
   EndIf

   ; V1.31.0: Allocate local slots (advance gLocalTop)
   gLocalTop + _NPARAMS + _NLOCALS

   ; Allocate local arrays using inline ARRAYINFO opcodes
   If _NLOCALARRAYS > 0
      CompilerIf #DEBUG
         Debug "  Allocating " + Str(_NLOCALARRAYS) + " local arrays from inline ARRAYINFO"
      CompilerEndIf
      For i = 0 To _NLOCALARRAYS - 1
         If _ARRAYINFO_SIZE(i) > 0
            ReDim gLocal(gLocalBase + _ARRAYINFO_OFFSET(i))\dta\ar(_ARRAYINFO_SIZE(i) - 1)
            gLocal(gLocalBase + _ARRAYINFO_OFFSET(i))\dta\size = _ARRAYINFO_SIZE(i)
            CompilerIf #DEBUG
               Debug "    Array[" + Str(i) + "] at slot " + Str(gLocalBase + _ARRAYINFO_OFFSET(i)) + " size=" + Str(_ARRAYINFO_SIZE(i))
            CompilerEndIf
         EndIf
      Next
   EndIf

   pc = _PCADDR              ; Jump to function address
   gFunctionDepth + 1        ; Increment function depth counter

EndProcedure

; V1.033.12: Optimized CALL for 0 parameters - eliminates param copy loop
Procedure               C2CALL0()
   vm_DebugFunctionName()
   Define i.l

   gStackDepth + 1

   CompilerIf #DEBUG
      If gStackDepth >= gFunctionStack
         Debug "*** FATAL ERROR: Stack overflow at pc=" + Str(pc) + " funcId=" + Str(_FUNCID)
         End
      EndIf
   CompilerEndIf

   ; Save stack frame (no params to account for in sp)
   gStack(gStackDepth)\pc = pc + 1 + _NLOCALARRAYS
   gStack(gStackDepth)\sp = sp                        ; sp unchanged - no params
   gStack(gStackDepth)\localBase = gLocalBase
   gStack(gStackDepth)\localCount = _NLOCALS          ; 0 params + nLocals

   gLocalBase = gLocalTop

   ; No parameter copy needed - skip straight to template preload
   If _FUNCID >= 0 And _FUNCID <= ArraySize(gFuncTemplates())
      If gFuncTemplates(_FUNCID)\localCount > 0
         For i = 0 To gFuncTemplates(_FUNCID)\localCount - 1
            CopyStructure(gFuncTemplates(_FUNCID)\template(i), gLocal(gLocalBase + i), stVTSimple)
         Next
      EndIf
   EndIf

   gLocalTop + _NLOCALS

   ; Allocate local arrays
   If _NLOCALARRAYS > 0
      For i = 0 To _NLOCALARRAYS - 1
         If _ARRAYINFO_SIZE(i) > 0
            ReDim gLocal(gLocalBase + _ARRAYINFO_OFFSET(i))\dta\ar(_ARRAYINFO_SIZE(i) - 1)
            gLocal(gLocalBase + _ARRAYINFO_OFFSET(i))\dta\size = _ARRAYINFO_SIZE(i)
         EndIf
      Next
   EndIf

   pc = _PCADDR
   gFunctionDepth + 1
EndProcedure

; V1.033.12: Optimized CALL for 1 parameter - direct copy, no loop
Procedure               C2CALL1()
   vm_DebugFunctionName()
   Define i.l

   gStackDepth + 1

   CompilerIf #DEBUG
      If gStackDepth >= gFunctionStack
         Debug "*** FATAL ERROR: Stack overflow at pc=" + Str(pc) + " funcId=" + Str(_FUNCID)
         End
      EndIf
   CompilerEndIf

   gStack(gStackDepth)\pc = pc + 1 + _NLOCALARRAYS
   gStack(gStackDepth)\sp = sp - 1                    ; 1 param
   gStack(gStackDepth)\localBase = gLocalBase
   gStack(gStackDepth)\localCount = 1 + _NLOCALS

   gLocalBase = gLocalTop

   ; Direct copy of 1 param (no loop)
   CopyStructure(gEvalStack(sp - 1), gLocal(gLocalBase), stVTSimple)
   sp - 1

   ; Template preload
   If _FUNCID >= 0 And _FUNCID <= ArraySize(gFuncTemplates())
      If gFuncTemplates(_FUNCID)\localCount > 0
         For i = 0 To gFuncTemplates(_FUNCID)\localCount - 1
            CopyStructure(gFuncTemplates(_FUNCID)\template(i), gLocal(gLocalBase + 1 + i), stVTSimple)
         Next
      EndIf
   EndIf

   gLocalTop + 1 + _NLOCALS

   If _NLOCALARRAYS > 0
      For i = 0 To _NLOCALARRAYS - 1
         If _ARRAYINFO_SIZE(i) > 0
            ReDim gLocal(gLocalBase + _ARRAYINFO_OFFSET(i))\dta\ar(_ARRAYINFO_SIZE(i) - 1)
            gLocal(gLocalBase + _ARRAYINFO_OFFSET(i))\dta\size = _ARRAYINFO_SIZE(i)
         EndIf
      Next
   EndIf

   pc = _PCADDR
   gFunctionDepth + 1
EndProcedure

; V1.033.12: Optimized CALL for 2 parameters - unrolled copy
Procedure               C2CALL2()
   vm_DebugFunctionName()
   Define i.l

   gStackDepth + 1

   CompilerIf #DEBUG
      If gStackDepth >= gFunctionStack
         Debug "*** FATAL ERROR: Stack overflow at pc=" + Str(pc) + " funcId=" + Str(_FUNCID)
         End
      EndIf
   CompilerEndIf

   gStack(gStackDepth)\pc = pc + 1 + _NLOCALARRAYS
   gStack(gStackDepth)\sp = sp - 2                    ; 2 params
   gStack(gStackDepth)\localBase = gLocalBase
   gStack(gStackDepth)\localCount = 2 + _NLOCALS

   gLocalBase = gLocalTop

   ; Unrolled copy of 2 params (no loop)
   CopyStructure(gEvalStack(sp - 1), gLocal(gLocalBase), stVTSimple)      ; param 0
   CopyStructure(gEvalStack(sp - 2), gLocal(gLocalBase + 1), stVTSimple)  ; param 1
   sp - 2

   ; Template preload
   If _FUNCID >= 0 And _FUNCID <= ArraySize(gFuncTemplates())
      If gFuncTemplates(_FUNCID)\localCount > 0
         For i = 0 To gFuncTemplates(_FUNCID)\localCount - 1
            CopyStructure(gFuncTemplates(_FUNCID)\template(i), gLocal(gLocalBase + 2 + i), stVTSimple)
         Next
      EndIf
   EndIf

   gLocalTop + 2 + _NLOCALS

   If _NLOCALARRAYS > 0
      For i = 0 To _NLOCALARRAYS - 1
         If _ARRAYINFO_SIZE(i) > 0
            ReDim gLocal(gLocalBase + _ARRAYINFO_OFFSET(i))\dta\ar(_ARRAYINFO_SIZE(i) - 1)
            gLocal(gLocalBase + _ARRAYINFO_OFFSET(i))\dta\size = _ARRAYINFO_SIZE(i)
         EndIf
      Next
   EndIf

   pc = _PCADDR
   gFunctionDepth + 1
EndProcedure

; V1.031.106: Macro for common cleanup of local slots
Macro _CLEANUP_LOCALS(baseSlot, count)
   For _i = 0 To (count) - 1
      gLocal((baseSlot) + _i)\ss = ""
      If gLocal((baseSlot) + _i)\dta\size > 0
         ReDim gLocal((baseSlot) + _i)\dta\ar(0)
         gLocal((baseSlot) + _i)\dta\size = 0
      EndIf
   Next
EndMacro

Procedure               C2Return()
   ; V1.031.106: Refactored to use macros
   vm_DebugFunctionName()
   Define _i.l, _retval.i = 0, _savedBase.l = gLocalBase

   ; Save return value before cleanup
   If sp > 0 : _retval = _POPI : EndIf
   CompilerIf #DEBUG
      Debug "C2Return: sp=" + Str(sp) + " retval=" + Str(_retval) + " depth=" + Str(gStackDepth)
   CompilerEndIf

   ; Restore caller's pc and sp
   pc = gStack(gStackDepth)\pc
   sp = gStack(gStackDepth)\sp

   ; Clear local slots (strings/arrays for GC)
   _CLEANUP_LOCALS(_savedBase, gStack(gStackDepth)\localCount)

   ; Restore frame pointers and decrement depth
   gLocalTop = _savedBase
   gLocalBase = gStack(gStackDepth)\localBase
   gStackDepth - 1
   gFunctionDepth - 1

   ; Push return value
   gEvalStack(sp)\i = _retval
   sp + 1
EndProcedure

Procedure               C2ReturnF()
   ; V1.031.106: Refactored to use macros
   vm_DebugFunctionName()
   Define _i.l, _retval.d = 0.0, _savedBase.l = gLocalBase

   ; Save return value before cleanup
   If sp > 0 : _retval = _POPF : EndIf

   ; Restore caller's pc and sp
   pc = gStack(gStackDepth)\pc
   sp = gStack(gStackDepth)\sp

   ; Clear local slots (strings/arrays for GC)
   _CLEANUP_LOCALS(_savedBase, gStack(gStackDepth)\localCount)

   ; Restore frame pointers and decrement depth
   gLocalTop = _savedBase
   gLocalBase = gStack(gStackDepth)\localBase
   gStackDepth - 1
   gFunctionDepth - 1

   ; Push return value
   gEvalStack(sp)\f = _retval
   sp + 1
EndProcedure

Procedure               C2ReturnS()
   ; V1.031.106: Refactored to use macros
   vm_DebugFunctionName()
   Define _i.l, _retval.s = "", _savedBase.l = gLocalBase

   ; Save return value before cleanup
   If sp > 0 : _retval = _POPS : EndIf

   ; Restore caller's pc and sp
   pc = gStack(gStackDepth)\pc
   sp = gStack(gStackDepth)\sp

   ; Clear local slots (strings/arrays for GC)
   _CLEANUP_LOCALS(_savedBase, gStack(gStackDepth)\localCount)

   ; Restore frame pointers and decrement depth
   gLocalTop = _savedBase
   gLocalBase = gStack(gStackDepth)\localBase
   gStackDepth - 1
   gFunctionDepth - 1

   ; Push return value
   gEvalStack(sp)\ss = _retval
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

;- ============================================================================

;- Include Built-in Functions Module
XIncludeFile "c2-builtins-v06.pbi"

;- Include Array Operations Module
XIncludeFile "c2-arrays-v06.pbi"

;- Include Pointer Operations Module
XIncludeFile "c2-pointers-v05.pbi"

;- Include Collections Module (V1.028.0 - Unified in gVar)
XIncludeFile "c2-collections-v03.pbi"

;- End VM functions

; IDE Options = PureBasic 6.21 (Windows - x64)
; CursorPosition = 1079
; FirstLine = 1054
; Folding = -------------------------
; EnableAsm
; EnableThread
; EnableXP
; CPU = 1
; EnablePurifier
; EnableCompileCount = 0
; EnableBuildCount = 0
; EnableExeConstant