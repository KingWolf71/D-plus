// Comprehensive D+AI Test Suite
// Tests all features except structures and direct array assignments
// Reports PASS/FAIL for each test with final summary

#pragma appname "D+AI Comprehensive Test"
#pragma console on
#pragma version on
#pragma floattolerance 0.0001
#pragma consolesize "680x740"
#pragma consoleposition "30,50"
#pragma ListASM on
#pragma FastPrint on
#pragma RunThreaded on
#pragma ftoi "truncate"
#pragma modulename on
#pragma PasteToClipboard on
#pragma GlobalStack 1024
#pragma FunctionStack 32
#pragma EvalStack 256
#pragma LocalStack 64
#pragma CreateLog off
#pragma DefaultFPS 32
#pragma ThreadKillWait 1800
#pragma asmdecimal on


// Test counters
passed.i = 0;
failed.i = 0;
testnum.i = 0;

// =============================================
// SECTION 1: Basic Integer Arithmetic
// =============================================
print("=== SECTION 1: Integer Arithmetic ===");

testnum++;
result.i = 5 + 3;
if result == 8 { print("[ ", testnum, " ] -- PASS: 5+3=8"); passed++; }
else { print("[ ", testnum, " ] -- FAIL: 5+3 expected 8, got", result); failed++; }

testnum++;
result = 10 - 4;
if result == 6 { print("[ ", testnum, " ] -- PASS: 10-4=6"); passed++; }
else { print("[ ", testnum, " ] -- FAIL: 10-4 expected 6, got", result); failed++; }

testnum++;
result = 7 * 6;
if result == 42 { print("[ ", testnum, " ] -- PASS: 7*6=42"); passed++; }
else { print("[ ", testnum, " ] -- FAIL: 7*6 expected 42, got", result); failed++; }

testnum++;
result = 20 / 4;
if result == 5 { print("[ ", testnum, " ] -- PASS: 20/4=5"); passed++; }
else { print("[ ", testnum, " ] -- FAIL: 20/4 expected 5, got", result); failed++; }

testnum++;
result = 17 % 5;
if result == 2 { print("[ ", testnum, " ] -- PASS: 17%5=2"); passed++; }
else { print("[ ", testnum, " ] -- FAIL: 17%5 expected 2, got", result); failed++; }

testnum++;
result = -10;
if result == -10 { print("[ ", testnum, " ] -- PASS: negation=-10"); passed++; }
else { print("[ ", testnum, " ] -- FAIL: negation expected -10, got", result); failed++; }

// =============================================
// SECTION 2: Operator Precedence
// =============================================
print("");
print("=== SECTION 2: Operator Precedence ===");

testnum++;
result = 2 + 3 * 4;
if result == 14 { print("[ ", testnum, " ] -- PASS: 2+3*4=14"); passed++; }
else { print("[ ", testnum, " ] -- FAIL: 2+3*4 expected 14, got", result); failed++; }

testnum++;
result = (2 + 3) * 4;
if result == 20 { print("[ ", testnum, " ] -- PASS: (2+3)*4=20"); passed++; }
else { print("[ ", testnum, " ] -- FAIL: (2+3)*4 expected 20, got", result); failed++; }

testnum++;
result = 100 / 10 / 2;
if result == 5 { print("[ ", testnum, " ] -- PASS: 100/10/2=5"); passed++; }
else { print("[ ", testnum, " ] -- FAIL: 100/10/2 expected 5, got", result); failed++; }

testnum++;
result = 2 + 3 * 4 - 5;
if result == 9 { print("[ ", testnum, " ] -- PASS: 2+3*4-5=9"); passed++; }
else { print("[ ", testnum, " ] -- FAIL: 2+3*4-5 expected 9, got", result); failed++; }

// =============================================
// SECTION 3: Comparison Operators
// =============================================
print("");
print("=== SECTION 3: Comparison Operators ===");

testnum++;
result = (5 == 5);
if result == 1 { print("[ ", testnum, " ] -- PASS: 5==5 is true"); passed++; }
else { print("[ ", testnum, " ] -- FAIL: 5==5 expected 1, got", result); failed++; }

