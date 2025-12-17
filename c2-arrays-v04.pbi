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
; Version: 01
;

;- Array Operations

; ============================================================================
; V1.031.106: ARRAY MACROS
; ============================================================================
; Uses base macros from c2-vm-commands-v13.pb plus array-specific ones:
;   _ELEMSIZE     - Element size in slots (_AR()\j for structs, usually 1)
;   _ARRAYSIZE    - Array size from instruction (_AR()\n)
;   _GARR(slot)   - Global array at slot: gVar(slot)\dta\ar
;   _GARRSIZE(slot) - Global array size: gVar(slot)\dta\size
;   _LARR(offset) - Local array at offset: gLocal(gLocalBase+offset)\dta\ar
;   _LARRSIZE(offset) - Local array size
; ============================================================================

Macro _ELEMSIZE : _AR()\j : EndMacro
Macro _ARRAYSIZE : _AR()\n : EndMacro
Macro _GARR(slot) : gVar(slot)\dta\ar : EndMacro
Macro _GARRSIZE(slot) : gVar(slot)\dta\size : EndMacro
Macro _LARR(offset) : gLocal(gLocalBase + (offset))\dta\ar : EndMacro
Macro _LARRSIZE(offset) : gLocal(gLocalBase + (offset))\dta\size : EndMacro

Procedure               C2ARRAYINDEX()
   ; V1.031.106: Refactored to use macros
   ; Stack: index → computed element index
   vm_DebugFunctionName()

   sp - 1
   ; Bounds checking in debug mode only
   CompilerIf #DEBUG
      If gEvalStack(sp)\i < 0 Or gEvalStack(sp)\i >= _ARRAYSIZE
         Debug "Array index out of bounds: " + Str(gEvalStack(sp)\i) + " (size: " + Str(_ARRAYSIZE) + ")"
      EndIf
   CompilerEndIf

   ; Index already on stack, just advance
   sp + 1
   pc + 1
EndProcedure

Procedure               C2ARRAYFETCH()
   ; V1.031.106: Refactored to use macros
   ; Generic array fetch - copies entire stVTSimple to stack
   ; _ARRSLOT = array slot/offset, _ISLOCAL = 0 for global/1 for local
   ; _IDXSLOT = index var slot (>=0 = optimized path, <0 = from stack)
   Define _idx.i
   vm_DebugFunctionName()

   ; Get index from optimized slot or stack
   If _IDXSLOT >= 0
      _idx = gVar(_IDXSLOT)\i
   Else
      sp - 1
      _idx = gEvalStack(sp)\i
   EndIf

   ; Copy from array to stack based on array type
   If _ISLOCAL
      CompilerIf #DEBUG
         If _idx < 0 Or _idx >= _LARRSIZE(_ARRSLOT)
            Debug "Array bounds error: " + Str(_idx) + " size=" + Str(_LARRSIZE(_ARRSLOT))
            gExitApplication = #True : ProcedureReturn
         EndIf
      CompilerEndIf
      CopyStructure(gEvalStack(sp), _LARR(_ARRSLOT)(_idx), stVTSimple)
   Else
      CompilerIf #DEBUG
         If _idx < 0 Or _idx >= _GARRSIZE(_ARRSLOT)
            Debug "Array bounds error: " + Str(_idx) + " size=" + Str(_GARRSIZE(_ARRSLOT))
            gExitApplication = #True : ProcedureReturn
         EndIf
      CompilerEndIf
      CopyStructure(gEvalStack(sp), _GARR(_ARRSLOT)(_idx), stVTSimple)
   EndIf

   sp + 1
   pc + 1
EndProcedure

Procedure               C2ARRAYSTORE()
   ; V1.031.106: Refactored to use macros
   ; Generic array store - copies from stack to array element
   Define _idx.i
   vm_DebugFunctionName()

   ; Get index from optimized slot or stack
   If _IDXSLOT >= 0
      _idx = gVar(_IDXSLOT)\i
      sp - 1
   Else
      sp - 1
      _idx = gEvalStack(sp)\i
      sp - 1
   EndIf

   ; Copy from stack to array based on array type
   If _ISLOCAL
      CompilerIf #DEBUG
         If _idx < 0 Or _idx >= _LARRSIZE(_ARRSLOT)
            Debug "Array bounds error: " + Str(_idx) + " size=" + Str(_LARRSIZE(_ARRSLOT))
            gExitApplication = #True : ProcedureReturn
         EndIf
      CompilerEndIf
      CopyStructure(_LARR(_ARRSLOT)(_idx), gEvalStack(sp), stVTSimple)
   Else
      CompilerIf #DEBUG
         If _idx < 0 Or _idx >= _GARRSIZE(_ARRSLOT)
            Debug "Array bounds error: " + Str(_idx) + " size=" + Str(_GARRSIZE(_ARRSLOT))
            gExitApplication = #True : ProcedureReturn
         EndIf
      CompilerEndIf
      CopyStructure(_GARR(_ARRSLOT)(_idx), gEvalStack(sp), stVTSimple)
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
   gEvalStack(sp)\i = gVar(arrIdx)\dta\ar(index)\i
   ; Copy pointer metadata if present (for arrays of pointers)
   ; V1.022.35: Always clear or set ptrtype to avoid leftover values causing crashes
   If gVar(arrIdx)\dta\ar(index)\ptrtype
      gEvalStack(sp)\ptr = gVar(arrIdx)\dta\ar(index)\ptr
      gEvalStack(sp)\ptrtype = gVar(arrIdx)\dta\ar(index)\ptrtype
   Else
      gEvalStack(sp)\ptrtype = 0
   EndIf
   sp + 1
   pc + 1
EndProcedure

Procedure               C2ARRAYFETCH_INT_GLOBAL_STACK()
   ; Integer array fetch - global array, stack index
   Protected arrIdx.i, index.i
   vm_DebugFunctionName()
   arrIdx = _AR()\i
   sp - 1
   index = gEvalStack(sp)\i
   CompilerIf #DEBUG
      Protected arraySize.i = gVar(arrIdx)\dta\size
      If index < 0 Or index >= arraySize
         Debug "Array index out of bounds: " + Str(index) + " (size: " + Str(arraySize) + ") at pc=" + Str(pc)
         gExitApplication = #True
         ProcedureReturn
      EndIf
   CompilerEndIf
   gEvalStack(sp)\i = gVar(arrIdx)\dta\ar(index)\i
   ; Copy pointer metadata if present (for arrays of pointers)
   ; V1.022.35: Always clear or set ptrtype to avoid leftover values causing crashes
   If gVar(arrIdx)\dta\ar(index)\ptrtype
      gEvalStack(sp)\ptr = gVar(arrIdx)\dta\ar(index)\ptr
      gEvalStack(sp)\ptrtype = gVar(arrIdx)\dta\ar(index)\ptrtype
   Else
      gEvalStack(sp)\ptrtype = 0
   EndIf
   sp + 1
   pc + 1
EndProcedure

Procedure               C2ARRAYFETCH_INT_LOCAL_OPT()
   ; V1.18.0: Integer array fetch - local array in unified gVar[], optimized index
   Protected index.i
   Protected localSlot.i   ; V1.022.108: Cache for runtime checking
   Protected arraySize.i   ; V1.022.108: Runtime bounds checking
   vm_DebugFunctionName()
   index = gVar(_AR()\ndx)\i
   localSlot = _LARRAY(_AR()\i)

   ; V1.022.112: Always check bounds, use PrintN for release mode visibility
   arraySize = gLocal(localSlot)\dta\size
   If arraySize = 0
      PrintN("LFETCHARINT_OPT ERROR: Array at slot " + Str(localSlot) + " not allocated! pc=" + Str(pc) + " depth=" + Str(gStackDepth) + " offset=" + Str(_AR()\i))
      gExitApplication = #True
      pc + 1
      ProcedureReturn
   EndIf
   If index < 0 Or index >= arraySize
      PrintN("LFETCHARINT_OPT ERROR: Index " + Str(index) + " out of bounds (size=" + Str(arraySize) + ") pc=" + Str(pc))
      gExitApplication = #True
      pc + 1
      ProcedureReturn
   EndIf
   CompilerIf #DEBUG
      Debug "LFETCHARINT_OPT: pc=" + Str(pc) + " localSlot=" + Str(localSlot) + " index=" + Str(index) + " depth=" + Str(gStackDepth)
   CompilerEndIf
   gEvalStack(sp)\i = gLocal(localSlot)\dta\ar(index)\i
   ; Copy pointer metadata if present
   ; V1.022.35: Always clear or set ptrtype to avoid leftover values causing crashes
   If gLocal(localSlot)\dta\ar(index)\ptrtype
      gEvalStack(sp)\ptr = gLocal(localSlot)\dta\ar(index)\ptr
      gEvalStack(sp)\ptrtype = gLocal(localSlot)\dta\ar(index)\ptrtype
   Else
      gEvalStack(sp)\ptrtype = 0
   EndIf
   sp + 1
   pc + 1
EndProcedure

Procedure               C2ARRAYFETCH_INT_LOCAL_STACK()
   ; V1.18.0: Integer array fetch - local array in unified gVar[], stack index
   Protected index.i
   Protected localSlot.i   ; V1.022.108: Cache for runtime checking
   Protected arraySize.i   ; V1.022.108: Runtime bounds checking
   vm_DebugFunctionName()
   sp - 1
   index = gEvalStack(sp)\i
   localSlot = _LARRAY(_AR()\i)

   ; V1.022.112: Always check bounds, use PrintN for release mode visibility
   arraySize = gLocal(localSlot)\dta\size
   If arraySize = 0
      PrintN("LFETCHARINT_STACK ERROR: Array at slot " + Str(localSlot) + " not allocated! pc=" + Str(pc) + " depth=" + Str(gStackDepth) + " offset=" + Str(_AR()\i))
      gExitApplication = #True
      pc + 1
      ProcedureReturn
   EndIf
   If index < 0 Or index >= arraySize
      PrintN("LFETCHARINT_STACK ERROR: Index " + Str(index) + " out of bounds (size=" + Str(arraySize) + ") pc=" + Str(pc))
      gExitApplication = #True
      pc + 1
      ProcedureReturn
   EndIf
   CompilerIf #DEBUG
      Debug "LFETCHARINT_STACK: pc=" + Str(pc) + " localSlot=" + Str(localSlot) + " index=" + Str(index) + " depth=" + Str(gStackDepth)
   CompilerEndIf
   gEvalStack(sp)\i = gLocal(localSlot)\dta\ar(index)\i
   ; Copy pointer metadata if present
   ; V1.022.35: Always clear or set ptrtype to avoid leftover values causing crashes
   If gLocal(localSlot)\dta\ar(index)\ptrtype
      gEvalStack(sp)\ptr = gLocal(localSlot)\dta\ar(index)\ptr
      gEvalStack(sp)\ptrtype = gLocal(localSlot)\dta\ar(index)\ptrtype
   Else
      gEvalStack(sp)\ptrtype = 0
   EndIf
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
   gEvalStack(sp)\f = gVar(arrIdx)\dta\ar(index)\f
   ; Copy pointer metadata if present (for arrays of pointers)
   ; V1.022.35: Always clear or set ptrtype to avoid leftover values causing crashes
   If gVar(arrIdx)\dta\ar(index)\ptrtype
      gEvalStack(sp)\ptr = gVar(arrIdx)\dta\ar(index)\ptr
      gEvalStack(sp)\ptrtype = gVar(arrIdx)\dta\ar(index)\ptrtype
   Else
      gEvalStack(sp)\ptrtype = 0
   EndIf
   sp + 1
   pc + 1
EndProcedure

Procedure               C2ARRAYFETCH_FLOAT_GLOBAL_STACK()
   ; Float array fetch - global array, stack index
   Protected arrIdx.i, index.i
   vm_DebugFunctionName()
   arrIdx = _AR()\i
   sp - 1
   index = gEvalStack(sp)\i
   CompilerIf #DEBUG
      Protected arraySize.i = gVar(arrIdx)\dta\size
      If index < 0 Or index >= arraySize
         Debug "Array index out of bounds: " + Str(index) + " (size: " + Str(arraySize) + ") at pc=" + Str(pc)
         gExitApplication = #True
         ProcedureReturn
      EndIf
   CompilerEndIf
   gEvalStack(sp)\f = gVar(arrIdx)\dta\ar(index)\f
   ; Copy pointer metadata if present (for arrays of pointers)
   ; V1.022.35: Always clear or set ptrtype to avoid leftover values causing crashes
   If gVar(arrIdx)\dta\ar(index)\ptrtype
      gEvalStack(sp)\ptr = gVar(arrIdx)\dta\ar(index)\ptr
      gEvalStack(sp)\ptrtype = gVar(arrIdx)\dta\ar(index)\ptrtype
   Else
      gEvalStack(sp)\ptrtype = 0
   EndIf
   sp + 1
   pc + 1
EndProcedure

