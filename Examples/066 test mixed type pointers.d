/* Mixed-Type Pointer Arrays Test - V1.20.26+
   Tests arrays containing pointers to different types
   Uses: ptr\i, ptr\f, ptr\s for type-safe operations
*/

#pragma appname "Mixed-Type-Pointers-Test"
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

print("=== MIXED-TYPE POINTER ARRAYS TEST ===");
print("");

// =============================================================================
// TEST 1: Array of Pointers to Different Types
// =============================================================================
print("TEST 1: Array of Pointers to Different Types");
print("---------------------------------------------");

// Create variables of different types
intVal.i = 42;
floatVal.f = 3.14;
stringVal.s = "Hello";

// Create array of pointers (mixed types)
array *mixedPtrs[3];

// Store pointers to different types
mixedPtrs[0] = &intVal;
mixedPtrs[1] = &floatVal;
mixedPtrs[2] = &stringVal;

print("  Mixed pointer array created");
print("  Reading through pointers:");
print("    mixedPtrs[0]\\i = ", mixedPtrs[0]\i, " (expected 42)");
assertEqual(42, mixedPtrs[0]\i);

print("    mixedPtrs[1]\\f = ", mixedPtrs[1]\f, " (expected 3.14)");
assertFloatEqual(3.14, mixedPtrs[1]\f);

print("    mixedPtrs[2]\\s = ", mixedPtrs[2]\s, " (expected 'Hello')");
assertStringEqual("Hello", mixedPtrs[2]\s);

// V1.20.26: Using new pointer field syntax
mixedPtrs[0]\i = 99;
mixedPtrs[1]\f = 2.718;
mixedPtrs[2]\s = "World";

print("  After modification through pointers:");
print("    intVal = ", intVal, " (expected 99)");
assertEqual(99, intVal);

print("    floatVal = ", floatVal, " (expected 2.718)");
assertFloatEqual(2.718, floatVal);

print("    stringVal = ", stringVal, " (expected 'World')");
assertStringEqual("World", stringVal);

print("  PASS: Mixed-type pointer array works!");
print("");

// =============================================================================
// TEST 2: Pointer Reassignment with Different Types
// =============================================================================
print("TEST 2: Pointer Reassignment");
print("----------------------------");

i1.i = 10;
i2.i = 20;
f1.f = 1.5;
f2.f = 2.5;

// Create pointer and reassign to different variables of same type
pInt = &i1;
print("  pInt\\i = ", pInt\i, " (pointing to i1, expected 10)");
assertEqual(10, pInt\i);

pInt = &i2;
print("  After pInt = &i2:");
print("  pInt\\i = ", pInt\i, " (pointing to i2, expected 20)");
assertEqual(20, pInt\i);

pFloat = &f1;
print("  pFloat\\f = ", pFloat\f, " (pointing to f1, expected 1.5)");
assertFloatEqual(1.5, pFloat\f);

pFloat = &f2;
print("  After pFloat = &f2:");
print("  pFloat\\f = ", pFloat\f, " (pointing to f2, expected 2.5)");
assertFloatEqual(2.5, pFloat\f);

print("  PASS: Pointer reassignment works!");
print("");

// =============================================================================
// TEST 3: Array Elements with Different Types
// =============================================================================
print("TEST 3: Pointers to Array Elements (Mixed Types)");
print("-------------------------------------------------");

array ints.i[3];
array floats.f[3];
array strings.s[3];

ints[0] = 100;
ints[1] = 200;
ints[2] = 300;

floats[0] = 1.1;
floats[1] = 2.2;
floats[2] = 3.3;

strings[0] = "First";
strings[1] = "Second";
strings[2] = "Third";

// Create array of pointers to array elements
array *elemPtrs[9];

