
; -- lexical parser to VM for a simplified C Language
; Tested in UTF8
; PBx64 v6.20
;
; Based on  https://rosettacode.org/wiki/Compiler/lexical_analyzer
; And
; https://rosettacode.org/wiki/Compiler/syntax_analyzer
; Distribute and use freely
;
; Kingwolf71 May/2025
;
;
; Common constants and structures
;
; V1.31.0 - ISOLATED VARIABLE SYSTEM (replaces Unified V1.18.0)
; ==============================================================
; Complete isolation between global variables, local variables, and evaluation stack.
; Three separate arrays prevent any possibility of stack/local overlap bugs.
;
; V1.034.18: Unified Storage Model with ABSOLUTE indexing:
;   - gStorage[0..gGlobalStack-1]: Globals (indexed by slot)
;   - gStorage[gGlobalStack..]: Locals + eval stack (sp and gFrameBase are absolute)
;
; Opcode Categories (LL/GG/LG/GL):
;   - GG: Global to Global - MOV, MOVF, MOVS
;   - LL: Local to Local   - LLMOV, LLMOVF, LLMOVS
;   - GL: Global to Local  - LMOV, LMOVF, LMOVS
;   - LG: Local to Global  - LGMOV, LGMOVF, LGMOVS
;   - GS: Global to Stack  - FETCH, FETCHF, FETCHS
;   - LS: Local to Stack   - LFETCH, LFETCHF, LFETCHS
;   - SG: Stack to Global  - STORE, STOREF, STORES
;   - SL: Stack to Local   - LSTORE, LSTOREF, LSTORES
;
; Local variable access:
;   - paramOffset >= 0: index into gLocal[] from current frame's localBase
;   - paramOffset = -1: global variable (use gVar[slot] directly)
;
; V1.18.12 - paramOffset Space Allocation:
;   - Regular local variables: paramOffset = 0 to nLocals-1
;   - Local arrays: paramOffset = 1000 to 1000+nLocalArrays-1
;   - Separation needed because arrays use .dta.ar() while variables use .i/.f/.ss

; ======================================================================================================
;- Constants
; ======================================================================================================

#DEBUG            = 0   ; V1.034.52: Fixed sp bounds check - sp is absolute index, not relative to eval stack
#C2PROFILER       = 0     ; V1.033.16: Disabled for true VM speed test
#C2PROFILER_LOG   = 0     ; V1.031.112: Append profiler data to cumulative log file
#VM_INLINE_HOT    = 0     ; V1.034.27: Disabled inline hot opcodes for now

#INV$             = ~"\""
#C2MAXTOKENS      = 500   ; Legacy, use #C2TOKENCOUNT for actual count
#C2MAXCONSTANTS   = 32767
#C2MAXFUNCTIONS   = 8192  ; V1.033.54: Max functions (for function-indexed arrays)

; V1.31.0: Isolated Variable System array sizes - now use global variables:
; gMaxEvalStack, gMaxEvalStack, gGlobalStack, gFunctionStack (set via pragmas)

#C2FLAG_TYPE      = 28   ; Mask for type bits only (INT | FLOAT | STR = 4|8|16 = 28); VOID is separate
#C2FLAG_CONST     = 1
#C2FLAG_IDENT     = 2
#C2FLAG_INT       = 4
#C2FLAG_FLOAT     = 8
#C2FLAG_STR       = 16
#C2FLAG_CHG       = 32
#C2FLAG_PARAM     = 64
#C2FLAG_ARRAY     = 128
#C2FLAG_POINTER   = 256  ; Variable is a pointer type
#C2FLAG_STRUCT    = 512  ; Variable is a struct type (V1.021.0)
#C2FLAG_PRELOAD   = 1024 ; V1.023.0: Variable has constant init, preload from template (skip MOV)
#C2FLAG_LIST      = 2048 ; V1.026.0: Variable is a linked list
#C2FLAG_MAP       = 4096 ; V1.026.0: Variable is a map (string key -> value)
#C2FLAG_ARRAYPTR  = 8192 ; V1.027.0: Pointer points to array element (vs simple variable)
#C2FLAG_ASSIGNED  = 16384 ; V1.027.9: Variable has been assigned (prevents late PRELOAD marking)
#C2FLAG_VOID      = 32768 ; V1.033.11: Void type (no value, for functions/placeholders)
#C2FLAG_EXPLICIT  = 65536 ; V1.035.14: Variable has explicit type suffix (.i/.f/.s) - known non-pointer

; V1.026.0: Default max maps - can be changed via #pragma maxmaps
#C2_DEFAULT_MAX_MAPS = 64
#C2VM_QUEUE_TIMER    = 1

; V1.031.32: Local variable slot flags (for runtime local detection)
#C2_LOCAL_COLLECTION_FLAG = $40000000  ; High bit indicates local slot
#C2_SLOT_MASK = $3FFFFFFF              ; Mask to extract real slot number

Enumeration
   #C2HOLE_START
   #C2HOLE_DEFAULT
   #C2HOLE_PAIR
   #C2HOLE_BLIND
   #C2HOLE_LOOPBACK  ; V1.023.42: While loop backward jump (target is NOOPIF at loop start)
   #C2HOLE_BREAK     ; V1.024.0: Break statement (forward jump to loop/switch end)
   #C2HOLE_CONTINUE  ; V1.024.0: Continue statement (backward jump to loop condition)
   #C2HOLE_FORLOOP   ; V1.024.0: For loop backward jump
   #C2HOLE_SWITCH    ; V1.024.0: Switch case jump
   #C2HOLE_CASE      ; V1.024.0: Case label target
EndEnumeration

