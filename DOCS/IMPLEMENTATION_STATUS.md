# D+AI Implementation Status
Version: 1.037.4
Date: December 2025

**See also:** [D+AI_Compiler_Report.html](D+AI_Compiler_Report.html) - Comprehensive technical report with ratings

## Current File Versions

| Component | File | Description |
|-----------|------|-------------|
| Main compiler | `c2-modules-V23.pb` | Scanner, preprocessor, main entry |
| Definitions | `c2-inc-v19.pbi` | Constants, opcodes, structures |
| AST parser | `c2-ast-v08.pbi` | Recursive descent parser |
| Code generator | `c2-codegen-v08.pbi` | AST to bytecode (main CodeGenerator) |
| Codegen emit | `c2-codegen-emit.pbi` | EmitInt procedure (instruction emission) |
| Codegen vars | `c2-codegen-vars.pbi` | FetchVarOffset (variable resolution) |
| Codegen types | `c2-codegen-types.pbi` | GetExprResultType, GetExprSlotOrTemp |
| Codegen rules | `c2-codegen-rules.pbi` | Rule-based type dispatch tables |
| Scanner | `c2-scanner-v06.pbi` | Tokenizer |
| Type inference | `c2-typeinfer-V03.pbi` | Unified type resolution |
| Postprocessor | `c2-postprocessor-V12.pbi` | Correctness passes only |
| Optimizer | `c2-optimizer-V03.pbi` | Rule-based peephole/fusion (5 passes) |
| VM core | `c2-vm-V17.pb` | Virtual machine execution |
| VM commands | `c2-vm-commands-v15.pb` | Opcode implementations |
| Arrays | `c2-arrays-v07.pbi` | Array operations (Pointer Array Arch) |
| Pointers | `c2-pointers-v06.pbi` | Pointer operations |
| Collections | `c2-collections-v04.pbi` | Lists and Maps |
| Built-ins | `c2-builtins-v07.pbi` | Built-in functions |
| Test runner | `test/run_all_tests.ps1` | Windows PowerShell test runner (75 examples) |
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
- [x] printf() - C-style formatted output (%d, %f, %s, %.Nf, %%)
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
2. **PostProcessor** (c2-postprocessor-V11.pbi) - Correctness passes:
   - Implicit returns
   - Return value type conversions
   - Collection opcode typing
3. **Optimizer** (c2-optimizer-V02.pbi) - Consolidated 5-pass optimization:
   - Pass 1: Array instruction fusion
   - Pass 2: Unified peephole (dead code, constant folding, MOV fusion, jump opts)
   - Pass 3: Compound assignment optimization
   - Pass 4: Preload optimization
   - Pass 5: PUSH_IMM conversion (must be last)

## Test Suite

Located in `Examples/`:
- Comprehensive tests (01-51)
- Feature-specific tests
- AVL tree implementation (51)
- Mandelbrot set renderer (19)
- Julia set renderer (21)

## Recent Changes (v1.031.x - v1.037.x)

### v1.037.2-4
- **Struct Declaration Bug Fix**: Fixed `p1.Point;` syntax not allocating struct memory properly
  - V1.029.86 code detected pattern but didn't set up gVarMeta with struct information
  - Fixed by extracting variable name and setting up metadata before AST creation
  - Struct fields now properly accessible after declaration without initialization
- **ASM Opcode Name Normalization**: Shortened all long opcode display names for readable ASM output
  - ARRAYFETCH_INT_GLOBAL_OPT → AF_I_G_O
  - BUILTIN_ASSERT_EQUAL → BI_ASEQ
  - FOREACH_LIST_GET_INT → FE_L_GET_I
  - Added abbreviation legend comments in c2-inc-v19.pbi
- **Cross-Platform Testing**: All 75 tests pass on both Windows and Linux
  - Fixed Linux test detection to filter out ASM listing output

### v1.036.x
- **Array of Structs**: `array points.Point[10];` with field access via `points[i]\x`
- **printf() Built-in**: C-style formatted output with %d, %f, %s, %.Nf specifiers
- **String Length Caching**: O(1) length access via cached \i field

### v1.035.14-15
- **Post-increment in Function Arguments**: Fixed crash when using `x++` inside function calls
  - Added `gInFuncArgs` context flag to track when parsing function arguments
  - SEQ handler now skips DROP when in function argument context
  - Prevents stack imbalance that caused Linux runtime crashes
  - Example: `printf("x = %d\n", x++)` now works correctly
- **mapVariableTypes Type Fix**: Fixed 16-bit overflow bug
  - Changed `mapVariableTypes` from `.w` (16-bit) to `.l` (32-bit)
  - `#C2FLAG_EXPLICIT = 65536` requires 17 bits (was being truncated to 0)
  - Test 130 now correctly fails at compile time with pointer type error