elemPtrs[0] = &ints[0];
elemPtrs[1] = &ints[1];
elemPtrs[2] = &ints[2];
elemPtrs[3] = &floats[0];
elemPtrs[4] = &floats[1];
elemPtrs[5] = &floats[2];
elemPtrs[6] = &strings[0];
elemPtrs[7] = &strings[1];
elemPtrs[8] = &strings[2];

print("  Array element pointers created");
print("  Integer elements:");
print("    elemPtrs[0]\\i = ", elemPtrs[0]\i);
assertEqual(100, elemPtrs[0]\i);
print("    elemPtrs[1]\\i = ", elemPtrs[1]\i);
assertEqual(200, elemPtrs[1]\i);
print("    elemPtrs[2]\\i = ", elemPtrs[2]\i);
assertEqual(300, elemPtrs[2]\i);

print("  Float elements:");
print("    elemPtrs[3]\\f = ", elemPtrs[3]\f);
assertFloatEqual(1.1, elemPtrs[3]\f);
print("    elemPtrs[4]\\f = ", elemPtrs[4]\f);
assertFloatEqual(2.2, elemPtrs[4]\f);
print("    elemPtrs[5]\\f = ", elemPtrs[5]\f);
assertFloatEqual(3.3, elemPtrs[5]\f);

print("  String elements:");
print("    elemPtrs[6]\\s = ", elemPtrs[6]\s);
assertStringEqual("First", elemPtrs[6]\s);
print("    elemPtrs[7]\\s = ", elemPtrs[7]\s);
assertStringEqual("Second", elemPtrs[7]\s);
print("    elemPtrs[8]\\s = ", elemPtrs[8]\s);
assertStringEqual("Third", elemPtrs[8]\s);

// Modify through pointers
elemPtrs[1]\i = 222;
elemPtrs[4]\f = 2.718;
elemPtrs[7]\s = "Modified";

print("  After modification:");
print("    ints[1] = ", ints[1], " (expected 222)");
assertEqual(222, ints[1]);
print("    floats[1] = ", floats[1], " (expected 2.718)");
assertFloatEqual(2.718, floats[1]);
print("    strings[1] = ", strings[1], " (expected 'Modified')");
assertStringEqual("Modified", strings[1]);

print("  PASS: Mixed array element pointers work!");
print("");

// =============================================================================
// TEST 4: Pointer Aliasing (Multiple Pointers to Same Variable)
// =============================================================================
print("TEST 4: Pointer Aliasing");
print("------------------------");

shared.s = "";

ptr1 = &shared;
ptr2 = ptr1;    // Copy pointer - both point to same location
ptr3 = ptr2;
ptr4 = ptr3;

print("  Created 4 pointers all pointing to same string variable");
print("  Modifying through ptr1...");

ptr1\s = "Hello";
print("  ptr1\\s = ", ptr1\s);
print("  ptr2\\s = ", ptr2\s);
print("  ptr3\\s = ", ptr3\s);
print("  ptr4\\s = ", ptr4\s);

assertStringEqual("Hello", ptr1\s);
assertStringEqual("Hello", ptr2\s);
assertStringEqual("Hello", ptr3\s);
assertStringEqual("Hello", ptr4\s);
assertStringEqual("Hello", shared);

print("  Modifying through ptr4...");
ptr4\s = "World";

print("  All pointers now see: ", ptr1\s);
assertStringEqual("World", ptr1\s);
assertStringEqual("World", ptr2\s);
assertStringEqual("World", ptr3\s);
assertStringEqual("World", ptr4\s);
assertStringEqual("World", shared);

print("  PASS: Pointer aliasing works correctly!");
print("");

print("=== ALL MIXED-TYPE POINTER TESTS PASSED ===");
print("");
print("Summary:");
print("  - Mixed-type pointer arrays: WORKING");
print("  - Type-specific field access (\i, \f, \s): WORKING");
print("  - Pointer reassignment: WORKING");
print("  - Array element pointers (mixed types): WORKING");
print("  - Pointer aliasing: WORKING");
print("");
