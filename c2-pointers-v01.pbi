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
; Pointer Operations Module
; Version: 01
;

;- Pointer Operations

;- Global function pointers (initialized once for performance)
Global gPeekIntFn
Global gPokeIntFn
Global gPeekFloatFn
Global gPokeFloatFn
Global gPeekStringFn
Global gPokeStringFn

;- Peek/Poke functions for pointer dereferencing and storing
Procedure PeekInt(*field, *dest.stVTSimple)
   ; Peek function for integer fields - stores directly in destination
   *dest\i = PeekI(*field)
EndProcedure

Procedure PeekFloat(*field, *dest.stVTSimple)
   ; Peek function for float fields - stores directly in destination
   *dest\f = PeekD(*field)
EndProcedure

Procedure PeekString(*field, *dest.stVTSimple)
   ; Peek function for string fields - *field is actually slot index as pointer
   Protected slot.i = *field
   *dest\ss = gVar(slot)\ss
EndProcedure

Procedure PokeInt(*field, *src.stVTSimple)
   ; Poke function for integer fields
   PokeI(*field, *src\i)
EndProcedure

Procedure PokeFloat(*field, *src.stVTSimple)
   ; Poke function for float fields
   PokeD(*field, *src\f)
EndProcedure

Procedure PokeString(*field, *src.stVTSimple)
   ; Poke function for string fields - *field is actually slot index as pointer
   Protected slot.i = *field
   gVar(slot)\ss = *src\ss
EndProcedure

;- Peek/Poke functions for array element dereferencing
Procedure PeekArrayInt(arraySlot.i, elementIndex.i, *dest.stVTSimple)
   ; Peek function for integer array elements
   *dest\i = gVar(arraySlot)\dta\ar(elementIndex)\i
EndProcedure

Procedure PeekArrayFloat(arraySlot.i, elementIndex.i, *dest.stVTSimple)
   ; Peek function for float array elements
   *dest\f = gVar(arraySlot)\dta\ar(elementIndex)\f
EndProcedure

Procedure PeekArrayString(arraySlot.i, elementIndex.i, *dest.stVTSimple)
   ; Peek function for string array elements
   *dest\ss = gVar(arraySlot)\dta\ar(elementIndex)\ss
EndProcedure

Procedure PokeArrayInt(arraySlot.i, elementIndex.i, *src.stVTSimple)
   ; Poke function for integer array elements
   gVar(arraySlot)\dta\ar(elementIndex)\i = *src\i
EndProcedure

Procedure PokeArrayFloat(arraySlot.i, elementIndex.i, *src.stVTSimple)
   ; Poke function for float array elements
   gVar(arraySlot)\dta\ar(elementIndex)\f = *src\f
EndProcedure

Procedure PokeArrayString(arraySlot.i, elementIndex.i, *src.stVTSimple)
   ; Poke function for string array elements
   gVar(arraySlot)\dta\ar(elementIndex)\ss = *src\ss
EndProcedure

;- Initialize function pointers (call once at VM startup)
Procedure InitPointerFunctions()
   gPeekIntFn = @PeekInt()
   gPokeIntFn = @PokeInt()
   gPeekFloatFn = @PeekFloat()
   gPokeFloatFn = @PokeFloat()
   gPeekStringFn = @PeekString()
   gPokeStringFn = @PokeString()
EndProcedure

Procedure               C2GETADDR()
   ; Get address of integer variable - &var
   ; Sets *ptr to point to field and ptrtype tag

   vm_DebugFunctionName()

   gVar(sp)\i = _AR()\i
   gVar(sp)\ptr = @gVar(_AR()\i)\i
   gVar(sp)\ptrtype = #PTR_INT

   sp + 1
   pc + 1
EndProcedure

Procedure               C2GETADDRF()
   ; Get address of float variable - &var.f
   ; Sets *ptr to point to field and ptrtype tag

   vm_DebugFunctionName()

   gVar(sp)\i = _AR()\i
   gVar(sp)\ptr = @gVar(_AR()\i)\f
   gVar(sp)\ptrtype = #PTR_FLOAT

   sp + 1
   pc + 1
EndProcedure

Procedure               C2GETADDRS()
   ; Get address of string variable - &var.s
   ; Sets *ptr to slot index (as pointer) and ptrtype tag
   ; Note: For strings, we store slot index not memory address (managed type)

   vm_DebugFunctionName()

   gVar(sp)\i = _AR()\i
   gVar(sp)\ptr = _AR()\i
   gVar(sp)\ptrtype = #PTR_STRING

   sp + 1
   pc + 1
EndProcedure

