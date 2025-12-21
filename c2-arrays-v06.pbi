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
; Array Operations Module
; Version: 06
;
; V1.033.5: Major refactoring:
;   - Option 1: Added PURE variants without ptrtype checks
;   - Option 2: Moved all bounds checking to CompilerIf #DEBUG
;   - Option 3: Used macros to reduce code repetition
;

;- Array Operations

; ============================================================================
; ARRAY MACROS
; ============================================================================
; Base macros:
;   _ELEMSIZE     - Element size in slots (_AR()\j for structs, usually 1)
;   _ARRAYSIZE    - Array size from instruction (_AR()\n)
;   _GARR(slot)   - Global array at slot: gVar(slot)\dta\ar
;   _GARRSIZE(slot) - Global array size: gVar(slot)\dta\size
;   _LARR(offset) - Local array at offset: gLocal(gLocalBase+offset)\dta\ar
;   _LARRSIZE(offset) - Local array size
;   _LARRAY(offset) - Local slot calculation: gLocalBase + offset
; ============================================================================

Macro _ELEMSIZE : _AR()\j : EndMacro
Macro _ARRAYSIZE : _AR()\n : EndMacro
Macro _GARR(slot) : gVar(slot)\dta\ar : EndMacro
Macro _GARRSIZE(slot) : gVar(slot)\dta\size : EndMacro
Macro _LARR(offset) : gLocal(gLocalBase + (offset))\dta\ar : EndMacro
Macro _LARRSIZE(offset) : gLocal(gLocalBase + (offset))\dta\size : EndMacro

; ============================================================================
; DEBUG BOUNDS CHECKING MACROS
; All bounds checking is now DEBUG-only (Option 2)
; ============================================================================

Macro _CheckGlobalBounds(arrIdx, index)
   CompilerIf #DEBUG
      If index < 0 Or index >= gVar(arrIdx)\dta\size
         Debug "Array index out of bounds: " + Str(index) + " (size: " + Str(gVar(arrIdx)\dta\size) + ") at pc=" + Str(pc)
         gExitApplication = #True
         ProcedureReturn
      EndIf
   CompilerEndIf
EndMacro

Macro _CheckLocalBounds(localSlot, index)
   CompilerIf #DEBUG
      If gLocal(localSlot)\dta\size = 0
         Debug "Local array at slot " + Str(localSlot) + " not allocated! pc=" + Str(pc)
         gExitApplication = #True
         ProcedureReturn
      EndIf
      If index < 0 Or index >= gLocal(localSlot)\dta\size
         Debug "Local array index out of bounds: " + Str(index) + " (size: " + Str(gLocal(localSlot)\dta\size) + ") at pc=" + Str(pc)
         gExitApplication = #True
         ProcedureReturn
      EndIf
   CompilerEndIf
EndMacro

; ============================================================================
; PTRTYPE HANDLING MACROS
; Regular versions copy ptrtype; PURE versions skip it entirely (Option 1)
; ============================================================================

Macro _CopyPtrTypeFromGlobalArray(arrIdx, index)
   If gVar(arrIdx)\dta\ar(index)\ptrtype
      gEvalStack(sp)\ptr = gVar(arrIdx)\dta\ar(index)\ptr
      gEvalStack(sp)\ptrtype = gVar(arrIdx)\dta\ar(index)\ptrtype
   Else
      gEvalStack(sp)\ptrtype = 0
   EndIf
EndMacro

Macro _CopyPtrTypeFromLocalArray(localSlot, index)
   If gLocal(localSlot)\dta\ar(index)\ptrtype
      gEvalStack(sp)\ptr = gLocal(localSlot)\dta\ar(index)\ptr
      gEvalStack(sp)\ptrtype = gLocal(localSlot)\dta\ar(index)\ptrtype
   Else
      gEvalStack(sp)\ptrtype = 0
   EndIf
EndMacro

Macro _CopyPtrTypeToGlobalArray(arrIdx, index, srcSlot, isLocal)
   CompilerIf isLocal
      If gLocal(srcSlot)\ptrtype
         gVar(arrIdx)\dta\ar(index)\ptr = gLocal(srcSlot)\ptr
         gVar(arrIdx)\dta\ar(index)\ptrtype = gLocal(srcSlot)\ptrtype
      EndIf
   CompilerElse
      If gVar(srcSlot)\ptrtype
         gVar(arrIdx)\dta\ar(index)\ptr = gVar(srcSlot)\ptr
         gVar(arrIdx)\dta\ar(index)\ptrtype = gVar(srcSlot)\ptrtype
      EndIf
   CompilerEndIf
EndMacro

Macro _CopyPtrTypeFromStack(arrIdx, index)
   If gEvalStack(sp)\ptrtype
      gVar(arrIdx)\dta\ar(index)\ptr = gEvalStack(sp)\ptr
      gVar(arrIdx)\dta\ar(index)\ptrtype = gEvalStack(sp)\ptrtype
   EndIf
EndMacro

; ============================================================================
; ARRAYINDEX - Compute element index for multi-dimensional or struct arrays
; ============================================================================

Procedure C2ARRAYINDEX()
   ; Stack: index → computed element index
   vm_DebugFunctionName()
   sp - 1
   gEvalStack(sp)\i = gEvalStack(sp)\i * _ELEMSIZE
   sp + 1
   pc + 1
EndProcedure

; ============================================================================
; GENERIC ARRAYFETCH/ARRAYSTORE (fallback - not optimized)
; ============================================================================

Procedure C2ARRAYFETCH()
   ; Generic array fetch - copies entire stVTSimple to stack
   Define _idx.i
   vm_DebugFunctionName()

   If _AR()\ndx >= 0
      _idx = gVar(_AR()\ndx)\i
   Else
      sp - 1
      _idx = gEvalStack(sp)\i
   EndIf

   If _AR()\j  ; isLocal flag in \j
      CopyStructure(gEvalStack(sp), gLocal(_LARRAY(_AR()\i))\dta\ar(_idx), stVTSimple)
   Else
      CopyStructure(gEvalStack(sp), gVar(_AR()\i)\dta\ar(_idx), stVTSimple)
   EndIf

   sp + 1
   pc + 1
EndProcedure

Procedure C2ARRAYSTORE()
   ; Generic array store - copies from stack to array element
   Define _idx.i
   vm_DebugFunctionName()

   If _AR()\ndx >= 0
      _idx = gVar(_AR()\ndx)\i
      sp - 1
   Else
      sp - 1
      _idx = gEvalStack(sp)\i
      sp - 1
   EndIf

   If _AR()\j  ; isLocal flag
      CopyStructure(gLocal(_LARRAY(_AR()\i))\dta\ar(_idx), gEvalStack(sp), stVTSimple)
   Else
      CopyStructure(gVar(_AR()\i)\dta\ar(_idx), gEvalStack(sp), stVTSimple)
   EndIf

   pc + 1
EndProcedure

; ============================================================================
; ARRAYFETCH - INTEGER - GLOBAL
; ============================================================================

; Global array, optimized index (from global variable)
Procedure C2ARRAYFETCH_INT_GLOBAL_OPT()
   Protected arrIdx.i = _AR()\i
   Protected index.i = gVar(_AR()\ndx)\i
   vm_DebugFunctionName()
   _CheckGlobalBounds(arrIdx, index)
   gEvalStack(sp)\i = gVar(arrIdx)\dta\ar(index)\i
   _CopyPtrTypeFromGlobalArray(arrIdx, index)
   sp + 1
   pc + 1
EndProcedure

; PURE version - no ptrtype handling
Procedure C2ARRAYFETCH_INT_GLOBAL_OPT_PURE()
   Protected arrIdx.i = _AR()\i
   Protected index.i = gVar(_AR()\ndx)\i
   vm_DebugFunctionName()
   _CheckGlobalBounds(arrIdx, index)
   gEvalStack(sp)\i = gVar(arrIdx)\dta\ar(index)\i
   sp + 1
   pc + 1
EndProcedure

; Global array, stack index
Procedure C2ARRAYFETCH_INT_GLOBAL_STACK()
   Protected arrIdx.i = _AR()\i
   vm_DebugFunctionName()
   sp - 1
   Protected index.i = gEvalStack(sp)\i
   _CheckGlobalBounds(arrIdx, index)
   gEvalStack(sp)\i = gVar(arrIdx)\dta\ar(index)\i
   _CopyPtrTypeFromGlobalArray(arrIdx, index)
   sp + 1
   pc + 1
EndProcedure

