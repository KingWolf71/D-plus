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
; STACK OPERATIONS (gStorage):
;   _POPI         - Peek integer at top of stack (sp-1)
;   _POPF         - Peek float at top of stack
;   _POPS         - Peek string at top of stack
;   _STACKI(n)    - Stack integer at offset n from top
;   _STACKF(n)    - Stack float at offset n from top
;   _STACKS(n)    - Stack string at offset n from top
;
; LOCAL VARIABLE ACCESS (gLocal with gFrameBase):
;   _LOCALSLOT(offset) - Compute actual slot: gFrameBase + offset
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

; V1.035.0: POINTER ARRAY ARCHITECTURE
; *gVar(slot) points to stVar structure with \var() array
; - Globals: *gVar(slot)\var(0) for single value
; - Functions: *gVar(funcSlot)\var(localIdx) for params + locals
; - Eval stack: gEvalStack(sp) - separate array
; - Recursion: swap *gVar(funcSlot) to allocated frame, restore on return
;
; _SLOT(j, offset) - slot access:
;   j=0 → *gVar(offset)\var(0) = global at offset
;   j=1 → *gVar(gCurrentFuncSlot)\var(offset) = local at offset
Macro _SLOT(j, offset)
   *gVar(gCurrentFuncSlot * (j) + (offset) * (1 - (j)))\var((offset) * (j))
EndMacro

; V1.035.0: Global access macro - each global at *gVar(n)\var(0)
Macro _GLOBAL(n) : *gVar(n)\var(0) : EndMacro

; V1.035.0: Eval stack macros - gEvalStack is separate array
Macro _POPI : gEvalStack(sp - 1)\i : EndMacro
Macro _POPF : gEvalStack(sp - 1)\f : EndMacro
Macro _POPS : gEvalStack(sp - 1)\ss : EndMacro
Macro _STACKI(n) : gEvalStack(sp - 1 - (n))\i : EndMacro
Macro _STACKF(n) : gEvalStack(sp - 1 - (n))\f : EndMacro
Macro _STACKS(n) : gEvalStack(sp - 1 - (n))\ss : EndMacro

; V1.035.0: Local variable macros - use *gVar(gCurrentFuncSlot)\var(offset)
Macro _LOCALSLOT(offset) : (offset) : EndMacro
Macro _LOCALI(offset) : *gVar(gCurrentFuncSlot)\var(offset)\i : EndMacro
Macro _LOCALF(offset) : *gVar(gCurrentFuncSlot)\var(offset)\f : EndMacro
Macro _LOCALS(offset) : *gVar(gCurrentFuncSlot)\var(offset)\ss : EndMacro

; V1.035.0: Local pointer access for struct operations
Macro _LOCALPTR(offset) : *gVar(gCurrentFuncSlot)\var(offset)\ptr : EndMacro

; V1.035.0: Get function slot from funcId (via gFuncTemplates)
Macro _FUNCSLOT : gFuncTemplates(_FUNCID)\funcSlot : EndMacro
Macro _FUNC_NPARAMS : gFuncTemplates(_FUNCID)\nParams : EndMacro
Macro _FUNC_LOCALCOUNT : gFuncTemplates(_FUNCID)\localCount : EndMacro

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
; V1.035.0: Push to gEvalStack[]
; V1.035.1: Removed erroneous pc+1 - opcode handlers already increment pc
Macro                   vm_PushInt(value)
   gEvalStack(sp)\i = value
   sp + 1
EndMacro

; Macro for built-in functions: push float result
; V1.035.0: Push to gEvalStack[]
; V1.035.1: Removed erroneous pc+1 - opcode handlers already increment pc
Macro                   vm_PushFloat(value)
   gEvalStack(sp)\f = value
   sp + 1
EndMacro

; V1.039.45: Macro for built-in functions: push string result
Macro                   vm_PushString(value)
   gEvalStack(sp)\ss = value
   sp + 1
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
   ; V1.034.18: Unified FETCH using _SLOT(j, offset)
   ; j=0 → global: gStorage(offset), j=1 → local: gStorage(gFrameBase + offset)
   gEvalStack(sp)\i = _SLOT(_AR()\j, _AR()\i)\i
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
   ; V1.31.0: Push to gStorage[]
   gEvalStack(sp)\i = _AR()\i
   sp + 1
   pc + 1
EndProcedure

Procedure               C2FETCHS()
   vm_DebugFunctionName()
   ; V1.034.14: Unified FETCHS using _SLOT(j, offset)
   ; V1.035.13: Cache string length in \i for O(1) access
   gEvalStack(sp)\ss = _SLOT(_AR()\j, _AR()\i)\ss
   gEvalStack(sp)\i = Len(gEvalStack(sp)\ss)
   sp + 1
   pc + 1
EndProcedure

Procedure               C2FETCHF()
   vm_DebugFunctionName()
   ; V1.034.14: Unified FETCHF using _SLOT(j, offset)
   gEvalStack(sp)\f = _SLOT(_AR()\j, _AR()\i)\f
   sp + 1
   pc + 1
EndProcedure

Procedure               C2POP()
   vm_DebugFunctionName()
   sp - 1
   ; V1.034.14: Unified POP using _SLOT(j, offset)
   _SLOT(_AR()\j, _AR()\i)\i = gEvalStack(sp)\i
   pc + 1
EndProcedure

Procedure               C2POPS()
   vm_DebugFunctionName()
   sp - 1
   ; V1.034.14: Unified POPS using _SLOT(j, offset)
   _SLOT(_AR()\j, _AR()\i)\ss = gEvalStack(sp)\ss
   pc + 1
EndProcedure

Procedure               C2POPF()
   vm_DebugFunctionName()
   sp - 1
   ; V1.034.14: Unified POPF using _SLOT(j, offset)
   _SLOT(_AR()\j, _AR()\i)\f = gEvalStack(sp)\f
   pc + 1
EndProcedure

Procedure               C2PUSHS()
   vm_DebugFunctionName()
   ; V1.034.14: Unified PUSHS using _SLOT(j, offset) - same as FETCHS
   ; V1.035.13: Cache string length in \i for O(1) access
   gEvalStack(sp)\ss = _SLOT(_AR()\j, _AR()\i)\ss
   gEvalStack(sp)\i = Len(gEvalStack(sp)\ss)
   sp + 1
   pc + 1
EndProcedure

Procedure               C2PUSHF()
   vm_DebugFunctionName()
   ; V1.034.14: Unified PUSHF using _SLOT(j, offset) - same as FETCHF
   gEvalStack(sp)\f = _SLOT(_AR()\j, _AR()\i)\f
   sp + 1
   pc + 1
EndProcedure

Procedure               C2Store()
   vm_DebugFunctionName()
   sp - 1
   ; V1.034.14: Unified STORE using _SLOT(j, offset)
   ; TEMP DEBUG
   
   _SLOT(_AR()\j, _AR()\i)\i = gEvalStack(sp)\i
   pc + 1
EndProcedure

Procedure               C2STORES()
   vm_DebugFunctionName()
   sp - 1
   ; V1.034.14: Unified STORES using _SLOT(j, offset)
   _SLOT(_AR()\j, _AR()\i)\ss = gEvalStack(sp)\ss
   pc + 1
EndProcedure

Procedure               C2STOREF()
   vm_DebugFunctionName()
   sp - 1
   ; V1.034.14: Unified STOREF using _SLOT(j, offset)
   _SLOT(_AR()\j, _AR()\i)\f = gEvalStack(sp)\f
   pc + 1
EndProcedure