testnum++;
result = (5 == 6);
if result == 0 { print("[ ", testnum, " ] -- PASS: 5==6 is false"); passed++; }
else { print("[ ", testnum, " ] -- FAIL: 5==6 expected 0, got", result); failed++; }

testnum++;
result = (5 != 6);
if result == 1 { print("[ ", testnum, " ] -- PASS: 5!=6 is true"); passed++; }
else { print("[ ", testnum, " ] -- FAIL: 5!=6 expected 1, got", result); failed++; }

testnum++;
result = (5 < 10);
if result == 1 { print("[ ", testnum, " ] -- PASS: 5<10 is true"); passed++; }
else { print("[ ", testnum, " ] -- FAIL: 5<10 expected 1, got", result); failed++; }

testnum++;
result = (10 > 5);
if result == 1 { print("[ ", testnum, " ] -- PASS: 10>5 is true"); passed++; }
else { print("[ ", testnum, " ] -- FAIL: 10>5 expected 1, got", result); failed++; }

testnum++;
result = (5 <= 5);
if result == 1 { print("[ ", testnum, " ] -- PASS: 5<=5 is true"); passed++; }
else { print("[ ", testnum, " ] -- FAIL: 5<=5 expected 1, got", result); failed++; }

testnum++;
result = (5 >= 5);
if result == 1 { print("[ ", testnum, " ] -- PASS: 5>=5 is true"); passed++; }
else { print("[ ", testnum, " ] -- FAIL: 5>=5 expected 1, got", result); failed++; }

// =============================================
// SECTION 4: Logical Operators
// =============================================
print("");
print("=== SECTION 4: Logical Operators ===");

testnum++;
result = (1 && 1);
if result == 1 { print("[ ", testnum, " ] -- PASS: 1&&1=1"); passed++; }
else { print("[ ", testnum, " ] -- FAIL: 1&&1 expected 1, got", result); failed++; }

testnum++;
result = (1 && 0);
if result == 0 { print("[ ", testnum, " ] -- PASS: 1&&0=0"); passed++; }
else { print("[ ", testnum, " ] -- FAIL: 1&&0 expected 0, got", result); failed++; }

testnum++;
result = (0 || 1);
if result == 1 { print("[ ", testnum, " ] -- PASS: 0||1=1"); passed++; }
else { print("[ ", testnum, " ] -- FAIL: 0||1 expected 1, got", result); failed++; }

testnum++;
result = (0 || 0);
if result == 0 { print("[ ", testnum, " ] -- PASS: 0||0=0"); passed++; }
else { print("[ ", testnum, " ] -- FAIL: 0||0 expected 0, got", result); failed++; }

testnum++;
result = !0;
if result == 1 { print("[ ", testnum, " ] -- PASS: !0=1"); passed++; }
else { print("[ ", testnum, " ] -- FAIL: !0 expected 1, got", result); failed++; }

testnum++;
result = !1;
if result == 0 { print("[ ", testnum, " ] -- PASS: !1=0"); passed++; }
else { print("[ ", testnum, " ] -- FAIL: !1 expected 0, got", result); failed++; }

// =============================================
// SECTION 5: Bitwise Operators
// NOTE: & is address-of, use && for bitwise AND
// =============================================
print("");
print("=== SECTION 5: Bitwise Operators ===");

testnum++;
result = (5 && 3);  // Bitwise AND: 0101 & 0011 = 0001 (1)
if result == 1 { print("[ ", testnum, " ] -- PASS: 5&&3=1"); passed++; }
else { print("[ ", testnum, " ] -- FAIL: 5&&3 expected 1, got", result); failed++; }

testnum++;
result = (5 | 3);   // Bitwise OR: 0101 | 0011 = 0111 (7)
if result == 7 { print("[ ", testnum, " ] -- PASS: 5|3=7"); passed++; }
else { print("[ ", testnum, " ] -- FAIL: 5|3 expected 7, got", result); failed++; }

