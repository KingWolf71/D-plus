
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
; V1.18.0 - UNIFIED VARIABLE SYSTEM
; ===================================
; All variables (global and local) now use the same gVar[] array and opcodes.
; Local variables are allocated as temporary gVar[] slots during function calls.
; Benefits: Simpler code, one method for all variables, easier to understand.
;
; Variable Allocation:
;   - gVar[0 to gnLastVariable-1]              : Permanent global variables
;   - gVar[gnLastVariable to gCurrentMaxLocal] : Active local variables (nested calls)
;   - gVar[gCurrentMaxLocal onwards]           : Evaluation stack (sp starts here)
;
; Local variable access:
;   - paramOffset >= 0: actualSlot = localSlotStart + paramOffset
;   - paramOffset = -1: use varSlot directly (global)
;   - All variables use FETCH/STORE/MOV opcodes (no separate LFETCH/LSTORE/LMOV)
;
; V1.18.12 - paramOffset Space Allocation:
;   - Regular local variables: paramOffset = 0 to nLocals-1
;   - Local arrays: paramOffset = 1000 to 1000+nLocalArrays-1
;   - Separation needed because arrays use gVar[slot].dta.ar() while variables use gVar[slot].i/.f/.ss
;   - A gVar[] slot can hold EITHER a scalar value OR an array, but not both

; ======================================================================================================
;- Constants
; ======================================================================================================

#INV$             = ~"\""
#DEBUG            = 0

#C2MAXTOKENS      = 500   ; Legacy, use #C2TOKENCOUNT for actual count   
#C2MAXCONSTANTS   = 8192

#C2FLAG_TYPE      = 28   ; Mask for type bits only (INT | FLOAT | STR = 4|8|16 = 28)
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

Enumeration
   #C2HOLE_START
   #C2HOLE_DEFAULT
   #C2HOLE_PAIR
   #C2HOLE_BLIND
   #C2HOLE_LOOPBACK  ; V1.023.42: While loop backward jump (target is NOOPIF at loop start)
EndEnumeration

