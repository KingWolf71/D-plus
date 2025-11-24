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
   ; V1.18.0: Generic array fetch (copies entire stVT)
   ; _AR()\i = array index (global varSlot OR local paramOffset)
   ; _AR()\j = 0 for global, 1 for local
   ; _AR()\n = (available for future use - size now in structure)
   ; _AR()\ndx = index variable slot (if ndx >= 0, optimized path)

   Protected index.i
   CompilerIf #DEBUG
      Protected arraySize.i
   CompilerEndIf

   vm_DebugFunctionName()

   ; Get index from ndx field (optimized) or stack
   If _AR()\ndx >= 0
      index = gVar(_AR()\ndx)\i
   Else
      sp - 1
      index = gVar(sp)\i
   EndIf

   ; Bounds checking and copy based on array type
   If _AR()\j
      ; Local array - use unified gVar[] with _LARRAY macro
      CompilerIf #DEBUG
         arraySize = gVar(_LARRAY(_AR()\i))\dta\size
         If index < 0 Or index >= arraySize
            Debug "Array index out of bounds: " + Str(index) + " (size: " + Str(arraySize) + ") at pc=" + Str(pc)
            gExitApplication = #True
            ProcedureReturn
         EndIf
      CompilerEndIf
      CopyStructure( gVar(sp), gVar(_LARRAY(_AR()\i))\dta\ar(index), stVTSimple )
   Else
      ; Global array
      CompilerIf #DEBUG
         arraySize = gVar(_AR()\i)\dta\size
         If index < 0 Or index >= arraySize
            Debug "Array index out of bounds: " + Str(index) + " (size: " + Str(arraySize) + ") at pc=" + Str(pc)
            gExitApplication = #True
            ProcedureReturn
         EndIf
      CompilerEndIf
      CopyStructure( gVar(sp), gVar(_AR()\i)\dta\ar(index), stVTSimple )
   EndIf

   sp + 1
   pc + 1
EndProcedure

Procedure               C2ARRAYSTORE()
   ; V1.18.0: Generic array store (copies entire stVT)
   ; _AR()\i = array index (global varSlot OR local paramOffset)
   ; _AR()\j = 0 for global, 1 for local
   ; _AR()\n = (available for future use - size now in structure)
   ; _AR()\ndx = index variable slot (if ndx >= 0, optimized path)

   Protected index.i
   CompilerIf #DEBUG
      Protected arraySize.i
   CompilerEndIf

   vm_DebugFunctionName()

   ; Get index from ndx field (optimized) or stack
   If _AR()\ndx >= 0
      index = gVar(_AR()\ndx)\i
      sp - 1
   Else
      sp - 1
      index = gVar(sp)\i
      sp - 1
   EndIf

   ; Bounds checking and copy based on array type
   If _AR()\j
      ; Local array - use unified gVar[] with _LARRAY macro
      CompilerIf #DEBUG
         arraySize = gVar(_LARRAY(_AR()\i))\dta\size
         If index < 0 Or index >= arraySize
            Debug "Array index out of bounds: " + Str(index) + " (size: " + Str(arraySize) + ") at pc=" + Str(pc)
            gExitApplication = #True
            ProcedureReturn
         EndIf
      CompilerEndIf
      CopyStructure( gVar(_LARRAY(_AR()\i))\dta\ar(index), gVar(sp), stVTSimple )
   Else
      ; Global array
      CompilerIf #DEBUG
         arraySize = gVar(_AR()\i)\dta\size
         If index < 0 Or index >= arraySize
            Debug "Array index out of bounds: " + Str(index) + " (size: " + Str(arraySize) + ") at pc=" + Str(pc)
            gExitApplication = #True
            ProcedureReturn
         EndIf
      CompilerEndIf
      CopyStructure( gVar(_AR()\i)\dta\ar(index), gVar(sp), stVTSimple )
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
   gVar(sp)\i = gVar(arrIdx)\dta\ar(index)\i
   ; Copy pointer metadata if present (for arrays of pointers)
   If gVar(arrIdx)\dta\ar(index)\ptrtype
      gVar(sp)\ptr = gVar(arrIdx)\dta\ar(index)\ptr
      gVar(sp)\ptrtype = gVar(arrIdx)\dta\ar(index)\ptrtype
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
   index = gVar(sp)\i
   CompilerIf #DEBUG
      Protected arraySize.i = gVar(arrIdx)\dta\size
      If index < 0 Or index >= arraySize
         Debug "Array index out of bounds: " + Str(index) + " (size: " + Str(arraySize) + ") at pc=" + Str(pc)
         gExitApplication = #True
         ProcedureReturn
      EndIf
   CompilerEndIf
   gVar(sp)\i = gVar(arrIdx)\dta\ar(index)\i
   ; Copy pointer metadata if present (for arrays of pointers)
   If gVar(arrIdx)\dta\ar(index)\ptrtype
      gVar(sp)\ptr = gVar(arrIdx)\dta\ar(index)\ptr
      gVar(sp)\ptrtype = gVar(arrIdx)\dta\ar(index)\ptrtype
   EndIf
   sp + 1
   pc + 1