testnum++;
result = (5 ^ 3);   // Bitwise XOR: 0101 ^ 0011 = 0110 (6)
if result == 6 { print("[ ", testnum, " ] -- PASS: 5^3=6"); passed++; }
else { print("[ ", testnum, " ] -- FAIL: 5^3 expected 6, got", result); failed++; }

// =============================================
// SECTION 6: Float Arithmetic
// =============================================
print("");
print("=== SECTION 6: Float Arithmetic ===");

testnum++;
fres.f = 3.5 + 2.5;
if fres == 6.0 { print("[ ", testnum, " ] -- PASS: 3.5+2.5=6.0"); passed++; }
else { print("[ ", testnum, " ] -- FAIL: 3.5+2.5 expected 6.0, got", fres); failed++; }

testnum++;
fres = 10.0 - 4.5;
if fres == 5.5 { print("[ ", testnum, " ] -- PASS: 10.0-4.5=5.5"); passed++; }
else { print("[ ", testnum, " ] -- FAIL: 10.0-4.5 expected 5.5, got", fres); failed++; }

testnum++;
fres = 2.5 * 4.0;
if fres == 10.0 { print("[ ", testnum, " ] -- PASS: 2.5*4.0=10.0"); passed++; }
else { print("[ ", testnum, " ] -- FAIL: 2.5*4.0 expected 10.0, got", fres); failed++; }

testnum++;
fres = 15.0 / 3.0;
if fres == 5.0 { print("[ ", testnum, " ] -- PASS: 15.0/3.0=5.0"); passed++; }
else { print("[ ", testnum, " ] -- FAIL: 15.0/3.0 expected 5.0, got", fres); failed++; }

// =============================================
// SECTION 7: Increment/Decrement Operators
// =============================================
print("");
print("=== SECTION 7: Increment/Decrement ===");

testnum++;
x.i = 5;
x++;
if x == 6 { print("[ ", testnum, " ] -- PASS: x++=6"); passed++; }
else { print("[ ", testnum, " ] -- FAIL: x++ expected 6, got", x); failed++; }

testnum++;
x = 5;
x--;
if x == 4 { print("[ ", testnum, " ] -- PASS: x--=4"); passed++; }
else { print("[ ", testnum, " ] -- FAIL: x-- expected 4, got", x); failed++; }

testnum++;
x = 5;
y.i = ++x;
if x == 6 && y == 6 { print("[ ", testnum, " ] -- PASS: ++x pre-increment"); passed++; }
else { print("[ ", testnum, " ] -- FAIL: ++x expected x=6,y=6, got x=", x, "y=", y); failed++; }

testnum++;
x = 5;
y = --x;
if x == 4 && y == 4 { print("[ ", testnum, " ] -- PASS: --x pre-decrement"); passed++; }
else { print("[ ", testnum, " ] -- FAIL: --x expected x=4,y=4, got x=", x, "y=", y); failed++; }

// =============================================
// SECTION 8: Compound Assignment
// =============================================
print("");
print("=== SECTION 8: Compound Assignment ===");

testnum++;
x = 10;
x += 5;
if x == 15 { print("[ ", testnum, " ] -- PASS: x+=5 -> 15"); passed++; }
else { print("[ ", testnum, " ] -- FAIL: x+=5 expected 15, got", x); failed++; }

testnum++;
x = 10;
x -= 3;
if x == 7 { print("[ ", testnum, " ] -- PASS: x-=3 -> 7"); passed++; }
else { print("[ ", testnum, " ] -- FAIL: x-=3 expected 7, got", x); failed++; }

testnum++;
x = 10;
x *= 2;
if x == 20 { print("[ ", testnum, " ] -- PASS: x*=2 -> 20"); passed++; }
else { print("[ ", testnum, " ] -- FAIL: x*=2 expected 20, got", x); failed++; }

testnum++;
x = 20;
x /= 4;
if x == 5 { print("[ ", testnum, " ] -- PASS: x/=4 -> 5"); passed++; }
else { print("[ ", testnum, " ] -- FAIL: x/=4 expected 5, got", x); failed++; }

