/* Pointer Type Checking Test - V1.20.26+
   Tests compile-time validation of pointer types with \i/\f/\s syntax
   The compiler now enforces that only pointer variables can use field access
*/

#pragma appname "Pointer-Type-Checking"
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

print("=== Pointer Type Checking Test ===");
print("");

// Test 1: Valid pointer usage - should compile
print("TEST 1: Valid Pointer Usage");
print("---------------------------");

x.i = 42;
ptr = &x;  // ptr is inferred as pointer type

print("x = ", x);
print("ptr\\i = ", ptr\i, " (reading through pointer)");
assertEqual(42, ptr\i);

ptr\i = 99;  // ptr is known to be a pointer, so \i is allowed
print("After ptr\\i = 99:");
print("x = ", x);
assertEqual(99, x);

print("PASS: Pointer type checking allows valid pointer operations");
print("");

// Test 2: Multiple pointer types
print("TEST 2: Multiple Pointer Types");
print("-------------------------------");

f.f = 3.14;
s.s = "Hello";

ptrF = &f;  // Inferred as float pointer
ptrS = &s;  // Inferred as string pointer

print("ptrF\\f = ", ptrF\f);
assertFloatEqual(3.14, ptrF\f);

print("ptrS\\s = ", ptrS\s);
assertStringEqual("Hello", ptrS\s);

ptrF\f = 2.718;
ptrS\s = "World";

print("After modification:");
print("f = ", f, ", s = ", s);
assertFloatEqual(2.718, f);
assertStringEqual("World", s);

print("PASS: Multiple pointer types work correctly");
print("");

// Test 3: Array of pointers (runtime check)
print("TEST 3: Array of Pointers");
print("-------------------------");

val1.i = 100;
val2.i = 200;

array *ptrArray[2];
ptrArray[0] = &val1;
ptrArray[1] = &val2;

print("ptrArray[0]\\i = ", ptrArray[0]\i);
assertEqual(100, ptrArray[0]\i);

print("ptrArray[1]\\i = ", ptrArray[1]\i);
assertEqual(200, ptrArray[1]\i);

ptrArray[0]\i = 111;
print("After ptrArray[0]\\i = 111:");
print("val1 = ", val1);
assertEqual(111, val1);

print("PASS: Array element pointers use runtime checking");
print("");

// Test 4: Pointer reassignment
print("TEST 4: Pointer Reassignment");
print("-----------------------------");

a.i = 10;
b.i = 20;

p = &a;  // p is now a pointer
print("p\\i = ", p\i, " (pointing to a)");
assertEqual(10, p\i);

p = &b;  // Reassign to different variable
print("p\\i = ", p\i, " (pointing to b)");
assertEqual(20, p\i);

p\i = 30;
print("After p\\i = 30:");
print("a = ", a, ", b = ", b);
assertEqual(10, a);  // a unchanged
assertEqual(30, b);  // b modified

print("PASS: Pointer reassignment maintains type checking");
print("");

print("=== All Pointer Type Checking Tests Passed ===");
print("");
print("Summary:");
print("  - Pointer type inference: WORKING");
print("  - Compile-time type validation: ENFORCED");
print("  - Multiple pointer types: WORKING");
print("  - Array element pointers: WORKING (runtime check)");
print("  - Pointer reassignment: WORKING");
print("");
