
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
; Storage Model:
;   - gVar[]      : Global variables ONLY (permanent, indexed by slot)
;   - gLocal[]    : Local variables ONLY (per-function frame, indexed by offset)
;   - gEvalStack[]: Evaluation stack ONLY (sp-indexed, completely isolated)
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

#DEBUG            = 0
#C2PROFILER       = 0     ; V1.033.16: Disabled for true VM speed test
#C2PROFILER_LOG   = 0     ; V1.031.112: Append profiler data to cumulative log file
#VM_INLINE_HOT    = 1     ; V1.033.15: Inline hot opcodes (LFETCHS, STORE, LSTORES, SUB, JMP, NEG + originals) in VM loop

#INV$             = ~"\""
#C2MAXTOKENS      = 500   ; Legacy, use #C2TOKENCOUNT for actual count
#C2MAXCONSTANTS   = 32767

; V1.31.0: Isolated Variable System array sizes - now use global variables:
; gLocalStack, gMaxEvalStack, gGlobalStack, gFunctionStack (set via pragmas)

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

   #ljMOVS
   #ljMOVF
   #ljFETCHS
   #ljFETCHF
   #ljSTORES
   #ljSTOREF

   ;- Local Variable Opcodes (V1.31.0: Isolated Variable System)
   ; V1.31.0: Locals stored in gLocal[], globals in gVar[], eval stack in gEvalStack[]
   ; LMOV/LFETCH/LSTORE operate on gLocal[] array (isolated from gVar[])
   #ljLMOV       ; GL MOV: gLocal[offset] = gVar[slot] (Global → Local)
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
   ; LMOV is GL (Global → Local), use LGMOV for Local → Global
   #ljLGMOV      ; LG MOV: gVar[slot] = gLocal[offset] (Local → Global)
   #ljLGMOVS     ; LG MOVS: string variant
   #ljLGMOVF     ; LG MOVF: float variant
   #ljLLMOV      ; LL MOV: gLocal[dst] = gLocal[src] (Local → Local)
   #ljLLMOVS     ; LL MOVS: string variant
   #ljLLMOVF     ; LL MOVF: float variant

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
   ; INT variants (global/local × index source × value source)
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
   funcid.w    ; Function ID for CALL (word)
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
EndStructure

;  Function template - stores initial values for a function's local variables
;  Parameters (LOCAL[0..nParams-1]) are NOT in template - they come from caller
;  Template covers LOCAL[nParams..totalVars-1] only
Structure stFuncTemplate
   funcId.i                      ; Function ID (index in gFuncTemplates)
   localCount.i                  ; Number of non-param locals (template size)
   Array template.stVarTemplate(0)  ; Pre-initialized values for locals
EndStructure

;- Globals

