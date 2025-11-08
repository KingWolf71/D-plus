; ============================================================================
; LJ2 Built-in Functions Framework
; ============================================================================
; This file contains all built-in runtime functions like random(), abs(), etc.
;
; To add a new built-in function:
;   1. Add constant in Constants section below (use negative IDs)
;   2. Add VM handler in c2-vm-commands-v03.pb (C2BUILTIN_* naming)
;   3. Add dispatch case in C2CALL() procedure
;   4. Add registration in RegisterBuiltins() below
;
; Built-in functions use negative IDs to distinguish from user functions
; ============================================================================

;- Structures (for C2Common module)

Structure stBuiltinDef
   name.s          ; Function name as it appears in source code
   opcode.i        ; Opcode for this built-in
   minParams.i     ; Minimum parameter count
   maxParams.i     ; Maximum parameter count (-1 = unlimited)
   returnType.i    ; Return type: #C2FLAG_INT, #C2FLAG_FLOAT, or #C2FLAG_STR
EndStructure

; NOTE: Opcode enumerations are added to main enumeration in c2-inc-v06.pbi
; NOTE: VM handler procedures (C2BUILTIN_*) are in c2-vm-commands-v03.pb
; NOTE: Registration functions are in c2-modules-V10.pb (C2Lang module)
; NOTE: Jump table registration is in c2-vm-V05.pb
