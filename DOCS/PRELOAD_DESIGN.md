# Variable Preloading Design Document
## Version 1.023.0 - Major Refactor

### Goals
1. **Runtime-allocated gVar** - Dynamic allocation for better memory management/cleanup
2. **Variable preloading** - Remove redundant MOV/PUSH instructions for constants
3. **Function templates** - Pre-initialized local variable templates per function
4. **Global template** - Pre-initialized global variables copied at VM start

### Current Flow (Before)
```
; Function with 3 locals: int a = 10, int b = 20, int c
CALL funcAddr, 0, 3, 0     ; 0 params, 3 locals
LMOV 0, [slot_10]          ; a = 10  (instruction)
LMOV 1, [slot_20]          ; b = 20  (instruction)
; c is uninitialized (random value)
```

### New Flow (After)
```
; Function template[funcId] already contains: {10, 20, 0}
CALL funcAddr, 0, 3, 0     ; 0 params, 3 locals
; CopyStructure happens inside C2CALL - no LMOV needed!
; Only runtime-computed inits generate LMOV:
; e.g., LMOV 2, result_of_func()
```

---

## Data Structures

### 1. Global Template (NEW)
```purebasic
; Compile-time: built during codegen
Global Dim gGlobalTemplate.stVT(0)  ; Resized to gnGlobalVariables

; At VM init (before pc=0):
; CopyArray(gGlobalTemplate(), gVar(), 0, gnGlobalVariables-1)
```

### 2. Function Templates (NEW)
```purebasic
Structure stFuncTemplate
  funcId.i
  localCount.i              ; Total local slots (params + locals)
  paramCount.i              ; Number of parameters (not preloaded - passed at runtime)
  Array template.stVT(0)    ; Pre-initialized values for locals[paramCount..localCount-1]
EndStructure

Global Dim gFuncTemplates.stFuncTemplate(0)  ; Indexed by funcId
```

### 3. Runtime gVar (MODIFIED)
```purebasic
; Keep existing array structure - PureBasic arrays are heap-allocated
Global Dim gVar.stVT(#C2MAXCONSTANTS)

; VM Reset between runs:
Procedure VM_Reset()
  ; Clear all slots (ClearStructure frees strings/nested memory)
  For i = 0 To gVarCapacity - 1
    ClearStructure(@gVar(i), stVT)
  Next

  ; Preload globals from template using CopyStructure
  ; CopyStructure allocates fresh memory for strings automatically
  For i = 0 To gnGlobalVariables - 1
    CopyStructure(gGlobalTemplate(i), gVar(i), stVT)
  Next
EndProcedure
```

**Key Insight**: PureBasic's `CopyStructure()` performs deep copy with automatic memory allocation for strings and nested structures. This eliminates manual memory management.

---

## Compiler Changes

### Codegen Phase

#### A. Track Constant Initializations
When processing variable declarations with constant initializers:
```
int x = 10;      -> Don't emit LMOV, store 10 in template
float y = 3.14;  -> Don't emit LMOVF, store 3.14 in template
string s = "hi"; -> Don't emit LMOVS, store "hi" in template
```

#### B. Emit LMOV Only for Runtime Values
```
int x = func();  -> Still emit: CALL func; LSTORE 0
int y = a + b;   -> Still emit expression code + LSTORE
```

#### C. Build Templates During Codegen
```purebasic
; For each function, track initial values:
Structure stLocalInit
  slot.i          ; Local slot index (0-based from params)
  valueInt.i
  valueFloat.d
  valueString.s
  hasInit.b       ; True if constant init provided
EndStructure

; Per-function during codegen:
Global NewList currentFuncInits.stLocalInit()
```

### Postprocessor Phase

#### Build Final Templates
After all code generated, postprocessor:
1. Creates `gGlobalTemplate()` from `gVarMeta()` constant values
2. Creates `gFuncTemplates()` for each function from tracked inits

---

## VM Changes