; V1.029.84: Store to struct variable - copies both \i and \ptr
; This fixes the issue where regular STORE only copies \i but StructGetStr accesses \ptr
; The stVT structure has separate \i and \ptr fields (not a union)
; Used when storing function return values to struct variables: p.Person = listGet(...)
; V1.034.14: Unified using _SLOT(j, offset) - replaces both STORE_STRUCT and LSTORE_STRUCT
Procedure               C2STORE_STRUCT()
   vm_DebugFunctionName()
   sp - 1

   ; Copy both integer value AND pointer field using unified _SLOT access
   _SLOT(_AR()\j, _AR()\i)\i = gEvalStack(sp)\i
   _SLOT(_AR()\j, _AR()\i)\ptr = gEvalStack(sp)\i  ; Copy \i to \ptr for pointer semantics

   pc + 1
EndProcedure

; V1.034.14: LSTORE_STRUCT now just calls unified STORE_STRUCT (jump table compatibility)
Procedure               C2LSTORE_STRUCT()
   vm_DebugFunctionName()
   sp - 1

   ; Copy both integer value AND pointer field using unified _SLOT access
   ; Note: For local structs, j should be 1 (set by codegen)
   _SLOT(_AR()\j, _AR()\i)\i = gEvalStack(sp)\i
   _SLOT(_AR()\j, _AR()\i)\ptr = gEvalStack(sp)\i

   pc + 1
EndProcedure

Procedure               C2MOV()
   vm_DebugFunctionName()
   ; V1.034.17: Unified MOV using _SLOT with locality flags in n field
   ; n & 1 = source is local, n & 2 = destination is local
   ; n=0: GG, n=1: LG, n=2: GL, n=3: LL

   CompilerIf #DEBUG
      Debug "MOV: pc=" + Str(pc) + " src[" + Str(_AR()\j) + "] -> dest[" + Str(_AR()\i) + "] n=" + Str(_AR()\n)
   CompilerEndIf

   _SLOT(_AR()\n >> 1, _AR()\i)\i = _SLOT(_AR()\n & 1, _AR()\j)\i

   pc + 1
EndProcedure

Procedure               C2MOVS()
   vm_DebugFunctionName()
   ; V1.034.17: Unified MOVS using _SLOT with locality flags in n field

   _SLOT(_AR()\n >> 1, _AR()\i)\ss = _SLOT(_AR()\n & 1, _AR()\j)\ss

   pc + 1
EndProcedure

Procedure               C2MOVF()
   vm_DebugFunctionName()
   ; V1.034.17: Unified MOVF using _SLOT with locality flags in n field

   _SLOT(_AR()\n >> 1, _AR()\i)\f = _SLOT(_AR()\n & 1, _AR()\j)\f

   pc + 1
EndProcedure

;- V1.31.0: Local Variable Opcodes (Isolated Variable System)
;  LMOV (GL - Global to Local): gVar[j] -> gLocal[gFrameBase + i]
;  LGMOV (LG - Local to Global): gLocal[gFrameBase + j] -> gVar[i]
;  LLMOV (LL - Local to Local): gLocal[gFrameBase + j] -> gLocal[gFrameBase + i]

Procedure               C2LMOV()
   vm_DebugFunctionName()
   ; V1.035.0: GL - Global to Local: *gVar[j]\var(0) -> *gVar[funcSlot]\var(i)
   *gVar(gCurrentFuncSlot)\var(_AR()\i)\i = *gVar(_AR()\j)\var(0)\i
   pc + 1
EndProcedure

Procedure               C2LMOVS()
   vm_DebugFunctionName()
   ; V1.035.0: GL - Global to Local: *gVar[j]\var(0) -> *gVar[funcSlot]\var(i)
   *gVar(gCurrentFuncSlot)\var(_AR()\i)\ss = *gVar(_AR()\j)\var(0)\ss
   pc + 1
EndProcedure

Procedure               C2LMOVF()
   vm_DebugFunctionName()
   ; V1.035.0: GL - Global to Local: *gVar[j]\var(0) -> *gVar[funcSlot]\var(i)
   *gVar(gCurrentFuncSlot)\var(_AR()\i)\f = *gVar(_AR()\j)\var(0)\f
   pc + 1
EndProcedure

;- V1.035.0: Local-to-Global MOV opcodes (LGMOV - LG)
Procedure               C2LGMOV()
   vm_DebugFunctionName()
   ; V1.035.0: LG - Local to Global: *gVar[funcSlot]\var(j) -> *gVar[i]\var(0)
   *gVar(_AR()\i)\var(0)\i = *gVar(gCurrentFuncSlot)\var(_AR()\j)\i
   pc + 1
EndProcedure

Procedure               C2LGMOVS()
   vm_DebugFunctionName()
   ; V1.035.0: LG - Local to Global: *gVar[funcSlot]\var(j) -> *gVar[i]\var(0)
   *gVar(_AR()\i)\var(0)\ss = *gVar(gCurrentFuncSlot)\var(_AR()\j)\ss
   pc + 1
EndProcedure

Procedure               C2LGMOVF()
   vm_DebugFunctionName()
   ; V1.035.0: LG - Local to Global: *gVar[funcSlot]\var(j) -> *gVar[i]\var(0)
   *gVar(_AR()\i)\var(0)\f = *gVar(gCurrentFuncSlot)\var(_AR()\j)\f
   pc + 1
EndProcedure

;- V1.31.0: Local-to-Local MOV opcodes (LLMOV - LL)
Procedure               C2LLMOV()
   vm_DebugFunctionName()
   ; V1.31.0: LL - Local to Local: gLocal[gFrameBase + j] -> gLocal[gFrameBase + i]
   *gVar(gCurrentFuncSlot)\var(_AR()\i)\i = *gVar(gCurrentFuncSlot)\var(_AR()\j)\i
   pc + 1
EndProcedure

Procedure               C2LLMOVS()
   vm_DebugFunctionName()
   ; V1.31.0: LL - Local to Local: gLocal[gFrameBase + j] -> gLocal[gFrameBase + i]
   *gVar(gCurrentFuncSlot)\var(_AR()\i)\ss = *gVar(gCurrentFuncSlot)\var(_AR()\j)\ss
   pc + 1
EndProcedure

Procedure               C2LLMOVF()
   vm_DebugFunctionName()
   ; V1.31.0: LL - Local to Local: gLocal[gFrameBase + j] -> gLocal[gFrameBase + i]
   *gVar(gCurrentFuncSlot)\var(_AR()\i)\f = *gVar(gCurrentFuncSlot)\var(_AR()\j)\f
   pc + 1
EndProcedure

Procedure               C2LLPMOV()
   vm_DebugFunctionName()
   ; V1.033.41: LL PMOV - Local to Local pointer move (copies i, ptr, ptrtype)
   *gVar(gCurrentFuncSlot)\var(_AR()\i)\i = *gVar(gCurrentFuncSlot)\var(_AR()\j)\i
   *gVar(gCurrentFuncSlot)\var(_AR()\i)\ptr = *gVar(gCurrentFuncSlot)\var(_AR()\j)\ptr
   *gVar(gCurrentFuncSlot)\var(_AR()\i)\ptrtype = *gVar(gCurrentFuncSlot)\var(_AR()\j)\ptrtype
   pc + 1
EndProcedure

Procedure               C2LFETCH()
   vm_DebugFunctionName()
   ; V1.035.0: Fetch from *gVar(gCurrentFuncSlot)\var(offset) to gEvalStack[]
   ; Note: LFETCH is local-specific, always uses gCurrentFuncSlot
   CompilerIf #DEBUG
      If gStackDepth >= 6
         Debug "  LFETCH: depth=" + Str(gStackDepth) + " funcSlot=" + Str(gCurrentFuncSlot) + " offset=" + Str(_AR()\i) + " value=" + Str(*gVar(gCurrentFuncSlot)\var(_AR()\i)\i) + " pc=" + Str(pc) + " sp=" + Str(sp)
      EndIf
   CompilerEndIf
   gEvalStack(sp)\i = *gVar(gCurrentFuncSlot)\var(_AR()\i)\i
   sp + 1
   pc + 1
EndProcedure

