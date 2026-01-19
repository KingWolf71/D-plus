// =============================================================================
// D+AI FULL TEST SUITE WITH TALLY (V1.023.26)
// Creative tests for edge cases and unusual combinations
// =============================================================================

#pragma appname "D+AI-Full-Test-Suite"
#pragma decimals 6
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

// =============================================================================
// TALLY SYSTEM
// =============================================================================
gTestsPassed = 0;
gTestsFailed = 0;
gCurrentSection.s = "";
gFailedTests.s = "";

function test(name.s, expected, actual) {
    if (expected == actual) {
        gTestsPassed = gTestsPassed + 1;
        print("  PASS: ", name);
        print("        expected=", expected, " actual=", actual);
        return 1;
    } else {
        gTestsFailed = gTestsFailed + 1;
        gFailedTests = gFailedTests + gCurrentSection + ": " + name + " (expected " + str(expected) + ", got " + str(actual) + ")\n";
        print("  FAIL: ", name);
        print("        expected=", expected, " actual=", actual);
        return 0;
    }
}

function testFloat(name.s, expected.f, actual.f) {
    diff.f = expected - actual;
    if (diff < 0.0) { diff = 0.0 - diff; }
    if (diff < 0.0001) {
        gTestsPassed = gTestsPassed + 1;
        print("  PASS: ", name);
        print("        expected=", expected, " actual=", actual, " (diff=", diff, ")");
        return 1;
    } else {
        gTestsFailed = gTestsFailed + 1;
        gFailedTests = gFailedTests + gCurrentSection + ": " + name + " (expected " + strf(expected) + ", got " + strf(actual) + ")\n";
        print("  FAIL: ", name);
        print("        expected=", expected, " actual=", actual, " (diff=", diff, ")");
        return 0;
    }
}

function testString(name.s, expected.s, actual.s) {
    if (expected == actual) {
        gTestsPassed = gTestsPassed + 1;
        print("  PASS: ", name);
        print("        expected='", expected, "' actual='", actual, "'");
        return 1;
    } else {
        gTestsFailed = gTestsFailed + 1;
        gFailedTests = gFailedTests + gCurrentSection + ": " + name + " (expected '" + expected + "', got '" + actual + "')\n";
        print("  FAIL: ", name);
        print("        expected='", expected, "' actual='", actual, "'");
        return 0;
    }
}

function section(name.s) {
    gCurrentSection = name;
    print("");
    print("=== ", name, " ===");
}

print("========================================");
print("   D+AI FULL TEST SUITE (V1.023.26)");
print("========================================");

// =============================================================================
// SECTION 1: DEEPLY NESTED EXPRESSIONS
// =============================================================================
section("1. Deeply Nested Expressions");

// Test deeply nested parentheses
result = ((((1 + 2) * 3) - 4) / 2);  // ((3*3)-4)/2 = (9-4)/2 = 5/2 = 2
test("Nested parens basic", 2, result);

// Test nested arithmetic with all operators
result = (10 + (5 * (4 - (6 / 2))));  // 10 + (5 * (4 - 3)) = 10 + (5 * 1) = 15
test("Nested all ops", 15, result);

// Test deeply nested with negation
result = -(-(-(-(5))));  // ----5 = 5
test("Quadruple negation", 5, result);

// Test complex nested boolean
a = 5; b = 10; c = 15;
result = ((a < b) && (b < c)) || ((a > c) && (b > a));  // (1 && 1) || (0 && 1) = 1
test("Nested boolean", 1, result);

// =============================================================================
// SECTION 2: CHAINED COMPARISONS AND LOGIC
// =============================================================================
section("2. Chained Logic Operations");

// Chain of AND operations
x = 1; y = 2; z = 3; w = 4;
result = (x < y) && (y < z) && (z < w);  // All true
test("Triple AND chain", 1, result);

// Chain of OR operations
result = (x > y) || (y > z) || (z < w);  // Last one true
test("Triple OR chain", 1, result);

// Mixed AND/OR with precedence
result = (x < y) || (y > z) && (z > w);  // 1 || (0 && 0) = 1
test("Mixed AND/OR", 1, result);

// Complex boolean with NOT
result = !((x >= y) || (z <= y));  // !(0 || 0) = !0 = 1
test("NOT with OR", 1, result);