Enumeration
   #ljUNUSED
   #ljIDENT
   #ljINT
   #ljFLOAT
   #ljSTRING
   #ljStructType  ; V1.022.80: Struct type hint for arrays and variables (distinct from #ljStruct keyword)
   #ljTypeGuess   ; V1.022.80: Type inferred from first assignment (allows multi-pass refinement)
   #ljArray
   #ljIF
   #ljElse
   #ljWHILE
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

   #ljMOVS
   #ljMOVF
   #ljFETCHS
   #ljFETCHF
   #ljSTORES
   #ljSTOREF

   ;- Local Variable Opcodes (V1.022.31: Restored and expanded)
   ; V1.18.0 had marked these deprecated, but they're needed for proper local variable handling
   ; LMOV/LFETCH/LSTORE = Global-to-Local or Local-to-Stack operations (kept for compatibility)
   #ljLMOV       ; GL MOV: gVar[localBase+i] = gVar[j] (Global → Local)
   #ljLMOVS      ; GL MOVS: string variant
   #ljLMOVF      ; GL MOVF: float variant
   #ljLFETCH     ; Local FETCH: push gVar[localBase+i] to stack
   #ljLFETCHS    ; Local FETCHS: string variant
   #ljLFETCHF    ; Local FETCHF: float variant
   #ljLSTORE     ; Local STORE: pop stack to gVar[localBase+i]
   #ljLSTORES    ; Local STORES: string variant
   #ljLSTOREF    ; Local STOREF: float variant

   ;- V1.022.31: New cross-locality MOV opcodes for complete local/global transfer matrix
   ; Format: [src][dst]MOV where L=Local, G=Global
   ; LMOV above is actually GLMOV (kept for compatibility)
   #ljLGMOV      ; LG MOV: gVar[i] = gVar[localBase+j] (Local → Global)
   #ljLGMOVS     ; LG MOVS: string variant
   #ljLGMOVF     ; LG MOVF: float variant
   #ljLLMOV      ; LL MOV: gVar[localBase+i] = gVar[localBase+j] (Local → Local)
   #ljLLMOVS     ; LL MOVS: string variant
   #ljLLMOVF     ; LL MOVF: float variant

   ;- In-place increment/decrement opcodes (unified for all variables)
   #ljINC_VAR        ; Increment variable in place (no stack operation)
   #ljDEC_VAR        ; Decrement variable in place (no stack operation)
   #ljINC_VAR_PRE    ; Pre-increment: increment and push new value
   #ljDEC_VAR_PRE    ; Pre-decrement: decrement and push new value
   #ljINC_VAR_POST   ; Post-increment: push old value and increment
   #ljDEC_VAR_POST   ; Post-decrement: push old value and decrement

   ;- DEPRECATED: Local increment/decrement opcodes (kept for compatibility)
   #ljLINC_VAR       ; DEPRECATED - Use #ljINC_VAR with unified slot calculation
   #ljLDEC_VAR       ; DEPRECATED - Use #ljDEC_VAR with unified slot calculation
   #ljLINC_VAR_PRE   ; DEPRECATED - Use #ljINC_VAR_PRE with unified slot calculation
   #ljLDEC_VAR_PRE   ; DEPRECATED - Use #ljDEC_VAR_PRE with unified slot calculation
   #ljLINC_VAR_POST  ; DEPRECATED - Use #ljINC_VAR_POST with unified slot calculation
   #ljLDEC_VAR_POST  ; DEPRECATED - Use #ljDEC_VAR_POST with unified slot calculation

   ;- Pointer increment/decrement opcodes (V1.20.36: pointer arithmetic)
   #ljPTRINC         ; Increment pointer by sizeof(basetype) (no stack operation)
   #ljPTRDEC         ; Decrement pointer by sizeof(basetype) (no stack operation)
   #ljPTRINC_PRE     ; Pre-increment pointer: increment and push new value
   #ljPTRDEC_PRE     ; Pre-decrement pointer: decrement and push new value
   #ljPTRINC_POST    ; Post-increment pointer: push old value and increment
   #ljPTRDEC_POST    ; Post-decrement pointer: push old value and decrement

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
   #PTR_ARRAY_INT = 4      ; Pointer to integer array element
   #PTR_ARRAY_FLOAT = 5    ; Pointer to float array element
   #PTR_ARRAY_STRING = 6   ; Pointer to string array element
   #PTR_FUNCTION = 7       ; Pointer to function (PC address)
   #PTR_STRUCT = 8         ; V1.022.54: Pointer to struct (base slot in ptr field)
EndEnumeration

; Runtime value arrays - separated by type for maximum VM performance
Structure stVarMeta  ; Compile-time metadata and constant values
   name.s
   flags.w
   paramOffset.i        ; -1 = global variable (use varSlot directly)
                        ; >= 0 = local variable (offset from localSlotStart)
                        ; Used at runtime to compute: actualSlot = localSlotStart + paramOffset
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