Procedure               C2PTRFETCH()
   ; Generic pointer fetch using type dispatch
   ; Dispatches based on ptrtype tag for optimal performance
   ; V1.19.4: Single-field population for speed, with minimal cross-population for strings

   vm_DebugFunctionName()

   sp - 1

   Select gVar(sp)\ptrtype
      Case #PTR_INT
         gVar(sp)\i = PeekI(gVar(sp)\ptr)

      Case #PTR_FLOAT
         gVar(sp)\f = PeekD(gVar(sp)\ptr)

      Case #PTR_STRING
         ; V1.19.4: Cross-populate \i with string length for assertEqual detection
         gVar(sp)\ss = gVar(gVar(sp)\ptr)\ss
         gVar(sp)\i = Len(gVar(sp)\ss)

      Case #PTR_ARRAY_INT
         gVar(sp)\i = gVar(gVar(sp)\ptr)\dta\ar(gVar(sp)\i)\i

      Case #PTR_ARRAY_FLOAT
         gVar(sp)\f = gVar(gVar(sp)\ptr)\dta\ar(gVar(sp)\i)\f

      Case #PTR_ARRAY_STRING
         ; V1.19.4: Cross-populate \i with string length for assertEqual detection
         gVar(sp)\ss = gVar(gVar(sp)\ptr)\dta\ar(gVar(sp)\i)\ss
         gVar(sp)\i = Len(gVar(sp)\ss)

      Default
         CompilerIf #DEBUG
            Debug "Invalid pointer type in PTRFETCH: " + Str(gVar(sp)\ptrtype) + " at pc=" + Str(pc)
            gExitApplication = #True
            ProcedureReturn
         CompilerEndIf
   EndSelect

   sp + 1
   pc + 1
EndProcedure

Procedure               C2PTRFETCH_INT()
   ; Fetch integer through pointer
   ; Top of stack contains pointer (slot index or array pointer)
   ; V1.20.24: Handle both PTR_INT and PTR_ARRAY_INT

   vm_DebugFunctionName()

   sp - 1

   ; Check pointer type to determine fetch strategy
   If gVar(sp)\ptrtype = #PTR_ARRAY_INT
      ; Array element pointer: use ptr field for array slot, i field for index
      gVar(sp)\i = gVar(gVar(sp)\ptr)\dta\ar(gVar(sp)\i)\i
   Else
      ; Simple variable pointer (PTR_INT): use i field for slot
      ; Bounds check
      CompilerIf #DEBUG
         If gVar(sp)\i < 0 Or gVar(sp)\i >= #C2MAXCONSTANTS
            Debug "NULL or invalid pointer dereference at pc=" + Str(pc) + " slot=" + Str(gVar(sp)\i)
            gExitApplication = #True
            ProcedureReturn
         EndIf
      CompilerEndIf

      gVar(sp)\i = gVar(gVar(sp)\i)\i
   EndIf

   sp + 1
   pc + 1
EndProcedure

Procedure               C2PTRFETCH_FLOAT()
   ; Fetch float through pointer
   ; Top of stack contains pointer (slot index or array pointer)
   ; V1.20.24: Handle both PTR_FLOAT and PTR_ARRAY_FLOAT

   vm_DebugFunctionName()

   sp - 1

   ; Check pointer type to determine fetch strategy
   If gVar(sp)\ptrtype = #PTR_ARRAY_FLOAT
      ; Array element pointer: use ptr field for array slot, i field for index
      gVar(sp)\f = gVar(gVar(sp)\ptr)\dta\ar(gVar(sp)\i)\f
   Else
      ; Simple variable pointer (PTR_FLOAT): use i field for slot
      ; Bounds check
      CompilerIf #DEBUG
         If gVar(sp)\i < 0 Or gVar(sp)\i >= #C2MAXCONSTANTS
            Debug "NULL or invalid pointer dereference at pc=" + Str(pc) + " slot=" + Str(gVar(sp)\i)
            gExitApplication = #True
            ProcedureReturn
         EndIf
      CompilerEndIf

      gVar(sp)\f = gVar(gVar(sp)\i)\f
   EndIf

   sp + 1
   pc + 1
EndProcedure

