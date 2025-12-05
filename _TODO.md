LJ2 TODO
--------------------
Created: 9/Nov/2025
Updated: 29/Nov/2025

## V1.022.101 - Complex Expression Result Type Detection (DONE)

**BUG:** Even with V1.022.100 fix for user-declared local floats like `temp.f`, synthetic temp
variables created during array assignments (`data[i] = data[j]`) were still using LSTORE instead
of LSTOREF. The float value from `data[j]` was being truncated to integer before storage.

**ROOT CAUSE:** In `GetExprSlotOrTemp()`, the Default case for complex expressions (including
array accesses) always used `#ljLSTORE` to store the result to a local temp, regardless of
whether the expression produced a float result.

**The fix:** Call `GetExprResultType(*expr)` to detect if the expression produces a float
(e.g., float array access) or string result. Use that type to emit the correct store opcode:
- `#ljLSTOREF` for float expressions
- `#ljLSTORES` for string expressions
- `#ljLSTORE` for integer expressions (default)

Also fixed the global scope case to use type-appropriate temp slots and pop opcodes.

## V1.022.100 - Token Search Using Mangled Name Instead of Original (DONE)

**BUG:** V1.022.99 fix still didn't work - local float variables using LSTORE instead of LSTOREF.

**ROOT CAUSE:** `FetchVarOffset()` was called with the MANGLED name (e.g., `partition_temp`)
but searched the TOKEN() list which contains the ORIGINAL name (e.g., `temp`). The search
never found the token, so `foundTokenTypeHint` remained 0 and type detection failed.

**The fix:** Before searching the token list, extract the original name from the mangled name.
If `text` starts with `gCurrentFunctionName + "_"`, extract the part after the prefix and use
that for the token search. This ensures we find `temp` when looking for `partition_temp`.

## V1.022.99 - Token TypeHint Fix for Local Float Variables (PARTIAL)

**BUG:** Local float variables (`temp.f = data[i]`) were using LSTORE instead of LSTOREF.

**ROOT CAUSE:** In `FetchVarOffset()`, after finding a token by name in the token list,
the code restored the TOKEN() position to where it was before the search. Then when
checking `TOKEN()\typeHint` to set the variable's type flags, it was reading from the
WRONG token (the old position, not the found token).

**The fix:** Save `TOKEN()\typeHint` and `TOKEN()\TokenType` immediately when the token
is found, BEFORE restoring the position. Then use these saved values for type detection.

**NOTE:** This fix alone was insufficient - see V1.022.100 for the complete solution.

## V1.022.98 - InitJumpTracker Function-End NOOPIF Fix (DONE)

InitJumpTracker() was skipping past NOOPIF at function ends to #ljfunction marker.
Fixed to keep pointer at NOOPIF when followed by #ljfunction/#ljHALT.

### Test Cases Needed:
- [ ] Simple if/else in middle of function (should NOT affect)
- [ ] Nested if/else blocks (should NOT affect)
- [ ] While loops with break/continue (should NOT affect)
- [ ] Nested while loops (should NOT affect)
- [ ] If at END of function without explicit return (SHOULD convert NOOP→RETURN)
- [ ] Recursive functions like quicksort (SHOULD fix infinite loop)
- [ ] Multiple functions in sequence (each function end should get implicit RETURN)

### Potential Issues to Watch:
- NOOPs in middle of functions that are JZ targets still get deleted
- Jump tracker pointers to deleted NOOPs may become invalid
- If issues found, may need to also preserve jump-target NOOPs (not just function-end ones)

---

1. DUP C2DUP (fetch x 2)
2. global and local variable pre-loading (eliminate PUSH - all values via slot references)
   - Pre-allocate constant slots before VM runs (_const5 = 5, etc.)
   - Expressions compute to temp slots ($temp = i + 1)
   - Array/struct access always uses slot refs (ndx=slot, n=slot, never -1/stack)
   - Remove stack-based value passing from array ops
3. function variable defaults
4. fetch/store store/fetch optimizations
5. Passing arrays as parameters
6. structures (IN PROGRESS)
   - [DONE] struct definition and scalar fields
   - [DONE] struct fields that are arrays (s\arr[i])
   - [TODO] arrays of structs (points: Point[10], points[i]\x)
7. direct structure / array assignment.
8. Combined pointer increment/dereference expressions
   - Support `(++ptr)\i` - pre-increment with immediate dereference
   - Support `(ptr++)\i` - post-increment with immediate dereference
   - Support `(--ptr)\i` and `(ptr--)\i` - decrement variants
   - Currently requires separate statements: `++ptr; val = ptr\i;`