EndProcedure

Procedure               C2ARRAYFETCH_INT_LOCAL_OPT()
   ; V1.18.0: Integer array fetch - local array in unified gVar[], optimized index
   Protected index.i
   vm_DebugFunctionName()
   index = gVar(_AR()\ndx)\i
   CompilerIf #DEBUG
      Protected arraySize.i
      arraySize = gVar(_LARRAY(_AR()\i))\dta\size
      If index < 0 Or index >= arraySize
         Debug "Array index out of bounds: " + Str(index) + " (size: " + Str(arraySize) + ") at pc=" + Str(pc)
         gExitApplication = #True
         ProcedureReturn
      EndIf
   CompilerEndIf
   gVar(sp)\i = gVar(_LARRAY(_AR()\i))\dta\ar(index)\i
   ; Copy pointer metadata if present
   If gVar(_LARRAY(_AR()\i))\dta\ar(index)\ptrtype
      gVar(sp)\ptr = gVar(_LARRAY(_AR()\i))\dta\ar(index)\ptr
      gVar(sp)\ptrtype = gVar(_LARRAY(_AR()\i))\dta\ar(index)\ptrtype
   EndIf
   sp + 1
   pc + 1
EndProcedure

Procedure               C2ARRAYFETCH_INT_LOCAL_STACK()
   ; V1.18.0: Integer array fetch - local array in unified gVar[], stack index
   Protected index.i
   vm_DebugFunctionName()
   sp - 1
   index = gVar(sp)\i
   CompilerIf #DEBUG
      Protected arraySize.i
      arraySize = gVar(_LARRAY(_AR()\i))\dta\size
      If index < 0 Or index >= arraySize
         Debug "Array index out of bounds: " + Str(index) + " (size: " + Str(arraySize) + ") at pc=" + Str(pc)
         gExitApplication = #True
         ProcedureReturn
      EndIf
   CompilerEndIf
   gVar(sp)\i = gVar(_LARRAY(_AR()\i))\dta\ar(index)\i
   ; Copy pointer metadata if present
   If gVar(_LARRAY(_AR()\i))\dta\ar(index)\ptrtype
      gVar(sp)\ptr = gVar(_LARRAY(_AR()\i))\dta\ar(index)\ptr
      gVar(sp)\ptrtype = gVar(_LARRAY(_AR()\i))\dta\ar(index)\ptrtype
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
   gVar(sp)\f = gVar(arrIdx)\dta\ar(index)\f
   ; Copy pointer metadata if present (for arrays of pointers)
   If gVar(arrIdx)\dta\ar(index)\ptrtype
      gVar(sp)\ptr = gVar(arrIdx)\dta\ar(index)\ptr
      gVar(sp)\ptrtype = gVar(arrIdx)\dta\ar(index)\ptrtype
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
   index = gVar(sp)\i
   CompilerIf #DEBUG
      Protected arraySize.i = gVar(arrIdx)\dta\size
      If index < 0 Or index >= arraySize
         Debug "Array index out of bounds: " + Str(index) + " (size: " + Str(arraySize) + ") at pc=" + Str(pc)
         gExitApplication = #True
         ProcedureReturn
      EndIf
   CompilerEndIf
   gVar(sp)\f = gVar(arrIdx)\dta\ar(index)\f
   ; Copy pointer metadata if present (for arrays of pointers)
   If gVar(arrIdx)\dta\ar(index)\ptrtype
      gVar(sp)\ptr = gVar(arrIdx)\dta\ar(index)\ptr
      gVar(sp)\ptrtype = gVar(arrIdx)\dta\ar(index)\ptrtype
   EndIf
   sp + 1
   pc + 1
