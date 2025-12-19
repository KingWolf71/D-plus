# LJ2 Implementation Status
Version: 1.033.19
Date: December 2025

## Current File Versions

| Component | File | Description |
|-----------|------|-------------|
| Main compiler | `c2-modules-V21.pb` | Scanner, preprocessor, main entry |
| Definitions | `c2-inc-v17.pbi` | Constants, opcodes, structures |
| AST parser | `c2-ast-v06.pbi` | Recursive descent parser |
| Code generator | `c2-codegen-v06.pbi` | AST to bytecode |
| Scanner | `c2-scanner-v05.pbi` | Tokenizer |
| Postprocessor | `c2-postprocessor-V09.pbi` | Type inference, optimization |
| Optimizer | `c2-optimizer-V01.pbi` | Peephole and fusion optimizations |
| VM core | `c2-vm-V16.pb` | Virtual machine execution |
| VM commands | `c2-vm-commands-v14.pb` | Opcode implementations |
| Arrays | `c2-arrays-v05.pbi` | Array operations |
| Pointers | `c2-pointers-v05.pbi` | Pointer operations |
| Collections | `c2-collections-v03.pbi` | Lists and Maps |
| Built-ins | `c2-builtins-v06.pbi` | Built-in functions |
| Test runner | `run-tests-win.ps1` | Windows PowerShell test runner |

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

### PostProcessor Passes
1. Type inference - converts generic ops to typed variants
2. Array index optimization - eliminates redundant PUSH operations
3. Jump/call resolution - converts relative to absolute addresses

## Test Suite

Located in `Examples/`:
- Comprehensive tests (01-51)
- Feature-specific tests
- AVL tree implementation (51)
- Mandelbrot set renderer (19)
- Julia set renderer (21)

## Recent Changes (v1.031.x - v1.033.x)

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
- PostProcessor handles type inference (VM stays simple)
- gVarMeta NOT used in VM code

---
End of Status Report
