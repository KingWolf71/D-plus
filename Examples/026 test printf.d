// Test printf function
// V1.035.13

#pragma console on
#pragma consolesize "680x740"
#pragma consoleposition "30,50"
#pragma asmdecimal on

// Test 1: Simple string
printf("Hello World!\n");

// Test 2: Integer format
x.i = 42;
printf("Value: %d\n", x);

// Test 3: Float format
pi.f = 3.14159;
printf("Pi: %f\n", pi);

// Test 4: Float with precision
printf("Pi (2 decimals): %.2f\n", pi);
printf("Pi (4 decimals): %.4f\n", pi);

// Test 5: String format
name.s = "World";
printf("Hello, %s!\n", name);

// Test 6: Multiple arguments
age.i = 25;
score.f = 98.5;
printf("Name: %s, Age: %d, Score: %.1f\n", name, age, score);

// Test 7: Escape sequences
printf("Tab:\ttest\n");
printf("Newline test\nSecond line\n");

// Test 8: Literal percent
printf("Percent sign: 100%%\n");

// Test 9: Mixed with expressions
a.i = 10;
b.i = 20;
printf("Sum of %d and %d is %d\n", a, b, a + b);

print("All printf tests passed!");
