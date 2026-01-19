# D+AI Postprocessor Pass Analysis

## Current Passes Summary (c2-postprocessor-V08.pbi)

### Helper Functions (run before/after PostProcessor)
- `GenerateStructTypeBitmap()` - Helper for struct collections
- `InitJumpTracker()` - Populates jump tracker BEFORE postprocessor
- `FixJMP()` - Runs AFTER postprocessor, recalculates jump offsets

---

## ESSENTIAL PASSES (Correctness - Must Run)

### Pass 1: Pointer Type Tracking
- **Purpose**: Mark variables assigned from pointer sources
- **Pattern**: GETADDR/GETARRAYADDR/PTRADD/PTRSUB + STORE → mark variable in mapVariableTypes
- **Category**: TYPE RESOLUTION

### Pass 1a: Mark Variables Used with Pointer Operations
- **Purpose**: Variables used with PTRFETCH/PTRSTORE are pointers
- **Pattern**: FETCH + PTRFETCH → mark fetched variable as pointer
- **Category**: TYPE RESOLUTION

### Pass 1b: Track Pointer Parameters via PTRFETCH Usage
- **Purpose**: Mark function parameters used as pointers
- **Pattern**: PLFETCH/LFETCH + PTRFETCH → mark parameter as pointer
- **Category**: TYPE RESOLUTION

### Pass 2: Type-Based Opcode Fixups
- **Purpose**: Convert generic opcodes to typed variants based on variable types
- **Conversions**:
  - PUSH → PUSHF/PUSHS (based on variable type)
  - GETADDR → GETADDRF/GETADDRS
  - FETCH → PFETCH (for pointers)
  - STORE → PSTORE (for pointers)
  - POP → PPOP (for pointers)
  - MOV → PMOV (for pointers)
  - LFETCH → PLFETCH (for pointer locals)
  - LSTORE → PLSTORE (for pointer locals)
  - INC_VAR → PTRINC_* variants (array/string/float/int)
  - DEC_VAR → PTRDEC_* variants
  - ADD → PTRADD (for pointer arithmetic)
  - SUB → PTRSUB (for pointer arithmetic)
  - PRTI → PRTF/PRTS (based on value being printed)
- **Category**: TYPE SPECIALIZATION

### Pass 3: Convert Generic PTRFETCH to Typed Variants
- **Purpose**: Eliminate runtime type checking in pointer dereference
- **Conversions**:
  - PTRFETCH → PTRFETCH_VAR_INT/FLOAT/STR (simple variable pointers)
  - PTRFETCH → PTRFETCH_ARREL_INT/FLOAT/STR (array element pointers)
- **Category**: TYPE SPECIALIZATION

### Pass 6: Fix Print Types After PTRFETCH Typing
- **Purpose**: Match print opcode to PTRFETCH variant type
- **Pattern**: PTRFETCH_*_FLOAT + PRTI → PRTF
- **Category**: TYPE SPECIALIZATION

### Pass 8: Use PRTPTR After Generic PTRFETCH
- **Purpose**: Handle mixed-type pointer arrays at runtime
- **Pattern**: generic PTRFETCH + PRTI/PRTF/PRTS → PRTPTR
- **Category**: TYPE SPECIALIZATION

### Pass 10: Type Array Operations
- **Purpose**: Convert generic array ops to typed versions
- **Conversions**:
  - ARRAYFETCH → ARRAYFETCH_INT/FLOAT/STR
  - ARRAYSTORE → ARRAYSTORE_INT/FLOAT/STR
- **Category**: TYPE SPECIALIZATION

### Pass 12: Specialize Array Opcodes
- **Purpose**: Eliminate runtime branching in array operations
- **Variants**: GLOBAL/LOCAL × OPT/LOPT/STACK (index) × OPT/LOPT/STACK (value)
- **Example**: ARRAYFETCH_INT → ARRAYFETCH_INT_GLOBAL_OPT
- **Category**: TYPE SPECIALIZATION

### Pass 12b: Specialize Struct Opcodes
- **Purpose**: Handle local pointers and values for struct operations
- **Converts**: PTRSTRUCTFETCH/STORE to LPTR/LOPT variants
- **Category**: TYPE SPECIALIZATION

### Pass 13: Add Implicit Returns
- **Purpose**: Ensure functions have proper RET instructions
- **Action**: Insert RETURN before function markers if missing
- **Category**: CORRECTNESS

### Pass 21: Return Value Type Conversions
- **Purpose**: Insert type conversion before return statements
- **Conversions**: FTOI, ITOF, FTOS, ITOS as needed
- **Category**: TYPE COERCION

