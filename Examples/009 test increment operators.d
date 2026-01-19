/* =============================================================================
   D+AI Increment/Decrement & Compound Assignment Test Suite
   Tests all C-style increment/decrement and compound assignment operators
   ============================================================================= */

#pragma appname "D+AI-Increment-Operators-Test"
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

print("D+AI INCREMENT/DECREMENT & COMPOUND ASSIGNMENT TEST SUITE");
print("=========================================================");

/* =============================================================================
   Built-in assertion functions:
   - assertEqual(expected, actual) - for integers
   - assertFloatEqual(expected, actual) - for floats (uses pragma floattolerance)
   - assertStringEqual(expected, actual) - for strings
   ============================================================================= */

/* =============================================================================
   SECTION 1: PRE-INCREMENT (++var)
   Returns NEW value after incrementing
   ============================================================================= */
print("SECTION 1: Pre-Increment Tests");
print("-------------------------------");

print("Test: Pre-increment returns new value");
i = 5;
j = ++i;
assertEqual(6, i);
assertEqual(6, j);

print("Test: Pre-increment in expression");
i = 10;
k = ++i + 5;
assertEqual(11, i);
assertEqual(16, k);

print("Test: Multiple pre-increments");
a = 1;
b = ++a + ++a;
assertEqual(3, a);
assertEqual(5, b);

/* =============================================================================
   SECTION 2: PRE-DECREMENT (--var)
   Returns NEW value after decrementing
   ============================================================================= */
print("SECTION 2: Pre-Decrement Tests");
print("-------------------------------");

print("Test: Pre-decrement returns new value");
i = 5;
j = --i;
assertEqual(4, i);
assertEqual(4, j);

print("Test: Pre-decrement in expression");
i = 10;
k = --i + 5;
assertEqual(9, i);
assertEqual(14, k);

print("Test: Multiple pre-decrements");
a = 10;
b = --a + --a;
assertEqual(8, a);
assertEqual(17, b);

/* =============================================================================
   SECTION 3: POST-INCREMENT (var++)
   Returns OLD value, then increments
   ============================================================================= */
print("SECTION 3: Post-Increment Tests");
print("--------------------------------");

print("Test: Post-increment returns old value");
i = 5;
j = i++;
assertEqual(6, i);
assertEqual(5, j);

print("Test: Post-increment in expression");
i = 10;
k = i++ + 5;
assertEqual(11, i);
assertEqual(15, k);

print("Test: Multiple post-increments");
a = 1;
b = a++ + a++;
assertEqual(3, a);
assertEqual(3, b);

/* =============================================================================
   SECTION 4: POST-DECREMENT (var--)
   Returns OLD value, then decrements
   ============================================================================= */
print("SECTION 4: Post-Decrement Tests");
print("--------------------------------");

print("Test: Post-decrement returns old value");
i = 5;
j = i--;
assertEqual(4, i);
assertEqual(5, j);

print("Test: Post-decrement in expression");
i = 10;
k = i-- + 5;
assertEqual(9, i);
assertEqual(15, k);

print("Test: Multiple post-decrements");
a = 10;
b = a-- + a--;
assertEqual(8, a);
assertEqual(19, b);

/* =============================================================================
   SECTION 5: MIXED PRE/POST INCREMENT/DECREMENT
   ============================================================================= */
print("SECTION 5: Mixed Pre/Post Tests");
print("--------------------------------");

print("Test: Mix pre-inc and post-inc");
i = 5;
j = 10;
k = ++i + j++;
assertEqual(6, i);
assertEqual(11, j);
assertEqual(16, k);

print("Test: Mix post-inc and pre-inc");
i = 5;
j = 10;
k = i++ + ++j;
assertEqual(6, i);
assertEqual(11, j);
assertEqual(16, k);

print("Test: Mix pre-dec and post-dec");
i = 5;
j = 10;
k = --i + j--;
assertEqual(4, i);
assertEqual(9, j);
assertEqual(14, k);

/* =============================================================================
   SECTION 6: COMPOUND ASSIGNMENT - INTEGERS (+=, -=, *=, /=, %=)
   ============================================================================= */
print("SECTION 6: Compound Assignment (Integers)");
print("------------------------------------------");

print("Test: Integer += operator");
i = 10;
i += 5;
assertEqual(15, i);

print("Test: Integer -= operator");
i = 20;
i -= 7;
assertEqual(13, i);