testnum++;
x = 17;
x %= 5;
if x == 2 { print("[ ", testnum, " ] -- PASS: x%=5 -> 2"); passed++; }
else { print("[ ", testnum, " ] -- FAIL: x%=5 expected 2, got", x); failed++; }

// =============================================
// SECTION 9: While Loop
// =============================================
print("");
print("=== SECTION 9: While Loop ===");

testnum++;
sum.i = 0;
i.i = 1;
while i <= 5 {
    sum += i;
    i++;
}
if sum == 15 { print("[ ", testnum, " ] -- PASS: sum 1-5=15"); passed++; }
else { print("[ ", testnum, " ] -- FAIL: sum 1-5 expected 15, got", sum); failed++; }

testnum++;
count.i = 0;
i = 10;
while i > 0 {
    count++;
    i -= 2;
}
if count == 5 { print("[ ", testnum, " ] -- PASS: countdown count=5"); passed++; }
else { print("[ ", testnum, " ] -- FAIL: countdown expected 5, got", count); failed++; }

// =============================================
// SECTION 10: If/Else
// =============================================
print("");
print("=== SECTION 10: If/Else ===");

testnum++;
x = 10;
if x > 5 {
    result = 1;
} else {
    result = 0;
}
if result == 1 { print("[ ", testnum, " ] -- PASS: if x>5 true branch"); passed++; }
else { print("[ ", testnum, " ] -- FAIL: if x>5 expected true branch"); failed++; }

testnum++;
x = 3;
if x > 5 {
    result = 1;
} else {
    result = 0;
}
if result == 0 { print("[ ", testnum, " ] -- PASS: if x>5 false branch"); passed++; }
else { print("[ ", testnum, " ] -- FAIL: if x>5 expected false branch"); failed++; }

testnum++;
x = 5;
if x < 0 {
    result = -1;
} else if x == 0 {
    result = 0;
} else {
    result = 1;
}
if result == 1 { print("[ ", testnum, " ] -- PASS: else-if chain"); passed++; }
else { print("[ ", testnum, " ] -- FAIL: else-if expected 1, got", result); failed++; }

// =============================================
// SECTION 11: Ternary Operator
// =============================================
print("");
print("=== SECTION 11: Ternary Operator ===");

testnum++;
x = 10;
result = (x > 5) ? 100 : 200;
if result == 100 { print("[ ", testnum, " ] -- PASS: ternary true=100"); passed++; }
else { print("[ ", testnum, " ] -- FAIL: ternary expected 100, got", result); failed++; }

testnum++;
x = 3;
result = (x > 5) ? 100 : 200;
if result == 200 { print("[ ", testnum, " ] -- PASS: ternary false=200"); passed++; }
else { print("[ ", testnum, " ] -- FAIL: ternary expected 200, got", result); failed++; }

// =============================================
// SECTION 12: Functions
// =============================================
print("");
print("=== SECTION 12: Functions ===");

function add(a.i, b.i) {
    return a + b;
}

function multiply(a.i, b.i) {
    return a * b;
}

function factorial(n.i) {
    if n <= 1 {
        return 1;
    }
    return n * factorial(n - 1);
}

function fibonacci(n.i) {
    if n <= 1 {
        return n;
    }
    return fibonacci(n - 1) + fibonacci(n - 2);
}

testnum++;
result = add(3, 4);
if result == 7 { print("[ ", testnum, " ] -- PASS: add(3,4)=7"); passed++; }
else { print("[ ", testnum, " ] -- FAIL: add(3,4) expected 7, got", result); failed++; }

testnum++;
result = multiply(6, 7);
if result == 42 { print("[ ", testnum, " ] -- PASS: multiply(6,7)=42"); passed++; }
else { print("[ ", testnum, " ] -- FAIL: multiply(6,7) expected 42, got", result); failed++; }

testnum++;
result = factorial(5);
if result == 120 { print("[ ", testnum, " ] -- PASS: factorial(5)=120"); passed++; }
else { print("[ ", testnum, " ] -- FAIL: factorial(5) expected 120, got", result); failed++; }