- **Test Infrastructure**: Added test runner scripts to `test/` folder
  - `run_all_tests.ps1`: PowerShell test runner with colored output
  - `run_all_tests.cmd`: Batch file test runner for CMD
- All 71 tests pass on Windows and Linux (69 run + 2 error tests)

### v1.035.13
- **printf() Built-in Function**: C-style formatted output with single VM call
  - Format specifiers: `%d` (int), `%f` (float), `%s` (string), `%.Nf` (precision), `%%` (literal %)
  - Escape sequences processed at compile-time in scanner: `\n`, `\t`, `\r`, `\\`, `\"`, `\0`
  - Single VM call for entire format string (performance: one call vs multiple PRTS/PRTI/PRTF)
  - Example: `printf("Name: %s, Age: %d, Score: %.2f\n", name, age, score)`
- **String Length Caching**: O(1) length access optimization
  - String values now cache their length in the `\i` field of gEvalStack entries
  - Eliminates repeated `Len()` calls in string operations
  - Affected operations: FETCHS, PUSHS, LFETCHS, DUP_S, ADDSTR, FTOS, ITOS
  - printf uses cached length for format string processing
- All 69 tests pass (+ 2 error test files)

### v1.035.12
- **Lookup Function Consolidation**: Moved O(1) lookup functions to dedicated file
  - Moved from c2-codegen-v08.pbi to c2-codegen-lookup.pbi:
    - `GetCodeElement()`: Core O(1) map lookup, returns stCodeElement pointer
    - `FindVariableSlot()`: O(1) variable slot lookup
    - `FindVariableSlotCompat()`: O(1) with O(N) fallback for migration
    - `RegisterCodeElement()`: Registers gVarMeta entry in MapCodeElements
  - c2-codegen-lookup.pbi grew from 220 to 358 lines
  - c2-codegen-v08.pbi reduced from 3842 to 3712 lines (~130 lines removed)
  - All 70 tests pass

### v1.035.10
- **GetExprResultType File Extraction**: Continued codegen modularization
  - Created `c2-codegen-types.pbi` (~760 lines) containing:
    - `GetExprResultType()` procedure for expression type resolution
    - `GetExprSlotOrTemp()` for slot optimization (reuses existing slots vs temp)
    - `ContainsFunctionCall()` helper for recursive function call detection
    - `CollectVariables()` helper for variable reference collection
  - Added forward declaration for CodeGenerator (circular dependency)
  - Reduced c2-codegen-v08.pbi from ~4200 to ~3430 lines (~770 lines removed)
  - Include order: types.pbi must be after emit.pbi, before v08.pbi
  - All 70 tests pass

### v1.035.9
- **FetchVarOffset File Extraction**: Continued codegen modularization
  - Created `c2-codegen-vars.pbi` (~740 lines) containing:
    - `FetchVarOffset()` procedure for variable slot lookup and creation
    - Handles name mangling for local variables
    - DOT notation struct field access (e.g., "r.bottomRight.x")
    - Backslash notation struct field access (e.g., "c1\id")
    - Constant map lookups (fast path)
    - Local variable offset assignment
  - Reduced c2-codegen-v08.pbi from ~4935 to ~4200 lines (~735 lines removed)
  - Include order: vars.pbi must be before ast.pbi (FetchVarOffset called from AST)
  - All 70 tests pass

### v1.035.8
- **EmitInt File Extraction**: Split c2-codegen-v08.pbi into modular files
  - Created `c2-codegen-emit.pbi` (~500 lines) containing:
    - `EmitInt()` procedure for bytecode instruction emission
    - `IsLocalVar()` helper for local variable detection
    - `MarkPreloadable()` helper for constant preloading
    - `OSDebug()` macro for debug output
  - Reduced c2-codegen-v08.pbi from 5305 to ~4935 lines (~370 lines removed)
  - First phase of codegen file split (per plan: emit.pbi, vars.pbi, types.pbi)
  - All 70 tests pass

### v1.035.7
- Made CALL/CALL0 function call statistics DEBUG-only in runtime output

### v1.035.6
- **EmitInt Rule-Based Refactoring**: Replaced duplicate type-dispatch patterns with rule-based lookups
  - Reduced c2-codegen-v08.pbi from 5463 to 5305 lines (~158 lines, ~3% reduction)
  - New helper functions in c2-codegen-rules.pbi:
    - `GetStoreOpcodeByFlags()`: Returns STORE/STOREF/STORES/PSTORE based on type flags
    - `GetMovOpcodeByFlags()`: Returns MOV/MOVF/MOVS/PMOV based on source/dest flags
    - `ComputeMovLocality()`: Computes n/j/i fields for MOV optimization (GG/LG/GL/LL)
  - Replaced 10+ duplicate if/elseif type-dispatch blocks in EmitInt
  - All 70 tests pass