### Pass 27: Convert Collection Opcodes to Typed Versions
- **Purpose**: Type specialization for LIST/MAP operations
- **Conversions**:
  - LIST_ADD/GET/SET/INSERT → _INT/_FLOAT/_STR/_STRUCT variants
  - MAP_PUT/GET/VALUE → _INT/_FLOAT/_STR/_STRUCT variants
- **Category**: TYPE SPECIALIZATION

### Template Building (unnumbered)
- **Purpose**: Build gGlobalTemplate and gFuncTemplates for variable preloading
- **Category**: RUNTIME INITIALIZATION

---

## OPTIMIZATION PASSES (Performance - Can Be Separate)

### Pass 9: Array Index Optimization
- **Purpose**: Eliminate stack operations for array indexing
- **Pattern**: PUSH index + ARRAYFETCH/STORE → fold index into ndx field, PUSH→NOOP
- **Benefit**: Removes 1 instruction per array access
- **Category**: INSTRUCTION FUSION

### Pass 11: Fold Value PUSH into ARRAYSTORE
- **Purpose**: Eliminate stack for array value storage
- **Pattern**: PUSH value + ARRAYSTORE → fold value into n field, PUSH→NOOP
- **Benefit**: Removes 1 instruction per array store
- **Category**: INSTRUCTION FUSION

### Pass 14: Redundant Assignment Elimination
- **Purpose**: Remove x = x patterns
- **Pattern**: FETCH var + STORE same_var → both NOOP
- **Category**: PEEPHOLE

### Pass 15: Dead Code Elimination
- **Purpose**: Remove unused stack operations
- **Pattern**: PUSH/FETCH + POP → both NOOP
- **Category**: PEEPHOLE

### Pass 16: Constant Folding (Integer)
- **Purpose**: Evaluate constant expressions at compile time
- **Pattern**: PUSH const1 + PUSH const2 + ADD/SUB/MUL/DIV/MOD → PUSH result
- **Category**: CONSTANT FOLDING

### Pass 17: Constant Folding (Float)
- **Purpose**: Evaluate float constant expressions at compile time
- **Pattern**: PUSHF const1 + PUSHF const2 + FLOATADD/SUB/MUL/DIV → PUSHF result
- **Category**: CONSTANT FOLDING

### Pass 18: Arithmetic Identity Optimizations
- **Purpose**: Remove identity operations
- **Patterns**:
  - x + 0 → x (remove PUSH 0 + ADD)
  - x - 0 → x (remove PUSH 0 + SUB)
  - x * 1 → x (remove PUSH 1 + MUL)
  - x / 1 → x (remove PUSH 1 + DIV)
  - x * 0 → 0 (remove x + MUL)
- **Category**: PEEPHOLE

### Pass 19: String Identity Optimization
- **Purpose**: Remove empty string concatenation
- **Pattern**: str + "" → str (remove PUSHS "" + STRADD)
- **Category**: PEEPHOLE

### Pass 20: String Constant Folding
- **Purpose**: Concatenate string constants at compile time
- **Pattern**: PUSHS "a" + PUSHS "b" + STRADD → PUSHS "ab"
- **Category**: CONSTANT FOLDING

### Pass 23: Compound Assignment Optimization
- **Purpose**: Use in-place arithmetic operations
- **Pattern**: FETCH var + PUSH val + ADD + STORE var → ADD_ASSIGN_VAR
- **Benefit**: Eliminates 2 instructions (FETCH and STORE)
- **Category**: INSTRUCTION FUSION

### Pass 23b: Pointer Compound Assignments
- **Purpose**: Convert compound assignments on pointers
- **Pattern**: ADD_ASSIGN_VAR (pointer) → PTRADD_ASSIGN_* variant
- **Category**: TYPE SPECIALIZATION (should stay with postprocessor)

### Pass 24: Increment/Decrement + POP Optimization
- **Purpose**: Simplify standalone increment/decrement
- **Pattern**: INC_VAR_PRE/POST + POP → INC_VAR (remove POP)
- **Category**: PEEPHOLE

### Pass 26: Preload Optimization
- **Purpose**: Remove MOV for preloadable variables
- **Pattern**: MOV/LMOV for preload variables → NOOP (value comes from template)
- **Category**: TEMPLATE OPTIMIZATION

### Pass 28: PUSH_IMM Optimization
- **Purpose**: Use immediate values instead of variable lookup
- **Pattern**: PUSH (int constant) → PUSH_IMM (actual value)
- **Benefit**: Eliminates gVarMeta lookup in VM
- **Category**: IMMEDIATE VALUE

---

## DISABLED PASSES
- Pass 4, 5: Removed (arrays of pointers preserve full metadata)
- Pass 7: Replaced by Pass 8 (PRTPTR)
- Pass 22: CodeGenerator handles returns correctly
- Pass 25 (inside optimization block): NOOPs deleted in FixJMP instead