Procedure               C2ARRAYFETCH_FLOAT_LOCAL_OPT()
   ; V1.18.0: Float array fetch - local array in unified gVar[], optimized index
   Protected index.i
   Protected localSlot.i   ; V1.022.105: Debug variable
   Protected arraySize.i   ; V1.022.108: Runtime bounds checking
   vm_DebugFunctionName()
   index = gVar(_AR()\ndx)\i
   ; V1.022.105: Calculate and check local slot
   localSlot = _LARRAY(_AR()\i)

   ; V1.022.112: Always check bounds, use PrintN for release mode visibility
   arraySize = gLocal(localSlot)\dta\size
   If arraySize = 0
      PrintN("LFETCHARFLT_OPT ERROR: Array at slot " + Str(localSlot) + " not allocated! pc=" + Str(pc) + " depth=" + Str(gStackDepth) + " offset=" + Str(_AR()\i))
      gExitApplication = #True
      pc + 1
      ProcedureReturn
   EndIf
   If index < 0 Or index >= arraySize
      PrintN("LFETCHARFLT_OPT ERROR: Index " + Str(index) + " out of bounds (size=" + Str(arraySize) + ") pc=" + Str(pc))
      gExitApplication = #True
      pc + 1
      ProcedureReturn
   EndIf
   CompilerIf #DEBUG
      Debug "LFETCHARFLT_OPT: pc=" + Str(pc) + " offset=" + Str(_AR()\i) + " localSlot=" + Str(localSlot) + " index=" + Str(index) + " depth=" + Str(gStackDepth)
   CompilerEndIf
   gEvalStack(sp)\f = gLocal(localSlot)\dta\ar(index)\f
   ; Copy pointer metadata if present
   ; V1.022.35: Always clear or set ptrtype to avoid leftover values causing crashes
   If gLocal(localSlot)\dta\ar(index)\ptrtype
      gEvalStack(sp)\ptr = gLocal(localSlot)\dta\ar(index)\ptr
      gEvalStack(sp)\ptrtype = gLocal(localSlot)\dta\ar(index)\ptrtype
   Else
      gEvalStack(sp)\ptrtype = 0
   EndIf
   sp + 1
   pc + 1
EndProcedure

Procedure               C2ARRAYFETCH_FLOAT_LOCAL_STACK()
   ; V1.18.0: Float array fetch - local array in unified gVar[], stack index
   Protected index.i
   Protected localSlot.i   ; V1.022.104: Debug variable
   Protected arraySize.i   ; V1.022.108: Runtime bounds checking
   Protected spBefore.i    ; V1.022.113: For diagnostics
   vm_DebugFunctionName()
   spBefore = sp
   sp - 1
   index = gEvalStack(sp)\i
   ; V1.022.105: Calculate and check local slot
   localSlot = _LARRAY(_AR()\i)

   ; V1.022.113: Enhanced diagnostics with sp and ndx info
   arraySize = gLocal(localSlot)\dta\size
   If arraySize = 0
      PrintN("LFETCHARFLT_STACK ERROR: Array at slot " + Str(localSlot) + " not allocated! pc=" + Str(pc) + " depth=" + Str(gStackDepth) + " offset=" + Str(_AR()\i) + " sp=" + Str(spBefore))
      gExitApplication = #True
      pc + 1
      ProcedureReturn
   EndIf
   If index < 0 Or index >= arraySize
      PrintN("LFETCHARFLT_STACK ERROR: Index " + Str(index) + " out of bounds (size=" + Str(arraySize) + ") pc=" + Str(pc) + " sp=" + Str(spBefore) + " offset=" + Str(_AR()\i) + " ndx=" + Str(_AR()\ndx))
      gExitApplication = #True
      pc + 1
      ProcedureReturn
   EndIf
   CompilerIf #DEBUG
      Debug "LFETCHARFLT_STACK: pc=" + Str(pc) + " offset=" + Str(_AR()\i) + " localSlot=" + Str(localSlot) + " index=" + Str(index) + " depth=" + Str(gStackDepth)
   CompilerEndIf
   gEvalStack(sp)\f = gLocal(localSlot)\dta\ar(index)\f
   ; Copy pointer metadata if present
   ; V1.022.35: Always clear or set ptrtype to avoid leftover values causing crashes
   If gLocal(localSlot)\dta\ar(index)\ptrtype
      gEvalStack(sp)\ptr = gLocal(localSlot)\dta\ar(index)\ptr
      gEvalStack(sp)\ptrtype = gLocal(localSlot)\dta\ar(index)\ptrtype
   Else
      gEvalStack(sp)\ptrtype = 0
   EndIf
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
   gEvalStack(sp)\ss = gVar(arrIdx)\dta\ar(index)\ss
   ; Copy pointer metadata if present (for arrays of pointers)
   ; V1.022.35: Always clear or set ptrtype to avoid leftover values causing crashes
   If gVar(arrIdx)\dta\ar(index)\ptrtype
      gEvalStack(sp)\ptr = gVar(arrIdx)\dta\ar(index)\ptr
      gEvalStack(sp)\ptrtype = gVar(arrIdx)\dta\ar(index)\ptrtype
   Else
      gEvalStack(sp)\ptrtype = 0
   EndIf
   sp + 1
   pc + 1
EndProcedure

Procedure               C2ARRAYFETCH_STR_GLOBAL_STACK()
   ; String array fetch - global array, stack index
   Protected arrIdx.i, index.i
   vm_DebugFunctionName()
   arrIdx = _AR()\i
   sp - 1
   index = gEvalStack(sp)\i
   CompilerIf #DEBUG
      Protected arraySize.i = gVar(arrIdx)\dta\size
      If index < 0 Or index >= arraySize
         Debug "Array index out of bounds: " + Str(index) + " (size: " + Str(arraySize) + ") at pc=" + Str(pc)
         gExitApplication = #True
         ProcedureReturn
      EndIf
   CompilerEndIf
   gEvalStack(sp)\ss = gVar(arrIdx)\dta\ar(index)\ss
   ; Copy pointer metadata if present (for arrays of pointers)
   ; V1.022.35: Always clear or set ptrtype to avoid leftover values causing crashes
   If gVar(arrIdx)\dta\ar(index)\ptrtype
      gEvalStack(sp)\ptr = gVar(arrIdx)\dta\ar(index)\ptr
      gEvalStack(sp)\ptrtype = gVar(arrIdx)\dta\ar(index)\ptrtype
   Else
      gEvalStack(sp)\ptrtype = 0
   EndIf
   sp + 1
   pc + 1
EndProcedure

Procedure               C2ARRAYFETCH_STR_LOCAL_OPT()
   ; V1.18.0: String array fetch - local array in unified gVar[], optimized index
   Protected index.i
   vm_DebugFunctionName()
   index = gVar(_AR()\ndx)\i
   CompilerIf #DEBUG
      Protected arraySize.i
      arraySize = gLocal(_LARRAY(_AR()\i))\dta\size
      If index < 0 Or index >= arraySize
         Debug "Array index out of bounds: " + Str(index) + " (size: " + Str(arraySize) + ") at pc=" + Str(pc)
         gExitApplication = #True
         ProcedureReturn
      EndIf
   CompilerEndIf
   gEvalStack(sp)\ss = gLocal(_LARRAY(_AR()\i))\dta\ar(index)\ss
   ; Copy pointer metadata if present
   ; V1.022.35: Always clear or set ptrtype to avoid leftover values causing crashes
   If gLocal(_LARRAY(_AR()\i))\dta\ar(index)\ptrtype
      gEvalStack(sp)\ptr = gLocal(_LARRAY(_AR()\i))\dta\ar(index)\ptr
      gEvalStack(sp)\ptrtype = gLocal(_LARRAY(_AR()\i))\dta\ar(index)\ptrtype
   Else
      gEvalStack(sp)\ptrtype = 0
   EndIf
   sp + 1
   pc + 1
EndProcedure

Procedure               C2ARRAYFETCH_STR_LOCAL_STACK()
   ; V1.18.0: String array fetch - local array in unified gVar[], stack index
   Protected index.i
   vm_DebugFunctionName()
   sp - 1
   index = gEvalStack(sp)\i
   CompilerIf #DEBUG
      Protected arraySize.i
      arraySize = gLocal(_LARRAY(_AR()\i))\dta\size
      If index < 0 Or index >= arraySize
         Debug "Array index out of bounds: " + Str(index) + " (size: " + Str(arraySize) + ") at pc=" + Str(pc)
         gExitApplication = #True
         ProcedureReturn
      EndIf
   CompilerEndIf
   gEvalStack(sp)\ss = gLocal(_LARRAY(_AR()\i))\dta\ar(index)\ss
   ; Copy pointer metadata if present
   ; V1.022.35: Always clear or set ptrtype to avoid leftover values causing crashes
   If gLocal(_LARRAY(_AR()\i))\dta\ar(index)\ptrtype
      gEvalStack(sp)\ptr = gLocal(_LARRAY(_AR()\i))\dta\ar(index)\ptr
      gEvalStack(sp)\ptrtype = gLocal(_LARRAY(_AR()\i))\dta\ar(index)\ptrtype
   Else
      gEvalStack(sp)\ptrtype = 0
   EndIf
   sp + 1
   pc + 1
EndProcedure

;- V1.022.113: LOCAL_LOPT fetch handlers (local array, local index variable)
;  _AR()\i = local array offset, _AR()\ndx = local offset for index variable

Procedure               C2ARRAYFETCH_INT_LOCAL_LOPT()
   ; Integer array fetch - LOCAL array, LOCAL optimized index
   ; V1.031.19: Fixed to use gLocal[] instead of gVar[] for local slots
   Protected index.i
   Protected arrOffset.i, idxOffset.i, arrSlot.i, idxSlot.i
   Protected arraySize.i
   vm_DebugFunctionName()
   arrOffset = _AR()\i
   idxOffset = _AR()\ndx
   arrSlot = _LARRAY(arrOffset)
   idxSlot = _LARRAY(idxOffset)
   index = gLocal(idxSlot)\i   ; V1.031.19: Read index from gLocal[]

   ; V1.022.113: Always check bounds
   arraySize = gLocal(arrSlot)\dta\size
   If arraySize = 0
      Debug "LLOCAL_FETCH_I ERROR: Array at slot " + Str(arrSlot) + " not allocated! pc=" + Str(pc) + " depth=" + Str(gStackDepth)
      gExitApplication = #True
      pc + 1
      ProcedureReturn
   EndIf
   If index < 0 Or index >= arraySize
      Debug "LLOCAL_FETCH_I ERROR: Index " + Str(index) + " out of bounds (size=" + Str(arraySize) + ") pc=" + Str(pc)
      gExitApplication = #True
      pc + 1
      ProcedureReturn
   EndIf
   CompilerIf #DEBUG
      Debug "  LLOCAL_FETCH_I: depth=" + Str(gStackDepth) + " arrOff=" + Str(arrOffset) + " arrSlot=" + Str(arrSlot) + " idxOff=" + Str(idxOffset) + " idxSlot=" + Str(idxSlot) + " index=" + Str(index) + " pc=" + Str(pc)
   CompilerEndIf
   gEvalStack(sp)\i = gLocal(arrSlot)\dta\ar(index)\i
   If gLocal(arrSlot)\dta\ar(index)\ptrtype
      gEvalStack(sp)\ptr = gLocal(arrSlot)\dta\ar(index)\ptr
      gEvalStack(sp)\ptrtype = gLocal(arrSlot)\dta\ar(index)\ptrtype
   Else
      gEvalStack(sp)\ptrtype = 0
   EndIf
   sp + 1
   pc + 1
EndProcedure

Procedure               C2ARRAYFETCH_FLOAT_LOCAL_LOPT()
   ; Float array fetch - LOCAL array, LOCAL optimized index
   ; V1.031.19: Fixed to use gLocal[] instead of gVar[] for local slots
   Protected index.i
   Protected arrOffset.i, idxOffset.i, arrSlot.i, idxSlot.i
   Protected arraySize.i
   vm_DebugFunctionName()
   arrOffset = _AR()\i
   idxOffset = _AR()\ndx
   arrSlot = _LARRAY(arrOffset)
   idxSlot = _LARRAY(idxOffset)
   index = gLocal(idxSlot)\i   ; V1.031.19: Read index from gLocal[]

   ; V1.022.113: Always check bounds
   arraySize = gLocal(arrSlot)\dta\size
   If arraySize = 0
      PrintN("LLOCAL_FETCH_F ERROR: Array at slot " + Str(arrSlot) + " not allocated! pc=" + Str(pc) + " depth=" + Str(gStackDepth))
      gExitApplication = #True
      pc + 1
      ProcedureReturn
   EndIf
   If index < 0 Or index >= arraySize
      PrintN("LLOCAL_FETCH_F ERROR: Index " + Str(index) + " out of bounds (size=" + Str(arraySize) + ") pc=" + Str(pc))
      gExitApplication = #True
      pc + 1
      ProcedureReturn
   EndIf
   CompilerIf #DEBUG
      Debug "  LLOCAL_FETCH_F: depth=" + Str(gStackDepth) + " arrOff=" + Str(arrOffset) + " arrSlot=" + Str(arrSlot) + " idxOff=" + Str(idxOffset) + " idxSlot=" + Str(idxSlot) + " index=" + Str(index) + " pc=" + Str(pc)
   CompilerEndIf
   gEvalStack(sp)\f = gLocal(arrSlot)\dta\ar(index)\f
   If gLocal(arrSlot)\dta\ar(index)\ptrtype
      gEvalStack(sp)\ptr = gLocal(arrSlot)\dta\ar(index)\ptr
      gEvalStack(sp)\ptrtype = gLocal(arrSlot)\dta\ar(index)\ptrtype
   Else
      gEvalStack(sp)\ptrtype = 0
   EndIf
   sp + 1
   pc + 1
EndProcedure

