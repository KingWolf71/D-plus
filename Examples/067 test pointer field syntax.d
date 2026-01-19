/* Pointer Field Syntax Test (V1.20.22)
   Tests the new ptr\i, ptr\f, ptr\s syntax for pointer access

   New Syntax:
     ptr\i = value;   // Store integer through pointer
     ptr\f = value;   // Store float through pointer
     ptr\s = value;   // Store string through pointer
     val = ptr\i;     // Read integer through pointer
     val = ptr\f;     // Read float through pointer
     val = ptr\s;     // Read string through pointer

   This is equivalent to the old *ptr syntax but with explicit typing:
     Old: *ptr = value;  (requires postprocessor to determine type)
     New: ptr\i = value; (type known at compile time)
*/

#pragma appname "Pointer-Field-Syntax-Test"
#pragma decimals 3
#pragma console on
#pragma consolesize "680x740"
#pragma consoleposition "30,50"
#pragma ListASM on
#pragma FastPrint on
#pragma RunThreaded on
#pragma ftoi "truncate"
#pragma version on
#pragma modulename on
#pragma PasteToClipboard on
#pragma floattolerance 0.0001
#pragma GlobalStack 1024
#pragma FunctionStack 32
#pragma EvalStack 256
#pragma LocalStack 64
#pragma CreateLog off
#pragma DefaultFPS 32
#pragma ThreadKillWait 1800
#pragma asmdecimal on

print("=== POINTER FIELD SYNTAX TEST (V1.20.22) ===");
print("");

// =============================================================================
// TEST 1: Integer Pointer Field Access (ptr\i)
// =============================================================================
print("TEST 1: Integer Pointer Field Access (ptr\\i)");
print("--------------------------------------------");

intVal = 42;
intPtr = &intVal;

print("  Initial: intVal = ", intVal, "");
print("  Read via ptr\\i: ", intPtr\i, " (expected 42)");
assertEqual(42, intPtr\i);

// Modify through pointer field
intPtr\i = 100;
print("  After intPtr\\i = 100:");
print("    intVal = ", intVal, " (expected 100)");
assertEqual(100, intVal);
print("    intPtr\\i = ", intPtr\i, " (expected 100)");
assertEqual(100, intPtr\i);

print("  PASS: Integer pointer field access works!");
print("");

// =============================================================================
// TEST 2: Float Pointer Field Access (ptr\f)
// =============================================================================
print("TEST 2: Float Pointer Field Access (ptr\\f)");
print("------------------------------------------");

floatVal = 3.14;
floatPtr = &floatVal;

print("  Initial: floatVal = ", floatVal, "");
print("  Read via ptr\\f: ", floatPtr\f, " (expected 3.14)");
assertFloatEqual(3.14, floatPtr\f);

// Modify through pointer field
floatPtr\f = 2.718;
print("  After floatPtr\\f = 2.718:");
print("    floatVal = ", floatVal, " (expected 2.718)");
assertFloatEqual(2.718, floatVal);
print("    floatPtr\\f = ", floatPtr\f, " (expected 2.718)");
assertFloatEqual(2.718, floatPtr\f);

print("  PASS: Float pointer field access works!");
print("");

// =============================================================================
// TEST 3: String Pointer Field Access (ptr\s)
// =============================================================================
print("TEST 3: String Pointer Field Access (ptr\\s)");
print("-------------------------------------------");

stringVal = "Hello";
stringPtr = &stringVal;

print("  Initial: stringVal = ", stringVal, "");
print("  Read via ptr\\s: ", stringPtr\s, " (expected Hello)");
assertStringEqual("Hello", stringPtr\s);

// Modify through pointer field
stringPtr\s = "World";
print("  After stringPtr\\s = 'World':");
print("    stringVal = ", stringVal, " (expected World)");
assertStringEqual("World", stringVal);
print("    stringPtr\\s = ", stringPtr\s, " (expected World)");
assertStringEqual("World", stringPtr\s);

print("  PASS: String pointer field access works!");
print("");

// =============================================================================
// TEST 4: Pointer Field Arithmetic
// =============================================================================
print("TEST 4: Pointer Field Arithmetic");
print("--------------------------------");

a.i = 10;
b.i = 20;
ptrA = &a;
ptrB = &b;

print("  Initial: a = ", a, ", b = ", b, "");
print("  ptrA\\i = ", ptrA\i, ", ptrB\\i = ", ptrB\i, "");

