// D+AI Comprehensive Feature Test Suite - V1.037
// Tests all major language features with pass/fail tracking

#pragma console on
#pragma appname "D+AI Feature Test"
#pragma consolesize "680x740"
#pragma consoleposition "30,50"
#pragma asmdecimal on

// ============================================================================
// Test Infrastructure
// ============================================================================
gPassed.i = 0;
gFailed.i = 0;
gSection.s = "";

func startSection(name.s) {
   gSection = name;
   printf("\n=== %s ===\n", name);
}

func assertInt(actual.i, expected.i, testName.s) {
   if (actual == expected) {
      printf("  PASS: %s\n", testName);
      gPassed = gPassed + 1;
   } else {
      printf("  FAIL: %s (expected %d, got %d)\n", testName, expected, actual);
      gFailed = gFailed + 1;
   }
}

func assertFloat(actual.f, expected.f, testName.s) {
   diff.f = actual - expected;
   if (diff < 0.0) { diff = 0.0 - diff; }
   if (diff < 0.001) {
      printf("  PASS: %s\n", testName);
      gPassed = gPassed + 1;
   } else {
      printf("  FAIL: %s (expected %f, got %f)\n", testName, expected, actual);
      gFailed = gFailed + 1;
   }
}

func assertStr(actual.s, expected.s, testName.s) {
   if (actual == expected) {
      printf("  PASS: %s\n", testName);
      gPassed = gPassed + 1;
   } else {
      printf("  FAIL: %s\n", testName);
      printf("        expected: %s\n", expected);
      printf("        got: %s\n", actual);
      gFailed = gFailed + 1;
   }
}

func assertTrue(condition.i, testName.s) {
   if (condition) {
      printf("  PASS: %s\n", testName);
      gPassed = gPassed + 1;
   } else {
      printf("  FAIL: %s\n", testName);
      gFailed = gFailed + 1;
   }
}

printf("========================================\n");
printf("   D+AI COMPREHENSIVE FEATURE TEST\n");
printf("   Version 1.037\n");
printf("========================================\n");

// ============================================================================
// 1. Basic Arithmetic
// ============================================================================
startSection("1. Basic Arithmetic");

a.i = 10;
b.i = 3;
assertInt(a + b, 13, "Addition: 10 + 3 = 13");
assertInt(a - b, 7, "Subtraction: 10 - 3 = 7");
assertInt(a * b, 30, "Multiplication: 10 * 3 = 30");
assertInt(a / b, 3, "Integer division: 10 / 3 = 3");
assertInt(a % b, 1, "Modulo: 10 % 3 = 1");
assertInt(-a, -10, "Negation: -10");

// ============================================================================
// 2. Float Arithmetic
// ============================================================================
startSection("2. Float Arithmetic");

x.f = 10.0;
y.f = 3.0;
assertFloat(x + y, 13.0, "Float add: 10.0 + 3.0 = 13.0");
assertFloat(x - y, 7.0, "Float sub: 10.0 - 3.0 = 7.0");
assertFloat(x * y, 30.0, "Float mul: 10.0 * 3.0 = 30.0");
assertFloat(x / y, 3.333, "Float div: 10.0 / 3.0 = 3.333");

// ============================================================================
// 3. Comparison Operators
// ============================================================================
startSection("3. Comparison Operators");

assertTrue(5 == 5, "Equal: 5 == 5");
assertTrue(5 != 3, "Not equal: 5 != 3");
assertTrue(5 > 3, "Greater: 5 > 3");
assertTrue(3 < 5, "Less: 3 < 5");
assertTrue(5 >= 5, "Greater or equal: 5 >= 5");
assertTrue(3 <= 5, "Less or equal: 3 <= 5");

// ============================================================================
// 4. Logical Operators
// ============================================================================
startSection("4. Logical Operators");

assertTrue(1 && 1, "AND: 1 && 1");
assertTrue(1 || 0, "OR: 1 || 0");
assertTrue(!0, "NOT: !0");
assertTrue(!(1 && 0), "NOT AND: !(1 && 0)");

// ============================================================================
// 5. Bitwise Operators
// ============================================================================
startSection("5. Bitwise Operators");

