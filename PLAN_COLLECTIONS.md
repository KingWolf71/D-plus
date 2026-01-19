# D+AI Collections Implementation Plan
## LinkedLists and Maps

### Overview

Implement LinkedLists and Maps as first-class data structures in D+AI, using SpiderBasic-compatible PureBasic code for VM portability.

---

## Phase 1: Infrastructure (c2-collections-v01.pbi)

### 1.1 New Structures

```purebasic
; List element storage - each list stored as stVTArray in a gVar slot
; Maps use PureBasic's NewMap internally, referenced by slot

Structure stListMeta
   elementType.w        ; #C2FLAG_INT, #C2FLAG_FLOAT, #C2FLAG_STR
   currentIndex.i       ; Current element index (-1 if not set)
EndStructure

Structure stMapMeta
   keyType.w            ; Always string for now
   valueType.w          ; #C2FLAG_INT, #C2FLAG_FLOAT, #C2FLAG_STR
EndStructure
```

### 1.2 Global Storage

```purebasic
; Lists stored in gVar[slot]\dta\ar() - reusing array infrastructure
; Maps need separate storage since PureBasic maps can't be in arrays
Global NewList gListStorage.stVTSimple()     ; Temp list for operations
Global NewMap gMapStorageInt.i()             ; Integer maps
Global NewMap gMapStorageFloat.d()           ; Float maps
Global NewMap gMapStorageStr.s()             ; String maps
Global Dim gMapSlotToType.w(256)             ; Map slot -> value type
```

---

## Phase 2: New Opcodes (c2-inc-v15.pbi)

### 2.1 List Opcodes

```purebasic
; List Operations (20 opcodes)
#ljLIST_NEW           ; Create new list - slot in \i, type in \j
#ljLIST_ADD           ; Add element - list slot in \i, value on stack
#ljLIST_INSERT        ; Insert at current - list slot in \i, value on stack
#ljLIST_DELETE        ; Delete current element - list slot in \i
#ljLIST_CLEAR         ; Clear all elements - list slot in \i
#ljLIST_SIZE          ; Push list size - list slot in \i
#ljLIST_FIRST         ; Move to first, push success - list slot in \i
#ljLIST_LAST          ; Move to last, push success - list slot in \i
#ljLIST_NEXT          ; Move to next, push success - list slot in \i
#ljLIST_PREV          ; Move to previous, push success - list slot in \i
#ljLIST_SELECT        ; Select by index - list slot in \i, index on stack
#ljLIST_INDEX         ; Push current index - list slot in \i
#ljLIST_GET           ; Push current element value - list slot in \i
#ljLIST_SET           ; Set current element - list slot in \i, value on stack
#ljLIST_RESET         ; Reset position to before first - list slot in \i
```

### 2.2 Map Opcodes

```purebasic
; Map Operations (12 opcodes)
#ljMAP_NEW            ; Create new map - slot in \i, value type in \j
#ljMAP_PUT            ; Put key-value - map slot in \i, key+value on stack
#ljMAP_GET            ; Get value by key - map slot in \i, key on stack, push value
#ljMAP_DELETE         ; Delete by key - map slot in \i, key on stack
#ljMAP_CLEAR          ; Clear all entries - map slot in \i
#ljMAP_SIZE           ; Push map size - map slot in \i
#ljMAP_CONTAINS       ; Check key exists - map slot in \i, key on stack, push bool
#ljMAP_RESET          ; Reset iterator - map slot in \i
#ljMAP_NEXT           ; Move to next, push success - map slot in \i
#ljMAP_KEY            ; Push current key - map slot in \i
#ljMAP_VALUE          ; Push current value - map slot in \i
```

---

## Phase 3: Language Syntax

### 3.1 List Syntax

```c
// Declaration
list myList.i;              // Integer list
list names.s;               // String list
list values.f;              // Float list

// Operations
listAdd(myList, 42);        // Add to end
listInsert(myList, 10);     // Insert at current position
listDelete(myList);         // Delete current element
listClear(myList);          // Clear all

// Navigation
listFirst(myList);          // Move to first, returns success
listLast(myList);           // Move to last
listNext(myList);           // Move to next
listPrev(myList);           // Move to previous
listSelect(myList, 5);      // Select by index
listReset(myList);          // Reset to before first

// Access
n = listSize(myList);       // Get size
i = listIndex(myList);      // Get current index
val = listGet(myList);      // Get current value
listSet(myList, 100);       // Set current value

// Iteration
listFirst(myList);
while listNext(myList) {
    print(listGet(myList));
}
```