EndProcedure

Procedure               C2ARRAYFETCH_FLOAT_LOCAL_OPT()
   ; V1.18.0: Float array fetch - local array in unified gVar[], optimized index
   Protected index.i
   vm_DebugFunctionName()
   index = gVar(_AR()\ndx)\i
   CompilerIf #DEBUG
      Protected arraySize.i
      arraySize = gVar(_LARRAY(_AR()\i))\dta\size
      If index < 0 Or index >= arraySize
         Debug "Array index out of bounds: " + Str(index) + " (size: " + Str(arraySize) + ") at pc=" + Str(pc)
         gExitApplication = #True
         ProcedureReturn
      EndIf
   CompilerEndIf
   gVar(sp)\f = gVar(_LARRAY(_AR()\i))\dta\ar(index)\f
   ; Copy pointer metadata if present
   If gVar(_LARRAY(_AR()\i))\dta\ar(index)\ptrtype
      gVar(sp)\ptr = gVar(_LARRAY(_AR()\i))\dta\ar(index)\ptr
      gVar(sp)\ptrtype = gVar(_LARRAY(_AR()\i))\dta\ar(index)\ptrtype
   EndIf
   sp + 1
   pc + 1
EndProcedure

Procedure               C2ARRAYFETCH_FLOAT_LOCAL_STACK()
   ; V1.18.0: Float array fetch - local array in unified gVar[], stack index
   Protected index.i
   vm_DebugFunctionName()
   sp - 1
   index = gVar(sp)\i
   CompilerIf #DEBUG
      Protected arraySize.i
      arraySize = gVar(_LARRAY(_AR()\i))\dta\size
      If index < 0 Or index >= arraySize
         Debug "Array index out of bounds: " + Str(index) + " (size: " + Str(arraySize) + ") at pc=" + Str(pc)
         gExitApplication = #True
         ProcedureReturn
      EndIf
   CompilerEndIf
   gVar(sp)\f = gVar(_LARRAY(_AR()\i))\dta\ar(index)\f
   ; Copy pointer metadata if present
   If gVar(_LARRAY(_AR()\i))\dta\ar(index)\ptrtype
      gVar(sp)\ptr = gVar(_LARRAY(_AR()\i))\dta\ar(index)\ptr
      gVar(sp)\ptrtype = gVar(_LARRAY(_AR()\i))\dta\ar(index)\ptrtype
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
   gVar(sp)\ss = gVar(arrIdx)\dta\ar(index)\ss
   ; Copy pointer metadata if present (for arrays of pointers)
   If gVar(arrIdx)\dta\ar(index)\ptrtype
      gVar(sp)\ptr = gVar(arrIdx)\dta\ar(index)\ptr
      gVar(sp)\ptrtype = gVar(arrIdx)\dta\ar(index)\ptrtype
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
   index = gVar(sp)\i
   CompilerIf #DEBUG
      Protected arraySize.i = gVar(arrIdx)\dta\size
      If index < 0 Or index >= arraySize
         Debug "Array index out of bounds: " + Str(index) + " (size: " + Str(arraySize) + ") at pc=" + Str(pc)
         gExitApplication = #True
         ProcedureReturn
      EndIf
   CompilerEndIf
   gVar(sp)\ss = gVar(arrIdx)\dta\ar(index)\ss
   ; Copy pointer metadata if present (for arrays of pointers)
   If gVar(arrIdx)\dta\ar(index)\ptrtype
      gVar(sp)\ptr = gVar(arrIdx)\dta\ar(index)\ptr
      gVar(sp)\ptrtype = gVar(arrIdx)\dta\ar(index)\ptrtype
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
      arraySize = gVar(_LARRAY(_AR()\i))\dta\size
      If index < 0 Or index >= arraySize
         Debug "Array index out of bounds: " + Str(index) + " (size: " + Str(arraySize) + ") at pc=" + Str(pc)
         gExitApplication = #True
         ProcedureReturn
      EndIf
   CompilerEndIf
   gVar(sp)\ss = gVar(_LARRAY(_AR()\i))\dta\ar(index)\ss
   ; Copy pointer metadata if present
   If gVar(_LARRAY(_AR()\i))\dta\ar(index)\ptrtype
      gVar(sp)\ptr = gVar(_LARRAY(_AR()\i))\dta\ar(index)\ptr
      gVar(sp)\ptrtype = gVar(_LARRAY(_AR()\i))\dta\ar(index)\ptrtype
   EndIf
   sp + 1
   pc + 1