assertInt(5 & 3, 1, "Bitwise AND: 5 & 3 = 1");
assertInt(5 | 3, 7, "Bitwise OR: 5 | 3 = 7");
assertInt(5 ^ 3, 6, "Bitwise XOR: 5 ^ 3 = 6");
assertInt(1 << 3, 8, "Left shift: 1 << 3 = 8");
assertInt(8 >> 2, 2, "Right shift: 8 >> 2 = 2");

// ============================================================================
// 6. Compound Assignment
// ============================================================================
startSection("6. Compound Assignment");

c.i = 10;
c += 5;
assertInt(c, 15, "Add assign: 10 += 5 = 15");

c = 10;
c -= 3;
assertInt(c, 7, "Sub assign: 10 -= 3 = 7");

c = 10;
c *= 2;
assertInt(c, 20, "Mul assign: 10 *= 2 = 20");

c = 10;
c /= 2;
assertInt(c, 5, "Div assign: 10 /= 2 = 5");

// ============================================================================
// 7. Increment/Decrement
// ============================================================================
startSection("7. Increment/Decrement");

d.i = 5;
d++;
assertInt(d, 6, "Post-increment: 5++ = 6");

d = 5;
d--;
assertInt(d, 4, "Post-decrement: 5-- = 4");

// ============================================================================
// 8. If-Else Statements
// ============================================================================
startSection("8. If-Else Statements");

result.i = 0;
if (1) {
   result = 1;
}
assertInt(result, 1, "Simple if true");

result = 0;
if (0) {
   result = 1;
} else {
   result = 2;
}
assertInt(result, 2, "If-else takes else branch");

result = 0;
val.i = 15;
if (val < 10) {
   result = 1;
} else if (val < 20) {
   result = 2;
} else {
   result = 3;
}
assertInt(result, 2, "Else-if chain");

// ============================================================================
// 9. While Loop
// ============================================================================
startSection("9. While Loop");

sum.i = 0;
i.i = 1;
while (i <= 5) {
   sum = sum + i;
   i++;
}
assertInt(sum, 15, "While loop sum 1-5 = 15");

// ============================================================================
// 10. For Loop
// ============================================================================
startSection("10. For Loop");

sum = 0;
for (j.i = 1; j <= 5; j++) {
   sum = sum + j;
}
assertInt(sum, 15, "For loop sum 1-5 = 15");

// Nested for
sum = 0;
for (i = 0; i < 3; i++) {
   for (j = 0; j < 3; j++) {
      sum++;
   }
}
assertInt(sum, 9, "Nested for 3x3 = 9");

// ============================================================================
// 11. Break and Continue
// ============================================================================
startSection("11. Break and Continue");

sum = 0;
for (i = 1; i <= 10; i++) {
   if (i == 5) { break; }
   sum = sum + i;
}
assertInt(sum, 10, "Break at 5: sum 1-4 = 10");

sum = 0;
for (i = 1; i <= 5; i++) {
   if (i == 3) { continue; }
   sum = sum + i;
}
assertInt(sum, 12, "Continue at 3: 1+2+4+5 = 12");

// ============================================================================
// 12. Functions
// ============================================================================
startSection("12. Functions");

func addTwo(a.i, b.i) {
   return a + b;
}
assertInt(addTwo(3, 4), 7, "Function add: 3 + 4 = 7");

func factorial(n.i) {
   if (n <= 1) { return 1; }
   return n * factorial(n - 1);
}
assertInt(factorial(5), 120, "Recursive factorial(5) = 120");

func returnFloat.f(x.f) {
   return x * 2.0;
}
assertFloat(returnFloat(3.5), 7.0, "Float return function");

func returnString.s(name.s) {
   return "Hello, " + name + "!";
}
assertStr(returnString("World"), "Hello, World!", "String return function");

// ============================================================================
// 13. Default Parameters
// ============================================================================
startSection("13. Default Parameters");

func greet.s(name.s, greeting.s = "Hello") {
   return greeting + ", " + name;
}
assertStr(greet("Bob"), "Hello, Bob", "Default param used");
assertStr(greet("Bob", "Hi"), "Hi, Bob", "Default param overridden");

func addThree(a.i, b.i = 10, c.i = 5) {
   return a + b + c;
}
assertInt(addThree(1), 16, "Two defaults: 1+10+5=16");
assertInt(addThree(1, 20), 26, "One default: 1+20+5=26");
assertInt(addThree(1, 20, 30), 51, "No defaults: 1+20+30=51");

