// Comprehensive array test for D+AI
// Tests global arrays, local arrays, all types, indexing, and edge cases

#pragma appname "D+AI Comprehensive Array Test"
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
#pragma DumpASM off
#pragma asmdecimal on

print("=== D+AI Comprehensive Array Test ===");
print("");

// === Test 1: Global Integer Arrays ===
print("Test 1: Global Integer Arrays");
array g_ints.i[5];
g_ints[0] = 10;
g_ints[1] = 20;
g_ints[2] = 30;
g_ints[3] = 40;
g_ints[4] = 50;

i = 0;
while i < 5 {
    printf("  g_ints[%d] = %d\n", i, g_ints[i]);
    i = i + 1;
}

print("  Asserting g_ints[0] = ", g_ints[0]);
assertEqual(10, g_ints[0]);
print("  Asserting g_ints[2] = ", g_ints[2]);
assertEqual(30, g_ints[2]);
print("  Asserting g_ints[4] = ", g_ints[4]);
assertEqual(50, g_ints[4]);
print("  PASS: Global int array read/write");
print("");

// === Test 2: Global Float Arrays ===
print("Test 2: Global Float Arrays");
array g_floats.f[3];
g_floats[0] = 1.5;
g_floats[1] = 2.75;
g_floats[2] = 3.125;

i = 0;
while i < 3 {
    printf("  g_floats[%d] = %f\n", i, g_floats[i]);
    i = i + 1;
}

print("  Asserting g_floats[0] = ", g_floats[0]);
assertFloatEqual(1.5, g_floats[0]);
print("  Asserting g_floats[1] = ", g_floats[1]);
assertFloatEqual(2.75, g_floats[1]);
print("  Asserting g_floats[2] = ", g_floats[2]);
assertFloatEqual(3.125, g_floats[2]);
print("  PASS: Global float array read/write");
print("");

// === Test 3: Global String Arrays ===
print("Test 3: Global String Arrays");
array g_strings.s[4];
g_strings[0] = "Hello";
g_strings[1] = "World";
g_strings[2] = "Array";
g_strings[3] = "Test";

i = 0;
while i < 4 {
    printf("  g_strings[%d] = %s\n", i, g_strings[i]);
    i = i + 1;
}

print("  Asserting g_strings[0] = ", g_strings[0]);
assertStringEqual("Hello", g_strings[0]);
print("  Asserting g_strings[3] = ", g_strings[3]);
assertStringEqual("Test", g_strings[3]);
print("  PASS: Global string array read/write");
print("");

// === Test 4: Array Expressions ===
print("Test 4: Array Expressions");
g_ints[2] = g_ints[0] + g_ints[1];
print("  g_ints[0] + g_ints[1] = ", g_ints[2]);
assertEqual(30, g_ints[2]);

result = g_ints[4] - g_ints[3];
print("  g_ints[4] - g_ints[3] = ", result);
assertEqual(10, result);

g_floats[2] = g_floats[0] * g_floats[1];
print("  g_floats[0] * g_floats[1] = ", g_floats[2]);
assertFloatEqual(4.125, g_floats[2]);
print("  PASS: Array expressions");
print("");

// === Test 5: Variable Indexing ===
print("Test 5: Variable Indexing");
idx = 1;
g_ints[idx] = 99;
print("  Set g_ints[idx] where idx=1 to 99");
print("  g_ints[1] = ", g_ints[idx]);
assertEqual(99, g_ints[idx]);

idx = idx + 1;
print("  g_ints[2] = ", g_ints[idx]);
assertEqual(30, g_ints[idx]);
print("  PASS: Variable indexing");
print("");

// === Test 6: Local Arrays in Functions ===
print("Test 6: Local Arrays in Functions");