Global Dim           gszATR.stATR(#C2TOKENCOUNT)
Global Dim           gVarMeta.stVarMeta(#C2MAXCONSTANTS)  ; Compile-time info only
Global Dim           gFuncLocalArraySlots.i(512, 15)  ; [functionID, localArrayIndex] -> varSlot (initial size, Dim'd to exact size during FixJMP)
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
Global Dim           gFuncNames.s(512)       ; funcId -> function name (for CALL display)
Global Dim           gLocalNames.s(512, 64)  ; (funcId, paramOffset) -> local variable name

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
   ElseIf obj\code = #ljCall Or obj\code = #ljCALL0 Or obj\code = #ljCALL1 Or obj\code = #ljCALL2
      ; V1.033.12: Include optimized CALL0, CALL1, CALL2 opcodes
      CompilerIf show
         ; Runtime: just show basic CALL info (no compile-time metadata available)
         line + "  (" +Str(obj\i) + ") " + Str(i+1+obj\i) + " [params=" + Str(obj\j) + " locals=" + Str(obj\n) + "]"
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
         line + _asmFuncName + "() [params=" + Str(obj\j) + " locals=" + Str(obj\n) + "]"
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
      _ASMLineHelper1( show, obj\j )
      line + "[" + gVarMeta( obj\j )\name + temp + "] --> [" + gVarMeta( obj\i )\name + "] (src=" + Str(obj\j) + " dst=" + Str(obj\i) + ")"
      flag + 1
   ElseIf obj\code = #ljSTORE Or obj\code = #ljSTORES Or obj\code = #ljSTOREF
      ; V1.023.31: Don't use sp-1 for value display - sp is runtime, not compile-time
      line + "[sp] --> [" + gVarMeta( obj\i )\name + "] (slot=" + Str(obj\i) + ")"
      flag + 1
   ; Local variable STORE operations - show paramOffset with name
   ; V1.023.21: Added PLSTORE to display
   ElseIf obj\code = #ljLSTORE Or obj\code = #ljLSTORES Or obj\code = #ljLSTOREF Or obj\code = #ljPLSTORE
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
   ElseIf obj\code = #ljINC_VAR Or obj\code = #ljDEC_VAR Or obj\code = #ljINC_VAR_PRE Or obj\code = #ljDEC_VAR_PRE Or obj\code = #ljINC_VAR_POST Or obj\code = #ljDEC_VAR_POST
      line + "[" + gVarMeta(obj\i)\name + "]"
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
   ElseIf obj\code = #ljPUSH Or obj\code = #ljFetch Or obj\code = #ljPUSHS Or obj\code = #ljPUSHF
      flag + 1
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
Macro                   _LARRAY(offset)
   ; V1.031.14: Use global gLocalBase, NOT stack frame's localBase
   ; Stack frame stores CALLER's base for restoration, not current function's base
   (gLocalBase + offset)
EndMacro
;- End of file

DataSection
c2tokens:
   Data.s   "UNUSED"
   Data.i   0, 0
   Data.s   "VAR"
   Data.i   0, 0
   Data.s   "INT"
   Data.i   0, 0
   Data.s   "FLT"
   Data.i   0, 0
   Data.s   "STR"
   Data.i   0, 0
   Data.s   "VOID"        ; V1.033.19: Must match #ljVOID enum entry added in V1.033.11
   Data.i   0, 0
   Data.s   "STRUCTTYPE"  ; V1.022.80: New enum entry - must be in DataSection to maintain alignment
   Data.i   0, 0
   Data.s   "TYPEGUESS"   ; V1.022.80: New enum entry - must be in DataSection to maintain alignment
   Data.i   0, 0
   Data.s   "ARRAY"
   Data.i   0, 0

   Data.s   "IF"
   Data.i   0, 0
   Data.s   "ELSE"
   Data.i   0, 0
   Data.s   "WHILE"
   Data.i   0, 0
   ; V1.024.0: Control flow tokens
   Data.s   "FOR"
   Data.i   0, 0
   Data.s   "SWITCH"
   Data.i   0, 0
   Data.s   "CASE"
   Data.i   0, 0
   Data.s   "DEFAULT"
   Data.i   0, 0
   Data.s   "BREAK"
   Data.i   0, 0
   Data.s   "CONTINUE"
   Data.i   0, 0
   Data.s   "JZ"
   Data.i   0, 0
   Data.s   "JMP"
   Data.i   0, 0
   Data.s   "NEG"
   Data.i   #ljFLOATNEG, 0
   Data.s   "FLNEG"
   Data.i   #ljFLOATNEG, 0
   Data.s   "NOT"
   Data.i   0, 0
   Data.s   "ASSIGN"
   Data.i   0, 0

   ; Compound assignment and increment/decrement operators
   Data.s   "ADD_ASSIGN"
   Data.i   0, 0
   Data.s   "SUB_ASSIGN"
   Data.i   0, 0
   Data.s   "MUL_ASSIGN"
   Data.i   0, 0
   Data.s   "DIV_ASSIGN"
   Data.i   0, 0
   Data.s   "MOD_ASSIGN"
   Data.i   0, 0
   Data.s   "INC"
   Data.i   0, 0
   Data.s   "DEC"
   Data.i   0, 0
   Data.s   "PRE_INC"
   Data.i   0, 0
   Data.s   "PRE_DEC"
   Data.i   0, 0
   Data.s   "POST_INC"
   Data.i   0, 0
   Data.s   "POST_DEC"
   Data.i   0, 0

   Data.s   "ADD"
   Data.i   #ljFLOATADD, #ljSTRADD
   Data.s   "SUB"
   Data.i   #ljFLOATSUB, 0
   Data.s   "MUL"
   Data.i   #ljFLOATMUL, 0
   Data.s   "DIV"
   Data.i   #ljFLOATDIV, 0
   Data.s   "FLADD"
   Data.i   #ljFLOATADD, #ljSTRADD
   Data.s   "FLSUB"
   Data.i   #ljFLOATSUB, 0
   Data.s   "FLMUL"
   Data.i   #ljFLOATMUL, 0
   Data.s   "FLDIV"
   Data.i   #ljFLOATDIV, 0
   Data.s   "STRADD"
   Data.i   #ljFLOATADD, #ljSTRADD
   Data.s   "FTOS"
   Data.i   0, 0
   Data.s   "ITOS"
   Data.i   0, 0
   Data.s   "ITOF"
   Data.i   0, 0
   Data.s   "FTOI"
   Data.i   0, 0
   Data.s   "STOF"
   Data.i   0, 0
   Data.s   "STOI"
   Data.i   0, 0

   Data.s   "OR"
   Data.i   0, 0
   Data.s   "AND"
   Data.i   0, 0
   Data.s   "XOR"
   Data.i   0, 0
   Data.s   "MOD"
   Data.i   0, 0
   
   Data.s   "EQ"
   Data.i   #ljFLOATEQ, 0
   Data.s   "NE"
   Data.i   #ljFLOATNE, 0
   Data.s   "LTE"
   Data.i   #ljFLOATLE, 0
   Data.s   "GTE"
   Data.i   #ljFLOATGE, 0
   Data.s   "GT"
   Data.i   #ljFLOATGR, 0
   Data.s   "LT"
   Data.i   #ljFLOATLESS, 0
   Data.s   "FLEQ"
   Data.i   0, 0
   Data.s   "FLNE"
   Data.i   0, 0
   Data.s   "FLLTE"
   Data.i   0, 0
   Data.s   "FLGTE"
   Data.i   0, 0
   Data.s   "FLGT"
   Data.i   0, 0
   Data.s   "FLLT"
   Data.i   0, 0

   ; V1.023.30: String comparison opcodes
   Data.s   "STREQ"
   Data.i   0, 0
   Data.s   "STRNE"
   Data.i   0, 0

   Data.s   "MOV"
   Data.i   #ljMOVF, #ljMOVS
   Data.s   "FETCH"
   Data.i   #ljFETCHF, #ljFETCHS
   Data.s   "POP"
   Data.i   #ljPOPF, #ljPOPS
   Data.s   "POPS"
   Data.i   0, 0
   Data.s   "POPF"
   Data.i   0, 0
   Data.s   "PUSH"
   Data.i   #ljPUSHF, #ljPUSHS
   Data.s   "PUSHS"
   Data.i   0, 0
   Data.s   "PUSHF"
   Data.i   0, 0
   Data.s   "PUSH_IMM"        ; V1.031.113: Push immediate value
   Data.i   0, 0
   Data.s   "STORE"
   Data.i   #ljSTOREF, #ljSTORES
   Data.s   "HALT"
   Data.i   0, 0
   
   Data.s   "PRINT"
   Data.i   #ljPRTF, #ljPRTS
   Data.s   "PRTC"
   Data.i   #ljPRTF, #ljPRTS
   Data.s   "PRTI"
   Data.i   #ljPRTF, #ljPRTS
   Data.s   "PRTF"
   Data.i   #ljPRTF, #ljPRTS
   Data.s   "PRTS"
   Data.i   #ljPRTF, #ljPRTS

   Data.s   "LeftBrace"
   Data.i   0, 0
   Data.s   "RightBrace"
   Data.i   0, 0
   Data.s   "LeftParent"
   Data.i   0, 0
   Data.s   "RightParent"
   Data.i   0, 0
   Data.s   "LeftBracket"
   Data.i   0, 0
   Data.s   "RightBracket"
   Data.i   0, 0
   Data.s   "SemiColon"
   Data.i   0, 0
   Data.s   "Comma"
   Data.i   0, 0
   Data.s   "Backslash"
   Data.i   0, 0
   Data.s   "function"
   Data.i   0, 0
   Data.s   "RET"
   Data.i   #ljReturnF, #ljReturnS
   Data.s   "RETF"
   Data.i   0, 0
   Data.s   "RETS"
   Data.i   0, 0
   Data.s   "CALL"
   Data.i   0, 0
   Data.s   "CALL0"         ; V1.033.12: Optimized 0-param call
   Data.i   0, 0
   Data.s   "CALL1"         ; V1.033.12: Optimized 1-param call
   Data.i   0, 0
   Data.s   "CALL2"         ; V1.033.12: Optimized 2-param call
   Data.i   0, 0
   Data.s   "ARRAYINFO"     ; V1.031.105: Local array info (i=paramOffset, j=arraySize)
   Data.i   0, 0

   Data.s   "Unknown"
   Data.i   0, 0
   Data.s   "NOOP"
   Data.i   0, 0
   Data.s   "OP"
   Data.i   0, 0
   Data.s   "SEQ"
   Data.i   0, 0
   Data.s   "Keyword"
   Data.i   0, 0

   Data.s   "TERNARY"
   Data.i   0, 0
   Data.s   "QUESTION"
   Data.i   0, 0
   Data.s   "COLON"
   Data.i   0, 0
   Data.s   "TENIF"
   Data.i   0, 0
   Data.s   "TENELSE"
   Data.i   0, 0
   Data.s   "NOOPIF"
   Data.i   0, 0

   ; V1.024.0: New opcodes for switch statement
   Data.s   "DUP"
   Data.i   0, 0
   Data.s   "DUP_I"
   Data.i   0, 0
   Data.s   "DUP_F"
   Data.i   0, 0
   Data.s   "DUP_S"
   Data.i   0, 0
   Data.s   "JNZ"
   Data.i   0, 0
   Data.s   "DROP"
   Data.i   0, 0

   Data.s   "MOVS"
   Data.i   0, 0
   Data.s   "MOVF"
   Data.i   0, 0
   Data.s   "FETCHS"
   Data.i   0, 0
   Data.s   "FETCHF"
   Data.i   0, 0
   Data.s   "STORES"
   Data.i   0, 0
   Data.s   "STOREF"
   Data.i   0, 0

   ; Local variable opcodes (frame-relative, no flag checks)
   Data.s   "LMOV"
   Data.i   #ljLMOVF, #ljLMOVS
   Data.s   "LMOVS"
   Data.i   0, 0
   Data.s   "LMOVF"
   Data.i   0, 0
   Data.s   "LFETCH"
   Data.i   #ljLFETCHF, #ljLFETCHS
   Data.s   "LFETCHS"
   Data.i   0, 0
   Data.s   "LFETCHF"
   Data.i   0, 0
   Data.s   "LSTORE"
   Data.i   #ljLSTOREF, #ljLSTORES
   Data.s   "LSTORES"
   Data.i   0, 0
   Data.s   "LSTOREF"
   Data.i   0, 0

   ; V1.022.31: Cross-locality MOV opcodes
   Data.s   "LGMOV"
   Data.i   #ljLGMOVF, #ljLGMOVS
   Data.s   "LGMOVS"
   Data.i   0, 0
   Data.s   "LGMOVF"
   Data.i   0, 0
   Data.s   "LLMOV"
   Data.i   #ljLLMOVF, #ljLLMOVS
   Data.s   "LLMOVS"
   Data.i   0, 0
   Data.s   "LLMOVF"
   Data.i   0, 0

   ; In-place increment/decrement opcodes
   Data.s   "INC_VAR"
   Data.i   0, 0
   Data.s   "DEC_VAR"
   Data.i   0, 0
   Data.s   "INC_VAR_PRE"
   Data.i   0, 0
   Data.s   "DEC_VAR_PRE"
   Data.i   0, 0
   Data.s   "INC_VAR_POST"
   Data.i   0, 0
   Data.s   "DEC_VAR_POST"
   Data.i   0, 0
   Data.s   "LINC_VAR"
   Data.i   0, 0
   Data.s   "LDEC_VAR"
   Data.i   0, 0
   Data.s   "LINCV_PRE"
   Data.i   0, 0
   Data.s   "LDECV_PRE"
   Data.i   0, 0
   Data.s   "LINCV_POST"
   Data.i   0, 0
   Data.s   "LDECV_POST"
   Data.i   0, 0

   ; Pointer increment/decrement opcodes (V1.20.36)
   Data.s   "INCP"
   Data.i   0, 0
   Data.s   "DECP"
   Data.i   0, 0
   Data.s   "INCP_PRE"
   Data.i   0, 0
   Data.s   "DECP_PRE"
   Data.i   0, 0
   Data.s   "INCP_POST"
   Data.i   0, 0
   Data.s   "DECP_POST"
   Data.i   0, 0

   ; V1.029.84: Struct storage opcode
   Data.s   "STOSTRUCT"
   Data.i   0, 0

   ; In-place compound assignment opcodes (renamed V1.029.61)
   Data.s   "ADDASS"
   Data.i   0, 0
   Data.s   "SUBASS"
   Data.i   0, 0
   Data.s   "MULASS"
   Data.i   0, 0
   Data.s   "DIVASS"
   Data.i   0, 0
   Data.s   "MODASS"
   Data.i   0, 0
   Data.s   "ADDASSF"
   Data.i   0, 0
   Data.s   "SUBASSF"
   Data.i   0, 0
   Data.s   "MULASSF"
   Data.i   0, 0
   Data.s   "DIVASSF"
   Data.i   0, 0
   Data.s   "ADDPTRA"
   Data.i   0, 0
   Data.s   "SUBPTRA"
   Data.i   0, 0

   ; Built-in functions
   Data.s   "RANDOM"
   Data.i   0, 0
   Data.s   "ABS"
   Data.i   0, 0
   Data.s   "MIN"
   Data.i   0, 0
   Data.s   "MAX"
   Data.i   0, 0
   Data.s   "ASSERT_EQ"
   Data.i   0, 0
   Data.s   "ASSERT_FLT"
   Data.i   0, 0
   Data.s   "ASSERT_STR"
   Data.i   0, 0
   Data.s   "SQRT"
   Data.i   0, 0
   Data.s   "POW"
   Data.i   0, 0
   Data.s   "LEN"
   Data.i   0, 0
   Data.s   "STRCMP"
   Data.i   0, 0
   Data.s   "GETC"
   Data.i   0, 0

   ; Array operations
   Data.s   "ARRIDX"
   Data.i   0, 0
   Data.s   "ARRFETCH"
   Data.i   #ljARRAYFETCH_INT, #ljARRAYFETCH_STR
   Data.s   "IFETCHAR"
   Data.i   0, 0
   Data.s   "FFETCHAR"
   Data.i   0, 0
   Data.s   "SFETCHAR"
   Data.i   0, 0
   Data.s   "ARRSTORE"
   Data.i   #ljARRAYSTORE_INT, #ljARRAYSTORE_STR
   Data.s   "IARRSTORE"
   Data.i   0, 0
   Data.s   "FARRSTORE"
   Data.i   0, 0
   Data.s   "SARRSTORE"
   Data.i   0, 0

   ; Specialized array fetch opcodes (renamed V1.029.61 - FCHR=fetch char)
   Data.s   "GFCHR_O"
   Data.i   0, 0
   Data.s   "GFCHR_K"
   Data.i   0, 0
   Data.s   "LFCHR_O"
   Data.i   0, 0
   Data.s   "LFCHR_K"
   Data.i   0, 0
   Data.s   "GFCHRF_O"
   Data.i   0, 0
   Data.s   "GFCHRF_K"
   Data.i   0, 0
   Data.s   "LFCHRF_O"
   Data.i   0, 0
   Data.s   "LFCHRF_K"
   Data.i   0, 0
   Data.s   "GFCHRS_O"
   Data.i   0, 0
   Data.s   "GFCHRS_K"
   Data.i   0, 0
   Data.s   "LFCHRS_O"
   Data.i   0, 0
   Data.s   "LFCHRS_K"
   Data.i   0, 0

   ; Specialized array store opcodes (renamed V1.029.61 - STAR=store array)
   Data.s   "GSTAR_OO"
   Data.i   0, 0
   Data.s   "GSTAR_OS"
   Data.i   0, 0
   Data.s   "GSTAR_SO"
   Data.i   0, 0
   Data.s   "GSTAR_SS"
   Data.i   0, 0
   Data.s   "LSTAR_OO"
   Data.i   0, 0
   Data.s   "LSTAR_OS"
   Data.i   0, 0
   Data.s   "LSTAR_SO"
   Data.i   0, 0
   Data.s   "LSTAR_SS"
   Data.i   0, 0
   Data.s   "GSTARF_OO"
   Data.i   0, 0
   Data.s   "GSTARF_OS"
   Data.i   0, 0
   Data.s   "GSTARF_SO"
   Data.i   0, 0
   Data.s   "GSTARF_SS"
   Data.i   0, 0
   Data.s   "LSTARF_OO"
   Data.i   0, 0
   Data.s   "LSTARF_OS"
   Data.i   0, 0
   Data.s   "LSTARF_SO"
   Data.i   0, 0
   Data.s   "LSTARF_SS"
   Data.i   0, 0
   Data.s   "GSTARS_OO"
   Data.i   0, 0
   Data.s   "GSTARS_OS"
   Data.i   0, 0
   Data.s   "GSTARS_SO"
   Data.i   0, 0
   Data.s   "GSTARS_SS"
   Data.i   0, 0
   Data.s   "LSTARS_OO"
   Data.i   0, 0
   Data.s   "LSTARS_OS"
   Data.i   0, 0
   Data.s   "LSTARS_SO"
   Data.i   0, 0
   Data.s   "LSTARS_SS"
   Data.i   0, 0

   ; V1.022.114: OPT_LOPT opcodes (renamed V1.029.61)
   Data.s   "GSTAR_OLO"
   Data.i   0, 0
   Data.s   "GSTARF_OLO"
   Data.i   0, 0
   Data.s   "GSTARS_OLO"
   Data.i   0, 0

   ; V1.022.115: LOCAL OPT_LOPT opcodes (renamed V1.029.61)
   Data.s   "LSTAR_OLO"
   Data.i   0, 0
   Data.s   "LSTARF_OLO"
   Data.i   0, 0
   Data.s   "LSTARS_OLO"
   Data.i   0, 0

   ; V1.022.86: Local-Index Array Opcodes (renamed V1.029.61)
   Data.s   "GFCHR_LO"
   Data.i   0, 0
   Data.s   "GFCHRF_LO"
   Data.i   0, 0
   Data.s   "GFCHRS_LO"
   Data.i   0, 0
   Data.s   "GSTAR_LOLO"
   Data.i   0, 0
   Data.s   "GSTAR_LOO"
   Data.i   0, 0
   Data.s   "GSTAR_LOS"
   Data.i   0, 0
   Data.s   "GSTARF_LOLO"
   Data.i   0, 0
   Data.s   "GSTARF_LOO"
   Data.i   0, 0
   Data.s   "GSTARF_LOS"
   Data.i   0, 0
   Data.s   "GSTARS_LOLO"
   Data.i   0, 0
   Data.s   "GSTARS_LOO"
   Data.i   0, 0
   Data.s   "GSTARS_LOS"
   Data.i   0, 0

   ; V1.022.113: Local-Index Array Opcodes for LOCAL arrays (renamed V1.029.61)
   Data.s   "LFCHR_LO"
   Data.i   0, 0
   Data.s   "LFCHRF_LO"
   Data.i   0, 0
   Data.s   "LFCHRS_LO"
   Data.i   0, 0
   Data.s   "LSTAR_LOLO"
   Data.i   0, 0
   Data.s   "LSTAR_LOO"
   Data.i   0, 0
   Data.s   "LSTAR_LOS"
   Data.i   0, 0
   Data.s   "LSTARF_LOLO"
   Data.i   0, 0
   Data.s   "LSTARF_LOO"
   Data.i   0, 0
   Data.s   "LSTARF_LOS"
   Data.i   0, 0
   Data.s   "LSTARS_LOLO"
   Data.i   0, 0
   Data.s   "LSTARS_LOO"
   Data.i   0, 0
   Data.s   "LSTARS_LOS"
   Data.i   0, 0

   ; Pointer operations (renamed V1.029.61)
   Data.s   "ADDR"
   Data.i   0, 0
   Data.s   "ADDRF"
   Data.i   0, 0
   Data.s   "ADDRS"
   Data.i   0, 0
   ; V1.027.2: Local variable address opcodes (renamed V1.029.61)
   Data.s   "LADDR"
   Data.i   0, 0
   Data.s   "LADDRF"
   Data.i   0, 0
   Data.s   "LADDRS"
   Data.i   0, 0
   Data.s   "FETPTR"
   Data.i   #ljPTRFETCH_FLOAT, #ljPTRFETCH_STR
   Data.s   "FETPTR_I"
   Data.i   0, 0
   Data.s   "FETPTRF"
   Data.i   0, 0
   Data.s   "FETPTRS"
   Data.i   0, 0
   Data.s   "STOPTR"
   Data.i   #ljPTRSTORE_FLOAT, #ljPTRSTORE_STR
   Data.s   "STOPTR_I"
   Data.i   0, 0
   Data.s   "STOPTRF"
   Data.i   0, 0
   Data.s   "STOPTRS"
   Data.i   0, 0
   Data.s   "FLDPTR"
   Data.i   0, 0
   Data.s   "FLDPTRF"
   Data.i   0, 0
   Data.s   "FLDPTRS"
   Data.i   0, 0
   ; V1.022.44: AST node types for struct array field access (in enumeration, need entries)
   Data.s   "SAFLD_I"
   Data.i   0, 0
   Data.s   "SAFLD_F"
   Data.i   0, 0
   Data.s   "SAFLD_S"
   Data.i   0, 0
   Data.s   "PTRADD"
   Data.i   0, 0
   Data.s   "PTRSUB"
   Data.i   0, 0
   Data.s   "ADDRFN"
   Data.i   0, 0
   Data.s   "CALLFP"
   Data.i   0, 0

   ; Array pointer opcodes (renamed V1.029.61)
   Data.s   "ADDRAR"
   Data.i   0, 0
   Data.s   "ADDRARF"
   Data.i   0, 0
   Data.s   "ADDRARS"
   Data.i   0, 0
   ; V1.027.2: Local array address opcodes (renamed V1.029.61)
   Data.s   "LADDRAR"
   Data.i   0, 0
   Data.s   "LADDRARF"
   Data.i   0, 0
   Data.s   "LADDRARS"
   Data.i   0, 0

   Data.s   "PRTPTR"
   Data.i   0, 0

   ; V1.20.27: Pointer-only opcodes (always copy metadata, no runtime checks)
   Data.s   "PMOV"
   Data.i   0, 0
   Data.s   "PFETCH"
   Data.i   0, 0
   Data.s   "PSTORE"
   Data.i   0, 0
   Data.s   "PPOP"
   Data.i   0, 0
   Data.s   "PLFETCH"
   Data.i   0, 0
   Data.s   "PLSTORE"
   Data.i   0, 0
   Data.s   "PLMOV"
   Data.i   0, 0

   ; V1.18.63: Cast opcodes
   Data.s   "CAST_INT"
   Data.i   0, 0
   Data.s   "CAST_FLT"
   Data.i   0, 0
   Data.s   "CAST_STR"
   Data.i   0, 0

   ; V1.021.0: Structure support (renamed V1.029.61)
   Data.s   "STRUCT"
   Data.i   0, 0
   Data.s   "STFIELD"
   Data.i   0, 0
   Data.s   "INITST"
   Data.i   0, 0

   ; V1.022.0: Struct array field opcodes (renamed V1.029.61 - STAR=struct's array)
   Data.s   "FETSTAR"
   Data.i   0, 0
   Data.s   "FETSTARF"
   Data.i   0, 0
   Data.s   "FETSTARS"
   Data.i   0, 0
   Data.s   "STOSTAR"
   Data.i   0, 0
   Data.s   "STOSTARF"
   Data.i   0, 0
   Data.s   "STOSTARS"
   Data.i   0, 0

   ; V1.022.44: Array of structs opcodes (renamed V1.029.61 - ARST=array's struct)
   Data.s   "FETARST"
   Data.i   0, 0
   Data.s   "FETARSTF"
   Data.i   0, 0
   Data.s   "FETARSTS"
   Data.i   0, 0
   Data.s   "STOARST"
   Data.i   0, 0
   Data.s   "STOARSTF"
   Data.i   0, 0
   Data.s   "STOARSTS"
   Data.i   0, 0

   ; V1.022.118: Array of struct LOPT opcodes (renamed V1.029.61 - LI=local index)
   Data.s   "FETARST_LI"
   Data.i   0, 0
   Data.s   "FETARSTF_LI"
   Data.i   0, 0
   Data.s   "FETARSTS_LI"
   Data.i   0, 0
   Data.s   "STOARST_LI"
   Data.i   0, 0
   Data.s   "STOARSTF_LI"
   Data.i   0, 0
   Data.s   "STOARSTS_LI"
   Data.i   0, 0

   ; V1.022.54: Struct pointer opcodes (renamed V1.029.61)
   Data.s   "ADDRST"
   Data.i   0, 0
   Data.s   "FETPST"
   Data.i   0, 0
   Data.s   "FETPSTF"
   Data.i   0, 0
   Data.s   "FETPSTS"
   Data.i   0, 0
   Data.s   "STOPST"
   Data.i   0, 0
   Data.s   "STOPSTF"
   Data.i   0, 0
   Data.s   "STOPSTS"
   Data.i   0, 0

   ; V1.022.117: PTRSTRUCTSTORE LOPT opcodes (renamed V1.029.61 - LV=local value)
   Data.s   "STOPST_LV"
   Data.i   0, 0
   Data.s   "STOPSTF_LV"
   Data.i   0, 0
   Data.s   "STOPSTS_LV"
   Data.i   0, 0

   ; V1.022.119: PTRSTRUCTFETCH LPTR opcodes (renamed V1.029.61 - L=local ptr)
   Data.s   "LFETPST"
   Data.i   0, 0
   Data.s   "LFETPSTF"
   Data.i   0, 0
   Data.s   "LFETPSTS"
   Data.i   0, 0

   ; V1.022.119: PTRSTRUCTSTORE LPTR opcodes (renamed V1.029.61 - L=local ptr)
   Data.s   "LSTOPST"
   Data.i   0, 0
   Data.s   "LSTOPSTF"
   Data.i   0, 0
   Data.s   "LSTOPSTS"
   Data.i   0, 0

   ; V1.022.119: PTRSTRUCTSTORE LPTR_LOPT opcodes (renamed V1.029.61 - L=local ptr, LV=local val)
   Data.s   "LSTOPST_LV"
   Data.i   0, 0
   Data.s   "LSTOPSTF_LV"
   Data.i   0, 0
   Data.s   "LSTOPSTS_LV"
   Data.i   0, 0

   ; V1.022.64: Array resize opcode
   Data.s   "ARRESIZE"
   Data.i   0, 0

   ; V1.022.65: Struct copy opcode
   Data.s   "SCOPY"
   Data.i   0, 0

   ; V1.029.36: Struct pointer opcodes (renamed V1.029.61)
   Data.s   "ALLOCST"
   Data.i   0, 0
   Data.s   "LALLOCST"
   Data.i   0, 0
   Data.s   "FREEST"
   Data.i   0, 0
   Data.s   "FETST"
   Data.i   0, 0
   Data.s   "FETSTF"
   Data.i   0, 0
   Data.s   "LFETST"
   Data.i   0, 0
   Data.s   "LFETSTF"
   Data.i   0, 0
   Data.s   "STOST"
   Data.i   0, 0
   Data.s   "STOSTF"
   Data.i   0, 0
   Data.s   "LSTOST"
   Data.i   0, 0
   Data.s   "LSTOSTF"
   Data.i   0, 0
   ; V1.029.55: String struct field opcodes (renamed V1.029.61)
   Data.s   "FETSTS"
   Data.i   0, 0
   Data.s   "LFETSTS"
   Data.i   0, 0
   Data.s   "STOSTS"
   Data.i   0, 0
   Data.s   "LSTOSTS"
   Data.i   0, 0
   Data.s   "COPYSTP"
   Data.i   0, 0
   ; V1.029.38: Struct parameter passing (renamed V1.029.61)
   Data.s   "FETST_P"
   Data.i   0, 0
   Data.s   "LFETST_P"
   Data.i   0, 0

   ; V1.026.0: List operations
   Data.s   "List"
   Data.i   0, 0
   Data.s   "LIST_NEW"
   Data.i   0, 0
   Data.s   "LIST_ADD"
   Data.i   0, 0
   Data.s   "LIST_INSERT"
   Data.i   0, 0
   Data.s   "LIST_DELETE"
   Data.i   0, 0
   Data.s   "LIST_CLEAR"
   Data.i   0, 0
   Data.s   "LIST_SIZE"
   Data.i   0, 0
   Data.s   "LIST_FIRST"
   Data.i   0, 0
   Data.s   "LIST_LAST"
   Data.i   0, 0
   Data.s   "LIST_NEXT"
   Data.i   0, 0
   Data.s   "LIST_PREV"
   Data.i   0, 0
   Data.s   "LIST_SELECT"
   Data.i   0, 0
   Data.s   "LIST_INDEX"
   Data.i   0, 0
   Data.s   "LIST_GET"
   Data.i   0, 0
   Data.s   "LIST_SET"
   Data.i   0, 0
   Data.s   "LIST_RESET"
   Data.i   0, 0
   Data.s   "LIST_SORT"
   Data.i   0, 0

   ; V1.026.8: Typed list operations (renamed V1.029.61 - LST=list)
   Data.s   "LSTADD"
   Data.i   0, 0
   Data.s   "LSTADDF"
   Data.i   0, 0
   Data.s   "LSTADDS"
   Data.i   0, 0
   Data.s   "LSTINS"
   Data.i   0, 0
   Data.s   "LSTINSF"
   Data.i   0, 0
   Data.s   "LSTINSS"
   Data.i   0, 0
   Data.s   "LSTGET"
   Data.i   0, 0
   Data.s   "LSTGETF"
   Data.i   0, 0
   Data.s   "LSTGETS"
   Data.i   0, 0
   Data.s   "LSTSET"
   Data.i   0, 0
   Data.s   "LSTSETF"
   Data.i   0, 0
   Data.s   "LSTSETS"
   Data.i   0, 0

   ; V1.029.28: Struct list operations (renamed V1.029.61)
   Data.s   "LSTADDST"
   Data.i   0, 0
   Data.s   "LSTGETST"
   Data.i   0, 0
   Data.s   "LSTSETST"
   Data.i   0, 0

   ; V1.026.0: Map operations
   Data.s   "Map"
   Data.i   0, 0
   Data.s   "MAP_NEW"
   Data.i   0, 0
   Data.s   "MAP_PUT"
   Data.i   0, 0
   Data.s   "MAP_GET"
   Data.i   0, 0
   Data.s   "MAP_DELETE"
   Data.i   0, 0
   Data.s   "MAP_CLEAR"
   Data.i   0, 0
   Data.s   "MAP_SIZE"
   Data.i   0, 0
   Data.s   "MAP_CONTAINS"
   Data.i   0, 0
   Data.s   "MAP_RESET"
   Data.i   0, 0
   Data.s   "MAP_NEXT"
   Data.i   0, 0
   Data.s   "MAP_KEY"
   Data.i   0, 0
   Data.s   "MAP_VALUE"
   Data.i   0, 0

   ; V1.026.8: Typed map operations (renamed V1.029.61 - MAP=map)
   Data.s   "MAPPUT"
   Data.i   0, 0
   Data.s   "MAPPUTF"
   Data.i   0, 0
   Data.s   "MAPPUTS"
   Data.i   0, 0
   Data.s   "MAPGET"
   Data.i   0, 0
   Data.s   "MAPGETF"
   Data.i   0, 0
   Data.s   "MAPGETS"
   Data.i   0, 0
   Data.s   "MAPVAL"
   Data.i   0, 0
   Data.s   "MAPVALF"
   Data.i   0, 0
   Data.s   "MAPVALS"
   Data.i   0, 0

   ; V1.029.28: Struct map operations (renamed V1.029.61)
   Data.s   "MAPPUTST"
   Data.i   0, 0
   Data.s   "MAPGETST"
   Data.i   0, 0
   Data.s   "MAPVALST"
   Data.i   0, 0

   ; V1.029.65: \ptr-based struct collection operations
   Data.s   "LSTADDSTPT"
   Data.i   0, 0
   Data.s   "LSTGETSTPT"
   Data.i   0, 0
   Data.s   "MAPPUTSTPT"
   Data.i   0, 0
   Data.s   "MAPGETSTPT"
   Data.i   0, 0

   ; V1.026.0: Collection slot push
   ; V1.026.8: DEPRECATED - use FETCH/LFETCH instead
   Data.s   "PUSH_SLOT"
   Data.i   0, 0

   Data.s   "EOF"
   Data.i   0, 0
   Data.s   "-"
EndDataSection

; IDE Options = PureBasic 6.21 (Windows - x64)
; CursorPosition = 49
; FirstLine = 30
; Folding = --
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