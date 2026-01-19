; ======================================================================================================
; c2-collections-v03.pbi - Unified Collection Operations for LJ2 VM
; ======================================================================================================
; V1.035.0 - POINTER ARRAY ARCHITECTURE
;   - Locals at *gVar(gCurrentFuncSlot)\var(offset)
;   - Globals at *gVar(slot)\var(0)
;   - Uses gEvalStack[] for evaluation stack
; V1.028.0 - New unified approach: Lists and Maps directly in gVar structure
;            No separate pool - gVar(slot)\ll() and *gVar(slot)\var(0)\map() hold the data
;            Uses stVTSimple for elements - supports int, float, string, and struct pointers
;
; V1.028.1 - Removed ptrtype from collections (unused with typed opcodes)
;            Added typed LIST_SORT_INT/FLOAT/STR opcodes for correct sorting
;
; V1.029.0 - Struct support with precomputed offsets (Option B - fastest)
;            STRUCT_PEEK_INT/FLOAT/STR - read field at ptr + precomputed offset
;            STRUCT_POKE_INT/FLOAT/STR - write field at ptr + precomputed offset
;            LIST_ADD_STRUCT_TYPED - allocate + copy struct to list
;            MAP_PUT_STRUCT_TYPED - allocate + copy struct to map
;            STRUCT_FREE - free struct memory including string allocations
;            Memory layout: 8 bytes per field, strings allocated separately
;
; Key change from V1:
;   - OLD: *gVar(slot)\var(0)\i = poolSlot, used gListPool(poolSlot)\dataInt()
;   - NEW: *gVar(slot)\var(0)\i = slot, uses gVar(slot)\ll()\i directly
;
; Advantages:
;   - Simpler: No pool management
;   - Faster: Direct access to list/map in gVar
;   - Unified: Everything in gVar
;   - Struct support: *ptr field for struct pointers (AllocateMemory blocks)
;   - No runtime type checks: typed opcodes eliminate ptrtype lookups
;   - Precomputed offsets: No runtime math for struct field access
;
; SpiderBasic compatible - uses PureBasic LinkedList and Map
;
; Kingwolf71 December/2025
; ======================================================================================================

; ======================================================================================================
;- List Creation
; ======================================================================================================

; V1.031.31: Flag to mark local collection slots - stored in high bit of slot value
; When set, operations use gLocal instead of gVar
; V1.031.32: Constants moved to c2-inc-v16.pbi for use by postprocessor

; LIST_NEW: Initialize list at gVar[slot] or LOCAL[offset]
; In V2, we store the slot itself in \i so FETCH can push it
; The ll() list is already initialized by PureBasic (empty by default)
; _AR()\i = slot, _AR()\j = valueType (unused in V2), _AR()\n = isLocal flag
; V1.028.1: Removed ptrtype storage - type known at compile time via typed opcodes
; V1.031.26: Fixed to use gFrameBase and gLocal[] for local collections
; V1.035.0: POINTER ARRAY ARCHITECTURE - store offset with local flag
Procedure C2LIST_NEW()
   Protected slot.i, isLocal.i

   slot = _AR()\i
   isLocal = _AR()\n

   If isLocal
      ; V1.035.0: Store local offset with flag in *gVar(gCurrentFuncSlot)\var(slot)
      *gVar(gCurrentFuncSlot)\var(slot)\i = slot | #C2_LOCAL_COLLECTION_FLAG
      ClearList(*gVar(gCurrentFuncSlot)\var(slot)\ll())   ; Ensure fresh list
   Else
      ; Store to global variable
      *gVar(slot)\var(0)\i = slot                ; Store slot itself for FETCH
      ClearList(*gVar(slot)\var(0)\ll())         ; Ensure fresh list
   EndIf

   pc + 1
EndProcedure

; ======================================================================================================
;- List Operations - Direct gVar Access
; ======================================================================================================

; LIST_ADD_INT: Add integer element to list
; Stack: [varSlot, value] -> []
; The varSlot is the gVar/gLocal index where the list is stored
; V1.035.0: POINTER ARRAY ARCHITECTURE - realSlot is local offset
Procedure C2LIST_ADD_INT()
   Protected varSlot.i, val.i, realSlot.i

   sp - 1 : val = gEvalStack(sp)\i
   sp - 1 : varSlot = gEvalStack(sp)\i

   ; V1.035.0: Check if local collection flag is set
   If varSlot & #C2_LOCAL_COLLECTION_FLAG
      realSlot = varSlot & #C2_SLOT_MASK
      LastElement(*gVar(gCurrentFuncSlot)\var(realSlot)\ll())
      AddElement(*gVar(gCurrentFuncSlot)\var(realSlot)\ll())
      *gVar(gCurrentFuncSlot)\var(realSlot)\ll()\i = val
   Else
      ; Global list
      LastElement(*gVar(varSlot)\var(0)\ll())
      AddElement(*gVar(varSlot)\var(0)\ll())
      *gVar(varSlot)\var(0)\ll()\i = val
   EndIf

   pc + 1
EndProcedure

; LIST_ADD_FLOAT: Add float element to list
; Stack: [varSlot, value] -> []
; V1.031.31: Check local flag to determine which array to use
Procedure C2LIST_ADD_FLOAT()
   Protected varSlot.i, val.d, realSlot.i

   sp - 1 : val = gEvalStack(sp)\f
   sp - 1 : varSlot = gEvalStack(sp)\i

   If varSlot & #C2_LOCAL_COLLECTION_FLAG
      realSlot = varSlot & #C2_SLOT_MASK
      LastElement(*gVar(gCurrentFuncSlot)\var(realSlot)\ll())
      AddElement(*gVar(gCurrentFuncSlot)\var(realSlot)\ll())
      *gVar(gCurrentFuncSlot)\var(realSlot)\ll()\f = val
   Else
      LastElement(*gVar(varSlot)\var(0)\ll())
      AddElement(*gVar(varSlot)\var(0)\ll())
      *gVar(varSlot)\var(0)\ll()\f = val
   EndIf

   pc + 1
EndProcedure

; LIST_ADD_STR: Add string element to list
; Stack: [varSlot, value] -> []
; V1.031.31: Check local flag to determine which array to use
Procedure C2LIST_ADD_STR()
   Protected varSlot.i, val.s, realSlot.i

   sp - 1 : val = gEvalStack(sp)\ss
   sp - 1 : varSlot = gEvalStack(sp)\i

   If varSlot & #C2_LOCAL_COLLECTION_FLAG
      realSlot = varSlot & #C2_SLOT_MASK
      LastElement(*gVar(gCurrentFuncSlot)\var(realSlot)\ll())
      AddElement(*gVar(gCurrentFuncSlot)\var(realSlot)\ll())
      *gVar(gCurrentFuncSlot)\var(realSlot)\ll()\ss = val
   Else
      LastElement(*gVar(varSlot)\var(0)\ll())
      AddElement(*gVar(varSlot)\var(0)\ll())
      *gVar(varSlot)\var(0)\ll()\ss = val
   EndIf

   pc + 1
EndProcedure

; LIST_ADD_STRUCT: Add struct from stack fields to list
; V1.029.28: Stack: [varSlot, field1, field2, ...fieldN] -> []
; _AR()\i = struct size (number of fields)
; _AR()\n = field type bitmap (2 bits per field: 00=int, 01=float, 10=string)
; V1.029.35: Use type bitmap to copy correct field type
Procedure C2LIST_ADD_STRUCT()
   Protected varSlot.i, structSize.i, typeBitmap.q, *mem, i.i, fieldType.i

   structSize = _AR()\i
   typeBitmap = _AR()\n
   If structSize < 1 : structSize = 1 : EndIf

   ; Allocate memory for struct (8 bytes per field)
   *mem = AllocateMemory(structSize * 8)
   If *mem
      ; Pop fields from stack in reverse order (last field first on stack)
      For i = structSize - 1 To 0 Step -1
         sp - 1
         ; V1.029.35: Extract field type from bitmap (2 bits per field)
         fieldType = (typeBitmap >> (i * 2)) & 3
         If fieldType = 1      ; Float
            PokeD(*mem + i * 8, gEvalStack(sp)\f)
         ElseIf fieldType = 2  ; String
            PokeQ(*mem + i * 8, gEvalStack(sp)\i)  ; Store string pointer as int
         Else                  ; Int (default)
            PokeQ(*mem + i * 8, gEvalStack(sp)\i)
         EndIf
      Next
   Else
      ; Failed allocation - just pop the fields
      sp - structSize
   EndIf

   ; Pop pool slot
   sp - 1 : varSlot = gEvalStack(sp)\i

   ; Add to list
   LastElement(*gVar(varSlot)\var(0)\ll())
   AddElement(*gVar(varSlot)\var(0)\ll())
   *gVar(varSlot)\var(0)\ll()\ptr = *mem

   pc + 1
EndProcedure

; LIST_GET_STRUCT: Get current struct and store to destination slots
; V1.029.28: Stack: [varSlot] -> [] (values stored directly to dest)
; V1.029.31: Direct store - no stack push, stores to gVar[destSlot+i]
; _AR()\i = struct size (number of fields)
; _AR()\j = destination base slot
; _AR()\n = field type bitmap (2 bits per field: 00=int, 01=float, 10=string)
; V1.029.35: Use type bitmap to restore correct field type
Procedure C2LIST_GET_STRUCT()
   Protected varSlot.i, structSize.i, destSlot.i, typeBitmap.q, *mem, i.i, fieldType.i

   sp - 1 : varSlot = gEvalStack(sp)\i
   structSize = _AR()\i
   destSlot = _AR()\j
   typeBitmap = _AR()\n
   If structSize < 1 : structSize = 1 : EndIf

   *mem = *gVar(varSlot)\var(0)\ll()\ptr

   If *mem And destSlot > 0
      ; V1.029.35: Restore fields based on type bitmap (8 bytes per field)
      For i = 0 To structSize - 1
         fieldType = (typeBitmap >> (i * 2)) & 3
         If fieldType = 1      ; Float
            *gVar(destSlot + i)\var(0)\f = PeekD(*mem + i * 8)
         ElseIf fieldType = 2  ; String
            *gVar(destSlot + i)\var(0)\i = PeekQ(*mem + i * 8)
         Else                  ; Int (default)
            *gVar(destSlot + i)\var(0)\i = PeekQ(*mem + i * 8)
         EndIf
      Next
   ElseIf destSlot > 0
      ; No memory - store zeros
      For i = 0 To structSize - 1
         fieldType = (typeBitmap >> (i * 2)) & 3
         If fieldType = 1
            *gVar(destSlot + i)\var(0)\f = 0.0
         Else
            *gVar(destSlot + i)\var(0)\i = 0
         EndIf
      Next
   Else
      ; No dest slot (fallback: push to gEvalStack)
      If *mem
         For i = 0 To structSize - 1
            fieldType = (typeBitmap >> (i * 2)) & 3
            If fieldType = 1
               gEvalStack(sp)\f = PeekD(*mem + i * 8)
            Else
               gEvalStack(sp)\i = PeekQ(*mem + i * 8)
            EndIf
            sp + 1
         Next
      Else
         For i = 0 To structSize - 1
            fieldType = (typeBitmap >> (i * 2)) & 3
            If fieldType = 1
               gEvalStack(sp)\f = 0.0
            Else
               gEvalStack(sp)\i = 0
            EndIf
            sp + 1
         Next
      EndIf
   EndIf

   pc + 1
