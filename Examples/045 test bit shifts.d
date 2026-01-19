// Test Bit Shift Operators (V1.034.4)
// Tests << (left shift) and >> (right shift) operators

#pragma appname "Bit-Shift-Test"
#pragma decimals 3
#pragma console on
#pragma consolesize "680x740"
#pragma consoleposition "30,50"
#pragma FastPrint on
#pragma asmdecimal on

print("=== BIT SHIFT OPERATORS TEST (V1.034.4) ===");
print("");

// ============================================
// TEST 1: Basic Left Shift
// ============================================
print("TEST 1: Basic Left Shift (<<)");
print("-----------------------------");

a.i = 1;
b.i = a << 1;
print("  1 << 1 = ", b);
assertEqual(b, 2);

b = a << 2;
print("  1 << 2 = ", b);
assertEqual(b, 4);

b = a << 3;
print("  1 << 3 = ", b);
assertEqual(b, 8);

b = a << 4;
print("  1 << 4 = ", b);
assertEqual(b, 16);

b = 5 << 2;
print("  5 << 2 = ", b);
assertEqual(b, 20);

print("  PASS: Basic left shift works!");
print("");

// ============================================
// TEST 2: Basic Right Shift
// ============================================
print("TEST 2: Basic Right Shift (>>)");
print("------------------------------");

a = 16;
b = a >> 1;
print("  16 >> 1 = ", b);
assertEqual(b, 8);

b = a >> 2;
print("  16 >> 2 = ", b);
assertEqual(b, 4);

b = a >> 3;
print("  16 >> 3 = ", b);
assertEqual(b, 2);

b = a >> 4;
print("  16 >> 4 = ", b);
assertEqual(b, 1);

b = 20 >> 2;
print("  20 >> 2 = ", b);
assertEqual(b, 5);

print("  PASS: Basic right shift works!");
print("");

// ============================================
// TEST 3: Shift with Variables
// ============================================
print("TEST 3: Shift with Variables");
print("----------------------------");

x.i = 8;
shift.i = 2;

y.i = x << shift;
print("  8 << 2 = ", y);
assertEqual(y, 32);

y = x >> shift;
print("  8 >> 2 = ", y);
assertEqual(y, 2);

print("  PASS: Shift with variables works!");
print("");

// ============================================
// TEST 4: Shift Zero
// ============================================
print("TEST 4: Shift by Zero");
print("---------------------");

a = 42;
b = a << 0;
print("  42 << 0 = ", b);
assertEqual(b, 42);

b = a >> 0;
print("  42 >> 0 = ", b);
assertEqual(b, 42);

print("  PASS: Shift by zero works!");
print("");

// ============================================
// TEST 5: Chained Shifts
// ============================================
print("TEST 5: Chained Shifts");
print("----------------------");

a = 1;
b = a << 4 >> 2;
print("  1 << 4 >> 2 = ", b);
assertEqual(b, 4);

b = 8 >> 1 << 3;
print("  8 >> 1 << 3 = ", b);
assertEqual(b, 32);

print("  PASS: Chained shifts work!");
print("");

// ============================================
// TEST 6: Precedence with Arithmetic
// ============================================
print("TEST 6: Precedence with Arithmetic");
print("----------------------------------");

// In C: shift has lower precedence than add/subtract
// 1 + 2 << 2 should be (1 + 2) << 2 = 12 (since + binds tighter)
// Actually in C: shift has higher precedence than add
// So 1 + (2 << 2) = 1 + 8 = 9

a = 1 + 2 << 2;
print("  1 + 2 << 2 = ", a);
// C precedence: shift (11) is lower than add (12)
// So this is (1 + 2) << 2 = 3 << 2 = 12
assertEqual(a, 12);

a = 2 << 2 + 1;
print("  2 << 2 + 1 = ", a);
// C precedence: (2 << 2) + 1 = 8 + 1 = 9
// Wait, shift is lower than add, so: 2 << (2 + 1) = 2 << 3 = 16
assertEqual(a, 16);