; PURE version
Procedure C2ARRAYFETCH_INT_GLOBAL_STACK_PURE()
   Protected arrIdx.i = _AR()\i
   vm_DebugFunctionName()
   sp - 1
   Protected index.i = gEvalStack(sp)\i
   _CheckGlobalBounds(arrIdx, index)
   gEvalStack(sp)\i = gVar(arrIdx)\dta\ar(index)\i
   sp + 1
   pc + 1
EndProcedure

; Global array, local optimized index
Procedure C2ARRAYFETCH_INT_GLOBAL_LOPT()
   Protected arrIdx.i = _AR()\i
   Protected localSlot.i = _LARRAY(_AR()\ndx)
   Protected index.i = gLocal(localSlot)\i
   vm_DebugFunctionName()
   _CheckGlobalBounds(arrIdx, index)
   gEvalStack(sp)\i = gVar(arrIdx)\dta\ar(index)\i
   _CopyPtrTypeFromGlobalArray(arrIdx, index)
   sp + 1
   pc + 1
EndProcedure

; PURE version
Procedure C2ARRAYFETCH_INT_GLOBAL_LOPT_PURE()
   Protected arrIdx.i = _AR()\i
   Protected localSlot.i = _LARRAY(_AR()\ndx)
   Protected index.i = gLocal(localSlot)\i
   vm_DebugFunctionName()
   _CheckGlobalBounds(arrIdx, index)
   gEvalStack(sp)\i = gVar(arrIdx)\dta\ar(index)\i
   sp + 1
   pc + 1
EndProcedure

; ============================================================================
; ARRAYFETCH - INTEGER - LOCAL
; ============================================================================

; Local array, global optimized index
Procedure C2ARRAYFETCH_INT_LOCAL_OPT()
   Protected localSlot.i = _LARRAY(_AR()\i)
   Protected index.i = gVar(_AR()\ndx)\i
   vm_DebugFunctionName()
   _CheckLocalBounds(localSlot, index)
   gEvalStack(sp)\i = gLocal(localSlot)\dta\ar(index)\i
   _CopyPtrTypeFromLocalArray(localSlot, index)
   sp + 1
   pc + 1
EndProcedure

; PURE version
Procedure C2ARRAYFETCH_INT_LOCAL_OPT_PURE()
   Protected localSlot.i = _LARRAY(_AR()\i)
   Protected index.i = gVar(_AR()\ndx)\i
   vm_DebugFunctionName()
   _CheckLocalBounds(localSlot, index)
   gEvalStack(sp)\i = gLocal(localSlot)\dta\ar(index)\i
   sp + 1
   pc + 1
EndProcedure

; Local array, stack index
Procedure C2ARRAYFETCH_INT_LOCAL_STACK()
   Protected localSlot.i = _LARRAY(_AR()\i)
   vm_DebugFunctionName()
   sp - 1
   Protected index.i = gEvalStack(sp)\i
   _CheckLocalBounds(localSlot, index)
   gEvalStack(sp)\i = gLocal(localSlot)\dta\ar(index)\i
   _CopyPtrTypeFromLocalArray(localSlot, index)
   sp + 1
   pc + 1
EndProcedure

; PURE version
Procedure C2ARRAYFETCH_INT_LOCAL_STACK_PURE()
   Protected localSlot.i = _LARRAY(_AR()\i)
   vm_DebugFunctionName()
   sp - 1
   Protected index.i = gEvalStack(sp)\i
   _CheckLocalBounds(localSlot, index)
   gEvalStack(sp)\i = gLocal(localSlot)\dta\ar(index)\i
   sp + 1
   pc + 1
EndProcedure

; Local array, local optimized index
Procedure C2ARRAYFETCH_INT_LOCAL_LOPT()
   Protected arrSlot.i = _LARRAY(_AR()\i)
   Protected idxSlot.i = _LARRAY(_AR()\ndx)
   Protected index.i = gLocal(idxSlot)\i
   vm_DebugFunctionName()
   _CheckLocalBounds(arrSlot, index)
   gEvalStack(sp)\i = gLocal(arrSlot)\dta\ar(index)\i
   _CopyPtrTypeFromLocalArray(arrSlot, index)
   sp + 1
   pc + 1
EndProcedure

; PURE version
Procedure C2ARRAYFETCH_INT_LOCAL_LOPT_PURE()
   Protected arrSlot.i = _LARRAY(_AR()\i)
   Protected idxSlot.i = _LARRAY(_AR()\ndx)
   Protected index.i = gLocal(idxSlot)\i
   vm_DebugFunctionName()
   _CheckLocalBounds(arrSlot, index)
   gEvalStack(sp)\i = gLocal(arrSlot)\dta\ar(index)\i
   sp + 1
   pc + 1
EndProcedure

; ============================================================================
; ARRAYFETCH - FLOAT - GLOBAL
; ============================================================================

Procedure C2ARRAYFETCH_FLOAT_GLOBAL_OPT()
   Protected arrIdx.i = _AR()\i
   Protected index.i = gVar(_AR()\ndx)\i
   vm_DebugFunctionName()
   _CheckGlobalBounds(arrIdx, index)
   gEvalStack(sp)\f = gVar(arrIdx)\dta\ar(index)\f
   sp + 1
   pc + 1
EndProcedure

Procedure C2ARRAYFETCH_FLOAT_GLOBAL_STACK()
   Protected arrIdx.i = _AR()\i
   vm_DebugFunctionName()
   sp - 1
   Protected index.i = gEvalStack(sp)\i
   _CheckGlobalBounds(arrIdx, index)
   gEvalStack(sp)\f = gVar(arrIdx)\dta\ar(index)\f
   sp + 1
   pc + 1
EndProcedure

Procedure C2ARRAYFETCH_FLOAT_GLOBAL_LOPT()
   Protected arrIdx.i = _AR()\i
   Protected localSlot.i = _LARRAY(_AR()\ndx)
   Protected index.i = gLocal(localSlot)\i
   vm_DebugFunctionName()
   _CheckGlobalBounds(arrIdx, index)
   gEvalStack(sp)\f = gVar(arrIdx)\dta\ar(index)\f
   sp + 1
   pc + 1
EndProcedure

; ============================================================================
; ARRAYFETCH - FLOAT - LOCAL
; ============================================================================

Procedure C2ARRAYFETCH_FLOAT_LOCAL_OPT()
   Protected localSlot.i = _LARRAY(_AR()\i)
   Protected index.i = gVar(_AR()\ndx)\i
   vm_DebugFunctionName()
   _CheckLocalBounds(localSlot, index)
   gEvalStack(sp)\f = gLocal(localSlot)\dta\ar(index)\f
   sp + 1
   pc + 1
EndProcedure

Procedure C2ARRAYFETCH_FLOAT_LOCAL_STACK()
   Protected localSlot.i = _LARRAY(_AR()\i)
   vm_DebugFunctionName()
   sp - 1
   Protected index.i = gEvalStack(sp)\i
   _CheckLocalBounds(localSlot, index)
   gEvalStack(sp)\f = gLocal(localSlot)\dta\ar(index)\f
   sp + 1
   pc + 1
EndProcedure

Procedure C2ARRAYFETCH_FLOAT_LOCAL_LOPT()
   Protected arrSlot.i = _LARRAY(_AR()\i)
   Protected idxSlot.i = _LARRAY(_AR()\ndx)
   Protected index.i = gLocal(idxSlot)\i
   vm_DebugFunctionName()
   _CheckLocalBounds(arrSlot, index)
   gEvalStack(sp)\f = gLocal(arrSlot)\dta\ar(index)\f
   sp + 1
   pc + 1
EndProcedure

; ============================================================================
; ARRAYFETCH - STRING - GLOBAL
; ============================================================================

Procedure C2ARRAYFETCH_STR_GLOBAL_OPT()
   Protected arrIdx.i = _AR()\i
   Protected index.i = gVar(_AR()\ndx)\i
   vm_DebugFunctionName()
   _CheckGlobalBounds(arrIdx, index)
   gEvalStack(sp)\ss = gVar(arrIdx)\dta\ar(index)\ss
   sp + 1
   pc + 1
EndProcedure

Procedure C2ARRAYFETCH_STR_GLOBAL_STACK()
   Protected arrIdx.i = _AR()\i
   vm_DebugFunctionName()
   sp - 1
   Protected index.i = gEvalStack(sp)\i
   _CheckGlobalBounds(arrIdx, index)
   gEvalStack(sp)\ss = gVar(arrIdx)\dta\ar(index)\ss
   sp + 1
   pc + 1