function testLocalInts() {
    array local_ints.i[3];
    local_ints[0] = 100;
    local_ints[1] = 200;
    local_ints[2] = 300;

    print("  Local int array:");
    j = 0;
    while j < 3 {
        printf("    local_ints[%d] = %d\n", j, local_ints[j]);
        j = j + 1;
    }

    print("  Asserting local_ints[0] = ", local_ints[0]);
    assertEqual(100, local_ints[0]);
    print("  Asserting local_ints[2] = ", local_ints[2]);
    assertEqual(300, local_ints[2]);

    sum = local_ints[0] + local_ints[1] + local_ints[2];
    print("  Sum of local_ints = ", sum);
    assertEqual(600, sum);
}

testLocalInts();
print("  PASS: Local int arrays");
print("");

// === Test 7: Local Float Arrays ===
print("Test 7: Local Float Arrays");

function testLocalFloats() {
    array local_floats.f[2];
    local_floats[0] = 1.25;
    local_floats[1] = 2.5;

    print("  Local float array:");
    k = 0;
    while k < 2 {
        printf("    local_floats[%d] = %f\n", k, local_floats[k]);
        k = k + 1;
    }

    print("  Asserting local_floats[0] = ", local_floats[0]);
    assertFloatEqual(1.25, local_floats[0]);

    product = local_floats[0] * local_floats[1];
    print("  Product = ", product);
    assertFloatEqual(3.125, product);
}

testLocalFloats();
print("  PASS: Local float arrays");
print("");

// === Test 8: Local String Arrays ===
print("Test 8: Local String Arrays");

function testLocalStrings() {
    array local_strings.s[3];
    local_strings[0] = "One";
    local_strings[1] = "Two";
    local_strings[2] = "Three";

    print("  Local string array:");
    m = 0;
    while m < 3 {
        printf("    local_strings[%d] = %s\n", m, local_strings[m]);
        m = m + 1;
    }

    print("  Asserting local_strings[1] = ", local_strings[1]);
    assertStringEqual("Two", local_strings[1]);
}

testLocalStrings();
print("  PASS: Local string arrays");
print("");

// === Test 9: Mixed Global and Local Access ===
print("Test 9: Mixed Global and Local Access");

function testMixed() {
    array local_mix.i[2];
    local_mix[0] = g_ints[0];
    local_mix[1] = g_ints[1];

    print("  Copied from global to local:");
    print("    local_mix[0] = ", local_mix[0]);
    print("    local_mix[1] = ", local_mix[1]);
    assertEqual(10, local_mix[0]);
    assertEqual(99, local_mix[1]);

    g_ints[0] = local_mix[0] + local_mix[1];
    print("  Modified global from local: g_ints[0] = ", g_ints[0]);
    assertEqual(109, g_ints[0]);
}

testMixed();
print("  PASS: Mixed global/local access");
print("");

// === Test 10: Functions Returning Array Values ===
print("Test 10: Functions Returning Array Values");

function getArraySum() {
    array nums.i[3];
    nums[0] = 5;
    nums[1] = 10;
    nums[2] = 15;

    total = nums[0] + nums[1] + nums[2];
    print("  Array sum in function = ", total);
    return total;
}

returnedSum = getArraySum();
print("  Returned sum = ", returnedSum);
assertEqual(30, returnedSum);

function getArrayElement() {
    array data.i[4];
    data[0] = 100;
    data[1] = 200;
    data[2] = 300;
    data[3] = 400;

    return data[2];
}

element = getArrayElement();
print("  Returned element = ", element);
assertEqual(300, element);

function computeWithArrays() {
    array a.i[2];
    array b.i[2];

    a[0] = 10;
    a[1] = 20;
    b[0] = 5;
    b[1] = 3;

    result = (a[0] + a[1]) * (b[0] - b[1]);
    print("  Computed result = ", result);
    return result;
}

computed = computeWithArrays();
print("  Final computed value = ", computed);
assertEqual(60, computed);
print("  PASS: Functions returning array values");
print("");

// === Test 11: Nested Function Calls ===
print("Test 11: Nested Function Calls");

