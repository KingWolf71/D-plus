// Test structures and direct data assignment
// V1.021.0 - New features
// Syntax: p1.StructType = {values}; for declaration
// Syntax: p1\field for field access

#pragma appname "D+AI Structure Test"
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

// =============================================
// Test 1: Structure Definition
// =============================================
print("=== Test 1: Structure Definition ===");

struct Point {
    x.i;
    y.i;
}

struct Data {
    value.i;
    factor.f;
    label.s;
}

// =============================================
// Test 2: Structure Declaration with Init
// =============================================
print("\n=== Test 2: Struct Declaration ===");

p1.Point = {10, 20};
printf("p1\\x = %d\n", p1\x);
printf("p1\\y = %d\n", p1\y);
printf("Sum = %d\n", p1\x + p1\y);

// =============================================
// Test 3: Mixed Type Struct
// =============================================
print("\n=== Test 3: Mixed Type Struct ===");

d.Data = {42, 3.14, "test"};
printf("d\\value = %d\n", d\value);
printf("d\\factor = %f\n", d\factor);
printf("d\\label = %s\n", d\label);

// =============================================
// Test 4: Field Assignment
// =============================================
print("\n=== Test 4: Field Assignment ===");

p1\x = 100;
p1\y = 200;
print("After assignment:");
printf("p1\\x = %d\n", p1\x);
printf("p1\\y = %d\n", p1\y);

// =============================================
// Test 5: Multiple Structs
// =============================================
print("\n=== Test 5: Multiple Structs ===");

origin.Point = {0, 0};
corner.Point = {640, 480};

printf("origin: %d %d\n", origin\x, origin\y);
printf("corner: %d %d\n", corner\x, corner\y);

// =============================================
// Test 6: Struct Field in Expressions
// =============================================
print("\n=== Test 6: Field Expressions ===");

a.Point = {5, 10};
b.Point = {15, 20};

sum.i = a\x + b\x;
printf("a\\x + b\\x = %d\n", sum);

diff.i = b\y - a\y;
printf("b\\y - a\\y = %d\n", diff);

// =============================================
// Test 7: Array Initialization
// =============================================
print("\n=== Test 7: Array Init ===");

array nums.i[5] = {10, 20, 30, 40, 50};
i = 0;
while i < 5 {
    printf("nums[%d] = %d\n", i, nums[i]);
    i++;
}

// =============================================
// Test 8: String Array Init
// =============================================
print("");
print("=== Test 8: String Array Init ===");

array names.s[3] = {"Alice", "Bob", "Charlie"};
print(names[0]);
print(names[1]);
print(names[2]);

print("");
print("All tests completed!");