EndProcedure

Procedure C2ARRAYFETCH_STR_GLOBAL_LOPT()
   Protected arrIdx.i = _AR()\i
   Protected localSlot.i = _LARRAY(_AR()\ndx)
   Protected index.i = gLocal(localSlot)\i
   vm_DebugFunctionName()
   _CheckGlobalBounds(arrIdx, index)
   gEvalStack(sp)\ss = gVar(arrIdx)\dta\ar(index)\ss
   sp + 1
   pc + 1
EndProcedure

; ============================================================================
; ARRAYFETCH - STRING - LOCAL
; ============================================================================

Procedure C2ARRAYFETCH_STR_LOCAL_OPT()
   Protected localSlot.i = _LARRAY(_AR()\i)
   Protected index.i = gVar(_AR()\ndx)\i
   vm_DebugFunctionName()
   _CheckLocalBounds(localSlot, index)
   gEvalStack(sp)\ss = gLocal(localSlot)\dta\ar(index)\ss
   sp + 1
   pc + 1
EndProcedure

Procedure C2ARRAYFETCH_STR_LOCAL_STACK()
   Protected localSlot.i = _LARRAY(_AR()\i)
   vm_DebugFunctionName()
   sp - 1
   Protected index.i = gEvalStack(sp)\i
   _CheckLocalBounds(localSlot, index)
   gEvalStack(sp)\ss = gLocal(localSlot)\dta\ar(index)\ss
   sp + 1
   pc + 1
EndProcedure

Procedure C2ARRAYFETCH_STR_LOCAL_LOPT()
   Protected arrSlot.i = _LARRAY(_AR()\i)
   Protected idxSlot.i = _LARRAY(_AR()\ndx)
   Protected index.i = gLocal(idxSlot)\i
   vm_DebugFunctionName()
   _CheckLocalBounds(arrSlot, index)
   gEvalStack(sp)\ss = gLocal(arrSlot)\dta\ar(index)\ss
   sp + 1
   pc + 1
EndProcedure

; ============================================================================
; ARRAYSTORE - INTEGER - GLOBAL
; Naming: ARRAYSTORE_<type>_<arrScope>_<idxSource>_<valSource>
; ============================================================================

; Global array, OPT index, OPT value
Procedure C2ARRAYSTORE_INT_GLOBAL_OPT_OPT()
   Protected arrIdx.i = _AR()\i
   Protected index.i = gVar(_AR()\ndx)\i
   Protected valSlot.i = _AR()\n
   vm_DebugFunctionName()
   _CheckGlobalBounds(arrIdx, index)
   gVar(arrIdx)\dta\ar(index)\i = gVar(valSlot)\i
   If gVar(valSlot)\ptrtype
      gVar(arrIdx)\dta\ar(index)\ptr = gVar(valSlot)\ptr
      gVar(arrIdx)\dta\ar(index)\ptrtype = gVar(valSlot)\ptrtype
   EndIf
   pc + 1
EndProcedure

Procedure C2ARRAYSTORE_INT_GLOBAL_OPT_OPT_PURE()
   Protected arrIdx.i = _AR()\i
   Protected index.i = gVar(_AR()\ndx)\i
   Protected valSlot.i = _AR()\n
   vm_DebugFunctionName()
   _CheckGlobalBounds(arrIdx, index)
   gVar(arrIdx)\dta\ar(index)\i = gVar(valSlot)\i
   pc + 1
EndProcedure

; Global array, OPT index, STACK value
Procedure C2ARRAYSTORE_INT_GLOBAL_OPT_STACK()
   Protected arrIdx.i = _AR()\i
   Protected index.i = gVar(_AR()\ndx)\i
   vm_DebugFunctionName()
   sp - 1
   _CheckGlobalBounds(arrIdx, index)
   gVar(arrIdx)\dta\ar(index)\i = gEvalStack(sp)\i
   _CopyPtrTypeFromStack(arrIdx, index)
   pc + 1
EndProcedure

Procedure C2ARRAYSTORE_INT_GLOBAL_OPT_STACK_PURE()
   Protected arrIdx.i = _AR()\i
   Protected index.i = gVar(_AR()\ndx)\i
   vm_DebugFunctionName()
   sp - 1
   _CheckGlobalBounds(arrIdx, index)
   gVar(arrIdx)\dta\ar(index)\i = gEvalStack(sp)\i
   pc + 1
EndProcedure

; Global array, OPT index, LOPT value
Procedure C2ARRAYSTORE_INT_GLOBAL_OPT_LOPT()
   Protected arrIdx.i = _AR()\i
   Protected index.i = gVar(_AR()\ndx)\i
   Protected valSlot.i = _LARRAY(_AR()\n)
   vm_DebugFunctionName()
   _CheckGlobalBounds(arrIdx, index)
   gVar(arrIdx)\dta\ar(index)\i = gLocal(valSlot)\i
   If gLocal(valSlot)\ptrtype
      gVar(arrIdx)\dta\ar(index)\ptr = gLocal(valSlot)\ptr
      gVar(arrIdx)\dta\ar(index)\ptrtype = gLocal(valSlot)\ptrtype
   EndIf
   pc + 1
EndProcedure

Procedure C2ARRAYSTORE_INT_GLOBAL_OPT_LOPT_PURE()
   Protected arrIdx.i = _AR()\i
   Protected index.i = gVar(_AR()\ndx)\i
   Protected valSlot.i = _LARRAY(_AR()\n)
   vm_DebugFunctionName()
   _CheckGlobalBounds(arrIdx, index)
   gVar(arrIdx)\dta\ar(index)\i = gLocal(valSlot)\i
   pc + 1
EndProcedure

; Global array, STACK index, OPT value
Procedure C2ARRAYSTORE_INT_GLOBAL_STACK_OPT()
   Protected arrIdx.i = _AR()\i
   Protected valSlot.i = _AR()\n
   vm_DebugFunctionName()
   sp - 1
   Protected index.i = gEvalStack(sp)\i
   _CheckGlobalBounds(arrIdx, index)
   gVar(arrIdx)\dta\ar(index)\i = gVar(valSlot)\i
   If gVar(valSlot)\ptrtype
      gVar(arrIdx)\dta\ar(index)\ptr = gVar(valSlot)\ptr
      gVar(arrIdx)\dta\ar(index)\ptrtype = gVar(valSlot)\ptrtype
   EndIf
   pc + 1
EndProcedure

Procedure C2ARRAYSTORE_INT_GLOBAL_STACK_OPT_PURE()
   Protected arrIdx.i = _AR()\i
   Protected valSlot.i = _AR()\n
   vm_DebugFunctionName()
   sp - 1
   Protected index.i = gEvalStack(sp)\i
   _CheckGlobalBounds(arrIdx, index)
   gVar(arrIdx)\dta\ar(index)\i = gVar(valSlot)\i
   pc + 1
EndProcedure

; Global array, STACK index, STACK value
Procedure C2ARRAYSTORE_INT_GLOBAL_STACK_STACK()
   Protected arrIdx.i = _AR()\i
   vm_DebugFunctionName()
   sp - 1
   Protected index.i = gEvalStack(sp)\i
   sp - 1
   _CheckGlobalBounds(arrIdx, index)
   gVar(arrIdx)\dta\ar(index)\i = gEvalStack(sp)\i
   _CopyPtrTypeFromStack(arrIdx, index)
   pc + 1
EndProcedure

Procedure C2ARRAYSTORE_INT_GLOBAL_STACK_STACK_PURE()
   Protected arrIdx.i = _AR()\i
   vm_DebugFunctionName()
   sp - 1
   Protected index.i = gEvalStack(sp)\i
   sp - 1
   _CheckGlobalBounds(arrIdx, index)
   gVar(arrIdx)\dta\ar(index)\i = gEvalStack(sp)\i
   pc + 1
EndProcedure

; Global array, LOPT index, LOPT value
Procedure C2ARRAYSTORE_INT_GLOBAL_LOPT_LOPT()
   Protected arrIdx.i = _AR()\i
   Protected idxSlot.i = _LARRAY(_AR()\ndx)
   Protected valSlot.i = _LARRAY(_AR()\n)
   Protected index.i = gLocal(idxSlot)\i
   vm_DebugFunctionName()
   _CheckGlobalBounds(arrIdx, index)
   gVar(arrIdx)\dta\ar(index)\i = gLocal(valSlot)\i
   If gLocal(valSlot)\ptrtype
      gVar(arrIdx)\dta\ar(index)\ptr = gLocal(valSlot)\ptr
      gVar(arrIdx)\dta\ar(index)\ptrtype = gLocal(valSlot)\ptrtype
   EndIf
   pc + 1