Procedure               C2LFETCHS()
   vm_DebugFunctionName()
   ; V1.31.0: Fetch string from gLocal[gFrameBase + offset] to gStorage[]
   ; V1.035.13: Cache string length in \i for O(1) access
   gEvalStack(sp)\ss = *gVar(gCurrentFuncSlot)\var(_AR()\i)\ss
   gEvalStack(sp)\i = Len(gEvalStack(sp)\ss)
   sp + 1
   pc + 1
EndProcedure

Procedure               C2LFETCHF()
   vm_DebugFunctionName()
   ; V1.31.0: Fetch float from gLocal[gFrameBase + offset] to gStorage[]
   gEvalStack(sp)\f = *gVar(gCurrentFuncSlot)\var(_AR()\i)\f
   sp + 1
   pc + 1
EndProcedure

Procedure               C2LSTORE()
   vm_DebugFunctionName()
   sp - 1
   ; V1.035.0: Store to *gVar(gCurrentFuncSlot)\var(offset) from gEvalStack[]
   ; Note: LSTORE is local-specific, always uses gCurrentFuncSlot
   CompilerIf #DEBUG
      ; V1.031.27: Bounds checking for debug builds
      ; V1.034.52: Fixed sp bounds check - sp is absolute index, not relative to eval stack
      If sp < 0 Or sp >= gMaxEvalStack
         Debug "*** LSTORE ERROR: sp=" + Str(sp) + " out of bounds [0.." + Str(gMaxEvalStack - 1) + "] at pc=" + Str(pc)
         gExitApplication = #True
         ProcedureReturn
      EndIf
      Debug "VM LSTORE: funcSlot=" + Str(gCurrentFuncSlot) + " offset=" + Str(_AR()\i) + " value=" + Str(gEvalStack(sp)\i)
   CompilerEndIf
   *gVar(gCurrentFuncSlot)\var(_AR()\i)\i = gEvalStack(sp)\i
   pc + 1
EndProcedure

Procedure               C2LSTORES()
   vm_DebugFunctionName()
   sp - 1
   ; V1.31.0: Store string to gLocal[gFrameBase + offset] from gStorage[]
   CompilerIf #DEBUG
      ; V1.034.52: Fixed sp bounds check - sp is absolute index, not relative to eval stack
      If sp < gGlobalStack Or sp >= gGlobalStack + gMaxEvalStack
         Debug "*** LSTORES ERROR: sp=" + Str(sp) + " out of bounds [" + Str(gGlobalStack) + ".." + Str(gGlobalStack + gMaxEvalStack - 1) + "] at pc=" + Str(pc)
         gExitApplication = #True
         ProcedureReturn
      EndIf
   CompilerEndIf
   *gVar(gCurrentFuncSlot)\var(_AR()\i)\ss = gEvalStack(sp)\ss
   pc + 1
EndProcedure

Procedure               C2LSTOREF()
   vm_DebugFunctionName()
   sp - 1
   ; V1.31.0: Store float to gLocal[gFrameBase + offset] from gStorage[]
   CompilerIf #DEBUG
      ; V1.034.52: Fixed sp bounds check - sp is absolute index, not relative to eval stack
      If sp < gGlobalStack Or sp >= gGlobalStack + gMaxEvalStack
         Debug "*** LSTOREF ERROR: sp=" + Str(sp) + " out of bounds [" + Str(gGlobalStack) + ".." + Str(gGlobalStack + gMaxEvalStack - 1) + "] at pc=" + Str(pc)
         gExitApplication = #True
         ProcedureReturn
      EndIf
   CompilerEndIf
   *gVar(gCurrentFuncSlot)\var(_AR()\i)\f = gEvalStack(sp)\f
   pc + 1
EndProcedure

;- In-place increment/decrement operations (efficient, no multi-operation sequences)

Procedure               C2INC_VAR()
   ; V1.034.14: Unified INC using _SLOT(j, offset)
   vm_DebugFunctionName()
   _SLOT(_AR()\j, _AR()\i)\i + 1
   pc + 1
EndProcedure

Procedure               C2DEC_VAR()
   ; V1.034.14: Unified DEC using _SLOT(j, offset)
   vm_DebugFunctionName()
   _SLOT(_AR()\j, _AR()\i)\i - 1
   pc + 1
EndProcedure

Procedure               C2INC_VAR_PRE()
   ; V1.034.14: Unified pre-increment using _SLOT(j, offset)
   vm_DebugFunctionName()
   _SLOT(_AR()\j, _AR()\i)\i + 1
   gEvalStack(sp)\i = _SLOT(_AR()\j, _AR()\i)\i
   sp + 1
   pc + 1
EndProcedure

Procedure               C2DEC_VAR_PRE()
   ; V1.034.14: Unified pre-decrement using _SLOT(j, offset)
   vm_DebugFunctionName()
   _SLOT(_AR()\j, _AR()\i)\i - 1
   gEvalStack(sp)\i = _SLOT(_AR()\j, _AR()\i)\i
   sp + 1
   pc + 1
EndProcedure

Procedure               C2INC_VAR_POST()
   ; V1.034.14: Unified post-increment using _SLOT(j, offset)
   vm_DebugFunctionName()
   gEvalStack(sp)\i = _SLOT(_AR()\j, _AR()\i)\i
   _SLOT(_AR()\j, _AR()\i)\i + 1
   sp + 1
   pc + 1
EndProcedure

Procedure               C2DEC_VAR_POST()
   ; V1.034.14: Unified post-decrement using _SLOT(j, offset)
   vm_DebugFunctionName()
   gEvalStack(sp)\i = _SLOT(_AR()\j, _AR()\i)\i
   _SLOT(_AR()\j, _AR()\i)\i - 1
   sp + 1
   pc + 1
EndProcedure

; V1.034.14: L-variants now use same unified _SLOT - kept for jump table compatibility
Procedure               C2LINC_VAR()
   ; V1.31.0: Local increment - gLocal[gFrameBase + offset]++
   vm_DebugFunctionName()
   *gVar(gCurrentFuncSlot)\var(_AR()\i)\i + 1
   pc + 1
EndProcedure

Procedure               C2LDEC_VAR()
   ; V1.31.0: Local decrement - gLocal[gFrameBase + offset]--
   vm_DebugFunctionName()
   *gVar(gCurrentFuncSlot)\var(_AR()\i)\i - 1
   pc + 1
EndProcedure

Procedure               C2LINC_VAR_PRE()
   ; V1.31.0: Local pre-increment - ++gLocal[gFrameBase + offset]
   vm_DebugFunctionName()
   *gVar(gCurrentFuncSlot)\var(_AR()\i)\i + 1
   gEvalStack(sp)\i = *gVar(gCurrentFuncSlot)\var(_AR()\i)\i
   sp + 1
   pc + 1
EndProcedure

Procedure               C2LDEC_VAR_PRE()
   ; V1.31.0: Local pre-decrement - --gLocal[gFrameBase + offset]
   vm_DebugFunctionName()
   *gVar(gCurrentFuncSlot)\var(_AR()\i)\i - 1
   gEvalStack(sp)\i = *gVar(gCurrentFuncSlot)\var(_AR()\i)\i
   sp + 1
   pc + 1
EndProcedure

Procedure               C2LINC_VAR_POST()
   ; V1.31.0: Local post-increment - gLocal[gFrameBase + offset]++
   vm_DebugFunctionName()
   gEvalStack(sp)\i = *gVar(gCurrentFuncSlot)\var(_AR()\i)\i
   *gVar(gCurrentFuncSlot)\var(_AR()\i)\i + 1
   sp + 1
   pc + 1
EndProcedure

Procedure               C2LDEC_VAR_POST()
   ; V1.31.0: Local post-decrement - gLocal[gFrameBase + offset]--
   vm_DebugFunctionName()
   gEvalStack(sp)\i = *gVar(gCurrentFuncSlot)\var(_AR()\i)\i
   *gVar(gCurrentFuncSlot)\var(_AR()\i)\i - 1
   sp + 1
   pc + 1