Procedure               C2ARRAYFETCH_STR_LOCAL_LOPT()
   ; String array fetch - LOCAL array, LOCAL optimized index
   ; V1.031.19: Fixed to use gLocal[] instead of gVar[] for local slots
   Protected index.i
   Protected arrOffset.i, idxOffset.i, arrSlot.i, idxSlot.i
   Protected arraySize.i
   vm_DebugFunctionName()
   arrOffset = _AR()\i
   idxOffset = _AR()\ndx
   arrSlot = _LARRAY(arrOffset)
   idxSlot = _LARRAY(idxOffset)
   index = gLocal(idxSlot)\i   ; V1.031.19: Read index from gLocal[]

   ; V1.022.113: Always check bounds
   arraySize = gLocal(arrSlot)\dta\size
   If arraySize = 0
      PrintN("LLOCAL_FETCH_S ERROR: Array at slot " + Str(arrSlot) + " not allocated! pc=" + Str(pc) + " depth=" + Str(gStackDepth))
      gExitApplication = #True
      pc + 1
      ProcedureReturn
   EndIf
   If index < 0 Or index >= arraySize
      PrintN("LLOCAL_FETCH_S ERROR: Index " + Str(index) + " out of bounds (size=" + Str(arraySize) + ") pc=" + Str(pc))
      gExitApplication = #True
      pc + 1
      ProcedureReturn
   EndIf
   CompilerIf #DEBUG
      Debug "  LLOCAL_FETCH_S: depth=" + Str(gStackDepth) + " arrOff=" + Str(arrOffset) + " arrSlot=" + Str(arrSlot) + " idxOff=" + Str(idxOffset) + " idxSlot=" + Str(idxSlot) + " index=" + Str(index) + " pc=" + Str(pc)
   CompilerEndIf
   gEvalStack(sp)\ss = gLocal(arrSlot)\dta\ar(index)\ss
   If gLocal(arrSlot)\dta\ar(index)\ptrtype
      gEvalStack(sp)\ptr = gLocal(arrSlot)\dta\ar(index)\ptr
      gEvalStack(sp)\ptrtype = gLocal(arrSlot)\dta\ar(index)\ptrtype
   Else
      gEvalStack(sp)\ptrtype = 0
   EndIf
   sp + 1
   pc + 1
EndProcedure

;- Specialized ARRAYSTORE handlers (no runtime branching)

Procedure               C2ARRAYSTORE_INT_GLOBAL_OPT_OPT()
   ; Integer array store - global array, optimized index, optimized value
   Protected arrIdx.i, index.i, value.i, varSlot.i
   vm_DebugFunctionName()
   arrIdx = _AR()\i
   index = gVar(_AR()\ndx)\i
   varSlot = _AR()\n
   value = gVar(varSlot)\i
   CompilerIf #DEBUG
      Protected arraySize.i = gVar(arrIdx)\dta\size
      If index < 0 Or index >= arraySize
         Debug "Array index out of bounds: " + Str(index) + " (size: " + Str(arraySize) + ") at pc=" + Str(pc)
         gExitApplication = #True
         ProcedureReturn
      EndIf
   CompilerEndIf
   gVar(arrIdx)\dta\ar(index)\i = value
   ; Copy pointer metadata if present (for arrays of pointers)
   If gVar(varSlot)\ptrtype
      gVar(arrIdx)\dta\ar(index)\ptr = gVar(varSlot)\ptr
      gVar(arrIdx)\dta\ar(index)\ptrtype = gVar(varSlot)\ptrtype
   EndIf
   pc + 1
EndProcedure

Procedure               C2ARRAYSTORE_INT_GLOBAL_OPT_STACK()
   ; Integer array store - global array, optimized index, stack value
   Protected arrIdx.i, index.i, value.i
   vm_DebugFunctionName()
   arrIdx = _AR()\i
   index = gVar(_AR()\ndx)\i
   sp - 1
   value = gEvalStack(sp)\i
   CompilerIf #DEBUG
      Protected arraySize.i = gVar(arrIdx)\dta\size
      If index < 0 Or index >= arraySize
         Debug "Array index out of bounds: " + Str(index) + " (size: " + Str(arraySize) + ") at pc=" + Str(pc)
         gExitApplication = #True
         ProcedureReturn
      EndIf
   CompilerEndIf
   gVar(arrIdx)\dta\ar(index)\i = value
   ; Copy pointer metadata if present (for arrays of pointers)
   If gEvalStack(sp)\ptrtype
      gVar(arrIdx)\dta\ar(index)\ptr = gEvalStack(sp)\ptr
      gVar(arrIdx)\dta\ar(index)\ptrtype = gEvalStack(sp)\ptrtype
   EndIf
   pc + 1
EndProcedure

Procedure               C2ARRAYSTORE_INT_GLOBAL_OPT_LOPT()
   ; V1.022.114: Integer array store - global array, GLOBAL opt index, LOCAL opt value
   ; Used when index is constant but value comes from local temp (function scope)
   ; V1.031.21: Fixed to use gLocal[] instead of gVar[] for local value slot
   Protected arrIdx.i, index.i, valSlot.i, value.i
   vm_DebugFunctionName()
   arrIdx = _AR()\i
   index = gVar(_AR()\ndx)\i           ; Read index from GLOBAL slot
   valSlot = _LARRAY(_AR()\n)
   value = gLocal(valSlot)\i           ; Read value from LOCAL slot (gLocal, not gVar)
   CompilerIf #DEBUG
      Protected arraySize.i = gVar(arrIdx)\dta\size
      If index < 0 Or index >= arraySize
         Debug "Array index out of bounds: " + Str(index) + " (size: " + Str(arraySize) + ") at pc=" + Str(pc)
         gExitApplication = #True
         ProcedureReturn
      EndIf
   CompilerEndIf
   gVar(arrIdx)\dta\ar(index)\i = value
   If gLocal(valSlot)\ptrtype
      gVar(arrIdx)\dta\ar(index)\ptr = gLocal(valSlot)\ptr
      gVar(arrIdx)\dta\ar(index)\ptrtype = gLocal(valSlot)\ptrtype
   EndIf
   pc + 1
EndProcedure

Procedure               C2ARRAYSTORE_INT_GLOBAL_STACK_OPT()
   ; Integer array store - global array, stack index, optimized value
   Protected arrIdx.i, index.i, value.i
   vm_DebugFunctionName()
   arrIdx = _AR()\i
   sp - 1
   index = gEvalStack(sp)\i
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
   ; Copy pointer metadata if present (for arrays of pointers)
   If gVar(_AR()\n)\ptrtype
      gVar(arrIdx)\dta\ar(index)\ptr = gVar(_AR()\n)\ptr
      gVar(arrIdx)\dta\ar(index)\ptrtype = gVar(_AR()\n)\ptrtype
   EndIf
   pc + 1
EndProcedure

Procedure               C2ARRAYSTORE_INT_GLOBAL_STACK_STACK()
   ; Integer array store - global array, stack index, stack value
   Protected arrIdx.i, index.i, value.i
   vm_DebugFunctionName()
   arrIdx = _AR()\i
   sp - 1
   index = gEvalStack(sp)\i
   sp - 1
   value = gEvalStack(sp)\i
   CompilerIf #DEBUG
      Protected arraySize.i = gVar(arrIdx)\dta\size
      If index < 0 Or index >= arraySize
         Debug "Array index out of bounds: " + Str(index) + " (size: " + Str(arraySize) + ") at pc=" + Str(pc)
         gExitApplication = #True
         ProcedureReturn
      EndIf
   CompilerEndIf
   gVar(arrIdx)\dta\ar(index)\i = value
   ; Copy pointer metadata if present (for arrays of pointers)
   If gEvalStack(sp)\ptrtype
      gVar(arrIdx)\dta\ar(index)\ptr = gEvalStack(sp)\ptr
      gVar(arrIdx)\dta\ar(index)\ptrtype = gEvalStack(sp)\ptrtype
   EndIf
   pc + 1
EndProcedure

Procedure               C2ARRAYSTORE_INT_LOCAL_OPT_OPT()
   ; V1.18.0: Integer array store - local array in unified gVar[], optimized index, optimized value
   Protected index.i, value.i
   vm_DebugFunctionName()
   index = gVar(_AR()\ndx)\i
   value = gVar(_AR()\n)\i
   CompilerIf #DEBUG
      Protected arraySize.i
      arraySize = gLocal(_LARRAY(_AR()\i))\dta\size
      If index < 0 Or index >= arraySize
         Debug "Array index out of bounds: " + Str(index) + " (size: " + Str(arraySize) + ") at pc=" + Str(pc)
         gExitApplication = #True
         ProcedureReturn
      EndIf
   CompilerEndIf
   gLocal(_LARRAY(_AR()\i))\dta\ar(index)\i = value
   pc + 1
EndProcedure

Procedure               C2ARRAYSTORE_INT_LOCAL_OPT_STACK()
   ; V1.18.0: Integer array store - local array in unified gVar[], optimized index, stack value
   Protected index.i, value.i
   vm_DebugFunctionName()
   index = gVar(_AR()\ndx)\i
   sp - 1
   value = gEvalStack(sp)\i
   CompilerIf #DEBUG
      Protected arraySize.i, actualSlot.i
      actualSlot = _LARRAY(_AR()\i)
      arraySize = gVar(actualSlot)\dta\size
      Debug "ARRAYSTORE_INT_LOCAL_OPT_STACK: paramOffset=" + Str(_AR()\i) + " actualSlot=" + Str(actualSlot) + " index=" + Str(index) + " arraySize=" + Str(arraySize) + " value=" + Str(value) + " pc=" + Str(pc)
      If index < 0 Or index >= arraySize
         Debug "Array index out of bounds: " + Str(index) + " (size: " + Str(arraySize) + ") at pc=" + Str(pc)
         gExitApplication = #True
         ProcedureReturn
      EndIf
   CompilerEndIf
   gLocal(_LARRAY(_AR()\i))\dta\ar(index)\i = value
   ; Copy pointer metadata if present
   If gEvalStack(sp)\ptrtype
      gLocal(_LARRAY(_AR()\i))\dta\ar(index)\ptr = gEvalStack(sp)\ptr
      gLocal(_LARRAY(_AR()\i))\dta\ar(index)\ptrtype = gEvalStack(sp)\ptrtype
   EndIf
   pc + 1
EndProcedure

Procedure               C2ARRAYSTORE_INT_LOCAL_OPT_LOPT()
   ; V1.022.115: Integer array store - local array, GLOBAL opt index, LOCAL opt value
   ; Used when index is constant but value comes from local temp (function scope)
   ; V1.031.20: Fixed to use gLocal[] for LOCAL value slot
   Protected index.i, valSlot.i, value.i
   vm_DebugFunctionName()
   index = gVar(_AR()\ndx)\i           ; Read index from GLOBAL slot
   valSlot = _LARRAY(_AR()\n)
   value = gLocal(valSlot)\i           ; Read value from LOCAL slot
   CompilerIf #DEBUG
      Protected arraySize.i, actualSlot.i
      actualSlot = _LARRAY(_AR()\i)
      arraySize = gLocal(actualSlot)\dta\size
      If index < 0 Or index >= arraySize
         Debug "Array index out of bounds: " + Str(index) + " (size: " + Str(arraySize) + ") at pc=" + Str(pc)
         gExitApplication = #True
         ProcedureReturn
      EndIf
   CompilerEndIf
   gLocal(_LARRAY(_AR()\i))\dta\ar(index)\i = value
   If gLocal(valSlot)\ptrtype
      gLocal(_LARRAY(_AR()\i))\dta\ar(index)\ptr = gLocal(valSlot)\ptr
      gLocal(_LARRAY(_AR()\i))\dta\ar(index)\ptrtype = gLocal(valSlot)\ptrtype
   EndIf
   pc + 1
EndProcedure

Procedure               C2ARRAYSTORE_INT_LOCAL_STACK_OPT()
   ; V1.18.0: Integer array store - local array in unified gVar[], stack index, optimized value
   Protected index.i, value.i
   vm_DebugFunctionName()
   sp - 1
   index = gEvalStack(sp)\i
   value = gVar(_AR()\n)\i
   CompilerIf #DEBUG
      Protected arraySize.i
      arraySize = gLocal(_LARRAY(_AR()\i))\dta\size
      If index < 0 Or index >= arraySize
         Debug "Array index out of bounds: " + Str(index) + " (size: " + Str(arraySize) + ") at pc=" + Str(pc)
         gExitApplication = #True
         ProcedureReturn
      EndIf
   CompilerEndIf
   gLocal(_LARRAY(_AR()\i))\dta\ar(index)\i = value
   ; Copy pointer metadata if present
   If gVar(_AR()\n)\ptrtype
      gLocal(_LARRAY(_AR()\i))\dta\ar(index)\ptr = gVar(_AR()\n)\ptr
      gLocal(_LARRAY(_AR()\i))\dta\ar(index)\ptrtype = gVar(_AR()\n)\ptrtype
   EndIf
   pc + 1
EndProcedure