### v1.035.5
- **DUP Optimization**: FETCH x + FETCH x → FETCH x + DUP for x*x squared patterns
  - Saves memory reads in tight loops (Mandelbrot x*x, y*y)
  - Implemented for INT, FLOAT, STRING types (DUP_I, DUP_F, DUP_S)
- **Negate Constant Folding**: PUSH const + NEGATE → PUSH -const at compile time
  - Eliminates runtime NEGATE instruction
  - Creates new constant slot with negated value
- Added helper functions: GetDupOpcodeForFetch(), AreSameFetchTarget(), IsGlobalFetchOpcode()

### v1.035.3-4
- **Rule-Based Optimizer**: Refactored peephole optimization to use lookup tables
- New rule maps in c2-codegen-rules.pbi:
  - `mapCompareFlip`: Comparison inversion (LESS+NOT → GREATER_EQUAL)
  - `mapDeadCodeOpcodes`: Dead code patterns (PUSH+POP elimination)
  - `mapIdentityOps`: Identity operations (+0, *1, /1)
  - `mapCompoundAssignInt/Float`: Compound assignment opcodes
  - `mapFetchStoreFusion`: FETCH→STORE to MOV fusion
- New lookup functions: IsDeadCodeOpcode(), GetFlippedCompare(), IsIdentityOp(), GetCompoundAssignOpcode()
- All 70 tests pass

### v1.034.80
- **Optimizer V02**: Consolidated optimization passes from 8+ to 5 clean passes
- **FETCH+STORE → MOV Fusion**: New unified MOV fusion handles all locality combinations:
  - `FETCH(j=0) + STORE(j=0)` → `MOV(n=0)` (Global→Global)
  - `FETCH(j=1) + STORE(j=0)` → `MOV(n=1)` (Local→Global)
  - `FETCH(j=0) + STORE(j=1)` → `MOV(n=2)` (Global→Local)
  - `FETCH(j=1) + STORE(j=1)` → `MOV(n=3)` (Local→Local)
- Self-assignment elimination (FETCH x + STORE x → NOOP)
- ~15% performance improvement on tight integer loops (Test 112: 0.07s → 0.06s)
- Unified peephole pass includes: dead code, constant folding, MOV fusion, jump opts, double negation, comparison flipping

### v1.034.79
- Fixed FOREACH opcodes not in VM jump table (runtime crash)
- Added 12 FOREACH opcode handlers to c2-vm-V16.pb
- Fixed FOREACH codegen missing from c2-codegen-v07.pbi

### v1.034.77
- Fixed DEBUG=1 silent crash (empty CompilerIf block in vm_PushInt)
- Removed debug traces from CALL0/RETURN opcodes

### v1.034.73-76
- Fixed vm_PushInt/vm_PushFloat macros (removed erroneous pc+1)
- Added explicit pc+1 to builtin functions
- Changed PrintN to Debug in bounds checking (GUI mode fix)

### v1.034.0
- **Major Architecture: Unified Code Element Map**: Added MapCodeElements for O(1) variable lookups
- New eElementType enumeration (VARIABLE, CONSTANT, FUNCTION, PARAMETER, STRUCT_FIELD, ARRAY)
- New stCodeElement structure with full metadata including:
  - Expression chain traversal pointers (*Left, *Right)
  - Usage flow tracking pointers (*AssignedFrom, *UsedBy)
  - Type info, flags, scope information
- O(1) lookup functions: GetCodeElement(), FindVariableSlot(), FindVariableSlotCompat()
- RegisterCodeElement() syncs gVarMeta entries to map
- **Fixed Implicit Return Hole Tracking**: MarkImplicitReturns() pre-marks function-end NOOPIFs
- Added #INST_FLAG_IMPLICIT_RETURN flag to prevent skipping in jump tracking
- Modified InitJumpTracker LOOPBACK/FORLOOP/CONTINUE skip logic
- All 66 tests pass

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
- Usage: `D+AI.exe -x 5 program.d` or `D+AI.exe --autoquit 5 program.d`
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
- Include examples (Examples/*.d)
- Include version file (_D+AI.ver)

## Architecture Notes

- VM execution speed prioritized
- Definitions at procedure start (PureBasic requirement)
- Global variables for state (no procedure statics)
- TypeInference module handles all type resolution (VM stays simple)
- PostProcessor handles correctness only (implicit returns, type conversions, collections)
- gVarMeta NOT used in VM code

---
End of Status Report