// =============================================================================
// SECTION 3: OPERATOR PRECEDENCE EDGE CASES
// =============================================================================
section("3. Operator Precedence Edge Cases");

// Multiplication before addition
result = 2 + 3 * 4;  // 2 + 12 = 14
test("Mul before add", 14, result);

// Division before subtraction
result = 20 - 12 / 4;  // 20 - 3 = 17
test("Div before sub", 17, result);

// Unary minus with multiplication
result = -3 * -4;  // 12
test("Neg times neg", 12, result);

// Modulo with other operators
result = 17 % 5 + 3;  // 2 + 3 = 5
test("Modulo then add", 5, result);

// Complex precedence
result = 2 + 3 * 4 - 5 / 5 + 6 % 4;  // 2 + 12 - 1 + 2 = 15
test("Complex precedence", 15, result);

// =============================================================================
// SECTION 4: BOUNDARY VALUE TESTS
// =============================================================================
section("4. Boundary Values");

// Large numbers
bigNum = 1000000;
result = bigNum * 1000;
test("Large multiply", 1000000000, result);

// Zero edge cases
result = 0 * 999999;
test("Zero times large", 0, result);

result = 999999 * 0;
test("Large times zero", 0, result);

// Division edge cases
result = 0 / 100;
test("Zero divided", 0, result);

// Modulo edge cases
result = 100 % 100;
test("N mod N", 0, result);

result = 99 % 100;
test("N-1 mod N", 99, result);

result = 1 % 100;
test("1 mod N", 1, result);

// =============================================================================
// SECTION 5: FLOAT PRECISION TESTS
// =============================================================================
section("5. Float Precision");

// Small float operations
small.f = 0.001;
resultF.f = small * 1000.0;
testFloat("Small float scale up", 1.0, resultF);

// Float accumulation
sumF.f = 0.0;
i = 0;
while (i < 10) {
    sumF = sumF + 0.1;
    i = i + 1;
}
testFloat("Float accumulation", 1.0, sumF);

// Float division precision
f1.f = 1.0;
f2.f = 3.0;
f3.f = f1 / f2;
f4.f = f3 * 3.0;
testFloat("1/3 * 3", 1.0, f4);

// Very small number
tiny.f = 0.0001;
tinyResult.f = tiny * tiny;  // 0.00000001
testFloat("Tiny squared", 0.00000001, tinyResult);

// =============================================================================
// SECTION 6: RECURSIVE FUNCTION TESTS
// =============================================================================
section("6. Recursive Functions");

// Fibonacci
function fib(n) {
    if (n <= 1) { return n; }
    return fib(n - 1) + fib(n - 2);
}

test("Fibonacci 0", 0, fib(0));
test("Fibonacci 1", 1, fib(1));
test("Fibonacci 5", 5, fib(5));
test("Fibonacci 10", 55, fib(10));

// Factorial
function fact(n) {
    if (n <= 1) { return 1; }
    return n * fact(n - 1);
}

test("Factorial 0", 1, fact(0));
test("Factorial 1", 1, fact(1));
test("Factorial 5", 120, fact(5));
test("Factorial 7", 5040, fact(7));

// Ackermann (small values only!)
function ack(m, n) {
    if (m == 0) { return n + 1; }
    if (n == 0) { return ack(m - 1, 1); }
    return ack(m - 1, ack(m, n - 1));
}

test("Ackermann 0,0", 1, ack(0, 0));
test("Ackermann 1,1", 3, ack(1, 1));
test("Ackermann 2,2", 7, ack(2, 2));
test("Ackermann 3,2", 29, ack(3, 2));

// =============================================================================
// SECTION 7: FUNCTION COMPOSITION
// =============================================================================
section("7. Function Composition");

function double(x) { return x * 2; }
function square(x) { return x * x; }
function addTen(x) { return x + 10; }

// Nested function calls
result = double(square(3));  // square(3)=9, double(9)=18
test("double(square(3))", 18, result);

result = square(double(3));  // double(3)=6, square(6)=36
test("square(double(3))", 36, result);

result = addTen(double(square(2)));  // square(2)=4, double(4)=8, addTen(8)=18
test("addTen(double(square(2)))", 18, result);