Procedure               C2ARRAYSTORE_INT_LOCAL_STACK_STACK()
   ; V1.18.0: Integer array store - local array in unified gVar[], stack index, stack value
   Protected index.i, value.i
   vm_DebugFunctionName()
   sp - 1
   index = gEvalStack(sp)\i
   sp - 1
   value = gEvalStack(sp)\i
   CompilerIf #DEBUG
      Protected arraySize.i
      arraySize = gLocal(_LARRAY(_AR()\i))\dta\size
      If index < 0 Or index >= arraySize
         Debug "Array index out of bounds: " + Str(index) + " (size: " + Str(arraySize) + ") at pc=" + Str(pc)
         gExitApplication = #True
         ProcedureReturn
      EndIf
   CompilerEndIf
   gLocal(_LARRAY(_AR()\i))\dta\ar(index)\i = value
   ; Copy pointer metadata if present
   If gEvalStack(sp)\ptrtype
      gLocal(_LARRAY(_AR()\i))\dta\ar(index)\ptr = gEvalStack(sp)\ptr
      gLocal(_LARRAY(_AR()\i))\dta\ar(index)\ptrtype = gEvalStack(sp)\ptrtype
   EndIf
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
   ; Copy pointer metadata if present (for arrays of pointers)
   If gVar(_AR()\n)\ptrtype
      gVar(arrIdx)\dta\ar(index)\ptr = gVar(_AR()\n)\ptr
      gVar(arrIdx)\dta\ar(index)\ptrtype = gVar(_AR()\n)\ptrtype
   EndIf
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
   value = gEvalStack(sp)\f
   CompilerIf #DEBUG
      Protected arraySize.i = gVar(arrIdx)\dta\size
      If index < 0 Or index >= arraySize
         Debug "Array index out of bounds: " + Str(index) + " (size: " + Str(arraySize) + ") at pc=" + Str(pc)
         gExitApplication = #True
         ProcedureReturn
      EndIf
   CompilerEndIf
   gVar(arrIdx)\dta\ar(index)\f = value
   ; Copy pointer metadata if present (for arrays of pointers)
   If gEvalStack(sp)\ptrtype
      gVar(arrIdx)\dta\ar(index)\ptr = gEvalStack(sp)\ptr
      gVar(arrIdx)\dta\ar(index)\ptrtype = gEvalStack(sp)\ptrtype
   EndIf
   pc + 1
EndProcedure

Procedure               C2ARRAYSTORE_FLOAT_GLOBAL_OPT_LOPT()
   ; V1.022.114: Float array store - global array, GLOBAL opt index, LOCAL opt value
   ; Used when index is constant but value comes from local temp (function scope)
   ; V1.031.21: Fixed to use gLocal[] instead of gVar[] for local value slot
   Protected arrIdx.i, index.i, valSlot.i
   Protected value.f
   vm_DebugFunctionName()
   arrIdx = _AR()\i
   index = gVar(_AR()\ndx)\i           ; Read index from GLOBAL slot
   valSlot = _LARRAY(_AR()\n)
   value = gLocal(valSlot)\f           ; Read value from LOCAL slot (gLocal, not gVar)
   CompilerIf #DEBUG
      Protected arraySize.i = gVar(arrIdx)\dta\size
      If index < 0 Or index >= arraySize
         Debug "Array index out of bounds: " + Str(index) + " (size: " + Str(arraySize) + ") at pc=" + Str(pc)
         gExitApplication = #True
         ProcedureReturn
      EndIf
   CompilerEndIf
   gVar(arrIdx)\dta\ar(index)\f = value
   If gLocal(valSlot)\ptrtype
      gVar(arrIdx)\dta\ar(index)\ptr = gLocal(valSlot)\ptr
      gVar(arrIdx)\dta\ar(index)\ptrtype = gLocal(valSlot)\ptrtype
   EndIf
   pc + 1
EndProcedure

Procedure               C2ARRAYSTORE_FLOAT_GLOBAL_STACK_OPT()
   ; Float array store - global array, stack index, optimized value
   Protected arrIdx.i, index.i
   Protected value.f
   vm_DebugFunctionName()
   arrIdx = _AR()\i
   sp - 1
   index = gEvalStack(sp)\i
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
   ; Copy pointer metadata if present (for arrays of pointers)
   If gVar(_AR()\n)\ptrtype
      gVar(arrIdx)\dta\ar(index)\ptr = gVar(_AR()\n)\ptr
      gVar(arrIdx)\dta\ar(index)\ptrtype = gVar(_AR()\n)\ptrtype
   EndIf
   pc + 1
EndProcedure

Procedure               C2ARRAYSTORE_FLOAT_GLOBAL_STACK_STACK()
   ; Float array store - global array, stack index, stack value
   Protected arrIdx.i, index.i
   Protected value.f
   vm_DebugFunctionName()
   arrIdx = _AR()\i
   sp - 1
   index = gEvalStack(sp)\i
   sp - 1
   value = gEvalStack(sp)\f
   CompilerIf #DEBUG
      Protected arraySize.i = gVar(arrIdx)\dta\size
      If index < 0 Or index >= arraySize
         Debug "Array index out of bounds: " + Str(index) + " (size: " + Str(arraySize) + ") at pc=" + Str(pc)
         gExitApplication = #True
         ProcedureReturn
      EndIf
   CompilerEndIf
   gVar(arrIdx)\dta\ar(index)\f = value
   ; Copy pointer metadata if present (for arrays of pointers)
   If gEvalStack(sp)\ptrtype
      gVar(arrIdx)\dta\ar(index)\ptr = gEvalStack(sp)\ptr
      gVar(arrIdx)\dta\ar(index)\ptrtype = gEvalStack(sp)\ptrtype
   EndIf
   pc + 1
EndProcedure

Procedure               C2ARRAYSTORE_FLOAT_LOCAL_OPT_OPT()
   ; V1.18.0: Float array store - local array in unified gVar[], optimized index, optimized value
   Protected index.i
   Protected value.f
   Protected localSlot.i   ; V1.022.105: Debug variable
   vm_DebugFunctionName()
   index = gVar(_AR()\ndx)\i
   value = gVar(_AR()\n)\f
   ; V1.022.105: Calculate and check local slot
   localSlot = _LARRAY(_AR()\i)
   CompilerIf #DEBUG
      Debug "LSTOREARFLT_OO: pc=" + Str(pc) + " offset=" + Str(_AR()\i) + " localSlot=" + Str(localSlot) + " index=" + Str(index) + " depth=" + Str(gStackDepth)
      If localSlot < 0 Or localSlot > gLocalStack
         Debug "  FATAL: localSlot " + Str(localSlot) + " out of bounds [0.." + Str(gLocalStack) + "]"
         gExitApplication = #True
         ProcedureReturn
      EndIf
      If gLocal(localSlot)\dta = 0
         Debug "  ERROR: Local array at slot " + Str(localSlot) + " has no dta allocated!"
         gExitApplication = #True
         ProcedureReturn
      EndIf
      Protected arraySize.i
      arraySize = gLocal(localSlot)\dta\size
      If index < 0 Or index >= arraySize
         Debug "Array index out of bounds: " + Str(index) + " (size: " + Str(arraySize) + ") at pc=" + Str(pc)
         gExitApplication = #True
         ProcedureReturn
      EndIf
   CompilerEndIf
   gLocal(localSlot)\dta\ar(index)\f = value
   ; Copy pointer metadata if present
   If gVar(_AR()\n)\ptrtype
      gLocal(localSlot)\dta\ar(index)\ptr = gVar(_AR()\n)\ptr
      gLocal(localSlot)\dta\ar(index)\ptrtype = gVar(_AR()\n)\ptrtype
   EndIf
   pc + 1
EndProcedure

Procedure               C2ARRAYSTORE_FLOAT_LOCAL_OPT_STACK()
   ; V1.18.0: Float array store - local array in unified gVar[], optimized index, stack value
   Protected index.i
   Protected value.f
   vm_DebugFunctionName()
   index = gVar(_AR()\ndx)\i
   sp - 1
   value = gEvalStack(sp)\f
   CompilerIf #DEBUG
      Protected arraySize.i
      arraySize = gLocal(_LARRAY(_AR()\i))\dta\size
      If index < 0 Or index >= arraySize
         Debug "Array index out of bounds: " + Str(index) + " (size: " + Str(arraySize) + ") at pc=" + Str(pc)
         gExitApplication = #True
         ProcedureReturn
      EndIf
   CompilerEndIf
   gLocal(_LARRAY(_AR()\i))\dta\ar(index)\f = value
   ; Copy pointer metadata if present
   If gEvalStack(sp)\ptrtype
      gLocal(_LARRAY(_AR()\i))\dta\ar(index)\ptr = gEvalStack(sp)\ptr
      gLocal(_LARRAY(_AR()\i))\dta\ar(index)\ptrtype = gEvalStack(sp)\ptrtype
   EndIf
   pc + 1
EndProcedure

Procedure               C2ARRAYSTORE_FLOAT_LOCAL_OPT_LOPT()
   ; V1.022.115: Float array store - local array, GLOBAL opt index, LOCAL opt value
   ; Used when index is constant but value comes from local temp (function scope)
   ; V1.031.20: Fixed to use gLocal[] for LOCAL value slot
   Protected index.i, valSlot.i
   Protected value.f
   vm_DebugFunctionName()
   index = gVar(_AR()\ndx)\i           ; Read index from GLOBAL slot
   valSlot = _LARRAY(_AR()\n)
   value = gLocal(valSlot)\f           ; Read value from LOCAL slot
   CompilerIf #DEBUG
      Protected arraySize.i
      arraySize = gLocal(_LARRAY(_AR()\i))\dta\size
      If index < 0 Or index >= arraySize
         Debug "Array index out of bounds: " + Str(index) + " (size: " + Str(arraySize) + ") at pc=" + Str(pc)
         gExitApplication = #True
         ProcedureReturn
      EndIf
   CompilerEndIf
   gLocal(_LARRAY(_AR()\i))\dta\ar(index)\f = value
   If gLocal(valSlot)\ptrtype
      gLocal(_LARRAY(_AR()\i))\dta\ar(index)\ptr = gLocal(valSlot)\ptr
      gLocal(_LARRAY(_AR()\i))\dta\ar(index)\ptrtype = gLocal(valSlot)\ptrtype
   EndIf
   pc + 1
EndProcedure

Procedure               C2ARRAYSTORE_FLOAT_LOCAL_STACK_OPT()
   ; V1.18.0: Float array store - local array in unified gVar[], stack index, optimized value
   Protected index.i
   Protected value.f
   vm_DebugFunctionName()
   sp - 1
   index = gEvalStack(sp)\i
   value = gVar(_AR()\n)\f
   CompilerIf #DEBUG
      Protected arraySize.i
      arraySize = gLocal(_LARRAY(_AR()\i))\dta\size
      If index < 0 Or index >= arraySize
         Debug "Array index out of bounds: " + Str(index) + " (size: " + Str(arraySize) + ") at pc=" + Str(pc)
         gExitApplication = #True
         ProcedureReturn
      EndIf
   CompilerEndIf
   gLocal(_LARRAY(_AR()\i))\dta\ar(index)\f = value
   ; Copy pointer metadata if present
   If gVar(_AR()\n)\ptrtype
      gLocal(_LARRAY(_AR()\i))\dta\ar(index)\ptr = gVar(_AR()\n)\ptr
      gLocal(_LARRAY(_AR()\i))\dta\ar(index)\ptrtype = gVar(_AR()\n)\ptrtype
   EndIf
   pc + 1
EndProcedure

Procedure               C2ARRAYSTORE_FLOAT_LOCAL_STACK_STACK()
   ; V1.18.0: Float array store - local array in unified gVar[], stack index, stack value
   Protected index.i
   Protected value.f
   vm_DebugFunctionName()
   sp - 1
   index = gEvalStack(sp)\i
   sp - 1
   value = gEvalStack(sp)\f
   CompilerIf #DEBUG
      Protected arraySize.i
      arraySize = gLocal(_LARRAY(_AR()\i))\dta\size
      If index < 0 Or index >= arraySize
         Debug "Array index out of bounds: " + Str(index) + " (size: " + Str(arraySize) + ") at pc=" + Str(pc)
         gExitApplication = #True
         ProcedureReturn
      EndIf
   CompilerEndIf
   gLocal(_LARRAY(_AR()\i))\dta\ar(index)\f = value
   ; Copy pointer metadata if present
   If gEvalStack(sp)\ptrtype
      gLocal(_LARRAY(_AR()\i))\dta\ar(index)\ptr = gEvalStack(sp)\ptr
      gLocal(_LARRAY(_AR()\i))\dta\ar(index)\ptrtype = gEvalStack(sp)\ptrtype
   EndIf
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
   ; Copy pointer metadata if present (for arrays of pointers)
   If gVar(_AR()\n)\ptrtype
      gVar(arrIdx)\dta\ar(index)\ptr = gVar(_AR()\n)\ptr
      gVar(arrIdx)\dta\ar(index)\ptrtype = gVar(_AR()\n)\ptrtype
   EndIf
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
   value = gEvalStack(sp)\ss
   CompilerIf #DEBUG
      Protected arraySize.i = gVar(arrIdx)\dta\size
      If index < 0 Or index >= arraySize
         Debug "Array index out of bounds: " + Str(index) + " (size: " + Str(arraySize) + ") at pc=" + Str(pc)
         gExitApplication = #True
         ProcedureReturn
      EndIf
   CompilerEndIf
   gVar(arrIdx)\dta\ar(index)\ss = value
   ; Copy pointer metadata if present (for arrays of pointers)
   If gEvalStack(sp)\ptrtype
      gVar(arrIdx)\dta\ar(index)\ptr = gEvalStack(sp)\ptr
      gVar(arrIdx)\dta\ar(index)\ptrtype = gEvalStack(sp)\ptrtype
   EndIf
   pc + 1
EndProcedure