EndProcedure

Procedure               C2ARRAYFETCH_STR_LOCAL_STACK()
   ; V1.18.0: String array fetch - local array in unified gVar[], stack index
   Protected index.i
   vm_DebugFunctionName()
   sp - 1
   index = gVar(sp)\i
   CompilerIf #DEBUG
      Protected arraySize.i
      arraySize = gVar(_LARRAY(_AR()\i))\dta\size
      If index < 0 Or index >= arraySize
         Debug "Array index out of bounds: " + Str(index) + " (size: " + Str(arraySize) + ") at pc=" + Str(pc)
         gExitApplication = #True
         ProcedureReturn
      EndIf
   CompilerEndIf
   gVar(sp)\ss = gVar(_LARRAY(_AR()\i))\dta\ar(index)\ss
   ; Copy pointer metadata if present
   If gVar(_LARRAY(_AR()\i))\dta\ar(index)\ptrtype
      gVar(sp)\ptr = gVar(_LARRAY(_AR()\i))\dta\ar(index)\ptr
      gVar(sp)\ptrtype = gVar(_LARRAY(_AR()\i))\dta\ar(index)\ptrtype
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
   ; Copy pointer metadata if present (for arrays of pointers)
   If gVar(sp)\ptrtype
      gVar(arrIdx)\dta\ar(index)\ptr = gVar(sp)\ptr
      gVar(arrIdx)\dta\ar(index)\ptrtype = gVar(sp)\ptrtype
   EndIf
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
   ; Copy pointer metadata if present (for arrays of pointers)
   If gVar(sp)\ptrtype
      gVar(arrIdx)\dta\ar(index)\ptr = gVar(sp)\ptr
      gVar(arrIdx)\dta\ar(index)\ptrtype = gVar(sp)\ptrtype
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
      arraySize = gVar(_LARRAY(_AR()\i))\dta\size
      If index < 0 Or index >= arraySize
         Debug "Array index out of bounds: " + Str(index) + " (size: " + Str(arraySize) + ") at pc=" + Str(pc)
         gExitApplication = #True
         ProcedureReturn
      EndIf
   CompilerEndIf
   gVar(_LARRAY(_AR()\i))\dta\ar(index)\i = value
   pc + 1
EndProcedure

Procedure               C2ARRAYSTORE_INT_LOCAL_OPT_STACK()
   ; V1.18.0: Integer array store - local array in unified gVar[], optimized index, stack value
   Protected index.i, value.i
   vm_DebugFunctionName()
   index = gVar(_AR()\ndx)\i
   sp - 1
   value = gVar(sp)\i
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
   gVar(_LARRAY(_AR()\i))\dta\ar(index)\i = value
   ; Copy pointer metadata if present
   If gVar(sp)\ptrtype
      gVar(_LARRAY(_AR()\i))\dta\ar(index)\ptr = gVar(sp)\ptr
      gVar(_LARRAY(_AR()\i))\dta\ar(index)\ptrtype = gVar(sp)\ptrtype
   EndIf
   pc + 1
EndProcedure