EndProcedure

Procedure C2ARRAYSTORE_INT_GLOBAL_LOPT_LOPT_PURE()
   Protected arrIdx.i = _AR()\i
   Protected idxSlot.i = _LARRAY(_AR()\ndx)
   Protected valSlot.i = _LARRAY(_AR()\n)
   Protected index.i = gLocal(idxSlot)\i
   vm_DebugFunctionName()
   _CheckGlobalBounds(arrIdx, index)
   gVar(arrIdx)\dta\ar(index)\i = gLocal(valSlot)\i
   pc + 1
EndProcedure

; Global array, LOPT index, OPT value
Procedure C2ARRAYSTORE_INT_GLOBAL_LOPT_OPT()
   Protected arrIdx.i = _AR()\i
   Protected idxSlot.i = _LARRAY(_AR()\ndx)
   Protected valSlot.i = _AR()\n
   Protected index.i = gLocal(idxSlot)\i
   vm_DebugFunctionName()
   _CheckGlobalBounds(arrIdx, index)
   gVar(arrIdx)\dta\ar(index)\i = gVar(valSlot)\i
   If gVar(valSlot)\ptrtype
      gVar(arrIdx)\dta\ar(index)\ptr = gVar(valSlot)\ptr
      gVar(arrIdx)\dta\ar(index)\ptrtype = gVar(valSlot)\ptrtype
   EndIf
   pc + 1
EndProcedure

Procedure C2ARRAYSTORE_INT_GLOBAL_LOPT_OPT_PURE()
   Protected arrIdx.i = _AR()\i
   Protected idxSlot.i = _LARRAY(_AR()\ndx)
   Protected valSlot.i = _AR()\n
   Protected index.i = gLocal(idxSlot)\i
   vm_DebugFunctionName()
   _CheckGlobalBounds(arrIdx, index)
   gVar(arrIdx)\dta\ar(index)\i = gVar(valSlot)\i
   pc + 1
EndProcedure

; Global array, LOPT index, STACK value
Procedure C2ARRAYSTORE_INT_GLOBAL_LOPT_STACK()
   Protected arrIdx.i = _AR()\i
   Protected idxSlot.i = _LARRAY(_AR()\ndx)
   Protected index.i = gLocal(idxSlot)\i
   vm_DebugFunctionName()
   sp - 1
   _CheckGlobalBounds(arrIdx, index)
   gVar(arrIdx)\dta\ar(index)\i = gEvalStack(sp)\i
   _CopyPtrTypeFromStack(arrIdx, index)
   pc + 1
EndProcedure

Procedure C2ARRAYSTORE_INT_GLOBAL_LOPT_STACK_PURE()
   Protected arrIdx.i = _AR()\i
   Protected idxSlot.i = _LARRAY(_AR()\ndx)
   Protected index.i = gLocal(idxSlot)\i
   vm_DebugFunctionName()
   sp - 1
   _CheckGlobalBounds(arrIdx, index)
   gVar(arrIdx)\dta\ar(index)\i = gEvalStack(sp)\i
   pc + 1
EndProcedure

; ============================================================================
; ARRAYSTORE - INTEGER - LOCAL
; ============================================================================

; Local array, OPT index, OPT value
Procedure C2ARRAYSTORE_INT_LOCAL_OPT_OPT()
   Protected arrSlot.i = _LARRAY(_AR()\i)
   Protected index.i = gVar(_AR()\ndx)\i
   Protected valSlot.i = _AR()\n
   vm_DebugFunctionName()
   _CheckLocalBounds(arrSlot, index)
   gLocal(arrSlot)\dta\ar(index)\i = gVar(valSlot)\i
   pc + 1
EndProcedure

; Local array, OPT index, STACK value
Procedure C2ARRAYSTORE_INT_LOCAL_OPT_STACK()
   Protected arrSlot.i = _LARRAY(_AR()\i)
   Protected index.i = gVar(_AR()\ndx)\i
   vm_DebugFunctionName()
   sp - 1
   _CheckLocalBounds(arrSlot, index)
   gLocal(arrSlot)\dta\ar(index)\i = gEvalStack(sp)\i
   pc + 1
EndProcedure

; Local array, OPT index, LOPT value
Procedure C2ARRAYSTORE_INT_LOCAL_OPT_LOPT()
   Protected arrSlot.i = _LARRAY(_AR()\i)
   Protected index.i = gVar(_AR()\ndx)\i
   Protected valSlot.i = _LARRAY(_AR()\n)
   vm_DebugFunctionName()
   _CheckLocalBounds(arrSlot, index)
   gLocal(arrSlot)\dta\ar(index)\i = gLocal(valSlot)\i
   pc + 1
EndProcedure

; Local array, STACK index, OPT value
Procedure C2ARRAYSTORE_INT_LOCAL_STACK_OPT()
   Protected arrSlot.i = _LARRAY(_AR()\i)
   Protected valSlot.i = _AR()\n
   vm_DebugFunctionName()
   sp - 1
   Protected index.i = gEvalStack(sp)\i
   _CheckLocalBounds(arrSlot, index)
   gLocal(arrSlot)\dta\ar(index)\i = gVar(valSlot)\i
   pc + 1
EndProcedure

; Local array, STACK index, STACK value
Procedure C2ARRAYSTORE_INT_LOCAL_STACK_STACK()
   Protected arrSlot.i = _LARRAY(_AR()\i)
   vm_DebugFunctionName()
   sp - 1
   Protected index.i = gEvalStack(sp)\i
   sp - 1
   _CheckLocalBounds(arrSlot, index)
   gLocal(arrSlot)\dta\ar(index)\i = gEvalStack(sp)\i
   pc + 1
EndProcedure

; Local array, LOPT index, LOPT value
Procedure C2ARRAYSTORE_INT_LOCAL_LOPT_LOPT()
   Protected arrSlot.i = _LARRAY(_AR()\i)
   Protected idxSlot.i = _LARRAY(_AR()\ndx)
   Protected valSlot.i = _LARRAY(_AR()\n)
   Protected index.i = gLocal(idxSlot)\i
   vm_DebugFunctionName()
   _CheckLocalBounds(arrSlot, index)
   gLocal(arrSlot)\dta\ar(index)\i = gLocal(valSlot)\i
   pc + 1
EndProcedure

; Local array, LOPT index, OPT value
Procedure C2ARRAYSTORE_INT_LOCAL_LOPT_OPT()
   Protected arrSlot.i = _LARRAY(_AR()\i)
   Protected idxSlot.i = _LARRAY(_AR()\ndx)
   Protected valSlot.i = _AR()\n
   Protected index.i = gLocal(idxSlot)\i
   vm_DebugFunctionName()
   _CheckLocalBounds(arrSlot, index)
   gLocal(arrSlot)\dta\ar(index)\i = gVar(valSlot)\i
   pc + 1
EndProcedure

; Local array, LOPT index, STACK value
Procedure C2ARRAYSTORE_INT_LOCAL_LOPT_STACK()
   Protected arrSlot.i = _LARRAY(_AR()\i)
   Protected idxSlot.i = _LARRAY(_AR()\ndx)
   Protected index.i = gLocal(idxSlot)\i
   vm_DebugFunctionName()
   sp - 1
   _CheckLocalBounds(arrSlot, index)
   gLocal(arrSlot)\dta\ar(index)\i = gEvalStack(sp)\i
   pc + 1
EndProcedure

; ============================================================================
; ARRAYSTORE - FLOAT - GLOBAL
; ============================================================================

Procedure C2ARRAYSTORE_FLOAT_GLOBAL_OPT_OPT()
   Protected arrIdx.i = _AR()\i
   Protected index.i = gVar(_AR()\ndx)\i
   Protected valSlot.i = _AR()\n
   vm_DebugFunctionName()
   _CheckGlobalBounds(arrIdx, index)
   gVar(arrIdx)\dta\ar(index)\f = gVar(valSlot)\f
   pc + 1
EndProcedure

Procedure C2ARRAYSTORE_FLOAT_GLOBAL_OPT_STACK()
   Protected arrIdx.i = _AR()\i
   Protected index.i = gVar(_AR()\ndx)\i
   vm_DebugFunctionName()
   sp - 1
   _CheckGlobalBounds(arrIdx, index)
   gVar(arrIdx)\dta\ar(index)\f = gEvalStack(sp)\f
   pc + 1