Procedure               C2ARRAYSTORE_STR_GLOBAL_OPT_LOPT()
   ; V1.022.114: String array store - global array, GLOBAL opt index, LOCAL opt value
   ; Used when index is constant but value comes from local temp (function scope)
   ; V1.031.21: Fixed to use gLocal[] instead of gVar[] for local value slot
   Protected arrIdx.i, index.i, valSlot.i
   Protected value.s
   vm_DebugFunctionName()
   arrIdx = _AR()\i
   index = gVar(_AR()\ndx)\i           ; Read index from GLOBAL slot
   valSlot = _LARRAY(_AR()\n)
   value = gLocal(valSlot)\ss          ; Read value from LOCAL slot (gLocal, not gVar)
   CompilerIf #DEBUG
      Protected arraySize.i = gVar(arrIdx)\dta\size
      If index < 0 Or index >= arraySize
         Debug "Array index out of bounds: " + Str(index) + " (size: " + Str(arraySize) + ") at pc=" + Str(pc)
         gExitApplication = #True
         ProcedureReturn
      EndIf
   CompilerEndIf
   gVar(arrIdx)\dta\ar(index)\ss = value
   If gLocal(valSlot)\ptrtype
      gVar(arrIdx)\dta\ar(index)\ptr = gLocal(valSlot)\ptr
      gVar(arrIdx)\dta\ar(index)\ptrtype = gLocal(valSlot)\ptrtype
   EndIf
   pc + 1
EndProcedure

Procedure               C2ARRAYSTORE_STR_GLOBAL_STACK_OPT()
   ; String array store - global array, stack index, optimized value
   Protected arrIdx.i, index.i
   Protected value.s
   vm_DebugFunctionName()
   arrIdx = _AR()\i
   sp - 1
   index = gEvalStack(sp)\i
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
   ; Copy pointer metadata if present (for arrays of pointers)
   If gVar(_AR()\n)\ptrtype
      gVar(arrIdx)\dta\ar(index)\ptr = gVar(_AR()\n)\ptr
      gVar(arrIdx)\dta\ar(index)\ptrtype = gVar(_AR()\n)\ptrtype
   EndIf
   pc + 1
EndProcedure

Procedure               C2ARRAYSTORE_STR_GLOBAL_STACK_STACK()
   ; String array store - global array, stack index, stack value
   Protected arrIdx.i, index.i
   Protected value.s
   vm_DebugFunctionName()
   arrIdx = _AR()\i
   sp - 1
   index = gEvalStack(sp)\i
   sp - 1
   value = gEvalStack(sp)\ss
   CompilerIf #DEBUG
      Protected arraySize.i = gVar(arrIdx)\dta\size
      If index < 0 Or index >= arraySize
         Debug "Array index out of bounds: " + Str(index) + " (size: " + Str(arraySize) + ") at pc=" + Str(pc)
         gExitApplication = #True
         ProcedureReturn
      EndIf
   CompilerEndIf
   gVar(arrIdx)\dta\ar(index)\ss = value
   ; Copy pointer metadata if present (for arrays of pointers)
   If gEvalStack(sp)\ptrtype
      gVar(arrIdx)\dta\ar(index)\ptr = gEvalStack(sp)\ptr
      gVar(arrIdx)\dta\ar(index)\ptrtype = gEvalStack(sp)\ptrtype
   EndIf
   pc + 1
EndProcedure

Procedure               C2ARRAYSTORE_STR_LOCAL_OPT_OPT()
   ; V1.18.0: String array store - local array in unified gVar[], optimized index, optimized value
   Protected index.i
   Protected value.s
   vm_DebugFunctionName()
   index = gVar(_AR()\ndx)\i
   value = gVar(_AR()\n)\ss
   CompilerIf #DEBUG
      Protected arraySize.i
      arraySize = gLocal(_LARRAY(_AR()\i))\dta\size
      If index < 0 Or index >= arraySize
         Debug "Array index out of bounds: " + Str(index) + " (size: " + Str(arraySize) + ") at pc=" + Str(pc)
         gExitApplication = #True
         ProcedureReturn
      EndIf
   CompilerEndIf
   gLocal(_LARRAY(_AR()\i))\dta\ar(index)\ss = value
   ; Copy pointer metadata if present
   If gVar(_AR()\n)\ptrtype
      gLocal(_LARRAY(_AR()\i))\dta\ar(index)\ptr = gVar(_AR()\n)\ptr
      gLocal(_LARRAY(_AR()\i))\dta\ar(index)\ptrtype = gVar(_AR()\n)\ptrtype
   EndIf
   pc + 1
EndProcedure

Procedure               C2ARRAYSTORE_STR_LOCAL_OPT_STACK()
   ; V1.18.0: String array store - local array in unified gVar[], optimized index, stack value
   Protected index.i
   Protected value.s
   vm_DebugFunctionName()
   index = gVar(_AR()\ndx)\i
   sp - 1
   value = gEvalStack(sp)\ss
   CompilerIf #DEBUG
      Protected arraySize.i
      arraySize = gLocal(_LARRAY(_AR()\i))\dta\size
      If index < 0 Or index >= arraySize
         Debug "Array index out of bounds: " + Str(index) + " (size: " + Str(arraySize) + ") at pc=" + Str(pc)
         gExitApplication = #True
         ProcedureReturn
      EndIf
   CompilerEndIf
   gLocal(_LARRAY(_AR()\i))\dta\ar(index)\ss = value
   ; Copy pointer metadata if present
   If gEvalStack(sp)\ptrtype
      gLocal(_LARRAY(_AR()\i))\dta\ar(index)\ptr = gEvalStack(sp)\ptr
      gLocal(_LARRAY(_AR()\i))\dta\ar(index)\ptrtype = gEvalStack(sp)\ptrtype
   EndIf
   pc + 1
EndProcedure

Procedure               C2ARRAYSTORE_STR_LOCAL_OPT_LOPT()
   ; V1.022.115: String array store - local array, GLOBAL opt index, LOCAL opt value
   ; Used when index is constant but value comes from local temp (function scope)
   ; V1.031.20: Fixed to use gLocal[] for LOCAL value slot
   Protected index.i, valSlot.i
   Protected value.s
   vm_DebugFunctionName()
   index = gVar(_AR()\ndx)\i           ; Read index from GLOBAL slot
   valSlot = _LARRAY(_AR()\n)
   value = gLocal(valSlot)\ss          ; Read value from LOCAL slot
   CompilerIf #DEBUG
      Protected arraySize.i
      arraySize = gLocal(_LARRAY(_AR()\i))\dta\size
      If index < 0 Or index >= arraySize
         Debug "Array index out of bounds: " + Str(index) + " (size: " + Str(arraySize) + ") at pc=" + Str(pc)
         gExitApplication = #True
         ProcedureReturn
      EndIf
   CompilerEndIf
   gLocal(_LARRAY(_AR()\i))\dta\ar(index)\ss = value
   If gLocal(valSlot)\ptrtype
      gLocal(_LARRAY(_AR()\i))\dta\ar(index)\ptr = gLocal(valSlot)\ptr
      gLocal(_LARRAY(_AR()\i))\dta\ar(index)\ptrtype = gLocal(valSlot)\ptrtype
   EndIf
   pc + 1
EndProcedure

Procedure               C2ARRAYSTORE_STR_LOCAL_STACK_OPT()
   ; V1.18.0: String array store - local array in unified gVar[], stack index, optimized value
   Protected index.i
   Protected value.s
   vm_DebugFunctionName()
   sp - 1
   index = gEvalStack(sp)\i
   value = gVar(_AR()\n)\ss
   CompilerIf #DEBUG
      Protected arraySize.i
      arraySize = gLocal(_LARRAY(_AR()\i))\dta\size
      If index < 0 Or index >= arraySize
         Debug "Array index out of bounds: " + Str(index) + " (size: " + Str(arraySize) + ") at pc=" + Str(pc)
         gExitApplication = #True
         ProcedureReturn
      EndIf
   CompilerEndIf
   gLocal(_LARRAY(_AR()\i))\dta\ar(index)\ss = value
   ; Copy pointer metadata if present
   If gVar(_AR()\n)\ptrtype
      gLocal(_LARRAY(_AR()\i))\dta\ar(index)\ptr = gVar(_AR()\n)\ptr
      gLocal(_LARRAY(_AR()\i))\dta\ar(index)\ptrtype = gVar(_AR()\n)\ptrtype
   EndIf
   pc + 1
EndProcedure

Procedure               C2ARRAYSTORE_STR_LOCAL_STACK_STACK()
   ; V1.18.0: String array store - local array in unified gVar[], stack index, stack value
   Protected index.i
   Protected value.s
   vm_DebugFunctionName()
   sp - 1
   index = gEvalStack(sp)\i
   sp - 1
   value = gEvalStack(sp)\ss
   CompilerIf #DEBUG
      Protected arraySize.i
      arraySize = gLocal(_LARRAY(_AR()\i))\dta\size
      If index < 0 Or index >= arraySize
         Debug "Array index out of bounds: " + Str(index) + " (size: " + Str(arraySize) + ") at pc=" + Str(pc)
         gExitApplication = #True
         ProcedureReturn
      EndIf
   CompilerEndIf
   gLocal(_LARRAY(_AR()\i))\dta\ar(index)\ss = value
   ; Copy pointer metadata if present
   If gEvalStack(sp)\ptrtype
      gLocal(_LARRAY(_AR()\i))\dta\ar(index)\ptr = gEvalStack(sp)\ptr
      gLocal(_LARRAY(_AR()\i))\dta\ar(index)\ptrtype = gEvalStack(sp)\ptrtype
   EndIf
   pc + 1
EndProcedure

;- V1.022.113: LOCAL_LOPT store handlers (local array, local index variable)
;  These handle stores to local arrays where the index is also a local variable

Procedure               C2ARRAYSTORE_INT_LOCAL_LOPT_LOPT()
   ; V1.022.113: Integer array store - local array, local index, local value
   ; V1.031.19: Fixed to use gLocal[] instead of gVar[] for local slots
   Protected arrSlot.i, idxSlot.i, valSlot.i, index.i, value.i
   vm_DebugFunctionName()
   arrSlot = _LARRAY(_AR()\i)
   idxSlot = _LARRAY(_AR()\ndx)
   valSlot = _LARRAY(_AR()\n)
   index = gLocal(idxSlot)\i
   value = gLocal(valSlot)\i
   CompilerIf #DEBUG
      Protected arraySize.i = gLocal(arrSlot)\dta\size
      If index < 0 Or index >= arraySize
         Debug "LSTOREARRINT_LOLO: Array index out of bounds: " + Str(index) + " (size: " + Str(arraySize) + ") at pc=" + Str(pc)
         gExitApplication = #True
         ProcedureReturn
      EndIf
   CompilerEndIf
   gLocal(arrSlot)\dta\ar(index)\i = value
   If gLocal(valSlot)\ptrtype
      gLocal(arrSlot)\dta\ar(index)\ptr = gLocal(valSlot)\ptr
      gLocal(arrSlot)\dta\ar(index)\ptrtype = gLocal(valSlot)\ptrtype
   EndIf
   pc + 1
EndProcedure

Procedure               C2ARRAYSTORE_INT_LOCAL_LOPT_OPT()
   ; V1.022.113: Integer array store - local array, local index, global value
   ; V1.031.19: Fixed to use gLocal[] for local slots
   Protected arrSlot.i, idxSlot.i, index.i, value.i
   vm_DebugFunctionName()
   arrSlot = _LARRAY(_AR()\i)
   idxSlot = _LARRAY(_AR()\ndx)
   index = gLocal(idxSlot)\i
   value = gVar(_AR()\n)\i
   CompilerIf #DEBUG
      Protected arraySize.i = gLocal(arrSlot)\dta\size
      If index < 0 Or index >= arraySize
         Debug "LSTOREARRINT_LOGO: Array index out of bounds: " + Str(index) + " (size: " + Str(arraySize) + ") at pc=" + Str(pc)
         gExitApplication = #True
         ProcedureReturn
      EndIf
   CompilerEndIf
   gLocal(arrSlot)\dta\ar(index)\i = value
   If gVar(_AR()\n)\ptrtype
      gLocal(arrSlot)\dta\ar(index)\ptr = gVar(_AR()\n)\ptr
      gLocal(arrSlot)\dta\ar(index)\ptrtype = gVar(_AR()\n)\ptrtype
   EndIf
   pc + 1
EndProcedure

Procedure               C2ARRAYSTORE_INT_LOCAL_LOPT_STACK()
   ; V1.022.113: Integer array store - local array, local index, stack value
   ; V1.031.19: Fixed to use gLocal[] for local slots
   Protected arrSlot.i, idxSlot.i, index.i, value.i
   vm_DebugFunctionName()
   arrSlot = _LARRAY(_AR()\i)
   idxSlot = _LARRAY(_AR()\ndx)
   index = gLocal(idxSlot)\i
   sp - 1
   value = gEvalStack(sp)\i
   CompilerIf #DEBUG
      Protected arraySize.i = gLocal(arrSlot)\dta\size
      If index < 0 Or index >= arraySize
         Debug "LSTOREARRINT_LOST: Array index out of bounds: " + Str(index) + " (size: " + Str(arraySize) + ") at pc=" + Str(pc)
         gExitApplication = #True
         ProcedureReturn
      EndIf
   CompilerEndIf
   gLocal(arrSlot)\dta\ar(index)\i = value
   If gEvalStack(sp)\ptrtype
      gLocal(arrSlot)\dta\ar(index)\ptr = gEvalStack(sp)\ptr
      gLocal(arrSlot)\dta\ar(index)\ptrtype = gEvalStack(sp)\ptrtype
   EndIf
   pc + 1
EndProcedure