Macro          ASMLine(obj,show)
   CompilerIf show = 1
      line = RSet( Str( i + 1 ), 9 ) + "  "
   CompilerElse
      line = RSet( Str( ListIndex(obj) ), 9 ) + "  "
   CompilerEndIf
   
   line + LSet( gszATR( obj\code )\s, 30 ) + "  "
   temp = "" : flag = 0
   
   If obj\code = #ljJMP Or obj\code = #ljJZ
      CompilerIf show
         ; V1.023.20: Fix target display to be 1-indexed (matching line numbers)
         line + "  (" +Str(obj\i) + ") " + Str(i+1+obj\i)
      CompilerElse
         line + "  (" +Str(obj\i) + ") " + Str(ListIndex(obj)+1+obj\i)
      CompilerEndIf
   ElseIf obj\code = #ljCall
      CompilerIf show
         ; V1.023.20: Fix target display to be 1-indexed (matching line numbers)
         line + "  (" +Str(obj\i) + ") " + Str(i+1+obj\i) + " [nParams=" + Str(obj\j) + " nLocals=" + Str(obj\n) + " nArrays=" + Str(obj\ndx) + "]"
      CompilerElse
         line + "  (" +Str(obj\i) + ") " + Str(ListIndex(obj)+1+obj\i) + " [nParams=" + Str(obj\j) + " nLocals=" + Str(obj\n) + " nArrays=" + Str(obj\ndx) + "]"
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
   ; Local variable STORE operations - show paramOffset
   ; V1.023.21: Added PLSTORE to display
   ElseIf obj\code = #ljLSTORE Or obj\code = #ljLSTORES Or obj\code = #ljLSTOREF Or obj\code = #ljPLSTORE
      ; V1.023.31: Don't use sp-1 for value display - sp is runtime, not compile-time
      line + "[sp] --> [LOCAL[" + Str(obj\i) + "]]"
      flag + 1
   ; Local variable FETCH operations - show paramOffset
   ElseIf obj\code = #ljLFETCH Or obj\code = #ljLFETCHS Or obj\code = #ljLFETCHF
      line + "[LOCAL[" + Str(obj\i) + "]] --> [sp]"
      flag + 1
   ; Local variable MOV operations - show both indices
   ElseIf obj\code = #ljLMOV Or obj\code = #ljLMOVS Or obj\code = #ljLMOVF
      line + "[slot" + Str(obj\j) + "] --> [LOCAL[" + Str(obj\i) + "]]"
      flag + 1
   ; In-place increment/decrement operations
   ElseIf obj\code = #ljINC_VAR Or obj\code = #ljDEC_VAR Or obj\code = #ljINC_VAR_PRE Or obj\code = #ljDEC_VAR_PRE Or obj\code = #ljINC_VAR_POST Or obj\code = #ljDEC_VAR_POST
      line + "[" + gVarMeta(obj\i)\name + "]"
      flag + 1
   ElseIf obj\code = #ljLINC_VAR Or obj\code = #ljLDEC_VAR Or obj\code = #ljLINC_VAR_PRE Or obj\code = #ljLDEC_VAR_PRE Or obj\code = #ljLINC_VAR_POST Or obj\code = #ljLDEC_VAR_POST
      line + "[LOCAL[" + Str(obj\i) + "]]"
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
   ElseIf obj\code = #ljNEGATE Or obj\code = #ljNOT 
      flag + 1
      line  + "  op (sp - 1)"
   ElseIf obj\code <> #ljHALT And obj\code <> #ljreturn And obj\code <> #ljreturnF And obj\code <> #ljreturnS
      line  + "   (sp - 2) -- (sp - 1)"
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
   (gStack(gStackDepth)\localSlotStart + offset)
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
   Data.s   "LINC_VAR_PRE"
   Data.i   0, 0
   Data.s   "LDEC_VAR_PRE"
   Data.i   0, 0
   Data.s   "LINC_VAR_POST"
   Data.i   0, 0
   Data.s   "LDEC_VAR_POST"
   Data.i   0, 0

   ; Pointer increment/decrement opcodes (V1.20.36)
   Data.s   "PTRINC"
   Data.i   0, 0
   Data.s   "PTRDEC"
   Data.i   0, 0
   Data.s   "PTRINC_PRE"
   Data.i   0, 0
   Data.s   "PTRDEC_PRE"
   Data.i   0, 0
   Data.s   "PTRINC_POST"
   Data.i   0, 0
   Data.s   "PTRDEC_POST"
   Data.i   0, 0

   ; In-place compound assignment opcodes
   Data.s   "ADD_ASSVAR"
   Data.i   0, 0
   Data.s   "SUB_ASSVAR"         ; ASS = ASSIGN
   Data.i   0, 0
   Data.s   "MUL_ASSVAR"
   Data.i   0, 0
   Data.s   "DIV_ASSVAR"
   Data.i   0, 0
   Data.s   "MOD_ASSVAR"
   Data.i   0, 0
   Data.s   "FLADD_ASSVAR"
   Data.i   0, 0
   Data.s   "FLSUB_ASSVAR"
   Data.i   0, 0
   Data.s   "FLMUL_ASSVAR"
   Data.i   0, 0
   Data.s   "FLDIV_ASSVAR"
   Data.i   0, 0
   Data.s   "PTRADD_ASSIGN"
   Data.i   0, 0
   Data.s   "PTRSUB_ASSIGN"
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

   ; Specialized array fetch opcodes (no runtime branching)
   Data.s   "GFETCHARINT_O"
   Data.i   0, 0
   Data.s   "GFETCHARINT_K"
   Data.i   0, 0
   Data.s   "LFETCHARINT_O"
   Data.i   0, 0
   Data.s   "LFETCHARINT_K"
   Data.i   0, 0
   Data.s   "GFETCHARFLT_O"
   Data.i   0, 0
   Data.s   "GFETCHARFLT_K"
   Data.i   0, 0
   Data.s   "LFETCHARFLT_O"
   Data.i   0, 0
   Data.s   "LFETCHARFLT_K"
   Data.i   0, 0
   Data.s   "GFETCHARSTR_O"
   Data.i   0, 0
   Data.s   "GFETCHARSTR_K"
   Data.i   0, 0
   Data.s   "LFETCHARSTR_O"
   Data.i   0, 0
   Data.s   "LFETCHARSTR_K"
   Data.i   0, 0

   ; Specialized array store opcodes (no runtime branching)
   Data.s   "GISTOREAR_OO"
   Data.i   0, 0
   Data.s   "GISTOREAR_OS"
   Data.i   0, 0
   Data.s   "GISTOREAR_SO"
   Data.i   0, 0
   Data.s   "GISTOREAR_SS"
   Data.i   0, 0
   Data.s   "LISTOREAR_OO"
   Data.i   0, 0
   Data.s   "LISTOREAR_OS"
   Data.i   0, 0
   Data.s   "LISTOREAR_SO"
   Data.i   0, 0
   Data.s   "LISTOREAR_SS"
   Data.i   0, 0
   Data.s   "GFSTOREAR_OO"
   Data.i   0, 0
   Data.s   "GFSTOREAR_OS"
   Data.i   0, 0
   Data.s   "GFSTOREAR_SO"
   Data.i   0, 0
   Data.s   "GFSTOREAR_SS"
   Data.i   0, 0
   Data.s   "LFSTOREAR_OO"
   Data.i   0, 0
   Data.s   "LFSTOREAR_OS"
   Data.i   0, 0
   Data.s   "LFSTOREAR_SO"
   Data.i   0, 0
   Data.s   "LFSTOREAR_SS"
   Data.i   0, 0
   Data.s   "GSSTOREAR_OO"
   Data.i   0, 0
   Data.s   "GSSTOREAR_OS"
   Data.i   0, 0
   Data.s   "GSSTOREAR_SO"
   Data.i   0, 0
   Data.s   "GSSTOREAR_SS"
   Data.i   0, 0
   Data.s   "LSSTOREAR_OO"
   Data.i   0, 0
   Data.s   "LSSTOREAR_OS"
   Data.i   0, 0
   Data.s   "LSSTOREAR_SO"
   Data.i   0, 0
   Data.s   "LSSTOREAR_SS"
   Data.i   0, 0

   ; V1.022.114: OPT_LOPT opcodes (global index, local value)
   Data.s   "GISTOREAR_OLO"
   Data.i   0, 0
   Data.s   "GFSTOREAR_OLO"
   Data.i   0, 0
   Data.s   "GSSTOREAR_OLO"
   Data.i   0, 0

   ; V1.022.115: LOCAL OPT_LOPT opcodes (local array, global index, local value)
   Data.s   "LISTOREAR_OLO"
   Data.i   0, 0
   Data.s   "LFSTOREAR_OLO"
   Data.i   0, 0
   Data.s   "LSSTOREAR_OLO"
   Data.i   0, 0

   ; V1.022.86: Local-Index Array Opcodes
   Data.s   "GFETCHARINT_LO"
   Data.i   0, 0
   Data.s   "GFETCHARFLT_LO"
   Data.i   0, 0
   Data.s   "GFETCHARSTR_LO"
   Data.i   0, 0
   Data.s   "GISTOREAR_LOLO"
   Data.i   0, 0
   Data.s   "GISTOREAR_LOO"
   Data.i   0, 0
   Data.s   "GISTOREAR_LOS"
   Data.i   0, 0
   Data.s   "GFSTOREAR_LOLO"
   Data.i   0, 0
   Data.s   "GFSTOREAR_LOO"
   Data.i   0, 0
   Data.s   "GFSTOREAR_LOS"
   Data.i   0, 0
   Data.s   "GSSTOREAR_LOLO"
   Data.i   0, 0
   Data.s   "GSSTOREAR_LOO"
   Data.i   0, 0
   Data.s   "GSSTOREAR_LOS"
   Data.i   0, 0

   ; V1.022.113: Local-Index Array Opcodes for LOCAL arrays
   Data.s   "LFETCHARINT_LO"
   Data.i   0, 0
   Data.s   "LFETCHARFLT_LO"
   Data.i   0, 0
   Data.s   "LFETCHARSTR_LO"
   Data.i   0, 0
   Data.s   "LISTOREAR_LOLO"
   Data.i   0, 0
   Data.s   "LISTOREAR_LOO"
   Data.i   0, 0
   Data.s   "LISTOREAR_LOS"
   Data.i   0, 0
   Data.s   "LFSTOREAR_LOLO"
   Data.i   0, 0
   Data.s   "LFSTOREAR_LOO"
   Data.i   0, 0
   Data.s   "LFSTOREAR_LOS"
   Data.i   0, 0
   Data.s   "LSSTOREAR_LOLO"
   Data.i   0, 0
   Data.s   "LSSTOREAR_LOO"
   Data.i   0, 0
   Data.s   "LSSTOREAR_LOS"
   Data.i   0, 0

   ; Pointer operations
   Data.s   "GETADDR"
   Data.i   0, 0
   Data.s   "GETADDRF"
   Data.i   0, 0
   Data.s   "GETADDRS"
   Data.i   0, 0
   Data.s   "PTRFETCH"
   Data.i   #ljPTRFETCH_FLOAT, #ljPTRFETCH_STR
   Data.s   "IPTRFETCH"
   Data.i   0, 0
   Data.s   "FPTRFETCH"
   Data.i   0, 0
   Data.s   "SPTRFETCH"
   Data.i   0, 0
   Data.s   "PTRSTORE"
   Data.i   #ljPTRSTORE_FLOAT, #ljPTRSTORE_STR
   Data.s   "IPTRSTORE"
   Data.i   0, 0
   Data.s   "FPTRSTORE"
   Data.i   0, 0
   Data.s   "SPTRSTORE"
   Data.i   0, 0
   Data.s   "PTRFIELD_I"
   Data.i   0, 0
   Data.s   "PTRFIELD_F"
   Data.i   0, 0
   Data.s   "PTRFIELD_S"
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
   Data.s   "GETFUNCADDR"
   Data.i   0, 0
   Data.s   "CALLFUNCPTR"
   Data.i   0, 0

   ; Array pointer opcodes
   Data.s   "GETARRAYADDR"
   Data.i   0, 0
   Data.s   "GETARRAYADDRF"
   Data.i   0, 0
   Data.s   "GETARRAYADDRS"
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

   ; V1.021.0: Structure support
   Data.s   "STRUCT"
   Data.i   0, 0
   Data.s   "STRUCTFIELD"
   Data.i   0, 0
   Data.s   "STRUCTINIT"
   Data.i   0, 0

   ; V1.022.0: Struct array field opcodes
   Data.s   "SARFETCH_I_OK"
   Data.i   0, 0
   Data.s   "SARFETCH_F"
   Data.i   0, 0
   Data.s   "SARFETCH_S"
   Data.i   0, 0
   Data.s   "SARSTORE_I"
   Data.i   0, 0
   Data.s   "SARSTORE_F"
   Data.i   0, 0
   Data.s   "SARSTORE_S"
   Data.i   0, 0

   ; V1.022.44: Array of structs opcodes
   Data.s   "AOSFETCH_I"
   Data.i   0, 0
   Data.s   "AOSFETCH_F"
   Data.i   0, 0
   Data.s   "AOSFETCH_S"
   Data.i   0, 0
   Data.s   "AOSSTORE_I"
   Data.i   0, 0
   Data.s   "AOSSTORE_F"
   Data.i   0, 0
   Data.s   "AOSSTORE_S"
   Data.i   0, 0

   ; V1.022.118: ARRAYOFSTRUCT LOPT opcodes (index from local slot)
   Data.s   "AOSFETCH_I_LO"
   Data.i   0, 0
   Data.s   "AOSFETCH_F_LO"
   Data.i   0, 0
   Data.s   "AOSFETCH_S_LO"
   Data.i   0, 0
   Data.s   "AOSSTORE_I_LO"
   Data.i   0, 0
   Data.s   "AOSSTORE_F_LO"
   Data.i   0, 0
   Data.s   "AOSSTORE_S_LO"
   Data.i   0, 0

   ; V1.022.54: Struct pointer opcodes
   Data.s   "GETSADDR"
   Data.i   0, 0
   Data.s   "PSFETCH_I"
   Data.i   0, 0
   Data.s   "PSFETCH_F"
   Data.i   0, 0
   Data.s   "PSFETCH_S"
   Data.i   0, 0
   Data.s   "PSSTORE_I"
   Data.i   0, 0
   Data.s   "PSSTORE_F"
   Data.i   0, 0
   Data.s   "PSSTORE_S"
   Data.i   0, 0

   ; V1.022.117: PTRSTRUCTSTORE LOPT opcodes (value from local slot)
   Data.s   "PSSTORE_I_LO"
   Data.i   0, 0
   Data.s   "PSSTORE_F_LO"
   Data.i   0, 0
   Data.s   "PSSTORE_S_LO"
   Data.i   0, 0

   ; V1.022.119: PTRSTRUCTFETCH LPTR opcodes (pointer from local slot)
   Data.s   "PSFETCH_I_LP"
   Data.i   0, 0
   Data.s   "PSFETCH_F_LP"
   Data.i   0, 0
   Data.s   "PSFETCH_S_LP"
   Data.i   0, 0

   ; V1.022.119: PTRSTRUCTSTORE LPTR opcodes (pointer from local slot)
   Data.s   "PSSTORE_I_LP"
   Data.i   0, 0
   Data.s   "PSSTORE_F_LP"
   Data.i   0, 0
   Data.s   "PSSTORE_S_LP"
   Data.i   0, 0

   ; V1.022.119: PTRSTRUCTSTORE LPTR_LOPT opcodes (both pointer and value from local)
   Data.s   "PSSTORE_I_LP_LO"
   Data.i   0, 0
   Data.s   "PSSTORE_F_LP_LO"
   Data.i   0, 0
   Data.s   "PSSTORE_S_LP_LO"
   Data.i   0, 0

   ; V1.022.64: Array resize opcode
   Data.s   "ARRESIZE"
   Data.i   0, 0

   ; V1.022.65: Struct copy opcode
   Data.s   "SCOPY"
   Data.i   0, 0

   Data.s   "EOF"
   Data.i   0, 0
   Data.s   "-"
EndDataSection

; IDE Options = PureBasic 6.21 (Windows - x64)
; CursorPosition = 42
; FirstLine = 21
; Folding = --
; Optimizer
; EnableAsm
; EnableThread
; EnableXP
; SharedUCRT
; CPU = 1
; EnablePurifier
; EnableCompileCount = 24
; EnableBuildCount = 0
; EnableExeConstant