EndProcedure

Procedure C2ARRAYSTORE_FLOAT_GLOBAL_OPT_LOPT()
   Protected arrIdx.i = _AR()\i
   Protected index.i = gVar(_AR()\ndx)\i
   Protected valSlot.i = _LARRAY(_AR()\n)
   vm_DebugFunctionName()
   _CheckGlobalBounds(arrIdx, index)
   gVar(arrIdx)\dta\ar(index)\f = gLocal(valSlot)\f
   pc + 1
EndProcedure

Procedure C2ARRAYSTORE_FLOAT_GLOBAL_STACK_OPT()
   Protected arrIdx.i = _AR()\i
   Protected valSlot.i = _AR()\n
   vm_DebugFunctionName()
   sp - 1
   Protected index.i = gEvalStack(sp)\i
   _CheckGlobalBounds(arrIdx, index)
   gVar(arrIdx)\dta\ar(index)\f = gVar(valSlot)\f
   pc + 1
EndProcedure

Procedure C2ARRAYSTORE_FLOAT_GLOBAL_STACK_STACK()
   Protected arrIdx.i = _AR()\i
   vm_DebugFunctionName()
   sp - 1
   Protected index.i = gEvalStack(sp)\i
   sp - 1
   _CheckGlobalBounds(arrIdx, index)
   gVar(arrIdx)\dta\ar(index)\f = gEvalStack(sp)\f
   pc + 1
EndProcedure

Procedure C2ARRAYSTORE_FLOAT_GLOBAL_LOPT_LOPT()
   Protected arrIdx.i = _AR()\i
   Protected idxSlot.i = _LARRAY(_AR()\ndx)
   Protected valSlot.i = _LARRAY(_AR()\n)
   Protected index.i = gLocal(idxSlot)\i
   vm_DebugFunctionName()
   _CheckGlobalBounds(arrIdx, index)
   gVar(arrIdx)\dta\ar(index)\f = gLocal(valSlot)\f
   pc + 1
EndProcedure

Procedure C2ARRAYSTORE_FLOAT_GLOBAL_LOPT_OPT()
   Protected arrIdx.i = _AR()\i
   Protected idxSlot.i = _LARRAY(_AR()\ndx)
   Protected valSlot.i = _AR()\n
   Protected index.i = gLocal(idxSlot)\i
   vm_DebugFunctionName()
   _CheckGlobalBounds(arrIdx, index)
   gVar(arrIdx)\dta\ar(index)\f = gVar(valSlot)\f
   pc + 1
EndProcedure

Procedure C2ARRAYSTORE_FLOAT_GLOBAL_LOPT_STACK()
   Protected arrIdx.i = _AR()\i
   Protected idxSlot.i = _LARRAY(_AR()\ndx)
   Protected index.i = gLocal(idxSlot)\i
   vm_DebugFunctionName()
   sp - 1
   _CheckGlobalBounds(arrIdx, index)
   gVar(arrIdx)\dta\ar(index)\f = gEvalStack(sp)\f
   pc + 1
EndProcedure

; ============================================================================
; ARRAYSTORE - FLOAT - LOCAL
; ============================================================================

Procedure C2ARRAYSTORE_FLOAT_LOCAL_OPT_OPT()
   Protected arrSlot.i = _LARRAY(_AR()\i)
   Protected index.i = gVar(_AR()\ndx)\i
   Protected valSlot.i = _AR()\n
   vm_DebugFunctionName()
   _CheckLocalBounds(arrSlot, index)
   gLocal(arrSlot)\dta\ar(index)\f = gVar(valSlot)\f
   pc + 1
EndProcedure

Procedure C2ARRAYSTORE_FLOAT_LOCAL_OPT_STACK()
   Protected arrSlot.i = _LARRAY(_AR()\i)
   Protected index.i = gVar(_AR()\ndx)\i
   vm_DebugFunctionName()
   sp - 1
   _CheckLocalBounds(arrSlot, index)
   gLocal(arrSlot)\dta\ar(index)\f = gEvalStack(sp)\f
   pc + 1
EndProcedure

Procedure C2ARRAYSTORE_FLOAT_LOCAL_OPT_LOPT()
   Protected arrSlot.i = _LARRAY(_AR()\i)
   Protected index.i = gVar(_AR()\ndx)\i
   Protected valSlot.i = _LARRAY(_AR()\n)
   vm_DebugFunctionName()
   _CheckLocalBounds(arrSlot, index)
   gLocal(arrSlot)\dta\ar(index)\f = gLocal(valSlot)\f
   pc + 1
EndProcedure

Procedure C2ARRAYSTORE_FLOAT_LOCAL_STACK_OPT()
   Protected arrSlot.i = _LARRAY(_AR()\i)
   Protected valSlot.i = _AR()\n
   vm_DebugFunctionName()
   sp - 1
   Protected index.i = gEvalStack(sp)\i
   _CheckLocalBounds(arrSlot, index)
   gLocal(arrSlot)\dta\ar(index)\f = gVar(valSlot)\f
   pc + 1
EndProcedure

Procedure C2ARRAYSTORE_FLOAT_LOCAL_STACK_STACK()
   Protected arrSlot.i = _LARRAY(_AR()\i)
   vm_DebugFunctionName()
   sp - 1
   Protected index.i = gEvalStack(sp)\i
   sp - 1
   _CheckLocalBounds(arrSlot, index)
   gLocal(arrSlot)\dta\ar(index)\f = gEvalStack(sp)\f
   pc + 1
EndProcedure

Procedure C2ARRAYSTORE_FLOAT_LOCAL_LOPT_LOPT()
   Protected arrSlot.i = _LARRAY(_AR()\i)
   Protected idxSlot.i = _LARRAY(_AR()\ndx)
   Protected valSlot.i = _LARRAY(_AR()\n)
   Protected index.i = gLocal(idxSlot)\i
   vm_DebugFunctionName()
   _CheckLocalBounds(arrSlot, index)
   gLocal(arrSlot)\dta\ar(index)\f = gLocal(valSlot)\f
   pc + 1
EndProcedure

Procedure C2ARRAYSTORE_FLOAT_LOCAL_LOPT_OPT()
   Protected arrSlot.i = _LARRAY(_AR()\i)
   Protected idxSlot.i = _LARRAY(_AR()\ndx)
   Protected valSlot.i = _AR()\n
   Protected index.i = gLocal(idxSlot)\i
   vm_DebugFunctionName()
   _CheckLocalBounds(arrSlot, index)
   gLocal(arrSlot)\dta\ar(index)\f = gVar(valSlot)\f
   pc + 1
EndProcedure

Procedure C2ARRAYSTORE_FLOAT_LOCAL_LOPT_STACK()
   Protected arrSlot.i = _LARRAY(_AR()\i)
   Protected idxSlot.i = _LARRAY(_AR()\ndx)
   Protected index.i = gLocal(idxSlot)\i
   vm_DebugFunctionName()
   sp - 1
   _CheckLocalBounds(arrSlot, index)
   gLocal(arrSlot)\dta\ar(index)\f = gEvalStack(sp)\f
   pc + 1
EndProcedure

; ============================================================================
; ARRAYSTORE - STRING - GLOBAL
; ============================================================================

Procedure C2ARRAYSTORE_STR_GLOBAL_OPT_OPT()
   Protected arrIdx.i = _AR()\i
   Protected index.i = gVar(_AR()\ndx)\i
   Protected valSlot.i = _AR()\n
   vm_DebugFunctionName()
   _CheckGlobalBounds(arrIdx, index)
   gVar(arrIdx)\dta\ar(index)\ss = gVar(valSlot)\ss
   pc + 1
EndProcedure

Procedure C2ARRAYSTORE_STR_GLOBAL_OPT_STACK()
   Protected arrIdx.i = _AR()\i
   Protected index.i = gVar(_AR()\ndx)\i
   vm_DebugFunctionName()
   sp - 1
   _CheckGlobalBounds(arrIdx, index)
   gVar(arrIdx)\dta\ar(index)\ss = gEvalStack(sp)\ss
   pc + 1
EndProcedure

Procedure C2ARRAYSTORE_STR_GLOBAL_OPT_LOPT()
   Protected arrIdx.i = _AR()\i
   Protected index.i = gVar(_AR()\ndx)\i
   Protected valSlot.i = _LARRAY(_AR()\n)
   vm_DebugFunctionName()
   _CheckGlobalBounds(arrIdx, index)
   gVar(arrIdx)\dta\ar(index)\ss = gLocal(valSlot)\ss
   pc + 1
