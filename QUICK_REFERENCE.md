# LJ2 Quick Reference

## File Locations Cheat Sheet

| What | Where |
|------|-------|
| Main compiler | `c2-modules-V13.pb` |
| Global definitions | `c2-inc-v09.pbi` |
| Optimizations | `c2-postprocessor-V02.pbi` |
| VM core | `c2-vm-V08.pb` |
| VM instructions | `c2-vm-commands-v06.pb` |
| Test runner | `pbtester.pb` |
| Examples | `Examples/*.lj` |

## Key Global Variables

```purebasic
; Compile-time
Global Dim gVarMeta.stVarMeta()        ; Variable metadata
Global NewList llObjects.stType()      ; Instruction list (pre-VM)
Global NewMap mapPragmas.s()           ; Pragma settings
Global Dim gFuncLocalArraySlots.i()    ; [funcID, arrayIdx] → varSlot

; Runtime
Global Dim arCode.stCodeIns()          ; Bytecode array
Global Dim gVar.stVar()                ; Global variables
Global Dim gStack.stStack()            ; Call stack
Global pc.i                            ; Program counter
Global sp.i                            ; Stack pointer
Global gStackDepth.i                   ; Current call depth
```

## Instruction Structure Quick View

```purebasic
; Compile-time (llObjects)
Structure stType
   code.l      ; Opcode
   i.l         ; Operand 1 / varSlot / PC address
   j.l         ; Operand 2 / is_local / param count
   n.l         ; Operand 3 / varSlot for typing / local count
   ndx.l       ; Index / optimized index / array count
   flags.b     ; Function ID
EndStructure

; Runtime (arCode)
Structure stCodeIns
   ; Same fields as stType
EndStructure
```

## Common Patterns

### Adding a New Opcode

1. **Define constant** in `c2-inc-v09.pbi`:
   ```purebasic
   #ljMYOPCODE = 123
   ```

2. **Emit in CodeGenerator** (`c2-modules-V13.pb`):
   ```purebasic
   Case #ljMyNode
      CodeGenerator(*x\left)
      EmitInt(#ljMYOPCODE, operand)
   ```

3. **Implement VM handler** (`c2-vm-commands-v06.pb`):
   ```purebasic
   Procedure C2MYOPCODE()
      ; Implementation
      pc + 1
   EndProcedure
   ```

4. **Add to dispatch** (`c2-vm-V08.pb`):
   ```purebasic
   Case #ljMYOPCODE: C2MYOPCODE()
   ```

5. **Update ASMLine** for disassembly (optional)

### Emitting Instructions

```purebasic
; Simple instruction with one operand
EmitInt(#ljPush, varSlot)

; Instruction with multiple fields
AddElement(llObjects())
llObjects()\code = #ljARRAYFETCH
llObjects()\i = arrayVarSlot
llObjects()\j = isLocal           ; 0=global, 1=local
llObjects()\ndx = -1               ; -1 = index on stack (for PostProcessor)
llObjects()\n = arrayVarSlot       ; For type inference
```

### Accessing Variables

```purebasic
; Get or create variable slot
varSlot = FetchVarOffset(name.s)

; Read metadata
flags = gVarMeta(varSlot)\flags
isArray = Bool(flags & #C2FLAG_ARRAY)
isLocal = Bool(gVarMeta(varSlot)\paramOffset >= 0)

; Runtime access
value = gVar(varSlot)\i            ; Integer
value.d = gVar(varSlot)\f          ; Float
value.s = gVar(varSlot)\ss         ; String
```

### Local Variable Access

```purebasic
; Compile-time: get local offset
paramOffset = gVarMeta(varSlot)\paramOffset

; Emit local fetch
EmitInt(#ljLFETCH, paramOffset)

; Runtime: read local
value = gStack(gStackDepth)\LocalInt(paramOffset)
```

### Array Operations

```purebasic
; CodeGen: emit generic ARRAYFETCH
EmitInt(#ljARRAYFETCH, arrayVarSlot)
llObjects()\j = isLocal
llObjects()\ndx = -1        ; -1 = not optimized yet
llObjects()\n = arrayVarSlot

; PostProcessor: converts to typed variant
; #ljARRAYFETCH → #ljARRAYFETCH_INT_GLOBAL_OPT

; VM: specialized handler
Procedure C2ARRAYFETCH_INT_GLOBAL_OPT()
   varSlot = _AR()\i
   index = gVar(_AR()\ndx)\i
   gVar(sp)\i = gVar(varSlot)\gArray\ar(index)\i
   sp + 1
   pc + 1
EndProcedure
```

## Debugging Tips

### Enable Debug Output

```purebasic
#DEBUG = 1   ; In c2-inc-v09.pbi
```

### Common Debug Points

