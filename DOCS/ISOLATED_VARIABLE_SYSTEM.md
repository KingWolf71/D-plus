# Isolated Variable System (V1.31.0)

## Overview

As of version 1.31.0, LJ2 uses an **isolated variable system** where globals, locals, and the evaluation stack are stored in completely separate arrays. This eliminates the possibility of stack/local overlap bugs that could occur in the previous unified system (V1.18.0).

## Key Changes from Unified System

### Before (V1.18.0-V1.30.x - Unified System)
- **All variables** stored in single `gVar[]` array
- Globals at slots 0 to gnLastVariable-1
- Locals at slots gnLastVariable onwards
- Evaluation stack overlapped with local variable range
- **Risk**: Stack pointer could drift into local variable slots (bug found in V1.030.69)

### After (V1.31.0 - Isolated System)
- **Three separate arrays** for complete isolation
- `gVar[]` - Global variables ONLY
- `gLocal[]` - Local variables ONLY
- `gEvalStack[]` - Evaluation stack ONLY
- **No overlap possible** - each array is independent

## Memory Layout

```
COMPLETE ISOLATION:
+-------------------------------------+
| gVar[]      : Global variables ONLY |  Permanent, indexed by slot
|             : Slots 0 to 65535      |
+-------------------------------------+
| gLocal[]    : Local variables ONLY  |  Per-function frame, indexed by offset
|             : Size 8192 slots       |
+-------------------------------------+
| gEvalStack[]: Evaluation stack ONLY |  sp-indexed, completely isolated
|             : Size 4096 slots       |
+-------------------------------------+

NO OVERLAP POSSIBLE - each array is independent!
```

## Array Constants

```purebasic
#C2MAXGLOBALS     = 65536    ; gVar[] size (existing)
#C2MAXLOCALS      = 8192     ; gLocal[] size (new)
#C2MAXEVALSTACK   = 4096     ; gEvalStack[] size (new)
```

## Global Variables

```purebasic
Global Dim           gVar.stVT(#C2MAXVARS)             ; Global variables ONLY
Global Dim           gLocal.stVT(#C2MAXLOCALS)         ; Local variables ONLY
Global Dim           gEvalStack.stVT(#C2MAXEVALSTACK)  ; Evaluation stack ONLY

Global               gLocalBase.i = 0                   ; Base index in gLocal[] for current frame
Global               gLocalTop.i = 0                    ; Current top of gLocal[] allocation
```

## Opcode Categories (LL/GG/LG/GL)

### GG - Global to Global (existing opcodes, unchanged semantics)
- `MOV`, `MOVF`, `MOVS` - Global slot to global slot
- `FETCH`, `FETCHF`, `FETCHS` - Global to evaluation stack
- `STORE`, `STOREF`, `STORES` - Evaluation stack to global
- `POP`, `POPF`, `POPS` - Evaluation stack to global

### LL - Local to Local
- `LLMOV`, `LLMOVF`, `LLMOVS` - Local offset to local offset

### GL - Global to Local
- `LMOV`, `LMOVF`, `LMOVS` - Global slot to local offset

### LG - Local to Global
- `LGMOV`, `LGMOVF`, `LGMOVS` - Local offset to global slot

### Local Stack Operations
- `LFETCH`, `LFETCHF`, `LFETCHS` - Local to evaluation stack
- `LSTORE`, `LSTOREF`, `LSTORES` - Evaluation stack to local

## Stack Frame Structure

```purebasic
Structure stStack
   sp.l              ; Saved stack pointer (into gEvalStack[])
   pc.l              ; Saved program counter
   localBase.l       ; V1.31.0: Base index in gLocal[] for this frame
   localCount.l      ; V1.31.0: Number of local slots (params + locals)
EndStructure
```

## How It Works

### Function Call (C2CALL)

```purebasic
; Save caller's local base
savedLocalBase = gLocalBase

; Set up new frame in gLocal[]
gLocalBase = gLocalTop
gLocalTop + totalLocals

; Copy parameters from gEvalStack[] to gLocal[]
For i = 0 To nParams - 1
   gLocal(gLocalBase + i) = gEvalStack(sp - nParams + i)
Next
sp - nParams  ; Pop parameters from evaluation stack

; Save frame info
gStack(gStackDepth)\localBase = savedLocalBase
gStack(gStackDepth)\localCount = totalLocals
```

### Local Variable Access (LFETCH/LSTORE)

```purebasic
; LFETCH: Local to evaluation stack
offset = _AR()\i  ; Local variable offset
gEvalStack(sp) = gLocal(gLocalBase + offset)
sp + 1

; LSTORE: Evaluation stack to local
offset = _AR()\i
sp - 1
gLocal(gLocalBase + offset) = gEvalStack(sp)
```

### Cross-Array Operations (LMOV, LGMOV, LLMOV)