Procedure               C2PTRFETCH_STR()
   ; Fetch string through pointer
   ; Top of stack contains pointer (slot index or array pointer)
   ; V1.20.24: Handle both PTR_STRING and PTR_ARRAY_STRING

   vm_DebugFunctionName()

   sp - 1

   ; Check pointer type to determine fetch strategy
   If gVar(sp)\ptrtype = #PTR_ARRAY_STRING
      ; Array element pointer: use ptr field for array slot, i field for index
      gVar(sp)\ss = gVar(gVar(sp)\ptr)\dta\ar(gVar(sp)\i)\ss
      gVar(sp)\i = Len(gVar(sp)\ss)  ; Cross-populate for assertEqual
   Else
      ; Simple variable pointer (PTR_STRING): use i field for slot
      ; Bounds check
      CompilerIf #DEBUG
         If gVar(sp)\i < 0 Or gVar(sp)\i >= #C2MAXCONSTANTS
            Debug "NULL or invalid pointer dereference at pc=" + Str(pc) + " slot=" + Str(gVar(sp)\i)
            gExitApplication = #True
            ProcedureReturn
         EndIf
      CompilerEndIf

      gVar(sp)\ss = gVar(gVar(sp)\i)\ss
      gVar(sp)\i = Len(gVar(sp)\ss)  ; Cross-populate for assertEqual
   EndIf

   sp + 1
   pc + 1
EndProcedure

Procedure               C2PTRSTORE()
   ; Generic pointer store using type dispatch
   ; Dispatches based on ptrtype tag for optimal performance
   ; Stack: [value] [pointer]

   vm_DebugFunctionName()

   sp - 1

   Select gVar(sp)\ptrtype
      Case #PTR_INT
         sp - 1
         PokeI(gVar(sp + 1)\ptr, gVar(sp)\i)

      Case #PTR_FLOAT
         sp - 1
         PokeD(gVar(sp + 1)\ptr, gVar(sp)\f)

      Case #PTR_STRING
         sp - 1
         gVar(gVar(sp + 1)\ptr)\ss = gVar(sp)\ss

      Case #PTR_ARRAY_INT
         sp - 1
         gVar(gVar(sp + 1)\ptr)\dta\ar(gVar(sp + 1)\i)\i = gVar(sp)\i

      Case #PTR_ARRAY_FLOAT
         sp - 1
         gVar(gVar(sp + 1)\ptr)\dta\ar(gVar(sp + 1)\i)\f = gVar(sp)\f

      Case #PTR_ARRAY_STRING
         sp - 1
         gVar(gVar(sp + 1)\ptr)\dta\ar(gVar(sp + 1)\i)\ss = gVar(sp)\ss

      Default
         CompilerIf #DEBUG
            Debug "Invalid pointer type in PTRSTORE: " + Str(gVar(sp)\ptrtype) + " at pc=" + Str(pc)
            gExitApplication = #True
            ProcedureReturn
         CompilerEndIf
   EndSelect

   pc + 1
EndProcedure

Procedure               C2PTRSTORE_INT()
   ; Store integer through pointer
   ; Stack: [value] [pointer]
   ; V1.20.24: Handle both PTR_INT and PTR_ARRAY_INT

   vm_DebugFunctionName()

   sp - 1

   ; Check pointer type to determine store strategy
   If gVar(sp)\ptrtype = #PTR_ARRAY_INT
      ; Array element pointer: use ptr field for array slot, i field for index
      sp - 1
      gVar(gVar(sp + 1)\ptr)\dta\ar(gVar(sp + 1)\i)\i = gVar(sp)\i
   Else
      ; Simple variable pointer (PTR_INT): use i field for slot
      ; Bounds check
      CompilerIf #DEBUG
         If gVar(sp)\i < 0 Or gVar(sp)\i >= #C2MAXCONSTANTS
            Debug "NULL or invalid pointer dereference at pc=" + Str(pc) + " slot=" + Str(gVar(sp)\i)
            gExitApplication = #True
            ProcedureReturn
         EndIf
      CompilerEndIf

      sp - 1
      gVar(gVar(sp + 1)\i)\i = gVar(sp)\i
   EndIf

   pc + 1
EndProcedure

Procedure               C2PTRSTORE_FLOAT()
   ; Store float through pointer
   ; Stack: [value] [pointer]
   ; V1.20.24: Handle both PTR_FLOAT and PTR_ARRAY_FLOAT

   vm_DebugFunctionName()

   sp - 1

   ; Check pointer type to determine store strategy
   If gVar(sp)\ptrtype = #PTR_ARRAY_FLOAT
      ; Array element pointer: use ptr field for array slot, i field for index
      sp - 1
      gVar(gVar(sp + 1)\ptr)\dta\ar(gVar(sp + 1)\i)\f = gVar(sp)\f
   Else
      ; Simple variable pointer (PTR_FLOAT): use i field for slot
      ; Bounds check
      CompilerIf #DEBUG
         If gVar(sp)\i < 0 Or gVar(sp)\i >= #C2MAXCONSTANTS
            Debug "NULL or invalid pointer dereference at pc=" + Str(pc) + " slot=" + Str(gVar(sp)\i)
            gExitApplication = #True
            ProcedureReturn
         EndIf
      CompilerEndIf

      sp - 1
      gVar(gVar(sp + 1)\i)\f = gVar(sp)\f
   EndIf

   pc + 1
