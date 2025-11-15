# LJ2 Compiler & Virtual Machine

**Version:** 1.17.0
**Language:** PureBasic (v6.20+)
**Target:** Windows x64 / Linux

## Overview

LJ2 is a high-performance compiler and virtual machine for a simplified C-like language. The project prioritizes **VM execution speed** above all else, implementing aggressive optimizations at both compile-time and runtime.

The language features:
- C-style syntax with semicolon-terminated statements
- Dynamic typing with type inference
- Functions with parameters and local variables
- Arrays (global and local, integer/float/string types)
- Macros with nested expansion
- Pragmas for compile-time configuration
- Built-in assertion functions for testing

## Architecture

### Compiler Pipeline

The LJ2 compiler follows a multi-stage pipeline:

```
Source Code (.lj)
    ↓
[1] Preprocessor  → Macro expansion, pragma processing
    ↓
[2] Scanner       → Tokenization, lexical analysis
    ↓
[3] Parser        → AST construction, syntax analysis
    ↓
[4] Code Generator → Bytecode emission
    ↓
[5] PostProcessor → Type inference, instruction fusion, optimizations
    ↓
[6] FixJMP        → Jump address resolution, function patching
    ↓
Bytecode Array (arCode)
    ↓
[7] Virtual Machine → Execution
```

### Key Design Principles

1. **Speed First**: VM execution performance is the top priority
2. **Type Resolution**: Types are inferred and resolved during PostProcessor phase, eliminating runtime type checks
3. **Instruction Fusion**: Multiple operations are combined into single optimized instructions
4. **Separation of Concerns**: Compile-time metadata (gVarMeta) is never accessed by VM
5. **Stack-Based VM**: Uses hybrid stack + register model for optimal performance

## Project Structure

### Core Modules

| File | Version | Purpose |
|------|---------|---------|
| `c2-modules-V13.pb` | V13 | Main compiler module - orchestrates compilation pipeline |
| `c2-inc-v09.pbi` | v09 | Global definitions, structures, constants, macros |
| `c2-postprocessor-V02.pbi` | V02 | Type inference, optimizations, instruction fusion |
| `c2-vm-V08.pb` | V08 | Virtual machine core, execution loop |
| `c2-vm-commands-v06.pb` | v06 | VM instruction implementations (~150 opcodes) |
| `pbtester.pb` | - | Test harness for running .lj programs |

### Support Files

- `_lj2.ver` - Version tracking (MAJ.MIN.FIX format)
- `CLAUDE.md` - Development guidelines for AI assistance
- `DOCS/` - Detailed documentation on each compiler phase
- `Examples/` - Test programs and language demonstrations
- `BACKUP/` - Previous module versions

## Compiler Phases Explained

### 1. Preprocessor
- Expands macros (supports nested macro calls)
- Processes `#define`, `#pragma`, `#include` directives
- Handles conditional compilation
- Outputs preprocessed token stream

### 2. Scanner
- Tokenizes source code
- Identifies keywords, operators, literals, identifiers
- Tracks line/column for error reporting
- Produces TOKEN() list

### 3. Parser (AST Builder)
- Recursive descent parser
- Builds abstract syntax tree (AST)
- Implements operator precedence
- Validates syntax structure

### 4. Code Generator
- Traverses AST and emits bytecode instructions
- Manages variable allocation (global vs local)
- Handles function calls, parameters, local variables
- Tracks local array metadata in `gFuncLocalArraySlots`
- Emits untyped generic instructions (typing happens in PostProcessor)

### 5. PostProcessor ⭐ **Critical Phase**
The PostProcessor performs multiple optimization passes:

#### Pass 1: Type Inference
- Analyzes variable usage patterns
- Converts generic instructions to typed variants (INT/FLOAT/STR)
- Example: `PUSH` → `PUSHI` / `PUSHF` / `PUSHS`

#### Pass 2: Instruction Fusion
- **Array Index Optimization**: `PUSH index + ARRAYFETCH` → `ARRAYFETCH_OPT` (index in ndx field)
- **Array Value Optimization**: `PUSH value + ARRAYSTORE` → `ARRAYSTORE_OPT` (value in n field)
- **Constant Folding**: `PUSH 2 + PUSH 3 + ADD` → `PUSH 5`
- **Local/Global Specialization**: Creates 8 variants per operation (GLOBAL/LOCAL × OPT/STACK × OPT/STACK)

#### Pass 3: Implicit Returns
- Ensures all functions have proper return instructions
- Prevents fall-through execution bugs

### 6. FixJMP
- Resolves jump addresses after optimizations
- Patches CALL instructions with:
  - `i` field = PC address (for jumping)
  - `flags` field = Function ID (for local array metadata lookup)
  - `j` field = Parameter count
  - `n` field = Local variable count
  - `ndx` field = Local array count
- Converts instruction list (llObjects) to array (arCode)

### 7. Virtual Machine

The VM uses a stack-based architecture with specialized instruction variants for performance:

**Key Features:**
- ~150 specialized opcodes (vs ~20 generic)
- Separate local variable arrays per stack frame (LocalInt, LocalFloat, LocalString)
- Local array support with proper scoping
- Zero-overhead type dispatch (resolved at compile time)
- Optimized array operations (direct register access when possible)

**Execution Model:**
```
gStack[depth]
  ├── LocalInt[]       - Local integer variables
  ├── LocalFloat[]     - Local float variables
  ├── LocalString[]    - Local string variables
  ├── LocalArrays[]    - Local array instances
  ├── pc               - Return address
  └── sp               - Saved stack pointer
```