EndProcedure

; LIST_SET_STRUCT: Set current struct from stack fields
; V1.029.28: Stack: [varSlot, field1, field2, ...fieldN] -> []
; _AR()\i = struct size (number of fields)
; _AR()\n = type bitmap (2 bits per field: 00=int, 01=float, 10=string)
Procedure C2LIST_SET_STRUCT()
   Protected varSlot.i, structSize.i, typeBitmap.q, *mem, i.i, fieldType.i

   structSize = _AR()\i
   typeBitmap = _AR()\n
   If structSize < 1 : structSize = 1 : EndIf

   ; Get or allocate memory for current element
   *mem = gEvalStack(sp - structSize - 1)\ll()\ptr
   If Not *mem
      *mem = AllocateMemory(structSize * 8)
      gEvalStack(sp - structSize - 1)\ll()\ptr = *mem
   EndIf

   If *mem
      ; Pop fields from stack in reverse order
      For i = structSize - 1 To 0 Step -1
         sp - 1
         ; V1.029.35: Use type bitmap to read correct field type
         fieldType = (typeBitmap >> (i * 2)) & 3
         If fieldType = 1      ; Float
            PokeD(*mem + i * 8, gEvalStack(sp)\f)
         ElseIf fieldType = 2  ; String
            PokeQ(*mem + i * 8, gEvalStack(sp)\i)
         Else                  ; Int (default)
            PokeQ(*mem + i * 8, gEvalStack(sp)\i)
         EndIf
      Next
   Else
      sp - structSize
   EndIf

   ; Pop pool slot
   sp - 1 : varSlot = gEvalStack(sp)\i

   pc + 1
EndProcedure

; LIST_INSERT_INT: Insert integer at current position
; Stack: [varSlot, value] -> []
Procedure C2LIST_INSERT_INT()
   Protected varSlot.i, val.i

   sp - 1 : val = gEvalStack(sp)\i
   sp - 1 : varSlot = gEvalStack(sp)\i

   InsertElement(*gVar(varSlot)\var(0)\ll())
   *gVar(varSlot)\var(0)\ll()\i = val

   pc + 1
EndProcedure

; LIST_INSERT_FLOAT: Insert float at current position
; Stack: [varSlot, value] -> []
Procedure C2LIST_INSERT_FLOAT()
   Protected varSlot.i, val.d

   sp - 1 : val = gEvalStack(sp)\f
   sp - 1 : varSlot = gEvalStack(sp)\i

   InsertElement(*gVar(varSlot)\var(0)\ll())
   *gVar(varSlot)\var(0)\ll()\f = val

   pc + 1
EndProcedure

; LIST_INSERT_STR: Insert string at current position
; Stack: [varSlot, value] -> []
Procedure C2LIST_INSERT_STR()
   Protected varSlot.i, val.s

   sp - 1 : val = gEvalStack(sp)\ss
   sp - 1 : varSlot = gEvalStack(sp)\i

   InsertElement(*gVar(varSlot)\var(0)\ll())
   *gVar(varSlot)\var(0)\ll()\ss = val

   pc + 1
EndProcedure

; LIST_GET_INT: Get current integer element
; Stack: [varSlot] -> [value]
; V1.031.31: Check local flag
Procedure C2LIST_GET_INT()
   Protected varSlot.i, realSlot.i

   sp - 1 : varSlot = gEvalStack(sp)\i

   If varSlot & #C2_LOCAL_COLLECTION_FLAG
      realSlot = varSlot & #C2_SLOT_MASK
      If ListIndex(*gVar(gCurrentFuncSlot)\var(realSlot)\ll()) >= 0
         gEvalStack(sp)\i = *gVar(gCurrentFuncSlot)\var(realSlot)\ll()\i
      Else
         gEvalStack(sp)\i = 0
      EndIf
   Else
      If ListIndex(*gVar(varSlot)\var(0)\ll()) >= 0
         gEvalStack(sp)\i = *gVar(varSlot)\var(0)\ll()\i
      Else
         gEvalStack(sp)\i = 0
      EndIf
   EndIf
   sp + 1

   pc + 1
EndProcedure

; LIST_GET_FLOAT: Get current float element
; Stack: [varSlot] -> [value]
; V1.031.31: Check local flag
Procedure C2LIST_GET_FLOAT()
   Protected varSlot.i, realSlot.i

   sp - 1 : varSlot = gEvalStack(sp)\i

   If varSlot & #C2_LOCAL_COLLECTION_FLAG
      realSlot = varSlot & #C2_SLOT_MASK
      If ListIndex(*gVar(gCurrentFuncSlot)\var(realSlot)\ll()) >= 0
         gEvalStack(sp)\f = *gVar(gCurrentFuncSlot)\var(realSlot)\ll()\f
      Else
         gEvalStack(sp)\f = 0.0
      EndIf
   Else
      If ListIndex(*gVar(varSlot)\var(0)\ll()) >= 0
         gEvalStack(sp)\f = *gVar(varSlot)\var(0)\ll()\f
      Else
         gEvalStack(sp)\f = 0.0
      EndIf
   EndIf
   sp + 1

   pc + 1
EndProcedure

; LIST_GET_STR: Get current string element
; Stack: [varSlot] -> [value]
; V1.031.31: Check local flag
Procedure C2LIST_GET_STR()
   Protected varSlot.i, realSlot.i

   sp - 1 : varSlot = gEvalStack(sp)\i

   If varSlot & #C2_LOCAL_COLLECTION_FLAG
      realSlot = varSlot & #C2_SLOT_MASK
      If ListIndex(*gVar(gCurrentFuncSlot)\var(realSlot)\ll()) >= 0
         gEvalStack(sp)\ss = *gVar(gCurrentFuncSlot)\var(realSlot)\ll()\ss
      Else
         gEvalStack(sp)\ss = ""
      EndIf
   Else
      If ListIndex(*gVar(varSlot)\var(0)\ll()) >= 0
         gEvalStack(sp)\ss = *gVar(varSlot)\var(0)\ll()\ss
      Else
         gEvalStack(sp)\ss = ""
      EndIf
   EndIf
   sp + 1

   pc + 1
EndProcedure

; LIST_SET_INT: Set current integer element
; Stack: [varSlot, value] -> []
; V1.031.31: Check local flag
Procedure C2LIST_SET_INT()
   Protected varSlot.i, val.i, realSlot.i

   sp - 1 : val = gEvalStack(sp)\i
   sp - 1 : varSlot = gEvalStack(sp)\i

   If varSlot & #C2_LOCAL_COLLECTION_FLAG
      realSlot = varSlot & #C2_SLOT_MASK
      If ListIndex(*gVar(gCurrentFuncSlot)\var(realSlot)\ll()) >= 0
         *gVar(gCurrentFuncSlot)\var(realSlot)\ll()\i = val
      EndIf
   Else
      If ListIndex(*gVar(varSlot)\var(0)\ll()) >= 0
         *gVar(varSlot)\var(0)\ll()\i = val
      EndIf
   EndIf

   pc + 1
EndProcedure

; LIST_SET_FLOAT: Set current float element
; Stack: [varSlot, value] -> []
; V1.031.31: Check local flag
Procedure C2LIST_SET_FLOAT()
   Protected varSlot.i, val.d, realSlot.i

   sp - 1 : val = gEvalStack(sp)\f
   sp - 1 : varSlot = gEvalStack(sp)\i

   If varSlot & #C2_LOCAL_COLLECTION_FLAG
      realSlot = varSlot & #C2_SLOT_MASK
      If ListIndex(*gVar(gCurrentFuncSlot)\var(realSlot)\ll()) >= 0
         *gVar(gCurrentFuncSlot)\var(realSlot)\ll()\f = val
      EndIf
   Else
      If ListIndex(*gVar(varSlot)\var(0)\ll()) >= 0
         *gVar(varSlot)\var(0)\ll()\f = val
      EndIf
   EndIf

   pc + 1
EndProcedure

; LIST_SET_STR: Set current string element
; Stack: [varSlot, value] -> []
; V1.031.31: Check local flag
Procedure C2LIST_SET_STR()
   Protected varSlot.i, val.s, realSlot.i

   sp - 1 : val = gEvalStack(sp)\ss
   sp - 1 : varSlot = gEvalStack(sp)\i

   If varSlot & #C2_LOCAL_COLLECTION_FLAG
      realSlot = varSlot & #C2_SLOT_MASK
      If ListIndex(*gVar(gCurrentFuncSlot)\var(realSlot)\ll()) >= 0
         *gVar(gCurrentFuncSlot)\var(realSlot)\ll()\ss = val
      EndIf
   Else
      If ListIndex(*gVar(varSlot)\var(0)\ll()) >= 0
         *gVar(varSlot)\var(0)\ll()\ss = val
      EndIf
   EndIf

   pc + 1
EndProcedure

; LIST_SIZE_T: Get list size (pool slot from stack)
; Stack: [varSlot] -> [size]
; V1.031.31: Check local flag
Procedure C2LIST_SIZE_T()
   Protected varSlot.i, realSlot.i

   sp - 1 : varSlot = gEvalStack(sp)\i
   If varSlot & #C2_LOCAL_COLLECTION_FLAG
      realSlot = varSlot & #C2_SLOT_MASK
      gEvalStack(sp)\i = ListSize(*gVar(gCurrentFuncSlot)\var(realSlot)\ll())
   Else
      gEvalStack(sp)\i = ListSize(*gVar(varSlot)\var(0)\ll())
   EndIf
   sp + 1

   pc + 1