// Function results in expressions
result = double(3) + square(4);  // 6 + 16 = 22
test("double(3)+square(4)", 22, result);

result = double(3) * square(2);  // 6 * 4 = 24
test("double(3)*square(2)", 24, result);

// =============================================================================
// SECTION 8: CONTROL FLOW EDGE CASES
// =============================================================================
section("8. Control Flow Edge Cases");

// Empty loop body (0 iterations)
count = 0;
i = 10;
while (i < 10) {
    count = count + 1;
    i = i + 1;
}
test("Zero iteration loop", 0, count);

// Single iteration loop
count = 0;
i = 0;
while (i < 1) {
    count = count + 1;
    i = i + 1;
}
test("Single iteration loop", 1, count);

// Nested loops with break simulation
sum = 0;
i = 0;
while (i < 5) {
    j = 0;
    while (j < 5) {
        sum = sum + 1;
        j = j + 1;
    }
    i = i + 1;
}
test("Nested 5x5 loop", 25, sum);

// Deeply nested if-else
val = 50;
if (val < 25) {
    result = 1;
} else {
    if (val < 50) {
        result = 2;
    } else {
        if (val < 75) {
            result = 3;
        } else {
            result = 4;
        }
    }
}
test("Deep if-else chain", 3, result);

// =============================================================================
// SECTION 9: TERNARY OPERATOR TESTS
// =============================================================================
section("9. Ternary Operator");

// Basic ternary
result = (5 > 3) ? 100 : 200;
test("Basic ternary true", 100, result);

result = (3 > 5) ? 100 : 200;
test("Basic ternary false", 200, result);

// Nested ternary
val = 50;
result = (val < 30) ? 1 : ((val < 60) ? 2 : 3);
test("Nested ternary", 2, result);

// Ternary with expressions
a = 10; b = 20;
result = (a < b) ? (a + b) : (a - b);
test("Ternary with expr true", 30, result);

result = (a > b) ? (a + b) : (a * b);
test("Ternary with expr false", 200, result);

// Ternary in function call
function pick(cond, a, b) {
    return cond ? a : b;
}
test("Ternary in function", 42, pick(1, 42, 99));
test("Ternary in function false", 99, pick(0, 42, 99));

// =============================================================================
// SECTION 10: ARRAY OPERATIONS
// =============================================================================
section("10. Array Operations");

// Array initialization and access
Array nums[10];
i = 0;
while (i < 10) {
    nums[i] = i * i;
    i = i + 1;
}
test("Array squares 0", 0, nums[0]);
test("Array squares 5", 25, nums[5]);
test("Array squares 9", 81, nums[9]);

// Array sum
sum = 0;
i = 0;
while (i < 10) {
    sum = sum + nums[i];
    i = i + 1;
}
test("Array sum of squares", 285, sum);  // 0+1+4+9+16+25+36+49+64+81

// Array reverse copy
Array nums2[10];
i = 0;
while (i < 10) {
    nums2[i] = nums[9 - i];
    i = i + 1;
}
test("Reverse array first", 81, nums2[0]);
test("Reverse array last", 0, nums2[9]);

// =============================================================================
// SECTION 11: STRING OPERATIONS
// =============================================================================
section("11. String Operations");

// String concatenation
s1.s = "Hello";
s2.s = " World";
s3.s = s1 + s2;
testString("String concat", "Hello World", s3);

// String with numbers
num = 42;
s4.s = "Value: " + str(num);
testString("String with int", "Value: 42", s4);

// Multiple concatenation
s5.s = "W" + "X" + "Y" + "Z";
testString("Multi concat", "WXYZ", s5);

// Empty string handling
empty.s = "";
s6.s = empty + "test";
testString("Empty prefix", "test", s6);

s7.s = "test" + empty;
testString("Empty suffix", "test", s7);

// =============================================================================
// SECTION 12: STRUCTURE TESTS
// =============================================================================
section("12. Structure Operations");

struct Vector3 {
    x.f;
    y.f;
    z.f;
}

// Structure initialization
v1.Vector3 = {1.0, 2.0, 3.0};
testFloat("Struct init x", 1.0, v1\x);
testFloat("Struct init y", 2.0, v1\y);
testFloat("Struct init z", 3.0, v1\z);