EndProcedure

Procedure C2ARRAYSTORE_STR_GLOBAL_STACK_OPT()
   Protected arrIdx.i = _AR()\i
   Protected valSlot.i = _AR()\n
   vm_DebugFunctionName()
   sp - 1
   Protected index.i = gEvalStack(sp)\i
   _CheckGlobalBounds(arrIdx, index)
   gVar(arrIdx)\dta\ar(index)\ss = gVar(valSlot)\ss
   pc + 1
EndProcedure

Procedure C2ARRAYSTORE_STR_GLOBAL_STACK_STACK()
   Protected arrIdx.i = _AR()\i
   vm_DebugFunctionName()
   sp - 1
   Protected index.i = gEvalStack(sp)\i
   sp - 1
   _CheckGlobalBounds(arrIdx, index)
   gVar(arrIdx)\dta\ar(index)\ss = gEvalStack(sp)\ss
   pc + 1
EndProcedure

Procedure C2ARRAYSTORE_STR_GLOBAL_LOPT_LOPT()
   Protected arrIdx.i = _AR()\i
   Protected idxSlot.i = _LARRAY(_AR()\ndx)
   Protected valSlot.i = _LARRAY(_AR()\n)
   Protected index.i = gLocal(idxSlot)\i
   vm_DebugFunctionName()
   _CheckGlobalBounds(arrIdx, index)
   gVar(arrIdx)\dta\ar(index)\ss = gLocal(valSlot)\ss
   pc + 1
EndProcedure

Procedure C2ARRAYSTORE_STR_GLOBAL_LOPT_OPT()
   Protected arrIdx.i = _AR()\i
   Protected idxSlot.i = _LARRAY(_AR()\ndx)
   Protected valSlot.i = _AR()\n
   Protected index.i = gLocal(idxSlot)\i
   vm_DebugFunctionName()
   _CheckGlobalBounds(arrIdx, index)
   gVar(arrIdx)\dta\ar(index)\ss = gVar(valSlot)\ss
   pc + 1
EndProcedure

Procedure C2ARRAYSTORE_STR_GLOBAL_LOPT_STACK()
   Protected arrIdx.i = _AR()\i
   Protected idxSlot.i = _LARRAY(_AR()\ndx)
   Protected index.i = gLocal(idxSlot)\i
   vm_DebugFunctionName()
   sp - 1
   _CheckGlobalBounds(arrIdx, index)
   gVar(arrIdx)\dta\ar(index)\ss = gEvalStack(sp)\ss
   pc + 1
EndProcedure

; ============================================================================
; ARRAYSTORE - STRING - LOCAL
; ============================================================================

Procedure C2ARRAYSTORE_STR_LOCAL_OPT_OPT()
   Protected arrSlot.i = _LARRAY(_AR()\i)
   Protected index.i = gVar(_AR()\ndx)\i
   Protected valSlot.i = _AR()\n
   vm_DebugFunctionName()
   _CheckLocalBounds(arrSlot, index)
   gLocal(arrSlot)\dta\ar(index)\ss = gVar(valSlot)\ss
   pc + 1
EndProcedure

Procedure C2ARRAYSTORE_STR_LOCAL_OPT_STACK()
   Protected arrSlot.i = _LARRAY(_AR()\i)
   Protected index.i = gVar(_AR()\ndx)\i
   vm_DebugFunctionName()
   sp - 1
   _CheckLocalBounds(arrSlot, index)
   gLocal(arrSlot)\dta\ar(index)\ss = gEvalStack(sp)\ss
   pc + 1
EndProcedure

Procedure C2ARRAYSTORE_STR_LOCAL_OPT_LOPT()
   Protected arrSlot.i = _LARRAY(_AR()\i)
   Protected index.i = gVar(_AR()\ndx)\i
   Protected valSlot.i = _LARRAY(_AR()\n)
   vm_DebugFunctionName()
   _CheckLocalBounds(arrSlot, index)
   gLocal(arrSlot)\dta\ar(index)\ss = gLocal(valSlot)\ss
   pc + 1
EndProcedure

Procedure C2ARRAYSTORE_STR_LOCAL_STACK_OPT()
   Protected arrSlot.i = _LARRAY(_AR()\i)
   Protected valSlot.i = _AR()\n
   vm_DebugFunctionName()
   sp - 1
   Protected index.i = gEvalStack(sp)\i
   _CheckLocalBounds(arrSlot, index)
   gLocal(arrSlot)\dta\ar(index)\ss = gVar(valSlot)\ss
   pc + 1
EndProcedure

Procedure C2ARRAYSTORE_STR_LOCAL_STACK_STACK()
   Protected arrSlot.i = _LARRAY(_AR()\i)
   vm_DebugFunctionName()
   sp - 1
   Protected index.i = gEvalStack(sp)\i
   sp - 1
   _CheckLocalBounds(arrSlot, index)
   gLocal(arrSlot)\dta\ar(index)\ss = gEvalStack(sp)\ss
   pc + 1
EndProcedure

Procedure C2ARRAYSTORE_STR_LOCAL_LOPT_LOPT()
   Protected arrSlot.i = _LARRAY(_AR()\i)
   Protected idxSlot.i = _LARRAY(_AR()\ndx)
   Protected valSlot.i = _LARRAY(_AR()\n)
   Protected index.i = gLocal(idxSlot)\i
   vm_DebugFunctionName()
   _CheckLocalBounds(arrSlot, index)
   gLocal(arrSlot)\dta\ar(index)\ss = gLocal(valSlot)\ss
   pc + 1
EndProcedure

Procedure C2ARRAYSTORE_STR_LOCAL_LOPT_OPT()
   Protected arrSlot.i = _LARRAY(_AR()\i)
   Protected idxSlot.i = _LARRAY(_AR()\ndx)
   Protected valSlot.i = _AR()\n
   Protected index.i = gLocal(idxSlot)\i
   vm_DebugFunctionName()
   _CheckLocalBounds(arrSlot, index)
   gLocal(arrSlot)\dta\ar(index)\ss = gVar(valSlot)\ss
   pc + 1
EndProcedure

Procedure C2ARRAYSTORE_STR_LOCAL_LOPT_STACK()
   Protected arrSlot.i = _LARRAY(_AR()\i)
   Protected idxSlot.i = _LARRAY(_AR()\ndx)
   Protected index.i = gLocal(idxSlot)\i
   vm_DebugFunctionName()
   sp - 1
   _CheckLocalBounds(arrSlot, index)
   gLocal(arrSlot)\dta\ar(index)\ss = gEvalStack(sp)\ss
   pc + 1
EndProcedure

; ============================================================================
; STRUCTARRAY_FETCH - Fetch from struct array field using \ptr storage
; ============================================================================

Procedure C2STRUCTARRAY_FETCH_INT()
   ; Fetch integer from struct array field using \ptr storage
   ; _AR()\i = struct slot (or paramOffset for local)
   ; _AR()\j = isLocal (0 = global, 1 = local)
   ; _AR()\n = field byte offset (fieldOffset * 8)
   ; _AR()\ndx = index slot (>= 0) or -1 (index on stack)
   Protected index.i, byteOffset.i, *structPtr
   vm_DebugFunctionName()

   ; Get array index
   If _AR()\ndx >= 0
      index = gVar(_AR()\ndx)\i
   Else
      sp - 1
      index = gEvalStack(sp)\i
   EndIf

   ; Calculate total byte offset: field offset + index * 8
   byteOffset = _AR()\n + (index * 8)

   ; Get struct pointer based on local/global
   If _AR()\j
      *structPtr = gLocal(_LARRAY(_AR()\i))\ptr
   Else
      *structPtr = gVar(_AR()\i)\ptr
   EndIf

   CompilerIf #DEBUG
      Debug "SARFETCH_INT: pc=" + Str(pc) + " slot=" + Str(_AR()\i) + " ndx=" + Str(_AR()\ndx) + " j=" + Str(_AR()\j) + " fieldOff=" + Str(_AR()\n) + " index=" + Str(index) + " byteOff=" + Str(byteOffset) + " ptr=" + Str(*structPtr) + " value=" + Str(PeekQ(*structPtr + byteOffset))
   CompilerEndIf

   gEvalStack(sp)\i = PeekQ(*structPtr + byteOffset)
   sp + 1
   pc + 1
EndProcedure