Procedure               C2ARRAYSTORE_FLOAT_LOCAL_LOPT_LOPT()
   ; V1.022.113: Float array store - local array, local index, local value
   ; V1.031.19: Fixed to use gLocal[] for local slots
   Protected arrSlot.i, idxSlot.i, valSlot.i, index.i
   Protected value.f
   vm_DebugFunctionName()
   arrSlot = _LARRAY(_AR()\i)
   idxSlot = _LARRAY(_AR()\ndx)
   valSlot = _LARRAY(_AR()\n)
   index = gLocal(idxSlot)\i
   value = gLocal(valSlot)\f
   CompilerIf #DEBUG
      Protected arraySize.i = gLocal(arrSlot)\dta\size
      If index < 0 Or index >= arraySize
         Debug "LSTOREARFLT_LOLO: Array index out of bounds: " + Str(index) + " (size: " + Str(arraySize) + ") at pc=" + Str(pc)
         gExitApplication = #True
         ProcedureReturn
      EndIf
   CompilerEndIf
   gLocal(arrSlot)\dta\ar(index)\f = value
   If gLocal(valSlot)\ptrtype
      gLocal(arrSlot)\dta\ar(index)\ptr = gLocal(valSlot)\ptr
      gLocal(arrSlot)\dta\ar(index)\ptrtype = gLocal(valSlot)\ptrtype
   EndIf
   pc + 1
EndProcedure

Procedure               C2ARRAYSTORE_FLOAT_LOCAL_LOPT_OPT()
   ; V1.022.113: Float array store - local array, local index, global value
   ; V1.031.19: Fixed to use gLocal[] for local slots
   Protected arrSlot.i, idxSlot.i, index.i
   Protected value.f
   vm_DebugFunctionName()
   arrSlot = _LARRAY(_AR()\i)
   idxSlot = _LARRAY(_AR()\ndx)
   index = gLocal(idxSlot)\i
   value = gVar(_AR()\n)\f
   CompilerIf #DEBUG
      Protected arraySize.i = gLocal(arrSlot)\dta\size
      If index < 0 Or index >= arraySize
         Debug "LSTOREARFLT_LOGO: Array index out of bounds: " + Str(index) + " (size: " + Str(arraySize) + ") at pc=" + Str(pc)
         gExitApplication = #True
         ProcedureReturn
      EndIf
   CompilerEndIf
   gLocal(arrSlot)\dta\ar(index)\f = value
   If gVar(_AR()\n)\ptrtype
      gLocal(arrSlot)\dta\ar(index)\ptr = gVar(_AR()\n)\ptr
      gLocal(arrSlot)\dta\ar(index)\ptrtype = gVar(_AR()\n)\ptrtype
   EndIf
   pc + 1
EndProcedure

Procedure               C2ARRAYSTORE_FLOAT_LOCAL_LOPT_STACK()
   ; V1.022.113: Float array store - local array, local index, stack value
   ; V1.031.19: Fixed to use gLocal[] instead of gVar[] for local slots
   Protected arrSlot.i, idxSlot.i, index.i
   Protected value.f
   vm_DebugFunctionName()
   arrSlot = _LARRAY(_AR()\i)
   idxSlot = _LARRAY(_AR()\ndx)
   index = gLocal(idxSlot)\i
   sp - 1
   value = gEvalStack(sp)\f
   CompilerIf #DEBUG
      Protected arraySize.i = gLocal(arrSlot)\dta\size
      If index < 0 Or index >= arraySize
         Debug "LSTOREARFLT_LOST: Array index out of bounds: " + Str(index) + " (size: " + Str(arraySize) + ") at pc=" + Str(pc)
         gExitApplication = #True
         ProcedureReturn
      EndIf
   CompilerEndIf
   gLocal(arrSlot)\dta\ar(index)\f = value
   If gEvalStack(sp)\ptrtype
      gLocal(arrSlot)\dta\ar(index)\ptr = gEvalStack(sp)\ptr
      gLocal(arrSlot)\dta\ar(index)\ptrtype = gEvalStack(sp)\ptrtype
   EndIf
   pc + 1
EndProcedure

Procedure               C2ARRAYSTORE_STR_LOCAL_LOPT_LOPT()
   ; V1.022.113: String array store - local array, local index, local value
   ; V1.031.19: Fixed to use gLocal[] instead of gVar[] for local slots
   Protected arrSlot.i, idxSlot.i, valSlot.i, index.i
   Protected value.s
   vm_DebugFunctionName()
   arrSlot = _LARRAY(_AR()\i)
   idxSlot = _LARRAY(_AR()\ndx)
   valSlot = _LARRAY(_AR()\n)
   index = gLocal(idxSlot)\i
   value = gLocal(valSlot)\ss
   CompilerIf #DEBUG
      Protected arraySize.i = gLocal(arrSlot)\dta\size
      If index < 0 Or index >= arraySize
         Debug "LSTOREARSTR_LOLO: Array index out of bounds: " + Str(index) + " (size: " + Str(arraySize) + ") at pc=" + Str(pc)
         gExitApplication = #True
         ProcedureReturn
      EndIf
   CompilerEndIf
   gLocal(arrSlot)\dta\ar(index)\ss = value
   If gLocal(valSlot)\ptrtype
      gLocal(arrSlot)\dta\ar(index)\ptr = gLocal(valSlot)\ptr
      gLocal(arrSlot)\dta\ar(index)\ptrtype = gLocal(valSlot)\ptrtype
   EndIf
   pc + 1
EndProcedure

Procedure               C2ARRAYSTORE_STR_LOCAL_LOPT_OPT()
   ; V1.022.113: String array store - local array, local index, global value
   ; V1.031.19: Fixed to use gLocal[] instead of gVar[] for local slots
   Protected arrSlot.i, idxSlot.i, index.i
   Protected value.s
   vm_DebugFunctionName()
   arrSlot = _LARRAY(_AR()\i)
   idxSlot = _LARRAY(_AR()\ndx)
   index = gLocal(idxSlot)\i
   value = gVar(_AR()\n)\ss
   CompilerIf #DEBUG
      Protected arraySize.i = gLocal(arrSlot)\dta\size
      If index < 0 Or index >= arraySize
         Debug "LSTOREARSTR_LOGO: Array index out of bounds: " + Str(index) + " (size: " + Str(arraySize) + ") at pc=" + Str(pc)
         gExitApplication = #True
         ProcedureReturn
      EndIf
   CompilerEndIf
   gLocal(arrSlot)\dta\ar(index)\ss = value
   If gVar(_AR()\n)\ptrtype
      gLocal(arrSlot)\dta\ar(index)\ptr = gVar(_AR()\n)\ptr
      gLocal(arrSlot)\dta\ar(index)\ptrtype = gVar(_AR()\n)\ptrtype
   EndIf
   pc + 1
EndProcedure

Procedure               C2ARRAYSTORE_STR_LOCAL_LOPT_STACK()
   ; V1.022.113: String array store - local array, local index, stack value
   ; V1.031.19: Fixed to use gLocal[] instead of gVar[] for local slots
   Protected arrSlot.i, idxSlot.i, index.i
   Protected value.s
   vm_DebugFunctionName()
   arrSlot = _LARRAY(_AR()\i)
   idxSlot = _LARRAY(_AR()\ndx)
   index = gLocal(idxSlot)\i
   sp - 1
   value = gEvalStack(sp)\ss
   CompilerIf #DEBUG
      Protected arraySize.i = gLocal(arrSlot)\dta\size
      If index < 0 Or index >= arraySize
         Debug "LSTOREARSTR_LOST: Array index out of bounds: " + Str(index) + " (size: " + Str(arraySize) + ") at pc=" + Str(pc)
         gExitApplication = #True
         ProcedureReturn
      EndIf
   CompilerEndIf
   gLocal(arrSlot)\dta\ar(index)\ss = value
   If gEvalStack(sp)\ptrtype
      gLocal(arrSlot)\dta\ar(index)\ptr = gEvalStack(sp)\ptr
      gLocal(arrSlot)\dta\ar(index)\ptrtype = gEvalStack(sp)\ptrtype
   EndIf
   pc + 1
EndProcedure

;- Struct Array Field Operations (V1.022.0)
;  V1.022.2: Support local and global structs
;  These access contiguous gVar[] slots: gVar[baseSlot + index]
;  Used for arrays inside structures where fields are laid out contiguously
;  _AR()\i = base slot (for global: structVarSlot + fieldOffset, for local: paramOffset + fieldOffset)
;  _AR()\j = 0 for global, 1 for local
;  _AR()\ndx = index variable slot (>= 0) or -1 (index on stack)

Procedure               C2STRUCTARRAY_FETCH_INT()
   ; V1.029.58: Updated for \ptr storage - read from struct memory, not gVar slots
   ; Fetch integer from struct array field using \ptr storage
   ; _AR()\i = struct slot (or paramOffset for local)
   ; _AR()\j = isLocal (0 = global, 1 = local)
   ; _AR()\n = field byte offset (fieldOffset * 8)
   ; _AR()\ndx = index slot (>= 0) or -1 (index on stack)
   Protected index.i
   Protected byteOffset.i
   Protected *structPtr
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
      ; Local struct - get from LocalVars array
      *structPtr = gLocal(_LARRAY(_AR()\i))\ptr
   Else
      ; Global struct - direct access
      *structPtr = gVar(_AR()\i)\ptr
   EndIf

   ; V1.022.8: Debug output to trace struct array fetch issues
   CompilerIf #DEBUG
      Debug "SARFETCH_INT: pc=" + Str(pc) + " slot=" + Str(_AR()\i) + " ndx=" + Str(_AR()\ndx) + " j=" + Str(_AR()\j) + " fieldOff=" + Str(_AR()\n) + " index=" + Str(index) + " byteOff=" + Str(byteOffset) + " ptr=" + Str(*structPtr) + " value=" + Str(PeekQ(*structPtr + byteOffset))
   CompilerEndIf

   ; Read value from struct memory
   gEvalStack(sp)\i = PeekQ(*structPtr + byteOffset)
   sp + 1
   pc + 1
EndProcedure

Procedure               C2STRUCTARRAY_FETCH_FLOAT()
   ; V1.029.58: Updated for \ptr storage - read from struct memory, not gVar slots
   ; Fetch float from struct array field using \ptr storage
   ; _AR()\i = struct slot (or paramOffset for local)
   ; _AR()\j = isLocal (0 = global, 1 = local)
   ; _AR()\n = field byte offset (fieldOffset * 8)
   ; _AR()\ndx = index slot (>= 0) or -1 (index on stack)
   Protected index.i
   Protected byteOffset.i
   Protected *structPtr
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
      ; Local struct - get from LocalVars array
      *structPtr = gLocal(_LARRAY(_AR()\i))\ptr
   Else
      ; Global struct - direct access
      *structPtr = gVar(_AR()\i)\ptr
   EndIf

   ; Read float value from struct memory
   gEvalStack(sp)\f = PeekD(*structPtr + byteOffset)
   sp + 1
   pc + 1
EndProcedure

Procedure               C2STRUCTARRAY_FETCH_STR()
   ; V1.029.58: Updated for \ptr storage - read from struct memory, not gVar slots
   ; _AR()\i = struct slot (or paramOffset for local)
   ; _AR()\j = isLocal (0=global, 1=local)
   ; _AR()\n = field byte offset (fieldOffset * 8)
   ; _AR()\ndx = index slot (>= 0) or -1 (index on stack)
   Protected index.i
   Protected byteOffset.i
   Protected *structPtr
   Protected *strPtr
   vm_DebugFunctionName()

   If _AR()\ndx >= 0
      index = gVar(_AR()\ndx)\i
   Else
      sp - 1
      index = gEvalStack(sp)\i
   EndIf

   ; V1.029.58: Calculate byte offset for \ptr storage
   byteOffset = _AR()\n + (index * 8)

   ; Get struct pointer (local or global)
   If _AR()\j
      *structPtr = gLocal(_LARRAY(_AR()\i))\ptr
   Else
      *structPtr = gVar(_AR()\i)\ptr
   EndIf

   ; V1.029.58: Read string pointer from struct memory, then read string
   *strPtr = PeekQ(*structPtr + byteOffset)
   If *strPtr
      gEvalStack(sp)\ss = PeekS(*strPtr)
   Else
      gEvalStack(sp)\ss = ""
   EndIf
   sp + 1
   pc + 1
EndProcedure

Procedure               C2STRUCTARRAY_STORE_INT()
   ; V1.029.58: Updated for \ptr storage - write to struct memory, not gVar slots
   ; _AR()\i = struct slot (or paramOffset for local)
   ; _AR()\j = isLocal (0=global, 1=local)
   ; _AR()\n = field byte offset (fieldOffset * 8)
   ; _AR()\ndx = index slot (>= 0) or -1 (index on stack)
   ; _AR()\funcid = value slot (>= 0) or -1 (value on stack)
   Protected index.i, value.i
   Protected byteOffset.i
   Protected *structPtr
   vm_DebugFunctionName()

   ; Get index
   If _AR()\ndx >= 0
      index = gVar(_AR()\ndx)\i
   Else
      sp - 1
      index = gEvalStack(sp)\i
   EndIf

   ; Get value (V1.029.58: now uses funcid instead of n)
   If _AR()\funcid >= 0
      value = gVar(_AR()\funcid)\i
   Else
      sp - 1
      value = gEvalStack(sp)\i
   EndIf

   ; V1.029.58: Calculate byte offset for \ptr storage
   byteOffset = _AR()\n + (index * 8)

   ; Get struct pointer (local or global)
   If _AR()\j
      *structPtr = gLocal(_LARRAY(_AR()\i))\ptr
   Else
      *structPtr = gVar(_AR()\i)\ptr
   EndIf

   ; V1.029.58: Write value to struct memory
   PokeQ(*structPtr + byteOffset, value)
   pc + 1
