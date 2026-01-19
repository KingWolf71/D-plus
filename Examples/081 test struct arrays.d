// Test arrays inside structures (V1.022.0)
// Tests struct field arrays: definition, initialization, access

#pragma appname "Struct-Arrays-Test"
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

print("=== STRUCT ARRAYS TEST (V1.022.0) ===");
print("");

// =============================================================================
// TEST 1: Basic struct with integer array
// =============================================================================
print("TEST 1: Basic struct with integer array");
print("---------------------------------------");

struct Container {
    id.i;
    data.i[5];
    name.s;
}

c1.Container = {100, {10, 20, 30, 40, 50}, "Test1"};

print("  c1\\id = ", c1\id, " (expected 100)");
assertEqual(100, c1\id);

print("  c1\\data[0] = ", c1\data[0], " (expected 10)");
assertEqual(10, c1\data[0]);

print("  c1\\data[2] = ", c1\data[2], " (expected 30)");
assertEqual(30, c1\data[2]);

print("  c1\\data[4] = ", c1\data[4], " (expected 50)");
assertEqual(50, c1\data[4]);

print("  c1\\name = ", c1\name, " (expected Test1)");
assertStringEqual("Test1", c1\name);

print("  PASS: Basic struct with int array works!");
print("");

// =============================================================================
// TEST 2: Modify array elements in struct
// =============================================================================
print("TEST 2: Modify array elements in struct");
print("---------------------------------------");

c1\data[0] = 111;
c1\data[2] = 333;
c1\data[4] = 555;

print("  After modification:");
print("  c1\\data[0] = ", c1\data[0], " (expected 111)");
assertEqual(111, c1\data[0]);

print("  c1\\data[1] = ", c1\data[1], " (expected 20, unchanged)");
assertEqual(20, c1\data[1]);

print("  c1\\data[2] = ", c1\data[2], " (expected 333)");
assertEqual(333, c1\data[2]);

print("  c1\\data[4] = ", c1\data[4], " (expected 555)");
assertEqual(555, c1\data[4]);

print("  PASS: Modifying struct array elements works!");
print("");

// =============================================================================
// TEST 3: Loop through struct array
// =============================================================================
print("TEST 3: Loop through struct array");
print("---------------------------------");

sum.i = 0;
i.i = 0;
while i < 5 {
    sum = sum + c1\data[i];
    i++;
}

print("  Sum of c1\\data elements = ", sum, " (expected 1042)");
// 111 + 20 + 333 + 40 + 555 = 1059... wait let me recalculate
// c1\data[0]=111, c1\data[1]=20, c1\data[2]=333, c1\data[3]=40, c1\data[4]=555
// 111 + 20 + 333 + 40 + 555 = 1059
assertEqual(1059, sum);

print("  PASS: Looping through struct array works!");
print("");

// =============================================================================
// TEST 4: Struct with float array
// =============================================================================
print("TEST 4: Struct with float array");
print("-------------------------------");

struct Vector3D {
    name.s;
    coords.f[3];
}

v1.Vector3D = {"Point1", {1.5, 2.5, 3.5}};

print("  v1\\name = ", v1\name, " (expected Point1)");
assertStringEqual("Point1", v1\name);

print("  v1\\coords[0] = ", v1\coords[0], " (expected 1.5)");
assertFloatEqual(1.5, v1\coords[0]);

print("  v1\\coords[1] = ", v1\coords[1], " (expected 2.5)");
assertFloatEqual(2.5, v1\coords[1]);

print("  v1\\coords[2] = ", v1\coords[2], " (expected 3.5)");
assertFloatEqual(3.5, v1\coords[2]);

print("  PASS: Struct with float array works!");
print("");

// =============================================================================
// TEST 5: Struct with string array
// =============================================================================
print("TEST 5: Struct with string array");
print("--------------------------------");

struct StringList {
    count.i;
    items.s[3];
}

sl.StringList = {3, {"Apple", "Banana", "Cherry"}};

print("  sl\\count = ", sl\count, " (expected 3)");
assertEqual(3, sl\count);

print("  sl\\items[0] = ", sl\items[0], " (expected Apple)");
assertStringEqual("Apple", sl\items[0]);

print("  sl\\items[1] = ", sl\items[1], " (expected Banana)");
assertStringEqual("Banana", sl\items[1]);

print("  sl\\items[2] = ", sl\items[2], " (expected Cherry)");
assertStringEqual("Cherry", sl\items[2]);

// Modify string array element
sl\items[1] = "Blueberry";

print("  After sl\\items[1] = 'Blueberry':");
print("  sl\\items[1] = ", sl\items[1], " (expected Blueberry)");
assertStringEqual("Blueberry", sl\items[1]);

print("  PASS: Struct with string array works!");
print("");

// =============================================================================
// TEST 6: Multiple array fields in struct
// =============================================================================
print("TEST 6: Multiple array fields in struct");
print("---------------------------------------");

struct MultiArray {
    header.i;
    ints.i[2];
    floats.f[2];
    trailer.i;
}

ma.MultiArray = {1, {10, 20}, {1.1, 2.2}, 99};

print("  ma\\header = ", ma\header, " (expected 1)");
assertEqual(1, ma\header);

print("  ma\\ints[0] = ", ma\ints[0], " (expected 10)");
assertEqual(10, ma\ints[0]);

print("  ma\\ints[1] = ", ma\ints[1], " (expected 20)");
assertEqual(20, ma\ints[1]);

print("  ma\\floats[0] = ", ma\floats[0], " (expected 1.1)");
assertFloatEqual(1.1, ma\floats[0]);

print("  ma\\floats[1] = ", ma\floats[1], " (expected 2.2)");
assertFloatEqual(2.2, ma\floats[1]);

print("  ma\\trailer = ", ma\trailer, " (expected 99)");
assertEqual(99, ma\trailer);

print("  PASS: Multiple array fields work!");
print("");

// =============================================================================
// TEST 7: Variable index access
// =============================================================================
print("TEST 7: Variable index access");
print("-----------------------------");

idx.i = 2;
print("  c1\\data[idx] where idx=2: ", c1\data[idx], " (expected 333)");
assertEqual(333, c1\data[idx]);

idx = 0;
print("  c1\\data[idx] where idx=0: ", c1\data[idx], " (expected 111)");
assertEqual(111, c1\data[idx]);

print("  PASS: Variable index access works!");
print("");

print("=== ALL STRUCT ARRAY TESTS PASSED ===");
print("");
print("Summary:");
print("  - Struct definition with array fields: WORKING");
print("  - Struct initialization with array values: WORKING");
print("  - Array element access (s\\arr[i]): WORKING");
print("  - Array element modification: WORKING");
print("  - Loop iteration through struct arrays: WORKING");
print("  - Float array fields: WORKING");
print("  - String array fields: WORKING");
print("  - Multiple array fields: WORKING");
print("  - Variable index access: WORKING");
print("");