Procedure C2STRUCTARRAY_FETCH_FLOAT()
   ; Fetch float from struct array field using \ptr storage
   Protected index.i, byteOffset.i, *structPtr
   vm_DebugFunctionName()

   If _AR()\ndx >= 0
      index = gVar(_AR()\ndx)\i
   Else
      sp - 1
      index = gEvalStack(sp)\i
   EndIf

   byteOffset = _AR()\n + (index * 8)

   If _AR()\j
      *structPtr = gLocal(_LARRAY(_AR()\i))\ptr
   Else
      *structPtr = gVar(_AR()\i)\ptr
   EndIf

   gEvalStack(sp)\f = PeekD(*structPtr + byteOffset)
   sp + 1
   pc + 1
EndProcedure

Procedure C2STRUCTARRAY_FETCH_STR()
   ; Fetch string from struct array field using \ptr storage
   Protected index.i, byteOffset.i, *structPtr, *strPtr
   vm_DebugFunctionName()

   If _AR()\ndx >= 0
      index = gVar(_AR()\ndx)\i
   Else
      sp - 1
      index = gEvalStack(sp)\i
   EndIf

   byteOffset = _AR()\n + (index * 8)

   If _AR()\j
      *structPtr = gLocal(_LARRAY(_AR()\i))\ptr
   Else
      *structPtr = gVar(_AR()\i)\ptr
   EndIf

   *strPtr = PeekQ(*structPtr + byteOffset)
   If *strPtr
      gEvalStack(sp)\ss = PeekS(*strPtr)
   Else
      gEvalStack(sp)\ss = ""
   EndIf
   sp + 1
   pc + 1
EndProcedure

; ============================================================================
; STRUCTARRAY_STORE - Store to struct array field using \ptr storage
; ============================================================================

Procedure C2STRUCTARRAY_STORE_INT()
   ; Store integer to struct array field
   ; _AR()\funcid = value slot (>= 0) or -1 (value on stack)
   Protected index.i, value.i, byteOffset.i, *structPtr
   vm_DebugFunctionName()

   If _AR()\ndx >= 0
      index = gVar(_AR()\ndx)\i
   Else
      sp - 1
      index = gEvalStack(sp)\i
   EndIf

   If _AR()\funcid >= 0
      value = gVar(_AR()\funcid)\i
   Else
      sp - 1
      value = gEvalStack(sp)\i
   EndIf

   byteOffset = _AR()\n + (index * 8)

   If _AR()\j
      *structPtr = gLocal(_LARRAY(_AR()\i))\ptr
   Else
      *structPtr = gVar(_AR()\i)\ptr
   EndIf

   PokeQ(*structPtr + byteOffset, value)
   pc + 1
EndProcedure

Procedure C2STRUCTARRAY_STORE_FLOAT()
   ; Store float to struct array field
   Protected index.i, byteOffset.i, *structPtr
   Protected value.d
   vm_DebugFunctionName()

   If _AR()\ndx >= 0
      index = gVar(_AR()\ndx)\i
   Else
      sp - 1
      index = gEvalStack(sp)\i
   EndIf

   If _AR()\funcid >= 0
      value = gVar(_AR()\funcid)\f
   Else
      sp - 1
      value = gEvalStack(sp)\f
   EndIf

   byteOffset = _AR()\n + (index * 8)

   If _AR()\j
      *structPtr = gLocal(_LARRAY(_AR()\i))\ptr
   Else
      *structPtr = gVar(_AR()\i)\ptr
   EndIf

   PokeD(*structPtr + byteOffset, value)
   pc + 1
EndProcedure

Procedure C2STRUCTARRAY_STORE_STR()
   ; Store string to struct array field
   Protected index.i, byteOffset.i, *structPtr
   Protected value.s, *oldStr, *newStr, strLen.i
   vm_DebugFunctionName()

   If _AR()\ndx >= 0
      index = gVar(_AR()\ndx)\i
   Else
      sp - 1
      index = gEvalStack(sp)\i
   EndIf

   If _AR()\funcid >= 0
      value = gVar(_AR()\funcid)\ss
   Else
      sp - 1
      value = gEvalStack(sp)\ss
   EndIf

   byteOffset = _AR()\n + (index * 8)

   If _AR()\j
      *structPtr = gLocal(_LARRAY(_AR()\i))\ptr
   Else
      *structPtr = gVar(_AR()\i)\ptr
   EndIf

   ; Free old string if exists
   *oldStr = PeekQ(*structPtr + byteOffset)
   If *oldStr : FreeMemory(*oldStr) : EndIf

   ; Allocate and copy new string
   strLen = StringByteLength(value) + SizeOf(Character)
   *newStr = AllocateMemory(strLen)
   PokeS(*newStr, value)
   PokeQ(*structPtr + byteOffset, *newStr)
   pc + 1
EndProcedure

; ============================================================================
; ARRAYOFSTRUCT_FETCH - Array of Structs Operations
; targetSlot = arrayBase + (index * elementSize) + fieldOffset
; _AR()\i = array base slot, _AR()\j = element size, _AR()\n = field offset
; _AR()\ndx = index slot, _AR()\funcid = 1 for local, 0 for global
; ============================================================================

Procedure C2ARRAYOFSTRUCT_FETCH_INT()
   Protected index.i, targetSlot.i, baseSlot.i
   Protected elementSize.i, fieldOffset.i
   vm_DebugFunctionName()

   ; V1.033.36: Handle local index slots (negative ndx = local offset encoded as -(offset+2))
   If _AR()\ndx < -1
      index = gLocal(_LARRAY(-(_AR()\ndx + 2)))\i
   Else
      index = gVar(_AR()\ndx)\i
   EndIf
   elementSize = _AR()\j
   fieldOffset = _AR()\n

   If _AR()\funcid
      baseSlot = _LARRAY(_AR()\i)
   Else
      baseSlot = _AR()\i
   EndIf

   targetSlot = baseSlot + (index * elementSize) + fieldOffset

   CompilerIf #DEBUG
      Debug "AOSFETCH_INT: base=" + Str(baseSlot) + " idx=" + Str(index) + " elemSz=" + Str(elementSize) + " fldOff=" + Str(fieldOffset) + " target=" + Str(targetSlot) + " val=" + Str(gVar(targetSlot)\i)
   CompilerEndIf

   gEvalStack(sp)\i = gVar(targetSlot)\i
   sp + 1
   pc + 1
EndProcedure

Procedure C2ARRAYOFSTRUCT_FETCH_FLOAT()
   Protected index.i, targetSlot.i, baseSlot.i
   Protected elementSize.i, fieldOffset.i
   vm_DebugFunctionName()

   ; V1.033.36: Handle local index slots (negative ndx = local offset encoded as -(offset+2))
   If _AR()\ndx < -1
      index = gLocal(_LARRAY(-(_AR()\ndx + 2)))\i
   Else
      index = gVar(_AR()\ndx)\i
   EndIf
   elementSize = _AR()\j
   fieldOffset = _AR()\n

   If _AR()\funcid
      baseSlot = _LARRAY(_AR()\i)
   Else
      baseSlot = _AR()\i
   EndIf

   targetSlot = baseSlot + (index * elementSize) + fieldOffset
   gEvalStack(sp)\f = gVar(targetSlot)\f
   sp + 1
   pc + 1
EndProcedure

Procedure C2ARRAYOFSTRUCT_FETCH_STR()
   Protected index.i, targetSlot.i, baseSlot.i
   Protected elementSize.i, fieldOffset.i
   vm_DebugFunctionName()

   ; V1.033.36: Handle local index slots (negative ndx = local offset encoded as -(offset+2))
   If _AR()\ndx < -1
      index = gLocal(_LARRAY(-(_AR()\ndx + 2)))\i
   Else
      index = gVar(_AR()\ndx)\i
   EndIf
   elementSize = _AR()\j
   fieldOffset = _AR()\n

   If _AR()\funcid
      baseSlot = _LARRAY(_AR()\i)
   Else
      baseSlot = _AR()\i
   EndIf

   targetSlot = baseSlot + (index * elementSize) + fieldOffset
   gEvalStack(sp)\ss = gVar(targetSlot)\ss
   sp + 1
   pc + 1
EndProcedure

; ============================================================================
; ARRAYOFSTRUCT_STORE - Store to Array of Structs
; ============================================================================