// Structure field modification
v1\x = 10.0;
testFloat("Struct modify x", 10.0, v1\x);

// Structure copy
v2.Vector3 = v1;
testFloat("Struct copy x", 10.0, v2\x);
testFloat("Struct copy y", 2.0, v2\y);

// Modify copy doesn't affect original
v2\x = 99.0;
testFloat("Original unchanged", 10.0, v1\x);
testFloat("Copy changed", 99.0, v2\x);

// =============================================================================
// SECTION 13: POINTER TESTS
// =============================================================================
section("13. Pointer Operations");

// Basic pointer
ptrTarget = 42;
ptr = &ptrTarget;
test("Pointer deref", 42, *ptr);

// Modify through pointer
*ptr = 100;
test("Modify via pointer", 100, ptrTarget);

// Pointer arithmetic
Array ptrArr[5];
ptrArr[0] = 10;
ptrArr[1] = 20;
ptrArr[2] = 30;
ptrArr[3] = 40;
ptrArr[4] = 50;

arrPtr = &ptrArr[0];
test("Array ptr [0]", 10, *arrPtr);
arrPtr = arrPtr + 1;
test("Array ptr [1]", 20, *arrPtr);
arrPtr = arrPtr + 2;
test("Array ptr [3]", 40, *arrPtr);

// =============================================================================
// SECTION 14: STRUCT POINTERS
// =============================================================================
section("14. Struct Pointers");

struct Point {
    x.i;
    y.i;
}

p1.Point = {100, 200};
pPtr = &p1;

test("Struct ptr x", 100, pPtr\x);
test("Struct ptr y", 200, pPtr\y);

// Modify through struct pointer
pPtr\x = 999;
test("Modified via ptr", 999, p1\x);

// Struct pointer in function
function movePoint(dx, dy) {
    localPtr = &p1;
    localPtr\x = p1\x + dx;
    localPtr\y = p1\y + dy;
}

movePoint(1, 1);
test("Func struct ptr x", 1000, p1\x);
test("Func struct ptr y", 201, p1\y);

// =============================================================================
// SECTION 15: MIXED TYPE ARITHMETIC
// =============================================================================
section("15. Mixed Type Arithmetic");

// Int to float promotion
intVal = 5;
floatVal.f = 2.5;
mixedResult.f = intVal * floatVal;  // 5 * 2.5 = 12.5
testFloat("Int * float", 12.5, mixedResult);

mixedResult = intVal + floatVal;  // 5 + 2.5 = 7.5
testFloat("Int + float", 7.5, mixedResult);

// Division with int operands producing float
intA = 7;
intB = 2;
divResult.f = intA;
divResult = divResult / intB;  // 7.0 / 2 = 3.5
testFloat("Int division to float", 3.5, divResult);

// =============================================================================
// SECTION 16: SPECIAL VALUES
// =============================================================================
section("16. Special Values");

// Boolean-like values
trueVal = 1;
falseVal = 0;
test("True is 1", 1, trueVal);
test("False is 0", 0, falseVal);

// Negation of boolean
test("Not true", 0, !trueVal);
test("Not false", 1, !falseVal);

// Double negation
test("Not not true", 1, !!trueVal);
test("Not not false", 0, !!falseVal);

// =============================================================================
// SECTION 17: LOOP ACCUMULATOR PATTERNS
// =============================================================================
section("17. Loop Patterns");

// Sum 1 to N
sum = 0;
i = 1;
while (i <= 100) {
    sum = sum + i;
    i = i + 1;
}
test("Sum 1 to 100", 5050, sum);  // n(n+1)/2 = 100*101/2

// Product (factorial via loop)
prod = 1;
i = 1;
while (i <= 6) {
    prod = prod * i;
    i = i + 1;
}
test("6! via loop", 720, prod);

// Count evens in range
count = 0;
i = 1;
while (i <= 20) {
    if (i % 2 == 0) {
        count = count + 1;
    }
    i = i + 1;
}
test("Evens 1-20", 10, count);

