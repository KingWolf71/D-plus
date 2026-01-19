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
; Version: 05
;
; V1.035.0: POINTER ARRAY ARCHITECTURE
; - Uses *gVar(gCurrentFuncSlot)\var(offset) for local variable access
; - Uses gEvalStack[] for evaluation stack
; - NOTE: C2CALLFUNCPTR needs runtime PC-to-funcSlot lookup (TODO)

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
   *dest\ss = *gVar(slot)\var(0)\ss
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
   *gVar(slot)\var(0)\ss = *src\ss
EndProcedure

;- Peek/Poke functions for array element dereferencing
Procedure PeekArrayInt(arraySlot.i, elementIndex.i, *dest.stVTSimple)
   ; Peek function for integer array elements
   *dest\i = *gVar(arraySlot)\var(0)\dta\ar(elementIndex)\i
EndProcedure

Procedure PeekArrayFloat(arraySlot.i, elementIndex.i, *dest.stVTSimple)
   ; Peek function for float array elements
   *dest\f = *gVar(arraySlot)\var(0)\dta\ar(elementIndex)\f
EndProcedure

Procedure PeekArrayString(arraySlot.i, elementIndex.i, *dest.stVTSimple)
   ; Peek function for string array elements
   *dest\ss = *gVar(arraySlot)\var(0)\dta\ar(elementIndex)\ss
EndProcedure

Procedure PokeArrayInt(arraySlot.i, elementIndex.i, *src.stVTSimple)
   ; Poke function for integer array elements
   *gVar(arraySlot)\var(0)\dta\ar(elementIndex)\i = *src\i
EndProcedure

Procedure PokeArrayFloat(arraySlot.i, elementIndex.i, *src.stVTSimple)
   ; Poke function for float array elements
   *gVar(arraySlot)\var(0)\dta\ar(elementIndex)\f = *src\f
EndProcedure

Procedure PokeArrayString(arraySlot.i, elementIndex.i, *src.stVTSimple)
   ; Poke function for string array elements
   *gVar(arraySlot)\var(0)\dta\ar(elementIndex)\ss = *src\ss
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

   gEvalStack(sp)\i = _AR()\i
   gEvalStack(sp)\ptr = @*gVar(_AR()\i)\var(0)\i
   gEvalStack(sp)\ptrtype = #PTR_INT

   sp + 1
   pc + 1
EndProcedure

Procedure               C2GETADDRF()
   ; Get address of float variable - &var.f
   ; Sets *ptr to point to field and ptrtype tag

   vm_DebugFunctionName()

   gEvalStack(sp)\i = _AR()\i
   gEvalStack(sp)\ptr = @*gVar(_AR()\i)\var(0)\f
   gEvalStack(sp)\ptrtype = #PTR_FLOAT

   sp + 1
   pc + 1
EndProcedure

Procedure               C2GETADDRS()
   ; Get address of string variable - &var.s
   ; Sets *ptr to slot index (as pointer) and ptrtype tag
   ; Note: For strings, we store slot index not memory address (managed type)

   vm_DebugFunctionName()

   gEvalStack(sp)\i = _AR()\i
   gEvalStack(sp)\ptr = _AR()\i
   gEvalStack(sp)\ptrtype = #PTR_STRING

   sp + 1
   pc + 1
EndProcedure

;- V1.027.2: Local Variable Address Operations (localBase-relative)

