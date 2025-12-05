; ======================================================================================================
; c2-collections-v01.pbi - Collection Operations (Lists and Maps) for LJ2 VM
; ======================================================================================================
; V1.026.3 - LinkedLists and Maps using PureBasic runtime functions
; V1.026.8 - Typed opcodes: pool slot popped from stack (via FETCH/LFETCH)
;            No gVar lookup needed in VM - faster execution
;            Supports local list/map variables via LFETCH
; SpiderBasic compatible - uses pool approach for both lists and maps
;
; Lists: Pre-allocated pool (gListPool) with PureBasic LinkedList functions
;        gVar[slot].i = pool index (or LOCAL[offset] for locals)
;        Uses AddElement(), FirstElement(), NextElement(), etc.
;
; Maps:  Pre-allocated pool (gMapPool) with PureBasic Map functions
;        gVar[slot].i = pool index (or LOCAL[offset] for locals)
;        Uses FindMapElement(), NextMapElement(), MapKey(), etc.
;
; Kingwolf71 December/2025
; ======================================================================================================

; ======================================================================================================
;- List Pool Structure (SpiderBasic Compatible)
; ======================================================================================================

Structure stListPool
   inUse.b                        ; Is this pool slot in use?
   valueType.w                    ; Value type: #C2FLAG_INT, #C2FLAG_FLOAT, #C2FLAG_STR
   List dataInt.i()               ; Integer list storage
   List dataFloat.d()             ; Float list storage
   List dataStr.s()               ; String list storage
EndStructure