EndProcedure

;- In-place compound assignment operations (pop stack, operate, store - no push)

Procedure               C2ADD_ASSIGN_VAR()
   ; V1.31.0: Pop value from gStorage[], add to global, store back (no push)
   vm_DebugFunctionName()
   sp - 1
   _SLOT(_AR()\j, _AR()\i)\i + gEvalStack(sp)\i
   pc + 1
EndProcedure

Procedure               C2SUB_ASSIGN_VAR()
   ; V1.31.0: Pop value from gStorage[], subtract from global, store back (no push)
   vm_DebugFunctionName()
   sp - 1
   _SLOT(_AR()\j, _AR()\i)\i - gEvalStack(sp)\i
   pc + 1
EndProcedure

Procedure               C2MUL_ASSIGN_VAR()
   ; V1.31.0: Pop value from gStorage[], multiply global, store back (no push)
   vm_DebugFunctionName()
   sp - 1
   _SLOT(_AR()\j, _AR()\i)\i * gEvalStack(sp)\i
   pc + 1
EndProcedure

Procedure               C2DIV_ASSIGN_VAR()
   ; V1.31.0: Pop value from gStorage[], divide global, store back (no push)
   vm_DebugFunctionName()
   sp - 1
   _SLOT(_AR()\j, _AR()\i)\i / gEvalStack(sp)\i
   pc + 1
EndProcedure

Procedure               C2MOD_ASSIGN_VAR()
   ; V1.31.0: Pop value from gStorage[], modulo global, store back (no push)
   vm_DebugFunctionName()
   sp - 1
   _SLOT(_AR()\j, _AR()\i)\i % gEvalStack(sp)\i
   pc + 1
EndProcedure

Procedure               C2FLOATADD_ASSIGN_VAR()
   ; V1.31.0: Pop value from gStorage[], float add to global, store back (no push)
   vm_DebugFunctionName()
   sp - 1
   _SLOT(_AR()\j, _AR()\i)\f + gEvalStack(sp)\f
   pc + 1
EndProcedure

Procedure               C2FLOATSUB_ASSIGN_VAR()
   ; V1.31.0: Pop value from gStorage[], float subtract from global, store back (no push)
   vm_DebugFunctionName()
   sp - 1
   _SLOT(_AR()\j, _AR()\i)\f - gEvalStack(sp)\f
   pc + 1
EndProcedure

Procedure               C2FLOATMUL_ASSIGN_VAR()
   ; V1.31.0: Pop value from gStorage[], float multiply global, store back (no push)
   vm_DebugFunctionName()
   sp - 1
   _SLOT(_AR()\j, _AR()\i)\f * gEvalStack(sp)\f
   pc + 1
EndProcedure

Procedure               C2FLOATDIV_ASSIGN_VAR()
   ; V1.31.0: Pop value from gStorage[], float divide global, store back (no push)
   vm_DebugFunctionName()
   sp - 1
   _SLOT(_AR()\j, _AR()\i)\f / gEvalStack(sp)\f
   pc + 1
EndProcedure

Procedure               C2JMP()
   vm_DebugFunctionName()
   pc + _AR()\i
EndProcedure

Procedure               C2JZ()
   vm_DebugFunctionName()
   sp - 1
   ; V1.31.0: Read from gStorage[]
   If Not gEvalStack(sp)\i
      pc + _AR()\i
   Else
      pc + 1
   EndIf
EndProcedure

Procedure               C2TENIF()
   ; V1.31.0: Ternary IF - use gStorage[]
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
; V1.31.0: Updated for gStorage[]
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
   ; V1.035.13: Copy both string and cached length
   gEvalStack(sp)\ss = gEvalStack(sp - 1)\ss
   gEvalStack(sp)\i = gEvalStack(sp - 1)\i
   sp + 1
   pc + 1
EndProcedure

Procedure               C2JNZ()
   ; V1.31.0: Use gStorage[]
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

;- V1.035.16: Fused comparison-jump opcodes for loop optimization
; Pattern: FETCH + PUSH_IMM + CMP + JZ fused into single instruction
; Encoding: \ndx=slot, \j=immediate, \i=jump offset (FixJMP updates \i)
; Note: These use INVERTED condition (jump when OPPOSITE is true)
; e.g., JGE_VAR_IMM jumps when var >= imm (inverts LESS+JZ which exits when var < imm is false)

; Global variable versions - compare *gVar(slot)\var(0)\i with immediate
Procedure               C2JGE_VAR_IMM()
   vm_DebugFunctionName()
   If _GLOBAL(_AR()\ndx)\i >= _AR()\j
      pc + _AR()\i
   Else
      pc + 1
   EndIf
EndProcedure

Procedure               C2JGT_VAR_IMM()
   vm_DebugFunctionName()
   If _GLOBAL(_AR()\ndx)\i > _AR()\j
      pc + _AR()\i
   Else
      pc + 1
   EndIf
EndProcedure

Procedure               C2JLE_VAR_IMM()
   vm_DebugFunctionName()
   If _GLOBAL(_AR()\ndx)\i <= _AR()\j
      pc + _AR()\i
   Else
      pc + 1
   EndIf
EndProcedure

Procedure               C2JLT_VAR_IMM()
   vm_DebugFunctionName()
   If _GLOBAL(_AR()\ndx)\i < _AR()\j
      pc + _AR()\i
   Else
      pc + 1
   EndIf
EndProcedure

Procedure               C2JEQ_VAR_IMM()
   vm_DebugFunctionName()
   If _GLOBAL(_AR()\ndx)\i = _AR()\j
      pc + _AR()\i
   Else
      pc + 1
   EndIf
EndProcedure

Procedure               C2JNE_VAR_IMM()
   vm_DebugFunctionName()
   If _GLOBAL(_AR()\ndx)\i <> _AR()\j
      pc + _AR()\i
   Else
      pc + 1
   EndIf
EndProcedure

; Local variable versions - compare *gVar(gCurrentFuncSlot)\var(offset)\i with immediate
Procedure               C2JGE_LVAR_IMM()
   vm_DebugFunctionName()
   If _LOCALI(_AR()\ndx) >= _AR()\j
      pc + _AR()\i
   Else
      pc + 1
   EndIf
EndProcedure

Procedure               C2JGT_LVAR_IMM()
   vm_DebugFunctionName()
   If _LOCALI(_AR()\ndx) > _AR()\j
      pc + _AR()\i
   Else
      pc + 1
   EndIf
EndProcedure

Procedure               C2JLE_LVAR_IMM()
   vm_DebugFunctionName()
   If _LOCALI(_AR()\ndx) <= _AR()\j
      pc + _AR()\i
   Else
      pc + 1
   EndIf
EndProcedure

Procedure               C2JLT_LVAR_IMM()
   vm_DebugFunctionName()
   If _LOCALI(_AR()\ndx) < _AR()\j
      pc + _AR()\i
   Else
      pc + 1
   EndIf
EndProcedure

Procedure               C2JEQ_LVAR_IMM()
   vm_DebugFunctionName()
   If _LOCALI(_AR()\ndx) = _AR()\j
      pc + _AR()\i
   Else
      pc + 1
   EndIf
EndProcedure

Procedure               C2JNE_LVAR_IMM()
   vm_DebugFunctionName()
   If _LOCALI(_AR()\ndx) <> _AR()\j
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
   sp - 1
   ; V1.31.0: String concatenation on gStorage[]
   ; V1.035.13: Update cached length (sum of both lengths)
   gEvalStack(sp - 1)\ss = gEvalStack(sp - 1)\ss + gEvalStack(sp)\ss
   gEvalStack(sp - 1)\i = gEvalStack(sp - 1)\i + gEvalStack(sp)\i
   pc + 1
EndProcedure