EndProcedure

Procedure               C2STRUCTARRAY_STORE_FLOAT()
   ; V1.029.58: Updated for \ptr storage - write to struct memory, not gVar slots
   ; _AR()\i = struct slot (or paramOffset for local)
   ; _AR()\j = isLocal (0=global, 1=local)
   ; _AR()\n = field byte offset (fieldOffset * 8)
   ; _AR()\ndx = index slot (>= 0) or -1 (index on stack)
   ; _AR()\funcid = value slot (>= 0) or -1 (value on stack)
   Protected index.i
   Protected value.d
   Protected byteOffset.i
   Protected *structPtr
   vm_DebugFunctionName()

   ; Get index
   If _AR()\ndx >= 0
      index = gVar(_AR()\ndx)\i
   Else
      sp - 1
      index = gEvalStack(sp)\i
   EndIf

   ; Get value (V1.029.58: now uses funcid instead of n)
   If _AR()\funcid >= 0
      value = gVar(_AR()\funcid)\f
   Else
      sp - 1
      value = gEvalStack(sp)\f
   EndIf

   ; V1.029.58: Calculate byte offset for \ptr storage
   byteOffset = _AR()\n + (index * 8)

   ; Get struct pointer (local or global)
   If _AR()\j
      *structPtr = gLocal(_LARRAY(_AR()\i))\ptr
   Else
      *structPtr = gVar(_AR()\i)\ptr
   EndIf

   ; V1.029.58: Write value to struct memory
   PokeD(*structPtr + byteOffset, value)
   pc + 1
EndProcedure

Procedure               C2STRUCTARRAY_STORE_STR()
   ; V1.029.58: Updated for \ptr storage - write to struct memory, not gVar slots
   ; _AR()\i = struct slot (or paramOffset for local)
   ; _AR()\j = isLocal (0=global, 1=local)
   ; _AR()\n = field byte offset (fieldOffset * 8)
   ; _AR()\ndx = index slot (>= 0) or -1 (index on stack)
   ; _AR()\funcid = value slot (>= 0) or -1 (value on stack)
   Protected index.i
   Protected value.s
   Protected byteOffset.i
   Protected *structPtr
   Protected *oldStr, *newStr, strLen.i
   vm_DebugFunctionName()

   ; Get index
   If _AR()\ndx >= 0
      index = gVar(_AR()\ndx)\i
   Else
      sp - 1
      index = gEvalStack(sp)\i
   EndIf

   ; Get value (V1.029.58: now uses funcid instead of n)
   If _AR()\funcid >= 0
      value = gVar(_AR()\funcid)\ss
   Else
      sp - 1
      value = gEvalStack(sp)\ss
   EndIf

   ; V1.029.58: Calculate byte offset for \ptr storage
   byteOffset = _AR()\n + (index * 8)

   ; Get struct pointer (local or global)
   If _AR()\j
      *structPtr = gLocal(_LARRAY(_AR()\i))\ptr
   Else
      *structPtr = gVar(_AR()\i)\ptr
   EndIf

   ; V1.029.58: Free old string if exists
   *oldStr = PeekQ(*structPtr + byteOffset)
   If *oldStr : FreeMemory(*oldStr) : EndIf

   ; Allocate and copy new string
   strLen = StringByteLength(value) + SizeOf(Character)
   *newStr = AllocateMemory(strLen)
   PokeS(*newStr, value)
   PokeQ(*structPtr + byteOffset, *newStr)
   pc + 1
EndProcedure

;- V1.022.44: Array of Structs Operations
; These compute: targetSlot = arrayBase + (index * elementSize) + fieldOffset
; _AR()\i = array base slot
; _AR()\j = element size (struct size)
; _AR()\n = field offset
; _AR()\ndx = index slot
; _AR()\funcid = 1 for local, 0 for global

Procedure               C2ARRAYOFSTRUCT_FETCH_INT()
   ; Fetch integer from array of structs: arr[i]\field
   ; V1.022.50: ndx always contains valid slot (codegen ensures this)
   Protected index.i, targetSlot.i, baseSlot.i
   Protected elementSize.i, fieldOffset.i
   vm_DebugFunctionName()

   ; Get index from slot
   index = gVar(_AR()\ndx)\i
   elementSize = _AR()\j
   fieldOffset = _AR()\n

   ; Calculate base slot (local or global)
   If _AR()\funcid
      ; Local array - use _LARRAY
      baseSlot = _LARRAY(_AR()\i)
   Else
      ; Global array - direct slot
      baseSlot = _AR()\i
   EndIf

   ; Calculate target: baseSlot + (index * elementSize) + fieldOffset
   targetSlot = baseSlot + (index * elementSize) + fieldOffset

   CompilerIf #DEBUG
      Debug "AOSFETCH_INT: base=" + Str(baseSlot) + " idx=" + Str(index) + " elemSz=" + Str(elementSize) + " fldOff=" + Str(fieldOffset) + " target=" + Str(targetSlot) + " val=" + Str(gVar(targetSlot)\i)
   CompilerEndIf

   gEvalStack(sp)\i = gVar(targetSlot)\i
   sp + 1
   pc + 1
EndProcedure

Procedure               C2ARRAYOFSTRUCT_FETCH_FLOAT()
   ; Fetch float from array of structs: arr[i]\field
   ; V1.022.50: ndx always contains valid slot (codegen ensures this)
   Protected index.i, targetSlot.i, baseSlot.i
   Protected elementSize.i, fieldOffset.i
   vm_DebugFunctionName()

   ; Get index from slot
   index = gVar(_AR()\ndx)\i
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

Procedure               C2ARRAYOFSTRUCT_FETCH_STR()
   ; Fetch string from array of structs: arr[i]\field
   ; V1.022.50: ndx always contains valid slot (codegen ensures this)
   Protected index.i, targetSlot.i, baseSlot.i
   Protected elementSize.i, fieldOffset.i
   vm_DebugFunctionName()

   ; Get index from slot
   index = gVar(_AR()\ndx)\i
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

Procedure               C2ARRAYOFSTRUCT_STORE_INT()
   ; Store integer to array of structs: arr[i]\field = value
   ; V1.022.45: Value popped from stack, index from slot
   ; V1.022.50: ndx always contains valid slot (codegen ensures this)
   ; _AR()\i = array base slot, _AR()\j = element size, _AR()\n = field offset
   ; _AR()\ndx = index slot, _AR()\funcid = local flag
   Protected index.i, targetSlot.i, baseSlot.i, value.i
   Protected elementSize.i, fieldOffset.i
   vm_DebugFunctionName()

   ; Pop value from stack
   sp - 1
   value = gEvalStack(sp)\i

   ; Get index from slot
   index = gVar(_AR()\ndx)\i
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

Procedure               C2ARRAYOFSTRUCT_STORE_FLOAT()
   ; Store float to array of structs: arr[i]\field = value
   ; V1.022.45: Value popped from stack, index from slot
   ; V1.022.50: ndx always contains valid slot (codegen ensures this)
   Protected index.i, targetSlot.i, baseSlot.i
   Protected elementSize.i, fieldOffset.i
   Protected value.d
   vm_DebugFunctionName()

   ; Pop value from stack
   sp - 1
   value = gEvalStack(sp)\f

   ; Get index from slot
   index = gVar(_AR()\ndx)\i
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

Procedure               C2ARRAYOFSTRUCT_STORE_STR()
   ; Store string to array of structs: arr[i]\field = value
   ; V1.022.45: Value popped from stack, index from slot
   ; V1.022.50: ndx always contains valid slot (codegen ensures this)
   Protected index.i, targetSlot.i, baseSlot.i
   Protected elementSize.i, fieldOffset.i
   Protected value.s
   vm_DebugFunctionName()

   ; Pop value from stack
   sp - 1
   value = gEvalStack(sp)\ss

   ; Get index from slot
   index = gVar(_AR()\ndx)\i
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

;- V1.022.118: ARRAYOFSTRUCT_*_LOPT (index from local slot)
; These variants read the index from a LOCAL slot using _LARRAY()

Procedure               C2ARRAYOFSTRUCT_FETCH_INT_LOPT()
   ; Fetch integer from array of structs with LOCAL index
   ; ndx = LOCAL offset, use _LARRAY() to get actual slot
   Protected index.i, targetSlot.i, baseSlot.i
   Protected elementSize.i, fieldOffset.i
   vm_DebugFunctionName()

   ; Get index from LOCAL slot
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

Procedure               C2ARRAYOFSTRUCT_FETCH_FLOAT_LOPT()
   ; Fetch float from array of structs with LOCAL index
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

Procedure               C2ARRAYOFSTRUCT_FETCH_STR_LOPT()
   ; Fetch string from array of structs with LOCAL index
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

Procedure               C2ARRAYOFSTRUCT_STORE_INT_LOPT()
   ; Store integer to array of structs with LOCAL index
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

Procedure               C2ARRAYOFSTRUCT_STORE_FLOAT_LOPT()
   ; Store float to array of structs with LOCAL index
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

Procedure               C2ARRAYOFSTRUCT_STORE_STR_LOPT()
   ; Store string to array of structs with LOCAL index
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

;- V1.022.64: Array Resize Operation
;  Resize existing array using PureBasic ReDim - preserves existing elements
;  _AR()\i = array slot
;  _AR()\j = new size
;  _AR()\n = isLocal flag (0 = global, 1 = local)

Procedure               C2ARRAYRESIZE()
   ; Resize array using ReDim - preserves existing elements up to new size
   ; For global arrays: ReDim gVar(arrSlot)\dta\ar(newSize - 1)
   ; For local arrays: ReDim gLocal(_LARRAY(paramOffset))\dta\ar(newSize - 1)
   Protected arrSlot.i, newSize.i, isLocal.i, actualSlot.i
   vm_DebugFunctionName()

   arrSlot = _AR()\i
   newSize = _AR()\j
   isLocal = _AR()\n

   ; Calculate actual slot for local arrays
   If isLocal
      actualSlot = _LARRAY(arrSlot)
   Else
      actualSlot = arrSlot
   EndIf

   CompilerIf #DEBUG
      Debug "ARRAYRESIZE: slot=" + Str(arrSlot) + " actualSlot=" + Str(actualSlot) + " oldSize=" + Str(gVar(actualSlot)\dta\size) + " newSize=" + Str(newSize) + " isLocal=" + Str(isLocal)
   CompilerEndIf

   ; PureBasic ReDim preserves existing data up to the smaller of old/new size
   ReDim gVar(actualSlot)\dta\ar(newSize - 1)
   gVar(actualSlot)\dta\size = newSize

   pc + 1
EndProcedure

;- V1.022.86: Local-Index Array Operations
;  For recursion-safe temp variables: index read from LOCAL slot instead of global
;  _AR()\i = array slot (global), _AR()\ndx = local offset for index

Procedure               C2ARRAYFETCH_INT_GLOBAL_LOPT()
   ; Integer array fetch - global array, LOCAL optimized index
   Protected arrIdx.i, index.i
   Protected idxOffset.i, idxSlot.i
   vm_DebugFunctionName()
   arrIdx = _AR()\i
   idxOffset = _AR()\ndx
   idxSlot = _LARRAY(idxOffset)
   ; V1.031.13: Fix - read from gLocal[] not gVar[] for Isolated Variable System
   index = gLocal(idxSlot)\i   ; Read index from LOCAL slot
   CompilerIf #DEBUG
      Protected arraySize.i = gVar(arrIdx)\dta\size
      ; V1.022.95: Bounds check BEFORE debug output to avoid crash on OOB access
      If index < 0 Or index >= arraySize
         Debug "LOPT_FETCH_I: Array index out of bounds: " + Str(index) + " (size: " + Str(arraySize) + ") at pc=" + Str(pc) + " depth=" + Str(gStackDepth)
         gExitApplication = #True
         ProcedureReturn
      EndIf
      ; V1.022.92: Detailed LOPT debug trace for recursion debugging
      Debug "  LOPT_FETCH_I: depth=" + Str(gStackDepth) + " localStart=" + Str(gStack(gStackDepth)\localBase) + " idxOff=" + Str(idxOffset) + " idxSlot=" + Str(idxSlot) + " index=" + Str(index) + " value=" + Str(gVar(arrIdx)\dta\ar(index)\i) + " pc=" + Str(pc)
   CompilerEndIf
   gEvalStack(sp)\i = gVar(arrIdx)\dta\ar(index)\i
   If gVar(arrIdx)\dta\ar(index)\ptrtype
      gEvalStack(sp)\ptr = gVar(arrIdx)\dta\ar(index)\ptr
      gEvalStack(sp)\ptrtype = gVar(arrIdx)\dta\ar(index)\ptrtype
   Else
      gEvalStack(sp)\ptrtype = 0
   EndIf
   sp + 1
   pc + 1
EndProcedure