print("Test: Integer *= operator");
i = 6;
i *= 4;
assertEqual(24, i);

print("Test: Integer /= operator");
i = 50;
i /= 5;
assertEqual(10, i);

print("Test: Integer %= operator");
i = 17;
i %= 5;
assertEqual(2, i);

print("Test: Chained compound assignments");
i = 5;
i += 3;
i *= 2;
i -= 4;
i /= 2;
assertEqual(6, i);

/* =============================================================================
   SECTION 7: COMPOUND ASSIGNMENT - FLOATS (+=, -=, *=, /=)
   ============================================================================= */
print("SECTION 7: Compound Assignment (Floats)");
print("----------------------------------------");

print("Test: Float += operator");
x.f = 10.5;
x += 5.25;
assertFloatEqual(15.75, x);

print("Test: Float -= operator");
x = 20.8;
x -= 7.3;
assertFloatEqual(13.5, x);

print("Test: Float *= operator");
x = 6.5;
x *= 4.0;
assertFloatEqual(26.0, x);

print("Test: Float /= operator");
x = 50.0;
x /= 5.0;
assertFloatEqual(10.0, x);

print("Test: Chained float compound assignments");
x = 5.0;
x += 3.5;
x *= 2.0;
x -= 4.0;
x /= 2.0;
assertFloatEqual(6.5, x);

/* =============================================================================
   SECTION 8: COMPOUND ASSIGNMENT - ARRAYS
   ============================================================================= */
print("SECTION 8: Compound Assignment with Arrays");
print("-------------------------------------------");

array nums.i[10];
array values.f[10];

print("Test: Array element += (integer)");
nums[0] = 100;
nums[0] += 50;
assertEqual(150, nums[0]);

print("Test: Array element -= (integer)");
nums[1] = 80;
nums[1] -= 30;
assertEqual(50, nums[1]);

print("Test: Array element *= (integer)");
nums[2] = 5;
nums[2] *= 7;
assertEqual(35, nums[2]);

print("Test: Array element /= (integer)");
nums[3] = 100;
nums[3] /= 4;
assertEqual(25, nums[3]);

print("Test: Array element %= (integer)");
nums[4] = 23;
nums[4] %= 6;
assertEqual(5, nums[4]);

print("Test: Array element += (float)");
values[0] = 100.5;
values[0] += 25.25;
assertFloatEqual(125.75, values[0]);

print("Test: Array element *= (float)");
values[1] = 50.0;
values[1] *= 2.5;
assertFloatEqual(125.0, values[1]);

print("Test: Array with variable index");
idx = 5;
nums[idx] = 42;
nums[idx] += 8;
assertEqual(50, nums[idx]);

/* =============================================================================
   SECTION 9: INCREMENT/DECREMENT IN LOOPS
   ============================================================================= */
print("SECTION 9: Increment/Decrement in Loops");
print("----------------------------------------");


print("Test: Post-increment in while loop");
i = 0;
sum = 0;
while i < 5 {
    sum += i;
    i++;
}
assertEqual(5, i);
assertEqual(10, sum);

print("Test: Post-decrement in while loop");
i = 5;
sum = 0;
while i > 0 {
    sum += i;
    i--;
}
assertEqual(0, i);
assertEqual(15, sum);

print("Test: Pre-increment in while loop");
i = 0;
sum = 0;
while i < 5 {
    sum += ++i;
}
assertEqual(5, i);
assertEqual(15, sum);

/* =============================================================================
   SECTION 10: COMPLEX EXPRESSIONS
   ============================================================================= */
print("SECTION 10: Complex Expressions");
print("--------------------------------");

print("Test: Compound assignment with expression");
i = 10;
i += 5 * 2;
assertEqual(20, i);

print("Test: Compound assignment with multiple operations");
i = 10;
j = 5;
i += j * 2 + 3;
assertEqual(23, i);

print("Test: Inc/dec with compound assignment");
i = 10;
i++;
i += 5;
i--;
assertEqual(15, i);

print("Test: Multiple variables with inc/dec");
a = 5;
b = 10;
c = 15;
result = a++ + ++b + c--;
assertEqual(6, a);
assertEqual(11, b);
assertEqual(14, c);
assertEqual(31, result);

/* =============================================================================
   ALL TESTS COMPLETE
   ============================================================================= */
print("");
print("===========================================");
print("ALL TESTS PASSED SUCCESSFULLY!");
print("===========================================");