## Recent Improvements (v1.17.0)

### Local Arrays in Functions
Full support for local arrays with proper scoping and lifetime management:

```c
function processData() {
    array local_ints.i[100];
    array local_floats.f[50];

    // Arrays are automatically allocated on function entry
    // and deallocated on return
}
```

**Implementation:**
- Function ID stored in CALL instruction's `flags` field
- `gFuncLocalArraySlots[funcID, arrayIndex]` maps to variable metadata
- VM allocates local arrays on stack frame creation
- Array metadata populated during CodeGenerator phase

### Instruction Structure Enhancement
Added `flags` field to both compile-time (`stType`) and runtime (`stCodeIns`) structures:

```purebasic
Structure stCodeIns
   code.l      ; Opcode
   i.l         ; Operand 1 / PC address for CALL
   j.l         ; Operand 2 / Param count for CALL
   n.l         ; Operand 3 / Local count for CALL
   ndx.l       ; Index field / Array count for CALL
   flags.b     ; Function ID for CALL (NEW in v1.17)
EndStructure
```

### Bug Fixes
- **LMOV Corruption**: Fixed Select statement in EmitInt that was overwriting local variable indices
- **Array Bounds**: Corrected `gFuncLocalArraySlots` indexing (by function ID, not PC address)
- **Data Loss**: Prevented accidental array clearing during FixJMP phase

## Usage

### Compiling and Running Programs

1. **Open in PureBasic IDE**: Load `c2-modules-V13.pb`
2. **Select Target**: Choose your .lj file at the bottom of the module
3. **Compile**: Press F5 to compile and run
4. **Output**: Results appear in the VM console window

### Example Program

```c
// Example: Array operations with functions
#pragma console on
#pragma appname "Array Demo"
#pragma version

array global_ints.i[10];

function fillArray() {
    array local_data.i[5];

    i = 0;
    while i < 5 {
        local_data[i] = i * 10;
        global_ints[i] = local_data[i];
        i = i + 1;
    }
}

fillArray();

i = 0;
while i < 5 {
    print("global_ints[", i, "] = ", global_ints[i]);
    i = i + 1;
}
```

### Pragma Directives

| Pragma | Values | Purpose |
|--------|--------|---------|
| `appname` | "string" | Sets console window title |
| `console` | on/off | Enables GUI console |
| `consolesize` | "WxH" | Sets console dimensions |
| `version` | - | Prints compiler version |
| `optimizecode` | on/off | Enables/disables optimizations |
| `ListASM` | on/off | Shows generated bytecode |
| `decimals` | N | Float display precision |
| `floattolerance` | N | Float comparison epsilon |
| `FastPrint` | on/off | Buffered vs immediate print |
| `RunThreaded` | on/off | Execute in separate thread |
| `stackspace` | N | Stack size for values |
| `stackdepth` | N | Maximum function call depth |

## Performance Characteristics

### Optimization Examples

**Before Optimization:**
```
PUSH [const_2]      ; Push index
PUSH [const_100]    ; Push value
ARRAYSTORE          ; Store with stack operations
```

**After Optimization:**
```
ARRAYSTORE_INT_GLOBAL_OPT_OPT  ; Single instruction, index=2, value=100
```

This reduces 3 instructions to 1, eliminates 2 stack operations, and resolves types at compile time.

### Instruction Variants

Array operations have 8 specialized variants:
- 2 storage types: GLOBAL / LOCAL
- 2 index sources: OPTIMIZED (in ndx field) / STACK
- 2 value sources: OPTIMIZED (in n field) / STACK

Example: `ARRAYSTORE_INT_LOCAL_OPT_STACK`
- Type: Integer
- Storage: Local array
- Index: Optimized (constant or variable in ndx field)
- Value: From stack

## Development Guidelines

See `CLAUDE.md` for detailed development instructions, including:
- Code style conventions
- Variable naming rules
- PureBasic-specific gotchas
- Testing procedures
- Version management

## Testing

### Test Suite
The `Examples/` folder contains comprehensive tests:
- `00 comprehensive test.lj` - Full language feature test
- `07 Floats and Macros.lj` - Float operations and macro expansion
- `22 array comprehensive.lj` - Array operations (all types)
- `bug fix2.lj` - Local array regression tests

### Running Tests
Use `pbtester.pb` to batch-run test files and verify output.

## Version History

### v1.17.0 (Current)
- ✅ Full local array support in functions
- ✅ Function ID tracking in CALL instructions
- ✅ LMOV instruction fix
- ✅ Module version advancement (V12→V13, v05→v06, etc.)
- ✅ Improved array bounds checking

### v1.16.x Series
- Array implementation and optimization
- Instruction fusion system
- Type inference improvements
- Local variable optimizations

## Documentation

For detailed information on each phase:
- `DOCS/1. lexical.txt` - Scanner/tokenizer
- `DOCS/2. syntax.txt` - Parser/AST builder
- `DOCS/3. AST Interpreter.txt` - AST traversal
- `DOCS/4. code generator.txt` - Bytecode emission
- `DOCS/5. vm.txt` - Virtual machine architecture

## License

Distribute and use freely.
Based on Rosetta Code compiler examples.

---

**Author:** Kingwolf71
**Date:** May 2025
**Platform:** PureBasic 6.21 (Windows x64)
