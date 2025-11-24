# Pointer Implementation Design for LJ2 Language
Version: 1.0
Date: 2025

## Overview
This document outlines the design for implementing pointers in the LJ2 language, including pointer types, operations, arrays of pointers, and function pointers.

## 1. Pointer Types

### 1.1 Basic Syntax
Pointers are declared using the `*` suffix after the type:
- `int* ptr` - pointer to integer
- `float* fptr` - pointer to float
- `string* sptr` - pointer to string

### 1.2 Internal Representation
Since LJ2 uses a slot-based VM (gVar array), pointers are represented as **slot indices** rather than memory addresses:
- A pointer stores the slot index of the variable it points to
- Pointer values are stored in the `.i` (integer) field of stVT structure
- Type information is tracked separately in gVarMeta for type safety

### 1.3 Flag Addition
New flag in c2-inc-v12.pbi:
```purebasic
#C2FLAG_POINTER = 256  ; Variable is a pointer type
```

## 2. Pointer Operations

### 2.1 Address-of Operator (&)
Returns the slot index of a variable:
```c
int x = 42;
int* ptr = &x;  // ptr now contains the slot index of x
```

VM Operation: `GETADDR`
- Input: Variable slot index
- Output: Push slot index to stack
- Implementation: Simply pushes the slot index as an integer value

### 2.2 Dereference Operator (*)
Accesses the value at the pointed-to slot:
```c
int* ptr = &x;
int value = *ptr;  // Read value from slot pointed to by ptr
*ptr = 100;        // Write value to slot pointed to by ptr
```

VM Operations:
- `PTRFETCH` - Fetch value from pointed-to slot
- `PTRSTORE` - Store value to pointed-to slot

Both operations need type-specific variants:
- `PTRFETCH_INT`, `PTRFETCH_FLOAT`, `PTRFETCH_STR`
- `PTRSTORE_INT`, `PTRSTORE_FLOAT`, `PTRSTORE_STR`

### 2.3 Pointer Arithmetic
Pointers can be incremented/decremented for array traversal:
```c
int arr[10];
int* ptr = &arr[0];
ptr + 1;  // Advance to next array element
```

VM Operations:
- `PTRADD` - Add integer to pointer (for array indexing)
- `PTRSUB` - Subtract integer from pointer

### 2.4 Null Pointers
A pointer with value -1 represents null:
```c
int* ptr = null;  // Internally: ptr->i = -1
```

## 3. Arrays of Pointers

### 3.1 Syntax
Arrays of pointers use `*[]` suffix:
```c
int*[10] ptrs;     // Array of 10 integer pointers
string*[5] names;  // Array of 5 string pointers
```

### 3.2 Internal Representation
- Each array element stores a slot index (pointer value)
- Array elements are stored in the `dta\ar[]` structure
- Each element's `.i` field contains the slot index

### 3.3 Usage Example
```c
int a = 10, b = 20, c = 30;
int*[3] ptrs;
ptrs[0] = &a;
ptrs[1] = &b;
ptrs[2] = &c;
*ptrs[1] = 25;  // Modify b through pointer
```

## 4. Function Pointers

### 4.1 Syntax
Function pointers store the PC address of a function:
```c
int (*funcptr)(int, int);  // Pointer to function taking 2 ints, returning int
funcptr = &add;            // Get address of add function
int result = (*funcptr)(5, 3);  // Call through pointer
```

Alternative simpler syntax (C-style optional dereference):
```c
int result = funcptr(5, 3);  // Same as (*funcptr)(5, 3)
```

### 4.2 Internal Representation
- Function pointer stores PC address (bytecode address) in `.i` field
- Function metadata (parameter count, return type) stored in gFuncMeta map
- Type signature verified at compile time

### 4.3 VM Operations
- `GETFUNCADDR` - Get PC address of function
- `CALLFUNCPTR` - Call function through pointer

### 4.4 Function Pointer Arrays
```c
int (*ops[4])(int, int);  // Array of 4 function pointers
ops[0] = &add;
ops[1] = &sub;
ops[2] = &mul;
ops[3] = &div;
int result = ops[2](10, 5);  // Calls mul(10, 5)
```

## 5. New VM Opcodes