---

## PASS DEPENDENCIES

```
InitJumpTracker() - must run BEFORE PostProcessor
    ↓
PostProcessor()
    ├── Pass 1, 1a, 1b (Pointer tracking) - must run first
    ├── Pass 2 (Type fixups) - depends on pointer tracking
    ├── Pass 3 (PTRFETCH typing) - depends on Pass 2
    ├── Pass 6, 8 (Print fixups) - depends on Pass 3
    ├── Pass 10, 12, 12b (Array/Struct specialization)
    ├── Pass 13 (Implicit returns) - independent
    ├── Pass 21 (Return type conversion) - must be after type resolution
    ├── Pass 27 (Collection typing) - must be after Pass 10
    │
    └── OPTIMIZATIONS (if enabled):
        ├── Pass 9, 11 (Array fusion) - before Pass 12
        ├── Pass 14, 15 (Dead code) - can run anytime
        ├── Pass 16, 17, 18, 19, 20 (Constant folding/identity)
        ├── Pass 23, 23b (Compound assign) - after Pass 2
        ├── Pass 24 (Inc/Dec + POP)
        ├── Template Building
        ├── Pass 26 (Preload opt) - after templates
        └── Pass 28 (PUSH_IMM) - MUST BE LAST (changes operand meaning)
    ↓
FixJMP() - must run AFTER PostProcessor
    ├── Pass 25a (NOOP→RETURN at function ends)
    ├── Delete NOOPs
    └── Recalculate jump offsets
```

---

## IMPLEMENTED SPLIT (V1.033.0)

### c2-postprocessor-V09.pbi (Essential - Correctness)
**8 consolidated passes for correctness:**

| Pass | Purpose | Consolidates |
|------|---------|--------------|
| 1 | Pointer type tracking | Old Pass 1, 1a, 1b |
| 2 | Type-based opcode fixups | Old Pass 2 |
| 3 | PTRFETCH specialization | Old Pass 3 |
| 4 | Print type fixups | Old Pass 6, 8 |
| 5 | Array/Struct typing and specialization | Old Pass 10, 12, 12b |
| 6 | Add implicit returns | Old Pass 13 |
| 7 | Return value type conversions | Old Pass 21 |
| 8 | Collection opcode typing | Old Pass 27 |

**Also includes:**
- `InitJumpTracker()` - Populates jump tracker before optimization
- `FixJMP()` - Recalculates jump offsets after NOOP removal
- Template building for variable preloading

### c2-optimizer-V01.pbi (Performance - Peephole)
**5 optimization passes:**

| Pass | Purpose | Pattern |
|------|---------|---------|
| 1 | Instruction Fusion | PUSH + ARRAYFETCH → fold index; PUSH + ARRAYSTORE → fold value |
| 2 | Peephole (single pass) | Dead code, redundant assign, constant folding, identities, inc/dec+POP |
| 3 | Compound Assignment | FETCH + PUSH + OP + STORE → compound assign (+ pointer variants) |
| 4 | Preload Optimization | MOV/LMOV for preload vars → NOOP |
| 5 | PUSH_IMM Conversion | PUSH (int const) → PUSH_IMM (MUST BE LAST) |

**Peephole patterns in Pass 2:**
- FETCH var + STORE same_var → NOOP both
- PUSH/FETCH + POP → NOOP both
- PUSH const + PUSH const + OP → PUSH result (int/float/string)
- PUSH 0/1 + ADD/SUB/MUL/DIV → identity optimizations
- PUSHS "" + STRADD → remove
- INC/DEC_PRE/POST + POP → INC/DEC

---

## BENEFITS OF SPLIT

1. **Clarity**: Essential passes clearly separated from optimizations
2. **Debuggability**: Can disable optimizer entirely to debug issues
3. **Maintainability**: Peephole patterns easier to add/modify
4. **Performance**: Single-pass peephole more efficient than multiple passes
5. **Correctness**: Essential passes never accidentally disabled

## PASS REDUCTION ACHIEVED

| Before (V08) | After (V09 + Optimizer V01) |
|--------------|----------------------------|
| 28+ passes | 8 postprocessor + 5 optimizer = **13 passes** |

**Consolidation summary:**
- Pass 1, 1a, 1b → Single Pass 1 (pointer tracking)
- Pass 6, 8 → Pass 4 (print fixups)
- Pass 10, 12, 12b → Pass 5 (array/struct typing)
- Pass 14, 15, 16, 17, 18, 19, 20, 24 → Optimizer Pass 2 (single peephole pass)
- Pass 23, 23b → Optimizer Pass 3 (compound assignment)