// ============================================================================
// 14. Arrays
// ============================================================================
startSection("14. Arrays");

array nums.i[5];
nums[0] = 10;
nums[1] = 20;
nums[2] = 30;
assertInt(nums[0], 10, "Array store/fetch [0]");
assertInt(nums[2], 30, "Array store/fetch [2]");

// Array with variable index
idx.i = 1;
assertInt(nums[idx], 20, "Array with variable index");

// ============================================================================
// 15. Multi-Dimensional Arrays
// ============================================================================
startSection("15. Multi-Dimensional Arrays");

array grid.i[3][4];
grid[0][0] = 1;
grid[1][2] = 42;
grid[2][3] = 99;

assertInt(grid[0][0], 1, "2D array [0][0]");
assertInt(grid[1][2], 42, "2D array [1][2]");
assertInt(grid[2][3], 99, "2D array [2][3]");

row.i = 1;
col.i = 2;
assertInt(grid[row][col], 42, "2D array variable indices");

// ============================================================================
// 16. Strings
// ============================================================================
startSection("16. Strings");

s1.s = "Hello";
s2.s = "World";
s3.s = s1 + " " + s2;
assertStr(s3, "Hello World", "String concatenation");

assertInt(len(s1), 5, "String length: len(\"Hello\") = 5");

// ============================================================================
// 17. Type Casting
// ============================================================================
startSection("17. Type Casting");

fv.f = 3.7;
iv.i = (int)fv;
assertInt(iv, 4, "Float to int cast (rounds)");

iv = 5;
fv = (float)iv;
assertFloat(fv, 5.0, "Int to float cast");

sv.s = str(42);
assertStr(sv, "42", "Int to string: str(42)");

// ============================================================================
// 18. Structures
// ============================================================================
startSection("18. Structures");

struct Point {
   x.i;
   y.i;
}

p1.Point = { };  // Note: empty braces required for field assignment to work
p1\x = 10;
p1\y = 20;
assertInt(p1\x, 10, "Struct field x");
assertInt(p1\y, 20, "Struct field y");

// ============================================================================
// 19. Pointers
// ============================================================================
startSection("19. Pointers");

pval.i = 42;
ptr.i = &pval;
assertInt(*ptr, 42, "Pointer dereference");

*ptr = 100;
assertInt(pval, 100, "Pointer write-through");

// ============================================================================
// 20. Ternary Operator
// ============================================================================
startSection("20. Ternary Operator");

t1.i = (5 > 3) ? 1 : 0;
assertInt(t1, 1, "Ternary true branch");

t2.i = (5 < 3) ? 1 : 0;
assertInt(t2, 0, "Ternary false branch");

// ============================================================================
// 21. Switch Statement
// ============================================================================
startSection("21. Switch Statement");

choice.i = 2;
result = 0;
switch (choice) {
   case 1: result = 10; break;
   case 2: result = 20; break;
   case 3: result = 30; break;
   default: result = -1;
}
assertInt(result, 20, "Switch case 2");

choice = 99;
result = 0;
switch (choice) {
   case 1: result = 10; break;
   default: result = -1;
}
assertInt(result, -1, "Switch default");

// ============================================================================
// 22. Macros
// ============================================================================
startSection("22. Macros");

#define MAX_VAL 100
#define SQUARE(x) ((x) * (x))

assertInt(MAX_VAL, 100, "Constant macro");
assertInt(SQUARE(5), 25, "Function-like macro");

// ============================================================================
// 23. Math Functions
// ============================================================================
startSection("23. Math Functions");

assertInt(abs(-5), 5, "abs(-5) = 5");
assertInt(min(3, 7), 3, "min(3, 7) = 3");
assertInt(max(3, 7), 7, "max(3, 7) = 7");
assertFloat(sqrt(16.0), 4.0, "sqrt(16) = 4");

// ============================================================================
// Summary
// ============================================================================
printf("\n========================================\n");
printf("   TEST SUMMARY\n");
printf("========================================\n");
printf("   Passed: %d\n", gPassed);
printf("   Failed: %d\n", gFailed);
printf("   Total:  %d\n", gPassed + gFailed);
printf("========================================\n");

if (gFailed == 0) {
   printf("   *** ALL TESTS PASSED! ***\n");
} else {
   printf("   *** SOME TESTS FAILED ***\n");
}
printf("========================================\n");