; Global list pool - allocated once, reused
Global Dim gListPool.stListPool(#C2_DEFAULT_MAX_MAPS - 1)
Global gMaxLists.i = #C2_DEFAULT_MAX_MAPS
Global gNextListSlot.i = 0

; ======================================================================================================
;- Map Pool Structure (SpiderBasic Compatible)
; ======================================================================================================

Structure stMapPool
   inUse.b                        ; Is this pool slot in use?
   valueType.w                    ; Value type: #C2FLAG_INT, #C2FLAG_FLOAT, #C2FLAG_STR
   currentKey.s                   ; Current iterator key
   Map dataInt.i()                ; Integer value storage
   Map dataFloat.d()              ; Float value storage
   Map dataStr.s()                ; String value storage
EndStructure

; Global map pool - allocated once, reused
Global Dim gMapPool.stMapPool(#C2_DEFAULT_MAX_MAPS - 1)
Global gMaxMaps.i = #C2_DEFAULT_MAX_MAPS
Global gNextMapSlot.i = 0

; ======================================================================================================
;- List Pool Management
; ======================================================================================================

Procedure InitListPool()
   Protected i.i
   For i = 0 To gMaxLists - 1
      gListPool(i)\inUse = #False
      gListPool(i)\valueType = 0
      ClearList(gListPool(i)\dataInt())
      ClearList(gListPool(i)\dataFloat())
      ClearList(gListPool(i)\dataStr())
   Next
   gNextListSlot = 0
EndProcedure

Procedure.i AllocateListSlot()
   Protected i.i, startSlot.i, checkSlot.i
   startSlot = gNextListSlot

   For i = 0 To gMaxLists - 1
      checkSlot = (startSlot + i) % gMaxLists
      If gListPool(checkSlot)\inUse = #False
         gListPool(checkSlot)\inUse = #True
         gNextListSlot = (checkSlot + 1) % gMaxLists
         ProcedureReturn checkSlot
      EndIf
   Next

   ProcedureReturn -1
EndProcedure

Procedure FreeListSlot(poolSlot.i)
   If poolSlot >= 0 And poolSlot < gMaxLists
      ClearList(gListPool(poolSlot)\dataInt())
      ClearList(gListPool(poolSlot)\dataFloat())
      ClearList(gListPool(poolSlot)\dataStr())
      gListPool(poolSlot)\inUse = #False
      gListPool(poolSlot)\valueType = 0
   EndIf
EndProcedure

; ======================================================================================================
;- Map Pool Management
; ======================================================================================================

Procedure InitMapPool()
   Protected i.i
   For i = 0 To gMaxMaps - 1
      gMapPool(i)\inUse = #False
      gMapPool(i)\valueType = 0
      gMapPool(i)\currentKey = ""
      ClearMap(gMapPool(i)\dataInt())
      ClearMap(gMapPool(i)\dataFloat())
      ClearMap(gMapPool(i)\dataStr())
   Next
   gNextMapSlot = 0
EndProcedure

Procedure.i AllocateMapSlot()
   Protected i.i, startSlot.i, checkSlot.i
   startSlot = gNextMapSlot

   For i = 0 To gMaxMaps - 1
      checkSlot = (startSlot + i) % gMaxMaps
      If gMapPool(checkSlot)\inUse = #False
         gMapPool(checkSlot)\inUse = #True
         gNextMapSlot = (checkSlot + 1) % gMaxMaps
         ProcedureReturn checkSlot
      EndIf
   Next

   ProcedureReturn -1
EndProcedure

Procedure FreeMapSlot(poolSlot.i)
   If poolSlot >= 0 And poolSlot < gMaxMaps
      ClearMap(gMapPool(poolSlot)\dataInt())
      ClearMap(gMapPool(poolSlot)\dataFloat())
      ClearMap(gMapPool(poolSlot)\dataStr())
      gMapPool(poolSlot)\inUse = #False
      gMapPool(poolSlot)\valueType = 0
      gMapPool(poolSlot)\currentKey = ""
   EndIf
EndProcedure

; ======================================================================================================
;- List VM Operations (using PureBasic LinkedList functions)
; ======================================================================================================

; LIST_NEW: Create new list at gVar[slot] or LOCAL[offset]
; V1.026.19: \n = isLocal flag - if 1, store to local variable instead of global
Procedure C2LIST_NEW()
   Protected slot.i, valueType.i, poolSlot.i, isLocal.i, targetSlot.i

   slot = _AR()\i
   valueType = _AR()\j
   isLocal = _AR()\n
   poolSlot = AllocateListSlot()

   If poolSlot >= 0
      gListPool(poolSlot)\valueType = valueType
      If isLocal
         ; Store to local variable: gVar[localSlotStart + offset]
         targetSlot = gStack(gStackDepth)\localSlotStart + slot
         gVar(targetSlot)\i = poolSlot
      Else
         ; Store to global variable
         gVar(slot)\i = poolSlot
      EndIf
   Else
      If isLocal
         targetSlot = gStack(gStackDepth)\localSlotStart + slot
         gVar(targetSlot)\i = -1
      Else
         gVar(slot)\i = -1
      EndIf
   EndIf

   pc + 1
EndProcedure

; LIST_ADD: Add element to end of list
; Stack: [slot, value]
Procedure C2LIST_ADD()
   Protected slot.i, poolSlot.i, valueType.i
   Protected valI.i, valF.d, valS.s

   ; Pop value first
   sp - 1
   valI = gVar(sp)\i
   valF = gVar(sp)\f
   valS = gVar(sp)\ss

   ; Pop slot
   sp - 1
   slot = gVar(sp)\i

   poolSlot = gVar(slot)\i

   If poolSlot >= 0 And poolSlot < gMaxLists And gListPool(poolSlot)\inUse
      valueType = gListPool(poolSlot)\valueType

      If valueType = #C2FLAG_FLOAT
         LastElement(gListPool(poolSlot)\dataFloat())
         AddElement(gListPool(poolSlot)\dataFloat())
         gListPool(poolSlot)\dataFloat() = valF
      ElseIf valueType = #C2FLAG_STR
         LastElement(gListPool(poolSlot)\dataStr())
         AddElement(gListPool(poolSlot)\dataStr())
         gListPool(poolSlot)\dataStr() = valS
      Else
         LastElement(gListPool(poolSlot)\dataInt())
         AddElement(gListPool(poolSlot)\dataInt())
         gListPool(poolSlot)\dataInt() = valI
      EndIf
   EndIf

   pc + 1
EndProcedure

; LIST_INSERT: Insert element at current position
; Stack: [slot, value]
Procedure C2LIST_INSERT()
   Protected slot.i, poolSlot.i, valueType.i
   Protected valI.i, valF.d, valS.s

   ; Pop value first
   sp - 1
   valI = gVar(sp)\i
   valF = gVar(sp)\f
   valS = gVar(sp)\ss

   ; Pop slot
   sp - 1
   slot = gVar(sp)\i

   poolSlot = gVar(slot)\i

   If poolSlot >= 0 And poolSlot < gMaxLists And gListPool(poolSlot)\inUse
      valueType = gListPool(poolSlot)\valueType

      If valueType = #C2FLAG_FLOAT
         InsertElement(gListPool(poolSlot)\dataFloat())
         gListPool(poolSlot)\dataFloat() = valF
      ElseIf valueType = #C2FLAG_STR
         InsertElement(gListPool(poolSlot)\dataStr())
         gListPool(poolSlot)\dataStr() = valS
      Else
         InsertElement(gListPool(poolSlot)\dataInt())
         gListPool(poolSlot)\dataInt() = valI
      EndIf
   EndIf

   pc + 1
EndProcedure

; LIST_DELETE: Delete element at current position
; Stack: [slot]
Procedure C2LIST_DELETE()
   Protected slot.i, poolSlot.i, valueType.i

   sp - 1
   slot = gVar(sp)\i

   poolSlot = gVar(slot)\i

   If poolSlot >= 0 And poolSlot < gMaxLists And gListPool(poolSlot)\inUse
      valueType = gListPool(poolSlot)\valueType

      If valueType = #C2FLAG_FLOAT
         DeleteElement(gListPool(poolSlot)\dataFloat())
      ElseIf valueType = #C2FLAG_STR
         DeleteElement(gListPool(poolSlot)\dataStr())
      Else
         DeleteElement(gListPool(poolSlot)\dataInt())
      EndIf
   EndIf

   pc + 1
EndProcedure

; LIST_CLEAR: Clear all elements
; Stack: [slot]
Procedure C2LIST_CLEAR()
   Protected slot.i, poolSlot.i, valueType.i

   sp - 1
   slot = gVar(sp)\i

   poolSlot = gVar(slot)\i

   If poolSlot >= 0 And poolSlot < gMaxLists And gListPool(poolSlot)\inUse
      valueType = gListPool(poolSlot)\valueType

      If valueType = #C2FLAG_FLOAT
         ClearList(gListPool(poolSlot)\dataFloat())
      ElseIf valueType = #C2FLAG_STR
         ClearList(gListPool(poolSlot)\dataStr())
      Else
         ClearList(gListPool(poolSlot)\dataInt())
      EndIf
   EndIf

   pc + 1
EndProcedure

; LIST_SIZE: Push list size
; Stack: [slot] -> [size]
Procedure C2LIST_SIZE()
   Protected slot.i, poolSlot.i, valueType.i

   sp - 1
   slot = gVar(sp)\i

   poolSlot = gVar(slot)\i

   If poolSlot >= 0 And poolSlot < gMaxLists And gListPool(poolSlot)\inUse
      valueType = gListPool(poolSlot)\valueType

      If valueType = #C2FLAG_FLOAT
         gVar(sp)\i = ListSize(gListPool(poolSlot)\dataFloat())
      ElseIf valueType = #C2FLAG_STR
         gVar(sp)\i = ListSize(gListPool(poolSlot)\dataStr())
      Else
         gVar(sp)\i = ListSize(gListPool(poolSlot)\dataInt())
      EndIf
   Else
      gVar(sp)\i = 0
   EndIf
   sp + 1

   pc + 1
EndProcedure

; LIST_FIRST: Move to first element, push success
; Stack: [slot] -> [success]
Procedure C2LIST_FIRST()
   Protected slot.i, poolSlot.i, valueType.i, success.i

   sp - 1
   slot = gVar(sp)\i

   poolSlot = gVar(slot)\i
   success = 0

   If poolSlot >= 0 And poolSlot < gMaxLists And gListPool(poolSlot)\inUse
      valueType = gListPool(poolSlot)\valueType

      If valueType = #C2FLAG_FLOAT
         If FirstElement(gListPool(poolSlot)\dataFloat())
            success = 1
         EndIf
      ElseIf valueType = #C2FLAG_STR
         If FirstElement(gListPool(poolSlot)\dataStr())
            success = 1
         EndIf
      Else
         If FirstElement(gListPool(poolSlot)\dataInt())
            success = 1
         EndIf
      EndIf
   EndIf

   gVar(sp)\i = success
   sp + 1
   pc + 1
EndProcedure

; LIST_LAST: Move to last element, push success
; Stack: [slot] -> [success]
Procedure C2LIST_LAST()
   Protected slot.i, poolSlot.i, valueType.i, success.i

   sp - 1
   slot = gVar(sp)\i

   poolSlot = gVar(slot)\i
   success = 0

   If poolSlot >= 0 And poolSlot < gMaxLists And gListPool(poolSlot)\inUse
      valueType = gListPool(poolSlot)\valueType

      If valueType = #C2FLAG_FLOAT
         If LastElement(gListPool(poolSlot)\dataFloat())
            success = 1
         EndIf
      ElseIf valueType = #C2FLAG_STR
         If LastElement(gListPool(poolSlot)\dataStr())
            success = 1
         EndIf
      Else
         If LastElement(gListPool(poolSlot)\dataInt())
            success = 1
         EndIf
      EndIf
   EndIf

   gVar(sp)\i = success
   sp + 1
   pc + 1
EndProcedure

; LIST_NEXT: Move to next element, push success
; Stack: [slot] -> [success]
Procedure C2LIST_NEXT()
   Protected slot.i, poolSlot.i, valueType.i, success.i

   sp - 1
   slot = gVar(sp)\i

   poolSlot = gVar(slot)\i
   success = 0

   If poolSlot >= 0 And poolSlot < gMaxLists And gListPool(poolSlot)\inUse
      valueType = gListPool(poolSlot)\valueType

      If valueType = #C2FLAG_FLOAT
         If NextElement(gListPool(poolSlot)\dataFloat())
            success = 1
         EndIf
      ElseIf valueType = #C2FLAG_STR
         If NextElement(gListPool(poolSlot)\dataStr())
            success = 1
         EndIf
      Else
         If NextElement(gListPool(poolSlot)\dataInt())
            success = 1
         EndIf
      EndIf
   EndIf

   gVar(sp)\i = success
   sp + 1
   pc + 1
EndProcedure

; LIST_PREV: Move to previous element, push success
; Stack: [slot] -> [success]
Procedure C2LIST_PREV()
   Protected slot.i, poolSlot.i, valueType.i, success.i

   sp - 1
   slot = gVar(sp)\i

   poolSlot = gVar(slot)\i
   success = 0

   If poolSlot >= 0 And poolSlot < gMaxLists And gListPool(poolSlot)\inUse
      valueType = gListPool(poolSlot)\valueType

      If valueType = #C2FLAG_FLOAT
         If PreviousElement(gListPool(poolSlot)\dataFloat())
            success = 1
         EndIf
      ElseIf valueType = #C2FLAG_STR
         If PreviousElement(gListPool(poolSlot)\dataStr())
            success = 1
         EndIf
      Else
         If PreviousElement(gListPool(poolSlot)\dataInt())
            success = 1
         EndIf
      EndIf
   EndIf

   gVar(sp)\i = success
   sp + 1
   pc + 1
EndProcedure

; LIST_SELECT: Select element by index
; Stack: [slot, index] -> [success]
Procedure C2LIST_SELECT()
   Protected slot.i, poolSlot.i, valueType.i, idx.i, success.i

   ; Pop index first
   sp - 1
   idx = gVar(sp)\i

   ; Pop slot
   sp - 1
   slot = gVar(sp)\i

   poolSlot = gVar(slot)\i
   success = 0

   If poolSlot >= 0 And poolSlot < gMaxLists And gListPool(poolSlot)\inUse
      valueType = gListPool(poolSlot)\valueType

      If valueType = #C2FLAG_FLOAT
         If SelectElement(gListPool(poolSlot)\dataFloat(), idx)
            success = 1
         EndIf
      ElseIf valueType = #C2FLAG_STR
         If SelectElement(gListPool(poolSlot)\dataStr(), idx)
            success = 1
         EndIf
      Else
         If SelectElement(gListPool(poolSlot)\dataInt(), idx)
            success = 1
         EndIf
      EndIf
   EndIf

   gVar(sp)\i = success
   sp + 1
   pc + 1
EndProcedure

; LIST_INDEX: Push current index
; Stack: [slot] -> [index]
Procedure C2LIST_INDEX()
   Protected slot.i, poolSlot.i, valueType.i

   sp - 1
   slot = gVar(sp)\i

   poolSlot = gVar(slot)\i

   If poolSlot >= 0 And poolSlot < gMaxLists And gListPool(poolSlot)\inUse
      valueType = gListPool(poolSlot)\valueType

      If valueType = #C2FLAG_FLOAT
         gVar(sp)\i = ListIndex(gListPool(poolSlot)\dataFloat())
      ElseIf valueType = #C2FLAG_STR
         gVar(sp)\i = ListIndex(gListPool(poolSlot)\dataStr())
      Else
         gVar(sp)\i = ListIndex(gListPool(poolSlot)\dataInt())
      EndIf
   Else
      gVar(sp)\i = -1
   EndIf
   sp + 1

   pc + 1
EndProcedure

; LIST_GET: Push current element value
; Stack: [slot] -> [value]
Procedure C2LIST_GET()
   Protected slot.i, poolSlot.i, valueType.i

   sp - 1
   slot = gVar(sp)\i

   poolSlot = gVar(slot)\i

   If poolSlot >= 0 And poolSlot < gMaxLists And gListPool(poolSlot)\inUse
      valueType = gListPool(poolSlot)\valueType

      If valueType = #C2FLAG_FLOAT
         If ListIndex(gListPool(poolSlot)\dataFloat()) >= 0
            gVar(sp)\f = gListPool(poolSlot)\dataFloat()
         Else
            gVar(sp)\f = 0.0
         EndIf
      ElseIf valueType = #C2FLAG_STR
         If ListIndex(gListPool(poolSlot)\dataStr()) >= 0
            gVar(sp)\ss = gListPool(poolSlot)\dataStr()
         Else
            gVar(sp)\ss = ""
         EndIf
      Else
         If ListIndex(gListPool(poolSlot)\dataInt()) >= 0
            gVar(sp)\i = gListPool(poolSlot)\dataInt()
         Else
            gVar(sp)\i = 0
         EndIf
      EndIf
   Else
      gVar(sp)\i = 0
   EndIf
   sp + 1

   pc + 1
EndProcedure

; LIST_SET: Set current element value
; Stack: [slot, value]
Procedure C2LIST_SET()
   Protected slot.i, poolSlot.i, valueType.i
   Protected valI.i, valF.d, valS.s

   ; Pop value first
   sp - 1
   valI = gVar(sp)\i
   valF = gVar(sp)\f
   valS = gVar(sp)\ss

   ; Pop slot
   sp - 1
   slot = gVar(sp)\i

   poolSlot = gVar(slot)\i

   If poolSlot >= 0 And poolSlot < gMaxLists And gListPool(poolSlot)\inUse
      valueType = gListPool(poolSlot)\valueType

      If valueType = #C2FLAG_FLOAT
         If ListIndex(gListPool(poolSlot)\dataFloat()) >= 0
            gListPool(poolSlot)\dataFloat() = valF
         EndIf
      ElseIf valueType = #C2FLAG_STR
         If ListIndex(gListPool(poolSlot)\dataStr()) >= 0
            gListPool(poolSlot)\dataStr() = valS
         EndIf
      Else
         If ListIndex(gListPool(poolSlot)\dataInt()) >= 0
            gListPool(poolSlot)\dataInt() = valI
         EndIf
      EndIf
   EndIf

   pc + 1
EndProcedure

; LIST_RESET: Reset position to before first (for iteration)
; Stack: [slot]
Procedure C2LIST_RESET()
   Protected slot.i, poolSlot.i, valueType.i

   sp - 1
   slot = gVar(sp)\i

   poolSlot = gVar(slot)\i

   If poolSlot >= 0 And poolSlot < gMaxLists And gListPool(poolSlot)\inUse
      valueType = gListPool(poolSlot)\valueType

      ; Reset to before first element by using ResetList
      If valueType = #C2FLAG_FLOAT
         ResetList(gListPool(poolSlot)\dataFloat())
      ElseIf valueType = #C2FLAG_STR
         ResetList(gListPool(poolSlot)\dataStr())
      Else
         ResetList(gListPool(poolSlot)\dataInt())
      EndIf
   EndIf

   pc + 1
EndProcedure

; LIST_SORT: Sort list elements
; Stack: [slot, ascending]
Procedure C2LIST_SORT()
   Protected slot.i, poolSlot.i, valueType.i, ascending.i

   ; Pop ascending flag
   sp - 1
   ascending = gVar(sp)\i

   ; Pop slot
   sp - 1
   slot = gVar(sp)\i

   poolSlot = gVar(slot)\i

   If poolSlot >= 0 And poolSlot < gMaxLists And gListPool(poolSlot)\inUse
      valueType = gListPool(poolSlot)\valueType

      If valueType = #C2FLAG_FLOAT
         If ascending
            SortList(gListPool(poolSlot)\dataFloat(), #PB_Sort_Ascending)
         Else
            SortList(gListPool(poolSlot)\dataFloat(), #PB_Sort_Descending)
         EndIf
      ElseIf valueType = #C2FLAG_STR
         If ascending
            SortList(gListPool(poolSlot)\dataStr(), #PB_Sort_Ascending)
         Else
            SortList(gListPool(poolSlot)\dataStr(), #PB_Sort_Descending)
         EndIf
      Else
         If ascending
            SortList(gListPool(poolSlot)\dataInt(), #PB_Sort_Ascending)
         Else
            SortList(gListPool(poolSlot)\dataInt(), #PB_Sort_Descending)
         EndIf
      EndIf
   EndIf

   pc + 1
EndProcedure

; ======================================================================================================
;- V1.026.8: Typed List Operations - Pool slot popped directly from stack
;  No gVar lookup needed, faster execution, works with locals via LFETCH
; ======================================================================================================

; LIST_ADD_INT: Add integer element
; Stack: [poolSlot, value] -> []
Procedure C2LIST_ADD_INT()
   Protected poolSlot.i, val.i

   sp - 1 : val = gVar(sp)\i
   sp - 1 : poolSlot = gVar(sp)\i

   If poolSlot >= 0 And poolSlot < gMaxLists And gListPool(poolSlot)\inUse
      LastElement(gListPool(poolSlot)\dataInt())
      AddElement(gListPool(poolSlot)\dataInt())
      gListPool(poolSlot)\dataInt() = val
   EndIf

   pc + 1
EndProcedure

; LIST_ADD_FLOAT: Add float element
; Stack: [poolSlot, value] -> []
Procedure C2LIST_ADD_FLOAT()
   Protected poolSlot.i, val.d

   sp - 1 : val = gVar(sp)\f
   sp - 1 : poolSlot = gVar(sp)\i

   If poolSlot >= 0 And poolSlot < gMaxLists And gListPool(poolSlot)\inUse
      LastElement(gListPool(poolSlot)\dataFloat())
      AddElement(gListPool(poolSlot)\dataFloat())
      gListPool(poolSlot)\dataFloat() = val
   EndIf

   pc + 1
EndProcedure

; LIST_ADD_STR: Add string element
; Stack: [poolSlot, value] -> []
Procedure C2LIST_ADD_STR()
   Protected poolSlot.i, val.s

   sp - 1 : val = gVar(sp)\ss
   sp - 1 : poolSlot = gVar(sp)\i

   If poolSlot >= 0 And poolSlot < gMaxLists And gListPool(poolSlot)\inUse
      LastElement(gListPool(poolSlot)\dataStr())
      AddElement(gListPool(poolSlot)\dataStr())
      gListPool(poolSlot)\dataStr() = val
   EndIf

   pc + 1
EndProcedure

; LIST_INSERT_INT: Insert integer at current position
; Stack: [poolSlot, value] -> []
Procedure C2LIST_INSERT_INT()
   Protected poolSlot.i, val.i

   sp - 1 : val = gVar(sp)\i
   sp - 1 : poolSlot = gVar(sp)\i

   If poolSlot >= 0 And poolSlot < gMaxLists And gListPool(poolSlot)\inUse
      InsertElement(gListPool(poolSlot)\dataInt())
      gListPool(poolSlot)\dataInt() = val
   EndIf

   pc + 1
EndProcedure

; LIST_INSERT_FLOAT: Insert float at current position
; Stack: [poolSlot, value] -> []
Procedure C2LIST_INSERT_FLOAT()
   Protected poolSlot.i, val.d

   sp - 1 : val = gVar(sp)\f
   sp - 1 : poolSlot = gVar(sp)\i

   If poolSlot >= 0 And poolSlot < gMaxLists And gListPool(poolSlot)\inUse
      InsertElement(gListPool(poolSlot)\dataFloat())
      gListPool(poolSlot)\dataFloat() = val
   EndIf

   pc + 1
EndProcedure

; LIST_INSERT_STR: Insert string at current position
; Stack: [poolSlot, value] -> []
Procedure C2LIST_INSERT_STR()
   Protected poolSlot.i, val.s

   sp - 1 : val = gVar(sp)\ss
   sp - 1 : poolSlot = gVar(sp)\i

   If poolSlot >= 0 And poolSlot < gMaxLists And gListPool(poolSlot)\inUse
      InsertElement(gListPool(poolSlot)\dataStr())
      gListPool(poolSlot)\dataStr() = val
   EndIf

   pc + 1
EndProcedure

; LIST_GET_INT: Get current integer element
; Stack: [poolSlot] -> [value]
Procedure C2LIST_GET_INT()
   Protected poolSlot.i

   sp - 1 : poolSlot = gVar(sp)\i

   If poolSlot >= 0 And poolSlot < gMaxLists And gListPool(poolSlot)\inUse
      If ListIndex(gListPool(poolSlot)\dataInt()) >= 0
         gVar(sp)\i = gListPool(poolSlot)\dataInt()
      Else
         gVar(sp)\i = 0
      EndIf
   Else
      gVar(sp)\i = 0
   EndIf
   sp + 1

   pc + 1
EndProcedure

; LIST_GET_FLOAT: Get current float element
; Stack: [poolSlot] -> [value]
Procedure C2LIST_GET_FLOAT()
   Protected poolSlot.i

   sp - 1 : poolSlot = gVar(sp)\i

   If poolSlot >= 0 And poolSlot < gMaxLists And gListPool(poolSlot)\inUse
      If ListIndex(gListPool(poolSlot)\dataFloat()) >= 0
         gVar(sp)\f = gListPool(poolSlot)\dataFloat()
      Else
         gVar(sp)\f = 0.0
      EndIf
   Else
      gVar(sp)\f = 0.0
   EndIf
   sp + 1

   pc + 1
EndProcedure

; LIST_GET_STR: Get current string element
; Stack: [poolSlot] -> [value]
Procedure C2LIST_GET_STR()
   Protected poolSlot.i

   sp - 1 : poolSlot = gVar(sp)\i

   If poolSlot >= 0 And poolSlot < gMaxLists And gListPool(poolSlot)\inUse
      If ListIndex(gListPool(poolSlot)\dataStr()) >= 0
         gVar(sp)\ss = gListPool(poolSlot)\dataStr()
      Else
         gVar(sp)\ss = ""
      EndIf
   Else
      gVar(sp)\ss = ""
   EndIf
   sp + 1

   pc + 1
EndProcedure

; LIST_SET_INT: Set current integer element
; Stack: [poolSlot, value] -> []
Procedure C2LIST_SET_INT()
   Protected poolSlot.i, val.i

   sp - 1 : val = gVar(sp)\i
   sp - 1 : poolSlot = gVar(sp)\i

   If poolSlot >= 0 And poolSlot < gMaxLists And gListPool(poolSlot)\inUse
      If ListIndex(gListPool(poolSlot)\dataInt()) >= 0
         gListPool(poolSlot)\dataInt() = val
      EndIf
   EndIf

   pc + 1
EndProcedure

; LIST_SET_FLOAT: Set current float element
; Stack: [poolSlot, value] -> []
Procedure C2LIST_SET_FLOAT()
   Protected poolSlot.i, val.d

   sp - 1 : val = gVar(sp)\f
   sp - 1 : poolSlot = gVar(sp)\i

   If poolSlot >= 0 And poolSlot < gMaxLists And gListPool(poolSlot)\inUse
      If ListIndex(gListPool(poolSlot)\dataFloat()) >= 0
         gListPool(poolSlot)\dataFloat() = val
      EndIf
   EndIf

   pc + 1
EndProcedure

; LIST_SET_STR: Set current string element
; Stack: [poolSlot, value] -> []
Procedure C2LIST_SET_STR()
   Protected poolSlot.i, val.s

   sp - 1 : val = gVar(sp)\ss
   sp - 1 : poolSlot = gVar(sp)\i

   If poolSlot >= 0 And poolSlot < gMaxLists And gListPool(poolSlot)\inUse
      If ListIndex(gListPool(poolSlot)\dataStr()) >= 0
         gListPool(poolSlot)\dataStr() = val
      EndIf
   EndIf

   pc + 1
EndProcedure

; ======================================================================================================
;- V1.026.8: Typed operations for non-value list ops (pool slot direct from stack)
;  These still need valueType for determining which internal list to use
; ======================================================================================================

; LIST_DELETE_T: Delete current element (typed version - pool slot from stack)
; Stack: [poolSlot] -> []
Procedure C2LIST_DELETE_T()
   Protected poolSlot.i, valueType.i

   sp - 1 : poolSlot = gVar(sp)\i

   If poolSlot >= 0 And poolSlot < gMaxLists And gListPool(poolSlot)\inUse
      valueType = gListPool(poolSlot)\valueType

      If valueType = #C2FLAG_FLOAT
         DeleteElement(gListPool(poolSlot)\dataFloat())
      ElseIf valueType = #C2FLAG_STR
         DeleteElement(gListPool(poolSlot)\dataStr())
      Else
         DeleteElement(gListPool(poolSlot)\dataInt())
      EndIf
   EndIf

   pc + 1
EndProcedure

; LIST_CLEAR_T: Clear all elements (typed version - pool slot from stack)
; Stack: [poolSlot] -> []
Procedure C2LIST_CLEAR_T()
   Protected poolSlot.i, valueType.i

   sp - 1 : poolSlot = gVar(sp)\i

   If poolSlot >= 0 And poolSlot < gMaxLists And gListPool(poolSlot)\inUse
      valueType = gListPool(poolSlot)\valueType

      If valueType = #C2FLAG_FLOAT
         ClearList(gListPool(poolSlot)\dataFloat())
      ElseIf valueType = #C2FLAG_STR
         ClearList(gListPool(poolSlot)\dataStr())
      Else
         ClearList(gListPool(poolSlot)\dataInt())
      EndIf
   EndIf

   pc + 1
EndProcedure

; LIST_SIZE_T: Push list size (typed version - pool slot from stack)
; Stack: [poolSlot] -> [size]
Procedure C2LIST_SIZE_T()
   Protected poolSlot.i, valueType.i

   sp - 1 : poolSlot = gVar(sp)\i

   If poolSlot >= 0 And poolSlot < gMaxLists And gListPool(poolSlot)\inUse
      valueType = gListPool(poolSlot)\valueType

      If valueType = #C2FLAG_FLOAT
         gVar(sp)\i = ListSize(gListPool(poolSlot)\dataFloat())
      ElseIf valueType = #C2FLAG_STR
         gVar(sp)\i = ListSize(gListPool(poolSlot)\dataStr())
      Else
         gVar(sp)\i = ListSize(gListPool(poolSlot)\dataInt())
      EndIf
   Else
      gVar(sp)\i = 0
   EndIf
   sp + 1

   pc + 1
EndProcedure

; LIST_FIRST_T: Move to first element (pool slot from stack)
; Stack: [poolSlot] -> [success]
Procedure C2LIST_FIRST_T()
   Protected poolSlot.i, valueType.i, success.i

   sp - 1 : poolSlot = gVar(sp)\i
   success = 0

   If poolSlot >= 0 And poolSlot < gMaxLists And gListPool(poolSlot)\inUse
      valueType = gListPool(poolSlot)\valueType

      If valueType = #C2FLAG_FLOAT
         If FirstElement(gListPool(poolSlot)\dataFloat())
            success = 1
         EndIf
      ElseIf valueType = #C2FLAG_STR
         If FirstElement(gListPool(poolSlot)\dataStr())
            success = 1
         EndIf
      Else
         If FirstElement(gListPool(poolSlot)\dataInt())
            success = 1
         EndIf
      EndIf
   EndIf

   gVar(sp)\i = success
   sp + 1
   pc + 1
EndProcedure

; LIST_LAST_T: Move to last element (pool slot from stack)
; Stack: [poolSlot] -> [success]
Procedure C2LIST_LAST_T()
   Protected poolSlot.i, valueType.i, success.i

   sp - 1 : poolSlot = gVar(sp)\i
   success = 0

   If poolSlot >= 0 And poolSlot < gMaxLists And gListPool(poolSlot)\inUse
      valueType = gListPool(poolSlot)\valueType

      If valueType = #C2FLAG_FLOAT
         If LastElement(gListPool(poolSlot)\dataFloat())
            success = 1
         EndIf
      ElseIf valueType = #C2FLAG_STR
         If LastElement(gListPool(poolSlot)\dataStr())
            success = 1
         EndIf
      Else
         If LastElement(gListPool(poolSlot)\dataInt())
            success = 1
         EndIf
      EndIf
   EndIf

   gVar(sp)\i = success
   sp + 1
   pc + 1
EndProcedure

; LIST_NEXT_T: Move to next element (pool slot from stack)
; Stack: [poolSlot] -> [success]
Procedure C2LIST_NEXT_T()
   Protected poolSlot.i, valueType.i, success.i

   sp - 1 : poolSlot = gVar(sp)\i
   success = 0

   If poolSlot >= 0 And poolSlot < gMaxLists And gListPool(poolSlot)\inUse
      valueType = gListPool(poolSlot)\valueType

      If valueType = #C2FLAG_FLOAT
         If NextElement(gListPool(poolSlot)\dataFloat())
            success = 1
         EndIf
      ElseIf valueType = #C2FLAG_STR
         If NextElement(gListPool(poolSlot)\dataStr())
            success = 1
         EndIf
      Else
         If NextElement(gListPool(poolSlot)\dataInt())
            success = 1
         EndIf
      EndIf
   EndIf

   gVar(sp)\i = success
   sp + 1
   pc + 1
EndProcedure

; LIST_PREV_T: Move to previous element (pool slot from stack)
; Stack: [poolSlot] -> [success]
Procedure C2LIST_PREV_T()
   Protected poolSlot.i, valueType.i, success.i

   sp - 1 : poolSlot = gVar(sp)\i
   success = 0

   If poolSlot >= 0 And poolSlot < gMaxLists And gListPool(poolSlot)\inUse
      valueType = gListPool(poolSlot)\valueType

      If valueType = #C2FLAG_FLOAT
         If PreviousElement(gListPool(poolSlot)\dataFloat())
            success = 1
         EndIf
      ElseIf valueType = #C2FLAG_STR
         If PreviousElement(gListPool(poolSlot)\dataStr())
            success = 1
         EndIf
      Else
         If PreviousElement(gListPool(poolSlot)\dataInt())
            success = 1
         EndIf
      EndIf
   EndIf

   gVar(sp)\i = success
   sp + 1
   pc + 1
EndProcedure

; LIST_SELECT_T: Select element by index (pool slot from stack)
; Stack: [poolSlot, index] -> [success]
Procedure C2LIST_SELECT_T()
   Protected poolSlot.i, idx.i, valueType.i, success.i

   sp - 1 : idx = gVar(sp)\i
   sp - 1 : poolSlot = gVar(sp)\i
   success = 0

   If poolSlot >= 0 And poolSlot < gMaxLists And gListPool(poolSlot)\inUse
      valueType = gListPool(poolSlot)\valueType

      If valueType = #C2FLAG_FLOAT
         If SelectElement(gListPool(poolSlot)\dataFloat(), idx)
            success = 1
         EndIf
      ElseIf valueType = #C2FLAG_STR
         If SelectElement(gListPool(poolSlot)\dataStr(), idx)
            success = 1
         EndIf
      Else
         If SelectElement(gListPool(poolSlot)\dataInt(), idx)
            success = 1
         EndIf
      EndIf
   EndIf

   gVar(sp)\i = success
   sp + 1
   pc + 1
EndProcedure

; LIST_INDEX_T: Push current index (pool slot from stack)
; Stack: [poolSlot] -> [index]
Procedure C2LIST_INDEX_T()
   Protected poolSlot.i, valueType.i

   sp - 1 : poolSlot = gVar(sp)\i

   If poolSlot >= 0 And poolSlot < gMaxLists And gListPool(poolSlot)\inUse
      valueType = gListPool(poolSlot)\valueType

      If valueType = #C2FLAG_FLOAT
         gVar(sp)\i = ListIndex(gListPool(poolSlot)\dataFloat())
      ElseIf valueType = #C2FLAG_STR
         gVar(sp)\i = ListIndex(gListPool(poolSlot)\dataStr())
      Else
         gVar(sp)\i = ListIndex(gListPool(poolSlot)\dataInt())
      EndIf
   Else
      gVar(sp)\i = -1
   EndIf
   sp + 1

   pc + 1
EndProcedure

; LIST_RESET_T: Reset position to before first (pool slot from stack)
; Stack: [poolSlot] -> []
Procedure C2LIST_RESET_T()
   Protected poolSlot.i, valueType.i

   sp - 1 : poolSlot = gVar(sp)\i

   If poolSlot >= 0 And poolSlot < gMaxLists And gListPool(poolSlot)\inUse
      valueType = gListPool(poolSlot)\valueType

      If valueType = #C2FLAG_FLOAT
         ResetList(gListPool(poolSlot)\dataFloat())
      ElseIf valueType = #C2FLAG_STR
         ResetList(gListPool(poolSlot)\dataStr())
      Else
         ResetList(gListPool(poolSlot)\dataInt())
      EndIf
   EndIf

   pc + 1
EndProcedure

; LIST_SORT_T: Sort list elements (pool slot from stack)
; Stack: [poolSlot, ascending] -> []
Procedure C2LIST_SORT_T()
   Protected poolSlot.i, valueType.i, ascending.i

   sp - 1 : ascending = gVar(sp)\i
   sp - 1 : poolSlot = gVar(sp)\i

   If poolSlot >= 0 And poolSlot < gMaxLists And gListPool(poolSlot)\inUse
      valueType = gListPool(poolSlot)\valueType

      If valueType = #C2FLAG_FLOAT
         If ascending
            SortList(gListPool(poolSlot)\dataFloat(), #PB_Sort_Ascending)
         Else
            SortList(gListPool(poolSlot)\dataFloat(), #PB_Sort_Descending)
         EndIf
      ElseIf valueType = #C2FLAG_STR
         If ascending
            SortList(gListPool(poolSlot)\dataStr(), #PB_Sort_Ascending)
         Else
            SortList(gListPool(poolSlot)\dataStr(), #PB_Sort_Descending)
         EndIf
      Else
         If ascending
            SortList(gListPool(poolSlot)\dataInt(), #PB_Sort_Ascending)
         Else
            SortList(gListPool(poolSlot)\dataInt(), #PB_Sort_Descending)
         EndIf
      EndIf
   EndIf

   pc + 1
EndProcedure

; ======================================================================================================
;- Map VM Operations (using PureBasic Map functions)
; ======================================================================================================

; MAP_NEW: Create new map at gVar[slot] or LOCAL[offset]
; V1.026.19: \n = isLocal flag - if 1, store to local variable instead of global
Procedure C2MAP_NEW()
   Protected slot.i, valueType.i, poolSlot.i, isLocal.i, targetSlot.i

   slot = _AR()\i
   valueType = _AR()\j
   isLocal = _AR()\n
   poolSlot = AllocateMapSlot()

   If poolSlot >= 0
      gMapPool(poolSlot)\valueType = valueType
      If isLocal
         ; Store to local variable: gVar[localSlotStart + offset]
         targetSlot = gStack(gStackDepth)\localSlotStart + slot
         gVar(targetSlot)\i = poolSlot
      Else
         ; Store to global variable
         gVar(slot)\i = poolSlot
      EndIf
   Else
      If isLocal
         targetSlot = gStack(gStackDepth)\localSlotStart + slot
         gVar(targetSlot)\i = -1
      Else
         gVar(slot)\i = -1
      EndIf
   EndIf

   pc + 1
EndProcedure

; MAP_PUT: Put key-value pair
; Stack: [slot, key, value]
Procedure C2MAP_PUT()
   Protected slot.i, poolSlot.i, key.s, valueType.i
   Protected valI.i, valF.d, valS.s

   ; Pop value
   sp - 1
   valI = gVar(sp)\i
   valF = gVar(sp)\f
   valS = gVar(sp)\ss

   ; Pop key
   sp - 1
   key = gVar(sp)\ss

   ; Pop slot
   sp - 1
   slot = gVar(sp)\i

   poolSlot = gVar(slot)\i

   If poolSlot >= 0 And poolSlot < gMaxMaps And gMapPool(poolSlot)\inUse
      valueType = gMapPool(poolSlot)\valueType

      If valueType = #C2FLAG_FLOAT
         gMapPool(poolSlot)\dataFloat(key) = valF
      ElseIf valueType = #C2FLAG_STR
         gMapPool(poolSlot)\dataStr(key) = valS
      Else
         gMapPool(poolSlot)\dataInt(key) = valI
      EndIf
   EndIf

   pc + 1
EndProcedure

; MAP_GET: Get value by key, push result
; Stack: [slot, key] -> [value]
Procedure C2MAP_GET()
   Protected slot.i, poolSlot.i, key.s, valueType.i

   ; Pop key
   sp - 1
   key = gVar(sp)\ss

   ; Pop slot
   sp - 1
   slot = gVar(sp)\i

   poolSlot = gVar(slot)\i

   If poolSlot >= 0 And poolSlot < gMaxMaps And gMapPool(poolSlot)\inUse
      valueType = gMapPool(poolSlot)\valueType

      If valueType = #C2FLAG_FLOAT
         If FindMapElement(gMapPool(poolSlot)\dataFloat(), key)
            gVar(sp)\f = gMapPool(poolSlot)\dataFloat(key)
         Else
            gVar(sp)\f = 0.0
         EndIf
      ElseIf valueType = #C2FLAG_STR
         If FindMapElement(gMapPool(poolSlot)\dataStr(), key)
            gVar(sp)\ss = gMapPool(poolSlot)\dataStr(key)
         Else
            gVar(sp)\ss = ""
         EndIf
      Else
         If FindMapElement(gMapPool(poolSlot)\dataInt(), key)
            gVar(sp)\i = gMapPool(poolSlot)\dataInt(key)
         Else
            gVar(sp)\i = 0
         EndIf
      EndIf
   Else
      gVar(sp)\i = 0
   EndIf
   sp + 1

   pc + 1
EndProcedure

; MAP_DELETE: Delete entry by key
; Stack: [slot, key]
Procedure C2MAP_DELETE()
   Protected slot.i, poolSlot.i, key.s, valueType.i

   ; Pop key
   sp - 1
   key = gVar(sp)\ss

   ; Pop slot
   sp - 1
   slot = gVar(sp)\i

   poolSlot = gVar(slot)\i

   If poolSlot >= 0 And poolSlot < gMaxMaps And gMapPool(poolSlot)\inUse
      valueType = gMapPool(poolSlot)\valueType

      If valueType = #C2FLAG_FLOAT
         DeleteMapElement(gMapPool(poolSlot)\dataFloat(), key)
      ElseIf valueType = #C2FLAG_STR
         DeleteMapElement(gMapPool(poolSlot)\dataStr(), key)
      Else
         DeleteMapElement(gMapPool(poolSlot)\dataInt(), key)
      EndIf
   EndIf

   pc + 1
EndProcedure

; MAP_CLEAR: Clear all entries
; Stack: [slot]
Procedure C2MAP_CLEAR()
   Protected slot.i, poolSlot.i, valueType.i

   sp - 1
   slot = gVar(sp)\i

   poolSlot = gVar(slot)\i

   If poolSlot >= 0 And poolSlot < gMaxMaps And gMapPool(poolSlot)\inUse
      valueType = gMapPool(poolSlot)\valueType

      If valueType = #C2FLAG_FLOAT
         ClearMap(gMapPool(poolSlot)\dataFloat())
      ElseIf valueType = #C2FLAG_STR
         ClearMap(gMapPool(poolSlot)\dataStr())
      Else
         ClearMap(gMapPool(poolSlot)\dataInt())
      EndIf
   EndIf

   pc + 1
EndProcedure

; MAP_SIZE: Push map size
; Stack: [slot] -> [size]
Procedure C2MAP_SIZE()
   Protected slot.i, poolSlot.i, valueType.i

   sp - 1
   slot = gVar(sp)\i

   poolSlot = gVar(slot)\i

   If poolSlot >= 0 And poolSlot < gMaxMaps And gMapPool(poolSlot)\inUse
      valueType = gMapPool(poolSlot)\valueType

      If valueType = #C2FLAG_FLOAT
         gVar(sp)\i = MapSize(gMapPool(poolSlot)\dataFloat())
      ElseIf valueType = #C2FLAG_STR
         gVar(sp)\i = MapSize(gMapPool(poolSlot)\dataStr())
      Else
         gVar(sp)\i = MapSize(gMapPool(poolSlot)\dataInt())
      EndIf
   Else
      gVar(sp)\i = 0
   EndIf
   sp + 1

   pc + 1
EndProcedure

; MAP_CONTAINS: Check if key exists
; Stack: [slot, key] -> [result]
Procedure C2MAP_CONTAINS()
   Protected slot.i, poolSlot.i, key.s, valueType.i

   ; Pop key
   sp - 1
   key = gVar(sp)\ss

   ; Pop slot
   sp - 1
   slot = gVar(sp)\i

   poolSlot = gVar(slot)\i

   If poolSlot >= 0 And poolSlot < gMaxMaps And gMapPool(poolSlot)\inUse
      valueType = gMapPool(poolSlot)\valueType

      If valueType = #C2FLAG_FLOAT
         gVar(sp)\i = Bool(FindMapElement(gMapPool(poolSlot)\dataFloat(), key) <> 0)
      ElseIf valueType = #C2FLAG_STR
         gVar(sp)\i = Bool(FindMapElement(gMapPool(poolSlot)\dataStr(), key) <> 0)
      Else
         gVar(sp)\i = Bool(FindMapElement(gMapPool(poolSlot)\dataInt(), key) <> 0)
      EndIf
   Else
      gVar(sp)\i = 0
   EndIf
   sp + 1

   pc + 1
EndProcedure

; MAP_RESET: Reset iterator
; Stack: [slot]
Procedure C2MAP_RESET()
   Protected slot.i, poolSlot.i, valueType.i

   sp - 1
   slot = gVar(sp)\i

   poolSlot = gVar(slot)\i

   If poolSlot >= 0 And poolSlot < gMaxMaps And gMapPool(poolSlot)\inUse
      valueType = gMapPool(poolSlot)\valueType

      If valueType = #C2FLAG_FLOAT
         ResetMap(gMapPool(poolSlot)\dataFloat())
      ElseIf valueType = #C2FLAG_STR
         ResetMap(gMapPool(poolSlot)\dataStr())
      Else
         ResetMap(gMapPool(poolSlot)\dataInt())
      EndIf
   EndIf

   pc + 1
EndProcedure

; MAP_NEXT: Move to next element, push success
; Stack: [slot] -> [success]
Procedure C2MAP_NEXT()
   Protected slot.i, poolSlot.i, valueType.i, success.i

   sp - 1
   slot = gVar(sp)\i

   poolSlot = gVar(slot)\i
   success = 0

   If poolSlot >= 0 And poolSlot < gMaxMaps And gMapPool(poolSlot)\inUse
      valueType = gMapPool(poolSlot)\valueType

      If valueType = #C2FLAG_FLOAT
         If NextMapElement(gMapPool(poolSlot)\dataFloat())
            gMapPool(poolSlot)\currentKey = MapKey(gMapPool(poolSlot)\dataFloat())
            success = 1
         EndIf
      ElseIf valueType = #C2FLAG_STR
         If NextMapElement(gMapPool(poolSlot)\dataStr())
            gMapPool(poolSlot)\currentKey = MapKey(gMapPool(poolSlot)\dataStr())
            success = 1
         EndIf
      Else
         If NextMapElement(gMapPool(poolSlot)\dataInt())
            gMapPool(poolSlot)\currentKey = MapKey(gMapPool(poolSlot)\dataInt())
            success = 1
         EndIf
      EndIf
   EndIf

   gVar(sp)\i = success
   sp + 1
   pc + 1
EndProcedure

; MAP_KEY: Push current key
; Stack: [slot] -> [key]
Procedure C2MAP_KEY()
   Protected slot.i, poolSlot.i

   sp - 1
   slot = gVar(sp)\i

   poolSlot = gVar(slot)\i

   If poolSlot >= 0 And poolSlot < gMaxMaps And gMapPool(poolSlot)\inUse
      gVar(sp)\ss = gMapPool(poolSlot)\currentKey
   Else
      gVar(sp)\ss = ""
   EndIf
   sp + 1

   pc + 1
EndProcedure

; MAP_VALUE: Push current value
; Stack: [slot] -> [value]
Procedure C2MAP_VALUE()
   Protected slot.i, poolSlot.i, valueType.i

   sp - 1
   slot = gVar(sp)\i

   poolSlot = gVar(slot)\i

   If poolSlot >= 0 And poolSlot < gMaxMaps And gMapPool(poolSlot)\inUse
      valueType = gMapPool(poolSlot)\valueType

      ; Get current element value
      If valueType = #C2FLAG_FLOAT
         gVar(sp)\f = gMapPool(poolSlot)\dataFloat()
      ElseIf valueType = #C2FLAG_STR
         gVar(sp)\ss = gMapPool(poolSlot)\dataStr()
      Else
         gVar(sp)\i = gMapPool(poolSlot)\dataInt()
      EndIf
   Else
      gVar(sp)\i = 0
   EndIf
   sp + 1

   pc + 1
EndProcedure

; ======================================================================================================
;- V1.026.8: Typed Map Operations - Pool slot popped directly from stack
;  No gVar lookup needed, faster execution, works with locals via LFETCH
; ======================================================================================================

; MAP_PUT_INT: Put integer key-value pair
; Stack: [poolSlot, key, value] -> []
Procedure C2MAP_PUT_INT()
   Protected poolSlot.i, key.s, val.i

   sp - 1 : val = gVar(sp)\i
   sp - 1 : key = gVar(sp)\ss
   sp - 1 : poolSlot = gVar(sp)\i

   If poolSlot >= 0 And poolSlot < gMaxMaps And gMapPool(poolSlot)\inUse
      gMapPool(poolSlot)\dataInt(key) = val
   EndIf

   pc + 1
EndProcedure

; MAP_PUT_FLOAT: Put float key-value pair
; Stack: [poolSlot, key, value] -> []
Procedure C2MAP_PUT_FLOAT()
   Protected poolSlot.i, key.s, val.d

   sp - 1 : val = gVar(sp)\f
   sp - 1 : key = gVar(sp)\ss
   sp - 1 : poolSlot = gVar(sp)\i

   If poolSlot >= 0 And poolSlot < gMaxMaps And gMapPool(poolSlot)\inUse
      gMapPool(poolSlot)\dataFloat(key) = val
   EndIf

   pc + 1
EndProcedure

; MAP_PUT_STR: Put string key-value pair
; Stack: [poolSlot, key, value] -> []
Procedure C2MAP_PUT_STR()
   Protected poolSlot.i, key.s, val.s

   sp - 1 : val = gVar(sp)\ss
   sp - 1 : key = gVar(sp)\ss
   sp - 1 : poolSlot = gVar(sp)\i

   If poolSlot >= 0 And poolSlot < gMaxMaps And gMapPool(poolSlot)\inUse
      gMapPool(poolSlot)\dataStr(key) = val
   EndIf

   pc + 1
EndProcedure

; MAP_GET_INT: Get integer value by key
; Stack: [poolSlot, key] -> [value]
Procedure C2MAP_GET_INT()
   Protected poolSlot.i, key.s

   sp - 1 : key = gVar(sp)\ss
   sp - 1 : poolSlot = gVar(sp)\i

   If poolSlot >= 0 And poolSlot < gMaxMaps And gMapPool(poolSlot)\inUse
      If FindMapElement(gMapPool(poolSlot)\dataInt(), key)
         gVar(sp)\i = gMapPool(poolSlot)\dataInt(key)
      Else
         gVar(sp)\i = 0
      EndIf
   Else
      gVar(sp)\i = 0
   EndIf
   sp + 1

   pc + 1
EndProcedure

; MAP_GET_FLOAT: Get float value by key
; Stack: [poolSlot, key] -> [value]
Procedure C2MAP_GET_FLOAT()
   Protected poolSlot.i, key.s

   sp - 1 : key = gVar(sp)\ss
   sp - 1 : poolSlot = gVar(sp)\i

   If poolSlot >= 0 And poolSlot < gMaxMaps And gMapPool(poolSlot)\inUse
      If FindMapElement(gMapPool(poolSlot)\dataFloat(), key)
         gVar(sp)\f = gMapPool(poolSlot)\dataFloat(key)
      Else
         gVar(sp)\f = 0.0
      EndIf
   Else
      gVar(sp)\f = 0.0
   EndIf
   sp + 1

   pc + 1
EndProcedure

; MAP_GET_STR: Get string value by key
; Stack: [poolSlot, key] -> [value]
Procedure C2MAP_GET_STR()
   Protected poolSlot.i, key.s

   sp - 1 : key = gVar(sp)\ss
   sp - 1 : poolSlot = gVar(sp)\i

   If poolSlot >= 0 And poolSlot < gMaxMaps And gMapPool(poolSlot)\inUse
      If FindMapElement(gMapPool(poolSlot)\dataStr(), key)
         gVar(sp)\ss = gMapPool(poolSlot)\dataStr(key)
      Else
         gVar(sp)\ss = ""
      EndIf
   Else
      gVar(sp)\ss = ""
   EndIf
   sp + 1

   pc + 1
EndProcedure

; MAP_VALUE_INT: Push current integer value
; Stack: [poolSlot] -> [value]
Procedure C2MAP_VALUE_INT()
   Protected poolSlot.i

   sp - 1 : poolSlot = gVar(sp)\i

   If poolSlot >= 0 And poolSlot < gMaxMaps And gMapPool(poolSlot)\inUse
      gVar(sp)\i = gMapPool(poolSlot)\dataInt()
   Else
      gVar(sp)\i = 0
   EndIf
   sp + 1

   pc + 1
EndProcedure

; MAP_VALUE_FLOAT: Push current float value
; Stack: [poolSlot] -> [value]
Procedure C2MAP_VALUE_FLOAT()
   Protected poolSlot.i

   sp - 1 : poolSlot = gVar(sp)\i

   If poolSlot >= 0 And poolSlot < gMaxMaps And gMapPool(poolSlot)\inUse
      gVar(sp)\f = gMapPool(poolSlot)\dataFloat()
   Else
      gVar(sp)\f = 0.0
   EndIf
   sp + 1

   pc + 1
EndProcedure

; MAP_VALUE_STR: Push current string value
; Stack: [poolSlot] -> [value]
Procedure C2MAP_VALUE_STR()
   Protected poolSlot.i

   sp - 1 : poolSlot = gVar(sp)\i

   If poolSlot >= 0 And poolSlot < gMaxMaps And gMapPool(poolSlot)\inUse
      gVar(sp)\ss = gMapPool(poolSlot)\dataStr()
   Else
      gVar(sp)\ss = ""
   EndIf
   sp + 1

   pc + 1
EndProcedure

; ======================================================================================================
;- V1.026.8: Typed operations for non-value map ops (pool slot direct from stack)
;  These still need valueType for determining which internal map to use
; ======================================================================================================

; MAP_DELETE_T: Delete entry by key (pool slot from stack)
; Stack: [poolSlot, key] -> []
Procedure C2MAP_DELETE_T()
   Protected poolSlot.i, key.s, valueType.i

   sp - 1 : key = gVar(sp)\ss
   sp - 1 : poolSlot = gVar(sp)\i

   If poolSlot >= 0 And poolSlot < gMaxMaps And gMapPool(poolSlot)\inUse
      valueType = gMapPool(poolSlot)\valueType

      If valueType = #C2FLAG_FLOAT
         DeleteMapElement(gMapPool(poolSlot)\dataFloat(), key)
      ElseIf valueType = #C2FLAG_STR
         DeleteMapElement(gMapPool(poolSlot)\dataStr(), key)
      Else
         DeleteMapElement(gMapPool(poolSlot)\dataInt(), key)
      EndIf
   EndIf

   pc + 1
EndProcedure

; MAP_CLEAR_T: Clear all entries (pool slot from stack)
; Stack: [poolSlot] -> []
Procedure C2MAP_CLEAR_T()
   Protected poolSlot.i, valueType.i

   sp - 1 : poolSlot = gVar(sp)\i

   If poolSlot >= 0 And poolSlot < gMaxMaps And gMapPool(poolSlot)\inUse
      valueType = gMapPool(poolSlot)\valueType

      If valueType = #C2FLAG_FLOAT
         ClearMap(gMapPool(poolSlot)\dataFloat())
      ElseIf valueType = #C2FLAG_STR
         ClearMap(gMapPool(poolSlot)\dataStr())
      Else
         ClearMap(gMapPool(poolSlot)\dataInt())
      EndIf
   EndIf

   pc + 1
EndProcedure

; MAP_SIZE_T: Push map size (pool slot from stack)
; Stack: [poolSlot] -> [size]
Procedure C2MAP_SIZE_T()
   Protected poolSlot.i, valueType.i

   sp - 1 : poolSlot = gVar(sp)\i

   If poolSlot >= 0 And poolSlot < gMaxMaps And gMapPool(poolSlot)\inUse
      valueType = gMapPool(poolSlot)\valueType

      If valueType = #C2FLAG_FLOAT
         gVar(sp)\i = MapSize(gMapPool(poolSlot)\dataFloat())
      ElseIf valueType = #C2FLAG_STR
         gVar(sp)\i = MapSize(gMapPool(poolSlot)\dataStr())
      Else
         gVar(sp)\i = MapSize(gMapPool(poolSlot)\dataInt())
      EndIf
   Else
      gVar(sp)\i = 0
   EndIf
   sp + 1

   pc + 1
EndProcedure

; MAP_CONTAINS_T: Check if key exists (pool slot from stack)
; Stack: [poolSlot, key] -> [result]
Procedure C2MAP_CONTAINS_T()
   Protected poolSlot.i, key.s, valueType.i

   sp - 1 : key = gVar(sp)\ss
   sp - 1 : poolSlot = gVar(sp)\i

   If poolSlot >= 0 And poolSlot < gMaxMaps And gMapPool(poolSlot)\inUse
      valueType = gMapPool(poolSlot)\valueType

      If valueType = #C2FLAG_FLOAT
         gVar(sp)\i = Bool(FindMapElement(gMapPool(poolSlot)\dataFloat(), key) <> 0)
      ElseIf valueType = #C2FLAG_STR
         gVar(sp)\i = Bool(FindMapElement(gMapPool(poolSlot)\dataStr(), key) <> 0)
      Else
         gVar(sp)\i = Bool(FindMapElement(gMapPool(poolSlot)\dataInt(), key) <> 0)
      EndIf
   Else
      gVar(sp)\i = 0
   EndIf
   sp + 1

   pc + 1
EndProcedure

; MAP_RESET_T: Reset iterator (pool slot from stack)
; Stack: [poolSlot] -> []
Procedure C2MAP_RESET_T()
   Protected poolSlot.i, valueType.i

   sp - 1 : poolSlot = gVar(sp)\i

   If poolSlot >= 0 And poolSlot < gMaxMaps And gMapPool(poolSlot)\inUse
      valueType = gMapPool(poolSlot)\valueType

      If valueType = #C2FLAG_FLOAT
         ResetMap(gMapPool(poolSlot)\dataFloat())
      ElseIf valueType = #C2FLAG_STR
         ResetMap(gMapPool(poolSlot)\dataStr())
      Else
         ResetMap(gMapPool(poolSlot)\dataInt())
      EndIf
   EndIf

   pc + 1
EndProcedure

; MAP_NEXT_T: Move to next element (pool slot from stack)
; Stack: [poolSlot] -> [success]
Procedure C2MAP_NEXT_T()
   Protected poolSlot.i, valueType.i, success.i

   sp - 1 : poolSlot = gVar(sp)\i
   success = 0

   If poolSlot >= 0 And poolSlot < gMaxMaps And gMapPool(poolSlot)\inUse
      valueType = gMapPool(poolSlot)\valueType

      If valueType = #C2FLAG_FLOAT
         If NextMapElement(gMapPool(poolSlot)\dataFloat())
            gMapPool(poolSlot)\currentKey = MapKey(gMapPool(poolSlot)\dataFloat())
            success = 1
         EndIf
      ElseIf valueType = #C2FLAG_STR
         If NextMapElement(gMapPool(poolSlot)\dataStr())
            gMapPool(poolSlot)\currentKey = MapKey(gMapPool(poolSlot)\dataStr())
            success = 1
         EndIf
      Else
         If NextMapElement(gMapPool(poolSlot)\dataInt())
            gMapPool(poolSlot)\currentKey = MapKey(gMapPool(poolSlot)\dataInt())
            success = 1
         EndIf
      EndIf
   EndIf

   gVar(sp)\i = success
   sp + 1
   pc + 1
EndProcedure

; MAP_KEY_T: Push current key (pool slot from stack)
; Stack: [poolSlot] -> [key]
Procedure C2MAP_KEY_T()
   Protected poolSlot.i

   sp - 1 : poolSlot = gVar(sp)\i

   If poolSlot >= 0 And poolSlot < gMaxMaps And gMapPool(poolSlot)\inUse
      gVar(sp)\ss = gMapPool(poolSlot)\currentKey
   Else
      gVar(sp)\ss = ""
   EndIf
   sp + 1

   pc + 1
EndProcedure

; ======================================================================================================
;- Collection Cleanup
; ======================================================================================================

Procedure ResetCollections()
   Protected i.i

   ; Reset list pool
   For i = 0 To gMaxLists - 1
      If gListPool(i)\inUse
         FreeListSlot(i)
      EndIf
   Next
   gNextListSlot = 0

   ; Reset map pool
   For i = 0 To gMaxMaps - 1
      If gMapPool(i)\inUse
         FreeMapSlot(i)
      EndIf
   Next
   gNextMapSlot = 0
EndProcedure

; IDE Options = PureBasic 6.21 (Windows - x64)
; CursorPosition = 1
; Folding = ------
; EnableXP
; CPU = 1
