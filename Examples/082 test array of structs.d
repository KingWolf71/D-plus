// Test Arrays OF Structs (V1.022.44)
// Syntax: array points.Point[10] - array where each element is a struct
// Access: points[i]\field - read/write field of struct at index

#pragma appname "Array-Of-Structs-Test"
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

print("=== ARRAY OF STRUCTS TEST (V1.022.44) ===");
print("");

// =============================================================================
// Define test structures
// =============================================================================
struct Point {
    x.i;
    y.i;
}

struct Particle {
    posX.f;
    posY.f;
    name.s;
}

struct Record {
    id.i;
    value.f;
    label.s;
}

// =============================================================================
// TEST 1: Basic array of structs declaration
// =============================================================================
print("TEST 1: Basic array of structs declaration");
print("------------------------------------------");

array points.Point[5];

print("  Declared: array points.Point[5]");
print("  PASS: Declaration compiled!");
print("");

// =============================================================================
// TEST 2: Assign to struct array elements
// =============================================================================
print("TEST 2: Assign to struct array elements");
print("---------------------------------------");

points[0]\x = 10;
points[0]\y = 20;
points[1]\x = 30;
points[1]\y = 40;
points[2]\x = 50;
points[2]\y = 60;

print("  Assigned: points[0] = (10, 20)");
print("  Assigned: points[1] = (30, 40)");
print("  Assigned: points[2] = (50, 60)");
print("  PASS: Assignments compiled!");
print("");

// =============================================================================
// TEST 3: Read from struct array elements
// =============================================================================
print("TEST 3: Read from struct array elements");
print("--------------------------------------");

print("  points[0]\\x = ", points[0]\x, " (expected 10)");
assertEqual(10, points[0]\x);

print("  points[0]\\y = ", points[0]\y, " (expected 20)");
assertEqual(20, points[0]\y);

print("  points[1]\\x = ", points[1]\x, " (expected 30)");
assertEqual(30, points[1]\x);

print("  points[1]\\y = ", points[1]\y, " (expected 40)");
assertEqual(40, points[1]\y);

print("  points[2]\\x = ", points[2]\x, " (expected 50)");
assertEqual(50, points[2]\x);

print("  points[2]\\y = ", points[2]\y, " (expected 60)");
assertEqual(60, points[2]\y);

print("  PASS: All reads match expected values!");
print("");

// =============================================================================
// TEST 4: Loop through array of structs
// =============================================================================
print("TEST 4: Loop through array of structs");
print("------------------------------------");

// Initialize remaining elements
points[3]\x = 70;
points[3]\y = 80;
points[4]\x = 90;
points[4]\y = 100;

sumX.i = 0;
sumY.i = 0;
i = 0;
while i < 5 {
    sumX = sumX + points[i]\x;
    sumY = sumY + points[i]\y;
    print("  points[", i, "] = (", points[i]\x, ", ", points[i]\y, ")");
    i++;
}

print("  Sum of x values = ", sumX, " (expected 250)");
assertEqual(250, sumX);

print("  Sum of y values = ", sumY, " (expected 300)");
assertEqual(300, sumY);

print("  PASS: Loop iteration works!");
print("");

// =============================================================================
// TEST 5: Array of structs with float fields
// =============================================================================
print("TEST 5: Array of structs with float fields");
print("-----------------------------------------");

array particles.Particle[3];

particles[0]\posX = 1.5;
particles[0]\posY = 2.5;
particles[0]\name = "P0";

particles[1]\posX = 3.5;
particles[1]\posY = 4.5;
particles[1]\name = "P1";

particles[2]\posX = 5.5;
particles[2]\posY = 6.5;
particles[2]\name = "P2";

print("  particles[0]\\posX = ", particles[0]\posX, " (expected 1.5)");
assertFloatEqual(1.5, particles[0]\posX);

print("  particles[1]\\posY = ", particles[1]\posY, " (expected 4.5)");
assertFloatEqual(4.5, particles[1]\posY);

print("  particles[2]\\name = ", particles[2]\name, " (expected P2)");
assertStringEqual("P2", particles[2]\name);

print("  PASS: Float and string fields work!");
print("");

// =============================================================================
// TEST 6: Variable index access
// =============================================================================
print("TEST 6: Variable index access");
print("----------------------------");

idx.i = 1;
print("  points[idx]\\x where idx=1: ", points[idx]\x, " (expected 30)");
assertEqual(30, points[idx]\x);

idx = 3;
print("  points[idx]\\y where idx=3: ", points[idx]\y, " (expected 80)");
assertEqual(80, points[idx]\y);

print("  PASS: Variable index works!");
print("");

// =============================================================================
// TEST 7: Expressions with struct array fields
// =============================================================================
print("TEST 7: Expressions with struct array fields");
print("-------------------------------------------");

dist.i = points[4]\x - points[0]\x;
print("  Distance x (p4-p0) = ", dist, " (expected 80)");
assertEqual(80, dist);

midX.i = (points[0]\x + points[4]\x) / 2;
print("  Mid-point x = ", midX, " (expected 50)");
assertEqual(50, midX);

print("  PASS: Expressions work!");
print("");

// =============================================================================
// TEST 8: Mixed types in one array
// =============================================================================
print("TEST 8: Mixed type struct array");
print("------------------------------");

array records.Record[3];

records[0]\id = 1;
records[0]\value = 10.5;
records[0]\label = "First";

records[1]\id = 2;
records[1]\value = 20.5;
records[1]\label = "Second";

records[2]\id = 3;
records[2]\value = 30.5;
records[2]\label = "Third";

print("  records[0] = (", records[0]\id, ", ", records[0]\value, ", '", records[0]\label, "')");
print("  records[1] = (", records[1]\id, ", ", records[1]\value, ", '", records[1]\label, "')");
print("  records[2] = (", records[2]\id, ", ", records[2]\value, ", '", records[2]\label, "')");

assertEqual(2, records[1]\id);
assertFloatEqual(30.5, records[2]\value);
assertStringEqual("First", records[0]\label);

print("  PASS: Mixed type struct arrays work!");
print("");

print("=== ALL ARRAY OF STRUCTS TESTS PASSED ===");
print("");
print("Summary:");
print("  - Array of structs declaration: WORKING");
print("  - Field assignment (arr[i]\\field = val): WORKING");
print("  - Field read (arr[i]\\field): WORKING");
print("  - Loop iteration: WORKING");
print("  - Float fields: WORKING");
print("  - String fields: WORKING");
print("  - Variable index: WORKING");
print("  - Expressions: WORKING");
print("");
