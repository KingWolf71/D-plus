// Test Struct Copy (V1.022.65)
// Syntax: destStruct = srcStruct - copy all fields
// Requires same struct type for source and destination

#pragma appname "Struct-Copy-Test"
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

print("=== STRUCT COPY TEST (V1.022.65) ===");
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
}

struct Mixed {
    intVal.i;
    floatVal.f;
    strVal.s;
}

// =============================================================================
// TEST 1: Basic Point struct copy
// =============================================================================
print("TEST 1: Basic Point struct copy");
print("-------------------------------");

p1.Point\x = 10;
p1\y = 20;

p2.Point\x = 0;
p2\y = 0;

print("  Before copy:");
print("    p1 = (", p1\x, ", ", p1\y, ")");
print("    p2 = (", p2\x, ", ", p2\y, ")");

// Copy struct
p2 = p1;

print("  After p2 = p1:");
print("    p1 = (", p1\x, ", ", p1\y, ")");
print("    p2 = (", p2\x, ", ", p2\y, ")");

assertEqual(10, p2\x);
assertEqual(20, p2\y);
assertEqual(10, p1\x);
assertEqual(20, p1\y);

print("  PASS: Basic struct copy works!");
print("");

// =============================================================================
// TEST 2: Verify copy is independent (modify copy doesn't affect original)
// =============================================================================
print("TEST 2: Copy independence");
print("------------------------");

// Modify the copy
p2\x = 100;
p2\y = 200;

print("  After modifying p2:");
print("    p1 = (", p1\x, ", ", p1\y, ") - should be unchanged");
print("    p2 = (", p2\x, ", ", p2\y, ") - should be modified");

assertEqual(10, p1\x);
assertEqual(20, p1\y);
assertEqual(100, p2\x);
assertEqual(200, p2\y);

print("  PASS: Copy is independent of original!");
print("");

// =============================================================================
// TEST 3: Rectangle struct copy (4 fields)
// =============================================================================
print("TEST 3: Rectangle struct copy");
print("----------------------------");

rect1.Rectangle\x = 5;
rect1\y = 10;
rect1\width = 100;
rect1\height = 50;

rect2.Rectangle\x = 0;
rect2\y = 0;
rect2\width = 0;
rect2\height = 0;

print("  Before copy:");
print("    rect1 = (", rect1\x, ", ", rect1\y, ", ", rect1\width, ", ", rect1\height, ")");
print("    rect2 = (", rect2\x, ", ", rect2\y, ", ", rect2\width, ", ", rect2\height, ")");

rect2 = rect1;

print("  After rect2 = rect1:");
print("    rect2 = (", rect2\x, ", ", rect2\y, ", ", rect2\width, ", ", rect2\height, ")");

assertEqual(5, rect2\x);
assertEqual(10, rect2\y);
assertEqual(100, rect2\width);
assertEqual(50, rect2\height);

print("  PASS: Rectangle struct copy works!");
print("");

// =============================================================================
// TEST 4: Mixed types struct copy (int, float, string)
// =============================================================================
print("TEST 4: Mixed types struct copy");
print("------------------------------");

m1.Mixed\intVal = 42;
m1\floatVal = 3.14159;
m1\strVal = "Hello World";

m2.Mixed\intVal = 0;
m2\floatVal = 0.0;
m2\strVal = "";

print("  Before copy:");
print("    m1 = (", m1\intVal, ", ", m1\floatVal, ", '", m1\strVal, "')");
print("    m2 = (", m2\intVal, ", ", m2\floatVal, ", '", m2\strVal, "')");

m2 = m1;

print("  After m2 = m1:");
print("    m2 = (", m2\intVal, ", ", m2\floatVal, ", '", m2\strVal, "')");

assertEqual(42, m2\intVal);
assertFloatEqual(3.14159, m2\floatVal);
assertStringEqual("Hello World", m2\strVal);

print("  PASS: Mixed types struct copy works!");
print("");

// =============================================================================
// TEST 5: Multiple consecutive copies
// =============================================================================
print("TEST 5: Multiple consecutive copies");
print("----------------------------------");

pa.Point = {1, 2};
pb.Point = {3, 4};
pc.Point = {5, 6};

print("  Initial: pa=(", pa\x, ",", pa\y, ") pb=(", pb\x, ",", pb\y, ") pc=(", pc\x, ",", pc\y, ")");

// Chain of copies
pb = pa;
pc = pb;

print("  After pb=pa, pc=pb:");
print("    pa=(", pa\x, ",", pa\y, ") pb=(", pb\x, ",", pb\y, ") pc=(", pc\x, ",", pc\y, ")");

assertEqual(1, pa\x);
assertEqual(2, pa\y);
assertEqual(1, pb\x);
assertEqual(2, pb\y);
assertEqual(1, pc\x);
assertEqual(2, pc\y);

print("  PASS: Multiple copies work!");
print("");

// =============================================================================
// TEST 6: Copy with struct literal initialization
// =============================================================================
print("TEST 6: Copy after literal initialization");
print("-----------------------------------------");

src.Point = {99, 88};
dst.Point = {0, 0};

dst = src;

print("  dst = (", dst\x, ", ", dst\y, ") after copy from {99, 88}");

assertEqual(99, dst\x);
assertEqual(88, dst\y);

print("  PASS: Copy after literal init works!");
print("");

print("=== ALL STRUCT COPY TESTS PASSED ===");
print("");
print("Summary:");
print("  - Basic struct copy: WORKING");
print("  - Copy independence: WORKING");
print("  - Multi-field structs: WORKING");
print("  - Mixed type fields: WORKING");
print("  - Consecutive copies: WORKING");
print("  - Literal init + copy: WORKING");
print("");
