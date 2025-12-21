# LJ2 Implementation Status
Version: 1.033.57
Date: December 2025

## Current File Versions

| Component | File | Description |
|-----------|------|-------------|
| Main compiler | `c2-modules-V21.pb` | Scanner, preprocessor, main entry |
| Definitions | `c2-inc-v17.pbi` | Constants, opcodes, structures |
| AST parser | `c2-ast-v06.pbi` | Recursive descent parser |
| Code generator | `c2-codegen-v06.pbi` | AST to bytecode |
| Scanner | `c2-scanner-v05.pbi` | Tokenizer |
| Type inference | `c2-typeinfer-V01.pbi` | Unified type resolution (NEW) |
| Postprocessor | `c2-postprocessor-V10.pbi` | Correctness passes only |
| Optimizer | `c2-optimizer-V01.pbi` | Peephole and fusion optimizations |
| VM core | `c2-vm-V16.pb` | Virtual machine execution |
| VM commands | `c2-vm-commands-v14.pb` | Opcode implementations |
| Arrays | `c2-arrays-v05.pbi` | Array operations |
| Pointers | `c2-pointers-v05.pbi` | Pointer operations |
| Collections | `c2-collections-v03.pbi` | Lists and Maps |
| Built-ins | `c2-builtins-v06.pbi` | Built-in functions |
| Test runner | `run-tests-win.ps1` | Windows PowerShell test runner |
| Quick test | `quick-test.ps1` | Fast test runner (excludes long tests) |

## Implemented Features

### Core Language
- [x] Variables (int, float, string)
- [x] Type annotations (.i, .f, .s)
- [x] Type inference
- [x] Operators (+, -, *, /, %, ==, !=, <, >, <=, >=, &&, ||, !)
- [x] Compound assignment (+=, -=, *=, /=, %=)
- [x] Increment/decrement (++, --)
- [x] Ternary operator (? :)

### Control Flow
- [x] if/else statements
- [x] while loops
- [x] for loops (with i++, i = i + n, i += n support)
- [x] switch/case statements
- [x] break/continue

### Functions
- [x] Function declarations
- [x] Parameters and return values
- [x] Local variables
- [x] Recursion
- [x] Function pointers

### Arrays
- [x] Global arrays (array name.type[size])
- [x] Local arrays
- [x] Multi-dimensional concept via struct arrays
- [x] Array keyword alias: `arr`

### Structures
- [x] Struct definitions
- [x] Struct instances
- [x] Field access (struct\field)
- [x] Struct initialization ({val1, val2, ...})
- [x] Arrays of structs

### Pointers
- [x] Pointer declarations (*ptr)
- [x] Address-of operator (&var)
- [x] Pointer dereference
- [x] Struct pointers (ptr\field)
- [x] Pointer arithmetic
- [x] Function pointers

### Built-in Functions
- [x] print() - console output
- [x] random() - random numbers
- [x] abs(), min(), max()
- [x] sqrt(), sin(), cos(), tan(), acos(), asin(), atan()
- [x] log(), log10(), exp(), pow()
- [x] floor(), ceil(), round()
- [x] strlen(), left(), right(), mid()
- [x] str(), val(), chr(), asc()
- [x] assertEqual(), assertFloatEqual(), assertStringEqual()

### Pragmas
- [x] #pragma optimizecode on/off
- [x] #pragma ListASM on/off
- [x] #pragma console on/off
- [x] #pragma ftoi "truncate"/"round"
- [x] And many more...

## VM Optimizations

### Specialized Opcodes
- Type-specific operations (INT, FLOAT, STR variants)
- Optimized array access (global vs local, optimized index vs stack index)
- 24 specialized array store variants
- 12 specialized array fetch variants
- 60 specialized pointer opcodes (eliminates runtime ptrType checks):
  - FETPTR_VI/VF/VS: Simple variable pointer fetch (direct memory)
  - FETPTR_AI/AF/AS: Array element pointer fetch (slot+index)
  - FETPTR_LVI/LVF/LVS: Local variable pointer fetch
  - FETPTR_LAI/LAF/LAS: Local array element pointer fetch
  - STOPTR variants for all above patterns
  - Typed pointer arithmetic (PTRADD/SUB_I/F/S/A)
  - Typed increment/decrement (pre/post variants)

### Compiler Pipeline
1. **TypeInference** (c2-typeinfer-V01.pbi) - Unified type resolution:
   - Phase A: Pointer type discovery
   - Phase B: Opcode specialization (generic → typed variants)
   - Phase B2: Array variant specialization (36 variants)
   - Phase B3: PTRFETCH specialization
   - Phase B4: Print type fixups
2. **PostProcessor** (c2-postprocessor-V10.pbi) - Correctness passes:
   - Implicit returns
   - Return value type conversions
   - Collection opcode typing
3. **Optimizer** (c2-optimizer-V01.pbi) - Performance optimizations:
   - Peephole optimization
   - Instruction fusion (LLMOV, etc.)

## Test Suite

Located in `Examples/`:
- Comprehensive tests (01-51)
- Feature-specific tests
- AVL tree implementation (51)
- Mandelbrot set renderer (19)
- Julia set renderer (21)

## Recent Changes (v1.031.x - v1.033.x)

### v1.033.57
- **Large Function Support**: Added #C2MAXFUNCTIONS = 8192 constant for function-indexed arrays
- Increased gFuncLocalArraySlots, gFuncNames, gLocalNames array capacities from 512 to 8192
- Fixed PureBasic 2D array ReDim limitation (only last dimension can be resized)
- Removed ReDim calls that were shrinking arrays on multi-run sessions
- Fixed hardcoded 512 limits in c2-typeinfer-V01.pbi
- Successfully compiles stress test with 4,100+ functions, 5,045 lines of code
- All tests pass