Procedure C2ARRAYOFSTRUCT_STORE_INT()
   Protected index.i, targetSlot.i, baseSlot.i, value.i
   Protected elementSize.i, fieldOffset.i
   vm_DebugFunctionName()

   sp - 1
   value = gEvalStack(sp)\i

   ; V1.033.36: Handle local index slots (negative ndx = local offset encoded as -(offset+2))
   If _AR()\ndx < -1
      index = gLocal(_LARRAY(-(_AR()\ndx + 2)))\i
   Else
      index = gVar(_AR()\ndx)\i
   EndIf
   elementSize = _AR()\j
   fieldOffset = _AR()\n

   If _AR()\funcid
      baseSlot = _LARRAY(_AR()\i)
   Else
      baseSlot = _AR()\i
   EndIf

   targetSlot = baseSlot + (index * elementSize) + fieldOffset

   CompilerIf #DEBUG
      Debug "AOSSTORE_INT: base=" + Str(baseSlot) + " idx=" + Str(index) + " elemSz=" + Str(elementSize) + " fldOff=" + Str(fieldOffset) + " target=" + Str(targetSlot) + " val=" + Str(value)
   CompilerEndIf

   gVar(targetSlot)\i = value
   pc + 1
EndProcedure

Procedure C2ARRAYOFSTRUCT_STORE_FLOAT()
   Protected index.i, targetSlot.i, baseSlot.i
   Protected elementSize.i, fieldOffset.i
   Protected value.d
   vm_DebugFunctionName()

   sp - 1
   value = gEvalStack(sp)\f

   ; V1.033.36: Handle local index slots (negative ndx = local offset encoded as -(offset+2))
   If _AR()\ndx < -1
      index = gLocal(_LARRAY(-(_AR()\ndx + 2)))\i
   Else
      index = gVar(_AR()\ndx)\i
   EndIf
   elementSize = _AR()\j
   fieldOffset = _AR()\n

   If _AR()\funcid
      baseSlot = _LARRAY(_AR()\i)
   Else
      baseSlot = _AR()\i
   EndIf

   targetSlot = baseSlot + (index * elementSize) + fieldOffset
   gVar(targetSlot)\f = value
   pc + 1
EndProcedure

Procedure C2ARRAYOFSTRUCT_STORE_STR()
   Protected index.i, targetSlot.i, baseSlot.i
   Protected elementSize.i, fieldOffset.i
   Protected value.s
   vm_DebugFunctionName()

   sp - 1
   value = gEvalStack(sp)\ss

   ; V1.033.36: Handle local index slots (negative ndx = local offset encoded as -(offset+2))
   If _AR()\ndx < -1
      index = gLocal(_LARRAY(-(_AR()\ndx + 2)))\i
   Else
      index = gVar(_AR()\ndx)\i
   EndIf
   elementSize = _AR()\j
   fieldOffset = _AR()\n

   If _AR()\funcid
      baseSlot = _LARRAY(_AR()\i)
   Else
      baseSlot = _AR()\i
   EndIf

   targetSlot = baseSlot + (index * elementSize) + fieldOffset
   gVar(targetSlot)\ss = value
   pc + 1
EndProcedure

; ============================================================================
; ARRAYOFSTRUCT_*_LOPT - Local index variants
; ============================================================================

Procedure C2ARRAYOFSTRUCT_FETCH_INT_LOPT()
   Protected index.i, targetSlot.i, baseSlot.i
   Protected elementSize.i, fieldOffset.i
   vm_DebugFunctionName()

   index = gLocal(_LARRAY(_AR()\ndx))\i
   elementSize = _AR()\j
   fieldOffset = _AR()\n

   If _AR()\funcid
      baseSlot = _LARRAY(_AR()\i)
   Else
      baseSlot = _AR()\i
   EndIf

   targetSlot = baseSlot + (index * elementSize) + fieldOffset
   gEvalStack(sp)\i = gVar(targetSlot)\i
   sp + 1
   pc + 1
EndProcedure

Procedure C2ARRAYOFSTRUCT_FETCH_FLOAT_LOPT()
   Protected index.i, targetSlot.i, baseSlot.i
   Protected elementSize.i, fieldOffset.i
   vm_DebugFunctionName()

   index = gLocal(_LARRAY(_AR()\ndx))\i
   elementSize = _AR()\j
   fieldOffset = _AR()\n

   If _AR()\funcid
      baseSlot = _LARRAY(_AR()\i)
   Else
      baseSlot = _AR()\i
   EndIf

   targetSlot = baseSlot + (index * elementSize) + fieldOffset
   gEvalStack(sp)\f = gVar(targetSlot)\f
   sp + 1
   pc + 1
EndProcedure

Procedure C2ARRAYOFSTRUCT_FETCH_STR_LOPT()
   Protected index.i, targetSlot.i, baseSlot.i
   Protected elementSize.i, fieldOffset.i
   vm_DebugFunctionName()

   index = gLocal(_LARRAY(_AR()\ndx))\i
   elementSize = _AR()\j
   fieldOffset = _AR()\n

   If _AR()\funcid
      baseSlot = _LARRAY(_AR()\i)
   Else
      baseSlot = _AR()\i
   EndIf

   targetSlot = baseSlot + (index * elementSize) + fieldOffset
   gEvalStack(sp)\ss = gVar(targetSlot)\ss
   sp + 1
   pc + 1
EndProcedure

Procedure C2ARRAYOFSTRUCT_STORE_INT_LOPT()
   Protected index.i, targetSlot.i, baseSlot.i, value.i
   Protected elementSize.i, fieldOffset.i
   vm_DebugFunctionName()

   sp - 1
   value = gEvalStack(sp)\i

   index = gLocal(_LARRAY(_AR()\ndx))\i
   elementSize = _AR()\j
   fieldOffset = _AR()\n

   If _AR()\funcid
      baseSlot = _LARRAY(_AR()\i)
   Else
      baseSlot = _AR()\i
   EndIf

   targetSlot = baseSlot + (index * elementSize) + fieldOffset
   gVar(targetSlot)\i = value
   pc + 1
EndProcedure

Procedure C2ARRAYOFSTRUCT_STORE_FLOAT_LOPT()
   Protected index.i, targetSlot.i, baseSlot.i
   Protected elementSize.i, fieldOffset.i
   Protected value.d
   vm_DebugFunctionName()

   sp - 1
   value = gEvalStack(sp)\f

   index = gLocal(_LARRAY(_AR()\ndx))\i
   elementSize = _AR()\j
   fieldOffset = _AR()\n

   If _AR()\funcid
      baseSlot = _LARRAY(_AR()\i)
   Else
      baseSlot = _AR()\i
   EndIf

   targetSlot = baseSlot + (index * elementSize) + fieldOffset
   gVar(targetSlot)\f = value
   pc + 1
EndProcedure

Procedure C2ARRAYOFSTRUCT_STORE_STR_LOPT()
   Protected index.i, targetSlot.i, baseSlot.i
   Protected elementSize.i, fieldOffset.i
   Protected value.s
   vm_DebugFunctionName()

   sp - 1
   value = gEvalStack(sp)\ss

   index = gLocal(_LARRAY(_AR()\ndx))\i
   elementSize = _AR()\j
   fieldOffset = _AR()\n

   If _AR()\funcid
      baseSlot = _LARRAY(_AR()\i)
   Else
      baseSlot = _AR()\i
   EndIf

   targetSlot = baseSlot + (index * elementSize) + fieldOffset
   gVar(targetSlot)\ss = value
   pc + 1
EndProcedure

; ============================================================================
; ARRAYRESIZE - Resize array using ReDim
; _AR()\i = array slot, _AR()\j = new size, _AR()\n = isLocal flag
; ============================================================================

Procedure C2ARRAYRESIZE()
   Protected arrSlot.i, newSize.i, isLocal.i, actualSlot.i
   vm_DebugFunctionName()

   arrSlot = _AR()\i
   newSize = _AR()\j
   isLocal = _AR()\n

   If isLocal
      actualSlot = _LARRAY(arrSlot)
   Else
      actualSlot = arrSlot
   EndIf

   CompilerIf #DEBUG
      Debug "ARRAYRESIZE: slot=" + Str(arrSlot) + " actualSlot=" + Str(actualSlot) + " oldSize=" + Str(gVar(actualSlot)\dta\size) + " newSize=" + Str(newSize) + " isLocal=" + Str(isLocal)
   CompilerEndIf

   ReDim gVar(actualSlot)\dta\ar(newSize - 1)
   gVar(actualSlot)\dta\size = newSize

   pc + 1
EndProcedure

;- End Array Operations

; IDE Options = PureBasic 6.21 (Windows - x64)
; EnableAsm
; EnableThread
; EnableXP
; CPU = 1