; opCodes
Enumeration
   #ljUNUSED
   #ljIDENT
   #ljINT
   #ljFLOAT
   #ljSTRING
   #ljVOID        ; V1.033.11: Void type (no return value, placeholders, generic pointers)
   #ljStructType  ; V1.022.80: Struct type hint for arrays and variables (distinct from #ljStruct keyword)
   #ljTypeGuess   ; V1.022.80: Type inferred from first assignment (allows multi-pass refinement)
   #ljArray
   #ljIF
   #ljElse
   #ljWHILE
   #ljFOR           ; V1.024.0: for(;;) loop
   #ljSWITCH        ; V1.024.0: switch statement
   #ljCASE          ; V1.024.0: case label
   #ljDEFAULT_CASE  ; V1.024.0: default label
   #ljBREAK         ; V1.024.0: break statement
   #ljCONTINUE      ; V1.024.0: continue statement
   #ljFOREACH       ; V1.034.6: foreach loop for lists/maps (scoped iterator)
   #ljJZ
   #ljJMP
   #ljNEGATE
   #ljFLOATNEG
   #ljNOT
   #ljASSIGN

   ; Compound assignment and increment/decrement operators
   #ljADD_ASSIGN     ; +=
   #ljSUB_ASSIGN     ; -=
   #ljMUL_ASSIGN     ; *=
   #ljDIV_ASSIGN     ; /=
   #ljMOD_ASSIGN     ; %=
   #ljINC            ; ++ (token)
   #ljDEC            ; -- (token)
   #ljPRE_INC        ; Pre-increment (AST node)
   #ljPRE_DEC        ; Pre-decrement (AST node)
   #ljPOST_INC       ; Post-increment (AST node)
   #ljPOST_DEC       ; Post-decrement (AST node)

   #ljADD
   #ljSUBTRACT
   #ljMULTIPLY
   #ljDIVIDE
   #ljFLOATADD
   #ljFLOATSUB
   #ljFLOATMUL
   #ljFLOATDIV
   #ljSTRADD
   #ljFTOS         ; Float To String conversion
   #ljITOS         ; Integer To String conversion
   #ljITOF         ; Integer To Float conversion
   #ljFTOI         ; Float To Integer conversion
   #ljSTOF         ; String To Float conversion
   #ljSTOI         ; String To Integer conversion

   #ljOr
   #ljAND
   #ljXOR
   #ljMOD
   #ljSHL            ; V1.034.4: Bit shift left
   #ljSHR            ; V1.034.4: Bit shift right
  
   #ljEQUAL 
   #ljNotEqual
   #ljLESSEQUAL
   #ljGreaterEqual
   #ljGREATER
   #ljLESS
   #ljFLOATEQ
   #ljFLOATNE
   #ljFLOATLE
   #ljFLOATGE
   #ljFLOATGR
   #ljFLOATLESS

   ; V1.023.30: String comparison opcodes
   #ljSTREQ               ; String equals
   #ljSTRNE               ; String not equals

   #ljMOV
   #ljFetch
   #ljPOP
   #ljPOPS
   #ljPOPF
   #ljPush
   #ljPUSHS
   #ljPUSHF
   #ljPUSH_IMM    ; V1.031.113: Push immediate integer value (no gVar lookup)
   #ljStore
   #ljHALT
   
   #ljPrint
   #ljPRTC
   #ljPRTI
   #ljPRTF
   #ljPRTS

   #ljLeftBrace
   #ljRightBrace
   #ljLeftParent
   #ljRightParent
   #ljLeftBracket
   #ljRightBracket
   #ljSemi
   #ljComma
   #ljBackslash    ; V1.20.21: Pointer field accessor (ptr\i, ptr\f, ptr\s)
   #ljfunction
   #ljreturn
   #ljreturnF
   #ljreturnS
   #ljCall
   #ljCALL0        ; V1.033.12: Optimized call - 0 parameters (no param copy loop)
   #ljCALL1        ; V1.033.12: Optimized call - 1 parameter (direct copy)
   #ljCALL2        ; V1.033.12: Optimized call - 2 parameters (unrolled copy)
   #ljCALL_REC     ; V1.034.65: Recursive call - uses frame pool, no gFuncActive check
   #ljRETURN_REC   ; V1.034.65: Return from recursive function - returns frame to pool
   #ljARRAYINFO    ; V1.031.105: Local array info for CALL (i=paramOffset, j=arraySize)

   #ljUNKNOWN
   #ljNOOP
   #ljOP
   #ljSEQ
   #ljKeyword

   #ljTERNARY
   #ljQUESTION
   #ljCOLON
   #ljTENIF        ; Ternary IF: Jump if condition false
   #ljTENELSE      ; Ternary ELSE: Jump past false branch
   #ljNOOPIF       ; Marker for ternary fix() positions (removed after FixJMP)

   ; V1.024.0: New opcodes for switch statement
   #ljDUP          ; Duplicate top of stack (generic)
   #ljDUP_I        ; V1.024.4: Duplicate integer (also pointers, arrays, structs)
   #ljDUP_F        ; V1.024.4: Duplicate float
   #ljDUP_S        ; V1.024.4: Duplicate string
   #ljJNZ          ; Jump if Not Zero (for switch case matching)
   #ljDROP         ; V1.024.6: Discard top of stack (no store, just sp-1)

   ;- V1.035.16: Fused comparison-jump opcodes for loop optimization
   ; Pattern: FETCH + PUSH_IMM + CMP + JZ → single instruction
   ; Uses \i=slot, \j=immediate, \ndx=offset (reuses array instruction encoding)
   #ljJGE_VAR_IMM  ; Jump if gVar[slot] >= imm (inverts LESS+JZ)
   #ljJGT_VAR_IMM  ; Jump if gVar[slot] > imm (inverts LESSEQUAL+JZ)
   #ljJLE_VAR_IMM  ; Jump if gVar[slot] <= imm (inverts GREATER+JZ)
   #ljJLT_VAR_IMM  ; Jump if gVar[slot] < imm (inverts GREATEREQUAL+JZ)
   #ljJEQ_VAR_IMM  ; Jump if gVar[slot] == imm (inverts NOTEQUAL+JZ)
   #ljJNE_VAR_IMM  ; Jump if gVar[slot] != imm (inverts EQUAL+JZ)
   ; Local variable versions
   #ljJGE_LVAR_IMM ; Jump if gLocal[offset] >= imm
   #ljJGT_LVAR_IMM ; Jump if gLocal[offset] > imm
   #ljJLE_LVAR_IMM ; Jump if gLocal[offset] <= imm
   #ljJLT_LVAR_IMM ; Jump if gLocal[offset] < imm
   #ljJEQ_LVAR_IMM ; Jump if gLocal[offset] == imm
   #ljJNE_LVAR_IMM ; Jump if gLocal[offset] != imm

   #ljMOVS
   #ljMOVF
   #ljFETCHS
   #ljFETCHF
   #ljSTORES
   #ljSTOREF

   ;- Local Variable Opcodes (V1.31.0: Isolated Variable System)
   ; V1.31.0: Locals stored in gLocal[], globals in gVar[], eval stack in gEvalStack[]
   ; LMOV/LFETCH/LSTORE operate on gLocal[] array (isolated from gVar[])
   #ljLMOV       ; GL MOV: gLocal[offset] = gVar[slot] (Global ? Local)
   #ljLMOVS      ; GL MOVS: string variant
   #ljLMOVF      ; GL MOVF: float variant
   #ljLFETCH     ; Local FETCH: push gLocal[offset] to gEvalStack
   #ljLFETCHS    ; Local FETCHS: string variant
   #ljLFETCHF    ; Local FETCHF: float variant
   #ljLSTORE     ; Local STORE: pop gEvalStack to gLocal[offset]
   #ljLSTORES    ; Local STORES: string variant
   #ljLSTOREF    ; Local STOREF: float variant

   ;- Cross-locality MOV opcodes (LL/LG/GL matrix)
   ; Format: [src][dst]MOV where L=Local (gLocal[]), G=Global (gVar[])
   ; LMOV is GL (Global ? Local), use LGMOV for Local ? Global
   #ljLGMOV      ; LG MOV: gVar[slot] = gLocal[offset] (Local ? Global)
   #ljLGMOVS     ; LG MOVS: string variant
   #ljLGMOVF     ; LG MOVF: float variant
   #ljLLMOV      ; LL MOV: gLocal[dst] = gLocal[src] (Local ? Local)
   #ljLLMOVS     ; LL MOVS: string variant
   #ljLLMOVF     ; LL MOVF: float variant
   #ljLLPMOV     ; LL PMOV: pointer variant (copies i, ptr, ptrtype)

   ;- In-place increment/decrement opcodes (unified for all variables)
   #ljINC_VAR        ; Increment variable in place (no stack operation)
   #ljDEC_VAR        ; Decrement variable in place (no stack operation)
   #ljINC_VAR_PRE    ; Pre-increment: increment and push new value
   #ljDEC_VAR_PRE    ; Pre-decrement: decrement and push new value
   #ljINC_VAR_POST   ; Post-increment: push old value and increment
   #ljDEC_VAR_POST   ; Post-decrement: push old value and decrement

   ;- Local increment/decrement opcodes (operate on gLocal[])
   #ljLINC_VAR       ; Increment local variable in place
   #ljLDEC_VAR       ; Decrement local variable in place
   #ljLINC_VAR_PRE   ; Pre-increment local: increment and push new value
   #ljLDEC_VAR_PRE   ; Pre-decrement local: decrement and push new value
   #ljLINC_VAR_POST  ; Post-increment local: push old value and increment
   #ljLDEC_VAR_POST  ; Post-decrement local: push old value and decrement

   ;- Pointer increment/decrement opcodes (V1.20.36: pointer arithmetic)
   #ljPTRINC         ; Increment pointer by sizeof(basetype) (no stack operation)
   #ljPTRDEC         ; Decrement pointer by sizeof(basetype) (no stack operation)
   #ljPTRINC_PRE     ; Pre-increment pointer: increment and push new value
   #ljPTRDEC_PRE     ; Pre-decrement pointer: decrement and push new value
   #ljPTRINC_POST    ; Post-increment pointer: push old value and increment
   #ljPTRDEC_POST    ; Post-decrement pointer: push old value and decrement

   ;- Struct storage opcode (V1.029.84)
   #ljSTORE_STRUCT   ; Store to struct variable: pops stack, copies both \i and \ptr (for pointer semantics)
   #ljLSTORE_STRUCT  ; V1.031.32: Local variant - stores to gLocal[offset] instead of gVar[]

   ;- In-place compound assignment opcodes (optimized by post-processor)
   #ljADD_ASSIGN_VAR     ; Pop stack, add to variable, store (var = var + stack)
   #ljSUB_ASSIGN_VAR     ; Pop stack, subtract from variable, store (var = var - stack)
   #ljMUL_ASSIGN_VAR     ; Pop stack, multiply variable, store (var = var * stack)
   #ljDIV_ASSIGN_VAR     ; Pop stack, divide variable, store (var = var / stack)
   #ljMOD_ASSIGN_VAR     ; Pop stack, modulo variable, store (var = var % stack)
   #ljFLOATADD_ASSIGN_VAR  ; Pop stack, float add to variable, store (var = var + stack)
   #ljFLOATSUB_ASSIGN_VAR  ; Pop stack, float subtract from variable, store (var = var - stack)
   #ljFLOATMUL_ASSIGN_VAR  ; Pop stack, float multiply variable, store (var = var * stack)
   #ljFLOATDIV_ASSIGN_VAR  ; Pop stack, float divide variable, store (var = var / stack)
   #ljPTRADD_ASSIGN        ; Pop stack, add to pointer (ptr = ptr + offset), pointer arithmetic
   #ljPTRSUB_ASSIGN        ; Pop stack, subtract from pointer (ptr = ptr - offset), pointer arithmetic

   ;- Built-in Function Opcodes
   #ljBUILTIN_RANDOM      ; random() or random(max) or random(min, max)
   #ljBUILTIN_ABS         ; abs(x) - absolute value
   #ljBUILTIN_MIN         ; min(a, b) - minimum of two values
   #ljBUILTIN_MAX         ; max(a, b) - maximum of two values
   #ljBUILTIN_ASSERT_EQUAL      ; assertEqual(expected, actual) - assert integers are equal
   #ljBUILTIN_ASSERT_FLOAT      ; assertFloatEqual(expected, actual, tolerance) - assert floats are equal within tolerance
   #ljBUILTIN_ASSERT_STRING     ; assertStringEqual(expected, actual) - assert strings are equal
   #ljBUILTIN_SQRT         ; sqrt(x) - square root (returns float)
   #ljBUILTIN_POW          ; pow(base, exp) - power function (returns float)
   #ljBUILTIN_LEN          ; len(s) - string length (returns int)
   #ljBUILTIN_STRCMP       ; strcmp(a, b) - string compare, returns -1/0/1
   #ljBUILTIN_GETC         ; getc(s, idx) - get character code at index
   #ljBUILTIN_PRINTF       ; V1.035.13: printf(format, args...) - C-style formatted output

   ;- Array Opcodes
   #ljARRAYINDEX          ; Compute array element index (base + index * elementSize)
   #ljARRAYFETCH          ; Fetch array element to stack (generic)
   #ljARRAYFETCH_INT      ; Fetch integer array element
   #ljARRAYFETCH_FLOAT    ; Fetch float array element
   #ljARRAYFETCH_STR      ; Fetch string array element
   #ljARRAYSTORE          ; Store to array element (generic)
   #ljARRAYSTORE_INT      ; Store integer to array element
   #ljARRAYSTORE_FLOAT    ; Store float to array element
   #ljARRAYSTORE_STR      ; Store string to array element

   ;- Specialized Array Fetch Opcodes (eliminate runtime branching)
   ; INT variants
   #ljARRAYFETCH_INT_GLOBAL_OPT       ; Global array, optimized index
   #ljARRAYFETCH_INT_GLOBAL_STACK     ; Global array, stack index
   #ljARRAYFETCH_INT_LOCAL_OPT        ; Local array, optimized index
   #ljARRAYFETCH_INT_LOCAL_STACK      ; Local array, stack index
   ; FLOAT variants
   #ljARRAYFETCH_FLOAT_GLOBAL_OPT     ; Global array, optimized index
   #ljARRAYFETCH_FLOAT_GLOBAL_STACK   ; Global array, stack index
   #ljARRAYFETCH_FLOAT_LOCAL_OPT      ; Local array, optimized index
   #ljARRAYFETCH_FLOAT_LOCAL_STACK    ; Local array, stack index
   ; STRING variants
   #ljARRAYFETCH_STR_GLOBAL_OPT       ; Global array, optimized index
   #ljARRAYFETCH_STR_GLOBAL_STACK     ; Global array, stack index
   #ljARRAYFETCH_STR_LOCAL_OPT        ; Local array, optimized index
   #ljARRAYFETCH_STR_LOCAL_STACK      ; Local array, stack index

   ;- Specialized Array Store Opcodes (eliminate runtime branching)
   ; INT variants (global/local � index source � value source)
   #ljARRAYSTORE_INT_GLOBAL_OPT_OPT       ; Global, opt index, opt value
   #ljARRAYSTORE_INT_GLOBAL_OPT_STACK     ; Global, opt index, stack value
   #ljARRAYSTORE_INT_GLOBAL_STACK_OPT     ; Global, stack index, opt value
   #ljARRAYSTORE_INT_GLOBAL_STACK_STACK   ; Global, stack index, stack value
   #ljARRAYSTORE_INT_LOCAL_OPT_OPT        ; Local, opt index, opt value
   #ljARRAYSTORE_INT_LOCAL_OPT_STACK      ; Local, opt index, stack value
   #ljARRAYSTORE_INT_LOCAL_STACK_OPT      ; Local, stack index, opt value
   #ljARRAYSTORE_INT_LOCAL_STACK_STACK    ; Local, stack index, stack value
   ; FLOAT variants
   #ljARRAYSTORE_FLOAT_GLOBAL_OPT_OPT     ; Global, opt index, opt value
   #ljARRAYSTORE_FLOAT_GLOBAL_OPT_STACK   ; Global, opt index, stack value
   #ljARRAYSTORE_FLOAT_GLOBAL_STACK_OPT   ; Global, stack index, opt value
   #ljARRAYSTORE_FLOAT_GLOBAL_STACK_STACK ; Global, stack index, stack value
   #ljARRAYSTORE_FLOAT_LOCAL_OPT_OPT      ; Local, opt index, opt value
   #ljARRAYSTORE_FLOAT_LOCAL_OPT_STACK    ; Local, opt index, stack value
   #ljARRAYSTORE_FLOAT_LOCAL_STACK_OPT    ; Local, stack index, opt value
   #ljARRAYSTORE_FLOAT_LOCAL_STACK_STACK  ; Local, stack index, stack value
   ; STRING variants
   #ljARRAYSTORE_STR_GLOBAL_OPT_OPT       ; Global, opt index, opt value
   #ljARRAYSTORE_STR_GLOBAL_OPT_STACK     ; Global, opt index, stack value
   #ljARRAYSTORE_STR_GLOBAL_STACK_OPT     ; Global, stack index, opt value
   #ljARRAYSTORE_STR_GLOBAL_STACK_STACK   ; Global, stack index, stack value
   #ljARRAYSTORE_STR_LOCAL_OPT_OPT        ; Local, opt index, opt value
   #ljARRAYSTORE_STR_LOCAL_OPT_STACK      ; Local, opt index, stack value
   #ljARRAYSTORE_STR_LOCAL_STACK_OPT      ; Local, stack index, opt value
   #ljARRAYSTORE_STR_LOCAL_STACK_STACK    ; Local, stack index, stack value

   ; V1.022.114: OPT_LOPT variants for GLOBAL arrays (global index, local value)
   ; Used when array index is constant but value comes from local temp (function scope)
   #ljARRAYSTORE_INT_GLOBAL_OPT_LOPT      ; Global int, global idx, local val
   #ljARRAYSTORE_FLOAT_GLOBAL_OPT_LOPT    ; Global float, global idx, local val
   #ljARRAYSTORE_STR_GLOBAL_OPT_LOPT      ; Global str, global idx, local val

   ; V1.022.115: OPT_LOPT variants for LOCAL arrays (global index, local value)
   ; Used when local array index is constant but value comes from local temp (function scope)
   #ljARRAYSTORE_INT_LOCAL_OPT_LOPT       ; Local int, global idx, local val
   #ljARRAYSTORE_FLOAT_LOCAL_OPT_LOPT     ; Local float, global idx, local val
   #ljARRAYSTORE_STR_LOCAL_OPT_LOPT       ; Local str, global idx, local val

   ;- V1.022.86: Local-Index Array Opcodes (for recursion-safe temp variables)
   ; LOPT = index from LOCAL slot (vs OPT = index from global slot)
   ; Used when array index is computed inside a function and stored in local temp
   ; FETCH variants: Global array, Local optimized index
   #ljARRAYFETCH_INT_GLOBAL_LOPT          ; Global int array, local opt index
   #ljARRAYFETCH_FLOAT_GLOBAL_LOPT        ; Global float array, local opt index
   #ljARRAYFETCH_STR_GLOBAL_LOPT          ; Global string array, local opt index
   ; STORE variants: Global array, Local optimized index, various value sources
   #ljARRAYSTORE_INT_GLOBAL_LOPT_LOPT     ; Global int, local idx, local val
   #ljARRAYSTORE_INT_GLOBAL_LOPT_OPT      ; Global int, local idx, global val
   #ljARRAYSTORE_INT_GLOBAL_LOPT_STACK    ; Global int, local idx, stack val
   #ljARRAYSTORE_FLOAT_GLOBAL_LOPT_LOPT   ; Global float, local idx, local val
   #ljARRAYSTORE_FLOAT_GLOBAL_LOPT_OPT    ; Global float, local idx, global val
   #ljARRAYSTORE_FLOAT_GLOBAL_LOPT_STACK  ; Global float, local idx, stack val
   #ljARRAYSTORE_STR_GLOBAL_LOPT_LOPT     ; Global str, local idx, local val
   #ljARRAYSTORE_STR_GLOBAL_LOPT_OPT      ; Global str, local idx, global val
   #ljARRAYSTORE_STR_GLOBAL_LOPT_STACK    ; Global str, local idx, stack val

   ; V1.022.113: LOPT variants for LOCAL arrays (index from local variable)
   ; FETCH variants: Local array, Local optimized index
   #ljARRAYFETCH_INT_LOCAL_LOPT           ; Local int array, local opt index
   #ljARRAYFETCH_FLOAT_LOCAL_LOPT         ; Local float array, local opt index
   #ljARRAYFETCH_STR_LOCAL_LOPT           ; Local string array, local opt index
   ; STORE variants: Local array, Local optimized index, various value sources
   #ljARRAYSTORE_INT_LOCAL_LOPT_LOPT      ; Local int, local idx, local val
   #ljARRAYSTORE_INT_LOCAL_LOPT_OPT       ; Local int, local idx, global val
   #ljARRAYSTORE_INT_LOCAL_LOPT_STACK     ; Local int, local idx, stack val
   #ljARRAYSTORE_FLOAT_LOCAL_LOPT_LOPT    ; Local float, local idx, local val
   #ljARRAYSTORE_FLOAT_LOCAL_LOPT_OPT     ; Local float, local idx, global val
   #ljARRAYSTORE_FLOAT_LOCAL_LOPT_STACK   ; Local float, local idx, stack val
   #ljARRAYSTORE_STR_LOCAL_LOPT_LOPT      ; Local str, local idx, local val
   #ljARRAYSTORE_STR_LOCAL_LOPT_OPT       ; Local str, local idx, global val
   #ljARRAYSTORE_STR_LOCAL_LOPT_STACK     ; Local str, local idx, stack val

   ;- Pointer Opcodes
   #ljGETADDR         ; Get address of integer variable - &var
   #ljGETADDRF        ; Get address of float variable - &var.f
   #ljGETADDRS        ; Get address of string variable - &var.s
   #ljGETLOCALADDR    ; Get address of local integer variable - &localVar (fp + offset)
   #ljGETLOCALADDRF   ; Get address of local float variable - &localVar.f (fp + offset)
   #ljGETLOCALADDRS   ; Get address of local string variable - &localVar.s (fp + offset)
   #ljPTRFETCH        ; Generic pointer fetch - *ptr
   #ljPTRFETCH_INT    ; Fetch int through pointer
   #ljPTRFETCH_FLOAT  ; Fetch float through pointer
   #ljPTRFETCH_STR    ; Fetch string through pointer
   #ljPTRSTORE        ; Generic pointer store - *ptr = value
   #ljPTRSTORE_INT    ; Store int through pointer
   #ljPTRSTORE_FLOAT  ; Store float through pointer
   #ljPTRSTORE_STR    ; Store string through pointer

   ;- Pointer Field Access (V1.20.21: ptr\i, ptr\f, ptr\s syntax)
   #ljPTRFIELD_I      ; AST: ptr\i - read integer through pointer
   #ljPTRFIELD_F      ; AST: ptr\f - read float through pointer
   #ljPTRFIELD_S      ; AST: ptr\s - read string through pointer

   ;- V1.022.44: Struct Array Field Access (arr[i]\field syntax)
   #nd_StructArrayField_I  ; AST: arr[i]\field - read integer from struct array element
   #nd_StructArrayField_F  ; AST: arr[i]\field - read float from struct array element
   #nd_StructArrayField_S  ; AST: arr[i]\field - read string from struct array element

   ;- V1.036.0: Multi-dimensional Array Access
   #nd_MultiDimIndex       ; AST: arr[i][j][k] - multi-dim array access, value="nDims|idx1Slot|idx2Slot|..."

   #ljPTRADD          ; Pointer arithmetic: ptr + offset
   #ljPTRSUB          ; Pointer arithmetic: ptr - offset
   #ljGETFUNCADDR     ; Get function PC address - &function
   #ljCALLFUNCPTR     ; Call function through pointer

   ;- Array Pointer Opcodes (for &arr[index])
   #ljGETARRAYADDR        ; Get address of array element - &arr[i] (integer)
   #ljGETARRAYADDRF       ; Get address of array element - &arr.f[i] (float)
   #ljGETARRAYADDRS       ; Get address of array element - &arr.s[i] (string)
   #ljGETLOCALARRAYADDR   ; Get address of local array element - &localArr[i] (integer, fp-relative)
   #ljGETLOCALARRAYADDRF  ; Get address of local array element - &localArr.f[i] (float, fp-relative)
   #ljGETLOCALARRAYADDRS  ; Get address of local array element - &localArr.s[i] (string, fp-relative)

   #ljPRTPTR              ; Runtime dispatch print after generic pointer dereference

   ;- Pointer-Only Opcodes (V1.20.27: No runtime checks, always copy metadata)
   #ljPMOV                ; Pointer-only MOV (always copies ptr/ptrtype)
   #ljPFETCH              ; Pointer-only FETCH (always copies ptr/ptrtype)
   #ljPSTORE              ; Pointer-only STORE (always copies ptr/ptrtype)
   #ljPPOP                ; Pointer-only POP (always copies ptr/ptrtype)
   #ljPLFETCH             ; Pointer-only local FETCH (always copies ptr/ptrtype)
   #ljPLSTORE             ; Pointer-only local STORE (always copies ptr/ptrtype)
   #ljPLMOV               ; Pointer-only local MOV (always copies ptr/ptrtype)

   ;- Cast Operators (AST nodes, V1.18.63)
   #ljCAST_INT       ; Cast expression to integer: (int)expr
   #ljCAST_FLOAT     ; Cast expression to float: (float)expr
   #ljCAST_STRING    ; Cast expression to string: (string)expr
   #ljCAST_VOID      ; V1.033.11: Discard expression value: (void)expr
   #ljCAST_PTR       ; V1.036.2: Cast expression to pointer: (ptr)expr or (void *)expr

   ;- Structure Support (V1.021.0)
   #ljStruct         ; struct keyword
   #ljStructField    ; Structure field access (p.x)
   #ljStructInit     ; Structure initialization { ... }

   ; V1.022.71: 'local' keyword removed - type annotation (.i/.f/.s) creates local automatically

   ;- Struct Array Field Opcodes (V1.022.0: Arrays inside structures)
   ;  These access contiguous gVar[] slots: gVar[baseSlot + index]
   ;  Unlike regular arrays which use gVar[slot]\dta\ar(index)
   #ljSTRUCTARRAY_FETCH_INT    ; Fetch int from struct array field
   #ljSTRUCTARRAY_FETCH_FLOAT  ; Fetch float from struct array field
   #ljSTRUCTARRAY_FETCH_STR    ; Fetch string from struct array field
   #ljSTRUCTARRAY_STORE_INT    ; Store int to struct array field
   #ljSTRUCTARRAY_STORE_FLOAT  ; Store float to struct array field
   #ljSTRUCTARRAY_STORE_STR    ; Store string to struct array field

   ;- V1.022.44: Array of Structs Opcodes (array arr.StructType[n])
   ;  Access: gVar[arrayBase + (index * elementSize) + fieldOffset]
   #ljARRAYOFSTRUCT_FETCH_INT    ; Fetch int from array of structs: arr[i]\field
   #ljARRAYOFSTRUCT_FETCH_FLOAT  ; Fetch float from array of structs
   #ljARRAYOFSTRUCT_FETCH_STR    ; Fetch string from array of structs
   #ljARRAYOFSTRUCT_STORE_INT    ; Store int to array of structs
   #ljARRAYOFSTRUCT_STORE_FLOAT  ; Store float to array of structs
   #ljARRAYOFSTRUCT_STORE_STR    ; Store string to array of structs

   ; V1.022.118: ARRAYOFSTRUCT_*_LOPT variants for local index source
   ; Used when index comes from local temp (function scope expression result)
   ; _AR()\i = array slot, _AR()\j = element size, _AR()\n = field offset, _AR()\ndx = LOCAL index offset
   #ljARRAYOFSTRUCT_FETCH_INT_LOPT    ; Fetch int, index from local slot
   #ljARRAYOFSTRUCT_FETCH_FLOAT_LOPT  ; Fetch float, index from local slot
   #ljARRAYOFSTRUCT_FETCH_STR_LOPT    ; Fetch string, index from local slot
   #ljARRAYOFSTRUCT_STORE_INT_LOPT    ; Store int, index from local slot
   #ljARRAYOFSTRUCT_STORE_FLOAT_LOPT  ; Store float, index from local slot
   #ljARRAYOFSTRUCT_STORE_STR_LOPT    ; Store string, index from local slot

   ;- V1.022.54: Struct Pointer Opcodes (ptr = &struct, ptr\field)
   ;  ptr field stores base slot of struct, ptrtype = #PTR_STRUCT
   #ljGETSTRUCTADDR               ; Get address of struct variable: &structVar
   #ljPTRSTRUCTFETCH_INT          ; Read int field through struct pointer: ptr\field
   #ljPTRSTRUCTFETCH_FLOAT        ; Read float field through struct pointer
   #ljPTRSTRUCTFETCH_STR          ; Read string field through struct pointer
   #ljPTRSTRUCTSTORE_INT          ; Write int field through struct pointer: ptr\field = val
   #ljPTRSTRUCTSTORE_FLOAT        ; Write float field through struct pointer
   #ljPTRSTRUCTSTORE_STR          ; Write string field through struct pointer

   ; V1.022.117: PTRSTRUCTSTORE_*_LOPT variants for local value source
   ; Used when value comes from local temp (function scope expression result)
   ; _AR()\i = pointer slot, _AR()\n = field offset, _AR()\ndx = LOCAL value offset
   #ljPTRSTRUCTSTORE_INT_LOPT     ; Write int field, value from local slot
   #ljPTRSTRUCTSTORE_FLOAT_LOPT   ; Write float field, value from local slot
   #ljPTRSTRUCTSTORE_STR_LOPT     ; Write string field, value from local slot

   ; V1.022.119: PTRSTRUCTFETCH_*_LPTR variants for local pointer variable
   ; Used when pointer variable itself is local (function scope)
   ; _AR()\i = LOCAL pointer offset, _AR()\n = field offset
   #ljPTRSTRUCTFETCH_INT_LPTR     ; Read int field, pointer from local slot
   #ljPTRSTRUCTFETCH_FLOAT_LPTR   ; Read float field, pointer from local slot
   #ljPTRSTRUCTFETCH_STR_LPTR     ; Read string field, pointer from local slot

   ; V1.022.119: PTRSTRUCTSTORE_*_LPTR variants for local pointer variable
   ; _AR()\i = LOCAL pointer offset, _AR()\n = field offset, _AR()\ndx = value slot (global)
   #ljPTRSTRUCTSTORE_INT_LPTR     ; Write int field, pointer from local slot
   #ljPTRSTRUCTSTORE_FLOAT_LPTR   ; Write float field, pointer from local slot
   #ljPTRSTRUCTSTORE_STR_LPTR     ; Write string field, pointer from local slot

   ; V1.022.119: PTRSTRUCTSTORE_*_LPTR_LOPT variants for local pointer AND local value
   ; _AR()\i = LOCAL pointer offset, _AR()\n = field offset, _AR()\ndx = LOCAL value offset
   #ljPTRSTRUCTSTORE_INT_LPTR_LOPT    ; Write int field, both pointer and value from local
   #ljPTRSTRUCTSTORE_FLOAT_LPTR_LOPT  ; Write float field, both pointer and value from local
   #ljPTRSTRUCTSTORE_STR_LPTR_LOPT    ; Write string field, both pointer and value from local

   ;- V1.022.64: Array Resize Opcode
   ;  Resize existing array using PureBasic ReDim - preserves existing elements
   ;  _AR()\i = array slot, _AR()\j = new size
   #ljARRAYRESIZE                 ; Resize array: array arr[newSize]

   ;- V1.022.65: Struct Copy Opcode
   ;  Copy all fields from one struct to another (same type required)
   ;  _AR()\i = dest base slot, _AR()\j = source base slot, _AR()\n = size (slots)
   #ljSTRUCTCOPY                  ; Copy struct: destStruct = srcStruct

   ;- V1.029.36: Struct Pointer Opcodes - unified \ptr storage
   ;  All struct variables use gVar(slot)\ptr for contiguous memory storage
   ;  Field offset = field_index * 8 (8 bytes per field: int=Q, float=D)
   #ljSTRUCT_ALLOC                ; Allocate global struct: _AR()\i = slot, _AR()\j = byte size
   #ljSTRUCT_ALLOC_LOCAL          ; Allocate local struct: _AR()\i = paramOffset, _AR()\j = byte size
   #ljSTRUCT_FREE                 ; Free struct memory: _AR()\i = slot
   #ljSTRUCT_FETCH_INT            ; Fetch int from global struct: _AR()\i = slot, _AR()\j = byte offset
   #ljSTRUCT_FETCH_FLOAT          ; Fetch float from global struct: _AR()\i = slot, _AR()\j = byte offset
   #ljSTRUCT_FETCH_INT_LOCAL      ; Fetch int from local struct: _AR()\i = paramOffset, _AR()\j = byte offset
   #ljSTRUCT_FETCH_FLOAT_LOCAL    ; Fetch float from local struct: _AR()\i = paramOffset, _AR()\j = byte offset
   #ljSTRUCT_STORE_INT            ; Store int to global struct: _AR()\i = slot, _AR()\j = byte offset, value on stack
   #ljSTRUCT_STORE_FLOAT          ; Store float to global struct: _AR()\i = slot, _AR()\j = byte offset, value on stack
   #ljSTRUCT_STORE_INT_LOCAL      ; Store int to local struct: _AR()\i = paramOffset, _AR()\j = byte offset, value on stack
   #ljSTRUCT_STORE_FLOAT_LOCAL    ; Store float to local struct: _AR()\i = paramOffset, _AR()\j = byte offset, value on stack
   ; V1.029.55: String variants for struct fields
   #ljSTRUCT_FETCH_STR            ; Fetch string from global struct: _AR()\i = slot, _AR()\j = byte offset
   #ljSTRUCT_FETCH_STR_LOCAL      ; Fetch string from local struct: _AR()\i = paramOffset, _AR()\j = byte offset
   #ljSTRUCT_STORE_STR            ; Store string to global struct: _AR()\i = slot, _AR()\j = byte offset, value on stack
   #ljSTRUCT_STORE_STR_LOCAL      ; Store string to local struct: _AR()\i = paramOffset, _AR()\j = byte offset, value on stack
   #ljSTRUCT_COPY_PTR             ; Copy struct memory: _AR()\i = dest slot, _AR()\j = src slot, _AR()\n = byte size
   #ljFETCH_STRUCT                ; V1.029.38: Fetch global struct for parameter passing (copies \i AND \ptr)
   #ljLFETCH_STRUCT               ; V1.029.38: Fetch local struct for parameter passing (copies \i AND \ptr)

   ;- V1.026.0: List Operations - Keywords and Generic Opcodes
   ;  V1.026.8: Pool slot popped from stack (via FETCH/LFETCH), no gVar lookup needed
   ;  Generic opcodes converted to typed by postprocessor
   #ljList                        ; list keyword token
   #ljLIST_NEW                    ; Create new list - slot in \i, type in \j
   #ljLIST_ADD                    ; GENERIC: Add element (postprocessor converts to typed)
   #ljLIST_INSERT                 ; GENERIC: Insert at current (postprocessor converts to typed)
   #ljLIST_DELETE                 ; Delete current element - pool slot on stack
   #ljLIST_CLEAR                  ; Clear all elements - pool slot on stack
   #ljLIST_SIZE                   ; Push list size - pool slot on stack
   #ljLIST_FIRST                  ; Move to first, push success - pool slot on stack
   #ljLIST_LAST                   ; Move to last, push success - pool slot on stack
   #ljLIST_NEXT                   ; Move to next, push success - pool slot on stack
   #ljLIST_PREV                   ; Move to previous, push success - pool slot on stack
   #ljLIST_SELECT                 ; Select by index - pool slot, index on stack
   #ljLIST_INDEX                  ; Push current index - pool slot on stack
   #ljLIST_GET                    ; GENERIC: Get current element (postprocessor converts to typed)
   #ljLIST_SET                    ; GENERIC: Set current element (postprocessor converts to typed)
   #ljLIST_RESET                  ; Reset position to before first (-1) - pool slot on stack
   #ljLIST_SORT                   ; Sort list elements - pool slot on stack, \j = ascending(1)/descending(0)

   ;- V1.026.8: Typed List Opcodes (for VM - no type lookup needed)
   ;  Stack: [..., pool_slot] for get, [..., pool_slot, value] for add/set/insert
   #ljLIST_ADD_INT                ; Add int element - pool slot, value on stack
   #ljLIST_ADD_FLOAT              ; Add float element - pool slot, value on stack
   #ljLIST_ADD_STR                ; Add string element - pool slot, value on stack
   #ljLIST_INSERT_INT             ; Insert int at current - pool slot, value on stack
   #ljLIST_INSERT_FLOAT           ; Insert float at current - pool slot, value on stack
   #ljLIST_INSERT_STR             ; Insert string at current - pool slot, value on stack
   #ljLIST_GET_INT                ; Get current int element - pool slot on stack, push value
   #ljLIST_GET_FLOAT              ; Get current float element - pool slot on stack, push value
   #ljLIST_GET_STR                ; Get current string element - pool slot on stack, push value
   #ljLIST_SET_INT                ; Set current int element - pool slot, value on stack
   #ljLIST_SET_FLOAT              ; Set current float element - pool slot, value on stack
   #ljLIST_SET_STR                ; Set current string element - pool slot, value on stack

   ;- V1.029.28: Struct List Opcodes
   ;  Stack: [..., pool_slot, field1, field2, ...] for add/set
   ;  _AR()\i = struct size (number of fields), _AR()\j = base slot for field types
   #ljLIST_ADD_STRUCT             ; Add struct element - pool slot + N fields on stack
   #ljLIST_GET_STRUCT             ; Get current struct - pool slot on stack, push N fields
   #ljLIST_SET_STRUCT             ; Set current struct - pool slot + N fields on stack

   ;- V1.026.0: Map Operations - Keywords and Generic Opcodes
   ;  V1.026.8: Pool slot popped from stack (via FETCH/LFETCH), no gVar lookup needed
   ;  Keys are always strings, generic value opcodes converted to typed by postprocessor
   #ljMap                         ; map keyword token
   #ljMAP_NEW                     ; Create new map - slot in \i, value type in \j
   #ljMAP_PUT                     ; GENERIC: Put key-value (postprocessor converts to typed)
   #ljMAP_GET                     ; GENERIC: Get value by key (postprocessor converts to typed)
   #ljMAP_DELETE                  ; Delete by key - pool slot, key on stack
   #ljMAP_CLEAR                   ; Clear all entries - pool slot on stack
   #ljMAP_SIZE                    ; Push map size - pool slot on stack
   #ljMAP_CONTAINS                ; Check key exists - pool slot, key on stack, push bool
   #ljMAP_RESET                   ; Reset iterator - pool slot on stack
   #ljMAP_NEXT                    ; Move to next, push success - pool slot on stack
   #ljMAP_KEY                     ; Push current key (string) - pool slot on stack
   #ljMAP_VALUE                   ; GENERIC: Push current value (postprocessor converts to typed)

   ;- V1.026.8: Typed Map Opcodes (for VM - no type lookup needed)
   ;  Stack: [..., pool_slot, key] for get, [..., pool_slot, key, value] for put
   #ljMAP_PUT_INT                 ; Put int value - pool slot, key, value on stack
   #ljMAP_PUT_FLOAT               ; Put float value - pool slot, key, value on stack
   #ljMAP_PUT_STR                 ; Put string value - pool slot, key, value on stack
   #ljMAP_GET_INT                 ; Get int value by key - pool slot, key on stack, push value
   #ljMAP_GET_FLOAT               ; Get float value by key - pool slot, key on stack, push value
   #ljMAP_GET_STR                 ; Get string value by key - pool slot, key on stack, push value
   #ljMAP_VALUE_INT               ; Push current int value - pool slot on stack
   #ljMAP_VALUE_FLOAT             ; Push current float value - pool slot on stack
   #ljMAP_VALUE_STR               ; Push current string value - pool slot on stack

   ;- V1.029.28: Struct Map Opcodes
   ;  Stack: [..., pool_slot, key, field1, field2, ...] for put
   ;  _AR()\i = struct size (number of fields), _AR()\j = base slot for field types
   #ljMAP_PUT_STRUCT              ; Put struct value - pool slot, key, N fields on stack
   #ljMAP_GET_STRUCT              ; Get struct by key - pool slot, key on stack, push N fields
   #ljMAP_VALUE_STRUCT            ; Push current struct value - pool slot on stack, push N fields

   ;- V1.029.65: \ptr-based Struct Collection Opcodes (for V1.029.40+ \ptr storage)
   ;  These read/write struct data directly from/to gVar(slot)\ptr memory
   ;  Stack: [pool_slot, struct_slot] for add/put (struct data read from \ptr)
   ;  _AR()\i = byte size of struct
   #ljLIST_ADD_STRUCT_PTR         ; Add struct from \ptr storage - pool slot, struct slot on stack
   #ljLIST_GET_STRUCT_PTR         ; Get struct to \ptr storage - pool slot on stack, dest slot in \j
   #ljMAP_PUT_STRUCT_PTR          ; Put struct from \ptr storage - pool slot, key, struct slot on stack
   #ljMAP_GET_STRUCT_PTR          ; Get struct to \ptr storage - pool slot, key on stack, dest slot in \j

   ;- V1.034.6: ForEach Opcodes (scoped iterator for lists and maps)
   #ljFOREACH_LIST_INIT           ; Push initial iterator (-1) for list - varSlot in \i
   #ljFOREACH_LIST_NEXT           ; Advance iterator, push success
   #ljFOREACH_MAP_INIT            ; Push initial iterator state for map - varSlot in \i
   #ljFOREACH_MAP_NEXT            ; Advance iterator, push success
   #ljFOREACH_END                 ; Pop iterator from stack (cleanup)
   #ljFOREACH_LIST_GET_INT        ; Get list element using stack iterator
   #ljFOREACH_LIST_GET_FLOAT      ; Get list element using stack iterator
   #ljFOREACH_LIST_GET_STR        ; Get list element using stack iterator
   #ljFOREACH_MAP_KEY             ; Get current map key using stack iterator
   #ljFOREACH_MAP_VALUE_INT       ; Get current map value using stack iterator
   #ljFOREACH_MAP_VALUE_FLOAT     ; Get current map value using stack iterator
   #ljFOREACH_MAP_VALUE_STR       ; Get current map value using stack iterator


   ; V1.026.0: Special opcode for collection function first parameter
   ; V1.026.8: DEPRECATED - use FETCH/LFETCH instead (pool slot stored in gVar[slot]\i or LOCAL[offset])
   #ljPUSH_SLOT                   ; Push slot index as integer (not value) - for collection functions

   ;- V1.027.0: Type-Specialized Pointer Opcodes (eliminate runtime type dispatch)
   ;  These avoid expensive Select/If statements in VM by moving type decisions to compile time

   ;- Typed Print Pointer Opcodes (eliminates Select in PRTPTR)
   #ljPRTPTR_INT                  ; Print integer through pointer (simple var pointer)
   #ljPRTPTR_FLOAT                ; Print float through pointer (simple var pointer)
   #ljPRTPTR_STR                  ; Print string through pointer (simple var pointer)
   #ljPRTPTR_ARRAY_INT            ; Print integer through array element pointer
   #ljPRTPTR_ARRAY_FLOAT          ; Print float through array element pointer
   #ljPRTPTR_ARRAY_STR            ; Print string through array element pointer

   ;- Typed Simple Variable Pointer FETCH (eliminates If array check in PTRFETCH_*)
   ;  For simple variable pointers only (not array element pointers)
   #ljPTRFETCH_VAR_INT            ; Fetch int from simple variable pointer
   #ljPTRFETCH_VAR_FLOAT          ; Fetch float from simple variable pointer
   #ljPTRFETCH_VAR_STR            ; Fetch string from simple variable pointer

   ;- Typed Array Element Pointer FETCH (no If check needed)
   #ljPTRFETCH_ARREL_INT          ; Fetch int from array element pointer
   #ljPTRFETCH_ARREL_FLOAT        ; Fetch float from array element pointer
   #ljPTRFETCH_ARREL_STR          ; Fetch string from array element pointer

   ;- Typed Simple Variable Pointer STORE (eliminates If array check in PTRSTORE_*)
   #ljPTRSTORE_VAR_INT            ; Store int to simple variable pointer
   #ljPTRSTORE_VAR_FLOAT          ; Store float to simple variable pointer
   #ljPTRSTORE_VAR_STR            ; Store string to simple variable pointer

   ;- Typed Array Element Pointer STORE (no If check needed)
   #ljPTRSTORE_ARREL_INT          ; Store int to array element pointer
   #ljPTRSTORE_ARREL_FLOAT        ; Store float to array element pointer
   #ljPTRSTORE_ARREL_STR          ; Store string to array element pointer

   ;- Typed Pointer Arithmetic (eliminates Select in PTRADD/PTRSUB)
   #ljPTRADD_INT                  ; Pointer add for int pointer (memory address + offset*8)
   #ljPTRADD_FLOAT                ; Pointer add for float pointer (memory address + offset*8)
   #ljPTRADD_STRING               ; Pointer add for string pointer (slot index only)
   #ljPTRADD_ARRAY                ; Pointer add for array pointer (element index only)
   #ljPTRSUB_INT                  ; Pointer sub for int pointer
   #ljPTRSUB_FLOAT                ; Pointer sub for float pointer
   #ljPTRSUB_STRING               ; Pointer sub for string pointer
   #ljPTRSUB_ARRAY                ; Pointer sub for array pointer

   ;- Typed Pointer Increment/Decrement (eliminates Select in PTRINC/PTRDEC)
   #ljPTRINC_INT                  ; Increment int pointer (memory address)
   #ljPTRINC_FLOAT                ; Increment float pointer (memory address)
   #ljPTRINC_STRING               ; Increment string pointer (slot index)
   #ljPTRINC_ARRAY                ; Increment array pointer (element index)
   #ljPTRDEC_INT                  ; Decrement int pointer
   #ljPTRDEC_FLOAT                ; Decrement float pointer
   #ljPTRDEC_STRING               ; Decrement string pointer
   #ljPTRDEC_ARRAY                ; Decrement array pointer

   ;- Typed Pointer Pre-Increment/Pre-Decrement
   #ljPTRINC_PRE_INT              ; Pre-increment int pointer
   #ljPTRINC_PRE_FLOAT            ; Pre-increment float pointer
   #ljPTRINC_PRE_STRING           ; Pre-increment string pointer
   #ljPTRINC_PRE_ARRAY            ; Pre-increment array pointer
   #ljPTRDEC_PRE_INT              ; Pre-decrement int pointer
   #ljPTRDEC_PRE_FLOAT            ; Pre-decrement float pointer
   #ljPTRDEC_PRE_STRING           ; Pre-decrement string pointer
   #ljPTRDEC_PRE_ARRAY            ; Pre-decrement array pointer

   ;- Typed Pointer Post-Increment/Post-Decrement
   #ljPTRINC_POST_INT             ; Post-increment int pointer
   #ljPTRINC_POST_FLOAT           ; Post-increment float pointer
   #ljPTRINC_POST_STRING          ; Post-increment string pointer
   #ljPTRINC_POST_ARRAY           ; Post-increment array pointer
   #ljPTRDEC_POST_INT             ; Post-decrement int pointer
   #ljPTRDEC_POST_FLOAT           ; Post-decrement float pointer
   #ljPTRDEC_POST_STRING          ; Post-decrement string pointer
   #ljPTRDEC_POST_ARRAY           ; Post-decrement array pointer

   ;- Typed Pointer Compound Assignment (eliminates Select in PTRADD_ASSIGN/PTRSUB_ASSIGN)
   #ljPTRADD_ASSIGN_INT           ; ptr += offset for int pointer
   #ljPTRADD_ASSIGN_FLOAT         ; ptr += offset for float pointer
   #ljPTRADD_ASSIGN_STRING        ; ptr += offset for string pointer
   #ljPTRADD_ASSIGN_ARRAY         ; ptr += offset for array pointer
   #ljPTRSUB_ASSIGN_INT           ; ptr -= offset for int pointer
   #ljPTRSUB_ASSIGN_FLOAT         ; ptr -= offset for float pointer
   #ljPTRSUB_ASSIGN_STRING        ; ptr -= offset for string pointer
   #ljPTRSUB_ASSIGN_ARRAY         ; ptr -= offset for array pointer

   ;- V1.033.5: Local Pointer Fetch/Store (no If check, uses gLocal[])
   #ljPTRFETCH_LVAR_INT           ; Fetch int from local simple variable pointer
   #ljPTRFETCH_LVAR_FLOAT         ; Fetch float from local simple variable pointer
   #ljPTRFETCH_LVAR_STR           ; Fetch string from local simple variable pointer
   #ljPTRFETCH_LARREL_INT         ; Fetch int from local array element pointer
   #ljPTRFETCH_LARREL_FLOAT       ; Fetch float from local array element pointer
   #ljPTRFETCH_LARREL_STR         ; Fetch string from local array element pointer
   #ljPTRSTORE_LVAR_INT           ; Store int to local simple variable pointer
   #ljPTRSTORE_LVAR_FLOAT         ; Store float to local simple variable pointer
   #ljPTRSTORE_LVAR_STR           ; Store string to local simple variable pointer
   #ljPTRSTORE_LARREL_INT         ; Store int to local array element pointer
   #ljPTRSTORE_LARREL_FLOAT       ; Store float to local array element pointer
   #ljPTRSTORE_LARREL_STR         ; Store string to local array element pointer

   #ljEOF