Procedure               C2FTOS()
   vm_DebugFunctionName()
   ; V1.31.0: Convert float to string at gStorage[] top
   ; V1.035.13: Cache string length in \i
   gEvalStack(sp - 1)\ss = StrD(gEvalStack(sp - 1)\f, gDecs)
   gEvalStack(sp - 1)\i = Len(gEvalStack(sp - 1)\ss)
   pc + 1
EndProcedure

Procedure               C2ITOS()
   vm_DebugFunctionName()
   ; V1.31.0: Convert integer to string at gStorage[] top
   ; V1.035.13: Cache string length in \i
   gEvalStack(sp - 1)\ss = Str(gEvalStack(sp - 1)\i)
   gEvalStack(sp - 1)\i = Len(gEvalStack(sp - 1)\ss)
   pc + 1
EndProcedure

Procedure               C2ITOF()
   vm_DebugFunctionName()
   ; V1.31.0: Convert integer to float at gStorage[] top
   gEvalStack(sp - 1)\f = gEvalStack(sp - 1)\i
   gEvalStack(sp - 1)\ptr = 0
   gEvalStack(sp - 1)\ptrtype = 0
   pc + 1
EndProcedure

Procedure               C2FTOI_ROUND()
   vm_DebugFunctionName()
   ; V1.31.0: Convert float to integer at gStorage[] top (round to nearest)
   gEvalStack(sp - 1)\i = gEvalStack(sp - 1)\f
   pc + 1
EndProcedure

Procedure               C2FTOI_TRUNCATE()
   vm_DebugFunctionName()
   ; V1.31.0: Convert float to integer at gStorage[] top (truncate towards zero)
   gEvalStack(sp - 1)\i = Int(gEvalStack(sp - 1)\f)
   pc + 1
EndProcedure

Procedure               C2STOF()
   vm_DebugFunctionName()
   ; V1.31.0: Convert string to float at gStorage[] top
   gEvalStack(sp - 1)\f = ValD(gEvalStack(sp - 1)\ss)
   pc + 1
EndProcedure

Procedure               C2STOI()
   vm_DebugFunctionName()
   ; V1.31.0: Convert string to integer at gStorage[] top
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
; V1.31.0: Updated for gStorage[]
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

; V1.034.30: Bit shift operators
Procedure               C2SHL()
   vm_DebugFunctionName()
   vm_BitOperation( << )
EndProcedure

Procedure               C2SHR()
   vm_DebugFunctionName()
   vm_BitOperation( >> )
EndProcedure

Procedure               C2NOT()
   vm_DebugFunctionName()
   ; V1.31.0: Use gStorage[]
   gEvalStack(sp - 1)\i = Bool(Not gEvalStack(sp - 1)\i)
   pc + 1
EndProcedure

Procedure               C2NEGATE()
   vm_DebugFunctionName()
   ; V1.31.0: Use gStorage[]
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

; V1.31.0: Print operations updated for gStorage[]
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
   ; V1.31.0: Use gStorage[]
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
   ; V1.31.0: Tolerance-based float inequality using gStorage[]
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
   ; V1.31.0: Tolerance-based float equality using gStorage[]
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
   ; V1.035.0: POINTER ARRAY ARCHITECTURE
   ; Each function has its own slot in *gVar(funcSlot)
   ; Recursion: allocate new frame, swap pointer, restore on return
   vm_DebugFunctionName()
   Define i.l
   Define funcSlot.l, totalVars.l
   Define *newFrame.stVar

   ; Increment stack depth (create new frame)
   gStackDepth + 1

   CompilerIf #DEBUG
      If gStackDepth >= gFunctionStack
         Debug "*** FATAL ERROR: Stack overflow at pc=" + Str(pc) + " funcId=" + Str(_FUNCID)
         End
      EndIf
   CompilerEndIf

   ; V1.035.0: Get function slot from template
   funcSlot = _FUNCSLOT
   totalVars = _NPARAMS + _NLOCALS

   ; Save stack frame info
   gStack(gStackDepth)\pc = pc + 1 + _NLOCALARRAYS  ; Skip ARRAYINFO opcodes
   gStack(gStackDepth)\sp = sp - _NPARAMS           ; Save sp BEFORE params were pushed
   gStack(gStackDepth)\funcSlot = funcSlot          ; Which function slot we're using
   gStack(gStackDepth)\localCount = totalVars

   ; V1.034.64: Optimized with frame pool for fast recursion
   ; Ensure at least 1 slot to avoid negative array size
   Protected arraySize.i = totalVars
   If arraySize < 1 : arraySize = 1 : EndIf

   If gFuncActive(funcSlot)
      ; Recursion: use pooled frame if available and fits, else allocate
      If gFramePoolTop < gRecursionFrame And arraySize <= #FRAME_VAR_SIZE
         *newFrame = *gFramePool(gFramePoolTop)
         gFramePoolTop + 1
         gStack(gStackDepth)\isPooled = #True       ; Pooled, return to pool
         gStack(gStackDepth)\isAllocated = #False
      Else
         *newFrame = AllocateStructure(stVar)
         ReDim *newFrame\var(arraySize - 1)
         gStack(gStackDepth)\isPooled = #False
         gStack(gStackDepth)\isAllocated = #True    ; Allocated, must free
      EndIf
      gStack(gStackDepth)\savedFrame = *gVar(funcSlot)  ; Save original
      *gVar(funcSlot) = *newFrame
   Else
      ; First call: allocate/resize existing slot only if needed
      If Not *gVar(funcSlot)
         *gVar(funcSlot) = AllocateStructure(stVar)
         ReDim *gVar(funcSlot)\var(arraySize - 1)
      ElseIf ArraySize(*gVar(funcSlot)\var()) < arraySize - 1
         ReDim *gVar(funcSlot)\var(arraySize - 1)
      EndIf
      gStack(gStackDepth)\savedFrame = #Null
      gStack(gStackDepth)\isPooled = #False
      gStack(gStackDepth)\isAllocated = #False
      gFuncActive(funcSlot) = #True
   EndIf

   ; V1.034.63: Direct field copy for speed (CopyStructure stVT is too heavy)
   ; V1.034.66: Also copy pointer fields for pointer parameter support
   For i = 0 To _NPARAMS - 1
      *gVar(funcSlot)\var(i)\i = gEvalStack(sp - 1 - i)\i
      *gVar(funcSlot)\var(i)\f = gEvalStack(sp - 1 - i)\f
      *gVar(funcSlot)\var(i)\ss = gEvalStack(sp - 1 - i)\ss
      *gVar(funcSlot)\var(i)\ptr = gEvalStack(sp - 1 - i)\ptr
      *gVar(funcSlot)\var(i)\ptrtype = gEvalStack(sp - 1 - i)\ptrtype
   Next

   ; Preload non-parameter locals from function template - only if there are locals
   If _NLOCALS > 0 And _FUNCID >= 0 And _FUNCID <= ArraySize(gFuncTemplates())
      For i = 0 To gFuncTemplates(_FUNCID)\localCount - 1
         CopyStructure(gFuncTemplates(_FUNCID)\template(i), *gVar(funcSlot)\var(_NPARAMS + i), stVTSimple)
      Next
   EndIf

   ; V1.035.0: Pop params from eval stack, set current function slot
   sp = sp - _NPARAMS
   gCurrentFuncSlot = funcSlot
   gCallCount + 1

   ; Allocate local arrays using inline ARRAYINFO opcodes
   If _NLOCALARRAYS > 0
      CompilerIf #DEBUG
         Debug "  Allocating " + Str(_NLOCALARRAYS) + " local arrays"
      CompilerEndIf
      For i = 0 To _NLOCALARRAYS - 1
         If _ARRAYINFO_SIZE(i) > 0
            ReDim *gVar(funcSlot)\var(_ARRAYINFO_OFFSET(i))\dta\ar(_ARRAYINFO_SIZE(i) - 1)
            *gVar(funcSlot)\var(_ARRAYINFO_OFFSET(i))\dta\size = _ARRAYINFO_SIZE(i)
         EndIf
      Next
   EndIf

   pc = _PCADDR              ; Jump to function address
   gFunctionDepth + 1        ; Increment function depth counter