### 5.1 Enumeration Additions (c2-inc-v12.pbi)
```purebasic
; Pointer operations
#ljGETADDR          ; Get address of variable (&var)
#ljPTRFETCH         ; Generic pointer fetch
#ljPTRFETCH_INT     ; Fetch int through pointer
#ljPTRFETCH_FLOAT   ; Fetch float through pointer
#ljPTRFETCH_STR     ; Fetch string through pointer
#ljPTRSTORE         ; Generic pointer store
#ljPTRSTORE_INT     ; Store int through pointer
#ljPTRSTORE_FLOAT   ; Store float through pointer
#ljPTRSTORE_STR     ; Store string through pointer
#ljPTRADD           ; Pointer arithmetic: ptr + offset
#ljPTRSUB           ; Pointer arithmetic: ptr - offset

; Function pointer operations
#ljGETFUNCADDR      ; Get function PC address
#ljCALLFUNCPTR      ; Call function through pointer
```

### 5.2 VM Procedure Signatures

#### C2GETADDR()
```purebasic
Procedure C2GETADDR()
   ; _AR()\i = variable slot to get address of
   vm_DebugFunctionName()
   gVar(sp)\i = _AR()\i
   sp + 1
   pc + 1
EndProcedure
```

#### C2PTRFETCH_INT()
```purebasic
Procedure C2PTRFETCH_INT()
   ; Top of stack contains pointer (slot index)
   Protected slot.i
   vm_DebugFunctionName()
   sp - 1
   slot = gVar(sp)\i
   If slot < 0 Or slot >= #C2MAXCONSTANTS
      Debug "NULL or invalid pointer dereference at pc=" + Str(pc)
      gExitApplication = #True
      ProcedureReturn
   EndIf
   gVar(sp)\i = gVar(slot)\i
   sp + 1
   pc + 1
EndProcedure
```

#### C2PTRSTORE_INT()
```purebasic
Procedure C2PTRSTORE_INT()
   ; Stack: [value] [pointer]
   Protected slot.i, value.i
   vm_DebugFunctionName()
   sp - 1
   slot = gVar(sp)\i
   sp - 1
   value = gVar(sp)\i
   If slot < 0 Or slot >= #C2MAXCONSTANTS
      Debug "NULL or invalid pointer dereference at pc=" + Str(pc)
      gExitApplication = #True
      ProcedureReturn
   EndIf
   gVar(slot)\i = value
   pc + 1
EndProcedure
```

#### C2PTRADD()
```purebasic
Procedure C2PTRADD()
   ; Stack: [pointer] [offset]
   ; Result: pointer + offset
   Protected ptr.i, offset.i
   vm_DebugFunctionName()
   sp - 1
   offset = gVar(sp)\i
   sp - 1
   ptr = gVar(sp)\i
   gVar(sp)\i = ptr + offset
   sp + 1
   pc + 1
EndProcedure
```

#### C2GETFUNCADDR()
```purebasic
Procedure C2GETFUNCADDR()
   ; _AR()\i = function ID from gFuncMeta
   Protected funcId.i, funcPc.i
   vm_DebugFunctionName()
   funcId = _AR()\i
   funcPc = gFuncMeta(Str(funcId))\pc
   gVar(sp)\i = funcPc
   sp + 1
   pc + 1
EndProcedure
```

#### C2CALLFUNCPTR()
```purebasic
Procedure C2CALLFUNCPTR()
   ; _AR()\j = parameter count
   ; Top of stack contains function PC address
   ; Similar to C2CALL but gets PC from stack instead of instruction
   Protected funcPc.i
   vm_DebugFunctionName()
   sp - 1
   funcPc = gVar(sp)\i
   ; ... rest similar to C2CALL implementation
EndProcedure
```

## 6. Parser and Scanner Changes

### 6.1 Token Additions
- Detect `*` as pointer declarator (context-sensitive: declaration vs multiplication)
- Detect `&` as address-of operator (not bitwise AND in this context)
- Handle `*` as dereference operator in expressions

### 6.2 Type Parsing
Modify type parser to recognize pointer syntax:
- `int*` → Type: INT, Flags: #C2FLAG_INT | #C2FLAG_POINTER
- `float*[]` → Type: FLOAT, Flags: #C2FLAG_FLOAT | #C2FLAG_POINTER | #C2FLAG_ARRAY

