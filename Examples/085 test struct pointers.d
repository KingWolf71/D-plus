// Test Struct Pointers (V1.022.55)
// Syntax: ptr = &myStruct - get address of struct
// Access: ptr\field - read/write field through pointer

#pragma appname "Struct-Pointers-Test"
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

print("=== STRUCT POINTERS TEST (V1.022.55) ===");
print("");

// =============================================================================
// Define test structures
// =============================================================================
struct Point {
    x.i;
    y.i;
}

struct Rectangle {
    x.i;
    y.i;
    width.i;
    height.i;
    name.s;
}

struct Mixed {
    intVal.i;
    floatVal.f;
    strVal.s;
}

// =============================================================================
// TEST 1: Basic struct access (reference test)
// =============================================================================
print("TEST 1: Basic struct access (reference)");
print("---------------------------------------");

p.Point = {10, 20};

print("  p.x = ", p\x, " (expected 10)");
assertEqual(10, p\x);
print("  p.y = ", p\y, " (expected 20)");
assertEqual(20, p\y);

print("  PASS: Basic struct access works");
print("");

// =============================================================================
// TEST 2: Address-of struct (&struct)
// =============================================================================
print("TEST 2: Address-of struct");
print("------------------------");

// Get address of struct - should emit GETSTRUCTADDR
*ptr = &p;
print("  ptr = &p (pointer to struct assigned)");

// Access fields through pointer
print("  ptr\\x = ", ptr\x, " (expected 10)");
assertEqual(10, ptr\x);
print("  ptr\\y = ", ptr\y, " (expected 20)");
assertEqual(20, ptr\y);

print("  PASS: Struct pointer read works!");
print("");

// =============================================================================
// TEST 3: Write through struct pointer
// =============================================================================
print("TEST 3: Write through struct pointer");
print("------------------------------------");

// Modify struct through pointer
ptr\x = 100;
ptr\y = 200;

print("  ptr\\x = ", ptr\x, " (expected 100)");
assertEqual(100, ptr\x);
print("  ptr\\y = ", ptr\y, " (expected 200)");
assertEqual(200, ptr\y);

// Verify original struct was modified
print("  p\\x = ", p\x, " (expected 100 - modified through ptr)");
assertEqual(100, p\x);
print("  p\\y = ", p\y, " (expected 200 - modified through ptr)");
assertEqual(200, p\y);

print("  PASS: Struct pointer write works!");
print("");

// =============================================================================
// TEST 4: Rectangle struct with string field
// =============================================================================
print("TEST 4: Rectangle with string field");
print("-----------------------------------");

rect.Rectangle\x = 10;
rect\y = 20;
rect\width = 100;
rect\height = 50;
rect\name = "TestRect";

rptr = &rect;

print("  rptr\\x = ", rptr\x, " (expected 10)");
assertEqual(10, rptr\x);
print("  rptr\\width = ", rptr\width, " (expected 100)");
assertEqual(100, rptr\width);
print("  rptr\\name = ", rptr\name, " (expected TestRect)");
assertStringEqual("TestRect", rptr\name);

// Modify through pointer
rptr\width = 200;
rptr\height = 150;
rptr\name = "ModifiedRect";

print("  After modify: rptr\\width = ", rptr\width, " (expected 200)");
assertEqual(200, rptr\width);
print("  After modify: rect\\height = ", rect\height, " (expected 150)");
assertEqual(150, rect\height);
print("  After modify: rect\\name = ", rect\name, " (expected ModifiedRect)");
assertStringEqual("ModifiedRect", rect\name);

print("  PASS: Rectangle pointer works!");
print("");

// =============================================================================
// TEST 5: Mixed types struct pointer
// =============================================================================
print("TEST 5: Mixed types struct pointer");
print("---------------------------------");

mix.Mixed\intVal = 42;
mix\floatVal = 3.14159;
mix\strVal = "Hello";

mptr = &mix;

print("  mptr\\intVal = ", mptr\intVal, " (expected 42)");
assertEqual(42, mptr\intVal);
print("  mptr\\floatVal = ", mptr\floatVal, " (expected ~3.14)");
assertFloatEqual(3.14159, mptr\floatVal);
print("  mptr\\strVal = ", mptr\strVal, " (expected Hello)");
assertStringEqual("Hello", mptr\strVal);

// Modify through pointer
mptr\intVal = 100;
mptr\floatVal = 2.71828;
mptr\strVal = "World";

print("  After modify: mix\\intVal = ", mix\intVal, " (expected 100)");
assertEqual(100, mix\intVal);
print("  After modify: mix\\floatVal = ", mix\floatVal, " (expected ~2.72)");
assertFloatEqual(2.71828, mix\floatVal);
print("  After modify: mix\\strVal = ", mix\strVal, " (expected World)");
assertStringEqual("World", mix\strVal);

print("  PASS: Mixed types struct pointer works!");
print("");

// =============================================================================
// TEST 6: Expressions with pointer fields
// =============================================================================
print("TEST 6: Expressions with pointer fields");
print("--------------------------------------");

p\x = 50;
p\y = 30;
ptr = &p;

sum.i = ptr\x + ptr\y;
print("  sum = ptr\\x + ptr\\y = ", sum, " (expected 80)");
assertEqual(80, sum);

diff.i = ptr\x - ptr\y;
print("  diff = ptr\\x - ptr\\y = ", diff, " (expected 20)");
assertEqual(20, diff);

prod.i = ptr\x * ptr\y;
print("  prod = ptr\\x * ptr\\y = ", prod, " (expected 1500)");
assertEqual(1500, prod);

print("  PASS: Expressions with pointer fields work!");
print("");

// =============================================================================
// TEST 7: Multiple pointers to different structs
// =============================================================================
print("TEST 7: Multiple pointers");
print("------------------------");

p1.Point = {1, 2};
p2.Point = {3, 4};

ptr1 = &p1;
ptr2 = &p2;

print("  ptr1\\x = ", ptr1\x, ", ptr1\\y = ", ptr1\y, " (expected 1, 2)");
assertEqual(1, ptr1\x);
assertEqual(2, ptr1\y);

print("  ptr2\\x = ", ptr2\x, ", ptr2\\y = ", ptr2\y, " (expected 3, 4)");
assertEqual(3, ptr2\x);
assertEqual(4, ptr2\y);

// Swap values using pointers
tmp.i = ptr1\x;
ptr1\x = ptr2\x;
ptr2\x = tmp;

print("  After swap: ptr1\\x = ", ptr1\x, " (expected 3)");
assertEqual(3, ptr1\x);
print("  After swap: ptr2\\x = ", ptr2\x, " (expected 1)");
assertEqual(1, ptr2\x);

print("  PASS: Multiple pointers work!");
print("");

print("=== ALL STRUCT POINTER TESTS PASSED ===");
print("");
print("Summary:");
print("  - Address-of struct (&struct): WORKING");
print("  - Pointer field read (ptr\\field): WORKING");
print("  - Pointer field write (ptr\\field = val): WORKING");
print("  - Integer fields: WORKING");
print("  - Float fields: WORKING");
print("  - String fields: WORKING");
print("  - Expressions with pointer fields: WORKING");
print("  - Multiple pointers: WORKING");
print("");