Procedure               C2ARRAYSTORE_INT_LOCAL_STACK_OPT()
   ; V1.18.0: Integer array store - local array in unified gVar[], stack index, optimized value
   Protected index.i, value.i
   vm_DebugFunctionName()
   sp - 1
   index = gVar(sp)\i
   value = gVar(_AR()\n)\i
   CompilerIf #DEBUG
      Protected arraySize.i
      arraySize = gVar(_LARRAY(_AR()\i))\dta\size
      If index < 0 Or index >= arraySize
         Debug "Array index out of bounds: " + Str(index) + " (size: " + Str(arraySize) + ") at pc=" + Str(pc)
         gExitApplication = #True
         ProcedureReturn
      EndIf
   CompilerEndIf
   gVar(_LARRAY(_AR()\i))\dta\ar(index)\i = value
   ; Copy pointer metadata if present
   If gVar(_AR()\n)\ptrtype
      gVar(_LARRAY(_AR()\i))\dta\ar(index)\ptr = gVar(_AR()\n)\ptr
      gVar(_LARRAY(_AR()\i))\dta\ar(index)\ptrtype = gVar(_AR()\n)\ptrtype
   EndIf
   pc + 1
EndProcedure

Procedure               C2ARRAYSTORE_INT_LOCAL_STACK_STACK()
   ; V1.18.0: Integer array store - local array in unified gVar[], stack index, stack value
   Protected index.i, value.i
   vm_DebugFunctionName()
   sp - 1
   index = gVar(sp)\i
   sp - 1
   value = gVar(sp)\i
   CompilerIf #DEBUG
      Protected arraySize.i
      arraySize = gVar(_LARRAY(_AR()\i))\dta\size
      If index < 0 Or index >= arraySize
         Debug "Array index out of bounds: " + Str(index) + " (size: " + Str(arraySize) + ") at pc=" + Str(pc)
         gExitApplication = #True
         ProcedureReturn
      EndIf
   CompilerEndIf
   gVar(_LARRAY(_AR()\i))\dta\ar(index)\i = value
   ; Copy pointer metadata if present
   If gVar(sp)\ptrtype
      gVar(_LARRAY(_AR()\i))\dta\ar(index)\ptr = gVar(sp)\ptr
      gVar(_LARRAY(_AR()\i))\dta\ar(index)\ptrtype = gVar(sp)\ptrtype
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
   ; Copy pointer metadata if present (for arrays of pointers)
   If gVar(sp)\ptrtype
      gVar(arrIdx)\dta\ar(index)\ptr = gVar(sp)\ptr
      gVar(arrIdx)\dta\ar(index)\ptrtype = gVar(sp)\ptrtype
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
   ; Copy pointer metadata if present (for arrays of pointers)
   If gVar(sp)\ptrtype
      gVar(arrIdx)\dta\ar(index)\ptr = gVar(sp)\ptr
      gVar(arrIdx)\dta\ar(index)\ptrtype = gVar(sp)\ptrtype
   EndIf
   pc + 1
EndProcedure

Procedure               C2ARRAYSTORE_FLOAT_LOCAL_OPT_OPT()
   ; V1.18.0: Float array store - local array in unified gVar[], optimized index, optimized value
   Protected index.i
   Protected value.f
   vm_DebugFunctionName()
   index = gVar(_AR()\ndx)\i
   value = gVar(_AR()\n)\f
   CompilerIf #DEBUG
      Protected arraySize.i
      arraySize = gVar(_LARRAY(_AR()\i))\dta\size
      If index < 0 Or index >= arraySize
         Debug "Array index out of bounds: " + Str(index) + " (size: " + Str(arraySize) + ") at pc=" + Str(pc)
         gExitApplication = #True
         ProcedureReturn
      EndIf
   CompilerEndIf
   gVar(_LARRAY(_AR()\i))\dta\ar(index)\f = value
   ; Copy pointer metadata if present
   If gVar(_AR()\n)\ptrtype
      gVar(_LARRAY(_AR()\i))\dta\ar(index)\ptr = gVar(_AR()\n)\ptr
      gVar(_LARRAY(_AR()\i))\dta\ar(index)\ptrtype = gVar(_AR()\n)\ptrtype
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
   value = gVar(sp)\f
   CompilerIf #DEBUG
      Protected arraySize.i
      arraySize = gVar(_LARRAY(_AR()\i))\dta\size
      If index < 0 Or index >= arraySize
         Debug "Array index out of bounds: " + Str(index) + " (size: " + Str(arraySize) + ") at pc=" + Str(pc)
         gExitApplication = #True
         ProcedureReturn
      EndIf
   CompilerEndIf
   gVar(_LARRAY(_AR()\i))\dta\ar(index)\f = value
   ; Copy pointer metadata if present
   If gVar(sp)\ptrtype
      gVar(_LARRAY(_AR()\i))\dta\ar(index)\ptr = gVar(sp)\ptr
      gVar(_LARRAY(_AR()\i))\dta\ar(index)\ptrtype = gVar(sp)\ptrtype
   EndIf
   pc + 1