EndProcedure

Procedure               C2PTRSTORE_STR()
   ; Store string through pointer
   ; Stack: [value] [pointer]
   ; V1.20.24: Handle both PTR_STRING and PTR_ARRAY_STRING

   vm_DebugFunctionName()

   sp - 1

   ; Check pointer type to determine store strategy
   If gVar(sp)\ptrtype = #PTR_ARRAY_STRING
      ; Array element pointer: use ptr field for array slot, i field for index
      sp - 1
      gVar(gVar(sp + 1)\ptr)\dta\ar(gVar(sp + 1)\i)\ss = gVar(sp)\ss
   Else
      ; Simple variable pointer (PTR_STRING): use i field for slot
      ; Bounds check
      CompilerIf #DEBUG
         If gVar(sp)\i < 0 Or gVar(sp)\i >= #C2MAXCONSTANTS
            Debug "NULL or invalid pointer dereference at pc=" + Str(pc) + " slot=" + Str(gVar(sp)\i)
            gExitApplication = #True
            ProcedureReturn
         EndIf
      CompilerEndIf

      sp - 1
      gVar(gVar(sp + 1)\i)\ss = gVar(sp)\ss
   EndIf

   pc + 1
EndProcedure

Procedure               C2PTRADD()
   ; Pointer arithmetic: ptr + offset
   ; Stack: [offset] (top), [ptr] (bottom)
   ; Modifies pointer on stack
   Protected offset.i, ptrType.w

   vm_DebugFunctionName()

   sp - 1
   offset = gVar(sp)\i
   ptrType = gVar(sp - 1)\ptrtype

   ; Update element index for all pointer types
   gVar(sp - 1)\i + offset

   ; Update memory address for variable pointers (not array pointers)
   Select ptrType
      Case #PTR_INT
         gVar(sp - 1)\ptr + (offset * 8)
      Case #PTR_FLOAT
         gVar(sp - 1)\ptr + (offset * 8)
      Case #PTR_STRING
         ; String pointers: \i is the slot index, no \ptr update needed
   EndSelect

   pc + 1
EndProcedure

Procedure               C2PTRSUB()
   ; Pointer arithmetic: ptr - offset
   ; Stack: [offset] (top), [ptr] (bottom)
   ; Modifies pointer on stack
   Protected offset.i, ptrType.w

   vm_DebugFunctionName()

   sp - 1
   offset = gVar(sp)\i
   ptrType = gVar(sp - 1)\ptrtype

   ; Update element index for all pointer types
   gVar(sp - 1)\i - offset

   ; Update memory address for variable pointers (not array pointers)
   Select ptrType
      Case #PTR_INT
         gVar(sp - 1)\ptr - (offset * 8)
      Case #PTR_FLOAT
         gVar(sp - 1)\ptr - (offset * 8)
      Case #PTR_STRING
         ; String pointers: \i is the slot index, no \ptr update needed
   EndSelect

   pc + 1
EndProcedure

;- Pointer increment/decrement operations (V1.20.36)

Procedure               C2PTRINC()
   ; Pointer increment: ptr++
   ; Increments pointer by one element (based on pointer type)
   ; _AR()\i = variable slot containing the pointer
   ; For array pointers: increments element index
   ; For variable pointers: increments memory address by sizeof(type)

   Protected varSlot.i, ptrType.w

   vm_DebugFunctionName()

   varSlot = _AR()\i
   ptrType = gVar(varSlot)\ptrtype

   Select ptrType
      Case #PTR_ARRAY_INT, #PTR_ARRAY_FLOAT, #PTR_ARRAY_STRING
         ; Array pointer: increment element index
         gVar(varSlot)\i + 1

      Case #PTR_INT
         ; Integer pointer: increment memory address by 8 bytes (sizeof Integer)
         gVar(varSlot)\i + 1
         gVar(varSlot)\ptr + 8

      Case #PTR_FLOAT
         ; Float pointer: increment memory address by 8 bytes (sizeof Double)
         gVar(varSlot)\i + 1
         gVar(varSlot)\ptr + 8

      Case #PTR_STRING
         ; String pointer: increment slot index by 1
         gVar(varSlot)\i + 1

   EndSelect

   pc + 1
EndProcedure

