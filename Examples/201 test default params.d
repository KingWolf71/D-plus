// Test Default Parameter Values - V1.037.1
// Tests functions with default parameter values

#pragma console on
#pragma consolesize "680x740"
#pragma consoleposition "30,50"
#pragma asmdecimal on

// Test counters
passed.i = 0;
failed.i = 0;

// Assert helper
func assert(condition.i, testName.s) {
   if (condition) {
      printf("  PASS: %s\n", testName);
      passed = passed + 1;
   } else {
      printf("  FAIL: %s\n", testName);
      failed = failed + 1;
   }
}

// Test 1: Simple default value - returns greeting + name
func makeGreeting.s(name.s, greeting.s = "Hello") {
   return greeting + ", " + name + "!";
}

// Test 2: Multiple defaults
func add(a.i, b.i = 10, c.i = 5) {
   return a + b + c;
}

// Test 3: Float default
func scale.f(value.f, factor.f = 2.0) {
   return value * factor;
}

// Test 4: Mixed required and optional - returns formatted string
func formatValue.s(prefix.s, value.i, suffix.s = "") {
   return prefix + str(value) + suffix;
}

// Test 5: Single optional param
func increment(x.i, amount.i = 1) {
   return x + amount;
}

// Test 6: All optional params
func multiply(a.i = 2, b.i = 3) {
   return a * b;
}

printf("=== Default Parameter Tests ===\n\n");

// Test 1: String defaults
printf("Test 1: String defaults\n");
s1.s = makeGreeting("World");
assert(s1 == "Hello, World!", "Default greeting");

s2.s = makeGreeting("World", "Hi");
assert(s2 == "Hi, World!", "Custom greeting");

// Test 2: Multiple integer defaults
printf("\nTest 2: Multiple integer defaults\n");
r1.i = add(1);
assert(r1 == 16, "add(1) = 1+10+5 = 16");

r2.i = add(1, 20);
assert(r2 == 26, "add(1,20) = 1+20+5 = 26");

r3.i = add(1, 20, 30);
assert(r3 == 51, "add(1,20,30) = 51");

// Test 3: Float defaults
printf("\nTest 3: Float defaults\n");
f1.f = scale(5.0);
assert(f1 == 10.0, "scale(5.0) = 5*2 = 10");

f2.f = scale(5.0, 3.0);
assert(f2 == 15.0, "scale(5.0,3.0) = 15");

// Test 4: Mixed required and optional
printf("\nTest 4: Mixed required and optional\n");
s3.s = formatValue("Value: ", 42);
assert(s3 == "Value: 42", "No suffix");

s4.s = formatValue("Value: ", 42, " units");
assert(s4 == "Value: 42 units", "With suffix");

// Test 5: Single optional param
printf("\nTest 5: Single optional param\n");
i1.i = increment(10);
assert(i1 == 11, "increment(10) = 11");

i2.i = increment(10, 5);
assert(i2 == 15, "increment(10,5) = 15");

// Test 6: All optional params (call with no args)
printf("\nTest 6: All optional params\n");
m1.i = multiply();
assert(m1 == 6, "multiply() = 2*3 = 6");

m2.i = multiply(4);
assert(m2 == 12, "multiply(4) = 4*3 = 12");

m3.i = multiply(4, 5);
assert(m3 == 20, "multiply(4,5) = 20");

// Summary
printf("\n========================================\n");
if (failed == 0) {
   printf("*** ALL %d TESTS PASSED! ***\n", passed);
} else {
   printf("*** %d PASSED, %d FAILED ***\n", passed, failed);
}
printf("========================================\n");