EndProcedure

; V1.035.0: Optimized CALL for 0 parameters - POINTER ARRAY ARCHITECTURE
Procedure               C2CALL0()
   vm_DebugFunctionName()
   Define i.l
   Define funcSlot.l, totalVars.l
   Define *newFrame.stVar

   gStackDepth + 1

   CompilerIf #DEBUG
      If gStackDepth >= gFunctionStack
         Debug "*** FATAL ERROR: Stack overflow at pc=" + Str(pc) + " funcId=" + Str(_FUNCID)
         End
      EndIf
   CompilerEndIf

   funcSlot = _FUNCSLOT
   totalVars = _NLOCALS  ; 0 params

   ; Save stack frame
   gStack(gStackDepth)\pc = pc + 1 + _NLOCALARRAYS
   gStack(gStackDepth)\sp = sp
   gStack(gStackDepth)\funcSlot = funcSlot
   gStack(gStackDepth)\localCount = totalVars

   ; V1.034.64: Optimized with frame pool for fast recursion
   Protected arraySize.i = totalVars
   If arraySize < 1 : arraySize = 1 : EndIf

   ; Handle recursion
   If gFuncActive(funcSlot)
      ; Recursion: use pooled frame if available and fits, else allocate
      If gFramePoolTop < gRecursionFrame And arraySize <= #FRAME_VAR_SIZE
         *newFrame = *gFramePool(gFramePoolTop)
         gFramePoolTop + 1
         gStack(gStackDepth)\isPooled = #True       ; Pooled, return to pool
         gStack(gStackDepth)\isAllocated = #False
      Else
         *newFrame = AllocateStructure(stVar)
         ReDim *newFrame\var(arraySize - 1)
         gStack(gStackDepth)\isPooled = #False
         gStack(gStackDepth)\isAllocated = #True    ; Allocated, must free
      EndIf
      gStack(gStackDepth)\savedFrame = *gVar(funcSlot)
      *gVar(funcSlot) = *newFrame
   Else
      If Not *gVar(funcSlot)
         *gVar(funcSlot) = AllocateStructure(stVar)
         ReDim *gVar(funcSlot)\var(arraySize - 1)
      ElseIf ArraySize(*gVar(funcSlot)\var()) < arraySize - 1
         ReDim *gVar(funcSlot)\var(arraySize - 1)
      EndIf
      gStack(gStackDepth)\savedFrame = #Null
      gStack(gStackDepth)\isPooled = #False
      gStack(gStackDepth)\isAllocated = #False
      gFuncActive(funcSlot) = #True
   EndIf

   ; Template preload (no params) - only if there are locals
   If _NLOCALS > 0 And _FUNCID >= 0 And _FUNCID <= ArraySize(gFuncTemplates())
      For i = 0 To gFuncTemplates(_FUNCID)\localCount - 1
         CopyStructure(gFuncTemplates(_FUNCID)\template(i), *gVar(funcSlot)\var(i), stVTSimple)
      Next
   EndIf

   gCurrentFuncSlot = funcSlot
   gCall0Count + 1

   CompilerIf #DEBUG
      Debug "CALL0: at pc=" + Str(pc) + " funcSlot=" + Str(funcSlot) + " jumping to pc=" + Str(_PCADDR) + " nArr=" + Str(_NLOCALARRAYS)
   CompilerEndIf

   ; Allocate local arrays
   If _NLOCALARRAYS > 0
      CompilerIf #DEBUG
         Debug "CALL0: Allocating " + Str(_NLOCALARRAYS) + " local arrays at pc=" + Str(pc) + " funcSlot=" + Str(funcSlot)
      CompilerEndIf
      For i = 0 To _NLOCALARRAYS - 1
         CompilerIf #DEBUG
            Debug "  Array " + Str(i) + ": offset=" + Str(_ARRAYINFO_OFFSET(i)) + " size=" + Str(_ARRAYINFO_SIZE(i))
         CompilerEndIf
         If _ARRAYINFO_SIZE(i) > 0
            ReDim *gVar(funcSlot)\var(_ARRAYINFO_OFFSET(i))\dta\ar(_ARRAYINFO_SIZE(i) - 1)
            *gVar(funcSlot)\var(_ARRAYINFO_OFFSET(i))\dta\size = _ARRAYINFO_SIZE(i)
            CompilerIf #DEBUG
               Debug "    Allocated: dta.size=" + Str(*gVar(funcSlot)\var(_ARRAYINFO_OFFSET(i))\dta\size)
            CompilerEndIf
         EndIf
      Next
   EndIf

   pc = _PCADDR
   gFunctionDepth + 1
EndProcedure

; V1.035.0: Optimized CALL for 1 parameter - POINTER ARRAY ARCHITECTURE
Procedure               C2CALL1()
   vm_DebugFunctionName()
   Define i.l
   Define funcSlot.l, totalVars.l
   Define *newFrame.stVar

   gStackDepth + 1

   CompilerIf #DEBUG
      If gStackDepth >= gFunctionStack
         Debug "*** FATAL ERROR: Stack overflow at pc=" + Str(pc) + " funcId=" + Str(_FUNCID)
         End
      EndIf
   CompilerEndIf

   funcSlot = _FUNCSLOT
   totalVars = 1 + _NLOCALS  ; Always >= 1, no size check needed

   gStack(gStackDepth)\pc = pc + 1 + _NLOCALARRAYS
   gStack(gStackDepth)\sp = sp - 1
   gStack(gStackDepth)\funcSlot = funcSlot
   gStack(gStackDepth)\localCount = totalVars

   ; Handle recursion - V1.034.64: Optimized with frame pool for fast recursion
   If gFuncActive(funcSlot)
      ; Recursion: use pooled frame if available and fits, else allocate
      If gFramePoolTop < gRecursionFrame And totalVars <= #FRAME_VAR_SIZE
         *newFrame = *gFramePool(gFramePoolTop)
         gFramePoolTop + 1
         gStack(gStackDepth)\isPooled = #True       ; Pooled, return to pool
         gStack(gStackDepth)\isAllocated = #False
      Else
         *newFrame = AllocateStructure(stVar)
         ReDim *newFrame\var(totalVars - 1)
         gStack(gStackDepth)\isPooled = #False
         gStack(gStackDepth)\isAllocated = #True    ; Allocated, must free
      EndIf
      gStack(gStackDepth)\savedFrame = *gVar(funcSlot)
      *gVar(funcSlot) = *newFrame
   Else
      If Not *gVar(funcSlot)
         *gVar(funcSlot) = AllocateStructure(stVar)
         ReDim *gVar(funcSlot)\var(totalVars - 1)
      ElseIf ArraySize(*gVar(funcSlot)\var()) < totalVars - 1
         ReDim *gVar(funcSlot)\var(totalVars - 1)
      EndIf
      gStack(gStackDepth)\savedFrame = #Null
      gStack(gStackDepth)\isPooled = #False
      gStack(gStackDepth)\isAllocated = #False
      gFuncActive(funcSlot) = #True
   EndIf

   ; V1.034.63: Direct field copy for speed (CopyStructure stVT is too heavy)
   ; V1.034.66: Also copy pointer fields for pointer parameter support
   *gVar(funcSlot)\var(0)\i = gEvalStack(sp - 1)\i
   *gVar(funcSlot)\var(0)\f = gEvalStack(sp - 1)\f
   *gVar(funcSlot)\var(0)\ss = gEvalStack(sp - 1)\ss
   *gVar(funcSlot)\var(0)\ptr = gEvalStack(sp - 1)\ptr
   *gVar(funcSlot)\var(0)\ptrtype = gEvalStack(sp - 1)\ptrtype

   ; Template preload - only if there are locals beyond params
   If _NLOCALS > 0 And _FUNCID >= 0 And _FUNCID <= ArraySize(gFuncTemplates())
      For i = 0 To gFuncTemplates(_FUNCID)\localCount - 1
         CopyStructure(gFuncTemplates(_FUNCID)\template(i), *gVar(funcSlot)\var(1 + i), stVTSimple)
      Next
   EndIf

   sp = sp - 1
   gCurrentFuncSlot = funcSlot

   If _NLOCALARRAYS > 0
      For i = 0 To _NLOCALARRAYS - 1
         If _ARRAYINFO_SIZE(i) > 0
            ReDim *gVar(funcSlot)\var(_ARRAYINFO_OFFSET(i))\dta\ar(_ARRAYINFO_SIZE(i) - 1)
            *gVar(funcSlot)\var(_ARRAYINFO_OFFSET(i))\dta\size = _ARRAYINFO_SIZE(i)
         EndIf
      Next
   EndIf

   pc = _PCADDR
   gFunctionDepth + 1