EndProcedure

Procedure               C2ARRAYSTORE_FLOAT_LOCAL_STACK_OPT()
   ; V1.18.0: Float array store - local array in unified gVar[], stack index, optimized value
   Protected index.i
   Protected value.f
   vm_DebugFunctionName()
   sp - 1
   index = gVar(sp)\i
   value = gVar(_AR()\n)\f
   CompilerIf #DEBUG
      Protected arraySize.i
      arraySize = gVar(_LARRAY(_AR()\i))\dta\size
      If index < 0 Or index >= arraySize
         Debug "Array index out of bounds: " + Str(index) + " (size: " + Str(arraySize) + ") at pc=" + Str(pc)
         gExitApplication = #True
         ProcedureReturn
      EndIf
   CompilerEndIf
   gVar(_LARRAY(_AR()\i))\dta\ar(index)\f = value
   ; Copy pointer metadata if present
   If gVar(_AR()\n)\ptrtype
      gVar(_LARRAY(_AR()\i))\dta\ar(index)\ptr = gVar(_AR()\n)\ptr
      gVar(_LARRAY(_AR()\i))\dta\ar(index)\ptrtype = gVar(_AR()\n)\ptrtype
   EndIf
   pc + 1
EndProcedure

Procedure               C2ARRAYSTORE_FLOAT_LOCAL_STACK_STACK()
   ; V1.18.0: Float array store - local array in unified gVar[], stack index, stack value
   Protected index.i
   Protected value.f
   vm_DebugFunctionName()
   sp - 1
   index = gVar(sp)\i
   sp - 1
   value = gVar(sp)\f
   CompilerIf #DEBUG
      Protected arraySize.i
      arraySize = gVar(_LARRAY(_AR()\i))\dta\size
      If index < 0 Or index >= arraySize
         Debug "Array index out of bounds: " + Str(index) + " (size: " + Str(arraySize) + ") at pc=" + Str(pc)
         gExitApplication = #True
         ProcedureReturn
      EndIf
   CompilerEndIf
   gVar(_LARRAY(_AR()\i))\dta\ar(index)\f = value
   ; Copy pointer metadata if present
   If gVar(sp)\ptrtype
      gVar(_LARRAY(_AR()\i))\dta\ar(index)\ptr = gVar(sp)\ptr
      gVar(_LARRAY(_AR()\i))\dta\ar(index)\ptrtype = gVar(sp)\ptrtype
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
   ; Copy pointer metadata if present (for arrays of pointers)
   If gVar(sp)\ptrtype
      gVar(arrIdx)\dta\ar(index)\ptr = gVar(sp)\ptr
      gVar(arrIdx)\dta\ar(index)\ptrtype = gVar(sp)\ptrtype
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
   ; Copy pointer metadata if present (for arrays of pointers)
   If gVar(sp)\ptrtype
      gVar(arrIdx)\dta\ar(index)\ptr = gVar(sp)\ptr
      gVar(arrIdx)\dta\ar(index)\ptrtype = gVar(sp)\ptrtype
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
      arraySize = gVar(_LARRAY(_AR()\i))\dta\size
      If index < 0 Or index >= arraySize
         Debug "Array index out of bounds: " + Str(index) + " (size: " + Str(arraySize) + ") at pc=" + Str(pc)
         gExitApplication = #True
         ProcedureReturn
      EndIf
   CompilerEndIf
   gVar(_LARRAY(_AR()\i))\dta\ar(index)\ss = value
   ; Copy pointer metadata if present
   If gVar(_AR()\n)\ptrtype
      gVar(_LARRAY(_AR()\i))\dta\ar(index)\ptr = gVar(_AR()\n)\ptr
      gVar(_LARRAY(_AR()\i))\dta\ar(index)\ptrtype = gVar(_AR()\n)\ptrtype
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
   value = gVar(sp)\ss
   CompilerIf #DEBUG
      Protected arraySize.i
      arraySize = gVar(_LARRAY(_AR()\i))\dta\size
      If index < 0 Or index >= arraySize
         Debug "Array index out of bounds: " + Str(index) + " (size: " + Str(arraySize) + ") at pc=" + Str(pc)
         gExitApplication = #True
         ProcedureReturn
      EndIf
   CompilerEndIf
   gVar(_LARRAY(_AR()\i))\dta\ar(index)\ss = value
   ; Copy pointer metadata if present
   If gVar(sp)\ptrtype
      gVar(_LARRAY(_AR()\i))\dta\ar(index)\ptr = gVar(sp)\ptr
      gVar(_LARRAY(_AR()\i))\dta\ar(index)\ptrtype = gVar(sp)\ptrtype
   EndIf
   pc + 1