Procedure               C2PTRDEC()
   ; Pointer decrement: ptr--
   ; Decrements pointer by one element (based on pointer type)
   ; _AR()\i = variable slot containing the pointer

   Protected varSlot.i, ptrType.w

   vm_DebugFunctionName()

   varSlot = _AR()\i
   ptrType = gVar(varSlot)\ptrtype

   Select ptrType
      Case #PTR_ARRAY_INT, #PTR_ARRAY_FLOAT, #PTR_ARRAY_STRING
         ; Array pointer: decrement element index
         gVar(varSlot)\i - 1

      Case #PTR_INT
         ; Integer pointer: decrement memory address by 8 bytes
         gVar(varSlot)\i - 1
         gVar(varSlot)\ptr - 8

      Case #PTR_FLOAT
         ; Float pointer: decrement memory address by 8 bytes
         gVar(varSlot)\i - 1
         gVar(varSlot)\ptr - 8

      Case #PTR_STRING
         ; String pointer: decrement slot index by 1
         gVar(varSlot)\i - 1

   EndSelect

   pc + 1
EndProcedure

Procedure               C2PTRINC_PRE()
   ; Pre-increment pointer: ++ptr
   ; Increments pointer and pushes new value
   ; _AR()\i = variable slot containing the pointer

   Protected varSlot.i, ptrType.w

   vm_DebugFunctionName()

   varSlot = _AR()\i
   ptrType = gVar(varSlot)\ptrtype

   ; Increment pointer
   Select ptrType
      Case #PTR_ARRAY_INT, #PTR_ARRAY_FLOAT, #PTR_ARRAY_STRING
         gVar(varSlot)\i + 1
      Case #PTR_INT
         gVar(varSlot)\i + 1
         gVar(varSlot)\ptr + 8
      Case #PTR_FLOAT
         gVar(varSlot)\i + 1
         gVar(varSlot)\ptr + 8
      Case #PTR_STRING
         gVar(varSlot)\i + 1
   EndSelect

   ; Push new pointer value to stack
   gVar(sp)\i = gVar(varSlot)\i
   gVar(sp)\ptr = gVar(varSlot)\ptr
   gVar(sp)\ptrtype = ptrType
   sp + 1

   pc + 1
EndProcedure

Procedure               C2PTRDEC_PRE()
   ; Pre-decrement pointer: --ptr
   ; Decrements pointer and pushes new value
   ; _AR()\i = variable slot containing the pointer

   Protected varSlot.i, ptrType.w

   vm_DebugFunctionName()

   varSlot = _AR()\i
   ptrType = gVar(varSlot)\ptrtype

   ; Decrement pointer
   Select ptrType
      Case #PTR_ARRAY_INT, #PTR_ARRAY_FLOAT, #PTR_ARRAY_STRING
         gVar(varSlot)\i - 1
      Case #PTR_INT
         gVar(varSlot)\i - 1
         gVar(varSlot)\ptr - 8
      Case #PTR_FLOAT
         gVar(varSlot)\i - 1
         gVar(varSlot)\ptr - 8
      Case #PTR_STRING
         gVar(varSlot)\i - 1
   EndSelect

   ; Push new pointer value to stack
   gVar(sp)\i = gVar(varSlot)\i
   gVar(sp)\ptr = gVar(varSlot)\ptr
   gVar(sp)\ptrtype = ptrType
   sp + 1

   pc + 1
EndProcedure

Procedure               C2PTRINC_POST()
   ; Post-increment pointer: ptr++
   ; Pushes old value then increments pointer
   ; _AR()\i = variable slot containing the pointer

   Protected varSlot.i, ptrType.w

   vm_DebugFunctionName()

   varSlot = _AR()\i
   ptrType = gVar(varSlot)\ptrtype

   ; Push old pointer value to stack
   gVar(sp)\i = gVar(varSlot)\i
   gVar(sp)\ptr = gVar(varSlot)\ptr
   gVar(sp)\ptrtype = ptrType
   sp + 1

   ; Increment pointer
   Select ptrType
      Case #PTR_ARRAY_INT, #PTR_ARRAY_FLOAT, #PTR_ARRAY_STRING
         gVar(varSlot)\i + 1
      Case #PTR_INT
         gVar(varSlot)\i + 1
         gVar(varSlot)\ptr + 8
      Case #PTR_FLOAT
         gVar(varSlot)\i + 1
         gVar(varSlot)\ptr + 8
      Case #PTR_STRING
         gVar(varSlot)\i + 1
   EndSelect

   pc + 1
EndProcedure

