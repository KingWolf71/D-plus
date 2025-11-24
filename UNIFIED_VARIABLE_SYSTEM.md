# Unified Variable System (V1.18.0)

## Overview

As of version 1.18.0, LJ2 uses a **unified variable system** where all variables (global and local) are stored in the same `gVar[]` array and accessed using the same opcodes. This simplifies the codebase significantly and makes it much easier to understand and maintain.

## Key Changes

### Before (V1.17.x - Complex System)
- **Globals**: Stored in `gVar[]` array, accessed via FETCH/STORE opcodes
- **Locals**: Stored in separate `LocalInt/Float/String[]` arrays within stack frames
- **Specialized opcodes**: LFETCH, LSTORE, LMOV for local variables
- **Complex postprocessor**: Converted global opcodes to local variants
- **Two different code paths**: Difficult to understand and maintain

### After (V1.18.0 - Unified System)
- **All variables** stored in the same `gVar[]` array
- **Same opcodes** (FETCH/STORE/MOV) for all variables
- **Dynamic slot allocation**: Locals get temporary `gVar[]` slots during function calls
- **Simpler postprocessor**: No opcode conversions needed
- **One method to understand**: Consistent variable access pattern

## Memory Layout

```
gVar[] Array Organization:
┌─────────────────────────────────────────────────────────────┐
│ [0 to gnLastVariable-1]              : Permanent globals    │
│ [gnLastVariable to gCurrentMaxLocal] : Active local vars    │
│ [gCurrentMaxLocal onwards]           : Evaluation stack (sp)│
└─────────────────────────────────────────────────────────────┘
```

### Global Variables
- Allocated at compile time during parsing
- Slots: `0` to `gnLastVariable - 1`
- `paramOffset = -1` in metadata
- Permanent (never deallocated)

