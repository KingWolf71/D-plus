D+AI Bugs & TODO
--------------------
Updated: 7/Nov/2025

1. ~~Return not handled properly~~ **FIXED** - Added type-specific returns (RETF, RETS), fixed stack leak, proper initialization
2. concat type conversion
3. macro inference
4. MOVS, MOVF implementation
5. Recursion test

## Recent Fixes (7/Nov/2025)

### Return Value Handling & Stack Leak
- Added `#ljReturnF` and `#ljReturnS` opcodes for type-specific returns
- Implemented C2ReturnF() and C2ReturnS() procedures with proper type defaults
- Fixed return value initialization (was returning garbage/0 due to uninitialized variables)
- Fixed stack leak: CALL now saves sp BEFORE parameters (sp - nParams)
- Return procedures correctly compare sp against callerSp instead of gnLastVariable
- Compiler now emits correct return opcode based on expression type (GetExprResultType)
- Parameter count now tracked in CALL instruction j field via mapModules lookup