; V1.035.0: POINTER ARRAY ARCHITECTURE - uses *gVar(gCurrentFuncSlot)\var(offset) directly
; V1.031.34: Use PTR_LOCAL_INT to distinguish local from global pointers
; V1.035.0: POINTER ARRAY ARCHITECTURE - use *gVar(gCurrentFuncSlot)\var(offset)
Procedure               C2GETLOCALADDR()
   ; Get address of local integer variable - &localVar
   ; _AR()\i = paramOffset (local variable's offset within function)
   ; V1.035.0: Direct memory address of *gVar(gCurrentFuncSlot)\var(offset)\i

   vm_DebugFunctionName()

   Protected localOffset.i = _AR()\i

   gEvalStack(sp)\i = localOffset  ; Store offset for reference
   gEvalStack(sp)\ptr = @*gVar(gCurrentFuncSlot)\var(localOffset)\i
   gEvalStack(sp)\ptrtype = #PTR_LOCAL_INT  ; V1.031.34: Use local pointer type

   sp + 1
   pc + 1
EndProcedure

; V1.031.34: Use PTR_LOCAL_FLOAT to distinguish local from global pointers
; V1.035.0: POINTER ARRAY ARCHITECTURE - use *gVar(gCurrentFuncSlot)\var(offset)
Procedure               C2GETLOCALADDRF()
   ; Get address of local float variable - &localVar.f
   ; _AR()\i = paramOffset (local variable's offset within function)
   ; V1.035.0: Direct memory address of *gVar(gCurrentFuncSlot)\var(offset)\f

   vm_DebugFunctionName()

   Protected localOffset.i = _AR()\i

   gEvalStack(sp)\i = localOffset  ; Store offset for reference
   gEvalStack(sp)\ptr = @*gVar(gCurrentFuncSlot)\var(localOffset)\f
   gEvalStack(sp)\ptrtype = #PTR_LOCAL_FLOAT  ; V1.031.34: Use local pointer type

   sp + 1
   pc + 1
EndProcedure

; V1.031.34: Use PTR_LOCAL_STRING to distinguish local from global pointers
; V1.035.0: POINTER ARRAY ARCHITECTURE - use *gVar(gCurrentFuncSlot)\var(offset)
Procedure               C2GETLOCALADDRS()
   ; Get address of local string variable - &localVar.s
   ; _AR()\i = paramOffset (local variable's offset within function)
   ; V1.035.0: Store offset; strings are managed types, copy value for safety

   vm_DebugFunctionName()

   Protected localOffset.i = _AR()\i

   gEvalStack(sp)\i = localOffset  ; Store offset for reference
   gEvalStack(sp)\ptr = localOffset  ; For strings, ptr holds offset (managed type)
   gEvalStack(sp)\ss = *gVar(gCurrentFuncSlot)\var(localOffset)\ss  ; Copy string value for safety
   gEvalStack(sp)\ptrtype = #PTR_LOCAL_STRING  ; V1.031.34: Use local pointer type

   sp + 1
   pc + 1
EndProcedure

Procedure               C2PTRFETCH()
   ; Generic pointer fetch using type dispatch
   ; Dispatches based on ptrtype tag for optimal performance
   ; V1.19.4: Single-field population for speed, with minimal cross-population for strings
   ; V1.021.11: Handle ptrtype=0 as PTR_INT (when FETCH doesn't copy metadata)

   vm_DebugFunctionName()

   sp - 1

   Select gEvalStack(sp)\ptrtype
      Case #PTR_INT
         gEvalStack(sp)\i = PeekI(gEvalStack(sp)\ptr)

      Case #PTR_FLOAT
         gEvalStack(sp)\f = PeekD(gEvalStack(sp)\ptr)

      Case #PTR_STRING
         ; V1.19.4: Cross-populate \i with string length for assertEqual detection
         gEvalStack(sp)\ss = *gVar(gEvalStack(sp)\ptr)\var(0)\ss
         gEvalStack(sp)\i = Len(gEvalStack(sp)\ss)

      Case #PTR_ARRAY_INT
         gEvalStack(sp)\i = *gVar(gEvalStack(sp)\ptr)\var(0)\dta\ar(gEvalStack(sp)\i)\i

      Case #PTR_ARRAY_FLOAT
         gEvalStack(sp)\f = *gVar(gEvalStack(sp)\ptr)\var(0)\dta\ar(gEvalStack(sp)\i)\f

      Case #PTR_ARRAY_STRING
         ; V1.19.4: Cross-populate \i with string length for assertEqual detection
         gEvalStack(sp)\ss = *gVar(gEvalStack(sp)\ptr)\var(0)\dta\ar(gEvalStack(sp)\i)\ss
         gEvalStack(sp)\i = Len(gEvalStack(sp)\ss)

      Default
         ; V1.021.11: When ptrtype=0 (metadata not copied by FETCH), use slot-based dereference
         ; This happens when generic PTRFETCH is used instead of typed PTRFETCH_INT
         ; The \i field contains the slot index of the target variable
         gEvalStack(sp)\i = *gVar(gEvalStack(sp)\i)\var(0)\i

   EndSelect

   sp + 1
   pc + 1
EndProcedure

Procedure               C2PTRFETCH_INT()
   ; Fetch integer through pointer
   ; Top of stack contains pointer (slot index or array pointer)
   ; V1.20.24: Handle both PTR_INT and PTR_ARRAY_INT
   ; V1.031.22: Handle PTR_LOCAL_ARRAY_INT
   ; V1.031.34: Handle PTR_LOCAL_INT using PeekI on actual memory address

   vm_DebugFunctionName()

   sp - 1

   ; Check pointer type to determine fetch strategy
   If gEvalStack(sp)\ptrtype = #PTR_ARRAY_INT
      ; Global array element pointer: use ptr field for array slot, i field for index
      gEvalStack(sp)\i = *gVar(gEvalStack(sp)\ptr)\var(0)\dta\ar(gEvalStack(sp)\i)\i
   ElseIf gEvalStack(sp)\ptrtype = #PTR_LOCAL_ARRAY_INT
      ; V1.035.0: Local array element pointer: use *gVar(gCurrentFuncSlot)\var(offset)
      gEvalStack(sp)\i = *gVar(gCurrentFuncSlot)\var(gEvalStack(sp)\ptr)\dta\ar(gEvalStack(sp)\i)\i
   ElseIf gEvalStack(sp)\ptrtype = #PTR_LOCAL_INT
      ; V1.031.34: Local simple variable pointer: use PeekI on actual memory address
      gEvalStack(sp)\i = PeekI(gEvalStack(sp)\ptr)
   ElseIf gEvalStack(sp)\ptrtype = #PTR_INT
      ; V1.031.34: Global simple variable pointer: use PeekI on actual memory address
      gEvalStack(sp)\i = PeekI(gEvalStack(sp)\ptr)
   Else
      ; Fallback for unknown types: use slot-based access (legacy)
      ; Bounds check
      CompilerIf #DEBUG
         If gEvalStack(sp)\i < 0 Or gEvalStack(sp)\i >= #C2MAXCONSTANTS
            Debug "NULL or invalid pointer dereference at pc=" + Str(pc) + " slot=" + Str(gEvalStack(sp)\i)
            gExitApplication = #True
            ProcedureReturn
         EndIf
      CompilerEndIf

      gEvalStack(sp)\i = *gVar(gEvalStack(sp)\i)\var(0)\i
   EndIf

   sp + 1
   pc + 1
EndProcedure

Procedure               C2PTRFETCH_FLOAT()
   ; Fetch float through pointer
   ; Top of stack contains pointer (slot index or array pointer)
   ; V1.20.24: Handle both PTR_FLOAT and PTR_ARRAY_FLOAT
   ; V1.031.22: Handle PTR_LOCAL_ARRAY_FLOAT
   ; V1.031.34: Handle PTR_LOCAL_FLOAT using PeekD on actual memory address

   vm_DebugFunctionName()

   sp - 1

   ; Check pointer type to determine fetch strategy
   If gEvalStack(sp)\ptrtype = #PTR_ARRAY_FLOAT
      ; Global array element pointer: use ptr field for array slot, i field for index
      gEvalStack(sp)\f = *gVar(gEvalStack(sp)\ptr)\var(0)\dta\ar(gEvalStack(sp)\i)\f
   ElseIf gEvalStack(sp)\ptrtype = #PTR_LOCAL_ARRAY_FLOAT
      ; V1.031.22: Local array element pointer: use gStorage[] instead of gVar[]
      gEvalStack(sp)\f = *gVar(gCurrentFuncSlot)\var(gEvalStack(sp)\ptr)\dta\ar(gEvalStack(sp)\i)\f
   ElseIf gEvalStack(sp)\ptrtype = #PTR_LOCAL_FLOAT
      ; V1.031.34: Local simple variable pointer: use PeekD on actual memory address
      gEvalStack(sp)\f = PeekD(gEvalStack(sp)\ptr)
   ElseIf gEvalStack(sp)\ptrtype = #PTR_FLOAT
      ; V1.031.34: Global simple variable pointer: use PeekD on actual memory address
      gEvalStack(sp)\f = PeekD(gEvalStack(sp)\ptr)
   Else
      ; Fallback for unknown types: use slot-based access (legacy)
      ; Bounds check
      CompilerIf #DEBUG
         If gEvalStack(sp)\i < 0 Or gEvalStack(sp)\i >= #C2MAXCONSTANTS
            Debug "NULL or invalid pointer dereference at pc=" + Str(pc) + " slot=" + Str(gEvalStack(sp)\i)
            gExitApplication = #True
            ProcedureReturn
         EndIf
      CompilerEndIf

      gEvalStack(sp)\f = *gVar(gEvalStack(sp)\i)\var(0)\f
   EndIf

   sp + 1
   pc + 1
EndProcedure

Procedure               C2PTRFETCH_STR()
   ; Fetch string through pointer
   ; Top of stack contains pointer (slot index or array pointer)
   ; V1.20.24: Handle both PTR_STRING and PTR_ARRAY_STRING
   ; V1.031.22: Handle PTR_LOCAL_ARRAY_STRING
   ; V1.031.34: Handle PTR_LOCAL_STRING using gStorage[] or pre-copied \ss

   vm_DebugFunctionName()

   sp - 1

   ; Check pointer type to determine fetch strategy
   If gEvalStack(sp)\ptrtype = #PTR_ARRAY_STRING
      ; Global array element pointer: use ptr field for array slot, i field for index
      gEvalStack(sp)\ss = *gVar(gEvalStack(sp)\ptr)\var(0)\dta\ar(gEvalStack(sp)\i)\ss
      gEvalStack(sp)\i = Len(gEvalStack(sp)\ss)  ; Cross-populate for assertEqual
   ElseIf gEvalStack(sp)\ptrtype = #PTR_LOCAL_ARRAY_STRING
      ; V1.031.22: Local array element pointer: use gStorage[] instead of gVar[]
      gEvalStack(sp)\ss = *gVar(gCurrentFuncSlot)\var(gEvalStack(sp)\ptr)\dta\ar(gEvalStack(sp)\i)\ss
      gEvalStack(sp)\i = Len(gEvalStack(sp)\ss)  ; Cross-populate for assertEqual
   ElseIf gEvalStack(sp)\ptrtype = #PTR_LOCAL_STRING
      ; V1.031.35: Local simple string variable: fetch from gStorage[] using stored slot index
      ; V1.035.0: \i contains the paramOffset (for local variable access via gCurrentFuncSlot)
      ; Note: This is safe as long as we're still in the same function scope
      gEvalStack(sp)\ss = *gVar(gCurrentFuncSlot)\var(gEvalStack(sp)\i)\ss
      gEvalStack(sp)\i = Len(gEvalStack(sp)\ss)  ; Cross-populate for assertEqual
   ElseIf gEvalStack(sp)\ptrtype = #PTR_STRING
      ; Global simple string variable: use *gVar(slot)\var(0)
      gEvalStack(sp)\ss = *gVar(gEvalStack(sp)\i)\var(0)\ss
      gEvalStack(sp)\i = Len(gEvalStack(sp)\ss)  ; Cross-populate for assertEqual
   Else
      ; Fallback for unknown types: use slot-based access (legacy)
      ; Bounds check
      CompilerIf #DEBUG
         If gEvalStack(sp)\i < 0 Or gEvalStack(sp)\i >= #C2MAXCONSTANTS
            Debug "NULL or invalid pointer dereference at pc=" + Str(pc) + " slot=" + Str(gEvalStack(sp)\i)
            gExitApplication = #True
            ProcedureReturn
         EndIf
      CompilerEndIf

      gEvalStack(sp)\ss = *gVar(gEvalStack(sp)\i)\var(0)\ss
      gEvalStack(sp)\i = Len(gEvalStack(sp)\ss)  ; Cross-populate for assertEqual
   EndIf

   sp + 1
   pc + 1
EndProcedure

Procedure               C2PTRSTORE()
   ; Generic pointer store using type dispatch
   ; Dispatches based on ptrtype tag for optimal performance
   ; Stack: [value] [pointer]
   ; V1.031.22: Handle PTR_LOCAL_ARRAY_* types
   ; V1.031.34: Handle PTR_LOCAL_INT/FLOAT/STRING types

   vm_DebugFunctionName()

   sp - 1

   Select gEvalStack(sp)\ptrtype
      Case #PTR_INT, #PTR_LOCAL_INT  ; V1.031.34: Both use PokeI on \ptr
         sp - 1
         PokeI(gEvalStack(sp + 1)\ptr, gEvalStack(sp)\i)

      Case #PTR_FLOAT, #PTR_LOCAL_FLOAT  ; V1.031.34: Both use PokeD on \ptr
         sp - 1
         PokeD(gEvalStack(sp + 1)\ptr, gEvalStack(sp)\f)

      Case #PTR_STRING
         sp - 1
         *gVar(gEvalStack(sp + 1)\ptr)\var(0)\ss = gEvalStack(sp)\ss

      Case #PTR_LOCAL_STRING  ; V1.031.34: Local string pointer stores to gStorage[]
         sp - 1
         *gVar(gCurrentFuncSlot)\var(gEvalStack(sp + 1)\i)\ss = gEvalStack(sp)\ss

      Case #PTR_ARRAY_INT
         sp - 1
         *gVar(gEvalStack(sp + 1)\ptr)\var(0)\dta\ar(gEvalStack(sp + 1)\i)\i = gEvalStack(sp)\i

      Case #PTR_ARRAY_FLOAT
         sp - 1
         *gVar(gEvalStack(sp + 1)\ptr)\var(0)\dta\ar(gEvalStack(sp + 1)\i)\f = gEvalStack(sp)\f

      Case #PTR_ARRAY_STRING
         sp - 1
         *gVar(gEvalStack(sp + 1)\ptr)\var(0)\dta\ar(gEvalStack(sp + 1)\i)\ss = gEvalStack(sp)\ss

      ; V1.031.22: Local array pointer types
      Case #PTR_LOCAL_ARRAY_INT
         sp - 1
         *gVar(gCurrentFuncSlot)\var(gEvalStack(sp + 1)\ptr)\dta\ar(gEvalStack(sp + 1)\i)\i = gEvalStack(sp)\i

      Case #PTR_LOCAL_ARRAY_FLOAT
         sp - 1
         *gVar(gCurrentFuncSlot)\var(gEvalStack(sp + 1)\ptr)\dta\ar(gEvalStack(sp + 1)\i)\f = gEvalStack(sp)\f

      Case #PTR_LOCAL_ARRAY_STRING
         sp - 1
         *gVar(gCurrentFuncSlot)\var(gEvalStack(sp + 1)\ptr)\dta\ar(gEvalStack(sp + 1)\i)\ss = gEvalStack(sp)\ss

      Default
         CompilerIf #DEBUG
            Debug "Invalid pointer type in PTRSTORE: " + Str(gEvalStack(sp)\ptrtype) + " at pc=" + Str(pc)
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
   ; V1.031.22: Handle PTR_LOCAL_ARRAY_INT
   ; V1.031.34: Handle PTR_LOCAL_INT using PokeI on actual memory address

   vm_DebugFunctionName()

   sp - 1

   ; Check pointer type to determine store strategy
   If gEvalStack(sp)\ptrtype = #PTR_ARRAY_INT
      ; Global array element pointer: use ptr field for array slot, i field for index
      sp - 1
      *gVar(gEvalStack(sp + 1)\ptr)\var(0)\dta\ar(gEvalStack(sp + 1)\i)\i = gEvalStack(sp)\i
   ElseIf gEvalStack(sp)\ptrtype = #PTR_LOCAL_ARRAY_INT
      ; V1.031.22: Local array element pointer: use gStorage[] instead of gVar[]
      sp - 1
      *gVar(gCurrentFuncSlot)\var(gEvalStack(sp + 1)\ptr)\dta\ar(gEvalStack(sp + 1)\i)\i = gEvalStack(sp)\i
   ElseIf gEvalStack(sp)\ptrtype = #PTR_LOCAL_INT Or gEvalStack(sp)\ptrtype = #PTR_INT
      ; V1.031.34: Simple variable pointer: use PokeI on actual memory address
      sp - 1
      PokeI(gEvalStack(sp + 1)\ptr, gEvalStack(sp)\i)
   Else
      ; Fallback for unknown types: use slot-based access (legacy)
      ; Bounds check
      CompilerIf #DEBUG
         If gEvalStack(sp)\i < 0 Or gEvalStack(sp)\i >= #C2MAXCONSTANTS
            Debug "NULL or invalid pointer dereference at pc=" + Str(pc) + " slot=" + Str(gEvalStack(sp)\i)
            gExitApplication = #True
            ProcedureReturn
         EndIf
      CompilerEndIf

      sp - 1
      *gVar(gEvalStack(sp + 1)\i)\var(0)\i = gEvalStack(sp)\i
   EndIf

   pc + 1
EndProcedure

Procedure               C2PTRSTORE_FLOAT()
   ; Store float through pointer
   ; Stack: [value] [pointer]
   ; V1.20.24: Handle both PTR_FLOAT and PTR_ARRAY_FLOAT
   ; V1.031.22: Handle PTR_LOCAL_ARRAY_FLOAT
   ; V1.031.34: Handle PTR_LOCAL_FLOAT using PokeD on actual memory address

   vm_DebugFunctionName()

   sp - 1

   ; Check pointer type to determine store strategy
   If gEvalStack(sp)\ptrtype = #PTR_ARRAY_FLOAT
      ; Global array element pointer: use ptr field for array slot, i field for index
      sp - 1
      *gVar(gEvalStack(sp + 1)\ptr)\var(0)\dta\ar(gEvalStack(sp + 1)\i)\f = gEvalStack(sp)\f
   ElseIf gEvalStack(sp)\ptrtype = #PTR_LOCAL_ARRAY_FLOAT
      ; V1.031.22: Local array element pointer: use gStorage[] instead of gVar[]
      sp - 1
      *gVar(gCurrentFuncSlot)\var(gEvalStack(sp + 1)\ptr)\dta\ar(gEvalStack(sp + 1)\i)\f = gEvalStack(sp)\f
   ElseIf gEvalStack(sp)\ptrtype = #PTR_LOCAL_FLOAT Or gEvalStack(sp)\ptrtype = #PTR_FLOAT
      ; V1.031.34: Simple variable pointer: use PokeD on actual memory address
      sp - 1
      PokeD(gEvalStack(sp + 1)\ptr, gEvalStack(sp)\f)
   Else
      ; Fallback for unknown types: use slot-based access (legacy)
      ; Bounds check
      CompilerIf #DEBUG
         If gEvalStack(sp)\i < 0 Or gEvalStack(sp)\i >= #C2MAXCONSTANTS
            Debug "NULL or invalid pointer dereference at pc=" + Str(pc) + " slot=" + Str(gEvalStack(sp)\i)
            gExitApplication = #True
            ProcedureReturn
         EndIf
      CompilerEndIf

      sp - 1
      *gVar(gEvalStack(sp + 1)\i)\var(0)\f = gEvalStack(sp)\f
   EndIf

   pc + 1
EndProcedure

Procedure               C2PTRSTORE_STR()
   ; Store string through pointer
   ; Stack: [value] [pointer]
   ; V1.20.24: Handle both PTR_STRING and PTR_ARRAY_STRING
   ; V1.031.22: Handle PTR_LOCAL_ARRAY_STRING
   ; V1.031.34: Handle PTR_LOCAL_STRING using gStorage[]

   vm_DebugFunctionName()

   sp - 1

   ; Check pointer type to determine store strategy
   If gEvalStack(sp)\ptrtype = #PTR_ARRAY_STRING
      ; Global array element pointer: use ptr field for array slot, i field for index
      sp - 1
      *gVar(gEvalStack(sp + 1)\ptr)\var(0)\dta\ar(gEvalStack(sp + 1)\i)\ss = gEvalStack(sp)\ss
   ElseIf gEvalStack(sp)\ptrtype = #PTR_LOCAL_ARRAY_STRING
      ; V1.031.22: Local array element pointer: use gStorage[] instead of gVar[]
      sp - 1
      *gVar(gCurrentFuncSlot)\var(gEvalStack(sp + 1)\ptr)\dta\ar(gEvalStack(sp + 1)\i)\ss = gEvalStack(sp)\ss
   ElseIf gEvalStack(sp)\ptrtype = #PTR_LOCAL_STRING
      ; V1.031.34: Local simple string variable: use gStorage[]
      sp - 1
      *gVar(gCurrentFuncSlot)\var(gEvalStack(sp + 1)\i)\ss = gEvalStack(sp)\ss
   ElseIf gEvalStack(sp)\ptrtype = #PTR_STRING
      ; Global simple string variable: use *gVar(slot)\var(0)
      sp - 1
      *gVar(gEvalStack(sp + 1)\i)\var(0)\ss = gEvalStack(sp)\ss
   Else
      ; Fallback for unknown types: use slot-based access (legacy)
      ; Bounds check
      CompilerIf #DEBUG
         If gEvalStack(sp)\i < 0 Or gEvalStack(sp)\i >= #C2MAXCONSTANTS
            Debug "NULL or invalid pointer dereference at pc=" + Str(pc) + " slot=" + Str(gEvalStack(sp)\i)
            gExitApplication = #True
            ProcedureReturn
         EndIf
      CompilerEndIf

      sp - 1
      *gVar(gEvalStack(sp + 1)\i)\var(0)\ss = gEvalStack(sp)\ss
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
   offset = gEvalStack(sp)\i
   ptrType = gEvalStack(sp - 1)\ptrtype

   ; Update element index for all pointer types
   gEvalStack(sp - 1)\i + offset

   ; Update memory address for variable pointers (not array pointers)
   Select ptrType
      Case #PTR_INT
         gEvalStack(sp - 1)\ptr + (offset * 8)
      Case #PTR_FLOAT
         gEvalStack(sp - 1)\ptr + (offset * 8)
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
   offset = gEvalStack(sp)\i
   ptrType = gEvalStack(sp - 1)\ptrtype

   ; Update element index for all pointer types
   gEvalStack(sp - 1)\i - offset

   ; Update memory address for variable pointers (not array pointers)
   Select ptrType
      Case #PTR_INT
         gEvalStack(sp - 1)\ptr - (offset * 8)
      Case #PTR_FLOAT
         gEvalStack(sp - 1)\ptr - (offset * 8)
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
   ptrType = *gVar(varSlot)\var(0)\ptrtype

   Select ptrType
      Case #PTR_ARRAY_INT, #PTR_ARRAY_FLOAT, #PTR_ARRAY_STRING, #PTR_LOCAL_ARRAY_INT, #PTR_LOCAL_ARRAY_FLOAT, #PTR_LOCAL_ARRAY_STRING
         ; Array pointer (global or local): increment element index
         *gVar(varSlot)\var(0)\i + 1

      Case #PTR_INT
         ; Integer pointer: increment memory address by 8 bytes (sizeof Integer)
         *gVar(varSlot)\var(0)\i + 1
         *gVar(varSlot)\var(0)\ptr + 8

      Case #PTR_FLOAT
         ; Float pointer: increment memory address by 8 bytes (sizeof Double)
         *gVar(varSlot)\var(0)\i + 1
         *gVar(varSlot)\var(0)\ptr + 8

      Case #PTR_STRING
         ; String pointer: increment slot index by 1
         *gVar(varSlot)\var(0)\i + 1

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
   ptrType = *gVar(varSlot)\var(0)\ptrtype

   Select ptrType
      Case #PTR_ARRAY_INT, #PTR_ARRAY_FLOAT, #PTR_ARRAY_STRING, #PTR_LOCAL_ARRAY_INT, #PTR_LOCAL_ARRAY_FLOAT, #PTR_LOCAL_ARRAY_STRING
         ; Array pointer (global or local): decrement element index
         *gVar(varSlot)\var(0)\i - 1

      Case #PTR_INT
         ; Integer pointer: decrement memory address by 8 bytes
         *gVar(varSlot)\var(0)\i - 1
         *gVar(varSlot)\var(0)\ptr - 8

      Case #PTR_FLOAT
         ; Float pointer: decrement memory address by 8 bytes
         *gVar(varSlot)\var(0)\i - 1
         *gVar(varSlot)\var(0)\ptr - 8

      Case #PTR_STRING
         ; String pointer: decrement slot index by 1
         *gVar(varSlot)\var(0)\i - 1

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
   ptrType = *gVar(varSlot)\var(0)\ptrtype

   ; Increment pointer
   Select ptrType
      Case #PTR_ARRAY_INT, #PTR_ARRAY_FLOAT, #PTR_ARRAY_STRING, #PTR_LOCAL_ARRAY_INT, #PTR_LOCAL_ARRAY_FLOAT, #PTR_LOCAL_ARRAY_STRING
         *gVar(varSlot)\var(0)\i + 1
      Case #PTR_INT
         *gVar(varSlot)\var(0)\i + 1
         *gVar(varSlot)\var(0)\ptr + 8
      Case #PTR_FLOAT
         *gVar(varSlot)\var(0)\i + 1
         *gVar(varSlot)\var(0)\ptr + 8
      Case #PTR_STRING
         *gVar(varSlot)\var(0)\i + 1
   EndSelect

   ; Push new pointer value to stack
   gEvalStack(sp)\i = *gVar(varSlot)\var(0)\i
   gEvalStack(sp)\ptr = *gVar(varSlot)\var(0)\ptr
   gEvalStack(sp)\ptrtype = ptrType
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
   ptrType = *gVar(varSlot)\var(0)\ptrtype

   ; Decrement pointer
   Select ptrType
      Case #PTR_ARRAY_INT, #PTR_ARRAY_FLOAT, #PTR_ARRAY_STRING, #PTR_LOCAL_ARRAY_INT, #PTR_LOCAL_ARRAY_FLOAT, #PTR_LOCAL_ARRAY_STRING
         *gVar(varSlot)\var(0)\i - 1
      Case #PTR_INT
         *gVar(varSlot)\var(0)\i - 1
         *gVar(varSlot)\var(0)\ptr - 8
      Case #PTR_FLOAT
         *gVar(varSlot)\var(0)\i - 1
         *gVar(varSlot)\var(0)\ptr - 8
      Case #PTR_STRING
         *gVar(varSlot)\var(0)\i - 1
   EndSelect

   ; Push new pointer value to stack
   gEvalStack(sp)\i = *gVar(varSlot)\var(0)\i
   gEvalStack(sp)\ptr = *gVar(varSlot)\var(0)\ptr
   gEvalStack(sp)\ptrtype = ptrType
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
   ptrType = *gVar(varSlot)\var(0)\ptrtype

   ; Push old pointer value to stack
   gEvalStack(sp)\i = *gVar(varSlot)\var(0)\i
   gEvalStack(sp)\ptr = *gVar(varSlot)\var(0)\ptr
   gEvalStack(sp)\ptrtype = ptrType
   sp + 1

   ; Increment pointer
   Select ptrType
      Case #PTR_ARRAY_INT, #PTR_ARRAY_FLOAT, #PTR_ARRAY_STRING, #PTR_LOCAL_ARRAY_INT, #PTR_LOCAL_ARRAY_FLOAT, #PTR_LOCAL_ARRAY_STRING
         *gVar(varSlot)\var(0)\i + 1
      Case #PTR_INT
         *gVar(varSlot)\var(0)\i + 1
         *gVar(varSlot)\var(0)\ptr + 8
      Case #PTR_FLOAT
         *gVar(varSlot)\var(0)\i + 1
         *gVar(varSlot)\var(0)\ptr + 8
      Case #PTR_STRING
         *gVar(varSlot)\var(0)\i + 1
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
   ptrType = *gVar(varSlot)\var(0)\ptrtype

   ; Push old pointer value to stack
   gEvalStack(sp)\i = *gVar(varSlot)\var(0)\i
   gEvalStack(sp)\ptr = *gVar(varSlot)\var(0)\ptr
   gEvalStack(sp)\ptrtype = ptrType
   sp + 1

   ; Decrement pointer
   Select ptrType
      Case #PTR_ARRAY_INT, #PTR_ARRAY_FLOAT, #PTR_ARRAY_STRING, #PTR_LOCAL_ARRAY_INT, #PTR_LOCAL_ARRAY_FLOAT, #PTR_LOCAL_ARRAY_STRING
         *gVar(varSlot)\var(0)\i - 1
      Case #PTR_INT
         *gVar(varSlot)\var(0)\i - 1
         *gVar(varSlot)\var(0)\ptr - 8
      Case #PTR_FLOAT
         *gVar(varSlot)\var(0)\i - 1
         *gVar(varSlot)\var(0)\ptr - 8
      Case #PTR_STRING
         *gVar(varSlot)\var(0)\i - 1
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
   ptrType = *gVar(varSlot)\var(0)\ptrtype

   ; Pop offset from stack
   sp - 1
   offset = gEvalStack(sp)\i

   ; Add offset to pointer based on type
   Select ptrType
      Case #PTR_ARRAY_INT, #PTR_ARRAY_FLOAT, #PTR_ARRAY_STRING, #PTR_LOCAL_ARRAY_INT, #PTR_LOCAL_ARRAY_FLOAT, #PTR_LOCAL_ARRAY_STRING
         ; Array pointer (global or local): add to element index
         *gVar(varSlot)\var(0)\i + offset

      Case #PTR_INT
         ; Integer pointer: add offset * 8 to memory address
         *gVar(varSlot)\var(0)\i + offset
         *gVar(varSlot)\var(0)\ptr + (offset * 8)

      Case #PTR_FLOAT
         ; Float pointer: add offset * 8 to memory address
         *gVar(varSlot)\var(0)\i + offset
         *gVar(varSlot)\var(0)\ptr + (offset * 8)

      Case #PTR_STRING
         ; String pointer: add to slot index
         *gVar(varSlot)\var(0)\i + offset

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
   ptrType = *gVar(varSlot)\var(0)\ptrtype

   ; Pop offset from stack
   sp - 1
   offset = gEvalStack(sp)\i

   ; Subtract offset from pointer based on type
   Select ptrType
      Case #PTR_ARRAY_INT, #PTR_ARRAY_FLOAT, #PTR_ARRAY_STRING, #PTR_LOCAL_ARRAY_INT, #PTR_LOCAL_ARRAY_FLOAT, #PTR_LOCAL_ARRAY_STRING
         ; Array pointer (global or local): subtract from element index
         *gVar(varSlot)\var(0)\i - offset

      Case #PTR_INT
         ; Integer pointer: subtract offset * 8 from memory address
         *gVar(varSlot)\var(0)\i - offset
         *gVar(varSlot)\var(0)\ptr - (offset * 8)

      Case #PTR_FLOAT
         ; Float pointer: subtract offset * 8 from memory address
         *gVar(varSlot)\var(0)\i - offset
         *gVar(varSlot)\var(0)\ptr - (offset * 8)

      Case #PTR_STRING
         ; String pointer: subtract from slot index
         *gVar(varSlot)\var(0)\i - offset

   EndSelect

   pc + 1
EndProcedure

Procedure               C2GETFUNCADDR()
   ; Get function PC address - &function
   ; _AR()\i = function PC address (from gFuncMeta)
   ; Pushes function PC address to stack

   vm_DebugFunctionName()

   gEvalStack(sp)\i = _AR()\i
   gEvalStack(sp)\ptrtype = #PTR_FUNCTION
   sp + 1
   pc + 1
EndProcedure

Procedure               C2CALLFUNCPTR()
   ; V1.035.0: POINTER ARRAY ARCHITECTURE - TODO
   ; Function pointer calls need runtime funcSlot lookup (PC -> funcSlot mapping)
   ; This is currently NOT IMPLEMENTED - will print warning and continue
   ;
   ; For proper implementation, we need either:
   ; 1. Store funcSlot alongside PC in the pointer (requires modifying GETFUNCADDR)
   ; 2. Create a PC-to-funcSlot lookup table during code generation
   ;
   ; _AR()\j = parameter count
   ; _AR()\n = local variable count
   ; _AR()\ndx = local array count
   ; Top of stack contains function PC address (before parameters)
   ; Stack layout: [param1] [param2] ... [paramN] [funcPtr]

   Protected      nParams.l, nLocals.l, totalVars.l, nLocalArrays.l
   Protected      i.l, funcPc.l, funcSlot.l, funcId.l
   Protected      *newFrame.stVar
   vm_DebugFunctionName()

   ; Read parameters from instruction
   nParams = _AR()\j
   nLocals = _AR()\n
   nLocalArrays = _AR()\ndx
   totalVars = nParams + nLocals

   ; Get function PC from stack (it's AFTER the parameters)
   funcPc = gEvalStack(sp - 1)\i
   sp - 1  ; Pop function pointer

   ; Bounds check on function PC
   CompilerIf #DEBUG
      If funcPc < 0 Or funcPc >= ArraySize(arCode())
         Debug "Invalid function pointer at pc=" + Str(pc) + " funcPc=" + Str(funcPc)
         gExitApplication = #True
         ProcedureReturn
      EndIf
   CompilerEndIf

   ; V1.035.0: Look up funcSlot from PC
   ; Scan gFuncTemplates to find which function this PC belongs to
   funcSlot = -1
   For funcId = 0 To gnFuncTemplateCount - 1
      If gFuncTemplates(funcId)\funcSlot >= 0
         ; Check if PC matches (would need to store startPC in template - approximate for now)
         funcSlot = gFuncTemplates(funcId)\funcSlot
         ; TODO: Proper PC matching - for now use last matched as fallback
      EndIf
   Next

   ; If we couldn't find funcSlot, report error
   If funcSlot < 0
      Debug "*** ERROR: CALLFUNCPTR cannot determine funcSlot for pc=" + Str(funcPc) + " - using slot 0 as fallback"
      funcSlot = gnGlobalVariables  ; First function slot as fallback
   EndIf

   ; Create stack frame
   gStackDepth = gStackDepth + 1

   CompilerIf #DEBUG
      If gStackDepth >= gFunctionStack
         Debug "*** FATAL ERROR: Stack overflow in function pointer call at pc=" + Str(pc)
         gExitApplication = #True
         ProcedureReturn
      EndIf
   CompilerEndIf

   ; Save stack frame info
   gStack(gStackDepth)\pc = pc + 1
   gStack(gStackDepth)\sp = sp - nParams
   gStack(gStackDepth)\funcSlot = funcSlot
   gStack(gStackDepth)\localCount = totalVars

   ; V1.035.0: Check if function slot is already active (recursion)
   If gFuncActive(funcSlot)
      ; Recursion: allocate new frame and swap pointer
      *newFrame = AllocateStructure(stVar)
      ReDim *newFrame\var(totalVars - 1)
      gStack(gStackDepth)\savedFrame = *gVar(funcSlot)
      gStack(gStackDepth)\isAllocated = #True
      *gVar(funcSlot) = *newFrame
   Else
      ; First call: allocate/resize existing slot
      If Not *gVar(funcSlot)
         *gVar(funcSlot) = AllocateStructure(stVar)
      EndIf
      ReDim *gVar(funcSlot)\var(totalVars - 1)
      gStack(gStackDepth)\savedFrame = #Null
      gStack(gStackDepth)\isAllocated = #False
      gFuncActive(funcSlot) = #True
   EndIf

   ; Copy parameters from eval stack to function locals (reverse order)
   For i = 0 To nParams - 1
      CopyStructure(gEvalStack(sp - 1 - i), *gVar(funcSlot)\var(i), stVTSimple)
   Next

   ; Pop parameters from evaluation stack
   sp = sp - nParams

   ; Note: Local arrays not supported in function pointer calls (would need function metadata)
   If nLocalArrays > 0
      Debug "*** WARNING: Function pointer calls do not support local arrays at pc=" + Str(pc)
   EndIf

   ; Set current function slot for local variable access
   gCurrentFuncSlot = funcSlot

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
   elementIndex = gEvalStack(sp)\i

   ; Bounds check
   CompilerIf #DEBUG
      If elementIndex < 0 Or elementIndex >= *gVar(arraySlot)\var(0)\dta\size
         Debug "Array index out of bounds in GETARRAYADDR: " + Str(elementIndex) + " (size: " + Str(*gVar(arraySlot)\var(0)\dta\size) + ") at pc=" + Str(pc)
         gExitApplication = #True
         ProcedureReturn
      EndIf
   CompilerEndIf

   ; Set up pointer structure
   gEvalStack(sp)\ptr = arraySlot  ; Store array slot as pointer value
   gEvalStack(sp)\i = elementIndex ; Store current element index
   gEvalStack(sp)\ptrtype = #PTR_ARRAY_INT

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
   elementIndex = gEvalStack(sp)\i

   ; Bounds check
   CompilerIf #DEBUG
      If elementIndex < 0 Or elementIndex >= *gVar(arraySlot)\var(0)\dta\size
         Debug "Array index out of bounds in GETARRAYADDRF: " + Str(elementIndex) + " (size: " + Str(*gVar(arraySlot)\var(0)\dta\size) + ") at pc=" + Str(pc)
         gExitApplication = #True
         ProcedureReturn
      EndIf
   CompilerEndIf

   ; Set up pointer structure
   gEvalStack(sp)\ptr = arraySlot  ; Store array slot as pointer value
   gEvalStack(sp)\i = elementIndex ; Store current element index
   gEvalStack(sp)\ptrtype = #PTR_ARRAY_FLOAT

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
   elementIndex = gEvalStack(sp)\i

   ; Bounds check
   CompilerIf #DEBUG
      If elementIndex < 0 Or elementIndex >= *gVar(arraySlot)\var(0)\dta\size
         Debug "Array index out of bounds in GETARRAYADDRS: " + Str(elementIndex) + " (size: " + Str(*gVar(arraySlot)\var(0)\dta\size) + ") at pc=" + Str(pc)
         gExitApplication = #True
         ProcedureReturn
      EndIf
   CompilerEndIf

   ; Set up pointer structure
   gEvalStack(sp)\ptr = arraySlot  ; Store array slot as pointer value
   gEvalStack(sp)\i = elementIndex ; Store current element index
   gEvalStack(sp)\ptrtype = #PTR_ARRAY_STRING

   sp + 1
   pc + 1
EndProcedure

;- End Array Pointer Operations

;- V1.027.2: Local Array Pointer GETADDR Operations (localBase-relative)

; V1.035.0: POINTER ARRAY ARCHITECTURE - uses *gVar(gCurrentFuncSlot)\var(offset) directly
Procedure               C2GETLOCALARRAYADDR()
   ; Get address of local integer array element - &localArr[i]
   ; _AR()\i = array paramOffset (offset from localBase)
   ; Stack top = element index
   ; V1.035.0: arraySlot = paramOffset (index into *gVar(gCurrentFuncSlot)\var())
   ; V1.031.22: Fixed to use gStorage[] and PTR_LOCAL_ARRAY_INT

   Protected arraySlot.i, elementIndex.i

   vm_DebugFunctionName()

   arraySlot = _AR()\i

   ; Pop index from stack
   sp - 1
   elementIndex = gEvalStack(sp)\i

   ; Bounds check - V1.031.22: Use gStorage[] not gVar[]
   CompilerIf #DEBUG
      If elementIndex < 0 Or elementIndex >= *gVar(gCurrentFuncSlot)\var(arraySlot)\dta\size
         Debug "Array index out of bounds in GETLOCALARRAYADDR: " + Str(elementIndex) + " (size: " + Str(*gVar(gCurrentFuncSlot)\var(arraySlot)\dta\size) + ") at pc=" + Str(pc)
         gExitApplication = #True
         ProcedureReturn
      EndIf
   CompilerEndIf

   ; Set up pointer structure
   gEvalStack(sp)\ptr = arraySlot  ; Store actual array slot as pointer value (into gStorage[])
   gEvalStack(sp)\i = elementIndex ; Store current element index
   gEvalStack(sp)\ptrtype = #PTR_LOCAL_ARRAY_INT  ; V1.031.22: Use LOCAL type

   sp + 1
   pc + 1
EndProcedure

; V1.035.0: POINTER ARRAY ARCHITECTURE - uses *gVar(gCurrentFuncSlot)\var(offset) directly
Procedure               C2GETLOCALARRAYADDRF()
   ; Get address of local float array element - &localArr.f[i]
   ; _AR()\i = array paramOffset (offset from localBase)
   ; Stack top = element index
   ; V1.035.0: arraySlot = paramOffset (index into *gVar(gCurrentFuncSlot)\var())
   ; V1.031.22: Fixed to use gStorage[] and PTR_LOCAL_ARRAY_FLOAT

   Protected arraySlot.i, elementIndex.i

   vm_DebugFunctionName()

   arraySlot = _AR()\i

   ; Pop index from stack
   sp - 1
   elementIndex = gEvalStack(sp)\i

   ; Bounds check - V1.031.22: Use gStorage[] not gVar[]
   CompilerIf #DEBUG
      If elementIndex < 0 Or elementIndex >= *gVar(gCurrentFuncSlot)\var(arraySlot)\dta\size
         Debug "Array index out of bounds in GETLOCALARRAYADDRF: " + Str(elementIndex) + " (size: " + Str(*gVar(gCurrentFuncSlot)\var(arraySlot)\dta\size) + ") at pc=" + Str(pc)
         gExitApplication = #True
         ProcedureReturn
      EndIf
   CompilerEndIf

   ; Set up pointer structure
   gEvalStack(sp)\ptr = arraySlot  ; Store actual array slot as pointer value (into gStorage[])
   gEvalStack(sp)\i = elementIndex ; Store current element index
   gEvalStack(sp)\ptrtype = #PTR_LOCAL_ARRAY_FLOAT  ; V1.031.22: Use LOCAL type

   sp + 1
   pc + 1
EndProcedure

; V1.035.0: POINTER ARRAY ARCHITECTURE - uses *gVar(gCurrentFuncSlot)\var(offset) directly
Procedure               C2GETLOCALARRAYADDRS()
   ; Get address of local string array element - &localArr.s[i]
   ; _AR()\i = array paramOffset (offset from localBase)
   ; Stack top = element index
   ; V1.035.0: arraySlot = paramOffset (index into *gVar(gCurrentFuncSlot)\var())
   ; V1.031.22: Fixed to use gStorage[] and PTR_LOCAL_ARRAY_STRING

   Protected arraySlot.i, elementIndex.i

   vm_DebugFunctionName()

   arraySlot = _AR()\i

   ; Pop index from stack
   sp - 1
   elementIndex = gEvalStack(sp)\i

   ; Bounds check - V1.031.22: Use gStorage[] not gVar[]
   CompilerIf #DEBUG
      If elementIndex < 0 Or elementIndex >= *gVar(gCurrentFuncSlot)\var(arraySlot)\dta\size
         Debug "Array index out of bounds in GETLOCALARRAYADDRS: " + Str(elementIndex) + " (size: " + Str(*gVar(gCurrentFuncSlot)\var(arraySlot)\dta\size) + ") at pc=" + Str(pc)
         gExitApplication = #True
         ProcedureReturn
      EndIf
   CompilerEndIf

   ; Set up pointer structure
   gEvalStack(sp)\ptr = arraySlot  ; Store actual array slot as pointer value (into gStorage[])
   gEvalStack(sp)\i = elementIndex ; Store current element index
   gEvalStack(sp)\ptrtype = #PTR_LOCAL_ARRAY_STRING  ; V1.031.22: Use LOCAL type

   sp + 1
   pc + 1
EndProcedure

;- End Local Array Pointer Operations

;- Pointer-Only Opcodes (V1.020.027)
; These opcodes are emitted ONLY for pointer variables
; They ALWAYS copy pointer metadata - no conditional checks needed
; This keeps general opcodes (MOV, FETCH, STORE, etc.) clean and fast

Procedure               C2PMOV()
   ; V1.034.32: Unified PMOV using n field for locality encoding
   ; n=0: GG (both global), n=1: LG (local src, global dst), n=2: GL (global src, local dst), n=3: LL (both local)
   ; i = destination slot/paramOffset, j = source slot/paramOffset
   vm_DebugFunctionName()

   Select _AR()\n
      Case 0 ; GG: both global
         *gVar( _AR()\i )\var(0)\i = *gVar( _AR()\j )\var(0)\i
         *gVar( _AR()\i )\var(0)\ptr = *gVar( _AR()\j )\var(0)\ptr
         *gVar( _AR()\i )\var(0)\ptrtype = *gVar( _AR()\j )\var(0)\ptrtype
      Case 1 ; LG: local source -> global dest
         *gVar( _AR()\i )\var(0)\i = *gVar(gCurrentFuncSlot)\var(_AR()\j)\i
         *gVar( _AR()\i )\var(0)\ptr = *gVar(gCurrentFuncSlot)\var(_AR()\j)\ptr
         *gVar( _AR()\i )\var(0)\ptrtype = *gVar(gCurrentFuncSlot)\var(_AR()\j)\ptrtype
      Case 2 ; GL: global source -> local dest
         *gVar(gCurrentFuncSlot)\var(_AR()\i)\i = *gVar( _AR()\j )\var(0)\i
         *gVar(gCurrentFuncSlot)\var(_AR()\i)\ptr = *gVar( _AR()\j )\var(0)\ptr
         *gVar(gCurrentFuncSlot)\var(_AR()\i)\ptrtype = *gVar( _AR()\j )\var(0)\ptrtype
      Case 3 ; LL: both local
         *gVar(gCurrentFuncSlot)\var(_AR()\i)\i = *gVar(gCurrentFuncSlot)\var(_AR()\j)\i
         *gVar(gCurrentFuncSlot)\var(_AR()\i)\ptr = *gVar(gCurrentFuncSlot)\var(_AR()\j)\ptr
         *gVar(gCurrentFuncSlot)\var(_AR()\i)\ptrtype = *gVar(gCurrentFuncSlot)\var(_AR()\j)\ptrtype
   EndSelect

   pc + 1
EndProcedure

Procedure               C2PFETCH()
   ; V1.034.24: Unified pointer FETCH using _SLOT (j=1 for local, j=0 for global)
   vm_DebugFunctionName()

   gEvalStack(sp)\i = _SLOT(_AR()\j, _AR()\i)\i
   gEvalStack(sp)\ptr = _SLOT(_AR()\j, _AR()\i)\ptr
   gEvalStack(sp)\ptrtype = _SLOT(_AR()\j, _AR()\i)\ptrtype

   sp + 1
   pc + 1
EndProcedure

Procedure               C2PSTORE()
   ; V1.034.24: Unified pointer STORE using _SLOT (j=1 for local, j=0 for global)
   vm_DebugFunctionName()
   sp - 1

   _SLOT(_AR()\j, _AR()\i)\i = gEvalStack(sp)\i
   _SLOT(_AR()\j, _AR()\i)\ptr = gEvalStack(sp)\ptr
   _SLOT(_AR()\j, _AR()\i)\ptrtype = gEvalStack(sp)\ptrtype

   pc + 1
EndProcedure

Procedure               C2PPOP()
   ; V1.034.24: Unified pointer POP using _SLOT (j=1 for local, j=0 for global)
   vm_DebugFunctionName()
   sp - 1

   _SLOT(_AR()\j, _AR()\i)\i = gEvalStack(sp)\i
   _SLOT(_AR()\j, _AR()\i)\ptr = gEvalStack(sp)\ptr
   _SLOT(_AR()\j, _AR()\i)\ptrtype = gEvalStack(sp)\ptrtype

   pc + 1
EndProcedure

Procedure               C2PLFETCH()
   ; V1.31.0: Pointer-only local FETCH - gStorage[] to gStorage[]
   vm_DebugFunctionName()

   gEvalStack(sp)\i = *gVar(gCurrentFuncSlot)\var(_AR()\i)\i
   gEvalStack(sp)\ptr = *gVar(gCurrentFuncSlot)\var(_AR()\i)\ptr
   gEvalStack(sp)\ptrtype = *gVar(gCurrentFuncSlot)\var(_AR()\i)\ptrtype

   sp + 1
   pc + 1
EndProcedure

Procedure               C2PLSTORE()
   ; V1.31.0: Pointer-only local STORE - gStorage[] to gStorage[]
   vm_DebugFunctionName()
   sp - 1

   *gVar(gCurrentFuncSlot)\var(_AR()\i)\i = gEvalStack(sp)\i
   *gVar(gCurrentFuncSlot)\var(_AR()\i)\ptr = gEvalStack(sp)\ptr
   *gVar(gCurrentFuncSlot)\var(_AR()\i)\ptrtype = gEvalStack(sp)\ptrtype

   pc + 1
EndProcedure

Procedure               C2PLMOV()
   ; V1.31.0: Pointer-only local MOV (GL) - *gVar(global)\var(0) to *gVar(func)\var(local)
   vm_DebugFunctionName()

   *gVar(gCurrentFuncSlot)\var(_AR()\i)\i = *gVar( _AR()\j )\var(0)\i
   *gVar(gCurrentFuncSlot)\var(_AR()\i)\ptr = *gVar( _AR()\j )\var(0)\ptr
   *gVar(gCurrentFuncSlot)\var(_AR()\i)\ptrtype = *gVar( _AR()\j )\var(0)\ptrtype

   pc + 1
EndProcedure

;- End Pointer-Only Opcodes

;- V1.022.54: Struct Pointer Operations

Procedure               C2GETSTRUCTADDR()
   ; Get address of struct variable: ptr = &structVar
   ; _AR()\i = base slot of struct variable
   ; Push struct base slot as pointer with #PTR_STRUCT type
   vm_DebugFunctionName()

   gEvalStack(sp)\ptr = _AR()\i       ; Store base slot (not memory address)
   gEvalStack(sp)\ptrtype = #PTR_STRUCT
   gEvalStack(sp)\i = _AR()\i         ; Also store in i field (ptr and i are separate fields)
   sp + 1
   pc + 1
EndProcedure

Procedure               C2PTRSTRUCTFETCH_INT()
   ; Read int field through struct pointer: value = ptr\field
   ; V1.029.59: Updated for \ptr storage - read from struct memory, not gVar slots
   ; _AR()\i = pointer slot, _AR()\n = field offset (in slots, converted to bytes)
   vm_DebugFunctionName()
   Protected baseSlot.i, *structPtr, byteOffset.i

   ; V1.033.37: Handle local pointer slots (negative = local offset encoded as -(offset+2))
   If _AR()\i < -1
      baseSlot = _LVAR(-(_AR()\i + 2))\ptr
   Else
      baseSlot = *gVar(_AR()\i)\var(0)\ptr   ; Get struct base slot from pointer
   EndIf
   *structPtr = *gVar(baseSlot)\var(0)\ptr ; Get actual struct memory pointer
   byteOffset = _AR()\n * 8       ; Convert slot offset to byte offset

   gEvalStack(sp)\i = PeekQ(*structPtr + byteOffset)
   sp + 1
   pc + 1
EndProcedure

Procedure               C2PTRSTRUCTFETCH_FLOAT()
   ; Read float field through struct pointer: value = ptr\field
   ; V1.029.59: Updated for \ptr storage
   vm_DebugFunctionName()
   Protected baseSlot.i, *structPtr, byteOffset.i

   ; V1.033.37: Handle local pointer slots (negative = local offset encoded as -(offset+2))
   If _AR()\i < -1
      baseSlot = _LVAR(-(_AR()\i + 2))\ptr
   Else
      baseSlot = *gVar(_AR()\i)\var(0)\ptr
   EndIf
   *structPtr = *gVar(baseSlot)\var(0)\ptr
   byteOffset = _AR()\n * 8

   gEvalStack(sp)\f = PeekD(*structPtr + byteOffset)
   sp + 1
   pc + 1
EndProcedure

Procedure               C2PTRSTRUCTFETCH_STR()
   ; Read string field through struct pointer: value = ptr\field
   ; V1.029.59: Updated for \ptr storage - strings stored as pointers
   vm_DebugFunctionName()
   Protected baseSlot.i, *structPtr, byteOffset.i, *strPtr

   ; V1.033.37: Handle local pointer slots (negative = local offset encoded as -(offset+2))
   If _AR()\i < -1
      baseSlot = _LVAR(-(_AR()\i + 2))\ptr
   Else
      baseSlot = *gVar(_AR()\i)\var(0)\ptr
   EndIf
   *structPtr = *gVar(baseSlot)\var(0)\ptr
   byteOffset = _AR()\n * 8

   *strPtr = PeekQ(*structPtr + byteOffset)
   If *strPtr
      gEvalStack(sp)\ss = PeekS(*strPtr)
   Else
      gEvalStack(sp)\ss = ""
   EndIf
   sp + 1
   pc + 1
EndProcedure

Procedure               C2PTRSTRUCTSTORE_INT()
   ; Write int field through struct pointer: ptr\field = value
   ; V1.029.59: Updated for \ptr storage
   ; _AR()\i = pointer slot, _AR()\n = field offset, _AR()\ndx = value slot
   vm_DebugFunctionName()
   Protected baseSlot.i, *structPtr, byteOffset.i, value.i

   ; V1.033.37: Handle local pointer and value slots (negative = local offset encoded as -(offset+2))
   If _AR()\i < -1
      baseSlot = _LVAR(-(_AR()\i + 2))\ptr
   Else
      baseSlot = *gVar(_AR()\i)\var(0)\ptr
   EndIf
   *structPtr = *gVar(baseSlot)\var(0)\ptr ; Get actual struct memory pointer
   byteOffset = _AR()\n * 8       ; Convert slot offset to byte offset

   If _AR()\ndx < -1
      value = _LVAR(-(_AR()\ndx + 2))\i
   Else
      value = *gVar(_AR()\ndx)\var(0)\i
   EndIf
   PokeQ(*structPtr + byteOffset, value)
   pc + 1
EndProcedure

Procedure               C2PTRSTRUCTSTORE_FLOAT()
   ; Write float field through struct pointer: ptr\field = value
   ; V1.029.59: Updated for \ptr storage
   ; _AR()\i = pointer slot, _AR()\n = field offset, _AR()\ndx = value slot
   vm_DebugFunctionName()
   Protected baseSlot.i, *structPtr, byteOffset.i, value.d

   ; V1.033.37: Handle local pointer and value slots (negative = local offset encoded as -(offset+2))
   If _AR()\i < -1
      baseSlot = _LVAR(-(_AR()\i + 2))\ptr
   Else
      baseSlot = *gVar(_AR()\i)\var(0)\ptr
   EndIf
   *structPtr = *gVar(baseSlot)\var(0)\ptr
   byteOffset = _AR()\n * 8

   If _AR()\ndx < -1
      value = _LVAR(-(_AR()\ndx + 2))\f
   Else
      value = *gVar(_AR()\ndx)\var(0)\f
   EndIf
   PokeD(*structPtr + byteOffset, value)
   pc + 1
EndProcedure

Procedure               C2PTRSTRUCTSTORE_STR()
   ; Write string field through struct pointer: ptr\field = value
   ; V1.029.59: Updated for \ptr storage - manage string memory
   ; _AR()\i = pointer slot, _AR()\n = field offset, _AR()\ndx = value slot
   vm_DebugFunctionName()
   Protected baseSlot.i, *structPtr, byteOffset.i
   Protected *oldStr, *newStr, strLen.i, value.s

   ; V1.033.37: Handle local pointer and value slots (negative = local offset encoded as -(offset+2))
   If _AR()\i < -1
      baseSlot = _LVAR(-(_AR()\i + 2))\ptr
   Else
      baseSlot = *gVar(_AR()\i)\var(0)\ptr
   EndIf
   *structPtr = *gVar(baseSlot)\var(0)\ptr
   byteOffset = _AR()\n * 8
   If _AR()\ndx < -1
      value = _LVAR(-(_AR()\ndx + 2))\ss
   Else
      value = *gVar(_AR()\ndx)\var(0)\ss
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

;- V1.022.117: PTRSTRUCTSTORE_*_LOPT (value from local slot)

Procedure               C2PTRSTRUCTSTORE_INT_LOPT()
   ; Write int field through struct pointer: ptr\field = value (LOCAL value)
   ; V1.029.59: Updated for \ptr storage
   ; _AR()\i = pointer slot, _AR()\n = field offset, _AR()\ndx = LOCAL value offset
   vm_DebugFunctionName()
   Protected baseSlot.i, *structPtr, byteOffset.i, valSlot.i

   baseSlot = *gVar(_AR()\i)\var(0)\ptr   ; Get struct base slot from pointer
   *structPtr = *gVar(baseSlot)\var(0)\ptr ; Get actual struct memory pointer
   byteOffset = _AR()\n * 8       ; Convert slot offset to byte offset
   valSlot = _LARRAY(_AR()\ndx)   ; Get actual gVar index from local offset

   PokeQ(*structPtr + byteOffset, *gVar(valSlot)\var(0)\i)  ; Value from LOCAL slot
   pc + 1
EndProcedure

Procedure               C2PTRSTRUCTSTORE_FLOAT_LOPT()
   ; Write float field through struct pointer: ptr\field = value (LOCAL value)
   ; V1.029.59: Updated for \ptr storage
   ; _AR()\i = pointer slot, _AR()\n = field offset, _AR()\ndx = LOCAL value offset
   vm_DebugFunctionName()
   Protected baseSlot.i, *structPtr, byteOffset.i, valSlot.i

   baseSlot = *gVar(_AR()\i)\var(0)\ptr
   *structPtr = *gVar(baseSlot)\var(0)\ptr
   byteOffset = _AR()\n * 8
   valSlot = _LARRAY(_AR()\ndx)

   PokeD(*structPtr + byteOffset, *gVar(valSlot)\var(0)\f)  ; Value from LOCAL slot
   pc + 1
EndProcedure

Procedure               C2PTRSTRUCTSTORE_STR_LOPT()
   ; Write string field through struct pointer: ptr\field = value (LOCAL value)
   ; V1.029.59: Updated for \ptr storage - manage string memory
   ; _AR()\i = pointer slot, _AR()\n = field offset, _AR()\ndx = LOCAL value offset
   vm_DebugFunctionName()
   Protected baseSlot.i, *structPtr, byteOffset.i, valSlot.i
   Protected *oldStr, *newStr, strLen.i, value.s

   baseSlot = *gVar(_AR()\i)\var(0)\ptr
   *structPtr = *gVar(baseSlot)\var(0)\ptr
   byteOffset = _AR()\n * 8
   valSlot = _LARRAY(_AR()\ndx)
   value = *gVar(valSlot)\var(0)\ss

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

;- V1.022.119: PTRSTRUCTFETCH_*_LPTR (pointer from local slot)

Procedure               C2PTRSTRUCTFETCH_INT_LPTR()
   ; Read int field through struct pointer: value = ptr\field (LOCAL pointer)
   ; V1.029.59: Updated for \ptr storage
   ; _AR()\i = LOCAL pointer offset, _AR()\n = field offset
   vm_DebugFunctionName()
   Protected ptrSlot.i, baseSlot.i, *structPtr, byteOffset.i

   ptrSlot = _LARRAY(_AR()\i)              ; Get runtime pointer slot (gStorage[] index)
   ; V1.035.0: POINTER ARRAY ARCHITECTURE - ptrSlot is a gStorage[] index, not gVar[] index
   baseSlot = *gVar(gCurrentFuncSlot)\var(ptrSlot)\ptr           ; Get struct base slot from LOCAL pointer
   *structPtr = *gVar(baseSlot)\var(0)\ptr          ; Get actual struct memory pointer (structs in *gVar)
   byteOffset = _AR()\n * 8                 ; Convert slot offset to byte offset

   gEvalStack(sp)\i = PeekQ(*structPtr + byteOffset)
   sp + 1
   pc + 1
EndProcedure

Procedure               C2PTRSTRUCTFETCH_FLOAT_LPTR()
   ; Read float field through struct pointer (LOCAL pointer)
   ; V1.029.59: Updated for \ptr storage
   vm_DebugFunctionName()
   Protected ptrSlot.i, baseSlot.i, *structPtr, byteOffset.i

   ptrSlot = _LARRAY(_AR()\i)
   ; V1.035.0: POINTER ARRAY ARCHITECTURE
   baseSlot = *gVar(gCurrentFuncSlot)\var(ptrSlot)\ptr
   *structPtr = *gVar(baseSlot)\var(0)\ptr
   byteOffset = _AR()\n * 8

   gEvalStack(sp)\f = PeekD(*structPtr + byteOffset)
   sp + 1
   pc + 1
EndProcedure

Procedure               C2PTRSTRUCTFETCH_STR_LPTR()
   ; Read string field through struct pointer (LOCAL pointer)
   ; V1.029.59: Updated for \ptr storage - strings stored as pointers
   vm_DebugFunctionName()
   Protected ptrSlot.i, baseSlot.i, *structPtr, byteOffset.i, *strPtr

   ptrSlot = _LARRAY(_AR()\i)
   ; V1.035.0: POINTER ARRAY ARCHITECTURE
   baseSlot = *gVar(gCurrentFuncSlot)\var(ptrSlot)\ptr
   *structPtr = *gVar(baseSlot)\var(0)\ptr
   byteOffset = _AR()\n * 8

   *strPtr = PeekQ(*structPtr + byteOffset)
   If *strPtr
      gEvalStack(sp)\ss = PeekS(*strPtr)
   Else
      gEvalStack(sp)\ss = ""
   EndIf
   sp + 1
   pc + 1
EndProcedure

;- V1.022.119: PTRSTRUCTSTORE_*_LPTR (pointer from local slot, value from global)

Procedure               C2PTRSTRUCTSTORE_INT_LPTR()
   ; Write int field through struct pointer: ptr\field = value (LOCAL pointer)
   ; V1.029.59: Updated for \ptr storage
   ; _AR()\i = LOCAL pointer offset, _AR()\n = field offset, _AR()\ndx = global value slot
   vm_DebugFunctionName()
   Protected ptrSlot.i, baseSlot.i, *structPtr, byteOffset.i

   ptrSlot = _LARRAY(_AR()\i)              ; Get runtime pointer slot (gStorage[] index)
   ; V1.035.0: POINTER ARRAY ARCHITECTURE - ptrSlot is a gStorage[] index
   baseSlot = *gVar(gCurrentFuncSlot)\var(ptrSlot)\ptr           ; Get struct base slot from LOCAL pointer
   *structPtr = *gVar(baseSlot)\var(0)\ptr          ; Get actual struct memory pointer (structs in *gVar)
   byteOffset = _AR()\n * 8                 ; Convert slot offset to byte offset

   PokeQ(*structPtr + byteOffset, *gVar(_AR()\ndx)\var(0)\i)   ; Value from global slot
   pc + 1
EndProcedure

Procedure               C2PTRSTRUCTSTORE_FLOAT_LPTR()
   ; Write float field through struct pointer (LOCAL pointer)
   ; V1.029.59: Updated for \ptr storage
   vm_DebugFunctionName()
   Protected ptrSlot.i, baseSlot.i, *structPtr, byteOffset.i

   ptrSlot = _LARRAY(_AR()\i)
   ; V1.035.0: POINTER ARRAY ARCHITECTURE
   baseSlot = *gVar(gCurrentFuncSlot)\var(ptrSlot)\ptr
   *structPtr = *gVar(baseSlot)\var(0)\ptr
   byteOffset = _AR()\n * 8

   PokeD(*structPtr + byteOffset, *gVar(_AR()\ndx)\var(0)\f)   ; Value from global slot
   pc + 1
EndProcedure

Procedure               C2PTRSTRUCTSTORE_STR_LPTR()
   ; Write string field through struct pointer (LOCAL pointer)
   ; V1.029.59: Updated for \ptr storage - manage string memory
   vm_DebugFunctionName()
   Protected ptrSlot.i, baseSlot.i, *structPtr, byteOffset.i
   Protected *oldStr, *newStr, strLen.i, value.s

   ptrSlot = _LARRAY(_AR()\i)
   ; V1.035.0: POINTER ARRAY ARCHITECTURE
   baseSlot = *gVar(gCurrentFuncSlot)\var(ptrSlot)\ptr
   *structPtr = *gVar(baseSlot)\var(0)\ptr
   byteOffset = _AR()\n * 8
   value = *gVar(_AR()\ndx)\var(0)\ss

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

;- V1.022.119: PTRSTRUCTSTORE_*_LPTR_LOPT (both pointer and value from local)

Procedure               C2PTRSTRUCTSTORE_INT_LPTR_LOPT()
   ; Write int field through struct pointer (LOCAL pointer, LOCAL value)
   ; V1.029.59: Updated for \ptr storage
   ; _AR()\i = LOCAL pointer offset, _AR()\n = field offset, _AR()\ndx = LOCAL value offset
   vm_DebugFunctionName()
   Protected ptrSlot.i, baseSlot.i, *structPtr, byteOffset.i, valSlot.i

   ptrSlot = _LARRAY(_AR()\i)              ; Get runtime pointer slot (gStorage[] index)
   ; V1.035.0: POINTER ARRAY ARCHITECTURE for both pointer and value
   baseSlot = *gVar(gCurrentFuncSlot)\var(ptrSlot)\ptr           ; Get struct base slot from LOCAL pointer
   *structPtr = *gVar(baseSlot)\var(0)\ptr          ; Get actual struct memory pointer (structs in *gVar)
   byteOffset = _AR()\n * 8                 ; Convert slot offset to byte offset
   valSlot = _LARRAY(_AR()\ndx)             ; Get runtime value slot (gStorage[] index)

   PokeQ(*structPtr + byteOffset, *gVar(gCurrentFuncSlot)\var(valSlot)\i)   ; Value from LOCAL slot (gLocal, not gVar!)
   pc + 1
EndProcedure

Procedure               C2PTRSTRUCTSTORE_FLOAT_LPTR_LOPT()
   ; Write float field through struct pointer (LOCAL pointer, LOCAL value)
   ; V1.029.59: Updated for \ptr storage
   vm_DebugFunctionName()
   Protected ptrSlot.i, baseSlot.i, *structPtr, byteOffset.i, valSlot.i

   ptrSlot = _LARRAY(_AR()\i)
   ; V1.035.0: POINTER ARRAY ARCHITECTURE for both pointer and value
   baseSlot = *gVar(gCurrentFuncSlot)\var(ptrSlot)\ptr
   *structPtr = *gVar(baseSlot)\var(0)\ptr
   byteOffset = _AR()\n * 8
   valSlot = _LARRAY(_AR()\ndx)

   PokeD(*structPtr + byteOffset, *gVar(gCurrentFuncSlot)\var(valSlot)\f)   ; Value from LOCAL slot (gLocal, not gVar!)
   pc + 1
EndProcedure

Procedure               C2PTRSTRUCTSTORE_STR_LPTR_LOPT()
   ; Write string field through struct pointer (LOCAL pointer, LOCAL value)
   ; V1.029.59: Updated for \ptr storage - manage string memory
   vm_DebugFunctionName()
   Protected ptrSlot.i, baseSlot.i, *structPtr, byteOffset.i, valSlot.i
   Protected *oldStr, *newStr, strLen.i, value.s

   ptrSlot = _LARRAY(_AR()\i)
   ; V1.035.0: POINTER ARRAY ARCHITECTURE for both pointer and value
   baseSlot = *gVar(gCurrentFuncSlot)\var(ptrSlot)\ptr
   *structPtr = *gVar(baseSlot)\var(0)\ptr
   byteOffset = _AR()\n * 8
   valSlot = _LARRAY(_AR()\ndx)
   value = *gVar(gCurrentFuncSlot)\var(valSlot)\ss   ; Value from LOCAL slot (gLocal, not gVar!)

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

;- V1.022.65: Struct Copy Operation

Procedure               C2STRUCTCOPY()
   ; Copy struct: destStruct = srcStruct
   ; V1.029.60: Updated for \ptr storage - copy memory blocks
   ; _AR()\i = dest base slot, _AR()\j = source base slot, _AR()\n = size (slots)
   ; Copies memory from source to destination struct
   Protected destSlot.i, srcSlot.i, slotCount.i, byteSize.i
   Protected *destPtr, *srcPtr
   vm_DebugFunctionName()

   destSlot = _AR()\i
   srcSlot = _AR()\j
   slotCount = _AR()\n
   byteSize = slotCount * 8

   *destPtr = *gVar(destSlot)\var(0)\ptr
   *srcPtr = *gVar(srcSlot)\var(0)\ptr

   CompilerIf #DEBUG
      Debug "COPYST: d=" + Str(destSlot) + " s=" + Str(srcSlot) + " n=" + Str(slotCount) + " sz=" + Str(byteSize) + " dp=" + Str(*destPtr) + " sp=" + Str(*srcPtr)
   CompilerEndIf

   ; V1.029.60: Safety check - only copy if both pointers valid
   If *destPtr And *srcPtr And byteSize > 0
      CopyMemory(*srcPtr, *destPtr, byteSize)
   CompilerIf #DEBUG
   Else
      Debug "COPYST!: dp=" + Str(*destPtr) + " sp=" + Str(*srcPtr) + " sz=" + Str(byteSize)
   CompilerEndIf
   EndIf

   pc + 1
EndProcedure

;- V1.029.36: Struct Pointer Operations - unified \ptr storage
; All struct variables use *gVar(slot)\var(0)\ptr for contiguous memory storage
; Field offset = field_index * 8 (8 bytes per field)

; Global struct allocation: _AR()\i = slot, _AR()\j = byte size
Procedure C2STRUCT_ALLOC()
   Protected slot.i = _AR()\i
   Protected byteSize.i = _AR()\j
   StructAlloc(slot, byteSize)
   pc + 1
EndProcedure

; Local struct allocation: _AR()\i = paramOffset, _AR()\j = byte size
; V1.035.0: POINTER ARRAY ARCHITECTURE - uses *gVar(gCurrentFuncSlot)\var(offset) directly
; V1.031.26: Fixed to use StructAllocLocal (gStorage[]) instead of StructAlloc (gVar[])
; V1.031.28: Added bounds checking for diagnostics
Procedure C2STRUCT_ALLOC_LOCAL()
   Protected slot.i = _AR()\i
   Protected byteSize.i = _AR()\j
   CompilerIf #DEBUG
      Debug "VM STRUCT_ALLOC_LOCAL: gCurrentFuncSlot=" + Str(gCurrentFuncSlot) + " paramOffset=" + Str(_AR()\i) + " -> slot=" + Str(slot) + " bytes=" + Str(byteSize)
      If slot < 0  ; V1.035.0: POINTER ARRAY - upper bound check obsolete
         Debug "*** STRUCT_ALLOC_LOCAL ERROR: slot=" + Str(slot) + " (offset=" + Str(_AR()\i) + ") is negative at pc=" + Str(pc)
         gExitApplication = #True
         ProcedureReturn
      EndIf
   CompilerEndIf
   StructAllocLocal(slot, byteSize)
   CompilerIf #DEBUG
      Debug "VM STRUCT_ALLOC_LOCAL: after alloc, *gVar(funcSlot)\var(" + Str(slot) + ")\ptr=" + Str(*gVar(gCurrentFuncSlot)\var(slot)\ptr)
   CompilerEndIf
   pc + 1
EndProcedure

; V1.029.39: Free struct variable memory: _AR()\i = slot
; Different from C2STRUCT_FREE in collections (which handles string cleanup)
Procedure C2STRUCT_FREE_VAR()
   Protected slot.i = _AR()\i
   If *gVar(slot)\var(0)\ptr
      FreeMemory(*gVar(slot)\var(0)\ptr)
      *gVar(slot)\var(0)\ptr = 0
   EndIf
   pc + 1
EndProcedure

; Fetch int from global struct: _AR()\i = slot, _AR()\j = byte offset
Procedure C2STRUCT_FETCH_INT()
   Protected slot.i = _AR()\i
   Protected offset.i = _AR()\j
   gEvalStack(sp)\i = StructGetInt(slot, offset)
   sp + 1
   pc + 1
EndProcedure

; Fetch float from global struct: _AR()\i = slot, _AR()\j = byte offset
Procedure C2STRUCT_FETCH_FLOAT()
   Protected slot.i = _AR()\i
   Protected offset.i = _AR()\j
   gEvalStack(sp)\f = StructGetFloat(slot, offset)
   sp + 1
   pc + 1
EndProcedure

; Fetch int from local struct: _AR()\i = paramOffset, _AR()\j = byte offset
; V1.035.0: POINTER ARRAY ARCHITECTURE - uses *gVar(gCurrentFuncSlot)\var(offset) directly
; V1.031.28: Added bounds checking for diagnostics
Procedure C2STRUCT_FETCH_INT_LOCAL()
   Protected slot.i = _AR()\i
   Protected offset.i = _AR()\j
   CompilerIf #DEBUG
      If slot < 0  ; V1.035.0: POINTER ARRAY - upper bound check obsolete
         Debug "*** STRUCT_FETCH_INT_LOCAL ERROR: slot=" + Str(slot) + " out of bounds at pc=" + Str(pc)
         gExitApplication = #True
         ProcedureReturn
      EndIf
   CompilerEndIf
   Protected value.i = StructGetIntLocal(slot, offset)
   CompilerIf #DEBUG
      Debug "VM STRUCT_FETCH_INT_LOCAL: slot=" + Str(slot) + " offset=" + Str(offset) + " value=" + Str(value) + " (ptr=" + Str(*gVar(gCurrentFuncSlot)\var(slot)\ptr) + ")"
   CompilerEndIf
   gEvalStack(sp)\i = value
   sp + 1
   pc + 1
EndProcedure

; Fetch float from local struct: _AR()\i = paramOffset, _AR()\j = byte offset
; V1.035.0: POINTER ARRAY ARCHITECTURE - uses *gVar(gCurrentFuncSlot)\var(offset) directly
Procedure C2STRUCT_FETCH_FLOAT_LOCAL()
   Protected slot.i = _AR()\i
   Protected offset.i = _AR()\j
   CompilerIf #DEBUG
      If slot < 0  ; V1.035.0: POINTER ARRAY - upper bound check obsolete
         Debug "*** STRUCT_FETCH_FLOAT_LOCAL ERROR: slot=" + Str(slot) + " out of bounds at pc=" + Str(pc)
         gExitApplication = #True
         ProcedureReturn
      EndIf
   CompilerEndIf
   ; V1.034.48: Check for NULL ptr before dereferencing
   If *gVar(gCurrentFuncSlot)\var(slot)\ptr = 0
      gExitApplication = #True
      ProcedureReturn
   EndIf
   Protected value.d = StructGetFloatLocal(slot, offset)
   gEvalStack(sp)\f = value
   sp + 1
   pc + 1
EndProcedure

; Store int to global struct: _AR()\i = slot, _AR()\j = byte offset, value on stack
Procedure C2STRUCT_STORE_INT()
   Protected slot.i = _AR()\i
   Protected offset.i = _AR()\j
   sp - 1
   StructSetInt(slot, offset, gEvalStack(sp)\i)
   pc + 1
EndProcedure

; Store float to global struct: _AR()\i = slot, _AR()\j = byte offset, value on stack
Procedure C2STRUCT_STORE_FLOAT()
   Protected slot.i = _AR()\i
   Protected offset.i = _AR()\j
   sp - 1
   StructSetFloat(slot, offset, gEvalStack(sp)\f)
   pc + 1
EndProcedure

; Store int to local struct: _AR()\i = paramOffset, _AR()\j = byte offset, value on stack
; V1.035.0: POINTER ARRAY ARCHITECTURE - uses *gVar(gCurrentFuncSlot)\var(offset) directly
Procedure C2STRUCT_STORE_INT_LOCAL()
   Protected slot.i = _AR()\i
   Protected offset.i = _AR()\j
   sp - 1
   CompilerIf #DEBUG
      If slot < 0  ; V1.035.0: POINTER ARRAY - upper bound check obsolete
         Debug "*** STRUCT_STORE_INT_LOCAL ERROR: slot=" + Str(slot) + " out of bounds at pc=" + Str(pc)
         gExitApplication = #True
         ProcedureReturn
      EndIf
      ; V1.034.52: Fixed sp bounds check - sp is absolute index, not relative to eval stack
      If sp < gGlobalStack Or sp >= gGlobalStack + gMaxEvalStack
         Debug "*** STRUCT_STORE_INT_LOCAL ERROR: sp=" + Str(sp) + " out of bounds [" + Str(gGlobalStack) + ".." + Str(gGlobalStack + gMaxEvalStack - 1) + "] at pc=" + Str(pc)
         gExitApplication = #True
         ProcedureReturn
      EndIf
   CompilerEndIf
   Protected value.i = gEvalStack(sp)\i
   CompilerIf #DEBUG
      Debug "VM STRUCT_STORE_INT_LOCAL: slot=" + Str(slot) + " offset=" + Str(offset) + " value=" + Str(value) + " (ptr=" + Str(*gVar(gCurrentFuncSlot)\var(slot)\ptr) + ")"
   CompilerEndIf
   StructSetIntLocal(slot, offset, value)
   pc + 1
EndProcedure

; Store float to local struct: _AR()\i = paramOffset, _AR()\j = byte offset, value on stack
; V1.035.0: POINTER ARRAY ARCHITECTURE - uses *gVar(gCurrentFuncSlot)\var(offset) directly
Procedure C2STRUCT_STORE_FLOAT_LOCAL()
   Protected slot.i = _AR()\i
   Protected offset.i = _AR()\j
   sp - 1
   CompilerIf #DEBUG
      If slot < 0  ; V1.035.0: POINTER ARRAY - upper bound check obsolete
         Debug "*** STRUCT_STORE_FLOAT_LOCAL ERROR: slot=" + Str(slot) + " out of bounds at pc=" + Str(pc)
         gExitApplication = #True
         ProcedureReturn
      EndIf
      ; V1.034.52: Fixed sp bounds check - sp is absolute index, not relative to eval stack
      If sp < gGlobalStack Or sp >= gGlobalStack + gMaxEvalStack
         Debug "*** STRUCT_STORE_FLOAT_LOCAL ERROR: sp=" + Str(sp) + " out of bounds [" + Str(gGlobalStack) + ".." + Str(gGlobalStack + gMaxEvalStack - 1) + "] at pc=" + Str(pc)
         gExitApplication = #True
         ProcedureReturn
      EndIf
   CompilerEndIf
   ; V1.034.48: Check for NULL ptr before writing
   If *gVar(gCurrentFuncSlot)\var(slot)\ptr = 0
      gExitApplication = #True
      ProcedureReturn
   EndIf
   Protected value.d = gEvalStack(sp)\f
   StructSetFloatLocal(slot, offset, value)
   pc + 1
EndProcedure

; V1.029.55: String struct field support
; Fetch string from global struct: _AR()\i = slot, _AR()\j = byte offset
Procedure C2STRUCT_FETCH_STR()
   Protected slot.i = _AR()\i
   Protected offset.i = _AR()\j
   gEvalStack(sp)\ss = StructGetStr(slot, offset)
   sp + 1
   pc + 1
EndProcedure

; Fetch string from local struct: _AR()\i = paramOffset, _AR()\j = byte offset
; V1.035.0: POINTER ARRAY ARCHITECTURE - uses *gVar(gCurrentFuncSlot)\var(offset) directly
Procedure C2STRUCT_FETCH_STR_LOCAL()
   Protected slot.i = _AR()\i
   Protected offset.i = _AR()\j
   CompilerIf #DEBUG
      If slot < 0  ; V1.035.0: POINTER ARRAY - upper bound check obsolete
         Debug "*** STRUCT_FETCH_STR_LOCAL ERROR: slot=" + Str(slot) + " out of bounds at pc=" + Str(pc)
         gExitApplication = #True
         ProcedureReturn
      EndIf
   CompilerEndIf
   gEvalStack(sp)\ss = StructGetStrLocal(slot, offset)
   sp + 1
   pc + 1
EndProcedure

; Store string to global struct: _AR()\i = slot, _AR()\j = byte offset, value on stack
; Allocates memory for string copy and stores pointer
Procedure C2STRUCT_STORE_STR()
   Protected slot.i = _AR()\i
   Protected offset.i = _AR()\j
   Protected *oldStr, *newStr, strLen.i
   sp - 1
   ; Free old string if exists
   *oldStr = PeekQ(*gVar(slot)\var(0)\ptr + offset)
   If *oldStr : FreeMemory(*oldStr) : EndIf
   ; Allocate and copy new string
   strLen = StringByteLength(gEvalStack(sp)\ss) + SizeOf(Character)
   *newStr = AllocateMemory(strLen)
   PokeS(*newStr, gEvalStack(sp)\ss)
   PokeQ(*gVar(slot)\var(0)\ptr + offset, *newStr)
   pc + 1
EndProcedure

; Store string to local struct: _AR()\i = paramOffset, _AR()\j = byte offset, value on stack
; V1.035.0: POINTER ARRAY ARCHITECTURE - uses *gVar(gCurrentFuncSlot)\var(offset) directly
Procedure C2STRUCT_STORE_STR_LOCAL()
   Protected slot.i = _AR()\i
   Protected offset.i = _AR()\j
   Protected *oldStr, *newStr, strLen.i
   sp - 1
   CompilerIf #DEBUG
      If slot < 0  ; V1.035.0: POINTER ARRAY - upper bound check obsolete
         Debug "*** STRUCT_STORE_STR_LOCAL ERROR: slot=" + Str(slot) + " out of bounds at pc=" + Str(pc)
         gExitApplication = #True
         ProcedureReturn
      EndIf
      ; V1.034.52: Fixed sp bounds check - sp is absolute index, not relative to eval stack
      If sp < gGlobalStack Or sp >= gGlobalStack + gMaxEvalStack
         Debug "*** STRUCT_STORE_STR_LOCAL ERROR: sp=" + Str(sp) + " out of bounds [" + Str(gGlobalStack) + ".." + Str(gGlobalStack + gMaxEvalStack - 1) + "] at pc=" + Str(pc)
         gExitApplication = #True
         ProcedureReturn
      EndIf
   CompilerEndIf
   ; Free old string if exists
   *oldStr = PeekQ(*gVar(gCurrentFuncSlot)\var(slot)\ptr + offset)
   If *oldStr : FreeMemory(*oldStr) : EndIf
   ; Allocate and copy new string
   strLen = StringByteLength(gEvalStack(sp)\ss) + SizeOf(Character)
   *newStr = AllocateMemory(strLen)
   PokeS(*newStr, gEvalStack(sp)\ss)
   PokeQ(*gVar(gCurrentFuncSlot)\var(slot)\ptr + offset, *newStr)
   pc + 1
EndProcedure

; Copy struct memory: _AR()\i = dest slot, _AR()\j = src slot, _AR()\n = byte size
Procedure C2STRUCT_COPY_PTR()
   Protected destSlot.i = _AR()\i
   Protected srcSlot.i = _AR()\j
   Protected byteSize.i = _AR()\n

   ; Ensure dest has memory allocated
   If Not *gVar(destSlot)\var(0)\ptr
      *gVar(destSlot)\var(0)\ptr = AllocateMemory(byteSize)
   EndIf

   ; Copy if both pointers valid
   If *gVar(srcSlot)\var(0)\ptr And *gVar(destSlot)\var(0)\ptr
      StructCopy(*gVar(srcSlot)\var(0)\ptr, *gVar(destSlot)\var(0)\ptr, byteSize)
   EndIf

   pc + 1
EndProcedure

; V1.029.38: Fetch global struct for parameter passing - copies BOTH \i AND \ptr
; This ensures struct pointers are properly passed to callees
; V1.034.24: Unified FETCH_STRUCT - uses j=1 for local, j=0 for global
Procedure C2FETCH_STRUCT()
   gEvalStack(sp)\i = _SLOT(_AR()\j, _AR()\i)\i
   gEvalStack(sp)\ptr = _SLOT(_AR()\j, _AR()\i)\ptr
   sp + 1
   pc + 1
EndProcedure

; V1.034.24: LFETCH_STRUCT now just calls unified FETCH_STRUCT (jump table compatibility)
; Kept for backward compatibility with existing bytecode
Procedure C2LFETCH_STRUCT()
   ; Note: For local structs, j should be 1 (set by codegen), but old bytecode uses this opcode
   ; with j=0, so we hardcode local access for compatibility
   Protected srcSlot.i = _AR()\i
   gEvalStack(sp)\i = *gVar(gCurrentFuncSlot)\var(srcSlot)\i
   gEvalStack(sp)\ptr = *gVar(gCurrentFuncSlot)\var(srcSlot)\ptr
   sp + 1
   pc + 1
EndProcedure

;- End Struct Pointer Operations

;- V1.027.0: Type-Specialized Pointer Opcodes (eliminate runtime type dispatch)
;  These avoid expensive Select/If statements in VM by moving type decisions to compile time

;- Typed Print Pointer Opcodes

Procedure               C2PRTPTR_INT()
   ; Print integer through simple variable pointer (no type dispatch)
   vm_DebugFunctionName()
   sp - 1
   CompilerIf #PB_Compiler_ExecutableFormat = #PB_Compiler_Console
      gBatchOutput + Str(*gVar(gEvalStack(sp)\i)\var(0)\i)
      Print(Str(*gVar(gEvalStack(sp)\i)\var(0)\i))
   CompilerElse
      cline = cline + Str(*gVar(gEvalStack(sp)\i)\var(0)\i)
      If gFastPrint = #False
         vm_SetGadgetText(#edConsole, cy, cline)
      EndIf
   CompilerEndIf
   pc + 1
EndProcedure

Procedure               C2PRTPTR_FLOAT()
   ; Print float through simple variable pointer (no type dispatch)
   vm_DebugFunctionName()
   sp - 1
   CompilerIf #PB_Compiler_ExecutableFormat = #PB_Compiler_Console
      gBatchOutput + StrD(*gVar(gEvalStack(sp)\i)\var(0)\f, gDecs)
      Print(StrD(*gVar(gEvalStack(sp)\i)\var(0)\f, gDecs))
   CompilerElse
      cline = cline + StrD(*gVar(gEvalStack(sp)\i)\var(0)\f, gDecs)
      If gFastPrint = #False
         vm_SetGadgetText(#edConsole, cy, cline)
      EndIf
   CompilerEndIf
   pc + 1
EndProcedure

Procedure               C2PRTPTR_STR()
   ; Print string through simple variable pointer (no type dispatch)
   vm_DebugFunctionName()
   sp - 1
   CompilerIf #PB_Compiler_ExecutableFormat = #PB_Compiler_Console
      gBatchOutput + *gVar(gEvalStack(sp)\i)\var(0)\ss
      Print(*gVar(gEvalStack(sp)\i)\var(0)\ss)
   CompilerElse
      cline = cline + *gVar(gEvalStack(sp)\i)\var(0)\ss
      If gFastPrint = #False
         vm_SetGadgetText(#edConsole, cy, cline)
      EndIf
   CompilerEndIf
   pc + 1
EndProcedure

Procedure               C2PRTPTR_ARRAY_INT()
   ; Print integer through array element pointer (no type dispatch)
   vm_DebugFunctionName()
   sp - 1
   CompilerIf #PB_Compiler_ExecutableFormat = #PB_Compiler_Console
      gBatchOutput + Str(*gVar(gEvalStack(sp)\ptr)\var(0)\dta\ar(gEvalStack(sp)\i)\i)
      Print(Str(*gVar(gEvalStack(sp)\ptr)\var(0)\dta\ar(gEvalStack(sp)\i)\i))
   CompilerElse
      cline = cline + Str(*gVar(gEvalStack(sp)\ptr)\var(0)\dta\ar(gEvalStack(sp)\i)\i)
      If gFastPrint = #False
         vm_SetGadgetText(#edConsole, cy, cline)
      EndIf
   CompilerEndIf
   pc + 1
EndProcedure

Procedure               C2PRTPTR_ARRAY_FLOAT()
   ; Print float through array element pointer (no type dispatch)
   vm_DebugFunctionName()
   sp - 1
   CompilerIf #PB_Compiler_ExecutableFormat = #PB_Compiler_Console
      gBatchOutput + StrD(*gVar(gEvalStack(sp)\ptr)\var(0)\dta\ar(gEvalStack(sp)\i)\f, gDecs)
      Print(StrD(*gVar(gEvalStack(sp)\ptr)\var(0)\dta\ar(gEvalStack(sp)\i)\f, gDecs))
   CompilerElse
      cline = cline + StrD(*gVar(gEvalStack(sp)\ptr)\var(0)\dta\ar(gEvalStack(sp)\i)\f, gDecs)
      If gFastPrint = #False
         vm_SetGadgetText(#edConsole, cy, cline)
      EndIf
   CompilerEndIf
   pc + 1
EndProcedure

Procedure               C2PRTPTR_ARRAY_STR()
   ; Print string through array element pointer (no type dispatch)
   vm_DebugFunctionName()
   sp - 1
   CompilerIf #PB_Compiler_ExecutableFormat = #PB_Compiler_Console
      gBatchOutput + *gVar(gEvalStack(sp)\ptr)\var(0)\dta\ar(gEvalStack(sp)\i)\ss
      Print(*gVar(gEvalStack(sp)\ptr)\var(0)\dta\ar(gEvalStack(sp)\i)\ss)
   CompilerElse
      cline = cline + *gVar(gEvalStack(sp)\ptr)\var(0)\dta\ar(gEvalStack(sp)\i)\ss
      If gFastPrint = #False
         vm_SetGadgetText(#edConsole, cy, cline)
      EndIf
   CompilerEndIf
   pc + 1
EndProcedure

;- Typed Simple Variable Pointer FETCH (no If check)
;- V1.033.5: Optimized to use PeekI/PeekD on \ptr for direct memory access

Procedure               C2PTRFETCH_VAR_INT()
   ; Fetch int from simple variable pointer (no array check)
   ; Uses PeekI on \ptr for direct memory access
   vm_DebugFunctionName()
   sp - 1
   gEvalStack(sp)\i = PeekI(gEvalStack(sp)\ptr)
   sp + 1
   pc + 1
EndProcedure

Procedure               C2PTRFETCH_VAR_FLOAT()
   ; Fetch float from simple variable pointer (no array check)
   ; Uses PeekD on \ptr for direct memory access
   vm_DebugFunctionName()
   sp - 1
   gEvalStack(sp)\f = PeekD(gEvalStack(sp)\ptr)
   sp + 1
   pc + 1
EndProcedure

Procedure               C2PTRFETCH_VAR_STR()
   ; Fetch string from simple variable pointer (no array check)
   vm_DebugFunctionName()
   sp - 1
   gEvalStack(sp)\ss = *gVar(gEvalStack(sp)\i)\var(0)\ss
   gEvalStack(sp)\i = Len(gEvalStack(sp)\ss)
   sp + 1
   pc + 1
EndProcedure

;- Typed Array Element Pointer FETCH (no If check)

Procedure               C2PTRFETCH_ARREL_INT()
   ; Fetch int from array element pointer (no If check)
   ; V1.033.34: Use local vars to avoid \ptr/\i read-write conflict
   Define arraySlot.i, elementIdx.i
   vm_DebugFunctionName()
   sp - 1
   arraySlot = gEvalStack(sp)\ptr
   elementIdx = gEvalStack(sp)\i
   gEvalStack(sp)\i = *gVar(arraySlot)\var(0)\dta\ar(elementIdx)\i
   sp + 1
   pc + 1
EndProcedure

Procedure               C2PTRFETCH_ARREL_FLOAT()
   ; Fetch float from array element pointer (no If check)
   ; V1.033.34: Use local vars for consistency
   Define arraySlot.i, elementIdx.i
   vm_DebugFunctionName()
   sp - 1
   arraySlot = gEvalStack(sp)\ptr
   elementIdx = gEvalStack(sp)\i
   gEvalStack(sp)\f = *gVar(arraySlot)\var(0)\dta\ar(elementIdx)\f
   sp + 1
   pc + 1
EndProcedure

Procedure               C2PTRFETCH_ARREL_STR()
   ; Fetch string from array element pointer (no If check)
   ; V1.033.34: Use local vars for consistency
   Define arraySlot.i, elementIdx.i
   vm_DebugFunctionName()
   sp - 1
   arraySlot = gEvalStack(sp)\ptr
   elementIdx = gEvalStack(sp)\i
   gEvalStack(sp)\ss = *gVar(arraySlot)\var(0)\dta\ar(elementIdx)\ss
   gEvalStack(sp)\i = Len(gEvalStack(sp)\ss)
   sp + 1
   pc + 1
EndProcedure

;- Typed Simple Variable Pointer STORE (no If check)
;- V1.033.5: Optimized to use PokeI/PokeD on \ptr for direct memory access

Procedure               C2PTRSTORE_VAR_INT()
   ; Store int to simple variable pointer (no array check)
   ; Uses PokeI on \ptr for direct memory access
   ; Stack: [value] [pointer]
   vm_DebugFunctionName()
   sp - 1
   sp - 1
   PokeI(gEvalStack(sp + 1)\ptr, gEvalStack(sp)\i)
   pc + 1
EndProcedure

Procedure               C2PTRSTORE_VAR_FLOAT()
   ; Store float to simple variable pointer (no array check)
   ; Uses PokeD on \ptr for direct memory access
   vm_DebugFunctionName()
   sp - 1
   sp - 1
   PokeD(gEvalStack(sp + 1)\ptr, gEvalStack(sp)\f)
   pc + 1
EndProcedure

Procedure               C2PTRSTORE_VAR_STR()
   ; Store string to simple variable pointer (no array check)
   vm_DebugFunctionName()
   sp - 1
   sp - 1
   *gVar(gEvalStack(sp + 1)\i)\var(0)\ss = gEvalStack(sp)\ss
   pc + 1
EndProcedure

;- Typed Array Element Pointer STORE (no If check)

Procedure               C2PTRSTORE_ARREL_INT()
   ; Store int to array element pointer (no If check)
   ; Stack: [value] [pointer]
   ; V1.033.34: Use local vars to avoid \ptr/\i read issues
   Define arraySlot.i, elementIdx.i
   vm_DebugFunctionName()
   sp - 1
   arraySlot = gEvalStack(sp)\ptr
   elementIdx = gEvalStack(sp)\i
   sp - 1
   *gVar(arraySlot)\var(0)\dta\ar(elementIdx)\i = gEvalStack(sp)\i
   pc + 1
EndProcedure

Procedure               C2PTRSTORE_ARREL_FLOAT()
   ; Store float to array element pointer (no If check)
   ; V1.033.34: Use local vars for consistency
   Define arraySlot.i, elementIdx.i
   vm_DebugFunctionName()
   sp - 1
   arraySlot = gEvalStack(sp)\ptr
   elementIdx = gEvalStack(sp)\i
   sp - 1
   *gVar(arraySlot)\var(0)\dta\ar(elementIdx)\f = gEvalStack(sp)\f
   pc + 1
EndProcedure

Procedure               C2PTRSTORE_ARREL_STR()
   ; Store string to array element pointer (no If check)
   ; V1.033.34: Use local vars for consistency
   Define arraySlot.i, elementIdx.i
   vm_DebugFunctionName()
   sp - 1
   arraySlot = gEvalStack(sp)\ptr
   elementIdx = gEvalStack(sp)\i
   sp - 1
   *gVar(arraySlot)\var(0)\dta\ar(elementIdx)\ss = gEvalStack(sp)\ss
   pc + 1
EndProcedure

;- V1.033.5: Local Variable Pointer FETCH (no If check, uses gStorage[])

Procedure               C2PTRFETCH_LVAR_INT()
   ; Fetch int from local simple variable pointer (no array check)
   ; Uses PeekI on \ptr for direct memory access
   vm_DebugFunctionName()
   sp - 1
   gEvalStack(sp)\i = PeekI(gEvalStack(sp)\ptr)
   sp + 1
   pc + 1
EndProcedure

Procedure               C2PTRFETCH_LVAR_FLOAT()
   ; Fetch float from local simple variable pointer (no array check)
   ; Uses PeekD on \ptr for direct memory access
   vm_DebugFunctionName()
   sp - 1
   gEvalStack(sp)\f = PeekD(gEvalStack(sp)\ptr)
   sp + 1
   pc + 1
EndProcedure

Procedure               C2PTRFETCH_LVAR_STR()
   ; Fetch string from local simple variable pointer (no array check)
   ; \i contains actual slot in gStorage[]
   vm_DebugFunctionName()
   sp - 1
   gEvalStack(sp)\ss = *gVar(gCurrentFuncSlot)\var(gEvalStack(sp)\i)\ss
   sp + 1
   pc + 1
EndProcedure

;- V1.033.5: Local Array Element Pointer FETCH (no If check)

Procedure               C2PTRFETCH_LARREL_INT()
   ; Fetch int from local array element pointer (no If check)
   ; \ptr = array slot in gStorage[], \i = element index
   ; V1.033.34: Use local vars to avoid \ptr/\i read-write conflict
   Define arraySlot.i, elementIdx.i
   vm_DebugFunctionName()
   sp - 1
   arraySlot = gEvalStack(sp)\ptr
   elementIdx = gEvalStack(sp)\i
   gEvalStack(sp)\i = *gVar(gCurrentFuncSlot)\var(arraySlot)\dta\ar(elementIdx)\i
   sp + 1
   pc + 1
EndProcedure

Procedure               C2PTRFETCH_LARREL_FLOAT()
   ; Fetch float from local array element pointer (no If check)
   ; V1.033.34: Use local vars for consistency
   Define arraySlot.i, elementIdx.i
   vm_DebugFunctionName()
   sp - 1
   arraySlot = gEvalStack(sp)\ptr
   elementIdx = gEvalStack(sp)\i
   gEvalStack(sp)\f = *gVar(gCurrentFuncSlot)\var(arraySlot)\dta\ar(elementIdx)\f
   sp + 1
   pc + 1
EndProcedure

Procedure               C2PTRFETCH_LARREL_STR()
   ; Fetch string from local array element pointer (no If check)
   ; V1.033.34: Use local vars for consistency
   Define arraySlot.i, elementIdx.i
   vm_DebugFunctionName()
   sp - 1
   arraySlot = gEvalStack(sp)\ptr
   elementIdx = gEvalStack(sp)\i
   gEvalStack(sp)\ss = *gVar(gCurrentFuncSlot)\var(arraySlot)\dta\ar(elementIdx)\ss
   sp + 1
   pc + 1
EndProcedure

;- V1.033.5: Local Variable Pointer STORE (no If check)

Procedure               C2PTRSTORE_LVAR_INT()
   ; Store int to local simple variable pointer (no array check)
   ; Uses PokeI on \ptr for direct memory access
   ; Stack: [value] [pointer]
   vm_DebugFunctionName()
   sp - 1
   sp - 1
   PokeI(gEvalStack(sp + 1)\ptr, gEvalStack(sp)\i)
   pc + 1
EndProcedure

Procedure               C2PTRSTORE_LVAR_FLOAT()
   ; Store float to local simple variable pointer (no array check)
   ; Uses PokeD on \ptr for direct memory access
   vm_DebugFunctionName()
   sp - 1
   sp - 1
   PokeD(gEvalStack(sp + 1)\ptr, gEvalStack(sp)\f)
   pc + 1
EndProcedure

Procedure               C2PTRSTORE_LVAR_STR()
   ; Store string to local simple variable pointer (no array check)
   ; \i contains actual slot in gStorage[]
   vm_DebugFunctionName()
   sp - 1
   sp - 1
   *gVar(gCurrentFuncSlot)\var(gEvalStack(sp + 1)\i)\ss = gEvalStack(sp)\ss
   pc + 1
EndProcedure

;- V1.033.5: Local Array Element Pointer STORE (no If check)

Procedure               C2PTRSTORE_LARREL_INT()
   ; Store int to local array element pointer (no If check)
   ; Stack: [value] [pointer]
   ; V1.033.34: Use local vars to avoid \ptr/\i read issues
   Define arraySlot.i, elementIdx.i
   vm_DebugFunctionName()
   sp - 1
   arraySlot = gEvalStack(sp)\ptr
   elementIdx = gEvalStack(sp)\i
   sp - 1
   *gVar(gCurrentFuncSlot)\var(arraySlot)\dta\ar(elementIdx)\i = gEvalStack(sp)\i
   pc + 1
EndProcedure

Procedure               C2PTRSTORE_LARREL_FLOAT()
   ; Store float to local array element pointer (no If check)
   ; V1.033.34: Use local vars for consistency
   Define arraySlot.i, elementIdx.i
   vm_DebugFunctionName()
   sp - 1
   arraySlot = gEvalStack(sp)\ptr
   elementIdx = gEvalStack(sp)\i
   sp - 1
   *gVar(gCurrentFuncSlot)\var(arraySlot)\dta\ar(elementIdx)\f = gEvalStack(sp)\f
   pc + 1
EndProcedure

Procedure               C2PTRSTORE_LARREL_STR()
   ; Store string to local array element pointer (no If check)
   ; V1.033.34: Use local vars for consistency
   Define arraySlot.i, elementIdx.i
   vm_DebugFunctionName()
   sp - 1
   arraySlot = gEvalStack(sp)\ptr
   elementIdx = gEvalStack(sp)\i
   sp - 1
   *gVar(gCurrentFuncSlot)\var(arraySlot)\dta\ar(elementIdx)\ss = gEvalStack(sp)\ss
   pc + 1
EndProcedure

;- Typed Pointer Arithmetic (no Select)

Procedure               C2PTRADD_INT()
   ; Pointer add for int pointer (memory address + offset*8)
   vm_DebugFunctionName()
   sp - 1
   gEvalStack(sp - 1)\i + gEvalStack(sp)\i
   gEvalStack(sp - 1)\ptr + (gEvalStack(sp)\i * 8)
   pc + 1
EndProcedure

Procedure               C2PTRADD_FLOAT()
   ; Pointer add for float pointer (memory address + offset*8)
   vm_DebugFunctionName()
   sp - 1
   gEvalStack(sp - 1)\i + gEvalStack(sp)\i
   gEvalStack(sp - 1)\ptr + (gEvalStack(sp)\i * 8)
   pc + 1
EndProcedure

Procedure               C2PTRADD_STRING()
   ; Pointer add for string pointer (slot index only)
   vm_DebugFunctionName()
   sp - 1
   gEvalStack(sp - 1)\i + gEvalStack(sp)\i
   pc + 1
EndProcedure

Procedure               C2PTRADD_ARRAY()
   ; Pointer add for array pointer (element index only)
   vm_DebugFunctionName()
   sp - 1
   gEvalStack(sp - 1)\i + gEvalStack(sp)\i
   pc + 1
EndProcedure

Procedure               C2PTRSUB_INT()
   ; Pointer sub for int pointer
   vm_DebugFunctionName()
   sp - 1
   gEvalStack(sp - 1)\i - gEvalStack(sp)\i
   gEvalStack(sp - 1)\ptr - (gEvalStack(sp)\i * 8)
   pc + 1
EndProcedure

Procedure               C2PTRSUB_FLOAT()
   ; Pointer sub for float pointer
   vm_DebugFunctionName()
   sp - 1
   gEvalStack(sp - 1)\i - gEvalStack(sp)\i
   gEvalStack(sp - 1)\ptr - (gEvalStack(sp)\i * 8)
   pc + 1
EndProcedure

Procedure               C2PTRSUB_STRING()
   ; Pointer sub for string pointer (slot index only)
   vm_DebugFunctionName()
   sp - 1
   gEvalStack(sp - 1)\i - gEvalStack(sp)\i
   pc + 1
EndProcedure

Procedure               C2PTRSUB_ARRAY()
   ; Pointer sub for array pointer (element index only)
   vm_DebugFunctionName()
   sp - 1
   gEvalStack(sp - 1)\i - gEvalStack(sp)\i
   pc + 1
EndProcedure

;- Typed Pointer Increment (no Select)

Procedure               C2PTRINC_INT()
   ; Increment int pointer (memory address)
   vm_DebugFunctionName()
   *gVar(_AR()\i)\var(0)\i + 1
   *gVar(_AR()\i)\var(0)\ptr + 8
   pc + 1
EndProcedure

Procedure               C2PTRINC_FLOAT()
   ; Increment float pointer (memory address)
   vm_DebugFunctionName()
   *gVar(_AR()\i)\var(0)\i + 1
   *gVar(_AR()\i)\var(0)\ptr + 8
   pc + 1
EndProcedure

Procedure               C2PTRINC_STRING()
   ; Increment string pointer (slot index)
   vm_DebugFunctionName()
   *gVar(_AR()\i)\var(0)\i + 1
   pc + 1
EndProcedure

Procedure               C2PTRINC_ARRAY()
   ; Increment array pointer (element index)
   vm_DebugFunctionName()
   *gVar(_AR()\i)\var(0)\i + 1
   pc + 1
EndProcedure

;- Typed Pointer Decrement (no Select)

Procedure               C2PTRDEC_INT()
   ; Decrement int pointer
   vm_DebugFunctionName()
   *gVar(_AR()\i)\var(0)\i - 1
   *gVar(_AR()\i)\var(0)\ptr - 8
   pc + 1
EndProcedure

Procedure               C2PTRDEC_FLOAT()
   ; Decrement float pointer
   vm_DebugFunctionName()
   *gVar(_AR()\i)\var(0)\i - 1
   *gVar(_AR()\i)\var(0)\ptr - 8
   pc + 1
EndProcedure

Procedure               C2PTRDEC_STRING()
   ; Decrement string pointer (slot index)
   vm_DebugFunctionName()
   *gVar(_AR()\i)\var(0)\i - 1
   pc + 1
EndProcedure

Procedure               C2PTRDEC_ARRAY()
   ; Decrement array pointer (element index)
   vm_DebugFunctionName()
   *gVar(_AR()\i)\var(0)\i - 1
   pc + 1
EndProcedure

;- Typed Pointer Pre-Increment (no Select)

Procedure               C2PTRINC_PRE_INT()
   ; Pre-increment int pointer
   vm_DebugFunctionName()
   *gVar(_AR()\i)\var(0)\i + 1
   *gVar(_AR()\i)\var(0)\ptr + 8
   gEvalStack(sp)\i = *gVar(_AR()\i)\var(0)\i
   gEvalStack(sp)\ptr = *gVar(_AR()\i)\var(0)\ptr
   gEvalStack(sp)\ptrtype = #PTR_INT
   sp + 1
   pc + 1
EndProcedure

Procedure               C2PTRINC_PRE_FLOAT()
   ; Pre-increment float pointer
   vm_DebugFunctionName()
   *gVar(_AR()\i)\var(0)\i + 1
   *gVar(_AR()\i)\var(0)\ptr + 8
   gEvalStack(sp)\i = *gVar(_AR()\i)\var(0)\i
   gEvalStack(sp)\ptr = *gVar(_AR()\i)\var(0)\ptr
   gEvalStack(sp)\ptrtype = #PTR_FLOAT
   sp + 1
   pc + 1
EndProcedure

Procedure               C2PTRINC_PRE_STRING()
   ; Pre-increment string pointer
   vm_DebugFunctionName()
   *gVar(_AR()\i)\var(0)\i + 1
   gEvalStack(sp)\i = *gVar(_AR()\i)\var(0)\i
   gEvalStack(sp)\ptrtype = #PTR_STRING
   sp + 1
   pc + 1
EndProcedure

Procedure               C2PTRINC_PRE_ARRAY()
   ; Pre-increment array pointer (preserves original ptrtype)
   vm_DebugFunctionName()
   *gVar(_AR()\i)\var(0)\i + 1
   gEvalStack(sp)\i = *gVar(_AR()\i)\var(0)\i
   gEvalStack(sp)\ptr = *gVar(_AR()\i)\var(0)\ptr
   gEvalStack(sp)\ptrtype = *gVar(_AR()\i)\var(0)\ptrtype
   sp + 1
   pc + 1
EndProcedure

;- Typed Pointer Pre-Decrement (no Select)

Procedure               C2PTRDEC_PRE_INT()
   ; Pre-decrement int pointer
   vm_DebugFunctionName()
   *gVar(_AR()\i)\var(0)\i - 1
   *gVar(_AR()\i)\var(0)\ptr - 8
   gEvalStack(sp)\i = *gVar(_AR()\i)\var(0)\i
   gEvalStack(sp)\ptr = *gVar(_AR()\i)\var(0)\ptr
   gEvalStack(sp)\ptrtype = #PTR_INT
   sp + 1
   pc + 1
EndProcedure

Procedure               C2PTRDEC_PRE_FLOAT()
   ; Pre-decrement float pointer
   vm_DebugFunctionName()
   *gVar(_AR()\i)\var(0)\i - 1
   *gVar(_AR()\i)\var(0)\ptr - 8
   gEvalStack(sp)\i = *gVar(_AR()\i)\var(0)\i
   gEvalStack(sp)\ptr = *gVar(_AR()\i)\var(0)\ptr
   gEvalStack(sp)\ptrtype = #PTR_FLOAT
   sp + 1
   pc + 1
EndProcedure

Procedure               C2PTRDEC_PRE_STRING()
   ; Pre-decrement string pointer
   vm_DebugFunctionName()
   *gVar(_AR()\i)\var(0)\i - 1
   gEvalStack(sp)\i = *gVar(_AR()\i)\var(0)\i
   gEvalStack(sp)\ptrtype = #PTR_STRING
   sp + 1
   pc + 1
EndProcedure

Procedure               C2PTRDEC_PRE_ARRAY()
   ; Pre-decrement array pointer (preserves original ptrtype)
   vm_DebugFunctionName()
   *gVar(_AR()\i)\var(0)\i - 1
   gEvalStack(sp)\i = *gVar(_AR()\i)\var(0)\i
   gEvalStack(sp)\ptr = *gVar(_AR()\i)\var(0)\ptr
   gEvalStack(sp)\ptrtype = *gVar(_AR()\i)\var(0)\ptrtype
   sp + 1
   pc + 1
EndProcedure

;- Typed Pointer Post-Increment (no Select)

Procedure               C2PTRINC_POST_INT()
   ; V1.034.33: Post-increment int pointer - unified using _SLOT(j, offset)
   ; j=0: global pointer, j=1: local pointer
   ; V1.034.39: Fix ptrtype preservation and conditional ptr increment
   ; - For PTR_ARRAY_*: only increment i (element index), ptr is array slot
   ; - For PTR_INT/PTR_LOCAL_INT: increment ptr by 8 (memory address)
   vm_DebugFunctionName()
   gEvalStack(sp)\i = _SLOT(_AR()\j, _AR()\i)\i
   gEvalStack(sp)\ptr = _SLOT(_AR()\j, _AR()\i)\ptr
   gEvalStack(sp)\ptrtype = _SLOT(_AR()\j, _AR()\i)\ptrtype  ; Preserve original ptrtype
   _SLOT(_AR()\j, _AR()\i)\i + 1
   ; Only increment ptr for non-array pointers (PTR_INT, PTR_LOCAL_INT)
   If _SLOT(_AR()\j, _AR()\i)\ptrtype = #PTR_INT Or _SLOT(_AR()\j, _AR()\i)\ptrtype = #PTR_LOCAL_INT
      _SLOT(_AR()\j, _AR()\i)\ptr + 8
   EndIf
   sp + 1
   pc + 1
EndProcedure

Procedure               C2PTRINC_POST_FLOAT()
   ; V1.034.33: Post-increment float pointer - unified using _SLOT(j, offset)
   ; V1.034.39: Fix ptrtype preservation and conditional ptr increment
   vm_DebugFunctionName()
   gEvalStack(sp)\i = _SLOT(_AR()\j, _AR()\i)\i
   gEvalStack(sp)\ptr = _SLOT(_AR()\j, _AR()\i)\ptr
   gEvalStack(sp)\ptrtype = _SLOT(_AR()\j, _AR()\i)\ptrtype  ; Preserve original ptrtype
   _SLOT(_AR()\j, _AR()\i)\i + 1
   ; Only increment ptr for non-array pointers
   If _SLOT(_AR()\j, _AR()\i)\ptrtype = #PTR_FLOAT Or _SLOT(_AR()\j, _AR()\i)\ptrtype = #PTR_LOCAL_FLOAT
      _SLOT(_AR()\j, _AR()\i)\ptr + 8
   EndIf
   sp + 1
   pc + 1
EndProcedure

Procedure               C2PTRINC_POST_STRING()
   ; V1.034.33: Post-increment string pointer - unified using _SLOT(j, offset)
   vm_DebugFunctionName()
   gEvalStack(sp)\i = _SLOT(_AR()\j, _AR()\i)\i
   gEvalStack(sp)\ptrtype = #PTR_STRING
   _SLOT(_AR()\j, _AR()\i)\i + 1
   sp + 1
   pc + 1
EndProcedure

Procedure               C2PTRINC_POST_ARRAY()
   ; V1.034.33: Post-increment array pointer - unified using _SLOT(j, offset)
   vm_DebugFunctionName()
   gEvalStack(sp)\i = _SLOT(_AR()\j, _AR()\i)\i
   gEvalStack(sp)\ptr = _SLOT(_AR()\j, _AR()\i)\ptr
   gEvalStack(sp)\ptrtype = _SLOT(_AR()\j, _AR()\i)\ptrtype
   _SLOT(_AR()\j, _AR()\i)\i + 1
   sp + 1
   pc + 1
EndProcedure

;- Typed Pointer Post-Decrement (no Select)

Procedure               C2PTRDEC_POST_INT()
   ; V1.034.33: Post-decrement int pointer - unified using _SLOT(j, offset)
   ; V1.034.39: Fix ptrtype preservation and conditional ptr decrement
   vm_DebugFunctionName()
   gEvalStack(sp)\i = _SLOT(_AR()\j, _AR()\i)\i
   gEvalStack(sp)\ptr = _SLOT(_AR()\j, _AR()\i)\ptr
   gEvalStack(sp)\ptrtype = _SLOT(_AR()\j, _AR()\i)\ptrtype  ; Preserve original ptrtype
   _SLOT(_AR()\j, _AR()\i)\i - 1
   ; Only decrement ptr for non-array pointers
   If _SLOT(_AR()\j, _AR()\i)\ptrtype = #PTR_INT Or _SLOT(_AR()\j, _AR()\i)\ptrtype = #PTR_LOCAL_INT
      _SLOT(_AR()\j, _AR()\i)\ptr - 8
   EndIf
   sp + 1
   pc + 1
EndProcedure

Procedure               C2PTRDEC_POST_FLOAT()
   ; V1.034.33: Post-decrement float pointer - unified using _SLOT(j, offset)
   ; V1.034.39: Fix ptrtype preservation and conditional ptr decrement
   vm_DebugFunctionName()
   gEvalStack(sp)\i = _SLOT(_AR()\j, _AR()\i)\i
   gEvalStack(sp)\ptr = _SLOT(_AR()\j, _AR()\i)\ptr
   gEvalStack(sp)\ptrtype = _SLOT(_AR()\j, _AR()\i)\ptrtype  ; Preserve original ptrtype
   _SLOT(_AR()\j, _AR()\i)\i - 1
   ; Only decrement ptr for non-array pointers
   If _SLOT(_AR()\j, _AR()\i)\ptrtype = #PTR_FLOAT Or _SLOT(_AR()\j, _AR()\i)\ptrtype = #PTR_LOCAL_FLOAT
      _SLOT(_AR()\j, _AR()\i)\ptr - 8
   EndIf
   sp + 1
   pc + 1
EndProcedure

Procedure               C2PTRDEC_POST_STRING()
   ; V1.034.33: Post-decrement string pointer - unified using _SLOT(j, offset)
   vm_DebugFunctionName()
   gEvalStack(sp)\i = _SLOT(_AR()\j, _AR()\i)\i
   gEvalStack(sp)\ptrtype = #PTR_STRING
   _SLOT(_AR()\j, _AR()\i)\i - 1
   sp + 1
   pc + 1
EndProcedure

Procedure               C2PTRDEC_POST_ARRAY()
   ; V1.034.33: Post-decrement array pointer - unified using _SLOT(j, offset)
   vm_DebugFunctionName()
   gEvalStack(sp)\i = _SLOT(_AR()\j, _AR()\i)\i
   gEvalStack(sp)\ptr = _SLOT(_AR()\j, _AR()\i)\ptr
   gEvalStack(sp)\ptrtype = _SLOT(_AR()\j, _AR()\i)\ptrtype
   _SLOT(_AR()\j, _AR()\i)\i - 1
   sp + 1
   pc + 1
EndProcedure

;- Typed Pointer Compound Assignment (no Select)

Procedure               C2PTRADD_ASSIGN_INT()
   ; V1.034.33: ptr += offset for int pointer - unified using _SLOT(j, offset)
   vm_DebugFunctionName()
   sp - 1
   _SLOT(_AR()\j, _AR()\i)\i + gEvalStack(sp)\i
   _SLOT(_AR()\j, _AR()\i)\ptr + (gEvalStack(sp)\i * 8)
   pc + 1
EndProcedure

Procedure               C2PTRADD_ASSIGN_FLOAT()
   ; V1.034.33: ptr += offset for float pointer - unified using _SLOT(j, offset)
   vm_DebugFunctionName()
   sp - 1
   _SLOT(_AR()\j, _AR()\i)\i + gEvalStack(sp)\i
   _SLOT(_AR()\j, _AR()\i)\ptr + (gEvalStack(sp)\i * 8)
   pc + 1
EndProcedure

Procedure               C2PTRADD_ASSIGN_STRING()
   ; V1.034.33: ptr += offset for string pointer - unified using _SLOT(j, offset)
   vm_DebugFunctionName()
   sp - 1
   _SLOT(_AR()\j, _AR()\i)\i + gEvalStack(sp)\i
   pc + 1
EndProcedure

Procedure               C2PTRADD_ASSIGN_ARRAY()
   ; V1.034.33: ptr += offset for array pointer - unified using _SLOT(j, offset)
   vm_DebugFunctionName()
   sp - 1
   _SLOT(_AR()\j, _AR()\i)\i + gEvalStack(sp)\i
   pc + 1
EndProcedure

Procedure               C2PTRSUB_ASSIGN_INT()
   ; V1.034.33: ptr -= offset for int pointer - unified using _SLOT(j, offset)
   vm_DebugFunctionName()
   sp - 1
   _SLOT(_AR()\j, _AR()\i)\i - gEvalStack(sp)\i
   _SLOT(_AR()\j, _AR()\i)\ptr - (gEvalStack(sp)\i * 8)
   pc + 1
EndProcedure

Procedure               C2PTRSUB_ASSIGN_FLOAT()
   ; V1.034.33: ptr -= offset for float pointer - unified using _SLOT(j, offset)
   vm_DebugFunctionName()
   sp - 1
   _SLOT(_AR()\j, _AR()\i)\i - gEvalStack(sp)\i
   _SLOT(_AR()\j, _AR()\i)\ptr - (gEvalStack(sp)\i * 8)
   pc + 1
EndProcedure

Procedure               C2PTRSUB_ASSIGN_STRING()
   ; V1.034.33: ptr -= offset for string pointer - unified using _SLOT(j, offset)
   vm_DebugFunctionName()
   sp - 1
   _SLOT(_AR()\j, _AR()\i)\i - gEvalStack(sp)\i
   pc + 1
EndProcedure

Procedure               C2PTRSUB_ASSIGN_ARRAY()
   ; V1.034.33: ptr -= offset for array pointer - unified using _SLOT(j, offset)
   vm_DebugFunctionName()
   sp - 1
   _SLOT(_AR()\j, _AR()\i)\i - gEvalStack(sp)\i
   pc + 1
EndProcedure

;- End Type-Specialized Pointer Opcodes

;- End Pointer Operations

; IDE Options = PureBasic 6.21 (Windows - x64)
; CursorPosition = 878
; FirstLine = 863
; Folding = ----------
; Markers = 14
; EnableAsm
; EnableThread
; EnableXP
; CPU = 1
; EnablePurifier
; EnableCompileCount = 0
; EnableBuildCount = 0
; EnableExeConstant