### 3.2 Map Syntax

```c
// Declaration
map ages.i;                 // String key -> Integer value
map scores.f;               // String key -> Float value
map labels.s;               // String key -> String value

// Operations
mapPut(ages, "Alice", 30);  // Put key-value pair
age = mapGet(ages, "Alice"); // Get value (0 if not found)
mapDelete(ages, "Alice");    // Delete entry
mapClear(ages);              // Clear all

// Query
n = mapSize(ages);           // Get size
if mapContains(ages, "Bob") { ... }  // Check key exists

// Iteration
mapReset(ages);
while mapNext(ages) {
    print(mapKey(ages), " = ", mapValue(ages));
}
```

---

## Phase 4: Implementation Files

### 4.1 File Structure

```
c2-collections-v01.pbi     ; New file - VM collection operations
c2-inc-v16.pbi             ; Updated - new opcodes
c2-scanner-v05.pbi         ; Updated - new keywords
c2-ast-v05.pbi             ; Updated - new AST nodes
c2-codegen-v05.pbi         ; Updated - code generation
c2-postprocessor-V07.pbi   ; Updated - type inference
c2-vm-V14.pb               ; Updated - jump table
c2-vm-commands-v13.pb      ; Updated - include collections
```

### 4.2 New Keywords

```purebasic
; In scanner - Install() calls
Install("list", #ljList)
Install("map", #ljMap)

; Built-in functions (in gBuiltinDefs)
; Lists
{"listAdd", #ljLIST_ADD, 2, 2, #C2FLAG_INT}
{"listInsert", #ljLIST_INSERT, 2, 2, #C2FLAG_INT}
{"listDelete", #ljLIST_DELETE, 1, 1, #C2FLAG_INT}
{"listClear", #ljLIST_CLEAR, 1, 1, #C2FLAG_INT}
{"listSize", #ljLIST_SIZE, 1, 1, #C2FLAG_INT}
{"listFirst", #ljLIST_FIRST, 1, 1, #C2FLAG_INT}
{"listLast", #ljLIST_LAST, 1, 1, #C2FLAG_INT}
{"listNext", #ljLIST_NEXT, 1, 1, #C2FLAG_INT}
{"listPrev", #ljLIST_PREV, 1, 1, #C2FLAG_INT}
{"listSelect", #ljLIST_SELECT, 2, 2, #C2FLAG_INT}
{"listIndex", #ljLIST_INDEX, 1, 1, #C2FLAG_INT}
{"listGet", #ljLIST_GET, 1, 1, 0}  ; Return type depends on list type
{"listSet", #ljLIST_SET, 2, 2, #C2FLAG_INT}
{"listReset", #ljLIST_RESET, 1, 1, #C2FLAG_INT}

; Maps
{"mapPut", #ljMAP_PUT, 3, 3, #C2FLAG_INT}
{"mapGet", #ljMAP_GET, 2, 2, 0}   ; Return type depends on map type
{"mapDelete", #ljMAP_DELETE, 2, 2, #C2FLAG_INT}
{"mapClear", #ljMAP_CLEAR, 1, 1, #C2FLAG_INT}
{"mapSize", #ljMAP_SIZE, 1, 1, #C2FLAG_INT}
{"mapContains", #ljMAP_CONTAINS, 2, 2, #C2FLAG_INT}
{"mapReset", #ljMAP_RESET, 1, 1, #C2FLAG_INT}
{"mapNext", #ljMAP_NEXT, 1, 1, #C2FLAG_INT}
{"mapKey", #ljMAP_KEY, 1, 1, #C2FLAG_STR}
{"mapValue", #ljMAP_VALUE, 1, 1, 0}  ; Return type depends on map type
```

---

## Phase 5: VM Implementation (SpiderBasic Compatible)

### 5.1 List Implementation Strategy

Since SpiderBasic doesn't support arrays of lists, we'll use gVar[]\dta\ar() (the existing array infrastructure) with a current index tracker:

```purebasic
; Lists stored as:
; gVar[listSlot]\dta\ar()     - elements
; gVar[listSlot]\dta\size     - element count
; gVar[listSlot]\i            - current index (-1 = before first)
; gVarMeta[listSlot]\flags    - includes #C2FLAG_LIST

Procedure C2LIST_ADD()
   ; Add element to end of list
   listSlot = _AR()\i
   sp - 1

   size = gVar(listSlot)\dta\size
   ReDim gVar(listSlot)\dta\ar(size)

   ; Copy value based on type
   CopyStructure(@gVar(sp), @gVar(listSlot)\dta\ar(size), stVTSimple)

   gVar(listSlot)\dta\size = size + 1
   gVar(listSlot)\i = size  ; Current = newly added
   pc + 1
EndProcedure
```

### 5.2 Map Implementation Strategy

Maps are more complex since SpiderBasic Maps can't be dynamically created. We'll use a pool approach:

```purebasic
; Pre-allocated map pools (SpiderBasic compatible)
#MAX_MAPS = 64

Structure stMapPool
   inUse.b
   valueType.w
   currentKey.s
   NewMap dataInt.i()
   NewMap dataFloat.d()
   NewMap dataStr.s()
EndStructure

Global Dim gMapPool.stMapPool(#MAX_MAPS - 1)
Global gNextMapSlot.i = 0

Procedure C2MAP_NEW()
   ; Allocate map from pool
   mapSlot = _AR()\i
   valueType = _AR()\j

   ; Find free pool slot
   poolIdx = -1
   For i = 0 To #MAX_MAPS - 1
      If Not gMapPool(i)\inUse
         poolIdx = i
         Break
      EndIf
   Next

   If poolIdx >= 0
      gMapPool(poolIdx)\inUse = #True
      gMapPool(poolIdx)\valueType = valueType
      gVar(mapSlot)\i = poolIdx  ; Store pool index
   EndIf

   pc + 1
EndProcedure
```

---

## Phase 6: Test Files

### 6.1 Test Files to Create

```
Examples/52 test lists.lj           ; Basic list operations
Examples/53 test maps.lj            ; Basic map operations
Examples/54 test list iteration.lj  ; List traversal patterns
Examples/55 test map iteration.lj   ; Map traversal patterns
Examples/56 collections stress.lj   ; Performance/stress test
```

---

## Implementation Order

1. **c2-inc-v16.pbi** - Add new flags (#C2FLAG_LIST, #C2FLAG_MAP) and opcodes
2. **c2-collections-v01.pbi** - Implement VM procedures for all list/map operations
3. **c2-scanner-v05.pbi** - Add `list` and `map` keywords
4. **c2-ast-v05.pbi** - Handle list/map declarations
5. **c2-codegen-v05.pbi** - Generate opcodes for list/map operations
6. **c2-builtins-v05.pbi** - Register list/map functions
7. **c2-postprocessor-V07.pbi** - Type inference for collections
8. **c2-vm-commands-v13.pb** - Include collections module
9. **c2-vm-V14.pb** - Add jump table entries
10. **Test files** - Create comprehensive tests

---

## SpiderBasic Compatibility Notes

1. **No dynamic NewList/NewMap** - SpiderBasic can't create lists/maps at runtime in arrays, hence the pool approach for maps
2. **No pointers to lists** - Use slot indices instead
3. **ReDim supported** - Safe to use for array resizing
4. **ForEach not exposed** - Use while loops with Next functions instead
5. **All functions available**: AddElement, DeleteElement, FirstElement, NextElement, etc.

---

## Questions for User

1. Should maps support non-string keys (integer keys)?
2. Should lists support nested lists (list of lists)?
3. Maximum number of maps (#MAX_MAPS = 64) - is this sufficient?
4. Should we add sorting functions (listSort)?

---

## Version Impact

This will advance versions:
- c2-inc-v15 → v16
- c2-scanner-v04 → v05
- c2-ast-v04 → v05
- c2-codegen-v04 → v05
- c2-builtins-v04 → v05
- c2-postprocessor-V06 → V07
- c2-vm-commands-v12 → v13
- c2-vm-V13 → V14
- NEW: c2-collections-v01.pbi
- _D+AI.ver: 1.025.0 → 1.026.0