Procedure               C2PTRDEC_POST()
   ; Post-decrement pointer: ptr--
   ; Pushes old value then decrements pointer
   ; _AR()\i = variable slot containing the pointer

   Protected varSlot.i, ptrType.w

   vm_DebugFunctionName()

   varSlot = _AR()\i
   ptrType = gVar(varSlot)\ptrtype

   ; Push old pointer value to stack
   gVar(sp)\i = gVar(varSlot)\i
   gVar(sp)\ptr = gVar(varSlot)\ptr
   gVar(sp)\ptrtype = ptrType
   sp + 1

   ; Decrement pointer
   Select ptrType
      Case #PTR_ARRAY_INT, #PTR_ARRAY_FLOAT, #PTR_ARRAY_STRING
         gVar(varSlot)\i - 1
      Case #PTR_INT
         gVar(varSlot)\i - 1
         gVar(varSlot)\ptr - 8
      Case #PTR_FLOAT
         gVar(varSlot)\i - 1
         gVar(varSlot)\ptr - 8
      Case #PTR_STRING
         gVar(varSlot)\i - 1
   EndSelect

   pc + 1
EndProcedure

;- Pointer compound assignment operations (V1.20.37)

Procedure               C2PTRADD_ASSIGN()
   ; Pointer compound assignment: ptr += offset
   ; _AR()\i = variable slot containing the pointer
   ; Top of stack = offset value
   ; Adds offset to pointer (pointer arithmetic based on type)

   Protected varSlot.i, ptrType.w, offset.i

   vm_DebugFunctionName()

   varSlot = _AR()\i
   ptrType = gVar(varSlot)\ptrtype

   ; Pop offset from stack
   sp - 1
   offset = gVar(sp)\i

   ; Add offset to pointer based on type
   Select ptrType
      Case #PTR_ARRAY_INT, #PTR_ARRAY_FLOAT, #PTR_ARRAY_STRING
         ; Array pointer: add to element index
         gVar(varSlot)\i + offset

      Case #PTR_INT
         ; Integer pointer: add offset * 8 to memory address
         gVar(varSlot)\i + offset
         gVar(varSlot)\ptr + (offset * 8)

      Case #PTR_FLOAT
         ; Float pointer: add offset * 8 to memory address
         gVar(varSlot)\i + offset
         gVar(varSlot)\ptr + (offset * 8)

      Case #PTR_STRING
         ; String pointer: add to slot index
         gVar(varSlot)\i + offset

   EndSelect

   pc + 1
EndProcedure

Procedure               C2PTRSUB_ASSIGN()
   ; Pointer compound assignment: ptr -= offset
   ; _AR()\i = variable slot containing the pointer
   ; Top of stack = offset value
   ; Subtracts offset from pointer (pointer arithmetic based on type)

   Protected varSlot.i, ptrType.w, offset.i

   vm_DebugFunctionName()

   varSlot = _AR()\i
   ptrType = gVar(varSlot)\ptrtype

   ; Pop offset from stack
   sp - 1
   offset = gVar(sp)\i

   ; Subtract offset from pointer based on type
   Select ptrType
      Case #PTR_ARRAY_INT, #PTR_ARRAY_FLOAT, #PTR_ARRAY_STRING
         ; Array pointer: subtract from element index
         gVar(varSlot)\i - offset

      Case #PTR_INT
         ; Integer pointer: subtract offset * 8 from memory address
         gVar(varSlot)\i - offset
         gVar(varSlot)\ptr - (offset * 8)

      Case #PTR_FLOAT
         ; Float pointer: subtract offset * 8 from memory address
         gVar(varSlot)\i - offset
         gVar(varSlot)\ptr - (offset * 8)

      Case #PTR_STRING
         ; String pointer: subtract from slot index
         gVar(varSlot)\i - offset

   EndSelect

   pc + 1
EndProcedure

Procedure               C2GETFUNCADDR()
   ; Get function PC address - &function
   ; _AR()\i = function PC address (from gFuncMeta)
   ; Pushes function PC address to stack

   vm_DebugFunctionName()

   gVar(sp)\i = _AR()\i
   gVar(sp)\ptrtype = #PTR_FUNCTION
   sp + 1
   pc + 1
EndProcedure