function helper1() {
    array h1_array.i[2];
    h1_array[0] = 10;
    h1_array[1] = 20;
    result = h1_array[0] + h1_array[1];
    print("  helper1 result = ", result);
    return result;
}

function helper2() {
    array h2_array.i[2];
    h2_array[0] = 5;
    h2_array[1] = 15;
    val = helper1();
    result = h2_array[0] + h2_array[1] + val;
    print("  helper2 result = ", result);
    return result;
}

final = helper2();
print("  Final result = ", final);
assertEqual(50, final);
print("  PASS: Nested function calls with local arrays");
print("");

// === Test 12: Array Reset Test ===
print("Test 12: Array Reset Test");

function resetTest() {
    array reset_array.i[3];
    reset_array[0] = 1;
    reset_array[1] = 2;
    reset_array[2] = 3;

    n = 0;
    total = 0;
    while n < 3 {
        printf("  reset_array[%d] = %d\n", n, reset_array[n]);
        total = total + reset_array[n];
        n = n + 1;
    }
    return total;
}

sum1 = resetTest();
print("  First call sum = ", sum1);
assertEqual(6, sum1);

print("  Calling again...");
sum2 = resetTest();
print("  Second call sum = ", sum2);
assertEqual(6, sum2);
print("  PASS: Array reset between calls");
print("");

// === Test 13: Constant vs Variable Index ===
print("Test 13: Constant vs Variable Index");

array test_idx.i[3];
test_idx[0] = 11;
test_idx[1] = 22;
test_idx[2] = 33;

print("  Constant index: test_idx[1] = ", test_idx[1]);
assertEqual(22, test_idx[1]);

var_idx = 1;
print("  Variable index: test_idx[var_idx] = ", test_idx[var_idx]);
assertEqual(22, test_idx[var_idx]);

var_idx = 2;
print("  Variable index changed: test_idx[var_idx] = ", test_idx[var_idx]);
assertEqual(33, test_idx[var_idx]);
print("  PASS: Constant and variable indexing");
print("");

// === Test 14: Float Array Returns ===
print("Test 14: Float Array Returns");

function getFloatAverage.f() {
    array values.f[4];
    values[0] = 1.0;
    values[1] = 2.0;
    values[2] = 3.0;
    values[3] = 4.0;

    sum = values[0] + values[1] + values[2] + values[3];
    avg = sum / 4.0;
    print("  Float average = ", avg);
    return avg;
}

avg.f = getFloatAverage();
print("  Returned average = ", avg);
assertFloatEqual(2.5, avg);
print("  PASS: Float array returns");
print("");

// === Test 15: Dynamic Index Expressions (Functions and Calculations) ===
print("Test 15: Dynamic Index Expressions");

function getIndex() {
    return 2;
}

function calculateIndex(offset) {
    return 1 + offset;
}

array dynamic_test.i[5];
dynamic_test[0] = 100;
dynamic_test[1] = 200;
dynamic_test[2] = 300;
dynamic_test[3] = 400;
dynamic_test[4] = 500;

// Test direct function call as index
val1 = dynamic_test[getIndex()];
print("  dynamic_test[getIndex()] where getIndex()=2: ", val1);
assertEqual(300, val1);

// Test function call with addition
val2 = dynamic_test[getIndex() + 1];
print("  dynamic_test[getIndex() + 1]: ", val2);
assertEqual(400, val2);

// Test function call with parameter
val3 = dynamic_test[calculateIndex(1)];
print("  dynamic_test[calculateIndex(1)] where calculateIndex(1)=2: ", val3);
assertEqual(300, val3);

// Test expression in assignment
dynamic_test[getIndex()] = 999;
print("  Set dynamic_test[getIndex()] = 999");
assertEqual(999, dynamic_test[2]);

// Test with float arrays
array float_dynamic.f[3];
float_dynamic[0] = 1.5;
float_dynamic[1] = 2.5;
float_dynamic[2] = 3.5;