```purebasic
; LMOV (GL): Global to Local
; gVar[j] -> gLocal[gLocalBase + i]
gLocal(gLocalBase + _AR()\i) = gVar(_AR()\j)

; LGMOV (LG): Local to Global
; gLocal[gLocalBase + j] -> gVar[i]
gVar(_AR()\i) = gLocal(gLocalBase + _AR()\j)

; LLMOV (LL): Local to Local
; gLocal[gLocalBase + j] -> gLocal[gLocalBase + i]
gLocal(gLocalBase + _AR()\i) = gLocal(gLocalBase + _AR()\j)
```

### Function Return (C2Return)

```purebasic
; Get return value from gEvalStack[]
returnValue = gEvalStack(sp - 1)
sp - 1

; Clear local slots in gLocal[]
For i = 0 To localCount - 1
   Clear gLocal(savedLocalBase + i)
Next

; Restore gLocalBase and gLocalTop
gLocalTop = savedLocalBase
gLocalBase = gStack(gStackDepth)\localBase

; Pop stack frame
gStackDepth - 1

; Push return value to gEvalStack[]
gEvalStack(sp) = returnValue
sp + 1
```

## Stack Operations

All stack arithmetic and comparisons now use `gEvalStack[]`:

```purebasic
; Integer addition
sp - 1
gEvalStack(sp - 1)\i + gEvalStack(sp)\i

; Float comparison
sp - 1
If gEvalStack(sp - 1)\f > gEvalStack(sp)\f
   gEvalStack(sp - 1)\i = 1
Else
   gEvalStack(sp - 1)\i = 0
EndIf
```

## Benefits

### Elimination of Overlap Bugs
- **Complete isolation** - No way for stack to overwrite locals
- **Deterministic behavior** - Each array serves one purpose
- **Easier debugging** - Clear separation of concerns

### Better Memory Layout
- **Cache locality** - Related data grouped together
- **Predictable access patterns** - Each array accessed independently
- **Cleaner architecture** - Conceptually simpler

### Maintainability
- **Clear semantics** - LL/GG/LG/GL model easy to understand
- **Fewer edge cases** - No shared array means fewer interactions
- **Easier to extend** - Add features to one array without affecting others

## Modified Files

### Core VM Files
1. **c2-inc-v16.pbi**
   - Added #C2MAXLOCALS and #C2MAXEVALSTACK constants
   - Updated documentation header

2. **c2-vm-V14.pb**
   - Added gLocal[] and gEvalStack[] array declarations
   - Added gLocalBase and gLocalTop global variables
   - Updated stStack structure (localBase, localCount)
   - Modified vm_Comparators and other macros for gEvalStack[]

3. **c2-vm-commands-v13.pb**
   - C2CALL: Allocate in gLocal[], copy params from gEvalStack[]
   - C2Return/F/S: Clear gLocal[], push result to gEvalStack[]
   - LFETCH/LSTORE: Use gLocal[] and gEvalStack[]
   - LMOV/LGMOV/LLMOV: Cross-array operations
   - All arithmetic/comparison: Use gEvalStack[]

4. **c2-builtins-v05.pbi**
   - All builtin functions read params from gEvalStack[]

5. **c2-arrays-v04.pbi**
   - Array operations use gEvalStack[] for index values

6. **c2-collections-v02.pbi**
   - Collection operations use gEvalStack[] for values

7. **c2-pointers-v04.pbi**
   - Pointer operations use gEvalStack[] for values

## Migration from Unified System

### For Users
- **No changes needed** to .lj source files
- Same syntax, same semantics
- Compiled bytecode format unchanged

### For Developers
- Local variables now in gLocal[] (not gVar[])
- Evaluation stack now in gEvalStack[] (not gVar[])
- paramOffset >= 0 means: actualSlot = gLocalBase + paramOffset
- sp now indexes into gEvalStack[], starts at 0

## Example: Nested Function Calls

```
Before outer() call:
   gLocalBase = 0
   gLocalTop = 0
   sp = 0

During outer() execution:
   outer's locals → gLocal[0..1]
   gLocalBase = 0
   gLocalTop = 2

During inner() call (nested):
   inner's locals → gLocal[2..4]
   gLocalBase = 2
   gLocalTop = 5

After inner() returns:
   gLocalBase = 0 (restored)
   gLocalTop = 2 (restored)

After outer() returns:
   gLocalBase = 0
   gLocalTop = 0
```

## Summary

The isolated variable system (V1.31.0) is a **major architectural improvement** that eliminates the overlap bugs possible in the unified system. By using three completely separate arrays for globals, locals, and evaluation stack, the system is more robust, easier to understand, and simpler to maintain.

**Version**: 1.31.0
**Date**: December 2025
**Status**: Implemented
**Previous System**: Unified Variable System (V1.18.0)