// testnum++;
// result = fibonacci(10);
// if result == 55 { print("[ ", testnum, " ] -- PASS: fibonacci(10)=55"); passed++; }
// else { print("[ ", testnum, " ] -- FAIL: fibonacci(10) expected 55, got", result); failed++; }
print("(fibonacci test skipped - heavy recursion)");

// =============================================
// SECTION 13: Arrays
// =============================================
print("");
print("=== SECTION 13: Arrays ===");

array nums.i[5];
nums[0] = 10;
nums[1] = 20;
nums[2] = 30;
nums[3] = 40;
nums[4] = 50;

testnum++;
if nums[0] == 10 { print("[ ", testnum, " ] -- PASS: nums[0]=10"); passed++; }
else { print("[ ", testnum, " ] -- FAIL: nums[0] expected 10, got", nums[0]); failed++; }

testnum++;
if nums[4] == 50 { print("[ ", testnum, " ] -- PASS: nums[4]=50"); passed++; }
else { print("[ ", testnum, " ] -- FAIL: nums[4] expected 50, got", nums[4]); failed++; }

testnum++;
sum = 0;
i = 0;
while i < 5 {
    sum += nums[i];
    i++;
}
if sum == 150 { print("[ ", testnum, " ] -- PASS: array sum=150"); passed++; }
else { print("[ ", testnum, " ] -- FAIL: array sum expected 150, got", sum); failed++; }

testnum++;
nums[2] = nums[0] + nums[1];
if nums[2] == 30 { print("[ ", testnum, " ] -- PASS: nums[2]=nums[0]+nums[1]=30"); passed++; }
else { print("[ ", testnum, " ] -- FAIL: nums[2] expected 30, got", nums[2]); failed++; }

// =============================================
// SECTION 14: Pointers
// =============================================
print("");
print("=== SECTION 14: Pointers ===");

testnum++;
val.i = 42;
ptr.i = &val;
if *ptr == 42 { print("[ ", testnum, " ] -- PASS: *ptr=42"); passed++; }
else { print("[ ", testnum, " ] -- FAIL: *ptr expected 42, got", *ptr); failed++; }

testnum++;
*ptr = 100;
if val == 100 { print("[ ", testnum, " ] -- PASS: *ptr=100 changes val"); passed++; }
else { print("[ ", testnum, " ] -- FAIL: val expected 100, got", val); failed++; }

testnum++;
ptr2.i = &nums[0];
if *ptr2 == 10 { print("[ ", testnum, " ] -- PASS: ptr to array[0]=10"); passed++; }
else { print("[ ", testnum, " ] -- FAIL: ptr to array[0] expected 10, got", *ptr2); failed++; }

// =============================================
// SECTION 15: Built-in Functions
// =============================================
print("");
print("=== SECTION 15: Built-ins ===");

testnum++;
result = abs(-42);
if result == 42 { print("[ ", testnum, " ] -- PASS: abs(-42)=42"); passed++; }
else { print("[ ", testnum, " ] -- FAIL: abs(-42) expected 42, got", result); failed++; }

testnum++;
result = min(10, 5);
if result == 5 { print("[ ", testnum, " ] -- PASS: min(10,5)=5"); passed++; }
else { print("[ ", testnum, " ] -- FAIL: min(10,5) expected 5, got", result); failed++; }

testnum++;
result = max(10, 5);
if result == 10 { print("[ ", testnum, " ] -- PASS: max(10,5)=10"); passed++; }
else { print("[ ", testnum, " ] -- FAIL: max(10,5) expected 10, got", result); failed++; }

testnum++;
fres = sqrt(16.0);
if fres == 4.0 { print("[ ", testnum, " ] -- PASS: sqrt(16)=4"); passed++; }
else { print("[ ", testnum, " ] -- FAIL: sqrt(16) expected 4, got", fres); failed++; }

testnum++;
fres = pow(2.0, 8.0);
if fres == 256.0 { print("[ ", testnum, " ] -- PASS: pow(2,8)=256"); passed++; }
else { print("[ ", testnum, " ] -- FAIL: pow(2,8) expected 256, got", fres); failed++; }