fval = float_dynamic[getIndex() - 1];
print("  float_dynamic[getIndex() - 1]: ", fval);
assertFloatEqual(2.5, fval);

// Test with string arrays
array string_dynamic.s[3];
string_dynamic[0] = "Alpha";
string_dynamic[1] = "Beta";
string_dynamic[2] = "Gamma";

sval = string_dynamic[calculateIndex(0)];
print("  string_dynamic[calculateIndex(0)]: ", sval);
assertStringEqual("Beta", sval);

sval = string_dynamic[calculateIndex(0) + calculateIndex(0) + calculateIndex(0) - 1];
print("  string_dynamic[calculateIndex(0) + calculateIndex(0) + calculateIndex(0) - 1]: ", sval);
assertStringEqual("Gamma", sval);

print("  PASS: Dynamic index expressions");
print("");

// === Test 16: Global and Local Array Interaction ===
print("Test 16: Global and Local Array Interaction");

// Global arrays
array global_ints.i[4];
global_ints[0] = 10;
global_ints[1] = 20;
global_ints[2] = 30;
global_ints[3] = 40;

array global_floats.f[3];
global_floats[0] = 1.1;
global_floats[1] = 2.2;
global_floats[2] = 3.3;

array global_strings.s[3];
global_strings[0] = "Red";
global_strings[1] = "Green";
global_strings[2] = "Blue";

function processArrays() {
    // Local arrays
    array local_ints.i[4];
    array local_floats.f[3];
    array local_strings.s[3];

    // Copy from global to local
    print("  Copying from global to local arrays...");
    local_ints[0] = global_ints[0];
    local_ints[1] = global_ints[1];
    local_ints[2] = global_ints[2];
    local_ints[3] = global_ints[3];

    local_floats[0] = global_floats[0];
    local_floats[1] = global_floats[1];
    local_floats[2] = global_floats[2];

    local_strings[0] = global_strings[0];
    local_strings[1] = global_strings[1];
    local_strings[2] = global_strings[2];

    // Verify local arrays have correct values
    print("  Verifying local arrays:");
    print("    local_ints[1] = ", local_ints[1]);
    assertEqual(20, local_ints[1]);
    print("    local_floats[2] = ", local_floats[2]);
    assertFloatEqual(3.3, local_floats[2]);
    print("    local_strings[0] = ", local_strings[0]);
    assertStringEqual("Red", local_strings[0]);

    // Modify local arrays
    print("  Modifying local arrays...");
    local_ints[0] = local_ints[0] * 2;
    local_ints[1] = local_ints[1] * 2;
    local_floats[0] = local_floats[0] + 10.0;
    local_strings[1] = "Yellow";

    // Copy modified values back to global
    print("  Copying modified values back to global...");
    global_ints[0] = local_ints[0];
    global_ints[1] = local_ints[1];
    global_floats[0] = local_floats[0];
    global_strings[1] = local_strings[1];

    // Mixed operations: combine global and local
    result = global_ints[2] + local_ints[2];
    print("  Mixed operation: global_ints[2] + local_ints[2] = ", result);
    assertEqual(60, result);

    fresult = global_floats[1] * local_floats[1];
    print("  Mixed operation: global_floats[1] * local_floats[1] = ", fresult);
    assertFloatEqual(4.84, fresult);
}

processArrays();

// Verify global arrays were modified by function
print("  Verifying global arrays after function:");
print("    global_ints[0] = ", global_ints[0]);
assertEqual(20, global_ints[0]);
print("    global_ints[1] = ", global_ints[1]);
assertEqual(40, global_ints[1]);
print("    global_floats[0] = ", global_floats[0]);
assertFloatEqual(11.1, global_floats[0]);
print("    global_strings[1] = ", global_strings[1]);
assertStringEqual("Yellow", global_strings[1]);

print("  PASS: Global and local array interaction");
print("");

// === All Tests Complete ===
print("=================================");
print("ALL TESTS PASSED!");
print("=================================");