### Local Variables
- Allocated dynamically during CALL instruction
- Slots: `gnLastVariable` to `gCurrentMaxLocal`
- `paramOffset >= 0` (offset within function's locals)
- Temporary (deallocated on RETURN)

### Evaluation Stack
- Starts at `gCurrentMaxLocal`
- Grows upward during expression evaluation
- `sp` (stack pointer) tracks current position

## How It Works

### Function Call (CALL Instruction)

```purebasic
localSlotStart = gCurrentMaxLocal
gCurrentMaxLocal + (nParams + nLocals)  ; Reserve slots

; Copy parameters from stack to allocated slots
For i = 0 To nParams - 1
   gVar(localSlotStart + i) = gVar(sp - nParams + i)
Next

; Save in stack frame
gStack(gStackDepth)\localSlotStart = localSlotStart
gStack(gStackDepth)\localSlotCount = nParams + nLocals

; Allocate local arrays
For each local array:
   actualSlot = localSlotStart + paramOffset
   ReDim gVar(actualSlot)\dta\ar(arraySize - 1)
Next
```

### Variable Access (FETCH/STORE)

```purebasic
varSlot = instruction\i

; Compute actual gVar[] slot
If paramOffset >= 0 And gFunctionDepth > 0:
   actualSlot = localSlotStart + paramOffset  ; Local variable
Else:
   actualSlot = varSlot                       ; Global variable

; Access unified gVar[] array
value = gVar(actualSlot)
```

### Function Return (RETURN Instruction)

```purebasic
; Save return value
returnValue = gVar(sp - 1)

; Clear local slots (garbage collection)
For i = 0 To localSlotCount - 1
   Clear gVar(localSlotStart + i)
Next

; Deallocate slots
gCurrentMaxLocal = localSlotStart

; Pop stack frame
gStackDepth - 1

; Push return value
gVar(sp) = returnValue
```

## Modified Structures

### Stack Frame (stStack)

**Before:**
```purebasic
Structure stStack
   sp.l
   pc.l
   Array LocalInt.i(0)      ; Separate arrays
   Array LocalFloat.d(0)
   Array LocalString.s(0)
   Array LocalArrays.stVT(0)
EndStructure
```

**After:**
```purebasic
Structure stStack
   sp.l                  ; Saved stack pointer
   pc.l                  ; Saved program counter
   localSlotStart.l      ; First gVar[] slot for locals
   localSlotCount.l      ; Number of local slots allocated
EndStructure
```

### Variable Metadata (stVarMeta)

```purebasic
Structure stVarMeta
   name.s
   flags.w
   paramOffset.i         ; -1 = global, >= 0 = local offset
   typeSpecificIndex.i   ; For local arrays
   arraySize.i
   elementSize.i
   valueInt.i
   valueFloat.d
   valueString.s
EndStructure
```

**Key Field: paramOffset**
- `-1`: Global variable (use varSlot directly)
- `>= 0`: Local variable (offset from localSlotStart)

## Modified Files

### Core VM Files
1. **c2-inc-v12.pbi**
   - Removed LFETCH, LSTORE, LMOV, LINC_VAR opcode definitions
   - Updated stVarMeta documentation
   - Added unified system documentation header

2. **c2-vm-V10.pb**
   - Modified stStack structure (removed Local arrays)
   - Added `gCurrentMaxLocal` global variable
   - Initialize gCurrentMaxLocal in vmExecute() and vmClearRun()

3. **c2-vm-commands-v09.pb**
   - **C2CALL()**: Allocate gVar[] slots, copy params, save frame info
   - **C2Return/F/S()**: Clear slots, restore gCurrentMaxLocal
   - **C2FetchPush/S/F()**: Unified slot calculation
   - **C2POP/S/F()**: Unified slot calculation
   - **C2Store/S/F()**: Unified slot calculation
   - **C2MOV/S/F()**: Unified slot calculation for both src and dest

### Compilation Files
4. **c2-postprocessor-V03.pbi**
   - Remove LFETCH/LSTORE/LMOV opcode conversions
   - Simplified opcode specialization

5. **c2-modules-V16.pb**
   - Code generation uses FETCH/STORE for all variables
   - No special handling needed for locals vs globals

## Benefits

### Simplification
✅ **One method for all variables** - No need to understand two different systems
✅ **Fewer opcodes** - Removed 15+ local-specific opcodes
✅ **Simpler code** - Hundreds of lines of specialized code eliminated
✅ **Easier debugging** - Consistent behavior across all variables

### Performance
✅ **Same VM speed** - Still direct array access
✅ **Faster compilation** - Less postprocessor work
✅ **Better cache locality** - All variables in one array

### Maintenance
✅ **Easier to understand** - Consistent patterns
✅ **Fewer bugs** - Less code means fewer places for bugs
✅ **Easier to extend** - Add features once, works for all variables

## Compatibility

### Backward Compatibility
- Source code (.lj files) **unchanged** - Full compatibility
- Compilation process **unchanged** - Name mangling still works
- paramOffset field **unchanged** - Still distinguishes global vs local

### What Changed
- Internal representation only
- VM execution implementation
- Stack frame structure

## Examples

### Simple Function
```c
func add(a, b) {
   c = a + b;
   return c;
}
x = add(5, 10);
```

**Before (V1.17.x):**
- Parameters a, b → LocalInt[0], LocalInt[1]
- Local c → LocalInt[2]
- Access via LFETCH, LSTORE opcodes

**After (V1.18.0):**
- Parameters a, b → gVar[localSlotStart+0], gVar[localSlotStart+1]
- Local c → gVar[localSlotStart+2]
- Access via FETCH, STORE opcodes (same as globals!)

### Nested Calls
```c
func outer() {
   a = 1;
   b = inner();
   return a + b;
}

func inner() {
   x = 2;
   y = 3;
   return x + y;
}
```

**Slot Allocation:**
```
Before outer() call:
   gCurrentMaxLocal = gnLastVariable (e.g., 100)

During outer() execution:
   outer.a → gVar[100]
   outer.b → gVar[101]
   gCurrentMaxLocal = 102

During inner() call (nested):
   inner.x → gVar[102]
   inner.y → gVar[103]
   gCurrentMaxLocal = 104

After inner() returns:
   gCurrentMaxLocal = 102 (restored to outer's end)

After outer() returns:
   gCurrentMaxLocal = 100 (restored to gnLastVariable)
```

## Technical Details

### Slot Allocation Strategy
- **Sequential allocation**: Simple increment of gCurrentMaxLocal
- **Stack-based deallocation**: Restore gCurrentMaxLocal on return
- **Nested calls supported**: Each call extends gCurrentMaxLocal
- **Recursion safe**: Each recursive call gets its own slots

### Garbage Collection
- Slots cleared on RETURN (set to 0/""/0.0)
- Arrays deallocated (ReDim to 0)
- Pointer metadata cleared
- Prevents memory leaks

### Array Handling
- Local arrays stored in gVar[actualSlot].dta.ar()
- Same structure as global arrays
- Allocated during CALL based on gFuncLocalArraySlots mapping
- Deallocated during RETURN

## Future Enhancements

Possible future improvements:
1. **Slot reuse pool**: Reuse deallocated slots instead of always growing
2. **Compaction**: Periodic cleanup of unused slots
3. **Separate stacks**: Keep locals on call stack for better locality
4. **Type specialization**: Separate Int/Float/String arrays again if profiling shows benefit

But for now, the unified system provides the best balance of simplicity and performance.

## Migration Notes

### For Users
- No changes needed to your .lj source files
- Everything works exactly as before
- Same syntax, same semantics

### For Developers
- Study this document to understand the new system
- All local variable access now goes through gVar[]
- paramOffset >= 0 means: actualSlot = localSlotStart + paramOffset
- No more LocalInt/LocalFloat/LocalString arrays

## Summary

The unified variable system is a **major simplification** of the LJ2 compiler/VM. By using one method for all variables, the code is easier to understand, maintain, and extend. Performance remains excellent while complexity is dramatically reduced.

**Version**: 1.18.0
**Date**: January 2025
**Status**: Implemented ✅