// Find max in computed sequence
max = 0;
i = 0;
while (i < 10) {
    val = (i * 7) % 13;  // Pseudo-random sequence
    if (val > max) {
        max = val;
    }
    i = i + 1;
}
test("Max in sequence", 11, max);  // 0,7,1,8,2,9,3,10,4,11 -> max = 11
// Actually recomputing: i=0->0, i=1->7, i=2->1, i=3->8, i=4->2, i=5->9, i=6->3, i=7->10, i=8->4, i=9->11 -> max=11

// =============================================================================
// SECTION 18: GCD AND LCM
// =============================================================================
section("18. GCD and LCM");

// GCD using Euclidean algorithm
function gcd(a, b) {
    while (b != 0) {
        temp = b;
        b = a % b;
        a = temp;
    }
    return a;
}

test("GCD 12,8", 4, gcd(12, 8));
test("GCD 17,13", 1, gcd(17, 13));
test("GCD 100,25", 25, gcd(100, 25));
test("GCD 48,18", 6, gcd(48, 18));

// LCM = a * b / gcd(a, b)
function lcm(a, b) {
    return (a * b) / gcd(a, b);
}

test("LCM 4,6", 12, lcm(4, 6));
test("LCM 3,5", 15, lcm(3, 5));
test("LCM 12,18", 36, lcm(12, 18));

// =============================================================================
// SECTION 19: PRIME NUMBER TESTS
// =============================================================================
section("19. Prime Numbers");

function isPrime(n) {
    if (n < 2) { return 0; }
    if (n == 2) { return 1; }
    if (n % 2 == 0) { return 0; }
    j = 3;
    while (j * j <= n) {
        if (n % j == 0) { return 0; }
        j = j + 2;
    }
    return 1;
}

test("isPrime 1", 0, isPrime(1));
test("isPrime 2", 1, isPrime(2));
test("isPrime 3", 1, isPrime(3));
test("isPrime 4", 0, isPrime(4));
test("isPrime 17", 1, isPrime(17));
test("isPrime 18", 0, isPrime(18));
test("isPrime 97", 1, isPrime(97));

// Count primes up to 50
count = 0;
i = 2;
while (i <= 50) {
    if (isPrime(i)) {
        count = count + 1;
    }
    i = i + 1;
}
test("Primes <= 50", 15, count);  // 2,3,5,7,11,13,17,19,23,29,31,37,41,43,47

// =============================================================================
// SECTION 20: BITWISE-LIKE OPERATIONS (using mod/div)
// =============================================================================
section("20. Bit Manipulation Simulation");

// Extract "bits" using mod and division
function getBit(n, pos) {
    // Get bit at position (0-indexed from right)
    divisor = 1;
    i = 0;
    while (i < pos) {
        divisor = divisor * 2;
        i = i + 1;
    }
    return (n / divisor) % 2;
}

// Test with number 42 = 101010 in binary
test("Bit 0 of 42", 0, getBit(42, 0));
test("Bit 1 of 42", 1, getBit(42, 1));
test("Bit 2 of 42", 0, getBit(42, 2));
test("Bit 3 of 42", 1, getBit(42, 3));
test("Bit 4 of 42", 0, getBit(42, 4));
test("Bit 5 of 42", 1, getBit(42, 5));

// Power of 2 check
function isPowerOf2(n) {
    if (n <= 0) { return 0; }
    while (n > 1) {
        if (n % 2 != 0) { return 0; }
        n = n / 2;
    }
    return 1;
}

test("isPow2 1", 1, isPowerOf2(1));
test("isPow2 2", 1, isPowerOf2(2));
test("isPow2 3", 0, isPowerOf2(3));
test("isPow2 16", 1, isPowerOf2(16));
test("isPow2 17", 0, isPowerOf2(17));
test("isPow2 64", 1, isPowerOf2(64));

// =============================================================================
// FINAL SUMMARY
// =============================================================================
print("");
print("========================================");
print("           TEST RESULTS");
print("========================================");
print("");
print("Total Passed: ", gTestsPassed);
print("Total Failed: ", gTestsFailed);
print("Total Tests:  ", gTestsPassed + gTestsFailed);
print("");

if (gTestsFailed == 0) {
    print("*** ALL TESTS PASSED! ***");
} else {
    print("*** SOME TESTS FAILED ***");
    print("");
    print("Failed Tests:");
    print("-------------");
    print(gFailedTests);
}

print("");
print("========================================");