Procedure               C2CALLFUNCPTR()
   ; Call function through pointer
   ; _AR()\j = parameter count
   ; _AR()\n = local variable count
   ; _AR()\ndx = local array count
   ; Top of stack contains function PC address (before parameters)
   ; Stack layout: [param1] [param2] ... [paramN] [funcPtr]

   Protected nParams.l, nLocals.l, totalVars.l, nLocalArrays.l
   Protected i.l, paramSp.l, funcPc.l
   Protected prevStackDepth.i

   vm_DebugFunctionName()

   ; Read parameters from instruction
   nParams = _AR()\j
   nLocals = _AR()\n
   nLocalArrays = _AR()\ndx
   totalVars = nParams + nLocals

   ; Get function PC from stack (it's AFTER the parameters)
   funcPc = gVar(sp - 1)\i
   sp - 1  ; Pop function pointer

   ; Bounds check on function PC
   CompilerIf #DEBUG
      If funcPc < 0 Or funcPc >= ArraySize(arCode())
         Debug "Invalid function pointer at pc=" + Str(pc) + " funcPc=" + Str(funcPc)
         gExitApplication = #True
         ProcedureReturn
      EndIf
   CompilerEndIf

   ; Create stack frame (similar to C2CALL)
   prevStackDepth = gStackDepth
   gStackDepth = gStackDepth + 1

   If gStackDepth >= gMaxStackDepth
      Debug "*** FATAL ERROR: Stack overflow in function pointer call - max depth " + Str(gMaxStackDepth) + " exceeded at pc=" + Str(pc)
      End
   EndIf

   gStack(gStackDepth)\pc = pc + 1
   gStack(gStackDepth)\sp = sp - nParams

   ; V1.18.0: Allocate local variable slots in unified gVar[] array
   Protected localSlotStart.l
   localSlotStart = gCurrentMaxLocal
   gCurrentMaxLocal + totalVars

   gStack(gStackDepth)\localSlotStart = localSlotStart
   gStack(gStackDepth)\localSlotCount = totalVars

   ; Copy parameters from stack to allocated gVar[] slots
   If nParams > 0
      paramSp = sp - nParams
      For i = 0 To nParams - 1
         gVar(localSlotStart + i)\i = gVar(paramSp + i)\i
         gVar(localSlotStart + i)\f = gVar(paramSp + i)\f
         gVar(localSlotStart + i)\ss = gVar(paramSp + i)\ss
      Next
   EndIf

   ; Note: Local arrays not supported in function pointer calls (would need function metadata)
   ; This is a limitation - function pointers can't have local arrays
   If nLocalArrays > 0
      Debug "*** WARNING: Function pointer calls do not support local arrays at pc=" + Str(pc)
   EndIf

   ; Jump to function
   pc = funcPc
   gFunctionDepth = gFunctionDepth + 1
EndProcedure

;- Array Pointer GETADDR Operations

Procedure               C2GETARRAYADDR()
   ; Get address of integer array element - &arr[i]
   ; _AR()\i = array variable slot
   ; Stack top = element index
   ; Sets up pointer structure: ptr=arraySlot, i=elementIndex, peekfn/pokefn

   Protected arraySlot.i, elementIndex.i

   vm_DebugFunctionName()

   arraySlot = _AR()\i

   ; Pop index from stack
   sp - 1
   elementIndex = gVar(sp)\i

   ; Bounds check
   CompilerIf #DEBUG
      If elementIndex < 0 Or elementIndex >= gVar(arraySlot)\dta\size
         Debug "Array index out of bounds in GETARRAYADDR: " + Str(elementIndex) + " (size: " + Str(gVar(arraySlot)\dta\size) + ") at pc=" + Str(pc)
         gExitApplication = #True
         ProcedureReturn
      EndIf
   CompilerEndIf

   ; Set up pointer structure
   gVar(sp)\ptr = arraySlot  ; Store array slot as pointer value
   gVar(sp)\i = elementIndex ; Store current element index
   gVar(sp)\ptrtype = #PTR_ARRAY_INT

   sp + 1
   pc + 1
EndProcedure

Procedure               C2GETARRAYADDRF()
   ; Get address of float array element - &arr.f[i]
   ; _AR()\i = array variable slot
   ; Stack top = element index

   Protected arraySlot.i, elementIndex.i

   vm_DebugFunctionName()

   arraySlot = _AR()\i

   ; Pop index from stack
   sp - 1
   elementIndex = gVar(sp)\i

   ; Bounds check
   CompilerIf #DEBUG
      If elementIndex < 0 Or elementIndex >= gVar(arraySlot)\dta\size
         Debug "Array index out of bounds in GETARRAYADDRF: " + Str(elementIndex) + " (size: " + Str(gVar(arraySlot)\dta\size) + ") at pc=" + Str(pc)
         gExitApplication = #True
         ProcedureReturn
      EndIf
   CompilerEndIf

   ; Set up pointer structure
   gVar(sp)\ptr = arraySlot  ; Store array slot as pointer value
   gVar(sp)\i = elementIndex ; Store current element index
   gVar(sp)\ptrtype = #PTR_ARRAY_FLOAT

   sp + 1
   pc + 1
EndProcedure

Procedure               C2GETARRAYADDRS()
   ; Get address of string array element - &arr.s[i]
   ; _AR()\i = array variable slot
   ; Stack top = element index

   Protected arraySlot.i, elementIndex.i

   vm_DebugFunctionName()

   arraySlot = _AR()\i

   ; Pop index from stack
   sp - 1
   elementIndex = gVar(sp)\i

   ; Bounds check
   CompilerIf #DEBUG
      If elementIndex < 0 Or elementIndex >= gVar(arraySlot)\dta\size
         Debug "Array index out of bounds in GETARRAYADDRS: " + Str(elementIndex) + " (size: " + Str(gVar(arraySlot)\dta\size) + ") at pc=" + Str(pc)
         gExitApplication = #True
         ProcedureReturn
      EndIf
   CompilerEndIf

   ; Set up pointer structure
   gVar(sp)\ptr = arraySlot  ; Store array slot as pointer value
   gVar(sp)\i = elementIndex ; Store current element index
   gVar(sp)\ptrtype = #PTR_ARRAY_STRING

   sp + 1
   pc + 1
EndProcedure

;- End Array Pointer Operations

;- Pointer-Only Opcodes (V1.020.027)
; These opcodes are emitted ONLY for pointer variables
; They ALWAYS copy pointer metadata - no conditional checks needed
; This keeps general opcodes (MOV, FETCH, STORE, etc.) clean and fast

Procedure               C2PMOV()
   ; Pointer-only MOV - Always copies pointer metadata
   vm_DebugFunctionName()

   gVar( _AR()\i )\i = gVar( _AR()\j )\i
   gVar( _AR()\i )\ptr = gVar( _AR()\j )\ptr
   gVar( _AR()\i )\ptrtype = gVar( _AR()\j )\ptrtype

   pc + 1
EndProcedure

Procedure               C2PFETCH()
   ; Pointer-only FETCH - Always copies pointer metadata
   vm_DebugFunctionName()

   gVar( sp )\i = gVar( _AR()\i )\i
   gVar( sp )\ptr = gVar( _AR()\i )\ptr
   gVar( sp )\ptrtype = gVar( _AR()\i )\ptrtype

   sp + 1
   pc + 1
EndProcedure

Procedure               C2PSTORE()
   ; Pointer-only STORE - Always copies pointer metadata
   vm_DebugFunctionName()
   sp - 1

   gVar( _AR()\i )\i = gVar( sp )\i
   gVar( _AR()\i )\ptr = gVar( sp )\ptr
   gVar( _AR()\i )\ptrtype = gVar( sp )\ptrtype

   pc + 1
EndProcedure

Procedure               C2PPOP()
   ; Pointer-only POP - Always copies pointer metadata
   vm_DebugFunctionName()
   sp - 1

   gVar( _AR()\i )\i = gVar( sp )\i
   gVar( _AR()\i )\ptr = gVar( sp )\ptr
   gVar( _AR()\i )\ptrtype = gVar( sp )\ptrtype

   pc + 1
EndProcedure

Procedure               C2PLFETCH()
   ; Pointer-only local FETCH - Always copies pointer metadata
   vm_DebugFunctionName()

   Protected srcSlot.i = gStack(gStackDepth)\localSlotStart + _AR()\i
   gVar( sp )\i = gVar( srcSlot )\i
   gVar( sp )\ptr = gVar( srcSlot )\ptr
   gVar( sp )\ptrtype = gVar( srcSlot )\ptrtype

   sp + 1
   pc + 1
EndProcedure

Procedure               C2PLSTORE()
   ; Pointer-only local STORE - Always copies pointer metadata
   vm_DebugFunctionName()
   sp - 1

   Protected dstSlot.i = gStack(gStackDepth)\localSlotStart + _AR()\i
   gVar( dstSlot )\i = gVar( sp )\i
   gVar( dstSlot )\ptr = gVar( sp )\ptr
   gVar( dstSlot )\ptrtype = gVar( sp )\ptrtype

   pc + 1
EndProcedure

Procedure               C2PLMOV()
   ; Pointer-only local MOV - Always copies pointer metadata
   vm_DebugFunctionName()

   Protected dstSlot.i = gStack(gStackDepth)\localSlotStart + _AR()\i
   gVar( dstSlot )\i = gVar( _AR()\j )\i
   gVar( dstSlot )\ptr = gVar( _AR()\j )\ptr
   gVar( dstSlot )\ptrtype = gVar( _AR()\j )\ptrtype

   pc + 1
EndProcedure

;- End Pointer-Only Opcodes

;- End Pointer Operations

; IDE Options = PureBasic 6.21 (Windows - x64)
; CursorPosition = 595
; FirstLine = 561
; Folding = --------
; Markers = 14
; EnableAsm
; EnableThread
; EnableXP
; CPU = 1
; EnablePurifier
; EnableCompileCount = 0
; EnableBuildCount = 0
; EnableExeConstant