### 1. Initialization (Before pc=0)
```purebasic
Procedure VM_Initialize()
  ; Reset gVar to clean state
  ReDim gVar.stVT(gVarCapacity)

  ; Preload globals from template
  For i = 0 To gnGlobalVariables - 1
    CopyStructure(gGlobalTemplate(i), gVar(i), stVT)
  Next

  ; Reset stack
  sp = gnGlobalVariables  ; Evaluation stack starts after globals
  pc = 0
  gStackDepth = -1
EndProcedure
```

### 2. C2CALL Modification
```purebasic
Procedure C2CALL()
  ; ... existing frame setup (gStackDepth++, save frame) ...

  ; NEW: Preload non-parameter locals from template
  ; Parameters are at LOCAL[0..nParams-1], already set from caller's stack
  ; Template covers LOCAL[nParams..totalVars-1] - the actual local variables

  If funcId >= 0 And funcId < ArraySize(gFuncTemplates())
    templateCount = gFuncTemplates(funcId)\localCount  ; Non-param locals only

    If templateCount > 0
      ; Copy template values to local slots AFTER parameters
      dstStart = localSlotStart + nParams
      For i = 0 To templateCount - 1
        ; CopyStructure: deep copy with automatic string/memory allocation
        CopyStructure(gFuncTemplates(funcId)\template(i), gVar(dstStart + i), stVT)
      Next
    EndIf
  EndIf

  ; Arrays still need ReDim (template has size metadata, not allocated elements)
  ; ... existing array allocation code ...
EndProcedure
```

### 3. C2Return - No Change
Return already clears strings/arrays. Template approach doesn't affect cleanup.

---

## Optimization Analysis

### Instructions Saved Per Function Call
| Scenario | Before | After | Savings |
|----------|--------|-------|---------|
| 5 locals with const init | 5 LMOV | 1 CopyStruct | 4 opcodes |
| 10 locals with const init | 10 LMOV | 1 CopyStruct | 9 opcodes |
| Mixed (3 const, 2 runtime) | 5 LMOV | 1 CopyStruct + 2 LMOV | 2 opcodes |

### Memory Trade-off
- Extra memory: ~SizeOf(stVT) * totalLocals per function
- For 50 functions with avg 5 locals: 50 * 5 * ~40 bytes = ~10KB
- Acceptable for execution speed gain

---

## Implementation Phases

### Phase 1: Infrastructure
- [ ] Add template structures to c2-inc
- [ ] Add template arrays (gGlobalTemplate, gFuncTemplates)
- [ ] Modify VM init to use global template

### Phase 2: Codegen Changes
- [ ] Track constant initializations separately
- [ ] Skip LMOV/LMOVF/LMOVS for constant inits
- [ ] Store init values in metadata for postprocessor

### Phase 3: Postprocessor
- [ ] Build gGlobalTemplate from gVarMeta constant values
- [ ] Build gFuncTemplates for each function

### Phase 4: VM C2CALL
- [ ] Add template copy logic to C2CALL
- [ ] Ensure params not overwritten by template

### Phase 5: Testing & Optimization
- [ ] Verify all examples still work
- [ ] Benchmark function call overhead
- [ ] Profile memory usage

---

## Risk Mitigation

1. **Backward Compatibility**: Keep existing LMOV opcodes working; template is additive
2. **Incremental Rollout**: Can enable/disable via pragma during development
3. **Fallback**: If template missing, fall back to zero-init (current behavior without LMOV)

---

## Resolved Design Decisions

1. **String handling**: `CopyStructure()` automatically allocates fresh string memory
   - No aliasing issues - each call gets independent string copies
   - `ClearStructure()` on return properly frees string memory

2. **Struct locals**: Template includes full struct layout
   - All fields pre-zeroed or initialized with constant values
   - `CopyStructure()` handles nested structures automatically

3. **Array elements**: Template has size metadata only
   - `ReDim` still needed at call time for element allocation
   - Template stores `dta\size` for the array dimension