Procedure               C2ARRAYFETCH_FLOAT_GLOBAL_LOPT()
   ; Float array fetch - global array, LOCAL optimized index
   Protected arrIdx.i, index.i
   Protected idxOffset.i, idxSlot.i
   vm_DebugFunctionName()
   arrIdx = _AR()\i
   idxOffset = _AR()\ndx
   idxSlot = _LARRAY(idxOffset)
   ; V1.031.13: Fix - read from gLocal[] not gVar[] for Isolated Variable System
   index = gLocal(idxSlot)\i   ; Read index from LOCAL slot
   CompilerIf #DEBUG
      Protected arraySize.i = gVar(arrIdx)\dta\size
      ; V1.022.95: Bounds check BEFORE debug output to avoid crash on OOB access
      If index < 0 Or index >= arraySize
         Debug "LOPT_FETCH_F: Array index out of bounds: " + Str(index) + " (size: " + Str(arraySize) + ") at pc=" + Str(pc) + " depth=" + Str(gStackDepth)
         gExitApplication = #True
         ProcedureReturn
      EndIf
      ; V1.022.92: Detailed LOPT debug trace for recursion debugging
      Debug "  LOPT_FETCH_F: depth=" + Str(gStackDepth) + " localStart=" + Str(gStack(gStackDepth)\localBase) + " idxOff=" + Str(idxOffset) + " idxSlot=" + Str(idxSlot) + " index=" + Str(index) + " value=" + StrF(gVar(arrIdx)\dta\ar(index)\f, 2) + " pc=" + Str(pc)
   CompilerEndIf
   gEvalStack(sp)\f = gVar(arrIdx)\dta\ar(index)\f
   If gVar(arrIdx)\dta\ar(index)\ptrtype
      gEvalStack(sp)\ptr = gVar(arrIdx)\dta\ar(index)\ptr
      gEvalStack(sp)\ptrtype = gVar(arrIdx)\dta\ar(index)\ptrtype
   Else
      gEvalStack(sp)\ptrtype = 0
   EndIf
   sp + 1
   pc + 1
EndProcedure

Procedure               C2ARRAYFETCH_STR_GLOBAL_LOPT()
   ; String array fetch - global array, LOCAL optimized index
   Protected arrIdx.i, index.i
   vm_DebugFunctionName()
   arrIdx = _AR()\i
   index = gLocal(_LARRAY(_AR()\ndx))\i   ; Read index from LOCAL slot
   CompilerIf #DEBUG
      Protected arraySize.i = gVar(arrIdx)\dta\size
      If index < 0 Or index >= arraySize
         Debug "Array index out of bounds: " + Str(index) + " (size: " + Str(arraySize) + ") at pc=" + Str(pc)
         gExitApplication = #True
         ProcedureReturn
      EndIf
   CompilerEndIf
   gEvalStack(sp)\ss = gVar(arrIdx)\dta\ar(index)\ss
   sp + 1
   pc + 1
EndProcedure

Procedure               C2ARRAYSTORE_INT_GLOBAL_LOPT_LOPT()
   ; Integer array store - global array, LOCAL opt index, LOCAL opt value
   Protected arrIdx.i, index.i, value.i
   Protected idxOffset.i, valOffset.i, idxSlot.i, valSlot.i
   vm_DebugFunctionName()
   arrIdx = _AR()\i
   idxOffset = _AR()\ndx
   valOffset = _AR()\n
   idxSlot = _LARRAY(idxOffset)
   valSlot = _LARRAY(valOffset)
   ; V1.031.13: Fix - read from gLocal[] not gVar[] for Isolated Variable System
   index = gLocal(idxSlot)\i   ; Read index from LOCAL slot
   value = gLocal(valSlot)\i   ; Read value from LOCAL slot
   CompilerIf #DEBUG
      Protected arraySize.i = gVar(arrIdx)\dta\size
      ; V1.022.92: Detailed LOPT debug trace for recursion debugging
      Debug "  LOPT_STORE_I: depth=" + Str(gStackDepth) + " localStart=" + Str(gStack(gStackDepth)\localBase) + " idxOff=" + Str(idxOffset) + " valOff=" + Str(valOffset) + " idxSlot=" + Str(idxSlot) + " valSlot=" + Str(valSlot) + " index=" + Str(index) + " value=" + Str(value) + " pc=" + Str(pc)
      If index < 0 Or index >= arraySize
         Debug "Array index out of bounds: " + Str(index) + " (size: " + Str(arraySize) + ") at pc=" + Str(pc)
         gExitApplication = #True
         ProcedureReturn
      EndIf
   CompilerEndIf
   gVar(arrIdx)\dta\ar(index)\i = value
   If gLocal(valSlot)\ptrtype
      gVar(arrIdx)\dta\ar(index)\ptr = gLocal(valSlot)\ptr
      gVar(arrIdx)\dta\ar(index)\ptrtype = gLocal(valSlot)\ptrtype
   EndIf
   pc + 1
EndProcedure

Procedure               C2ARRAYSTORE_INT_GLOBAL_LOPT_OPT()
   ; Integer array store - global array, LOCAL opt index, GLOBAL opt value
   Protected arrIdx.i, index.i, value.i
   vm_DebugFunctionName()
   arrIdx = _AR()\i
   index = gLocal(_LARRAY(_AR()\ndx))\i   ; Read index from LOCAL slot
   value = gVar(_AR()\n)\i              ; Read value from GLOBAL slot
   CompilerIf #DEBUG
      Protected arraySize.i = gVar(arrIdx)\dta\size
      If index < 0 Or index >= arraySize
         Debug "Array index out of bounds: " + Str(index) + " (size: " + Str(arraySize) + ") at pc=" + Str(pc)
         gExitApplication = #True
         ProcedureReturn
      EndIf
   CompilerEndIf
   gVar(arrIdx)\dta\ar(index)\i = value
   If gVar(_AR()\n)\ptrtype
      gVar(arrIdx)\dta\ar(index)\ptr = gVar(_AR()\n)\ptr
      gVar(arrIdx)\dta\ar(index)\ptrtype = gVar(_AR()\n)\ptrtype
   EndIf
   pc + 1
EndProcedure

Procedure               C2ARRAYSTORE_INT_GLOBAL_LOPT_STACK()
   ; Integer array store - global array, LOCAL opt index, stack value
   Protected arrIdx.i, index.i, value.i
   vm_DebugFunctionName()
   arrIdx = _AR()\i
   index = gLocal(_LARRAY(_AR()\ndx))\i   ; Read index from LOCAL slot
   sp - 1
   value = gEvalStack(sp)\i
   CompilerIf #DEBUG
      Protected arraySize.i = gVar(arrIdx)\dta\size
      If index < 0 Or index >= arraySize
         Debug "Array index out of bounds: " + Str(index) + " (size: " + Str(arraySize) + ") at pc=" + Str(pc)
         gExitApplication = #True
         ProcedureReturn
      EndIf
   CompilerEndIf
   gVar(arrIdx)\dta\ar(index)\i = value
   If gEvalStack(sp)\ptrtype
      gVar(arrIdx)\dta\ar(index)\ptr = gEvalStack(sp)\ptr
      gVar(arrIdx)\dta\ar(index)\ptrtype = gEvalStack(sp)\ptrtype
   EndIf
   pc + 1
EndProcedure

Procedure               C2ARRAYSTORE_FLOAT_GLOBAL_LOPT_LOPT()
   ; Float array store - global array, LOCAL opt index, LOCAL opt value
   Protected arrIdx.i, index.i
   Protected value.f
   Protected idxOffset.i, valOffset.i, idxSlot.i, valSlot.i
   vm_DebugFunctionName()
   arrIdx = _AR()\i
   idxOffset = _AR()\ndx
   valOffset = _AR()\n
   idxSlot = _LARRAY(idxOffset)
   valSlot = _LARRAY(valOffset)
   ; V1.031.13: Fix - read from gLocal[] not gVar[] for Isolated Variable System
   index = gLocal(idxSlot)\i   ; Read index from LOCAL slot
   value = gLocal(valSlot)\f   ; Read value from LOCAL slot
   CompilerIf #DEBUG
      Protected arraySize.i = gVar(arrIdx)\dta\size
      ; V1.022.92: Detailed LOPT debug trace for recursion debugging
      Debug "  LOPT_STORE_F: depth=" + Str(gStackDepth) + " localStart=" + Str(gStack(gStackDepth)\localBase) + " idxOff=" + Str(idxOffset) + " valOff=" + Str(valOffset) + " idxSlot=" + Str(idxSlot) + " valSlot=" + Str(valSlot) + " index=" + Str(index) + " value=" + StrF(value, 2) + " pc=" + Str(pc)
      If index < 0 Or index >= arraySize
         Debug "Array index out of bounds: " + Str(index) + " (size: " + Str(arraySize) + ") at pc=" + Str(pc)
         gExitApplication = #True
         ProcedureReturn
      EndIf
   CompilerEndIf
   gVar(arrIdx)\dta\ar(index)\f = value
   pc + 1
EndProcedure

Procedure               C2ARRAYSTORE_FLOAT_GLOBAL_LOPT_OPT()
   ; Float array store - global array, LOCAL opt index, GLOBAL opt value
   Protected arrIdx.i, index.i
   Protected value.f
   Protected idxOffset.i, idxSlot.i
   vm_DebugFunctionName()
   arrIdx = _AR()\i
   idxOffset = _AR()\ndx
   idxSlot = _LARRAY(idxOffset)
   ; V1.031.13: Fix - read index from gLocal[] not gVar[] for Isolated Variable System
   index = gLocal(idxSlot)\i   ; Read index from LOCAL slot
   value = gVar(_AR()\n)\f   ; Read value from GLOBAL slot
   CompilerIf #DEBUG
      Protected arraySize.i = gVar(arrIdx)\dta\size
      ; V1.022.92: Detailed LOPT debug trace for recursion debugging
      Debug "  LOPT_STORE_F_G: depth=" + Str(gStackDepth) + " localStart=" + Str(gStack(gStackDepth)\localBase) + " idxOff=" + Str(idxOffset) + " idxSlot=" + Str(idxSlot) + " index=" + Str(index) + " valSlot=" + Str(_AR()\n) + " value=" + StrF(value, 2) + " pc=" + Str(pc)
      If index < 0 Or index >= arraySize
         Debug "Array index out of bounds: " + Str(index) + " (size: " + Str(arraySize) + ") at pc=" + Str(pc)
         gExitApplication = #True
         ProcedureReturn
      EndIf
   CompilerEndIf
   gVar(arrIdx)\dta\ar(index)\f = value
   pc + 1
EndProcedure

Procedure               C2ARRAYSTORE_FLOAT_GLOBAL_LOPT_STACK()
   ; Float array store - global array, LOCAL opt index, stack value
   Protected arrIdx.i, index.i
   Protected value.f
   Protected idxOffset.i, idxSlot.i
   vm_DebugFunctionName()
   arrIdx = _AR()\i
   idxOffset = _AR()\ndx
   idxSlot = _LARRAY(idxOffset)
   ; V1.031.13: Fix - read index from gLocal[] not gVar[] for Isolated Variable System
   index = gLocal(idxSlot)\i   ; Read index from LOCAL slot
   sp - 1
   value = gEvalStack(sp)\f
   CompilerIf #DEBUG
      Protected arraySize.i = gVar(arrIdx)\dta\size
      ; V1.022.92: Detailed LOPT debug trace for recursion debugging
      Debug "  LOPT_STORE_F_STK: depth=" + Str(gStackDepth) + " localStart=" + Str(gStack(gStackDepth)\localBase) + " idxOff=" + Str(idxOffset) + " idxSlot=" + Str(idxSlot) + " index=" + Str(index) + " value=" + StrF(value, 2) + " pc=" + Str(pc)
      If index < 0 Or index >= arraySize
         Debug "Array index out of bounds: " + Str(index) + " (size: " + Str(arraySize) + ") at pc=" + Str(pc)
         gExitApplication = #True
         ProcedureReturn
      EndIf
   CompilerEndIf
   gVar(arrIdx)\dta\ar(index)\f = value
   pc + 1
EndProcedure

Procedure               C2ARRAYSTORE_STR_GLOBAL_LOPT_LOPT()
   ; String array store - global array, LOCAL opt index, LOCAL opt value
   Protected arrIdx.i, index.i
   Protected value.s
   vm_DebugFunctionName()
   arrIdx = _AR()\i
   index = gLocal(_LARRAY(_AR()\ndx))\i   ; Read index from LOCAL slot
   value = gLocal(_LARRAY(_AR()\n))\ss    ; Read value from LOCAL slot
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

Procedure               C2ARRAYSTORE_STR_GLOBAL_LOPT_OPT()
   ; String array store - global array, LOCAL opt index, GLOBAL opt value
   Protected arrIdx.i, index.i
   Protected value.s
   vm_DebugFunctionName()
   arrIdx = _AR()\i
   index = gLocal(_LARRAY(_AR()\ndx))\i   ; Read index from LOCAL slot
   value = gVar(_AR()\n)\ss             ; Read value from GLOBAL slot
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

Procedure               C2ARRAYSTORE_STR_GLOBAL_LOPT_STACK()
   ; String array store - global array, LOCAL opt index, stack value
   Protected arrIdx.i, index.i
   Protected value.s
   vm_DebugFunctionName()
   arrIdx = _AR()\i
   index = gLocal(_LARRAY(_AR()\ndx))\i   ; Read index from LOCAL slot
   sp - 1
   value = gEvalStack(sp)\ss
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

;- End Array Operations

; IDE Options = PureBasic 6.21 (Windows - x64)
; CursorPosition = 538
; FirstLine = 529
; Folding = ----------------------------
; EnableAsm
; EnableThread
; EnableXP
; CPU = 1
; EnablePurifier
; EnableCompileCount = 0
; EnableBuildCount = 0
; EnableExeConstant