EndEnumeration

; Calculate total token count at compile time
#C2TOKENCOUNT = #ljEOF + 1


;- Error Codes
Enumeration C2ErrorCodes
   #C2ERR_INVALID_FILE = -2
   #C2ERR_FILE_OPEN_FAILED = -3

   #C2ERR_EMPTY_CHAR_LITERAL = 2
   #C2ERR_INVALID_ESCAPE_CHAR = 3
   #C2ERR_MULTI_CHAR_LITERAL = 4
   #C2ERR_UNRECOGNIZED_CHAR = 5
   #C2ERR_EOF_IN_STRING = 6
   #C2ERR_EOL_IN_STRING = 7
   #C2ERR_EOL_IN_IDENTIFIER = 8
   #C2ERR_UNKNOWN_SEQUENCE = 9
   #C2ERR_SYNTAX_EXPECTED = 10
   #C2ERR_EXPECTED_PRIMARY = 11
   #C2ERR_EXPECTED_STATEMENT = 12
   #C2ERR_STACK_OVERFLOW = 14
   #C2ERR_FUNCTION_REDECLARED = 15
   #C2ERR_UNDEFINED_FUNCTION = 16

   #C2ERR_MEMORY_ALLOCATION = 17
   #C2ERR_CODEGEN_FAILED = 18

   ; V1.024.0: Control flow errors
   #C2ERR_BREAK_OUTSIDE_LOOP = 19
   #C2ERR_CONTINUE_OUTSIDE_LOOP = 20