EndProcedure

; LIST_FIRST_T: Move to first element (pool slot from stack)
; Stack: [varSlot] -> [success]
; V1.031.31: Check local flag
Procedure C2LIST_FIRST_T()
   Protected varSlot.i, realSlot.i

   sp - 1 : varSlot = gEvalStack(sp)\i

   If varSlot & #C2_LOCAL_COLLECTION_FLAG
      realSlot = varSlot & #C2_SLOT_MASK
      If FirstElement(*gVar(gCurrentFuncSlot)\var(realSlot)\ll())
         gEvalStack(sp)\i = 1
      Else
         gEvalStack(sp)\i = 0
      EndIf
   Else
      If FirstElement(*gVar(varSlot)\var(0)\ll())
         gEvalStack(sp)\i = 1
      Else
         gEvalStack(sp)\i = 0
      EndIf
   EndIf
   sp + 1

   pc + 1
EndProcedure

; LIST_LAST_T: Move to last element (pool slot from stack)
; Stack: [varSlot] -> [success]
; V1.031.31: Check local flag
Procedure C2LIST_LAST_T()
   Protected varSlot.i, realSlot.i

   sp - 1 : varSlot = gEvalStack(sp)\i

   If varSlot & #C2_LOCAL_COLLECTION_FLAG
      realSlot = varSlot & #C2_SLOT_MASK
      If LastElement(*gVar(gCurrentFuncSlot)\var(realSlot)\ll())
         gEvalStack(sp)\i = 1
      Else
         gEvalStack(sp)\i = 0
      EndIf
   Else
      If LastElement(*gVar(varSlot)\var(0)\ll())
         gEvalStack(sp)\i = 1
      Else
         gEvalStack(sp)\i = 0
      EndIf
   EndIf
   sp + 1

   pc + 1
EndProcedure

; LIST_NEXT_T: Move to next element (pool slot from stack)
; Stack: [varSlot] -> [success]
; V1.031.31: Check local flag
Procedure C2LIST_NEXT_T()
   Protected varSlot.i, realSlot.i

   sp - 1 : varSlot = gEvalStack(sp)\i

   If varSlot & #C2_LOCAL_COLLECTION_FLAG
      realSlot = varSlot & #C2_SLOT_MASK
      If NextElement(*gVar(gCurrentFuncSlot)\var(realSlot)\ll())
         gEvalStack(sp)\i = 1
      Else
         gEvalStack(sp)\i = 0
      EndIf
   Else
      If NextElement(*gVar(varSlot)\var(0)\ll())
         gEvalStack(sp)\i = 1
      Else
         gEvalStack(sp)\i = 0
      EndIf
   EndIf
   sp + 1

   pc + 1
EndProcedure

; LIST_PREV_T: Move to previous element (pool slot from stack)
; Stack: [varSlot] -> [success]
; V1.031.31: Check local flag
Procedure C2LIST_PREV_T()
   Protected varSlot.i, realSlot.i

   sp - 1 : varSlot = gEvalStack(sp)\i

   If varSlot & #C2_LOCAL_COLLECTION_FLAG
      realSlot = varSlot & #C2_SLOT_MASK
      If PreviousElement(*gVar(gCurrentFuncSlot)\var(realSlot)\ll())
         gEvalStack(sp)\i = 1
      Else
         gEvalStack(sp)\i = 0
      EndIf
   Else
      If PreviousElement(*gVar(varSlot)\var(0)\ll())
         gEvalStack(sp)\i = 1
      Else
         gEvalStack(sp)\i = 0
      EndIf
   EndIf
   sp + 1

   pc + 1
EndProcedure

; LIST_RESET_T: Reset iterator (before first) (pool slot from stack)
; Stack: [varSlot] -> []
; V1.031.31: Check local flag
Procedure C2LIST_RESET_T()
   Protected varSlot.i, realSlot.i

   sp - 1 : varSlot = gEvalStack(sp)\i
   If varSlot & #C2_LOCAL_COLLECTION_FLAG
      realSlot = varSlot & #C2_SLOT_MASK
      ResetList(*gVar(gCurrentFuncSlot)\var(realSlot)\ll())
   Else
      ResetList(*gVar(varSlot)\var(0)\ll())
   EndIf

   pc + 1
EndProcedure

; LIST_INDEX_T: Get current element index (-1 if none) (pool slot from stack)
; Stack: [varSlot] -> [index]
Procedure C2LIST_INDEX_T()
   Protected varSlot.i

   sp - 1 : varSlot = gEvalStack(sp)\i
   gEvalStack(sp)\i = ListIndex(*gVar(varSlot)\var(0)\ll())
   sp + 1

   pc + 1
EndProcedure

; LIST_SELECT_T: Select element by index (pool slot from stack)
; Stack: [varSlot, index] -> [success]
Procedure C2LIST_SELECT_T()
   Protected varSlot.i, idx.i

   sp - 1 : idx = gEvalStack(sp)\i
   sp - 1 : varSlot = gEvalStack(sp)\i

   If SelectElement(*gVar(varSlot)\var(0)\ll(), idx)
      gEvalStack(sp)\i = 1
   Else
      gEvalStack(sp)\i = 0
   EndIf
   sp + 1

   pc + 1
EndProcedure

; LIST_DELETE_T: Delete current element (pool slot from stack)
; Stack: [varSlot] -> []
Procedure C2LIST_DELETE_T()
   Protected varSlot.i

   sp - 1 : varSlot = gEvalStack(sp)\i

   If ListIndex(*gVar(varSlot)\var(0)\ll()) >= 0
      ; Free struct memory if it's a struct pointer
      If *gVar(varSlot)\var(0)\ll()\ptr
         FreeMemory(*gVar(varSlot)\var(0)\ll()\ptr)
      EndIf
      DeleteElement(*gVar(varSlot)\var(0)\ll())
   EndIf

   pc + 1
EndProcedure

; LIST_CLEAR_T: Clear all elements (pool slot from stack)
; Stack: [varSlot] -> []
; V1.031.31: Check local flag
Procedure C2LIST_CLEAR_T()
   Protected varSlot.i, realSlot.i

   sp - 1 : varSlot = gEvalStack(sp)\i

   If varSlot & #C2_LOCAL_COLLECTION_FLAG
      realSlot = varSlot & #C2_SLOT_MASK
      ; Free all struct memory pointers
      ForEach *gVar(gCurrentFuncSlot)\var(realSlot)\ll()
         If *gVar(gCurrentFuncSlot)\var(realSlot)\ll()\ptr
            FreeMemory(*gVar(gCurrentFuncSlot)\var(realSlot)\ll()\ptr)
         EndIf
      Next
      ClearList(*gVar(gCurrentFuncSlot)\var(realSlot)\ll())
   Else
      ; Free all struct memory pointers
      ForEach *gVar(varSlot)\var(0)\ll()
         If *gVar(varSlot)\var(0)\ll()\ptr
            FreeMemory(*gVar(varSlot)\var(0)\ll()\ptr)
         EndIf
      Next
      ClearList(*gVar(varSlot)\var(0)\ll())
   EndIf

   pc + 1
EndProcedure