EndProcedure

; V1.035.0: Optimized CALL for 2 parameters - POINTER ARRAY ARCHITECTURE
Procedure               C2CALL2()
   vm_DebugFunctionName()
   Define i.l
   Define funcSlot.l, totalVars.l
   Define *newFrame.stVar

   gStackDepth + 1

   CompilerIf #DEBUG
      If gStackDepth >= gFunctionStack
         Debug "*** FATAL ERROR: Stack overflow at pc=" + Str(pc) + " funcId=" + Str(_FUNCID)
         End
      EndIf
   CompilerEndIf

   funcSlot = _FUNCSLOT
   totalVars = 2 + _NLOCALS  ; Always >= 2, no size check needed

   gStack(gStackDepth)\pc = pc + 1 + _NLOCALARRAYS
   gStack(gStackDepth)\sp = sp - 2
   gStack(gStackDepth)\funcSlot = funcSlot
   gStack(gStackDepth)\localCount = totalVars

   ; Handle recursion - V1.034.64: Optimized with frame pool for fast recursion
   If gFuncActive(funcSlot)
      ; Recursion: use pooled frame if available and fits, else allocate
      If gFramePoolTop < gRecursionFrame And totalVars <= #FRAME_VAR_SIZE
         *newFrame = *gFramePool(gFramePoolTop)
         gFramePoolTop + 1
         gStack(gStackDepth)\isPooled = #True       ; Pooled, return to pool
         gStack(gStackDepth)\isAllocated = #False
      Else
         *newFrame = AllocateStructure(stVar)
         ReDim *newFrame\var(totalVars - 1)
         gStack(gStackDepth)\isPooled = #False
         gStack(gStackDepth)\isAllocated = #True    ; Allocated, must free
      EndIf
      gStack(gStackDepth)\savedFrame = *gVar(funcSlot)
      *gVar(funcSlot) = *newFrame
   Else
      If Not *gVar(funcSlot)
         *gVar(funcSlot) = AllocateStructure(stVar)
         ReDim *gVar(funcSlot)\var(totalVars - 1)
      ElseIf ArraySize(*gVar(funcSlot)\var()) < totalVars - 1
         ReDim *gVar(funcSlot)\var(totalVars - 1)
      EndIf
      gStack(gStackDepth)\savedFrame = #Null
      gStack(gStackDepth)\isPooled = #False
      gStack(gStackDepth)\isAllocated = #False
      gFuncActive(funcSlot) = #True
   EndIf

   ; V1.034.63: Direct field copy for speed (CopyStructure stVT is too heavy)
   ; V1.034.66: Also copy pointer fields for pointer parameter support
   *gVar(funcSlot)\var(0)\i = gEvalStack(sp - 1)\i
   *gVar(funcSlot)\var(0)\f = gEvalStack(sp - 1)\f
   *gVar(funcSlot)\var(0)\ss = gEvalStack(sp - 1)\ss
   *gVar(funcSlot)\var(0)\ptr = gEvalStack(sp - 1)\ptr
   *gVar(funcSlot)\var(0)\ptrtype = gEvalStack(sp - 1)\ptrtype
   *gVar(funcSlot)\var(1)\i = gEvalStack(sp - 2)\i
   *gVar(funcSlot)\var(1)\f = gEvalStack(sp - 2)\f
   *gVar(funcSlot)\var(1)\ss = gEvalStack(sp - 2)\ss
   *gVar(funcSlot)\var(1)\ptr = gEvalStack(sp - 2)\ptr
   *gVar(funcSlot)\var(1)\ptrtype = gEvalStack(sp - 2)\ptrtype

   ; Template preload - only if there are locals beyond params
   If _NLOCALS > 0 And _FUNCID >= 0 And _FUNCID <= ArraySize(gFuncTemplates())
      For i = 0 To gFuncTemplates(_FUNCID)\localCount - 1
         CopyStructure(gFuncTemplates(_FUNCID)\template(i), *gVar(funcSlot)\var(2 + i), stVTSimple)
      Next
   EndIf

   sp = sp - 2
   gCurrentFuncSlot = funcSlot

   If _NLOCALARRAYS > 0
      For i = 0 To _NLOCALARRAYS - 1
         If _ARRAYINFO_SIZE(i) > 0
            ReDim *gVar(funcSlot)\var(_ARRAYINFO_OFFSET(i))\dta\ar(_ARRAYINFO_SIZE(i) - 1)
            *gVar(funcSlot)\var(_ARRAYINFO_OFFSET(i))\dta\size = _ARRAYINFO_SIZE(i)
         EndIf
      Next
   EndIf

   pc = _PCADDR
   gFunctionDepth + 1
EndProcedure