```purebasic
; After scanner
ForEach TOKEN()
   Debug TOKEN()\Type + " : " + TOKEN()\Value
Next

; After code generation
ForEach llObjects()
   Debug Str(ListIndex(llObjects())) + ": " + OpcodeName(llObjects()\code)
Next

; During VM execution
Debug "PC=" + Str(pc) + " SP=" + Str(sp) + " Opcode=" + OpcodeName(arCode(pc)\code)
```

### Listing Assembly

Add pragma to .lj file:
```c
#pragma ListASM on
```

Or check directly:
```purebasic
C2Lang::ListCode()
```

## Common Gotchas

### 1. Don't Use gVarMeta in VM
**Wrong:**
```purebasic
Procedure C2SOMETHING()
   If gVarMeta(varSlot)\flags & #C2FLAG_INT  ; ❌ BAD
      ; ...
   EndIf
EndProcedure
```

**Right:**
```purebasic
; Resolve types in PostProcessor
; Emit specialized instruction (#ljSOMETHING_INT)
; VM only deals with typed instructions
```

### 2. Preserve Field Values
**Wrong:**
```purebasic
EmitInt(#ljLFETCH, paramOffset)
llObjects()\i = someOtherValue   ; ❌ Overwrites paramOffset!
```

**Right:**
```purebasic
; Check EmitInt() for fields that shouldn't be overwritten
; Add to skip list if needed
```

### 3. Update Include Paths After Renaming
When incrementing module versions, update all XIncludeFile references:
```purebasic
; c2-modules-V13.pb
XIncludeFile "c2-inc-v09.pbi"          ; ✅ Match version
XIncludeFile "c2-vm-V08.pb"            ; ✅ Match version
```

### 4. Array Index Base
**PureBasic arrays are 0-indexed:**
```purebasic
Dim myArray(10)   ; Creates 11 elements: 0-10
```

### 5. String Concatenation
**PureBasic uses + for concatenation:**
```purebasic
str.s = "Hello" + " " + "World"   ; ✅ Correct
```

## Testing Checklist

Before committing changes:

- [ ] Run `Examples/00 comprehensive test.lj`
- [ ] Run `Examples/22 array comprehensive.lj`
- [ ] Run `Examples/bug fix2.lj`
- [ ] Check no assertions fail
- [ ] Test with `#pragma optimizecode on`
- [ ] Test with `#pragma optimizecode off`
- [ ] Verify ListASM output makes sense
- [ ] Update version in `_lj2.ver` (MAJ.MIN.FIX)
- [ ] Backup old modules to `BACKUP/` if needed

## Performance Profiling

### Enable Timing
```purebasic
startTime.q = ElapsedMilliseconds()
; ... run VM ...
Debug "Execution time: " + Str(ElapsedMilliseconds() - startTime) + "ms"
```

### Hotspot Identification
Enable #DEBUG and add counters in VM handlers:
```purebasic
Global callCount.i(500)  ; One per opcode

Procedure C2SOMETHING()
   callCount(#ljSOMETHING) + 1
   ; ...
EndProcedure

; After execution:
For i = 0 To 499
   If callCount(i) > 0
      Debug OpcodeName(i) + ": " + Str(callCount(i))
   EndIf
Next
```

## Quick vim-style Commands

| Command | Action |
|---------|--------|
| F5 | Compile and run (PureBasic IDE) |
| F7 | Compile only |
| Shift+F5 | Run with debugger |
| Ctrl+G | Go to line |
| F1 | PureBasic help |

## Useful File Patterns

```bash
# Find all function definitions
grep -n "^Procedure" *.pb *.pbi

# Find instruction implementations
grep -n "^Procedure.*C2" c2-vm-commands-v06.pb

# Find opcode definitions
grep -n "#lj" c2-inc-v09.pbi

# Find all array operations
grep -n "ARRAY" c2-postprocessor-V02.pbi
```

## Version Control Best Practices

1. **Always increment version** in `_lj2.ver`
2. **Backup before major changes** to `BACKUP/`
3. **Update XIncludeFile paths** when renaming
4. **Test before commit**
5. **Write meaningful commit messages**

Example commit message:
```
Added local array support (v1.17.0)

- Added flags field to instruction structures
- CALL instruction now stores function ID in flags
- Fixed gFuncLocalArraySlots indexing bug
- Updated all module versions (V12→V13, etc.)
```

## Emergency Rollback

If something breaks:
```bash
# 1. Check BACKUP/ folder for previous versions
ls BACKUP/

# 2. Copy back old version
cp BACKUP/c2-modules-V12.pb c2-modules-V13.pb

# 3. Update includes if needed
# 4. Revert _lj2.ver
```

---

**Tip:** Bookmark this file in your editor for quick access!