### v1.033.53
- **Function Limit Bug Fix**: Changed #C2FUNCSTART from 2 to 1000
- Function IDs now start at offset 1000, allowing 997+ user-defined functions
- Previous limit of ~170 functions was due to collision with special variable slots
- All tests pass

### v1.033.48
- Fixed array bounds errors in IDE debugger during VM execution
- Changed vmTransferMetaToRuntime() to dynamically resize gVar instead of returning early
- Moved gVar resize logic to run AFTER pragmas are processed, ensuring correct size
- Fixes issue where pragma GlobalStack could shrink gVar below required slot count
- All 75 tests pass

### v1.033.47
- Fixed array bounds errors in IDE debugger (Test 999)
- Added gGlobalTemplate reset in Init() to prevent stale template data between compilations
- Added bounds verification before accessing gGlobalTemplate and gVar arrays in vmTransferMetaToRuntime()
- Added dynamic gVar resizing in vmInitVM() when gnLastVariable exceeds default size
- Prevents IDE debugger array index out of bounds errors during VM execution
- All 75 tests pass

### v1.033.46
- **VM Independence**: Removed all gVarMeta references from VM code
- Extended stVarTemplate structure with flags, elementSize, paramOffset fields
- Postprocessor now populates complete template for all variables
- VM uses only gGlobalTemplate for runtime initialization
- Prepares for future compiler/VM separation (JSON/XML bytecode loading)
- All 75 tests pass

### v1.033.45
- Fixed pointer detection for local variables used with increment/decrement (Test 064)
- TypeInference Phase A7 detects LINCV/LDECV followed by POP as pointer pattern
- Local variables like `left++` and `right--` in pointer traversal now correctly marked as pointers
- Enables LLPMOV fusion instead of LLMOV for pointer-preserving local-to-local moves
- All 75 tests pass

### v1.033.44
- Fixed pointer array swap operations (Test 062 pointer array reordering)
- Pointer arrays (`array *name[n]`) now marked with ARRAY | POINTER flags
- TypeInference Phase B5 converts POP to PPOP after pointer array fetch
- Ensures pointer metadata is preserved when swapping elements in pointer arrays
- All 75 tests pass

### v1.033.43
- Added -x/--autoquit command line option to set auto-close timer
- Usage: `lj2.exe -x 5 program.lj` or `lj2.exe --autoquit 5 program.lj`
- Equivalent to adding `#pragma autoclose 5` to the source file
- Timer shows countdown message and closes window after specified seconds

### v1.033.42
- Fixed TypeInference prefix matching to handle leading underscore in variable names
- Variable names like `_funcname_varname` now correctly match function context
- Added LLPMOV opcode for pointer-aware local-to-local moves
- Optimizer now fuses PLFETCH+PLSTORE into LLPMOV for pointer assignments
- A6 phase propagates pointer types through LFETCH+LSTORE sequences
- All 75 tests pass

### v1.033.39
- Added specialized pointer opcode names to data section for ASM listing
- Complete set of 60 specialized pointer opcodes for fetch/store/arithmetic
- Opcodes now display correctly in ASM output (FETPTR_VI, STOPTR_AI, etc.)
- Removed debug statements from VM (C2JZ, C2CALL, C2Return tracing)

### v1.033.22
- Auto-disable RunThreaded when --test mode is active (fixes hanging tests)
- Updated quick-test.ps1 to exclude tests 064, 069 (RunThreaded issues)
- All 62 quick tests pass

### v1.033.21
- Major refactoring: Type inference consolidated into single module (c2-typeinfer-V01.pbi)
- Created c2-postprocessor-V10.pbi with only correctness passes (6-8)
- Type inference passes (1-5) moved from PostProcessor to TypeInference module
- All 63 tests pass with new architecture
- Updated quick-test.ps1 to exclude hanging tests (069, 120, 122)

### v1.033.20
- Created unified type inference module (c2-typeinfer-V01.pbi)
- Backup before major refactoring

### v1.033.19
- Fixed c2tokens Data section alignment (added missing VOID entry)
- ASM listing now shows correct opcode descriptions (SUB shows "-", MUL shows "*", etc.)

### v1.033.17-18
- Enhanced ASMLine macro with meaningful operation descriptions
- Added function name lookup tables (gFuncNames) for ASM display
- CALL opcodes now show function names in ASM output

### v1.033.14
- Added LLMOV fusion optimization (LFETCH+LSTORE → LLMOV)
- New optimizer module (c2-optimizer-V01.pbi)

### v1.031.120
- Added --test/-t command line flag for headless console output
- Re-enabled PUSH_IMM optimization for immediate values
- Increased stack size to 8MB via linker.txt
- Added Windows test runner (run-tests-win.ps1)

### v1.031.103
- Linux GUI now runs non-threaded (GTK threading fix)
- Windows GUI uses threading with queue-based updates
- Added collections module (c2-collections-v02.pbi)
- Improved isolated variable system

## Backup System

Backups stored in `backups/` folder:
- 7z archives with version numbers
- Include source files (.pb, .pbi)
- Include examples (Examples/*.lj)
- Include version file (_lj2.ver)

## Architecture Notes

- VM execution speed prioritized
- Definitions at procedure start (PureBasic requirement)
- Global variables for state (no procedure statics)
- TypeInference module handles all type resolution (VM stays simple)
- PostProcessor handles correctness only (implicit returns, type conversions, collections)
- gVarMeta NOT used in VM code

---
End of Status Report