a = 10 - 2 >> 1;
print("  10 - 2 >> 1 = ", a);
// shift is lower than subtract: (10 - 2) >> 1 = 8 >> 1 = 4
assertEqual(a, 4);

print("  PASS: Precedence with arithmetic works!");
print("");

// ============================================
// TEST 7: Precedence with Comparison
// ============================================
print("TEST 7: Precedence with Comparison");
print("----------------------------------");

// Shift has higher precedence than comparison
// 1 << 2 < 10 should be (1 << 2) < 10 = 4 < 10 = true
a = 1 << 2 < 10;
print("  1 << 2 < 10 = ", a);
assertEqual(a, 1);

a = 1 << 4 > 10;
print("  1 << 4 > 10 = ", a);
assertEqual(a, 1);

a = 16 >> 2 == 4;
print("  16 >> 2 == 4 = ", a);
assertEqual(a, 1);

print("  PASS: Precedence with comparison works!");
print("");

// ============================================
// TEST 8: Shift in Expressions
// ============================================
print("TEST 8: Shift in Expressions");
print("----------------------------");

x = 3;
y = (x << 2) + (x >> 1);
print("  (3 << 2) + (3 >> 1) = ", y);
assertEqual(y, 13);  // 12 + 1 = 13

y = (1 << x) * 2;
print("  (1 << 3) * 2 = ", y);
assertEqual(y, 16);  // 8 * 2 = 16

print("  PASS: Shift in expressions works!");
print("");

// ============================================
// TEST 9: Shift in Function
// ============================================
print("TEST 9: Shift in Function");
print("-------------------------");

func shiftTest(val.i, bits.i) {
    left.i = val << bits;
    right.i = val >> bits;
    return left + right;
}

result.i = shiftTest(8, 2);
print("  shiftTest(8, 2) = ", result);
assertEqual(result, 34);  // 32 + 2 = 34

result = shiftTest(4, 1);
print("  shiftTest(4, 1) = ", result);
assertEqual(result, 10);  // 8 + 2 = 10

print("  PASS: Shift in function works!");
print("");

// ============================================
// TEST 10: Bit Manipulation Patterns
// ============================================
print("TEST 10: Bit Manipulation Patterns");
print("----------------------------------");

// Setting a bit: value | (1 << bit)
flags.i = 0;
flags = flags | (1 << 0);  // Set bit 0
print("  Set bit 0: ", flags);
assertEqual(flags, 1);

flags = flags | (1 << 2);  // Set bit 2
print("  Set bit 2: ", flags);
assertEqual(flags, 5);

flags = flags | (1 << 4);  // Set bit 4
print("  Set bit 4: ", flags);
assertEqual(flags, 21);

// Checking a bit: (value >> bit) & 1
bit0.i = (flags >> 0) & 1;
print("  Bit 0 is: ", bit0);
assertEqual(bit0, 1);

bit1.i = (flags >> 1) & 1;
print("  Bit 1 is: ", bit1);
assertEqual(bit1, 0);

bit2.i = (flags >> 2) & 1;
print("  Bit 2 is: ", bit2);
assertEqual(bit2, 1);

print("  PASS: Bit manipulation patterns work!");
print("");

// ============================================
// TEST 11: Powers of Two
// ============================================
print("TEST 11: Powers of Two");
print("----------------------");

i.i = 0;
while (i < 8) {
    pow2.i = 1 << i;
    print("  2^", i, " = ", pow2);
    i = i + 1;
}

assertEqual(1 << 0, 1);
assertEqual(1 << 1, 2);
assertEqual(1 << 2, 4);
assertEqual(1 << 3, 8);
assertEqual(1 << 4, 16);
assertEqual(1 << 5, 32);
assertEqual(1 << 6, 64);
assertEqual(1 << 7, 128);

print("  PASS: Powers of two work!");
print("");

print("=== ALL BIT SHIFT TESTS PASSED ===");
