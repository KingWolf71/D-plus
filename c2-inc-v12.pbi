
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

Enumeration
   #C2HOLE_START
   #C2HOLE_DEFAULT
   #C2HOLE_PAIR
   #C2HOLE_BLIND
EndEnumeration

Enumeration
   #ljUNUSED
   #ljIDENT
   #ljINT
   #ljFLOAT
   #ljSTRING
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

   ;- DEPRECATED: Local Variable Opcodes (kept for compatibility, V1.18.0)
   ; These opcodes are DEPRECATED as of v1.18.0 - use unified FETCH/STORE/MOV instead
   ; They are kept defined to avoid breaking existing code/postprocessor/modules
   ; The VM procedures still exist but should not be used for new code
   #ljLMOV       ; DEPRECATED - Use #ljMOV with unified slot calculation
   #ljLMOVS      ; DEPRECATED - Use #ljMOVS with unified slot calculation
   #ljLMOVF      ; DEPRECATED - Use #ljMOVF with unified slot calculation
   #ljLFETCH     ; DEPRECATED - Use #ljFetch with unified slot calculation
   #ljLFETCHS    ; DEPRECATED - Use #ljFETCHS with unified slot calculation
   #ljLFETCHF    ; DEPRECATED - Use #ljFETCHF with unified slot calculation
   #ljLSTORE     ; DEPRECATED - Use #ljStore with unified slot calculation
   #ljLSTORES    ; DEPRECATED - Use #ljSTORES with unified slot calculation
   #ljLSTOREF    ; DEPRECATED - Use #ljSTOREF with unified slot calculation

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

;- Globals

Global Dim           gszATR.stATR(#C2TOKENCOUNT)
Global Dim           gVarMeta.stVarMeta(#C2MAXCONSTANTS)  ; Compile-time info only
Global Dim           gFuncLocalArraySlots.i(512, 15)  ; [functionID, localArrayIndex] -> varSlot (initial size, Dim'd to exact size during FixJMP)
Global Dim           arCode.stCodeIns(1)
Global NewMap        mapPragmas.s()

Global               gnLastVariable.i
Global               gnGlobalVariables.i  ; V1.020.057: Count of global variables only (for stack calculation)
Global               gnTotalTokens.i
Global               gPtrFetchExpectedType.w  ; V1.20.5: Expected type for PTRFETCH (0=use generic)

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
         line + "  (" +Str(obj\i) + ") " + Str(i+obj\i)
      CompilerElse
         line + "  (" +Str(obj\i) + ") " + Str(ListIndex(obj)+obj\i)
      CompilerEndIf
   ElseIf obj\code = #ljCall
      CompilerIf show
         line + "  (" +Str(obj\i) + ") " + Str(i+obj\i) + " [nParams=" + Str(obj\j) + " nLocals=" + Str(obj\n) + "]"
      CompilerElse
         line + "  (" +Str(obj\i) + ") " + Str(ListIndex(obj)+obj\i) + " [nParams=" + Str(obj\j) + " nLocals=" + Str(obj\n) + "]"
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
   ElseIf obj\code = #ljMOV
      _ASMLineHelper1( show, obj\j )
      line + "[" + gVarMeta( obj\j )\name + temp + "] --> [" + gVarMeta( obj\i )\name + "]"
      flag + 1
   ElseIf obj\code = #ljSTORE
      _ASMLineHelper1( show, sp - 1 )
      line + "[sp" + temp + "] --> [" + gVarMeta( obj\i )\name + "]"
      flag + 1
   ; Local variable STORE operations - show paramOffset
   ElseIf obj\code = #ljLSTORE Or obj\code = #ljLSTORES Or obj\code = #ljLSTOREF
      _ASMLineHelper1( show, sp - 1 )
      line + "[sp" + temp + "] --> [LOCAL[" + Str(obj\i) + "]]"
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
      _ASMLineHelper1( show, sp - 1 )
      line + "[" + gVarMeta(obj\i)\name + " OP= sp" + temp + "]"
      flag + 1
   ElseIf obj\code = #ljPUSH Or obj\code = #ljFetch Or obj\code = #ljPUSHS Or obj\code = #ljPUSHF
      flag + 1
      _ASMLineHelper1( 0, obj\i )
      If gVarMeta( obj\i )\flags & #C2FLAG_IDENT
         line + "[" + gVarMeta( obj\i )\name + "] --> [sp]"
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
   Data.i   #ljFLOATLE, 0
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

   Data.s   "EOF"
   Data.i   0, 0
   Data.s   "-"
EndDataSection

; IDE Options = PureBasic 6.21 (Windows - x64)
; CursorPosition = 42
; FirstLine = 33
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