### 6.3 Expression Parsing
- Parse `&variable` as address-of operation
- Parse `*pointer` as dereference operation
- Handle pointer arithmetic: `ptr + 1`, `ptr - 3`

## 7. Code Generator Changes

### 7.1 Address-of Operation
When encountering `&variable`:
1. Look up variable slot index
2. Generate `GETADDR` opcode with slot index
3. Result is pushed to stack

### 7.2 Dereference Operation
When encountering `*pointer`:
1. Generate code to evaluate pointer expression (pushes slot index to stack)
2. Generate appropriate `PTRFETCH_*` opcode based on pointer target type
3. Result is value from pointed-to slot

### 7.3 Pointer Assignment
For `*ptr = value`:
1. Generate code to evaluate `value` (push to stack)
2. Generate code to evaluate `ptr` (push slot index to stack)
3. Generate appropriate `PTRSTORE_*` opcode based on type

## 8. Postprocessor Changes

### 8.1 Type Inference
- Track pointer types through expressions
- Ensure type safety for pointer operations
- Validate pointer arithmetic (only on array element pointers)

### 8.2 Function Pointer Validation
- Verify function pointer signatures match call sites
- Check parameter counts and types

## 9. Example Programs

### 9.1 Basic Pointer Usage
```c
int x = 42;
int* ptr = &x;
print(*ptr);  // Output: 42
*ptr = 100;
print(x);     // Output: 100
```

### 9.2 Pointer Arithmetic with Arrays
```c
int arr[5];
arr[0] = 10;
arr[1] = 20;
arr[2] = 30;

int* ptr = &arr[0];
print(*ptr);      // Output: 10
ptr + 1;
print(*ptr);      // Output: 20
```

### 9.3 Array of Pointers
```c
int a = 1, b = 2, c = 3;
int*[3] ptrs;
ptrs[0] = &a;
ptrs[1] = &b;
ptrs[2] = &c;

int i = 0;
while i < 3 {
    print(*ptrs[i]);
    i + 1;
}
// Output: 1 2 3
```

### 9.4 Function Pointers
```c
int add(int a, int b) {
    return a + b;
}

int sub(int a, int b) {
    return a - b;
}

int (*operation)(int, int);
operation = &add;
print(operation(5, 3));  // Output: 8

operation = &sub;
print(operation(5, 3));  // Output: 2
```

### 9.5 Array of Function Pointers (Calculator)
```c
int add(int a, int b) { return a + b; }
int sub(int a, int b) { return a - b; }
int mul(int a, int b) { return a * b; }
int div(int a, int b) { return a / b; }

int (*ops[4])(int, int);
ops[0] = &add;
ops[1] = &sub;
ops[2] = &mul;
ops[3] = &div;

int choice = 2;  // Multiply
print(ops[choice](10, 5));  // Output: 50
```

## 10. Implementation Priority

1. **Phase 1**: Basic pointer operations (HIGH)
   - Add pointer flag and types
   - Implement GETADDR, PTRFETCH_*, PTRSTORE_*
   - Update parser for `&` and `*` operators

2. **Phase 2**: Pointer arithmetic (MEDIUM)
   - Implement PTRADD, PTRSUB
   - Support array traversal with pointers

3. **Phase 3**: Arrays of pointers (MEDIUM)
   - Extend array system to support pointer element types
   - Test with various pointer types

4. **Phase 4**: Function pointers (HIGH)
   - Implement GETFUNCADDR, CALLFUNCPTR
   - Support function pointer variables and calls

5. **Phase 5**: Advanced features (LOW)
   - Null pointer checks
   - Pointer-to-pointer support
   - Complex function pointer scenarios

## 11. Testing Strategy

Each phase should include:
- Unit tests for new VM opcodes
- Integration tests for parser/codegen changes
- End-to-end tests with example programs
- Edge case testing (null pointers, bounds checking, type mismatches)

## 12. Performance Considerations

- Pointer operations should be as fast as direct variable access (1-2 extra instructions max)
- Function pointer calls should have minimal overhead vs direct calls
- No additional memory overhead for pointer variables (reuse existing stVT structure)

---
End of Design Document