// Arithmetic through pointer fields
ptrA\i = ptrA\i + ptrB\i;  // a = a + b = 10 + 20 = 30
print("  After ptrA\\i = ptrA\\i + ptrB\\i:");
print("    a = ", a, " (expected 30)");
assertEqual(30, a);

ptrB\i = ptrB\i * 2;  // b = b * 2 = 20 * 2 = 40
print("  After ptrB\\i = ptrB\\i * 2:");
print("    b = ", b, " (expected 40)");
assertEqual(40, b);

print("  PASS: Pointer field arithmetic works!");
print("");

// =============================================================================
// TEST 5: Mixed Type Pointer Fields
// =============================================================================
print("TEST 5: Mixed Type Pointer Fields");
print("---------------------------------");

x.i = 100;
y.f = 50.5;
z = "Test";

ptrX = &x;
ptrY = &y;
ptrZ = &z;

print("  Initial values:");
print("    x = ", x, " (int)");
print("    y = ", y, " (float)");
print("    z = ", z, " (string)");
print("");

print("  Access via pointer fields:");
print("    ptrX\\i = ", ptrX\i, " (expected 100)");
assertEqual(100, ptrX\i);
print("    ptrY\\f = ", ptrY\f, " (expected 50.5)");
assertFloatEqual(50.5, ptrY\f);
print("    ptrZ\\s = ", ptrZ\s, " (expected Test)");
assertStringEqual("Test", ptrZ\s);

// Modify all through pointer fields
ptrX\i = 200;
ptrY\f = 99.9;
ptrZ\s = "Modified";

print("  After modification:");
print("    x = ", x, " (expected 200)");
assertEqual(200, x);
print("    y = ", y, " (expected 99.9)");
assertFloatEqual(99.9, y);
print("    z = ", z, " (expected Modified)");
assertStringEqual("Modified", z);

print("  PASS: Mixed type pointer fields work!");
print("");

// =============================================================================
// TEST 6: Pointer Field with Array Elements
// =============================================================================
print("TEST 6: Pointer Field with Array Elements");
print("-----------------------------------------");

array nums[5];
nums[0] = 10;
nums[1] = 20;
nums[2] = 30;
nums[3] = 40;
nums[4] = 50;

// Point to array element
elemPtr = &nums[2];

print("  Initial: nums[2] = ", nums[2], " (expected 30)");
print("  Read via elemPtr\\i: ", elemPtr\i, " (expected 30)");
assertEqual(30, elemPtr\i);

// Modify through pointer field
elemPtr\i = 999;
print("  After elemPtr\\i = 999:");
print("    nums[2] = ", nums[2], " (expected 999)");
assertEqual(999, nums[2]);

print("  PASS: Pointer field with array elements works!");
print("");

// =============================================================================
// TEST 7: Float Arithmetic with Type Conversion
// =============================================================================
print("TEST 7: Float Arithmetic with Type Conversion");
print("---------------------------------------------");

intArray = 100;
ptrInt = &intArray;

print("  Initial: intArray = ", intArray, " (integer)");
print("  ptrInt\\i = ", ptrInt\i, " (expected 100)");
assertEqual(100, ptrInt\i);

// Multiply by float, then convert back to int
ptrInt\i = (int)(ptrInt\i * 2.5);  // 100 * 2.5 = 250.0 -> 250

print("  After ptrInt\\i = (int)(ptrInt\\i * 2.5):");
print("    intArray = ", intArray, " (expected 250)");
assertEqual(250, intArray);

print("  PASS: Float arithmetic with type conversion works!");
print("");

print("=== ALL POINTER FIELD SYNTAX TESTS PASSED ===");
print("");
print("Summary:");
print("  - Integer pointer fields (ptr\\i): WORKING");
print("  - Float pointer fields (ptr\\f): WORKING");
print("  - String pointer fields (ptr\\s): WORKING");
print("  - Pointer field arithmetic: WORKING");
print("  - Mixed type pointer fields: WORKING");
print("  - Pointer fields with arrays: WORKING");
print("  - Type conversion with fields: WORKING");
print("");
print("The new pointer field syntax provides:");
print("  + Explicit type specification at compile time");
print("  + Clearer code (ptr\\i vs *ptr)");
print("  + Foundation for future structure field access");
print("  + Zero runtime overhead (types resolved at compile time)");
print("");