; V1.034.65: CALL_REC - Optimized recursive call (always uses frame pool)
; Used by compiler when function calls itself directly
; No gFuncActive check needed - we KNOW the function is active (it's calling itself)
Procedure               C2CALL_REC()
   vm_DebugFunctionName()
   Define i.l
   Define funcSlot.l, totalVars.l
   Define *newFrame.stVar

   gStackDepth + 1

   CompilerIf #DEBUG
      If gStackDepth >= gFunctionStack
         Debug "*** FATAL ERROR: Stack overflow at pc=" + Str(pc) + " funcId=" + Str(_FUNCID)
         End
      EndIf
   CompilerEndIf

   funcSlot = _FUNCSLOT
   totalVars = _NPARAMS + _NLOCALS

   ; Save stack frame
   gStack(gStackDepth)\pc = pc + 1 + _NLOCALARRAYS
   gStack(gStackDepth)\sp = sp - _NPARAMS
   gStack(gStackDepth)\funcSlot = funcSlot
   gStack(gStackDepth)\localCount = totalVars

   ; Always use frame pool for recursive calls (fast path)
   Protected arraySize.i = totalVars
   If arraySize < 1 : arraySize = 1 : EndIf

   If gFramePoolTop < gRecursionFrame And arraySize <= #FRAME_VAR_SIZE
      *newFrame = *gFramePool(gFramePoolTop)
      gFramePoolTop + 1
      gStack(gStackDepth)\isPooled = #True
      gStack(gStackDepth)\isAllocated = #False
   Else
      ; Pool exhausted or frame too large - allocate dynamically
      *newFrame = AllocateStructure(stVar)
      ReDim *newFrame\var(arraySize - 1)
      gStack(gStackDepth)\isPooled = #False
      gStack(gStackDepth)\isAllocated = #True
   EndIf
   gStack(gStackDepth)\savedFrame = *gVar(funcSlot)
   *gVar(funcSlot) = *newFrame

   ; Copy params from eval stack
   ; V1.034.66: Also copy pointer fields for pointer parameter support
   For i = 0 To _NPARAMS - 1
      *gVar(funcSlot)\var(i)\i = gEvalStack(sp - 1 - i)\i
      *gVar(funcSlot)\var(i)\f = gEvalStack(sp - 1 - i)\f
      *gVar(funcSlot)\var(i)\ss = gEvalStack(sp - 1 - i)\ss
      *gVar(funcSlot)\var(i)\ptr = gEvalStack(sp - 1 - i)\ptr
      *gVar(funcSlot)\var(i)\ptrtype = gEvalStack(sp - 1 - i)\ptrtype
   Next

   ; Preload locals from template
   If _NLOCALS > 0 And _FUNCID >= 0 And _FUNCID <= ArraySize(gFuncTemplates())
      For i = 0 To gFuncTemplates(_FUNCID)\localCount - 1
         CopyStructure(gFuncTemplates(_FUNCID)\template(i), *gVar(funcSlot)\var(_NPARAMS + i), stVTSimple)
      Next
   EndIf

   sp = sp - _NPARAMS
   gCurrentFuncSlot = funcSlot

   ; Allocate local arrays
   If _NLOCALARRAYS > 0
      For i = 0 To _NLOCALARRAYS - 1
         If _ARRAYINFO_SIZE(i) > 0
            ReDim *gVar(funcSlot)\var(_ARRAYINFO_OFFSET(i))\dta\ar(_ARRAYINFO_SIZE(i) - 1)
            *gVar(funcSlot)\var(_ARRAYINFO_OFFSET(i))\dta\size = _ARRAYINFO_SIZE(i)
         EndIf
      Next
   EndIf

   pc = _PCADDR
   gFunctionDepth + 1
EndProcedure

; V1.035.0: POINTER ARRAY ARCHITECTURE - cleanup macro for function locals
Macro _CLEANUP_FUNC_LOCALS(funcSlot, count)
   For _i = 0 To (count) - 1
      *gVar(funcSlot)\var(_i)\ss = ""
      If *gVar(funcSlot)\var(_i)\dta\size > 0
         ReDim *gVar(funcSlot)\var(_i)\dta\ar(0)
         *gVar(funcSlot)\var(_i)\dta\size = 0
      EndIf
   Next
EndMacro

Procedure               C2Return()
   ; V1.035.0: POINTER ARRAY ARCHITECTURE
   vm_DebugFunctionName()
   Define _i.l, _retval.i = 0
   Define funcSlot.l, *savedFrame.stVar

   ; Get return value from eval stack if present
   If sp > gStack(gStackDepth)\sp
      _retval = _POPI
   EndIf

   ; Get function slot from stack frame
   funcSlot = gStack(gStackDepth)\funcSlot

   CompilerIf #DEBUG
      Debug "RETURN: from funcSlot=" + Str(funcSlot) + " returning to pc=" + Str(gStack(gStackDepth)\pc) + " depth=" + Str(gStackDepth)
   CompilerEndIf

   ; Clear local slots (strings/arrays for GC)
   _CLEANUP_FUNC_LOCALS(funcSlot, gStack(gStackDepth)\localCount)

   ; Restore caller's pc and sp
   pc = gStack(gStackDepth)\pc
   sp = gStack(gStackDepth)\sp

   ; V1.034.64: Handle recursion cleanup with frame pool support
   If gStack(gStackDepth)\isPooled
      ; Pooled frame - return to pool
      gFramePoolTop - 1
      *savedFrame = gStack(gStackDepth)\savedFrame
      *gVar(funcSlot) = *savedFrame
   ElseIf gStack(gStackDepth)\isAllocated
      ; Dynamically allocated frame - free it and restore original
      *savedFrame = gStack(gStackDepth)\savedFrame
      FreeStructure(*gVar(funcSlot))
      *gVar(funcSlot) = *savedFrame
   Else
      ; First call frame - mark slot as inactive
      gFuncActive(funcSlot) = #False
   EndIf

   ; Restore caller's function slot (or 0 if returning to global)
   If gStackDepth > 0
      gCurrentFuncSlot = gStack(gStackDepth - 1)\funcSlot
   Else
      gCurrentFuncSlot = 0
   EndIf

   gStackDepth - 1
   gFunctionDepth - 1

   ; Push return value
   gEvalStack(sp)\i = _retval
   sp + 1
EndProcedure

Procedure               C2ReturnF()
   ; V1.035.0: POINTER ARRAY ARCHITECTURE
   vm_DebugFunctionName()
   Define _i.l, _retval.d = 0.0
   Define funcSlot.l, *savedFrame.stVar

   ; Get return value from eval stack if present
   If sp > gStack(gStackDepth)\sp
      _retval = _POPF
   EndIf

   funcSlot = gStack(gStackDepth)\funcSlot

   CompilerIf #DEBUG
      ;PrintN("RETURNF: from funcSlot=" + Str(funcSlot) + " returning to pc=" + Str(gStack(gStackDepth)\pc) + " depth=" + Str(gStackDepth))
   CompilerEndIf

   _CLEANUP_FUNC_LOCALS(funcSlot, gStack(gStackDepth)\localCount)

   pc = gStack(gStackDepth)\pc
   sp = gStack(gStackDepth)\sp

   ; V1.034.64: Handle recursion cleanup with frame pool support
   If gStack(gStackDepth)\isPooled
      ; Pooled frame - return to pool
      gFramePoolTop - 1
      *savedFrame = gStack(gStackDepth)\savedFrame
      *gVar(funcSlot) = *savedFrame
   ElseIf gStack(gStackDepth)\isAllocated
      *savedFrame = gStack(gStackDepth)\savedFrame
      FreeStructure(*gVar(funcSlot))
      *gVar(funcSlot) = *savedFrame
   Else
      gFuncActive(funcSlot) = #False
   EndIf

   If gStackDepth > 0
      gCurrentFuncSlot = gStack(gStackDepth - 1)\funcSlot
   Else
      gCurrentFuncSlot = 0
   EndIf

   gStackDepth - 1
   gFunctionDepth - 1

   gEvalStack(sp)\f = _retval
   sp + 1
EndProcedure

Procedure               C2ReturnS()
   ; V1.035.0: POINTER ARRAY ARCHITECTURE
   vm_DebugFunctionName()
   Define _i.l, _retval.s = ""
   Define funcSlot.l, *savedFrame.stVar

   ; Get return value from eval stack if present
   If sp > gStack(gStackDepth)\sp
      _retval = _POPS
   EndIf

   funcSlot = gStack(gStackDepth)\funcSlot
   _CLEANUP_FUNC_LOCALS(funcSlot, gStack(gStackDepth)\localCount)

   pc = gStack(gStackDepth)\pc
   sp = gStack(gStackDepth)\sp

   If gStack(gStackDepth)\isAllocated
      *savedFrame = gStack(gStackDepth)\savedFrame
      FreeStructure(*gVar(funcSlot))
      *gVar(funcSlot) = *savedFrame
   Else
      gFuncActive(funcSlot) = #False
   EndIf

   If gStackDepth > 0
      gCurrentFuncSlot = gStack(gStackDepth - 1)\funcSlot
   Else
      gCurrentFuncSlot = 0
   EndIf

   gStackDepth - 1
   gFunctionDepth - 1

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
XIncludeFile "c2-builtins-v09.pbi"

;- V1.039.45: Include System/Utility Built-in Functions Module
XIncludeFile "c2-builtins-system-v01.pbi"

;- Include Array Operations Module
XIncludeFile "c2-arrays-v08.pbi"

;- Include Pointer Operations Module
XIncludeFile "c2-pointers-v07.pbi"

;- Include Collections Module (V1.028.0 - Unified in gVar)
XIncludeFile "c2-collections-v05.pbi"

;- End VM functions

; IDE Options = PureBasic 6.21 (Windows - x64)
; CursorPosition = 266
; FirstLine = 256
; Folding = ------------------------------
; EnableAsm
; EnableThread
; EnableXP
; CPU = 1
; EnablePurifier
; EnableCompileCount = 0
; EnableBuildCount = 0
; EnableExeConstant