EndProcedure

Procedure               C2ARRAYSTORE_STR_LOCAL_STACK_OPT()
   ; V1.18.0: String array store - local array in unified gVar[], stack index, optimized value
   Protected index.i
   Protected value.s
   vm_DebugFunctionName()
   sp - 1
   index = gVar(sp)\i
   value = gVar(_AR()\n)\ss
   CompilerIf #DEBUG
      Protected arraySize.i
      arraySize = gVar(_LARRAY(_AR()\i))\dta\size
      If index < 0 Or index >= arraySize
         Debug "Array index out of bounds: " + Str(index) + " (size: " + Str(arraySize) + ") at pc=" + Str(pc)
         gExitApplication = #True
         ProcedureReturn
      EndIf
   CompilerEndIf
   gVar(_LARRAY(_AR()\i))\dta\ar(index)\ss = value
   ; Copy pointer metadata if present
   If gVar(_AR()\n)\ptrtype
      gVar(_LARRAY(_AR()\i))\dta\ar(index)\ptr = gVar(_AR()\n)\ptr
      gVar(_LARRAY(_AR()\i))\dta\ar(index)\ptrtype = gVar(_AR()\n)\ptrtype
   EndIf
   pc + 1
EndProcedure

Procedure               C2ARRAYSTORE_STR_LOCAL_STACK_STACK()
   ; V1.18.0: String array store - local array in unified gVar[], stack index, stack value
   Protected index.i
   Protected value.s
   vm_DebugFunctionName()
   sp - 1
   index = gVar(sp)\i
   sp - 1
   value = gVar(sp)\ss
   CompilerIf #DEBUG
      Protected arraySize.i
      arraySize = gVar(_LARRAY(_AR()\i))\dta\size
      If index < 0 Or index >= arraySize
         Debug "Array index out of bounds: " + Str(index) + " (size: " + Str(arraySize) + ") at pc=" + Str(pc)
         gExitApplication = #True
         ProcedureReturn
      EndIf
   CompilerEndIf
   gVar(_LARRAY(_AR()\i))\dta\ar(index)\ss = value
   ; Copy pointer metadata if present
   If gVar(sp)\ptrtype
      gVar(_LARRAY(_AR()\i))\dta\ar(index)\ptr = gVar(sp)\ptr
      gVar(_LARRAY(_AR()\i))\dta\ar(index)\ptrtype = gVar(sp)\ptrtype
   EndIf
   pc + 1
EndProcedure

;- End Array Operations

; IDE Options = PureBasic 6.21 (Windows - x64)
; Folding = --------------
; EnableAsm
; EnableThread
; EnableXP
; CPU = 1
; EnablePurifier
; EnableCompileCount = 0
; EnableBuildCount = 0
; EnableExeConstant