; LIST_SORT_INT: Sort integer list elements
; Stack: [varSlot, ascending] -> []
Procedure C2LIST_SORT_INT()
   Protected varSlot.i, ascending.i

   sp - 1 : ascending = gEvalStack(sp)\i
   sp - 1 : varSlot = gEvalStack(sp)\i

   If ascending
      SortStructuredList(*gVar(varSlot)\var(0)\ll(), #PB_Sort_Ascending, OffsetOf(stVTSimple\i), TypeOf(stVTSimple\i))
   Else
      SortStructuredList(*gVar(varSlot)\var(0)\ll(), #PB_Sort_Descending, OffsetOf(stVTSimple\i), TypeOf(stVTSimple\i))
   EndIf

   pc + 1
EndProcedure

; LIST_SORT_FLOAT: Sort float list elements
; Stack: [varSlot, ascending] -> []
Procedure C2LIST_SORT_FLOAT()
   Protected varSlot.i, ascending.i

   sp - 1 : ascending = gEvalStack(sp)\i
   sp - 1 : varSlot = gEvalStack(sp)\i

   If ascending
      SortStructuredList(*gVar(varSlot)\var(0)\ll(), #PB_Sort_Ascending, OffsetOf(stVTSimple\f), TypeOf(stVTSimple\f))
   Else
      SortStructuredList(*gVar(varSlot)\var(0)\ll(), #PB_Sort_Descending, OffsetOf(stVTSimple\f), TypeOf(stVTSimple\f))
   EndIf

   pc + 1
EndProcedure

; LIST_SORT_STR: Sort string list elements
; Stack: [varSlot, ascending] -> []
Procedure C2LIST_SORT_STR()
   Protected varSlot.i, ascending.i

   sp - 1 : ascending = gEvalStack(sp)\i
   sp - 1 : varSlot = gEvalStack(sp)\i

   If ascending
      SortStructuredList(*gVar(varSlot)\var(0)\ll(), #PB_Sort_Ascending, OffsetOf(stVTSimple\ss), TypeOf(stVTSimple\ss))
   Else
      SortStructuredList(*gVar(varSlot)\var(0)\ll(), #PB_Sort_Descending, OffsetOf(stVTSimple\ss), TypeOf(stVTSimple\ss))
   EndIf

   pc + 1
EndProcedure

; LIST_SORT_T: Generic stub (postprocessor should convert to typed version)
; Stack: [varSlot, ascending] -> []
Procedure C2LIST_SORT_T()
   ; Generic - postprocessor should convert to typed version
   ; Fallback: sort as integers
   Protected varSlot.i, ascending.i

   sp - 1 : ascending = gEvalStack(sp)\i
   sp - 1 : varSlot = gEvalStack(sp)\i

   If ascending
      SortStructuredList(*gVar(varSlot)\var(0)\ll(), #PB_Sort_Ascending, OffsetOf(stVTSimple\i), TypeOf(stVTSimple\i))
   Else
      SortStructuredList(*gVar(varSlot)\var(0)\ll(), #PB_Sort_Descending, OffsetOf(stVTSimple\i), TypeOf(stVTSimple\i))
   EndIf

   pc + 1
EndProcedure

; ======================================================================================================
;- Generic List Stubs (should be converted by postprocessor, but kept for safety)
; ======================================================================================================

Procedure C2LIST_ADD()
   ; Generic - postprocessor should convert to typed version
   pc + 1
EndProcedure

Procedure C2LIST_INSERT()
   ; Generic - postprocessor should convert to typed version
   pc + 1
EndProcedure

Procedure C2LIST_GET()
   ; Generic - postprocessor should convert to typed version
   pc + 1
EndProcedure

Procedure C2LIST_SET()
   ; Generic - postprocessor should convert to typed version
   pc + 1
EndProcedure

; ======================================================================================================
;- Map Creation
; ======================================================================================================

; MAP_NEW: Initialize map at gVar[slot] or LOCAL[offset]
; In V2, we store the slot itself in \i so FETCH can push it
; The map() is already initialized by PureBasic (empty by default)
; _AR()\i = slot, _AR()\j = valueType (unused in V2), _AR()\n = isLocal flag
; V1.028.1: Removed ptrtype storage - type known at compile time via typed opcodes
; V1.031.26: Fixed to use gFrameBase and gLocal[] for local collections
; V1.031.31: Store local flag in slot value so MAP operations know which array to use
; V1.035.0: POINTER ARRAY ARCHITECTURE - locals via *gVar(gCurrentFuncSlot)\var(offset)
Procedure C2MAP_NEW()
   Protected slot.i, isLocal.i

   slot = _AR()\i
   isLocal = _AR()\n

   If isLocal
      ; V1.035.0: slot is already the local offset - no gFrameBase needed
      ; V1.031.31: Set local flag so MAP operations know to use local
      *gVar(gCurrentFuncSlot)\var(slot)\i = slot | #C2_LOCAL_COLLECTION_FLAG
      ClearMap(*gVar(gCurrentFuncSlot)\var(slot)\map())   ; Ensure fresh map
   Else
      *gVar(slot)\var(0)\i = slot                ; Store slot itself for FETCH
      ClearMap(*gVar(slot)\var(0)\map())         ; Ensure fresh map
   EndIf

   pc + 1
EndProcedure

; ======================================================================================================
;- Map Operations - Direct gVar Access
; ======================================================================================================

; MAP_PUT_INT: Put integer value
; Stack: [varSlot, key, value] -> []
; V1.031.31: Check local flag
Procedure C2MAP_PUT_INT()
   Protected varSlot.i, key.s, val.i, realSlot.i

   sp - 1 : val = gEvalStack(sp)\i
   sp - 1 : key = gEvalStack(sp)\ss
   sp - 1 : varSlot = gEvalStack(sp)\i

   If varSlot & #C2_LOCAL_COLLECTION_FLAG
      realSlot = varSlot & #C2_SLOT_MASK
      *gVar(gCurrentFuncSlot)\var(realSlot)\map(key)\i = val
   Else
      *gVar(varSlot)\var(0)\map(key)\i = val
   EndIf

   pc + 1
EndProcedure

; MAP_PUT_FLOAT: Put float value
; Stack: [varSlot, key, value] -> []
; V1.031.31: Check local flag
Procedure C2MAP_PUT_FLOAT()
   Protected varSlot.i, key.s, val.d, realSlot.i

   sp - 1 : val = gEvalStack(sp)\f
   sp - 1 : key = gEvalStack(sp)\ss
   sp - 1 : varSlot = gEvalStack(sp)\i

   If varSlot & #C2_LOCAL_COLLECTION_FLAG
      realSlot = varSlot & #C2_SLOT_MASK
      *gVar(gCurrentFuncSlot)\var(realSlot)\map(key)\f = val
   Else
      *gVar(varSlot)\var(0)\map(key)\f = val
   EndIf

   pc + 1
EndProcedure

; MAP_PUT_STR: Put string value
; Stack: [varSlot, key, value] -> []
; V1.031.31: Check local flag
Procedure C2MAP_PUT_STR()
   Protected varSlot.i, key.s, val.s, realSlot.i

   sp - 1 : val = gEvalStack(sp)\ss
   sp - 1 : key = gEvalStack(sp)\ss
   sp - 1 : varSlot = gEvalStack(sp)\i

   If varSlot & #C2_LOCAL_COLLECTION_FLAG
      realSlot = varSlot & #C2_SLOT_MASK
      *gVar(gCurrentFuncSlot)\var(realSlot)\map(key)\ss = val
   Else
      *gVar(varSlot)\var(0)\map(key)\ss = val
   EndIf

   pc + 1
EndProcedure

; MAP_PUT_STRUCT: Put struct from stack fields
; V1.029.28: Stack: [varSlot, key, field1, field2, ...fieldN] -> []
; _AR()\i = struct size (number of fields)
; _AR()\n = field type bitmap (2 bits per field: 00=int, 01=float, 10=string)
; V1.029.35: Use type bitmap to copy correct field type
Procedure C2MAP_PUT_STRUCT()
   Protected varSlot.i, key.s, structSize.i, typeBitmap.q, *mem, i.i, fieldType.i

   structSize = _AR()\i
   typeBitmap = _AR()\n
   If structSize < 1 : structSize = 1 : EndIf

   ; Allocate memory for struct (8 bytes per field)
   *mem = AllocateMemory(structSize * 8)
   If *mem
      ; Pop fields from stack in reverse order
      For i = structSize - 1 To 0 Step -1
         sp - 1
         ; V1.029.35: Extract field type from bitmap
         fieldType = (typeBitmap >> (i * 2)) & 3
         If fieldType = 1      ; Float
            PokeD(*mem + i * 8, gEvalStack(sp)\f)
         ElseIf fieldType = 2  ; String
            PokeQ(*mem + i * 8, gEvalStack(sp)\i)
         Else                  ; Int (default)
            PokeQ(*mem + i * 8, gEvalStack(sp)\i)
         EndIf
      Next
   Else
      sp - structSize
   EndIf

   ; Pop key and slot
   sp - 1 : key = gEvalStack(sp)\ss
   sp - 1 : varSlot = gEvalStack(sp)\i

   ; Free old memory if exists
   If FindMapElement(*gVar(varSlot)\var(0)\map(), key) And *gVar(varSlot)\var(0)\map()\ptr
      FreeMemory(*gVar(varSlot)\var(0)\map()\ptr)
   EndIf

   *gVar(varSlot)\var(0)\map(key)\ptr = *mem

   pc + 1
EndProcedure

; MAP_GET_INT: Get integer value
; Stack: [varSlot, key] -> [value]
; V1.031.31: Check local flag
Procedure C2MAP_GET_INT()
   Protected varSlot.i, key.s, realSlot.i

   sp - 1 : key = gEvalStack(sp)\ss
   sp - 1 : varSlot = gEvalStack(sp)\i

   If varSlot & #C2_LOCAL_COLLECTION_FLAG
      realSlot = varSlot & #C2_SLOT_MASK
      If FindMapElement(*gVar(gCurrentFuncSlot)\var(realSlot)\map(), key)
         gEvalStack(sp)\i = *gVar(gCurrentFuncSlot)\var(realSlot)\map()\i
      Else
         gEvalStack(sp)\i = 0
      EndIf
   Else
      If FindMapElement(*gVar(varSlot)\var(0)\map(), key)
         gEvalStack(sp)\i = *gVar(varSlot)\var(0)\map()\i
      Else
         gEvalStack(sp)\i = 0
      EndIf
   EndIf
   sp + 1

   pc + 1
EndProcedure

; MAP_GET_FLOAT: Get float value
; Stack: [varSlot, key] -> [value]
; V1.031.31: Check local flag
Procedure C2MAP_GET_FLOAT()
   Protected varSlot.i, key.s, realSlot.i

   sp - 1 : key = gEvalStack(sp)\ss
   sp - 1 : varSlot = gEvalStack(sp)\i

   If varSlot & #C2_LOCAL_COLLECTION_FLAG
      realSlot = varSlot & #C2_SLOT_MASK
      If FindMapElement(*gVar(gCurrentFuncSlot)\var(realSlot)\map(), key)
         gEvalStack(sp)\f = *gVar(gCurrentFuncSlot)\var(realSlot)\map()\f
      Else
         gEvalStack(sp)\f = 0.0
      EndIf
   Else
      If FindMapElement(*gVar(varSlot)\var(0)\map(), key)
         gEvalStack(sp)\f = *gVar(varSlot)\var(0)\map()\f
      Else
         gEvalStack(sp)\f = 0.0
      EndIf
   EndIf
   sp + 1

   pc + 1
EndProcedure

; MAP_GET_STR: Get string value
; Stack: [varSlot, key] -> [value]
; V1.031.31: Check local flag
Procedure C2MAP_GET_STR()
   Protected varSlot.i, key.s, realSlot.i

   sp - 1 : key = gEvalStack(sp)\ss
   sp - 1 : varSlot = gEvalStack(sp)\i

   If varSlot & #C2_LOCAL_COLLECTION_FLAG
      realSlot = varSlot & #C2_SLOT_MASK
      If FindMapElement(*gVar(gCurrentFuncSlot)\var(realSlot)\map(), key)
         gEvalStack(sp)\ss = *gVar(gCurrentFuncSlot)\var(realSlot)\map()\ss
      Else
         gEvalStack(sp)\ss = ""
      EndIf
   Else
      If FindMapElement(*gVar(varSlot)\var(0)\map(), key)
         gEvalStack(sp)\ss = *gVar(varSlot)\var(0)\map()\ss
      Else
         gEvalStack(sp)\ss = ""
      EndIf
   EndIf
   sp + 1

   pc + 1
EndProcedure

; MAP_GET_STRUCT: Get struct and store to destination slots
; V1.029.28: Stack: [varSlot, key] -> [] (values stored directly to dest)
; V1.029.31: Direct store - no stack push, stores to gVar[destSlot+i]
; _AR()\i = struct size (number of fields)
; _AR()\j = destination base slot
; _AR()\n = field type bitmap (2 bits per field: 00=int, 01=float, 10=string)
; V1.029.35: Use type bitmap to restore correct field type
Procedure C2MAP_GET_STRUCT()
   Protected varSlot.i, key.s, structSize.i, destSlot.i, typeBitmap.q, *mem, i.i, fieldType.i

   sp - 1 : key = gEvalStack(sp)\ss
   sp - 1 : varSlot = gEvalStack(sp)\i

   structSize = _AR()\i
   destSlot = _AR()\j
   typeBitmap = _AR()\n
   If structSize < 1 : structSize = 1 : EndIf

   If FindMapElement(*gVar(varSlot)\var(0)\map(), key)
      *mem = *gVar(varSlot)\var(0)\map()\ptr
      If *mem And destSlot > 0
         ; V1.029.35: Restore fields based on type bitmap (8 bytes per field)
         For i = 0 To structSize - 1
            fieldType = (typeBitmap >> (i * 2)) & 3
            If fieldType = 1
               *gVar(destSlot + i)\var(0)\f = PeekD(*mem + i * 8)
            Else
               *gVar(destSlot + i)\var(0)\i = PeekQ(*mem + i * 8)
            EndIf
         Next
      ElseIf destSlot > 0
         ; No memory - store zeros
         For i = 0 To structSize - 1
            fieldType = (typeBitmap >> (i * 2)) & 3
            If fieldType = 1
               *gVar(destSlot + i)\var(0)\f = 0.0
            Else
               *gVar(destSlot + i)\var(0)\i = 0
            EndIf
         Next
      Else
         ; Fallback: push to stack
         If *mem
            For i = 0 To structSize - 1
               fieldType = (typeBitmap >> (i * 2)) & 3
               If fieldType = 1
                  gEvalStack(sp)\f = PeekD(*mem + i * 8)
               Else
                  gEvalStack(sp)\i = PeekQ(*mem + i * 8)
               EndIf
               sp + 1
            Next
         Else
            For i = 0 To structSize - 1
               fieldType = (typeBitmap >> (i * 2)) & 3
               If fieldType = 1
                  gEvalStack(sp)\f = 0.0
               Else
                  gEvalStack(sp)\i = 0
               EndIf
               sp + 1
            Next
         EndIf
      EndIf
   Else
      ; Key not found
      If destSlot > 0
         For i = 0 To structSize - 1
            fieldType = (typeBitmap >> (i * 2)) & 3
            If fieldType = 1
               *gVar(destSlot + i)\var(0)\f = 0.0
            Else
               *gVar(destSlot + i)\var(0)\i = 0
            EndIf
         Next
      Else
         For i = 0 To structSize - 1
            fieldType = (typeBitmap >> (i * 2)) & 3
            If fieldType = 1
               gEvalStack(sp)\f = 0.0
            Else
               gEvalStack(sp)\i = 0
            EndIf
            sp + 1
         Next
      EndIf
   EndIf

   pc + 1
EndProcedure

; MAP_VALUE_STRUCT: Get current iterator value and push fields to stack
; V1.029.28: Stack: [varSlot] -> [field1, field2, ...fieldN]
; _AR()\i = struct size (number of fields)
; _AR()\n = type bitmap (2 bits per field: 00=int, 01=float, 10=string)
Procedure C2MAP_VALUE_STRUCT()
   Protected varSlot.i, structSize.i, typeBitmap.q, *mem, i.i, fieldType.i

   sp - 1 : varSlot = gEvalStack(sp)\i

   structSize = _AR()\i
   typeBitmap = _AR()\n
   If structSize < 1 : structSize = 1 : EndIf

   *mem = *gVar(varSlot)\var(0)\map()\ptr

   If *mem
      ; V1.029.35: Use type bitmap to restore correct field type
      For i = 0 To structSize - 1
         fieldType = (typeBitmap >> (i * 2)) & 3
         If fieldType = 1      ; Float
            gEvalStack(sp)\f = PeekD(*mem + i * 8)
         ElseIf fieldType = 2  ; String
            gEvalStack(sp)\i = PeekQ(*mem + i * 8)
         Else                  ; Int (default)
            gEvalStack(sp)\i = PeekQ(*mem + i * 8)
         EndIf
         sp + 1
      Next
   Else
      ; No memory - push zeros
      For i = 0 To structSize - 1
         gEvalStack(sp)\i = 0
         sp + 1
      Next
   EndIf

   pc + 1
EndProcedure

; MAP_SIZE_T: Get map size (pool slot from stack)
; Stack: [varSlot] -> [size]
; V1.031.31: Check local flag
Procedure C2MAP_SIZE_T()
   Protected varSlot.i, realSlot.i

   sp - 1 : varSlot = gEvalStack(sp)\i
   If varSlot & #C2_LOCAL_COLLECTION_FLAG
      realSlot = varSlot & #C2_SLOT_MASK
      gEvalStack(sp)\i = MapSize(*gVar(gCurrentFuncSlot)\var(realSlot)\map())
   Else
      gEvalStack(sp)\i = MapSize(*gVar(varSlot)\var(0)\map())
   EndIf
   sp + 1

   pc + 1
EndProcedure

; MAP_CONTAINS_T: Check if key exists (pool slot from stack)
; Stack: [varSlot, key] -> [exists]
; V1.031.31: Check local flag
Procedure C2MAP_CONTAINS_T()
   Protected varSlot.i, key.s, realSlot.i

   sp - 1 : key = gEvalStack(sp)\ss
   sp - 1 : varSlot = gEvalStack(sp)\i

   If varSlot & #C2_LOCAL_COLLECTION_FLAG
      realSlot = varSlot & #C2_SLOT_MASK
      If FindMapElement(*gVar(gCurrentFuncSlot)\var(realSlot)\map(), key)
         gEvalStack(sp)\i = 1
      Else
         gEvalStack(sp)\i = 0
      EndIf
   Else
      If FindMapElement(*gVar(varSlot)\var(0)\map(), key)
         gEvalStack(sp)\i = 1
      Else
         gEvalStack(sp)\i = 0
      EndIf
   EndIf
   sp + 1

   pc + 1
EndProcedure

; MAP_DELETE_T: Delete key (pool slot from stack)
; Stack: [varSlot, key] -> []
; V1.031.31: Check local flag
Procedure C2MAP_DELETE_T()
   Protected varSlot.i, key.s, realSlot.i

   sp - 1 : key = gEvalStack(sp)\ss
   sp - 1 : varSlot = gEvalStack(sp)\i

   If varSlot & #C2_LOCAL_COLLECTION_FLAG
      realSlot = varSlot & #C2_SLOT_MASK
      If FindMapElement(*gVar(gCurrentFuncSlot)\var(realSlot)\map(), key)
         If *gVar(gCurrentFuncSlot)\var(realSlot)\map()\ptr
            FreeMemory(*gVar(gCurrentFuncSlot)\var(realSlot)\map()\ptr)
         EndIf
         DeleteMapElement(*gVar(gCurrentFuncSlot)\var(realSlot)\map())
      EndIf
   Else
      If FindMapElement(*gVar(varSlot)\var(0)\map(), key)
         ; Free struct memory if present
         If *gVar(varSlot)\var(0)\map()\ptr
            FreeMemory(*gVar(varSlot)\var(0)\map()\ptr)
         EndIf
         DeleteMapElement(*gVar(varSlot)\var(0)\map())
      EndIf
   EndIf

   pc + 1
EndProcedure

; MAP_CLEAR_T: Clear all entries (pool slot from stack)
; Stack: [varSlot] -> []
; V1.031.31: Check local flag
Procedure C2MAP_CLEAR_T()
   Protected varSlot.i, realSlot.i

   sp - 1 : varSlot = gEvalStack(sp)\i

   If varSlot & #C2_LOCAL_COLLECTION_FLAG
      realSlot = varSlot & #C2_SLOT_MASK
      ; Free all struct memory pointers
      ForEach *gVar(gCurrentFuncSlot)\var(realSlot)\map()
         If *gVar(gCurrentFuncSlot)\var(realSlot)\map()\ptr
            FreeMemory(*gVar(gCurrentFuncSlot)\var(realSlot)\map()\ptr)
         EndIf
      Next
      ClearMap(*gVar(gCurrentFuncSlot)\var(realSlot)\map())
   Else
      ; Free all struct memory pointers
      ForEach *gVar(varSlot)\var(0)\map()
         If *gVar(varSlot)\var(0)\map()\ptr
            FreeMemory(*gVar(varSlot)\var(0)\map()\ptr)
         EndIf
      Next
      ClearMap(*gVar(varSlot)\var(0)\map())
   EndIf

   pc + 1
EndProcedure

; MAP_RESET_T: Reset iterator (pool slot from stack)
; Stack: [varSlot] -> []
; V1.031.31: Check local flag
Procedure C2MAP_RESET_T()
   Protected varSlot.i, realSlot.i

   sp - 1 : varSlot = gEvalStack(sp)\i
   If varSlot & #C2_LOCAL_COLLECTION_FLAG
      realSlot = varSlot & #C2_SLOT_MASK
      ResetMap(*gVar(gCurrentFuncSlot)\var(realSlot)\map())
   Else
      ResetMap(*gVar(varSlot)\var(0)\map())
   EndIf

   pc + 1
EndProcedure

; MAP_NEXT_T: Move to next entry (pool slot from stack)
; Stack: [varSlot] -> [success]
; V1.031.31: Check local flag
Procedure C2MAP_NEXT_T()
   Protected varSlot.i, realSlot.i

   sp - 1 : varSlot = gEvalStack(sp)\i

   If varSlot & #C2_LOCAL_COLLECTION_FLAG
      realSlot = varSlot & #C2_SLOT_MASK
      If NextMapElement(*gVar(gCurrentFuncSlot)\var(realSlot)\map())
         gEvalStack(sp)\i = 1
      Else
         gEvalStack(sp)\i = 0
      EndIf
   Else
      If NextMapElement(*gVar(varSlot)\var(0)\map())
         gEvalStack(sp)\i = 1
      Else
         gEvalStack(sp)\i = 0
      EndIf
   EndIf
   sp + 1

   pc + 1
EndProcedure

; MAP_KEY_T: Get current key (pool slot from stack)
; Stack: [varSlot] -> [key]
; V1.031.31: Check local flag
Procedure C2MAP_KEY_T()
   Protected varSlot.i, realSlot.i

   sp - 1 : varSlot = gEvalStack(sp)\i
   If varSlot & #C2_LOCAL_COLLECTION_FLAG
      realSlot = varSlot & #C2_SLOT_MASK
      gEvalStack(sp)\ss = MapKey(*gVar(gCurrentFuncSlot)\var(realSlot)\map())
   Else
      gEvalStack(sp)\ss = MapKey(*gVar(varSlot)\var(0)\map())
   EndIf
   sp + 1

   pc + 1
EndProcedure

; MAP_VALUE_INT: Get current integer value
; Stack: [varSlot] -> [value]
; V1.031.31: Check local flag
Procedure C2MAP_VALUE_INT()
   Protected varSlot.i, realSlot.i

   sp - 1 : varSlot = gEvalStack(sp)\i
   If varSlot & #C2_LOCAL_COLLECTION_FLAG
      realSlot = varSlot & #C2_SLOT_MASK
      gEvalStack(sp)\i = *gVar(gCurrentFuncSlot)\var(realSlot)\map()\i
   Else
      gEvalStack(sp)\i = *gVar(varSlot)\var(0)\map()\i
   EndIf
   sp + 1

   pc + 1
EndProcedure

; MAP_VALUE_FLOAT: Get current float value
; Stack: [varSlot] -> [value]
; V1.031.31: Check local flag
Procedure C2MAP_VALUE_FLOAT()
   Protected varSlot.i, realSlot.i

   sp - 1 : varSlot = gEvalStack(sp)\i
   If varSlot & #C2_LOCAL_COLLECTION_FLAG
      realSlot = varSlot & #C2_SLOT_MASK
      gEvalStack(sp)\f = *gVar(gCurrentFuncSlot)\var(realSlot)\map()\f
   Else
      gEvalStack(sp)\f = *gVar(varSlot)\var(0)\map()\f
   EndIf
   sp + 1

   pc + 1
EndProcedure

; MAP_VALUE_STR: Get current string value
; Stack: [varSlot] -> [value]
; V1.031.31: Check local flag
Procedure C2MAP_VALUE_STR()
   Protected varSlot.i, realSlot.i

   sp - 1 : varSlot = gEvalStack(sp)\i
   If varSlot & #C2_LOCAL_COLLECTION_FLAG
      realSlot = varSlot & #C2_SLOT_MASK
      gEvalStack(sp)\ss = *gVar(gCurrentFuncSlot)\var(realSlot)\map()\ss
   Else
      gEvalStack(sp)\ss = *gVar(varSlot)\var(0)\map()\ss
   EndIf
   sp + 1

   pc + 1
EndProcedure

; ======================================================================================================
;- Generic Map Stubs (should be converted by postprocessor, but kept for safety)
; ======================================================================================================

Procedure C2MAP_PUT()
   ; Generic - postprocessor should convert to typed version
   pc + 1
EndProcedure

Procedure C2MAP_GET()
   ; Generic - postprocessor should convert to typed version
   pc + 1
EndProcedure

Procedure C2MAP_VALUE()
   ; Generic - postprocessor should convert to typed version
   pc + 1
EndProcedure

; ======================================================================================================
;- Struct Field Access with Precomputed Offsets (V1.029.0)
; ======================================================================================================
; Memory layout: 8 bytes per field (64-bit aligned)
; Compiler precomputes byte offsets, VM just does ptr + constant
; Strings: Allocated separately, pointer stored in struct memory

; STRUCT_PEEK_INT: Read integer from struct pointer + precomputed offset
; _AR()\i = byteOffset (precomputed by compiler)
; Stack: [ptr] -> [value]
Procedure C2STRUCT_PEEK_INT()
   sp - 1
   gEvalStack(sp)\i = PeekI(gEvalStack(sp)\ptr + _AR()\i)
   sp + 1
   pc + 1
EndProcedure

; STRUCT_PEEK_FLOAT: Read float from struct pointer + precomputed offset
; _AR()\i = byteOffset (precomputed by compiler)
; Stack: [ptr] -> [value]
Procedure C2STRUCT_PEEK_FLOAT()
   sp - 1
   gEvalStack(sp)\f = PeekD(gEvalStack(sp)\ptr + _AR()\i)
   sp + 1
   pc + 1
EndProcedure

; STRUCT_PEEK_STR: Read string from struct pointer + precomputed offset
; _AR()\i = byteOffset (precomputed by compiler)
; String pointer stored in struct memory, use PeekS to read
; Stack: [ptr] -> [value]
Procedure C2STRUCT_PEEK_STR()
   Protected *strPtr
   sp - 1
   *strPtr = PeekI(gEvalStack(sp)\ptr + _AR()\i)
   If *strPtr
      gEvalStack(sp)\ss = PeekS(*strPtr)
   Else
      gEvalStack(sp)\ss = ""
   EndIf
   sp + 1
   pc + 1
EndProcedure

; STRUCT_POKE_INT: Write integer to struct pointer + precomputed offset
; _AR()\i = byteOffset (precomputed by compiler)
; Stack: [ptr, value] -> []
Procedure C2STRUCT_POKE_INT()
   Protected *ptr, val.i
   sp - 1 : val = gEvalStack(sp)\i
   sp - 1 : *ptr = gEvalStack(sp)\ptr
   PokeI(*ptr + _AR()\i, val)
   pc + 1
EndProcedure

; STRUCT_POKE_FLOAT: Write float to struct pointer + precomputed offset
; _AR()\i = byteOffset (precomputed by compiler)
; Stack: [ptr, value] -> []
Procedure C2STRUCT_POKE_FLOAT()
   Protected *ptr, val.d
   sp - 1 : val = gEvalStack(sp)\f
   sp - 1 : *ptr = gEvalStack(sp)\ptr
   PokeD(*ptr + _AR()\i, val)
   pc + 1
EndProcedure

; STRUCT_POKE_STR: Write string to struct pointer + precomputed offset
; _AR()\i = byteOffset (precomputed by compiler)
; Allocates new string memory, frees old if present
; Stack: [ptr, value] -> []
Procedure C2STRUCT_POKE_STR()
   Protected *ptr, *oldStr, *newStr, val.s, slen.i
   sp - 1 : val = gEvalStack(sp)\ss
   sp - 1 : *ptr = gEvalStack(sp)\ptr

   ; Free old string if present
   *oldStr = PeekI(*ptr + _AR()\i)
   If *oldStr
      FreeMemory(*oldStr)
   EndIf

   ; Allocate and copy new string
   slen = StringByteLength(val) + SizeOf(Character)  ; Include null terminator
   *newStr = AllocateMemory(slen)
   If *newStr
      PokeS(*newStr, val)
   EndIf
   PokeI(*ptr + _AR()\i, *newStr)

   pc + 1
EndProcedure

; ======================================================================================================
;- Struct Copy Operations for Lists/Maps (V1.029.0)
; ======================================================================================================

; LIST_ADD_STRUCT_COPY: Allocate memory and copy struct fields to list
; _AR()\i = structSize (number of fields)
; _AR()\j = baseSlot (source struct base in gVar)
; _AR()\n = field types bitmask or type array pointer (for string handling)
; Stack: [varSlot] -> []
; Note: For simplicity, this version copies all fields as 8-byte values
;       Strings require separate handling via field type info
Procedure C2LIST_ADD_STRUCT_COPY()
   Protected varSlot.i, structSize.i, baseSlot.i, *mem, i.i, slen.i, *strMem

   sp - 1 : varSlot = gEvalStack(sp)\i
   structSize = _AR()\i
   baseSlot = _AR()\j

   ; Allocate memory for struct (8 bytes per field)
   *mem = AllocateMemory(structSize * 8)
   If *mem
      ; Copy each field - compiler should emit field types for proper handling
      ; For now, copy \i field (works for int, stores slot for strings to handle later)
      For i = 0 To structSize - 1
         PokeI(*mem + i * 8, *gVar(baseSlot + i)\var(0)\i)
      Next
   EndIf

   ; Add to list
   LastElement(*gVar(varSlot)\var(0)\ll())
   AddElement(*gVar(varSlot)\var(0)\ll())
   *gVar(varSlot)\var(0)\ll()\ptr = *mem

   pc + 1
EndProcedure

; LIST_ADD_STRUCT_TYPED: Add struct with proper type handling
; _AR()\i = structSize, _AR()\j = baseSlot, _AR()\n = fieldTypesSlot
; Field types: 0=int, 1=float, 2=string
; Stack: [varSlot] -> []
Procedure C2LIST_ADD_STRUCT_TYPED()
   Protected varSlot.i, structSize.i, baseSlot.i, fieldTypesSlot.i
   Protected *mem, i.i, fieldType.i, slen.i, *strMem

   sp - 1 : varSlot = gEvalStack(sp)\i
   structSize = _AR()\i
   baseSlot = _AR()\j
   fieldTypesSlot = _AR()\n

   ; Allocate memory for struct (8 bytes per field)
   *mem = AllocateMemory(structSize * 8)
   If *mem
      For i = 0 To structSize - 1
         fieldType = *gVar(fieldTypesSlot + i)\var(0)\i
         Select fieldType
            Case 0  ; Int
               PokeI(*mem + i * 8, *gVar(baseSlot + i)\var(0)\i)
            Case 1  ; Float
               PokeD(*mem + i * 8, *gVar(baseSlot + i)\var(0)\f)
            Case 2  ; String - allocate copy
               slen = StringByteLength(*gVar(baseSlot + i)\var(0)\ss) + SizeOf(Character)
               *strMem = AllocateMemory(slen)
               If *strMem
                  PokeS(*strMem, *gVar(baseSlot + i)\var(0)\ss)
               EndIf
               PokeI(*mem + i * 8, *strMem)
         EndSelect
      Next
   EndIf

   ; Add to list
   LastElement(*gVar(varSlot)\var(0)\ll())
   AddElement(*gVar(varSlot)\var(0)\ll())
   *gVar(varSlot)\var(0)\ll()\ptr = *mem

   pc + 1
EndProcedure

; MAP_PUT_STRUCT_TYPED: Put struct in map with proper type handling
; _AR()\i = structSize, _AR()\j = baseSlot, _AR()\n = fieldTypesSlot
; Stack: [varSlot, key] -> []
Procedure C2MAP_PUT_STRUCT_TYPED()
   Protected varSlot.i, key.s, structSize.i, baseSlot.i, fieldTypesSlot.i
   Protected *mem, *oldMem, i.i, fieldType.i, slen.i, *strMem

   sp - 1 : key = gEvalStack(sp)\ss
   sp - 1 : varSlot = gEvalStack(sp)\i
   structSize = _AR()\i
   baseSlot = _AR()\j
   fieldTypesSlot = _AR()\n

   ; Free old struct if key exists
   If FindMapElement(*gVar(varSlot)\var(0)\map(), key)
      *oldMem = *gVar(varSlot)\var(0)\map()\ptr
      If *oldMem
         ; Free string allocations first (would need field types info)
         FreeMemory(*oldMem)
      EndIf
   EndIf

   ; Allocate memory for struct (8 bytes per field)
   *mem = AllocateMemory(structSize * 8)
   If *mem
      For i = 0 To structSize - 1
         fieldType = *gVar(fieldTypesSlot + i)\var(0)\i
         Select fieldType
            Case 0  ; Int
               PokeI(*mem + i * 8, *gVar(baseSlot + i)\var(0)\i)
            Case 1  ; Float
               PokeD(*mem + i * 8, *gVar(baseSlot + i)\var(0)\f)
            Case 2  ; String - allocate copy
               slen = StringByteLength(*gVar(baseSlot + i)\var(0)\ss) + SizeOf(Character)
               *strMem = AllocateMemory(slen)
               If *strMem
                  PokeS(*strMem, *gVar(baseSlot + i)\var(0)\ss)
               EndIf
               PokeI(*mem + i * 8, *strMem)
         EndSelect
      Next
   EndIf

   ; Put in map
   *gVar(varSlot)\var(0)\map(key)\ptr = *mem

   pc + 1
EndProcedure

; ======================================================================================================
;- V1.029.65: \ptr-based Struct Collection Operations
;  These work with V1.029.40+ \ptr storage model where struct data is in gVar(slot)\ptr
; ======================================================================================================

; LIST_ADD_STRUCT_PTR: Add struct from \ptr storage to list
; Stack: [varSlot, structSlot] -> []
; _AR()\i = byte size of struct, _AR()\j = field type bitmap for deep string copy
; V1.031.33: Deep copy strings to prevent use-after-free when source struct is modified
Procedure C2LIST_ADD_STRUCT_PTR()
   Protected varSlot.i, structSlot.i, byteSize.i, *srcMem, *destMem
   Protected fieldBitmap.q, fieldIdx.i, numFields.i, fieldType.i
   Protected *srcStr, *newStr, strLen.i

   byteSize = _AR()\i
   fieldBitmap = _AR()\j  ; V1.031.33: Field type bitmap (2 bits per field: 00=int, 01=float, 10=string)
   If byteSize < 8 : byteSize = 8 : EndIf
   numFields = byteSize / 8  ; Each field is 8 bytes

   ; Pop struct slot (pushed via FETCH_STRUCT)
   sp - 1 : structSlot = gEvalStack(sp)\i
   ; Get source pointer from struct's \ptr
   *srcMem = gEvalStack(sp)\ptr

   ; Pop pool slot
   sp - 1 : varSlot = gEvalStack(sp)\i

   ; Allocate memory and shallow copy first
   *destMem = AllocateMemory(byteSize)
   If *destMem And *srcMem
      CopyMemory(*srcMem, *destMem, byteSize)

      ; V1.031.33: Deep copy string fields to prevent use-after-free
      ; Iterate through fields, check bitmap for string type (10 = string)
      For fieldIdx = 0 To numFields - 1
         fieldType = (fieldBitmap >> (fieldIdx * 2)) & 3
         If fieldType = 2  ; 10 = string
            ; Get source string pointer from field
            *srcStr = PeekI(*srcMem + fieldIdx * 8)
            If *srcStr
               ; Allocate new memory and copy string content
               strLen = MemoryStringLength(*srcStr) * SizeOf(Character) + SizeOf(Character)
               *newStr = AllocateMemory(strLen)
               If *newStr
                  CopyMemory(*srcStr, *newStr, strLen)
               EndIf
               ; Store new pointer in destination field
               PokeI(*destMem + fieldIdx * 8, *newStr)
            EndIf
         EndIf
      Next
   EndIf

   ; Add to list
   LastElement(*gVar(varSlot)\var(0)\ll())
   AddElement(*gVar(varSlot)\var(0)\ll())
   *gVar(varSlot)\var(0)\ll()\ptr = *destMem

   pc + 1
EndProcedure

; LIST_GET_STRUCT_PTR: Get current struct from list and store to destination \ptr
; Stack: [varSlot] -> []
; _AR()\i = byte size of struct, _AR()\j = destination base slot (with local flag if local)
; V1.031.32: Check local flag for both source list and destination struct
Procedure C2LIST_GET_STRUCT_PTR()
   Protected varSlot.i, destSlot.i, byteSize.i, *srcMem, *destMem
   Protected realVarSlot.i, realDestSlot.i

   sp - 1 : varSlot = gEvalStack(sp)\i
   byteSize = _AR()\i
   destSlot = _AR()\j
   If byteSize < 8 : byteSize = 8 : EndIf

   ; V1.031.32: Check if source list is local
   If varSlot & #C2_LOCAL_COLLECTION_FLAG
      realVarSlot = varSlot & #C2_SLOT_MASK
      *srcMem = *gVar(gCurrentFuncSlot)\var(realVarSlot)\ll()\ptr
   Else
      *srcMem = *gVar(varSlot)\var(0)\ll()\ptr
   EndIf

   ; V1.031.32: Check if destination struct is local
   ; V1.035.0: POINTER ARRAY ARCHITECTURE - locals via *gVar(gCurrentFuncSlot)\var(offset)
   If destSlot & #C2_LOCAL_COLLECTION_FLAG
      ; Local destination: offset is already the local index - no gFrameBase needed
      realDestSlot = destSlot & #C2_SLOT_MASK
      *destMem = *gVar(gCurrentFuncSlot)\var(realDestSlot)\ptr
   Else
      *destMem = *gVar(destSlot)\var(0)\ptr
   EndIf

   ; Copy data if both valid
   If *srcMem And *destMem
      CopyMemory(*srcMem, *destMem, byteSize)
   EndIf

   pc + 1
EndProcedure

; MAP_PUT_STRUCT_PTR: Put struct from \ptr storage to map
; Stack: [varSlot, key, structSlot] -> []
; _AR()\i = byte size of struct
Procedure C2MAP_PUT_STRUCT_PTR()
   Protected varSlot.i, key.s, structSlot.i, byteSize.i, *srcMem, *destMem

   byteSize = _AR()\i
   If byteSize < 8 : byteSize = 8 : EndIf

   ; Pop struct slot (pushed via FETCH_STRUCT)
   sp - 1 : structSlot = gEvalStack(sp)\i
   *srcMem = gEvalStack(sp)\ptr

   ; Pop key
   sp - 1 : key = gEvalStack(sp)\ss

   ; Pop pool slot
   sp - 1 : varSlot = gEvalStack(sp)\i

   ; Free existing entry if present
   If FindMapElement(*gVar(varSlot)\var(0)\map(), key)
      If *gVar(varSlot)\var(0)\map(key)\ptr
         FreeMemory(*gVar(varSlot)\var(0)\map(key)\ptr)
      EndIf
   EndIf

   ; Allocate memory and copy
   *destMem = AllocateMemory(byteSize)
   If *destMem And *srcMem
      CopyMemory(*srcMem, *destMem, byteSize)
   EndIf

   ; Add to map
   *gVar(varSlot)\var(0)\map(key)\ptr = *destMem

   pc + 1
EndProcedure

; MAP_GET_STRUCT_PTR: Get struct from map and store to destination \ptr
; Stack: [varSlot, key] -> []
; _AR()\i = byte size of struct, _AR()\j = destination base slot
Procedure C2MAP_GET_STRUCT_PTR()
   Protected varSlot.i, key.s, destSlot.i, byteSize.i, *srcMem, *destMem

   sp - 1 : key = gEvalStack(sp)\ss
   sp - 1 : varSlot = gEvalStack(sp)\i
   byteSize = _AR()\i
   destSlot = _AR()\j
   If byteSize < 8 : byteSize = 8 : EndIf

   ; Find in map
   *srcMem = 0
   If FindMapElement(*gVar(varSlot)\var(0)\map(), key)
      *srcMem = *gVar(varSlot)\var(0)\map(key)\ptr
   EndIf

   ; Get destination pointer
   *destMem = *gVar(destSlot)\var(0)\ptr

   ; Copy data if both valid
   If *srcMem And *destMem
      CopyMemory(*srcMem, *destMem, byteSize)
   EndIf

   pc + 1
EndProcedure

; STRUCT_FREE: Free struct memory including string allocations
; _AR()\i = structSize, _AR()\n = fieldTypesSlot (for string cleanup)
; Stack: [*ptr] -> []
Procedure C2STRUCT_FREE()
   Protected *mem, structSize.i, fieldTypesSlot.i, i.i, fieldType.i, *strMem

   sp - 1 : *mem = gEvalStack(sp)\ptr
   structSize = _AR()\i
   fieldTypesSlot = _AR()\n

   If *mem
      ; Free string allocations
      For i = 0 To structSize - 1
         fieldType = *gVar(fieldTypesSlot + i)\var(0)\i
         If fieldType = 2  ; String
            *strMem = PeekI(*mem + i * 8)
            If *strMem
               FreeMemory(*strMem)
            EndIf
         EndIf
      Next
      ; Free struct memory
      FreeMemory(*mem)
   EndIf

   pc + 1
EndProcedure

; ======================================================================================================
;- Pool Compatibility Stubs (V2: No pools needed)
; ======================================================================================================

; V2: No pool management needed - PureBasic handles List/Map memory automatically

Procedure InitListPool()
   ; V2: No-op - lists are embedded in gVar
EndProcedure

Procedure InitMapPool()
   ; V2: No-op - maps are embedded in gVar
EndProcedure

Procedure ResetCollections()
   ; V2: Collections are embedded in gVar
   ; Individual lists/maps should be cleared when gVar is reset
   ; ClearList/ClearMap in NEW operations handle initialization
EndProcedure

; ======================================================================================================
;- Struct Memory Helpers for Lists/Maps
; ======================================================================================================

; Helper: Allocate memory for struct and copy fields
; Used when adding a struct to a list/map
; Returns: pointer to allocated memory block
Procedure.i AllocateStructCopy(baseSlot.i, structSize.i)
   Protected *mem, i.i

   *mem = AllocateMemory(structSize * 8)  ; 8 bytes per slot (max of i/f)
   If *mem
      ; Copy each field
      For i = 0 To structSize - 1
         PokeI(*mem + i * 8, *gVar(baseSlot + i)\var(0)\i)
         ; Note: strings need special handling - store pointer or copy
      Next
   EndIf

   ProcedureReturn *mem
EndProcedure

; Helper: Read struct field from memory
Procedure.i PeekStructFieldInt(*mem, offset.i)
   ProcedureReturn PeekI(*mem + offset * 8)
EndProcedure

Procedure.d PeekStructFieldFloat(*mem, offset.i)
   ProcedureReturn PeekD(*mem + offset * 8)
EndProcedure

; ======================================================================================================
;- V1.034.6: ForEach Opcodes - Scoped Iterator for Lists and Maps
; ======================================================================================================
; These opcodes use a stack-based iterator position, allowing nested loops on the same collection.
; The iterator index is stored on the VM evaluation stack, not in the list/map itself.
; This solves the test 107 limitation where nested functions corrupted the shared iterator.

; FOREACH_LIST_INIT: Initialize list iterator on stack
; Instruction \i = varSlot (from codegen)
; Stack: [] -> [iter]
; Pushes initial iterator value (-1 = before first element)
Procedure C2FOREACH_LIST_INIT()
   gEvalStack(sp)\i = -1  ; Iterator starts at -1 (before first)
   sp + 1
   pc + 1
EndProcedure

; FOREACH_LIST_NEXT: Advance list iterator, push success
; Instruction \i = varSlot (from codegen via postprocessor or from INIT)
; Stack: [iter] -> [iter', success]
; Increments iterator in-place, positions list at that element, pushes 1 (success) or 0 (end)
Procedure C2FOREACH_LIST_NEXT()
   Protected varSlot.i, iter.i, realSlot.i, listLen.i, success.i

   ; Get varSlot from instruction (use _AR() macro)
   varSlot = _AR()\i

   ; Get and advance iterator from stack (update in-place)
   iter = gEvalStack(sp - 1)\i + 1
   gEvalStack(sp - 1)\i = iter

   ; Get list size and position list at current element
   success = 0
   If varSlot & #C2_LOCAL_COLLECTION_FLAG
      realSlot = varSlot & #C2_SLOT_MASK
      listLen = ListSize(*gVar(gCurrentFuncSlot)\var(realSlot)\ll())
      If iter < listLen
         SelectElement(*gVar(gCurrentFuncSlot)\var(realSlot)\ll(), iter)
         success = 1
      EndIf
   Else
      listLen = ListSize(*gVar(varSlot)\var(0)\ll())
      If iter < listLen
         SelectElement(*gVar(varSlot)\var(0)\ll(), iter)
         success = 1
      EndIf
   EndIf

   ; Push success
   gEvalStack(sp)\i = success
   sp + 1

   pc + 1
EndProcedure

; FOREACH_MAP_INIT: Initialize map iterator on stack
; Instruction \i = varSlot
; Stack: [] -> [iter]
Procedure C2FOREACH_MAP_INIT()
   gEvalStack(sp)\i = -1  ; Iterator starts at -1 (before first)
   sp + 1
   pc + 1
EndProcedure

; FOREACH_MAP_NEXT: Advance map iterator, push success
; Instruction \i = varSlot
; Stack: [iter] -> [iter', success]
Procedure C2FOREACH_MAP_NEXT()
   Protected varSlot.i, iter.i, realSlot.i, success.i

   ; Get varSlot from instruction (use _AR() macro)
   varSlot = _AR()\i

   ; Get current iterator
   iter = gEvalStack(sp - 1)\i

   ; For iter = -1, we need to reset and get first
   ; For iter >= 0, we need to advance to next
   If varSlot & #C2_LOCAL_COLLECTION_FLAG
      realSlot = varSlot & #C2_SLOT_MASK
      If iter = -1
         ResetMap(*gVar(gCurrentFuncSlot)\var(realSlot)\map())
      EndIf
      success = NextMapElement(*gVar(gCurrentFuncSlot)\var(realSlot)\map())
   Else
      If iter = -1
         ResetMap(*gVar(varSlot)\var(0)\map())
      EndIf
      success = NextMapElement(*gVar(varSlot)\var(0)\map())
   EndIf

   ; Increment iterator in-place
   gEvalStack(sp - 1)\i = iter + 1

   ; Push success
   gEvalStack(sp)\i = success
   sp + 1

   pc + 1
EndProcedure

; FOREACH_END: Cleanup - pop iterator from stack
; Stack: [iter] -> []
Procedure C2FOREACH_END()
   sp - 1  ; Pop and discard iterator
   pc + 1
EndProcedure

; FOREACH_LIST_GET_INT: Get list element at stack iterator position
; Instruction \i = varSlot
; Stack: [iter] -> [iter, value]
; Uses SelectElement to position by index, then reads value
Procedure C2FOREACH_LIST_GET_INT()
   Protected varSlot.i, iter.i, realSlot.i, val.i

   ; Get varSlot from instruction, iter from stack
   varSlot = _AR()\i
   iter = gEvalStack(sp - 1)\i

   val = 0
   If varSlot & #C2_LOCAL_COLLECTION_FLAG
      realSlot = varSlot & #C2_SLOT_MASK
      If SelectElement(*gVar(gCurrentFuncSlot)\var(realSlot)\ll(), iter)
         val = *gVar(gCurrentFuncSlot)\var(realSlot)\ll()\i
      EndIf
   Else
      If SelectElement(*gVar(varSlot)\var(0)\ll(), iter)
         val = *gVar(varSlot)\var(0)\ll()\i
      EndIf
   EndIf

   gEvalStack(sp)\i = val
   sp + 1
   pc + 1
EndProcedure

; FOREACH_LIST_GET_FLOAT: Get list float element at stack iterator position
; Instruction \i = varSlot
Procedure C2FOREACH_LIST_GET_FLOAT()
   Protected varSlot.i, iter.i, realSlot.i, val.d

   varSlot = _AR()\i
   iter = gEvalStack(sp - 1)\i

   val = 0.0
   If varSlot & #C2_LOCAL_COLLECTION_FLAG
      realSlot = varSlot & #C2_SLOT_MASK
      If SelectElement(*gVar(gCurrentFuncSlot)\var(realSlot)\ll(), iter)
         val = *gVar(gCurrentFuncSlot)\var(realSlot)\ll()\f
      EndIf
   Else
      If SelectElement(*gVar(varSlot)\var(0)\ll(), iter)
         val = *gVar(varSlot)\var(0)\ll()\f
      EndIf
   EndIf

   gEvalStack(sp)\f = val
   sp + 1
   pc + 1
EndProcedure

; FOREACH_LIST_GET_STR: Get list string element at stack iterator position
; Instruction \i = varSlot
Procedure C2FOREACH_LIST_GET_STR()
   Protected varSlot.i, iter.i, realSlot.i, val.s

   varSlot = _AR()\i
   iter = gEvalStack(sp - 1)\i

   val = ""
   If varSlot & #C2_LOCAL_COLLECTION_FLAG
      realSlot = varSlot & #C2_SLOT_MASK
      If SelectElement(*gVar(gCurrentFuncSlot)\var(realSlot)\ll(), iter)
         val = *gVar(gCurrentFuncSlot)\var(realSlot)\ll()\ss
      EndIf
   Else
      If SelectElement(*gVar(varSlot)\var(0)\ll(), iter)
         val = *gVar(varSlot)\var(0)\ll()\ss
      EndIf
   EndIf

   gEvalStack(sp)\ss = val
   sp + 1
   pc + 1
EndProcedure

; FOREACH_MAP_KEY: Get current map key (map iterator maintained internally)
; Instruction \i = varSlot
; Stack: [iter] -> [iter, key]
Procedure C2FOREACH_MAP_KEY()
   Protected varSlot.i, realSlot.i, key.s

   varSlot = _AR()\i

   If varSlot & #C2_LOCAL_COLLECTION_FLAG
      realSlot = varSlot & #C2_SLOT_MASK
      key = MapKey(*gVar(gCurrentFuncSlot)\var(realSlot)\map())
   Else
      key = MapKey(*gVar(varSlot)\var(0)\map())
   EndIf

   gEvalStack(sp)\ss = key
   sp + 1
   pc + 1
EndProcedure

; FOREACH_MAP_VALUE_INT: Get current map int value
; Instruction \i = varSlot
Procedure C2FOREACH_MAP_VALUE_INT()
   Protected varSlot.i, realSlot.i, val.i

   varSlot = _AR()\i

   If varSlot & #C2_LOCAL_COLLECTION_FLAG
      realSlot = varSlot & #C2_SLOT_MASK
      val = *gVar(gCurrentFuncSlot)\var(realSlot)\map()\i
   Else
      val = *gVar(varSlot)\var(0)\map()\i
   EndIf

   gEvalStack(sp)\i = val
   sp + 1
   pc + 1
EndProcedure

; FOREACH_MAP_VALUE_FLOAT: Get current map float value
; Instruction \i = varSlot
Procedure C2FOREACH_MAP_VALUE_FLOAT()
   Protected varSlot.i, realSlot.i, val.d

   varSlot = _AR()\i

   If varSlot & #C2_LOCAL_COLLECTION_FLAG
      realSlot = varSlot & #C2_SLOT_MASK
      val = *gVar(gCurrentFuncSlot)\var(realSlot)\map()\f
   Else
      val = *gVar(varSlot)\var(0)\map()\f
   EndIf

   gEvalStack(sp)\f = val
   sp + 1
   pc + 1
EndProcedure

; FOREACH_MAP_VALUE_STR: Get current map string value
; Instruction \i = varSlot
Procedure C2FOREACH_MAP_VALUE_STR()
   Protected varSlot.i, realSlot.i, val.s

   varSlot = _AR()\i

   If varSlot & #C2_LOCAL_COLLECTION_FLAG
      realSlot = varSlot & #C2_SLOT_MASK
      val = *gVar(gCurrentFuncSlot)\var(realSlot)\map()\ss
   Else
      val = *gVar(varSlot)\var(0)\map()\ss
   EndIf

   gEvalStack(sp)\ss = val
   sp + 1
   pc + 1
EndProcedure

; ======================================================================================================
;- End of Collections V2
; ======================================================================================================

; IDE Options = PureBasic 6.21 (Windows - x64)
; EnableThread
; EnableXP
