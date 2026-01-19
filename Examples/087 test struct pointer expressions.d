// Test Struct Pointer Writes with Expression Values in Functions (V1.022.117)
// This tests the case where ptr\field = expression inside a function
// The expression result may be stored in a local temp, requiring PTRSTRUCTSTORE_*_LOPT

#pragma appname "Struct-Ptr-Expr-Test"
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

print("=== STRUCT POINTER EXPRESSION TEST (V1.022.117) ===");
print("");

// =============================================================================
// Define test structures
// =============================================================================
struct Point {
    x.i;
    y.i;
}

struct Data {
    intVal.i;
    floatVal.f;
    strVal.s;
}

// =============================================================================
// TEST 1: Expression result assigned to struct pointer field inside function
// =============================================================================
print("TEST 1: Expression assigned to ptr\\field in function");
print("----------------------------------------------------");

p1.Point = {10, 20};

function modifyPointWithExpr(dx, dy) {
    ptr = &p1;
    // These expressions should trigger local temp usage
    ptr\x = p1\x + dx;  // Expression: p1\x + dx -> local temp -> ptr\x
    ptr\y = p1\y + dy;  // Expression: p1\y + dy -> local temp -> ptr\y
    print("  Inside function: ptr\\x = ", ptr\x, ", ptr\\y = ", ptr\y);
}

print("  Before: p1.x = ", p1\x, ", p1.y = ", p1\y);
modifyPointWithExpr(5, 10);
print("  After: p1.x = ", p1\x, ", p1.y = ", p1\y);

print("  p1\\x = ", p1\x, " (expected 15)");
assertEqual(15, p1\x);
print("  p1\\y = ", p1\y, " (expected 30)");
assertEqual(30, p1\y);

print("  PASS: Expression assigned to ptr\\field in function!");
print("");

// =============================================================================
// TEST 2: Complex expression with multiple operations
// =============================================================================
print("TEST 2: Complex expression in function");
print("-------------------------------------");

p2.Point = {100, 50};

function complexExpr(a, b, c) {
    ptr = &p2;
    // Complex expression: (a + b) * c -> local temp -> ptr\x
    ptr\x = (a + b) * c;
    ptr\y = a * b - c;
    print("  Inside function: ptr\\x = ", ptr\x, ", ptr\\y = ", ptr\y);
}

print("  Before: p2.x = ", p2\x, ", p2.y = ", p2\y);
complexExpr(3, 4, 5);  // x = (3+4)*5 = 35, y = 3*4-5 = 7
print("  After: p2.x = ", p2\x, ", p2.y = ", p2\y);

print("  p2\\x = ", p2\x, " (expected 35)");
assertEqual(35, p2\x);
print("  p2\\y = ", p2\y, " (expected 7)");
assertEqual(7, p2\y);

print("  PASS: Complex expression in function!");
print("");

// =============================================================================
// TEST 3: Float expressions through struct pointer
// =============================================================================
print("TEST 3: Float expression through struct pointer");
print("----------------------------------------------");

d1.Data\intVal = 10;
d1\floatVal = 2.5;
d1\strVal = "test";

function modifyFloat(multiplier.f) {
    ptr = &d1;
    // Float expression -> local temp -> ptr\floatVal
    ptr\floatVal = d1\floatVal * multiplier;
    print("  Inside function: ptr\\floatVal = ", ptr\floatVal);
}

print("  Before: d1.floatVal = ", d1\floatVal);
modifyFloat(3.0);  // 2.5 * 3.0 = 7.5
print("  After: d1.floatVal = ", d1\floatVal);

print("  d1\\floatVal = ", d1\floatVal, " (expected 7.5)");
assertFloatEqual(7.5, d1\floatVal);

print("  PASS: Float expression through struct pointer!");
print("");

// =============================================================================
// TEST 4: Mixed int and float expressions
// =============================================================================
print("TEST 4: Mixed type expressions");
print("-----------------------------");

d2.Data\intVal = 5;
d2\floatVal = 1.5;

function mixedExpr(intAdd, floatMult.f) {
    ptr = &d2;
    ptr\intVal = d2\intVal + intAdd + intAdd;  // 5 + 3 + 3 = 11
    ptr\floatVal = d2\floatVal * floatMult + 0.5;  // 1.5 * 2.0 + 0.5 = 3.5
    print("  Inside function: intVal=", ptr\intVal, " floatVal=", ptr\floatVal);
}

print("  Before: d2.intVal = ", d2\intVal, ", d2.floatVal = ", d2\floatVal);
mixedExpr(3, 2.0);
print("  After: d2.intVal = ", d2\intVal, ", d2.floatVal = ", d2\floatVal);

print("  d2\\intVal = ", d2\intVal, " (expected 11)");
assertEqual(11, d2\intVal);
print("  d2\\floatVal = ", d2\floatVal, " (expected 3.5)");
assertFloatEqual(3.5, d2\floatVal);

print("  PASS: Mixed type expressions!");
print("");

// =============================================================================
// TEST 5: Nested function calls with struct pointer expressions
// =============================================================================
print("TEST 5: Nested function calls");
print("----------------------------");

p3.Point = {0, 0};

function helper(val) {
    return val * 2;
}

function nestedExpr(base) {
    ptr = &p3;
    // helper(base) returns to stack, then + 10 -> local temp -> ptr\x
    ptr\x = helper(base) + 10;
    ptr\y = helper(base + 5) - 5;
    print("  Inside nestedExpr: ptr\\x = ", ptr\x, ", ptr\\y = ", ptr\y);
}

nestedExpr(5);  // x = helper(5)+10 = 10+10 = 20, y = helper(10)-5 = 20-5 = 15
print("  p3\\x = ", p3\x, " (expected 20)");
assertEqual(20, p3\x);
print("  p3\\y = ", p3\y, " (expected 15)");
assertEqual(15, p3\y);

print("  PASS: Nested function calls!");
print("");

// =============================================================================
// TEST 6: Local variables in expression
// =============================================================================
print("TEST 6: Local variables in expression");
print("------------------------------------");

p4.Point = {1, 1};

function localVarExpr(a, b) {
    ptr = &p4;
    localSum.i = a + b;
    localProd.i = a * b;
    // Local var in expression -> local temp -> ptr\field
    ptr\x = localSum + 100;
    ptr\y = localProd + 200;
    print("  localSum=", localSum, " localProd=", localProd);
    print("  ptr\\x=", ptr\x, " ptr\\y=", ptr\y);
}

localVarExpr(3, 7);  // sum=10, prod=21, x=110, y=221
print("  p4\\x = ", p4\x, " (expected 110)");
assertEqual(110, p4\x);
print("  p4\\y = ", p4\y, " (expected 221)");
assertEqual(221, p4\y);

print("  PASS: Local variables in expression!");
print("");

print("=== ALL STRUCT POINTER EXPRESSION TESTS PASSED ===");
print("");
print("Summary:");
print("  - Simple expressions in functions: WORKING");
print("  - Complex expressions: WORKING");
print("  - Float expressions: WORKING");
print("  - Mixed type expressions: WORKING");
print("  - Nested function calls: WORKING");
print("  - Local variables in expressions: WORKING");
print("");