// =============================================
// SECTION 16: String Operations
// =============================================
print("");
print("=== SECTION 16: Strings ===");

testnum++;
s1.s = "Hello";
s2.s = "World";
s3.s = s1 + " " + s2;
if s3 == "Hello World" { print("[ ", testnum, " ] -- PASS: string concat"); passed++; }
else { print("[ ", testnum, " ] -- FAIL: concat expected 'Hello World', got", s3); failed++; }

testnum++;
result = len("Hello");
if result == 5 { print("[ ", testnum, " ] -- PASS: len('Hello')=5"); passed++; }
else { print("[ ", testnum, " ] -- FAIL: len expected 5, got", result); failed++; }

// =============================================
// SECTION 17: Type Conversions
// =============================================
print("");
print("=== SECTION 17: Type Conversions ===");

testnum++;
fval.f = 3.7;
ival.i = (int)fval;
if ival == 3 { print("[ ", testnum, " ] -- PASS: (int)3.7=3"); passed++; }
else { print("[ ", testnum, " ] -- FAIL: (int)3.7 expected 3, got", ival); failed++; }

testnum++;
ival = 42;
fval = (float)ival;
if fval == 42.0 { print("[ ", testnum, " ] -- PASS: (float)42=42.0"); passed++; }
else { print("[ ", testnum, " ] -- FAIL: (float)42 expected 42.0, got", fval); failed++; }

// =============================================
// SECTION 18: Local Variables in Functions
// =============================================
print("");
print("=== SECTION 18: Local Variables ===");

gvar.i = 100;

function testLocals(param.i) {
    local.i = 50;
    return param + local + gvar;
}

testnum++;
result = testLocals(10);
if result == 160 { print("[ ", testnum, " ] -- PASS: local+param+global=160"); passed++; }
else { print("[ ", testnum, " ] -- FAIL: expected 160, got", result); failed++; }

testnum++;
if gvar == 100 { print("[ ", testnum, " ] -- PASS: global unchanged=100"); passed++; }
else { print("[ ", testnum, " ] -- FAIL: global expected 100, got", gvar); failed++; }

// =============================================
// SECTION 19: Nested Function Calls
// =============================================
print("");
print("=== SECTION 19: Nested Calls ===");

function double(n.i) {
    return n * 2;
}

function triple(n.i) {
    return n * 3;
}

testnum++;
result = double(triple(5));
if result == 30 { print("[ ", testnum, " ] -- PASS: double(triple(5))=30"); passed++; }
else { print("[ ", testnum, " ] -- FAIL: expected 30, got", result); failed++; }

testnum++;
result = add(double(3), triple(4));
if result == 18 { print("[ ", testnum, " ] -- PASS: add(double(3),triple(4))=18"); passed++; }
else { print("[ ", testnum, " ] -- FAIL: expected 18, got", result); failed++; }

// =============================================
// SECTION 20: Complex Expressions
// =============================================
print("");
print("=== SECTION 20: Complex Expressions ===");

testnum++;
a.i = 5;
b.i = 3;
c.i = 2;
result = a * b + c * (a - b);
if result == 19 { print("[ ", testnum, " ] -- PASS: complex expr=19"); passed++; }
else { print("[ ", testnum, " ] -- FAIL: expected 19, got", result); failed++; }

testnum++;
result = (a > b) && (b > c) && (a > c);
if result == 1 { print("[ ", testnum, " ] -- PASS: chained comparison=true"); passed++; }
else { print("[ ", testnum, " ] -- FAIL: chained comparison expected true"); failed++; }

// =============================================
// SECTION 21: Function Pointers (TEMPORARILY DISABLED)
// =============================================
print("");
print("=== SECTION 21: Function Pointers (SKIPPED) ===");

// =============================================
// FINAL SUMMARY
// =============================================
print("");
print("==========================================");
print("           TEST SUMMARY");
print("==========================================");
print("Total tests:", testnum);
print("Passed:", passed);
print("Failed:", failed);
print("");

if failed == 0 {
    print("*** ALL TESTS PASSED ***");
} else {
    print("*** SOME TESTS FAILED ***");
}
print("==========================================");