EndEnumeration

;- Structures
Structure stType
   code.l
   i.l
   j.l
   n.l
   ndx.l
   funcid.l
   flags.b     ; Instruction flags (bit 0: in ternary expression)
   anchor.w    ; V1.020.070: Jump anchor ID for NOOP-safe offset recalculation
EndStructure

Structure stCodeIns
   code.l      ; Opcode
   i.l         ; First parameter (full int)
   j.l         ; Second parameter (full int)
   n.w         ; Local var count (word)
   ndx.w       ; Local array count or index slot (word)
   funcid.l    ; Function ID for CALL (long - V1.033.50: changed from .w to support >32K functions)
   anchor.w    ; V1.020.070: Jump anchor ID for NOOP-safe offset recalculation
EndStructure

; V1.020.073: Jump tracker for incremental NOOP offset adjustment
Structure stJumpTracker
   *instruction.stType  ; Pointer to jump instruction in llObjects()
   *target.stType       ; V1.020.085: Pointer to target instruction
   srcPos.i             ; Source position when created
   targetPos.i          ; Target position when created
   offset.i             ; Current offset (adjusted as NOOPs created)
   type.i               ; Jump type: #ljJZ, #ljJMP, #ljTENIF, #ljTENELSE
   holeMode.i           ; V1.023.43: Hole mode for offset adjustment (#C2HOLE_LOOPBACK needs -1)
EndStructure

; Instruction flags
#INST_FLAG_TERNARY = 1
#INST_FLAG_IMPLICIT_RETURN = 2  ; V1.034.0: Marks NOOPIF that will become RETURN

;- Pointer Type Tags (for efficient pointer metadata)
Enumeration  ; Pointer Types
   #PTR_NONE = 0           ; Not a pointer
   #PTR_INT = 1            ; Pointer to integer variable
   #PTR_FLOAT = 2          ; Pointer to float variable
   #PTR_STRING = 3         ; Pointer to string variable
   #PTR_ARRAY_INT = 4      ; Pointer to integer array element (GLOBAL array in gVar[])
   #PTR_ARRAY_FLOAT = 5    ; Pointer to float array element (GLOBAL array in gVar[])
   #PTR_ARRAY_STRING = 6   ; Pointer to string array element (GLOBAL array in gVar[])
   #PTR_FUNCTION = 7       ; Pointer to function (PC address)
   #PTR_STRUCT = 8         ; V1.022.54: Pointer to struct (base slot in ptr field)
   ; V1.031.22: LOCAL array pointer types (array stored in gLocal[], not gVar[])
   #PTR_LOCAL_ARRAY_INT = 9      ; Pointer to local integer array element
   #PTR_LOCAL_ARRAY_FLOAT = 10   ; Pointer to local float array element
   #PTR_LOCAL_ARRAY_STRING = 11  ; Pointer to local string array element
   ; V1.031.34: LOCAL simple variable pointer types (for pointers to local int/float/string variables)
   #PTR_LOCAL_INT = 12           ; Pointer to local integer variable (uses gLocal[])
   #PTR_LOCAL_FLOAT = 13         ; Pointer to local float variable (uses gLocal[])
   #PTR_LOCAL_STRING = 14        ; Pointer to local string variable (uses gLocal[])
EndEnumeration

; Runtime value arrays - separated by type for maximum VM performance
Structure stVarMeta  ; Compile-time metadata and constant values
   name.s
   flags.w
   paramOffset.i        ; -1 = global variable (use varSlot directly)
                        ; >= 0 = local variable (offset from localBase)
                        ; V1.31.0: Used at runtime to compute: actualSlot = localBase + paramOffset
   typeSpecificIndex.i  ; For local arrays: index within function's local array list
   ; Array metadata (compile-time only)
   arraySize.i          ; Number of elements (0 if not array)
   elementSize.i        ; Slots per element (1 for primitives, N for structs)
   ; Constant values (set at compile time, copied to gVar at VM init)
   valueInt.i           ; Integer constant value
   valueFloat.d         ; Float constant value
   valueString.s        ; String constant value
   ; Structure metadata (V1.021.0)
   structType.s         ; For struct vars: name of struct type (key in mapStructDefs)
   ; Pointer metadata (V1.022.54)
   pointsToStructType.s ; For struct pointers: struct type that pointer points to
   ; V1.029.37: Struct field access metadata (for \ptr storage)
   structFieldBase.i    ; Base slot of parent struct (-1 if not a struct field)
   structFieldOffset.i  ; Byte offset within struct memory (field_index * 8)
   ; V1.029.40: Track if STRUCT_ALLOC has been emitted for this struct
   structAllocEmitted.b ; True if STRUCT_ALLOC has been emitted for this struct base slot
   ; V1.036.0: Multi-dimensional array support (folded as 1D)
   nDimensions.b        ; Number of dimensions (1-4, 0=not multi-dim / single-dim array)
   dimSizes.i[4]        ; Size of each dimension [D1, D2, D3, D4]
   dimStrides.i[4]      ; Stride for each dimension (precomputed: dimStrides[i] = product of dimSizes[i+1..n])
EndStructure

; V1.034.0: Unified Code Element Structure for O(1) compiler lookups
; This parallels gVarMeta for faster name-based lookups during compilation
Enumeration eElementType
   #ELEMENT_NONE = 0
   #ELEMENT_VARIABLE
   #ELEMENT_CONSTANT
   #ELEMENT_FUNCTION
   #ELEMENT_PARAMETER
   #ELEMENT_STRUCT_FIELD
   #ELEMENT_ARRAY
EndEnumeration

Structure stCodeElement
   ; Identity
   name.s                  ; Element name (variable, function, constant name)
   id.i                    ; Numeric ID (matches gVarMeta slot for variables)

   ; Type information
   elementType.w           ; eElementType
   varType.w               ; Type flags: #C2FLAG_INT, #C2FLAG_FLOAT, #C2FLAG_STR, etc.

   ; Value storage (for constants)
   valueInt.i
   valueFloat.d
   valueString.s

   ; Size and structure info
   size.i                  ; Size in slots
   elementSize.i           ; For arrays: slots per element; for structs: field count
   structType.s            ; For structs/struct pointers: struct type name

   ; Flags
   isIdent.b               ; Is an identifier (not literal constant)
   isArray.b               ; Is an array
   isPointer.b             ; Is a pointer type
   isLeftMost.b            ; Is leftmost in expression chain

   ; Expression chain traversal (for type coercion in a + b * c)
   *Left.stCodeElement     ; Left operand in expression
   *Right.stCodeElement    ; Right operand in expression

   ; Usage flow tracking (assignment->read patterns)
   *AssignedFrom.stCodeElement  ; Source of last assignment
   *UsedBy.stCodeElement        ; Next usage after this point

   ; Scope information
   paramOffset.i           ; -1 = global, >= 0 = local offset from localBase
   functionContext.s       ; For locals: parent function name
   List parameters.s()     ; For functions: parameter names
   returnType.w            ; For functions: return type flags

   ; Backwards compatibility
   varSlot.i               ; Index in gVarMeta array
EndStructure


Structure stATR
   s.s
   strtoken.w
   flttoken.w
EndStructure

Structure stBuiltinDef
   name.s          ; Function name as it appears in source code
   opcode.i        ; Opcode for this built-in
   minParams.i     ; Minimum parameter count
   maxParams.i     ; Maximum parameter count (-1 = unlimited)
   returnType.i    ; Return type: #C2FLAG_INT, #C2FLAG_FLOAT, or #C2FLAG_STR
EndStructure

;- Structure Field Definition (V1.021.0)
;  V1.022.0: Extended for array fields in structures
;  V1.022.47: Extended for nested struct fields
Structure stFieldDef
   name.s          ; Field name (e.g., "x", "y", "data")
   fieldType.w     ; Type flags (#C2FLAG_INT, #C2FLAG_FLOAT, #C2FLAG_STR, or 0 for nested struct)
   offset.i        ; Offset from base slot (0, 1, 2, ...)
   isArray.b       ; V1.022.0: True if field is an array
   arraySize.i     ; V1.022.0: Number of elements (0 if not array)
   structType.s    ; V1.022.47: Struct type name if field is a nested struct (empty if primitive)
EndStructure

;- Structure Type Definition (V1.021.0)
Structure stStructDef
   name.s          ; Structure type name (e.g., "Point")
   totalSize.i     ; Total gVar[] slots required
   List fields.stFieldDef()  ; Field definitions
EndStructure

;- V1.023.0: Variable Preloading Templates
;  Templates store initial values for variables, copied at VM init (globals)
;  and function entry (locals). This eliminates MOV instructions for constants.

;  Template value structure - mirrors stVT fields for direct field copy
Structure stVarTemplate
   ss.s              ; String value
   i.i               ; Integer value
   f.d               ; Float value
   *ptr              ; Pointer value (for pointer variables)
   ptrtype.w         ; Pointer type tag (0=not pointer, 1-7=pointer types)
   arraySize.i       ; For arrays: number of elements (0 if not array)
                     ; Note: actual array elements allocated at runtime via ReDim
   ; V1.033.50: VM needs these fields to work independently of gVarMeta
   flags.l           ; Variable flags (CONST, ARRAY, STRUCT, etc.)
   paramOffset.i     ; Parameter offset (-1 for globals)
   elementSize.i     ; For structs: number of fields (for memory allocation)
EndStructure

;  Function template - stores initial values for a function's local variables
;  Parameters (LOCAL[0..nParams-1]) are NOT in template - they come from caller
;  Template covers LOCAL[nParams..totalVars-1] only
Structure stFuncTemplate
   funcId.i                      ; Function ID (index in gFuncTemplates)
   localCount.i                  ; Number of non-param locals (template size)
   funcSlot.i                    ; V1.035.0: *gVar slot for this function's locals
   nParams.i                     ; V1.035.0: Number of parameters (for var() array sizing)
   Array template.stVarTemplate(0)  ; Pre-initialized values for locals
EndStructure

;- Globals

Global Dim           gszATR.stATR(#C2TOKENCOUNT)
Global Dim           gVarMeta.stVarMeta(#C2MAXCONSTANTS)  ; Compile-time info only
Global Dim           gFuncLocalArraySlots.i(#C2MAXFUNCTIONS, 15)  ; [functionID, localArrayIndex] -> varSlot
Global Dim           arCode.stCodeIns(1)
Global NewMap        mapPragmas.s()
Global NewMap        mapStructDefs.stStructDef()  ; V1.021.0: Structure type definitions

; V1.022.21: Constant extraction maps - pre-allocated slots for all constants
Global NewMap        mapConstInt.i()      ; "value" -> slot (e.g., "100" -> 5)
Global NewMap        mapConstFloat.i()    ; "value" -> slot (e.g., "3.14" -> 6)
Global NewMap        mapConstStr.i()      ; "value" -> slot (e.g., "hello" -> 7)

; V1.023.0: Variable preloading templates
Global Dim           gGlobalTemplate.stVarTemplate(0)   ; Template for global variables (resized to gnGlobalVariables)
Global Dim           gFuncTemplates.stFuncTemplate(0)   ; Templates for function locals (resized to function count)
Global               gnFuncTemplateCount.i              ; Number of function templates

Global               gnLastVariable.i
Global               gnGlobalVariables.i  ; V1.020.057: Count of global variables only (for stack calculation)
Global               gnTotalTokens.i
Global               gPtrFetchExpectedType.w  ; V1.20.5: Expected type for PTRFETCH (0=use generic)
Global               gnTempSlotCounter.i  ; V1.022.20: Counter for temp slot names ($sar0, $sar1, etc.)
Global               gExtraStructSlots.i  ; V1.029.5: Extra slots pushed for struct parameters
Global               gDotFieldType.w      ; V1.029.19: Field type from DOT notation handler (for typed LFETCH)

; V1.033.17: ASM listing name lookup tables (populated during codegen, used by ASMLine)
Global Dim           gFuncNames.s(#C2MAXFUNCTIONS)       ; funcId -> function name (for CALL display)
Global Dim           gLocalNames.s(#C2MAXFUNCTIONS, 64)  ; (funcId, paramOffset) -> local variable name

; V1.033.50: Dynamic function array capacity tracking
Global               gnFuncArrayCapacity.i = #C2MAXFUNCTIONS  ; Current capacity of function-indexed arrays

;- Macros
; V1.033.50/54: Ensure function-indexed arrays can hold funcId
; NOTE: 2D arrays (gFuncLocalArraySlots, gLocalNames) cannot be ReDim'd on first dimension
; Initial capacity set to 8192 to handle large programs (up to ~7000 functions)
Macro                EnsureFuncArrayCapacity(_funcId_)
   ; Capacity check removed - 8192 should be sufficient for any reasonable program
   ; If exceeded, array access will generate out-of-bounds error
EndMacro

;- Macros
Macro          _ASMLineHelper1(view, uvar)
   CompilerIf view
      If gVarMeta( uvar )\flags & #C2FLAG_INT
         temp = " (" + Str( gVarMeta( uvar )\valueInt ) + ")"
      ElseIf gVarMeta( uvar )\flags & #C2FLAG_FLOAT
         temp = " (" + StrF( gVarMeta( uvar )\valueFloat, 3 ) + ")"
      ElseIf gVarMeta( uvar )\flags & #C2FLAG_STR
         temp = " (" + gVarMeta( uvar )\valueString + ")"
      EndIf
   CompilerEndIf
EndMacro

Macro          DebugShowFilename()
   Debug "==========================================="
   Debug "Executing: " + filename
   Debug "==========================================="
EndMacro

Macro          _ASMLineHelper2(uvar)
   If gVarMeta( uvar )\flags & #C2FLAG_IDENT
      temp = gVarMeta( uvar )\name
   ElseIf gVarMeta( uvar )\flags & #C2FLAG_STR
      temp = gVarMeta( uvar )\valueString
   ElseIf gVarMeta( uvar )\flags & #C2FLAG_FLOAT
      temp = StrD( gVarMeta( uvar )\valueFloat )
   Else
      temp = Str( gVarMeta( uvar )\valueInt )
   EndIf
EndMacro

Macro                   _VarExpand(vr)
   temp = ""
   If gVarMeta( vr )\flags & #C2FLAG_INT :   temp + " INT "   : EndIf
   If gVarMeta( vr )\flags & #C2FLAG_FLOAT : temp + " FLT "   : EndIf
   If gVarMeta( vr )\flags & #C2FLAG_STR   : temp + " STR "   : EndIf
   If gVarMeta( vr )\flags & #C2FLAG_CONST : temp + " CONST " : EndIf
   If gVarMeta( vr )\flags & #C2FLAG_PARAM : temp + " PARAM " : EndIf
   If gVarMeta( vr )\flags & #C2FLAG_IDENT : temp + " VAR"    : EndIf
EndMacro

; V1.033.17: Helper macro to look up local variable name by paramOffset
; Uses gVarMeta to find mangled name matching funcName_varName pattern
; Uses gAsmCurrentFunc to track which function we're in during ASM display
Global gAsmCurrentFunc.i = -1      ; Current function ID for ASM display
Global gAsmLocalName.s = ""        ; Result of local name lookup
Global _asmGetLocalPrefix.s        ; Temp for _GetLocalName macro
Global _asmGetLocalPrefixLen.i     ; Temp for _GetLocalName macro
Global _asmGetLocalIdx.i           ; Temp for _GetLocalName macro
Global _asmFuncName.s              ; Temp for ASMLine CALL display
Global _asmSrcLocal.s              ; Temp for ASMLine LLMOV display

; _GetLocalName macro - simplified to just show offset (name lookup too complex for macro expansion)
Macro _GetLocalName(paramOffset)
   gAsmLocalName = "L" + Str(paramOffset)
EndMacro

Macro          ASMLine(obj,show)
   CompilerIf show = 1
      line = RSet( Str( i + 1 ), 9 ) + "  "
   CompilerElse
      line = RSet( Str( ListIndex(obj) ), 9 ) + "  "
   CompilerEndIf

   ; V1.026.10: Bounds check for ASMLine opcode display
   If obj\code >= 0 And obj\code < #C2TOKENCOUNT
      line + LSet( gszATR( obj\code )\s, 30 ) + "  "
   Else
      line + LSet( "UNKNOWN_" + Str(obj\code), 30 ) + "  "
      CompilerIf show = 1
         Debug "ERROR: Invalid opcode " + Str(obj\code) + " at line " + Str(i)
      CompilerElse
         Debug "ERROR: Invalid opcode " + Str(obj\code) + " at line " + Str(ListIndex(obj))
      CompilerEndIf
   EndIf
   temp = "" : flag = 0
   
   ; V1.024.12: Added JNZ to target display for switch case debugging
   If obj\code = #ljJMP Or obj\code = #ljJZ Or obj\code = #ljJNZ
      CompilerIf show
         ; V1.023.20: Fix target display to be 1-indexed (matching line numbers)
         line + "  (" +Str(obj\i) + ") " + Str(i+1+obj\i)
      CompilerElse
         line + "  (" +Str(obj\i) + ") " + Str(ListIndex(obj)+1+obj\i)
      CompilerEndIf
   ElseIf obj\code = #ljCall Or obj\code = #ljCALL0 Or obj\code = #ljCALL1 Or obj\code = #ljCALL2 Or obj\code = #ljCALL_REC
      ; V1.033.12: Include optimized CALL0, CALL1, CALL2 opcodes; V1.034.65: CALL_REC for recursive
      CompilerIf show
         ; Runtime: just show basic CALL info (no compile-time metadata available)
         line + "  (" +Str(obj\i) + ") " + Str(i+1+obj\i) + " [params=" + Str(obj\j) + " locals=" + Str(obj\n) + " nArr=" + Str(obj\ndx) + "]"
      CompilerElse
         ; V1.033.17: Compile-time: Look up and display function name
         gAsmCurrentFunc = obj\funcid
         _asmFuncName = ""
         If obj\funcid >= 0 And obj\funcid < 512
            _asmFuncName = gFuncNames(obj\funcid)
         EndIf
         If _asmFuncName = ""
            _asmFuncName = "func#" + Str(obj\funcid)
         EndIf
         line + _asmFuncName + "() [params=" + Str(obj\j) + " locals=" + Str(obj\n) + " nArr=" + Str(obj\ndx) + "]"
      CompilerEndIf
   ; Specialized array operations (no runtime branching) - opcode name encodes all info
   ElseIf obj\code = #ljARRAYFETCH_INT_GLOBAL_OPT Or obj\code = #ljARRAYFETCH_INT_GLOBAL_STACK Or obj\code = #ljARRAYFETCH_INT_LOCAL_OPT Or obj\code = #ljARRAYFETCH_INT_LOCAL_STACK Or obj\code = #ljARRAYFETCH_FLOAT_GLOBAL_OPT Or obj\code = #ljARRAYFETCH_FLOAT_GLOBAL_STACK Or obj\code = #ljARRAYFETCH_FLOAT_LOCAL_OPT Or obj\code = #ljARRAYFETCH_FLOAT_LOCAL_STACK Or obj\code = #ljARRAYFETCH_STR_GLOBAL_OPT Or obj\code = #ljARRAYFETCH_STR_GLOBAL_STACK Or obj\code = #ljARRAYFETCH_STR_LOCAL_OPT Or obj\code = #ljARRAYFETCH_STR_LOCAL_STACK Or obj\code = #ljARRAYSTORE_INT_GLOBAL_OPT_OPT Or obj\code = #ljARRAYSTORE_INT_GLOBAL_OPT_STACK Or obj\code = #ljARRAYSTORE_INT_GLOBAL_STACK_OPT Or obj\code = #ljARRAYSTORE_INT_GLOBAL_STACK_STACK Or obj\code = #ljARRAYSTORE_INT_LOCAL_OPT_OPT Or obj\code = #ljARRAYSTORE_INT_LOCAL_OPT_STACK Or obj\code = #ljARRAYSTORE_INT_LOCAL_STACK_OPT Or obj\code = #ljARRAYSTORE_INT_LOCAL_STACK_STACK Or obj\code = #ljARRAYSTORE_FLOAT_GLOBAL_OPT_OPT Or obj\code = #ljARRAYSTORE_FLOAT_GLOBAL_OPT_STACK Or obj\code = #ljARRAYSTORE_FLOAT_GLOBAL_STACK_OPT Or obj\code = #ljARRAYSTORE_FLOAT_GLOBAL_STACK_STACK Or obj\code = #ljARRAYSTORE_FLOAT_LOCAL_OPT_OPT Or obj\code = #ljARRAYSTORE_FLOAT_LOCAL_OPT_STACK Or obj\code = #ljARRAYSTORE_FLOAT_LOCAL_STACK_OPT Or obj\code = #ljARRAYSTORE_FLOAT_LOCAL_STACK_STACK Or obj\code = #ljARRAYSTORE_STR_GLOBAL_OPT_OPT Or obj\code = #ljARRAYSTORE_STR_GLOBAL_OPT_STACK Or obj\code = #ljARRAYSTORE_STR_GLOBAL_STACK_OPT Or obj\code = #ljARRAYSTORE_STR_GLOBAL_STACK_STACK Or obj\code = #ljARRAYSTORE_STR_LOCAL_OPT_OPT Or obj\code = #ljARRAYSTORE_STR_LOCAL_OPT_STACK Or obj\code = #ljARRAYSTORE_STR_LOCAL_STACK_OPT Or obj\code = #ljARRAYSTORE_STR_LOCAL_STACK_STACK
      ; Specialized array operations - opcode name contains all optimization info
      line + "[arr=" + Str(obj\i)
      ; Show actual slot numbers for optimized paths
      If obj\ndx >= 0
         line + " idx=" + Str(obj\ndx)
      EndIf
      ; For STORE operations with optimized value, show value slot
      If obj\n >= 0
         line + " val=" + Str(obj\n)
      EndIf
      line + "]"
   ElseIf obj\code = #ljARRAYFETCH Or obj\code = #ljARRAYFETCH_INT Or obj\code = #ljARRAYFETCH_FLOAT Or obj\code = #ljARRAYFETCH_STR Or obj\code = #ljARRAYSTORE Or obj\code = #ljARRAYSTORE_INT Or obj\code = #ljARRAYSTORE_FLOAT Or obj\code = #ljARRAYSTORE_STR
      ; Array operations: show array var, index, and value (for STORE) info
      line + "[arr=" + Str(obj\i)
      If obj\ndx >= 0
         line + " idx=slot" + Str(obj\ndx)
      Else
         line + " idx=stack"
      EndIf
      ; For ARRAYSTORE operations, also show value source (n field)
      If obj\code = #ljARRAYSTORE Or obj\code = #ljARRAYSTORE_INT Or obj\code = #ljARRAYSTORE_FLOAT Or obj\code = #ljARRAYSTORE_STR
         If obj\n >= 0
            line + " val=slot" + Str(obj\n)
         Else
            line + " val=stack"
         EndIf
      EndIf
      line + " j=" + Str(obj\j) + "]"
   ; V1.022.8: Struct array operations - show baseSlot, index info
   ElseIf obj\code = #ljSTRUCTARRAY_FETCH_INT Or obj\code = #ljSTRUCTARRAY_FETCH_FLOAT Or obj\code = #ljSTRUCTARRAY_FETCH_STR Or obj\code = #ljSTRUCTARRAY_STORE_INT Or obj\code = #ljSTRUCTARRAY_STORE_FLOAT Or obj\code = #ljSTRUCTARRAY_STORE_STR
      line + "[base=" + Str(obj\i)
      If obj\ndx >= 0
         line + " idx=slot" + Str(obj\ndx)
      Else
         line + " idx=stack"
      EndIf
      ; For SARSTORE operations, also show value source (n field)
      If obj\code = #ljSTRUCTARRAY_STORE_INT Or obj\code = #ljSTRUCTARRAY_STORE_FLOAT Or obj\code = #ljSTRUCTARRAY_STORE_STR
         If obj\n >= 0
            line + " val=slot" + Str(obj\n)
         Else
            line + " val=stack"
         EndIf
      EndIf
      line + " local=" + Str(obj\j) + "]"
      flag + 1
   ; V1.022.44: Array of Struct operations - show array base, index, element size, field offset
   ElseIf obj\code = #ljARRAYOFSTRUCT_FETCH_INT Or obj\code = #ljARRAYOFSTRUCT_FETCH_FLOAT Or obj\code = #ljARRAYOFSTRUCT_FETCH_STR Or obj\code = #ljARRAYOFSTRUCT_STORE_INT Or obj\code = #ljARRAYOFSTRUCT_STORE_FLOAT Or obj\code = #ljARRAYOFSTRUCT_STORE_STR Or obj\code = #ljARRAYOFSTRUCT_FETCH_INT_LOPT Or obj\code = #ljARRAYOFSTRUCT_FETCH_FLOAT_LOPT Or obj\code = #ljARRAYOFSTRUCT_FETCH_STR_LOPT Or obj\code = #ljARRAYOFSTRUCT_STORE_INT_LOPT Or obj\code = #ljARRAYOFSTRUCT_STORE_FLOAT_LOPT Or obj\code = #ljARRAYOFSTRUCT_STORE_STR_LOPT
      line + "[arr=" + Str(obj\i) + " idx=slot" + Str(obj\ndx) + " elemSz=" + Str(obj\j) + " fldOfs=" + Str(obj\n) + "]"
      flag + 1
   ; V1.022.54: Struct pointer operations - show ptr slot, field offset
   ElseIf obj\code = #ljGETSTRUCTADDR
      line + "[struct=" + Str(obj\i) + "] --> [sp]"
      flag + 1
   ElseIf obj\code = #ljPTRSTRUCTFETCH_INT Or obj\code = #ljPTRSTRUCTFETCH_FLOAT Or obj\code = #ljPTRSTRUCTFETCH_STR Or obj\code = #ljPTRSTRUCTSTORE_INT Or obj\code = #ljPTRSTRUCTSTORE_FLOAT Or obj\code = #ljPTRSTRUCTSTORE_STR Or obj\code = #ljPTRSTRUCTSTORE_INT_LOPT Or obj\code = #ljPTRSTRUCTSTORE_FLOAT_LOPT Or obj\code = #ljPTRSTRUCTSTORE_STR_LOPT
      line + "[ptr=slot" + Str(obj\i) + " fldOfs=" + Str(obj\n) + " val=" + Str(obj\ndx) + "]"
      flag + 1
   ; V1.022.119: LPTR variants - local pointer variable
   ElseIf obj\code = #ljPTRSTRUCTFETCH_INT_LPTR Or obj\code = #ljPTRSTRUCTFETCH_FLOAT_LPTR Or obj\code = #ljPTRSTRUCTFETCH_STR_LPTR
      line + "[ptr=LOCAL[" + Str(obj\i) + "] fldOfs=" + Str(obj\n) + "] --> [sp]"
      flag + 1
   ElseIf obj\code = #ljPTRSTRUCTSTORE_INT_LPTR Or obj\code = #ljPTRSTRUCTSTORE_FLOAT_LPTR Or obj\code = #ljPTRSTRUCTSTORE_STR_LPTR
      line + "[ptr=LOCAL[" + Str(obj\i) + "] fldOfs=" + Str(obj\n) + " val=slot" + Str(obj\ndx) + "]"
      flag + 1
   ElseIf obj\code = #ljPTRSTRUCTSTORE_INT_LPTR_LOPT Or obj\code = #ljPTRSTRUCTSTORE_FLOAT_LPTR_LOPT Or obj\code = #ljPTRSTRUCTSTORE_STR_LPTR_LOPT
      line + "[ptr=LOCAL[" + Str(obj\i) + "] fldOfs=" + Str(obj\n) + " val=LOCAL[" + Str(obj\ndx) + "]]"
      flag + 1
   ElseIf obj\code = #ljMOV
      ; V1.034.37: Unified MOV with n field for locality
      ; n & 1 = source is local, n >> 1 = destination is local
      ; n=0: GG, n=1: LG, n=2: GL, n=3: LL
      Protected srcIsLocal.i = obj\n & 1
      Protected dstIsLocal.i = obj\n >> 1
      If dstIsLocal
         ; Destination is local
         If srcIsLocal
            ; LL: local to local
            line + "[LOCAL[" + Str(obj\j) + "]] --> [LOCAL[" + Str(obj\i) + "]] (n=" + Str(obj\n) + " LL)"
         Else
            ; GL: global to local
            _ASMLineHelper1( show, obj\j )
            line + "[" + gVarMeta( obj\j )\name + temp + "] --> [LOCAL[" + Str(obj\i) + "]] (n=" + Str(obj\n) + " GL)"
         EndIf
      Else
         ; Destination is global
         If srcIsLocal
            ; LG: local to global
            line + "[LOCAL[" + Str(obj\j) + "]] --> [" + gVarMeta( obj\i )\name + "] (n=" + Str(obj\n) + " LG)"
         Else
            ; GG: global to global
            _ASMLineHelper1( show, obj\j )
            line + "[" + gVarMeta( obj\j )\name + temp + "] --> [" + gVarMeta( obj\i )\name + "] (n=" + Str(obj\n) + " GG)"
         EndIf
      EndIf
      flag + 1
   ; V1.034.30: Unified STORE handling - check j flag for local vs global
   ElseIf obj\code = #ljSTORE Or obj\code = #ljSTORES Or obj\code = #ljSTOREF
      ; V1.034.31: Check j flag to determine local vs global
      If obj\j = 1
         ; Unified STORE to local variable - show as LOCAL
         CompilerIf show
            line + "[sp] --> [LOCAL[" + Str(obj\i) + "]]"
         CompilerElse
            ; V1.033.17: Show local variable name at compile-time
            _GetLocalName(obj\i)
            line + "[sp] --> " + gAsmLocalName
         CompilerEndIf
      Else
         ; V1.023.31: Don't use sp-1 for value display - sp is runtime, not compile-time
         ; Global STORE (j=0)
         line + "[sp] --> [" + gVarMeta( obj\i )\name + "] (slot=" + Str(obj\i) + " j=" + Str(obj\j) + ")"
      EndIf
      flag + 1
   ; Local variable STORE operations - show paramOffset with name
   ; V1.023.21: Added PLSTORE to display
   ElseIf obj\code = #ljLSTORE Or obj\code = #ljLSTORES Or obj\code = #ljLSTOREF Or (obj\code = #ljPSTORE And obj\j = 1)
      CompilerIf show
         line + "[sp] --> [LOCAL[" + Str(obj\i) + "]]"
      CompilerElse
         ; V1.033.17: Show local variable name at compile-time
         _GetLocalName(obj\i)
         line + "[sp] --> " + gAsmLocalName
      CompilerEndIf
      flag + 1
   ; Local variable FETCH operations - show paramOffset with name
   ElseIf obj\code = #ljLFETCH Or obj\code = #ljLFETCHS Or obj\code = #ljLFETCHF
      CompilerIf show
         line + "[LOCAL[" + Str(obj\i) + "]] --> [sp]"
      CompilerElse
         ; V1.033.17: Show local variable name at compile-time
         _GetLocalName(obj\i)
         line + gAsmLocalName + " --> [sp]"
      CompilerEndIf
      flag + 1
   ; Local variable MOV operations - show both indices with name
   ElseIf obj\code = #ljLMOV Or obj\code = #ljLMOVS Or obj\code = #ljLMOVF
      CompilerIf show
         line + "[slot" + Str(obj\j) + "] --> [LOCAL[" + Str(obj\i) + "]]"
      CompilerElse
         ; V1.033.17: Show local variable name at compile-time
         _GetLocalName(obj\i)
         line + "[" + gVarMeta(obj\j)\name + "] --> " + gAsmLocalName
      CompilerEndIf
      flag + 1
   ; In-place increment/decrement operations
   ; V1.034.37: Unified format - j=0 global, j=1 local
   ElseIf obj\code = #ljINC_VAR Or obj\code = #ljDEC_VAR Or obj\code = #ljINC_VAR_PRE Or obj\code = #ljDEC_VAR_PRE Or obj\code = #ljINC_VAR_POST Or obj\code = #ljDEC_VAR_POST
      If obj\j = 1
         ; Local variable - i is paramOffset
         line + "[LOCAL[" + Str(obj\i) + "]]"
      Else
         ; Global variable - i is slot
         line + "[" + gVarMeta(obj\i)\name + "]"
      EndIf
      flag + 1
   ; V1.034.38: PFETCH display - pointer FETCH with j=1 for locals
   ElseIf obj\code = #ljPFETCH
      If obj\j = 1
         line + "[LOCAL[" + Str(obj\i) + "]] --> [sp] (ptr)"
      Else
         line + "[slot" + Str(obj\i) + "] --> [sp] (ptr)"
      EndIf
      flag + 1
   ; V1.034.38: PTRINC_POST_INT display - pointer post-increment with j=1 for locals
   ElseIf obj\code = #ljPTRINC_POST_INT Or obj\code = #ljPTRINC_POST_FLOAT Or obj\code = #ljPTRINC_POST_STRING Or obj\code = #ljPTRINC_POST_ARRAY Or obj\code = #ljPTRDEC_POST_INT Or obj\code = #ljPTRDEC_POST_FLOAT Or obj\code = #ljPTRDEC_POST_STRING Or obj\code = #ljPTRDEC_POST_ARRAY
      If obj\j = 1
         line + "[LOCAL[" + Str(obj\i) + "]] (ptr++/--)"
      Else
         line + "[slot" + Str(obj\i) + "] (ptr++/--)"
      EndIf
      flag + 1
   ; V1.034.38: PPOP display - pointer POP with j/i for target
   ElseIf obj\code = #ljPPOP
      If obj\j = 1
         line + "[sp] --> [LOCAL[" + Str(obj\i) + "]] (ppop)"
      Else
         line + "[sp] --> [slot" + Str(obj\i) + "] (ppop)"
      EndIf
      flag + 1
   ElseIf obj\code = #ljLINC_VAR Or obj\code = #ljLDEC_VAR Or obj\code = #ljLINC_VAR_PRE Or obj\code = #ljLDEC_VAR_PRE Or obj\code = #ljLINC_VAR_POST Or obj\code = #ljLDEC_VAR_POST
      CompilerIf show
         line + "[LOCAL[" + Str(obj\i) + "]]"
      CompilerElse
         ; V1.033.17: Show local variable name at compile-time
         _GetLocalName(obj\i)
         line + gAsmLocalName + "++"
      CompilerEndIf
      flag + 1
   ; In-place compound assignment operations
   ElseIf obj\code = #ljADD_ASSIGN_VAR Or obj\code = #ljSUB_ASSIGN_VAR Or obj\code = #ljMUL_ASSIGN_VAR Or obj\code = #ljDIV_ASSIGN_VAR Or obj\code = #ljMOD_ASSIGN_VAR Or obj\code = #ljFLOATADD_ASSIGN_VAR Or obj\code = #ljFLOATSUB_ASSIGN_VAR Or obj\code = #ljFLOATMUL_ASSIGN_VAR Or obj\code = #ljFLOATDIV_ASSIGN_VAR
      ; V1.023.31: Don't use sp-1 for value display - sp is runtime, not compile-time
      line + "[" + gVarMeta(obj\i)\name + " OP= sp]"
      flag + 1
   ElseIf obj\code = #ljPUSH Or obj\code = #ljFetch Or obj\code = #ljPUSHS Or obj\code = #ljPUSHF Or obj\code = #ljFETCHS Or obj\code = #ljFETCHF
      flag + 1
      ; V1.034.17: Handle unified opcodes - j=1 means local, obj\i is paramOffset
      If obj\j = 1
         ; Local variable - show as LOCAL[paramOffset]
         CompilerIf show
            line + "[LOCAL[" + Str(obj\i) + "]] --> [sp]"
         CompilerElse
            ; Compile-time: look up local variable name
            _GetLocalName(obj\i)
            line + gAsmLocalName + " --> [sp]"
         CompilerEndIf
      Else
         ; Global variable - standard display
         _ASMLineHelper1( 0, obj\i )
         If gVarMeta( obj\i )\flags & #C2FLAG_IDENT
            ; V1.023.21: Show slot number for IDENT to help debug
            line + "[" + gVarMeta( obj\i )\name + " (slot=" + Str(obj\i) + ")] --> [sp]"
         ElseIf gVarMeta( obj\i )\flags & #C2FLAG_STR
            line + "[" + gVarMeta( obj\i )\valueString + "] --> [sp]"
         ElseIf gVarMeta( obj\i )\flags & #C2FLAG_INT
            line + "[" + Str(gVarMeta( obj\i )\valueInt) +  "] --> [sp]"
         ElseIf gVarMeta( obj\i )\flags & #C2FLAG_FLOAT
            line + "[" + StrD(gVarMeta( obj\i )\valueFloat,3) +  "] --> [sp]"
         Else
            line + "[" + gVarMeta( obj\i )\name + "] --> [sp]"
         EndIf
      EndIf
   ElseIf obj\code = #ljPOP Or obj\code = #ljPOPS Or obj\code = #ljPOPF
      flag + 1
      _ASMLineHelper1( 0, obj\i )
      line + "[sp] --> [" + gVarMeta( obj\i )\name + "]"
   ElseIf obj\code = #ljNEGATE
      flag + 1
      line + "[sp] = -[sp]"
   ElseIf obj\code = #ljFLOATNEG
      flag + 1
      line + "[sp] = -[sp] (float)"
   ElseIf obj\code = #ljNOT
      flag + 1
      line + "[sp] = ![sp]"
   ; V1.033.16: Meaningful ASM output for arithmetic/comparison ops
   ElseIf obj\code = #ljADD
      line + "[sp-1] + [sp] --> [sp-1]"
   ElseIf obj\code = #ljSUBTRACT
      line + "[sp-1] - [sp] --> [sp-1]"
   ElseIf obj\code = #ljMULTIPLY
      line + "[sp-1] * [sp] --> [sp-1]"
   ElseIf obj\code = #ljDIVIDE
      line + "[sp-1] / [sp] --> [sp-1]"
   ElseIf obj\code = #ljMOD
      line + "[sp-1] % [sp] --> [sp-1]"
   ElseIf obj\code = #ljFLOATADD
      line + "[sp-1] +. [sp] --> [sp-1]"
   ElseIf obj\code = #ljFLOATSUB
      line + "[sp-1] -. [sp] --> [sp-1]"
   ElseIf obj\code = #ljFLOATMUL
      line + "[sp-1] *. [sp] --> [sp-1]"
   ElseIf obj\code = #ljFLOATDIV
      line + "[sp-1] /. [sp] --> [sp-1]"
   ElseIf obj\code = #ljSTRADD
      line + "[sp-1] + [sp] --> [sp-1] (str)"
   ElseIf obj\code = #ljEQUAL
      line + "[sp-1] == [sp] --> [sp-1]"
   ElseIf obj\code = #ljNotEqual
      line + "[sp-1] != [sp] --> [sp-1]"
   ElseIf obj\code = #ljLESS
      line + "[sp-1] < [sp] --> [sp-1]"
   ElseIf obj\code = #ljLESSEQUAL
      line + "[sp-1] <= [sp] --> [sp-1]"
   ElseIf obj\code = #ljGREATER
      line + "[sp-1] > [sp] --> [sp-1]"
   ElseIf obj\code = #ljGreaterEqual
      line + "[sp-1] >= [sp] --> [sp-1]"
   ElseIf obj\code = #ljFLOATEQ
      line + "[sp-1] ==. [sp] --> [sp-1]"
   ElseIf obj\code = #ljFLOATNE
      line + "[sp-1] !=. [sp] --> [sp-1]"
   ElseIf obj\code = #ljFLOATLE
      line + "[sp-1] <=. [sp] --> [sp-1]"
   ElseIf obj\code = #ljFLOATGE
      line + "[sp-1] >=. [sp] --> [sp-1]"
   ElseIf obj\code = #ljFLOATLESS
      line + "[sp-1] <. [sp] --> [sp-1]"
   ElseIf obj\code = #ljFLOATGR
      line + "[sp-1] >. [sp] --> [sp-1]"
   ElseIf obj\code = #ljSTREQ
      line + "[sp-1] == [sp] --> [sp-1] (str)"
   ElseIf obj\code = #ljSTRNE
      line + "[sp-1] != [sp] --> [sp-1] (str)"
   ElseIf obj\code = #ljAND
      line + "[sp-1] & [sp] --> [sp-1]"
   ElseIf obj\code = #ljOr
      line + "[sp-1] | [sp] --> [sp-1]"
   ElseIf obj\code = #ljXOR
      line + "[sp-1] ^ [sp] --> [sp-1]"
   ElseIf obj\code = #ljFTOI
      line + "[sp] = int([sp])"
   ElseIf obj\code = #ljITOF
      line + "[sp] = float([sp])"
   ElseIf obj\code = #ljFTOS
      line + "[sp] = str([sp]) (float)"
   ElseIf obj\code = #ljITOS
      line + "[sp] = str([sp]) (int)"
   ElseIf obj\code = #ljSTOF
      line + "[sp] = float([sp]) (str)"
   ElseIf obj\code = #ljSTOI
      line + "[sp] = int([sp]) (str)"
   ElseIf obj\code = #ljDUP Or obj\code = #ljDUP_I Or obj\code = #ljDUP_F Or obj\code = #ljDUP_S
      line + "[sp] = [sp-1] (dup)"
   ElseIf obj\code = #ljDROP
      line + "sp--"
   ElseIf obj\code = #ljPUSH_IMM
      line + "[" + Str(obj\i) + "] --> [sp] (imm)"
   ElseIf obj\code = #ljLLMOV Or obj\code = #ljLLMOVS Or obj\code = #ljLLMOVF
      CompilerIf show
         line + "[LOCAL[" + Str(obj\j) + "]] --> [LOCAL[" + Str(obj\i) + "]]"
      CompilerElse
         ; V1.033.17: Show local variable names for both src and dst
         _GetLocalName(obj\j)
         _asmSrcLocal = gAsmLocalName
         _GetLocalName(obj\i)
         line + _asmSrcLocal + " --> " + gAsmLocalName
      CompilerEndIf
   ElseIf obj\code = #ljLGMOV Or obj\code = #ljLGMOVS Or obj\code = #ljLGMOVF
      CompilerIf show
         line + "[LOCAL[" + Str(obj\j) + "]] --> [slot" + Str(obj\i) + "]"
      CompilerElse
         ; V1.033.17: Show local variable name for source
         _GetLocalName(obj\j)
         line + gAsmLocalName + " --> [" + gVarMeta(obj\i)\name + "]"
      CompilerEndIf
   ElseIf obj\code = #ljHALT
      line + "(end)"
   ElseIf obj\code = #ljreturn Or obj\code = #ljreturnF Or obj\code = #ljreturnS
      line + "(return)"
   EndIf
   CompilerIf Not show
      If flag
         _VarExpand( obj\i )
         line + " FLAGS ["+ temp +"]"
      EndIf
   CompilerEndIf
EndMacro

Macro                   vm_ListToArray( ll, ar )
   i = ListSize( ll() )
   ReDim ar( i )
   i = 0

   ForEach ll()
      ar( i )\code = ll()\code
      ar( i )\i = ll()\i
      ar( i )\j = ll()\j
      ar( i )\n = ll()\n
      ar( i )\ndx = ll()\ndx
      ar( i )\funcid = ll()\funcid  ; V1.18.0: Copy funcid for CALL instruction (for gFuncLocalArraySlots lookup)
      ar( i )\anchor = ll()\anchor  ; V1.020.070: Copy anchor for jump recalculation
      i + 1
   Next
EndMacro
Macro                   CPC()
   arCode(pc)\code
EndMacro
Macro                   _AR()
   arCode(pc)
EndMacro
; V1.035.0: POINTER ARRAY ARCHITECTURE - _LARRAY now just returns offset
Macro                   _LARRAY(offset)
   (offset)
EndMacro
; V1.035.0: _LVAR for local variable access
Macro                   _LVAR(offset)
   *gVar(gCurrentFuncSlot)\var(offset)
EndMacro
;- End of file

; V1.034.21: Inline opcode names - eliminates DataSection sync issues
; This macro REPLACES the DataSection reading loop
; Generated from enum - to add opcode, just add to Enumeration
Macro _INIT_OPCODE_NAMES
   ; Initialize opcode display names using enum constants directly
   ; Names stay perfectly in sync with enum - no manual sync required
   gszATR(#ljUNUSED)\s = "UNUSED"
   gszATR(#ljIDENT)\s = "IDENT"
   gszATR(#ljINT)\s = "INT"
   gszATR(#ljFLOAT)\s = "FLOAT"
   gszATR(#ljSTRING)\s = "STRING"
   gszATR(#ljVOID)\s = "VOID"
   gszATR(#ljStructType)\s = "STRUCTTYPE"
   gszATR(#ljTypeGuess)\s = "TYPEGUESS"
   gszATR(#ljArray)\s = "ARRAY"
   gszATR(#ljIF)\s = "IF"
   gszATR(#ljElse)\s = "ELSE"
   gszATR(#ljWHILE)\s = "WHILE"
   gszATR(#ljFOR)\s = "FOR"
   gszATR(#ljSWITCH)\s = "SWITCH"
   gszATR(#ljCASE)\s = "CASE"
   gszATR(#ljDEFAULT_CASE)\s = "DEFAULT_CASE"
   gszATR(#ljBREAK)\s = "BREAK"
   gszATR(#ljCONTINUE)\s = "CONTINUE"
   gszATR(#ljFOREACH)\s = "FOREACH"
   gszATR(#ljJZ)\s = "JZ"
   gszATR(#ljJMP)\s = "JMP"
   gszATR(#ljNEGATE)\s = "NEGATE"
   gszATR(#ljFLOATNEG)\s = "FLOATNEG"
   gszATR(#ljNOT)\s = "NOT"
   gszATR(#ljASSIGN)\s = "ASSIGN"
   gszATR(#ljADD_ASSIGN)\s = "ADD_ASSIGN"
   gszATR(#ljSUB_ASSIGN)\s = "SUB_ASSIGN"
   gszATR(#ljMUL_ASSIGN)\s = "MUL_ASSIGN"
   gszATR(#ljDIV_ASSIGN)\s = "DIV_ASSIGN"
   gszATR(#ljMOD_ASSIGN)\s = "MOD_ASSIGN"
   gszATR(#ljINC)\s = "INC"
   gszATR(#ljDEC)\s = "DEC"
   gszATR(#ljPRE_INC)\s = "PRE_INC"
   gszATR(#ljPRE_DEC)\s = "PRE_DEC"
   gszATR(#ljPOST_INC)\s = "POST_INC"
   gszATR(#ljPOST_DEC)\s = "POST_DEC"
   gszATR(#ljADD)\s = "ADD"
   gszATR(#ljSUBTRACT)\s = "SUBTRACT"
   gszATR(#ljMULTIPLY)\s = "MULTIPLY"
   gszATR(#ljDIVIDE)\s = "DIVIDE"
   gszATR(#ljFLOATADD)\s = "FLOATADD"
   gszATR(#ljFLOATSUB)\s = "FLOATSUB"
   gszATR(#ljFLOATMUL)\s = "FLOATMUL"
   gszATR(#ljFLOATDIV)\s = "FLOATDIV"
   gszATR(#ljSTRADD)\s = "STRADD"
   ; V1.034.26: Float/string token mappings for type coercion
   gszATR(#ljNEGATE)\flttoken = #ljFLOATNEG
   gszATR(#ljADD)\flttoken = #ljFLOATADD
   gszATR(#ljADD)\strtoken = #ljSTRADD
   gszATR(#ljSUBTRACT)\flttoken = #ljFLOATSUB
   gszATR(#ljMULTIPLY)\flttoken = #ljFLOATMUL
   gszATR(#ljDIVIDE)\flttoken = #ljFLOATDIV
   gszATR(#ljEQUAL)\flttoken = #ljFLOATEQ
   gszATR(#ljNotEqual)\flttoken = #ljFLOATNE
   gszATR(#ljLESSEQUAL)\flttoken = #ljFLOATLE
   gszATR(#ljGreaterEqual)\flttoken = #ljFLOATGE
   gszATR(#ljGREATER)\flttoken = #ljFLOATGR
   gszATR(#ljLESS)\flttoken = #ljFLOATLESS
   gszATR(#ljFTOS)\s = "FTOS"
   gszATR(#ljITOS)\s = "ITOS"
   gszATR(#ljITOF)\s = "ITOF"
   gszATR(#ljFTOI)\s = "FTOI"
   gszATR(#ljSTOF)\s = "STOF"
   gszATR(#ljSTOI)\s = "STOI"
   gszATR(#ljOr)\s = "OR"
   gszATR(#ljAND)\s = "AND"
   gszATR(#ljXOR)\s = "XOR"
   gszATR(#ljMOD)\s = "MOD"
   gszATR(#ljSHL)\s = "SHL"
   gszATR(#ljSHR)\s = "SHR"
   gszATR(#ljEQUAL)\s = "EQUAL"
   gszATR(#ljNotEqual)\s = "NOTEQUAL"
   gszATR(#ljLESSEQUAL)\s = "LESSEQUAL"
   gszATR(#ljGreaterEqual)\s = "GREATEREQUAL"
   gszATR(#ljGREATER)\s = "GREATER"
   gszATR(#ljLESS)\s = "LESS"
   gszATR(#ljFLOATEQ)\s = "FLOATEQ"
   gszATR(#ljFLOATNE)\s = "FLOATNE"
   gszATR(#ljFLOATLE)\s = "FLOATLE"
   gszATR(#ljFLOATGE)\s = "FLOATGE"
   gszATR(#ljFLOATGR)\s = "FLOATGR"
   gszATR(#ljFLOATLESS)\s = "FLOATLESS"
   gszATR(#ljSTREQ)\s = "STREQ"
   gszATR(#ljSTRNE)\s = "STRNE"
   gszATR(#ljMOV)\s = "MOV"
   gszATR(#ljFetch)\s = "FETCH"
   gszATR(#ljPOP)\s = "POP"
   gszATR(#ljPOPS)\s = "POPS"
   gszATR(#ljPOPF)\s = "POPF"
   gszATR(#ljPush)\s = "PUSH"
   gszATR(#ljPUSHS)\s = "PUSHS"
   gszATR(#ljPUSHF)\s = "PUSHF"
   gszATR(#ljPUSH_IMM)\s = "PUSH_IMM"
   gszATR(#ljStore)\s = "STORE"
   gszATR(#ljHALT)\s = "HALT"
   gszATR(#ljPrint)\s = "PRINT"
   gszATR(#ljPRTC)\s = "PRTC"
   gszATR(#ljPRTI)\s = "PRTI"
   gszATR(#ljPRTF)\s = "PRTF"
   gszATR(#ljPRTS)\s = "PRTS"
   gszATR(#ljLeftBrace)\s = "LEFTBRACE"
   gszATR(#ljRightBrace)\s = "RIGHTBRACE"
   gszATR(#ljLeftParent)\s = "LEFTPARENT"
   gszATR(#ljRightParent)\s = "RIGHTPARENT"
   gszATR(#ljLeftBracket)\s = "LEFTBRACKET"
   gszATR(#ljRightBracket)\s = "RIGHTBRACKET"
   gszATR(#ljSemi)\s = "SEMI"
   gszATR(#ljComma)\s = "COMMA"
   gszATR(#ljBackslash)\s = "BACKSLASH"
   gszATR(#ljfunction)\s = "FUNCTION"
   gszATR(#ljreturn)\s = "RETURN"
   gszATR(#ljreturnF)\s = "RETURNF"
   gszATR(#ljreturnS)\s = "RETURNS"
   gszATR(#ljCall)\s = "CALL"
   gszATR(#ljCALL0)\s = "CALL0"
   gszATR(#ljCALL1)\s = "CALL1"
   gszATR(#ljCALL2)\s = "CALL2"
   gszATR(#ljCALL_REC)\s = "CALL_REC"
   gszATR(#ljRETURN_REC)\s = "RETURN_REC"
   gszATR(#ljARRAYINFO)\s = "ARRAYINFO"
   gszATR(#ljUNKNOWN)\s = "UNKNOWN"
   gszATR(#ljNOOP)\s = "NOOP"
   gszATR(#ljOP)\s = "OP"
   gszATR(#ljSEQ)\s = "SEQ"
   gszATR(#ljKeyword)\s = "KEYWORD"
   gszATR(#ljTERNARY)\s = "TERNARY"
   gszATR(#ljQUESTION)\s = "QUESTION"
   gszATR(#ljCOLON)\s = "COLON"
   gszATR(#ljTENIF)\s = "TENIF"
   gszATR(#ljTENELSE)\s = "TENELSE"
   gszATR(#ljNOOPIF)\s = "NOOPIF"
   gszATR(#ljDUP)\s = "DUP"
   gszATR(#ljDUP_I)\s = "DUP_I"
   gszATR(#ljDUP_F)\s = "DUP_F"
   gszATR(#ljDUP_S)\s = "DUP_S"
   gszATR(#ljJNZ)\s = "JNZ"
   gszATR(#ljDROP)\s = "DROP"
   ; V1.035.16: Fused comparison-jump opcodes
   gszATR(#ljJGE_VAR_IMM)\s = "JGE_VAR_IMM"
   gszATR(#ljJGT_VAR_IMM)\s = "JGT_VAR_IMM"
   gszATR(#ljJLE_VAR_IMM)\s = "JLE_VAR_IMM"
   gszATR(#ljJLT_VAR_IMM)\s = "JLT_VAR_IMM"
   gszATR(#ljJEQ_VAR_IMM)\s = "JEQ_VAR_IMM"
   gszATR(#ljJNE_VAR_IMM)\s = "JNE_VAR_IMM"
   gszATR(#ljJGE_LVAR_IMM)\s = "JGE_LVAR_IMM"
   gszATR(#ljJGT_LVAR_IMM)\s = "JGT_LVAR_IMM"
   gszATR(#ljJLE_LVAR_IMM)\s = "JLE_LVAR_IMM"
   gszATR(#ljJLT_LVAR_IMM)\s = "JLT_LVAR_IMM"
   gszATR(#ljJEQ_LVAR_IMM)\s = "JEQ_LVAR_IMM"
   gszATR(#ljJNE_LVAR_IMM)\s = "JNE_LVAR_IMM"
   gszATR(#ljMOVS)\s = "MOVS"
   gszATR(#ljMOVF)\s = "MOVF"
   gszATR(#ljFETCHS)\s = "FETCHS"
   gszATR(#ljFETCHF)\s = "FETCHF"
   gszATR(#ljSTORES)\s = "STORES"
   gszATR(#ljSTOREF)\s = "STOREF"
   gszATR(#ljLMOV)\s = "LMOV"
   gszATR(#ljLMOVS)\s = "LMOVS"
   gszATR(#ljLMOVF)\s = "LMOVF"
   gszATR(#ljLFETCH)\s = "LFETCH"
   gszATR(#ljLFETCHS)\s = "LFETCHS"
   gszATR(#ljLFETCHF)\s = "LFETCHF"
   gszATR(#ljLSTORE)\s = "LSTORE"
   gszATR(#ljLSTORES)\s = "LSTORES"
   gszATR(#ljLSTOREF)\s = "LSTOREF"
   gszATR(#ljLGMOV)\s = "LGMOV"
   gszATR(#ljLGMOVS)\s = "LGMOVS"
   gszATR(#ljLGMOVF)\s = "LGMOVF"
   gszATR(#ljLLMOV)\s = "LLMOV"
   gszATR(#ljLLMOVS)\s = "LLMOVS"
   gszATR(#ljLLMOVF)\s = "LLMOVF"
   gszATR(#ljLLPMOV)\s = "LLPMOV"
   gszATR(#ljINC_VAR)\s = "INC_VAR"
   gszATR(#ljDEC_VAR)\s = "DEC_VAR"
   gszATR(#ljINC_VAR_PRE)\s = "INC_VAR_PRE"
   gszATR(#ljDEC_VAR_PRE)\s = "DEC_VAR_PRE"
   gszATR(#ljINC_VAR_POST)\s = "INC_VAR_POST"
   gszATR(#ljDEC_VAR_POST)\s = "DEC_VAR_POST"
   gszATR(#ljLINC_VAR)\s = "LINC_VAR"
   gszATR(#ljLDEC_VAR)\s = "LDEC_VAR"
   gszATR(#ljLINC_VAR_PRE)\s = "LINC_VAR_PRE"
   gszATR(#ljLDEC_VAR_PRE)\s = "LDEC_VAR_PRE"
   gszATR(#ljLINC_VAR_POST)\s = "LINC_VAR_POST"
   gszATR(#ljLDEC_VAR_POST)\s = "LDEC_VAR_POST"
   gszATR(#ljPTRINC)\s = "PTRINC"
   gszATR(#ljPTRDEC)\s = "PTRDEC"
   gszATR(#ljPTRINC_PRE)\s = "PTRINC_PRE"
   gszATR(#ljPTRDEC_PRE)\s = "PTRDEC_PRE"
   gszATR(#ljPTRINC_POST)\s = "PTRINC_POST"
   gszATR(#ljPTRDEC_POST)\s = "PTRDEC_POST"
   gszATR(#ljSTORE_STRUCT)\s = "STORE_STRUCT"
   gszATR(#ljLSTORE_STRUCT)\s = "LSTORE_STRUCT"
   gszATR(#ljADD_ASSIGN_VAR)\s = "ADD_ASSIGN_VAR"
   gszATR(#ljSUB_ASSIGN_VAR)\s = "SUB_ASSIGN_VAR"
   gszATR(#ljMUL_ASSIGN_VAR)\s = "MUL_ASSIGN_VAR"
   gszATR(#ljDIV_ASSIGN_VAR)\s = "DIV_ASSIGN_VAR"
   gszATR(#ljMOD_ASSIGN_VAR)\s = "MOD_ASSIGN_VAR"
   ; V1.037.3: FA/FS/FM/FD = FloatAdd/Sub/Mul/Div
   gszATR(#ljFLOATADD_ASSIGN_VAR)\s = "FA_ASGN_V"
   gszATR(#ljFLOATSUB_ASSIGN_VAR)\s = "FS_ASGN_V"
   gszATR(#ljFLOATMUL_ASSIGN_VAR)\s = "FM_ASGN_V"
   gszATR(#ljFLOATDIV_ASSIGN_VAR)\s = "FD_ASGN_V"
   gszATR(#ljPTRADD_ASSIGN)\s = "PTRADD_ASSIGN"
   gszATR(#ljPTRSUB_ASSIGN)\s = "PTRSUB_ASSIGN"
   ; BI = Builtin
   gszATR(#ljBUILTIN_RANDOM)\s = "BI_RANDOM"
   gszATR(#ljBUILTIN_ABS)\s = "BI_ABS"
   gszATR(#ljBUILTIN_MIN)\s = "BI_MIN"
   gszATR(#ljBUILTIN_MAX)\s = "BI_MAX"
   gszATR(#ljBUILTIN_ASSERT_EQUAL)\s = "BI_ASEQ"
   gszATR(#ljBUILTIN_ASSERT_FLOAT)\s = "BI_ASFLT"
   gszATR(#ljBUILTIN_ASSERT_STRING)\s = "BI_ASSTR"
   gszATR(#ljBUILTIN_SQRT)\s = "BI_SQRT"
   gszATR(#ljBUILTIN_POW)\s = "BI_POW"
   gszATR(#ljBUILTIN_LEN)\s = "BI_LEN"
   gszATR(#ljBUILTIN_STRCMP)\s = "BI_STRCMP"
   gszATR(#ljBUILTIN_GETC)\s = "BI_GETC"
   gszATR(#ljBUILTIN_PRINTF)\s = "BI_PRINTF"
   gszATR(#ljARRAYINDEX)\s = "ARRAYINDEX"
   gszATR(#ljARRAYFETCH)\s = "ARRAYFETCH"
   gszATR(#ljARRAYFETCH_INT)\s = "ARRAYFETCH_INT"
   gszATR(#ljARRAYFETCH_FLOAT)\s = "ARRAYFETCH_FLOAT"
   gszATR(#ljARRAYFETCH_STR)\s = "ARRAYFETCH_STR"
   gszATR(#ljARRAYSTORE)\s = "ARRAYSTORE"
   gszATR(#ljARRAYSTORE_INT)\s = "ARRAYSTORE_INT"
   gszATR(#ljARRAYSTORE_FLOAT)\s = "ARRAYSTORE_FLOAT"
   gszATR(#ljARRAYSTORE_STR)\s = "ARRAYSTORE_STR"
   ; V1.037.3: Normalized ASM names - AF=ArrayFetch, AS=ArrayStore, I/F/S=Int/Float/Str
   ; G/L=Global/Local, O=Opt(gslot), LO=LOpt(lslot), ST=Stack
   gszATR(#ljARRAYFETCH_INT_GLOBAL_OPT)\s = "AF_I_G_O"
   gszATR(#ljARRAYFETCH_INT_GLOBAL_STACK)\s = "AF_I_G_ST"
   gszATR(#ljARRAYFETCH_INT_LOCAL_OPT)\s = "AF_I_L_O"
   gszATR(#ljARRAYFETCH_INT_LOCAL_STACK)\s = "AF_I_L_ST"
   gszATR(#ljARRAYFETCH_FLOAT_GLOBAL_OPT)\s = "AF_F_G_O"
   gszATR(#ljARRAYFETCH_FLOAT_GLOBAL_STACK)\s = "AF_F_G_ST"
   gszATR(#ljARRAYFETCH_FLOAT_LOCAL_OPT)\s = "AF_F_L_O"
   gszATR(#ljARRAYFETCH_FLOAT_LOCAL_STACK)\s = "AF_F_L_ST"
   gszATR(#ljARRAYFETCH_STR_GLOBAL_OPT)\s = "AF_S_G_O"
   gszATR(#ljARRAYFETCH_STR_GLOBAL_STACK)\s = "AF_S_G_ST"
   gszATR(#ljARRAYFETCH_STR_LOCAL_OPT)\s = "AF_S_L_O"
   gszATR(#ljARRAYFETCH_STR_LOCAL_STACK)\s = "AF_S_L_ST"
   gszATR(#ljARRAYSTORE_INT_GLOBAL_OPT_OPT)\s = "AS_I_G_O_O"
   gszATR(#ljARRAYSTORE_INT_GLOBAL_OPT_STACK)\s = "AS_I_G_O_ST"
   gszATR(#ljARRAYSTORE_INT_GLOBAL_STACK_OPT)\s = "AS_I_G_ST_O"
   gszATR(#ljARRAYSTORE_INT_GLOBAL_STACK_STACK)\s = "AS_I_G_ST_ST"
   gszATR(#ljARRAYSTORE_INT_LOCAL_OPT_OPT)\s = "AS_I_L_O_O"
   gszATR(#ljARRAYSTORE_INT_LOCAL_OPT_STACK)\s = "AS_I_L_O_ST"
   gszATR(#ljARRAYSTORE_INT_LOCAL_STACK_OPT)\s = "AS_I_L_ST_O"
   gszATR(#ljARRAYSTORE_INT_LOCAL_STACK_STACK)\s = "AS_I_L_ST_ST"
   gszATR(#ljARRAYSTORE_FLOAT_GLOBAL_OPT_OPT)\s = "AS_F_G_O_O"
   gszATR(#ljARRAYSTORE_FLOAT_GLOBAL_OPT_STACK)\s = "AS_F_G_O_ST"
   gszATR(#ljARRAYSTORE_FLOAT_GLOBAL_STACK_OPT)\s = "AS_F_G_ST_O"
   gszATR(#ljARRAYSTORE_FLOAT_GLOBAL_STACK_STACK)\s = "AS_F_G_ST_ST"
   gszATR(#ljARRAYSTORE_FLOAT_LOCAL_OPT_OPT)\s = "AS_F_L_O_O"
   gszATR(#ljARRAYSTORE_FLOAT_LOCAL_OPT_STACK)\s = "AS_F_L_O_ST"
   gszATR(#ljARRAYSTORE_FLOAT_LOCAL_STACK_OPT)\s = "AS_F_L_ST_O"
   gszATR(#ljARRAYSTORE_FLOAT_LOCAL_STACK_STACK)\s = "AS_F_L_ST_ST"
   gszATR(#ljARRAYSTORE_STR_GLOBAL_OPT_OPT)\s = "AS_S_G_O_O"
   gszATR(#ljARRAYSTORE_STR_GLOBAL_OPT_STACK)\s = "AS_S_G_O_ST"
   gszATR(#ljARRAYSTORE_STR_GLOBAL_STACK_OPT)\s = "AS_S_G_ST_O"
   gszATR(#ljARRAYSTORE_STR_GLOBAL_STACK_STACK)\s = "AS_S_G_ST_ST"
   gszATR(#ljARRAYSTORE_STR_LOCAL_OPT_OPT)\s = "AS_S_L_O_O"
   gszATR(#ljARRAYSTORE_STR_LOCAL_OPT_STACK)\s = "AS_S_L_O_ST"
   gszATR(#ljARRAYSTORE_STR_LOCAL_STACK_OPT)\s = "AS_S_L_ST_O"
   gszATR(#ljARRAYSTORE_STR_LOCAL_STACK_STACK)\s = "AS_S_L_ST_ST"
   gszATR(#ljARRAYSTORE_INT_GLOBAL_OPT_LOPT)\s = "AS_I_G_O_LO"
   gszATR(#ljARRAYSTORE_FLOAT_GLOBAL_OPT_LOPT)\s = "AS_F_G_O_LO"
   gszATR(#ljARRAYSTORE_STR_GLOBAL_OPT_LOPT)\s = "AS_S_G_O_LO"
   gszATR(#ljARRAYSTORE_INT_LOCAL_OPT_LOPT)\s = "AS_I_L_O_LO"
   gszATR(#ljARRAYSTORE_FLOAT_LOCAL_OPT_LOPT)\s = "AS_F_L_O_LO"
   gszATR(#ljARRAYSTORE_STR_LOCAL_OPT_LOPT)\s = "AS_S_L_O_LO"
   gszATR(#ljARRAYFETCH_INT_GLOBAL_LOPT)\s = "AF_I_G_LO"
   gszATR(#ljARRAYFETCH_FLOAT_GLOBAL_LOPT)\s = "AF_F_G_LO"
   gszATR(#ljARRAYFETCH_STR_GLOBAL_LOPT)\s = "AF_S_G_LO"
   gszATR(#ljARRAYSTORE_INT_GLOBAL_LOPT_LOPT)\s = "AS_I_G_LO_LO"
   gszATR(#ljARRAYSTORE_INT_GLOBAL_LOPT_OPT)\s = "AS_I_G_LO_O"
   gszATR(#ljARRAYSTORE_INT_GLOBAL_LOPT_STACK)\s = "AS_I_G_LO_ST"
   gszATR(#ljARRAYSTORE_FLOAT_GLOBAL_LOPT_LOPT)\s = "AS_F_G_LO_LO"
   gszATR(#ljARRAYSTORE_FLOAT_GLOBAL_LOPT_OPT)\s = "AS_F_G_LO_O"
   gszATR(#ljARRAYSTORE_FLOAT_GLOBAL_LOPT_STACK)\s = "AS_F_G_LO_ST"
   gszATR(#ljARRAYSTORE_STR_GLOBAL_LOPT_LOPT)\s = "AS_S_G_LO_LO"
   gszATR(#ljARRAYSTORE_STR_GLOBAL_LOPT_OPT)\s = "AS_S_G_LO_O"
   gszATR(#ljARRAYSTORE_STR_GLOBAL_LOPT_STACK)\s = "AS_S_G_LO_ST"
   gszATR(#ljARRAYFETCH_INT_LOCAL_LOPT)\s = "AF_I_L_LO"
   gszATR(#ljARRAYFETCH_FLOAT_LOCAL_LOPT)\s = "AF_F_L_LO"
   gszATR(#ljARRAYFETCH_STR_LOCAL_LOPT)\s = "AF_S_L_LO"
   gszATR(#ljARRAYSTORE_INT_LOCAL_LOPT_LOPT)\s = "AS_I_L_LO_LO"
   gszATR(#ljARRAYSTORE_INT_LOCAL_LOPT_OPT)\s = "AS_I_L_LO_O"
   gszATR(#ljARRAYSTORE_INT_LOCAL_LOPT_STACK)\s = "AS_I_L_LO_ST"
   gszATR(#ljARRAYSTORE_FLOAT_LOCAL_LOPT_LOPT)\s = "AS_F_L_LO_LO"
   gszATR(#ljARRAYSTORE_FLOAT_LOCAL_LOPT_OPT)\s = "AS_F_L_LO_O"
   gszATR(#ljARRAYSTORE_FLOAT_LOCAL_LOPT_STACK)\s = "AS_F_L_LO_ST"
   gszATR(#ljARRAYSTORE_STR_LOCAL_LOPT_LOPT)\s = "AS_S_L_LO_LO"
   gszATR(#ljARRAYSTORE_STR_LOCAL_LOPT_OPT)\s = "AS_S_L_LO_O"
   gszATR(#ljARRAYSTORE_STR_LOCAL_LOPT_STACK)\s = "AS_S_L_LO_ST"
   gszATR(#ljGETADDR)\s = "GETADDR"
   gszATR(#ljGETADDRF)\s = "GETADDRF"
   gszATR(#ljGETADDRS)\s = "GETADDRS"
   gszATR(#ljGETLOCALADDR)\s = "GETLOCALADDR"
   gszATR(#ljGETLOCALADDRF)\s = "GETLOCALADDRF"
   gszATR(#ljGETLOCALADDRS)\s = "GETLOCALADDRS"
   gszATR(#ljPTRFETCH)\s = "PTRFETCH"
   gszATR(#ljPTRFETCH_INT)\s = "PTRFETCH_INT"
   gszATR(#ljPTRFETCH_FLOAT)\s = "PTRFETCH_FLOAT"
   gszATR(#ljPTRFETCH_STR)\s = "PTRFETCH_STR"
   gszATR(#ljPTRSTORE)\s = "PTRSTORE"
   gszATR(#ljPTRSTORE_INT)\s = "PTRSTORE_INT"
   gszATR(#ljPTRSTORE_FLOAT)\s = "PTRSTORE_FLOAT"
   gszATR(#ljPTRSTORE_STR)\s = "PTRSTORE_STR"
   gszATR(#ljPTRFIELD_I)\s = "PTRFIELD_I"
   gszATR(#ljPTRFIELD_F)\s = "PTRFIELD_F"
   gszATR(#ljPTRFIELD_S)\s = "PTRFIELD_S"
   gszATR(#ljPTRADD)\s = "PTRADD"
   gszATR(#ljPTRSUB)\s = "PTRSUB"
   gszATR(#ljGETFUNCADDR)\s = "GETFUNCADDR"
   gszATR(#ljCALLFUNCPTR)\s = "CALLFUNCPTR"
   ; GA = GetArrayAddr, GLA = GetLocalArrayAddr
   gszATR(#ljGETARRAYADDR)\s = "GA_I"
   gszATR(#ljGETARRAYADDRF)\s = "GA_F"
   gszATR(#ljGETARRAYADDRS)\s = "GA_S"
   gszATR(#ljGETLOCALARRAYADDR)\s = "GLA_I"
   gszATR(#ljGETLOCALARRAYADDRF)\s = "GLA_F"
   gszATR(#ljGETLOCALARRAYADDRS)\s = "GLA_S"
   gszATR(#ljPRTPTR)\s = "PRTPTR"
   gszATR(#ljPMOV)\s = "PMOV"
   gszATR(#ljPFETCH)\s = "PFETCH"
   gszATR(#ljPSTORE)\s = "PSTORE"
   gszATR(#ljPPOP)\s = "PPOP"
   gszATR(#ljPLFETCH)\s = "PLFETCH"
   gszATR(#ljPLSTORE)\s = "PLSTORE"
   gszATR(#ljPLMOV)\s = "PLMOV"
   gszATR(#ljCAST_INT)\s = "CAST_INT"
   gszATR(#ljCAST_FLOAT)\s = "CAST_FLOAT"
   gszATR(#ljCAST_STRING)\s = "CAST_STRING"
   gszATR(#ljCAST_VOID)\s = "CAST_VOID"
   gszATR(#ljCAST_PTR)\s = "CAST_PTR"
   gszATR(#ljStruct)\s = "STRUCT"
   gszATR(#ljStructField)\s = "STRUCTFIELD"
   gszATR(#ljStructInit)\s = "STRUCTINIT"
   ; SA=StructArray, AOS=ArrayOfStruct, PSF=PtrStructFetch, PSS=PtrStructStore
   gszATR(#ljSTRUCTARRAY_FETCH_INT)\s = "SA_F_I"
   gszATR(#ljSTRUCTARRAY_FETCH_FLOAT)\s = "SA_F_F"
   gszATR(#ljSTRUCTARRAY_FETCH_STR)\s = "SA_F_S"
   gszATR(#ljSTRUCTARRAY_STORE_INT)\s = "SA_S_I"
   gszATR(#ljSTRUCTARRAY_STORE_FLOAT)\s = "SA_S_F"
   gszATR(#ljSTRUCTARRAY_STORE_STR)\s = "SA_S_S"
   gszATR(#ljARRAYOFSTRUCT_FETCH_INT)\s = "AOS_F_I"
   gszATR(#ljARRAYOFSTRUCT_FETCH_FLOAT)\s = "AOS_F_F"
   gszATR(#ljARRAYOFSTRUCT_FETCH_STR)\s = "AOS_F_S"
   gszATR(#ljARRAYOFSTRUCT_STORE_INT)\s = "AOS_S_I"
   gszATR(#ljARRAYOFSTRUCT_STORE_FLOAT)\s = "AOS_S_F"
   gszATR(#ljARRAYOFSTRUCT_STORE_STR)\s = "AOS_S_S"
   gszATR(#ljARRAYOFSTRUCT_FETCH_INT_LOPT)\s = "AOS_F_I_LO"
   gszATR(#ljARRAYOFSTRUCT_FETCH_FLOAT_LOPT)\s = "AOS_F_F_LO"
   gszATR(#ljARRAYOFSTRUCT_FETCH_STR_LOPT)\s = "AOS_F_S_LO"
   gszATR(#ljARRAYOFSTRUCT_STORE_INT_LOPT)\s = "AOS_S_I_LO"
   gszATR(#ljARRAYOFSTRUCT_STORE_FLOAT_LOPT)\s = "AOS_S_F_LO"
   gszATR(#ljARRAYOFSTRUCT_STORE_STR_LOPT)\s = "AOS_S_S_LO"
   gszATR(#ljGETSTRUCTADDR)\s = "GETSTRUCTADDR"
   gszATR(#ljPTRSTRUCTFETCH_INT)\s = "PSF_I"
   gszATR(#ljPTRSTRUCTFETCH_FLOAT)\s = "PSF_F"
   gszATR(#ljPTRSTRUCTFETCH_STR)\s = "PSF_S"
   gszATR(#ljPTRSTRUCTSTORE_INT)\s = "PSS_I"
   gszATR(#ljPTRSTRUCTSTORE_FLOAT)\s = "PSS_F"
   gszATR(#ljPTRSTRUCTSTORE_STR)\s = "PSS_S"
   gszATR(#ljPTRSTRUCTSTORE_INT_LOPT)\s = "PSS_I_LO"
   gszATR(#ljPTRSTRUCTSTORE_FLOAT_LOPT)\s = "PSS_F_LO"
   gszATR(#ljPTRSTRUCTSTORE_STR_LOPT)\s = "PSS_S_LO"
   gszATR(#ljPTRSTRUCTFETCH_INT_LPTR)\s = "PSF_I_LP"
   gszATR(#ljPTRSTRUCTFETCH_FLOAT_LPTR)\s = "PSF_F_LP"
   gszATR(#ljPTRSTRUCTFETCH_STR_LPTR)\s = "PSF_S_LP"
   gszATR(#ljPTRSTRUCTSTORE_INT_LPTR)\s = "PSS_I_LP"
   gszATR(#ljPTRSTRUCTSTORE_FLOAT_LPTR)\s = "PSS_F_LP"
   gszATR(#ljPTRSTRUCTSTORE_STR_LPTR)\s = "PSS_S_LP"
   gszATR(#ljPTRSTRUCTSTORE_INT_LPTR_LOPT)\s = "PSS_I_LP_LO"
   gszATR(#ljPTRSTRUCTSTORE_FLOAT_LPTR_LOPT)\s = "PSS_F_LP_LO"
   gszATR(#ljPTRSTRUCTSTORE_STR_LPTR_LOPT)\s = "PSS_S_LP_LO"
   gszATR(#ljARRAYRESIZE)\s = "ARRAYRESIZE"
   gszATR(#ljSTRUCTCOPY)\s = "STRUCTCOPY"
   gszATR(#ljSTRUCT_ALLOC)\s = "ST_ALLOC"
   gszATR(#ljSTRUCT_ALLOC_LOCAL)\s = "ST_ALLOC_L"
   gszATR(#ljSTRUCT_FREE)\s = "ST_FREE"
   ; SF=StructFetch, SS=StructStore
   gszATR(#ljSTRUCT_FETCH_INT)\s = "SF_I"
   gszATR(#ljSTRUCT_FETCH_FLOAT)\s = "SF_F"
   gszATR(#ljSTRUCT_FETCH_INT_LOCAL)\s = "SF_I_L"
   gszATR(#ljSTRUCT_FETCH_FLOAT_LOCAL)\s = "SF_F_L"
   gszATR(#ljSTRUCT_STORE_INT)\s = "SS_I"
   gszATR(#ljSTRUCT_STORE_FLOAT)\s = "SS_F"
   gszATR(#ljSTRUCT_STORE_INT_LOCAL)\s = "SS_I_L"
   gszATR(#ljSTRUCT_STORE_FLOAT_LOCAL)\s = "SS_F_L"
   gszATR(#ljSTRUCT_FETCH_STR)\s = "SF_S"
   gszATR(#ljSTRUCT_FETCH_STR_LOCAL)\s = "SF_S_L"
   gszATR(#ljSTRUCT_STORE_STR)\s = "SS_S"
   gszATR(#ljSTRUCT_STORE_STR_LOCAL)\s = "SS_S_L"
   gszATR(#ljSTRUCT_COPY_PTR)\s = "STRUCT_COPY_PTR"
   gszATR(#ljFETCH_STRUCT)\s = "FETCH_STRUCT"
   gszATR(#ljLFETCH_STRUCT)\s = "LFETCH_STRUCT"
   gszATR(#ljList)\s = "LIST"
   gszATR(#ljLIST_NEW)\s = "LIST_NEW"
   gszATR(#ljLIST_ADD)\s = "LIST_ADD"
   gszATR(#ljLIST_INSERT)\s = "LIST_INSERT"
   gszATR(#ljLIST_DELETE)\s = "LIST_DELETE"
   gszATR(#ljLIST_CLEAR)\s = "LIST_CLEAR"
   gszATR(#ljLIST_SIZE)\s = "LIST_SIZE"
   gszATR(#ljLIST_FIRST)\s = "LIST_FIRST"
   gszATR(#ljLIST_LAST)\s = "LIST_LAST"
   gszATR(#ljLIST_NEXT)\s = "LIST_NEXT"
   gszATR(#ljLIST_PREV)\s = "LIST_PREV"
   gszATR(#ljLIST_SELECT)\s = "LIST_SELECT"
   gszATR(#ljLIST_INDEX)\s = "LIST_INDEX"
   gszATR(#ljLIST_GET)\s = "LIST_GET"
   gszATR(#ljLIST_SET)\s = "LIST_SET"
   gszATR(#ljLIST_RESET)\s = "LIST_RESET"
   gszATR(#ljLIST_SORT)\s = "LIST_SORT"
   ; L_ = List_, M_ = Map_
   gszATR(#ljLIST_ADD_INT)\s = "L_ADD_I"
   gszATR(#ljLIST_ADD_FLOAT)\s = "L_ADD_F"
   gszATR(#ljLIST_ADD_STR)\s = "L_ADD_S"
   gszATR(#ljLIST_INSERT_INT)\s = "L_INS_I"
   gszATR(#ljLIST_INSERT_FLOAT)\s = "L_INS_F"
   gszATR(#ljLIST_INSERT_STR)\s = "L_INS_S"
   gszATR(#ljLIST_GET_INT)\s = "L_GET_I"
   gszATR(#ljLIST_GET_FLOAT)\s = "L_GET_F"
   gszATR(#ljLIST_GET_STR)\s = "L_GET_S"
   gszATR(#ljLIST_SET_INT)\s = "L_SET_I"
   gszATR(#ljLIST_SET_FLOAT)\s = "L_SET_F"
   gszATR(#ljLIST_SET_STR)\s = "L_SET_S"
   gszATR(#ljLIST_ADD_STRUCT)\s = "L_ADD_ST"
   gszATR(#ljLIST_GET_STRUCT)\s = "L_GET_ST"
   gszATR(#ljLIST_SET_STRUCT)\s = "L_SET_ST"
   gszATR(#ljMap)\s = "MAP"
   gszATR(#ljMAP_NEW)\s = "MAP_NEW"
   gszATR(#ljMAP_PUT)\s = "MAP_PUT"
   gszATR(#ljMAP_GET)\s = "MAP_GET"
   gszATR(#ljMAP_DELETE)\s = "MAP_DELETE"
   gszATR(#ljMAP_CLEAR)\s = "MAP_CLEAR"
   gszATR(#ljMAP_SIZE)\s = "MAP_SIZE"
   gszATR(#ljMAP_CONTAINS)\s = "MAP_CONTAINS"
   gszATR(#ljMAP_RESET)\s = "MAP_RESET"
   gszATR(#ljMAP_NEXT)\s = "MAP_NEXT"
   gszATR(#ljMAP_KEY)\s = "MAP_KEY"
   gszATR(#ljMAP_VALUE)\s = "MAP_VALUE"
   gszATR(#ljMAP_PUT_INT)\s = "M_PUT_I"
   gszATR(#ljMAP_PUT_FLOAT)\s = "M_PUT_F"
   gszATR(#ljMAP_PUT_STR)\s = "M_PUT_S"
   gszATR(#ljMAP_GET_INT)\s = "M_GET_I"
   gszATR(#ljMAP_GET_FLOAT)\s = "M_GET_F"
   gszATR(#ljMAP_GET_STR)\s = "M_GET_S"
   gszATR(#ljMAP_VALUE_INT)\s = "M_VAL_I"
   gszATR(#ljMAP_VALUE_FLOAT)\s = "M_VAL_F"
   gszATR(#ljMAP_VALUE_STR)\s = "M_VAL_S"
   gszATR(#ljMAP_PUT_STRUCT)\s = "M_PUT_ST"
   gszATR(#ljMAP_GET_STRUCT)\s = "M_GET_ST"
   gszATR(#ljMAP_VALUE_STRUCT)\s = "M_VAL_ST"
   gszATR(#ljLIST_ADD_STRUCT_PTR)\s = "L_ADD_STP"
   gszATR(#ljLIST_GET_STRUCT_PTR)\s = "L_GET_STP"
   gszATR(#ljMAP_PUT_STRUCT_PTR)\s = "M_PUT_STP"
   gszATR(#ljMAP_GET_STRUCT_PTR)\s = "M_GET_STP"
   ; FE = Foreach
   gszATR(#ljFOREACH_LIST_INIT)\s = "FE_L_INIT"
   gszATR(#ljFOREACH_LIST_NEXT)\s = "FE_L_NEXT"
   gszATR(#ljFOREACH_MAP_INIT)\s = "FE_M_INIT"
   gszATR(#ljFOREACH_MAP_NEXT)\s = "FE_M_NEXT"
   gszATR(#ljFOREACH_END)\s = "FE_END"
   gszATR(#ljFOREACH_LIST_GET_INT)\s = "FE_L_GET_I"
   gszATR(#ljFOREACH_LIST_GET_FLOAT)\s = "FE_L_GET_F"
   gszATR(#ljFOREACH_LIST_GET_STR)\s = "FE_L_GET_S"
   gszATR(#ljFOREACH_MAP_KEY)\s = "FE_M_KEY"
   gszATR(#ljFOREACH_MAP_VALUE_INT)\s = "FE_M_VAL_I"
   gszATR(#ljFOREACH_MAP_VALUE_FLOAT)\s = "FE_M_VAL_F"
   gszATR(#ljFOREACH_MAP_VALUE_STR)\s = "FE_M_VAL_S"
   gszATR(#ljPUSH_SLOT)\s = "PUSH_SLOT"
   ; PP = PrtPtr, PF = PtrFetch, PS = PtrStore, V = Var, A = Arrel
   gszATR(#ljPRTPTR_INT)\s = "PP_I"
   gszATR(#ljPRTPTR_FLOAT)\s = "PP_F"
   gszATR(#ljPRTPTR_STR)\s = "PP_S"
   gszATR(#ljPRTPTR_ARRAY_INT)\s = "PP_A_I"
   gszATR(#ljPRTPTR_ARRAY_FLOAT)\s = "PP_A_F"
   gszATR(#ljPRTPTR_ARRAY_STR)\s = "PP_A_S"
   gszATR(#ljPTRFETCH_VAR_INT)\s = "PF_V_I"
   gszATR(#ljPTRFETCH_VAR_FLOAT)\s = "PF_V_F"
   gszATR(#ljPTRFETCH_VAR_STR)\s = "PF_V_S"
   gszATR(#ljPTRFETCH_ARREL_INT)\s = "PF_A_I"
   gszATR(#ljPTRFETCH_ARREL_FLOAT)\s = "PF_A_F"
   gszATR(#ljPTRFETCH_ARREL_STR)\s = "PF_A_S"
   gszATR(#ljPTRSTORE_VAR_INT)\s = "PS_V_I"
   gszATR(#ljPTRSTORE_VAR_FLOAT)\s = "PS_V_F"
   gszATR(#ljPTRSTORE_VAR_STR)\s = "PS_V_S"
   gszATR(#ljPTRSTORE_ARREL_INT)\s = "PS_A_I"
   gszATR(#ljPTRSTORE_ARREL_FLOAT)\s = "PS_A_F"
   gszATR(#ljPTRSTORE_ARREL_STR)\s = "PS_A_S"
   ; PA = PtrAdd, PB = PtrSub, PI = PtrInc, PD = PtrDec
   gszATR(#ljPTRADD_INT)\s = "PA_I"
   gszATR(#ljPTRADD_FLOAT)\s = "PA_F"
   gszATR(#ljPTRADD_STRING)\s = "PA_S"
   gszATR(#ljPTRADD_ARRAY)\s = "PA_A"
   gszATR(#ljPTRSUB_INT)\s = "PB_I"
   gszATR(#ljPTRSUB_FLOAT)\s = "PB_F"
   gszATR(#ljPTRSUB_STRING)\s = "PB_S"
   gszATR(#ljPTRSUB_ARRAY)\s = "PB_A"
   gszATR(#ljPTRINC_INT)\s = "PI_I"
   gszATR(#ljPTRINC_FLOAT)\s = "PI_F"
   gszATR(#ljPTRINC_STRING)\s = "PI_S"
   gszATR(#ljPTRINC_ARRAY)\s = "PI_A"
   gszATR(#ljPTRDEC_INT)\s = "PD_I"
   gszATR(#ljPTRDEC_FLOAT)\s = "PD_F"
   gszATR(#ljPTRDEC_STRING)\s = "PD_S"
   gszATR(#ljPTRDEC_ARRAY)\s = "PD_A"
   gszATR(#ljPTRINC_PRE_INT)\s = "PI_PR_I"
   gszATR(#ljPTRINC_PRE_FLOAT)\s = "PI_PR_F"
   gszATR(#ljPTRINC_PRE_STRING)\s = "PI_PR_S"
   gszATR(#ljPTRINC_PRE_ARRAY)\s = "PI_PR_A"
   gszATR(#ljPTRDEC_PRE_INT)\s = "PD_PR_I"
   gszATR(#ljPTRDEC_PRE_FLOAT)\s = "PD_PR_F"
   gszATR(#ljPTRDEC_PRE_STRING)\s = "PD_PR_S"
   gszATR(#ljPTRDEC_PRE_ARRAY)\s = "PD_PR_A"
   gszATR(#ljPTRINC_POST_INT)\s = "PI_PO_I"
   gszATR(#ljPTRINC_POST_FLOAT)\s = "PI_PO_F"
   gszATR(#ljPTRINC_POST_STRING)\s = "PI_PO_S"
   gszATR(#ljPTRINC_POST_ARRAY)\s = "PI_PO_A"
   gszATR(#ljPTRDEC_POST_INT)\s = "PD_PO_I"
   gszATR(#ljPTRDEC_POST_FLOAT)\s = "PD_PO_F"
   gszATR(#ljPTRDEC_POST_STRING)\s = "PD_PO_S"
   gszATR(#ljPTRDEC_POST_ARRAY)\s = "PD_PO_A"
   gszATR(#ljPTRADD_ASSIGN_INT)\s = "PA_AS_I"
   gszATR(#ljPTRADD_ASSIGN_FLOAT)\s = "PA_AS_F"
   gszATR(#ljPTRADD_ASSIGN_STRING)\s = "PA_AS_S"
   gszATR(#ljPTRADD_ASSIGN_ARRAY)\s = "PA_AS_A"
   gszATR(#ljPTRSUB_ASSIGN_INT)\s = "PB_AS_I"
   gszATR(#ljPTRSUB_ASSIGN_FLOAT)\s = "PB_AS_F"
   gszATR(#ljPTRSUB_ASSIGN_STRING)\s = "PB_AS_S"
   gszATR(#ljPTRSUB_ASSIGN_ARRAY)\s = "PB_AS_A"
   ; LV = LocalVar, LA = LocalArrel
   gszATR(#ljPTRFETCH_LVAR_INT)\s = "PF_LV_I"
   gszATR(#ljPTRFETCH_LVAR_FLOAT)\s = "PF_LV_F"
   gszATR(#ljPTRFETCH_LVAR_STR)\s = "PF_LV_S"
   gszATR(#ljPTRFETCH_LARREL_INT)\s = "PF_LA_I"
   gszATR(#ljPTRFETCH_LARREL_FLOAT)\s = "PF_LA_F"
   gszATR(#ljPTRFETCH_LARREL_STR)\s = "PF_LA_S"
   gszATR(#ljPTRSTORE_LVAR_INT)\s = "PS_LV_I"
   gszATR(#ljPTRSTORE_LVAR_FLOAT)\s = "PS_LV_F"
   gszATR(#ljPTRSTORE_LVAR_STR)\s = "PS_LV_S"
   gszATR(#ljPTRSTORE_LARREL_INT)\s = "PS_LA_I"
   gszATR(#ljPTRSTORE_LARREL_FLOAT)\s = "PS_LA_F"
   gszATR(#ljPTRSTORE_LARREL_STR)\s = "PS_LA_S"
   gszATR(#ljEOF)\s = "EOF"
EndMacro

; Total opcodes: 505

; IDE Options = PureBasic 6.21 (Windows - x64)
; CursorPosition = 47
; FirstLine = 30
; Folding = ---
; Optimizer
; EnableAsm
; EnableThread
; EnableXP
; SharedUCRT
; CPU = 1
; DisableDebugger
; EnableCompileCount = 26
; EnableBuildCount = 0
; EnableExeConstant