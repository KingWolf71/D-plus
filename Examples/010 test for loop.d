// Test file for C-style for loop
// V1.024.5

#pragma console on
#pragma consolesize "680x740"
#pragma consoleposition "30,50"
#pragma asmdecimal on

print("=== FOR Loop Tests ===\n");

// Basic for loop with inline variable declaration
print("Test 1: Basic for loop (0 to 4)");
for (i.i = 0; i < 5; i++) {
    printf("%d ", i);
}
print("");

// For loop with break
print("Test 2: For loop with break at 3");
for (i.i = 0; i < 10; i++) {
    if (i == 3) break;
    printf("%d ", i);
}
print("");

// For loop with continue
print("Test 3: For loop with continue (skip 3)");
for (i.i = 0; i < 5; i++) {
    if (i == 3) continue;
    printf("%d ", i);
}
print("");

// Nested for loops
print("Test 4: Nested for loops (3x3)");
for (i.i = 0; i < 3; i++) {
    for (j.i = 0; j < 3; j++) {
        printf("%d,%d ", i, j);
    }
    print("");
}

// Sum calculation
print("Test 5: Sum of 1 to 10");
sum.i = 0;
for (i.i = 1; i <= 10; i++) {
    sum += i;
}
printf("Sum = %d\n", sum);

print("=== All FOR tests complete ===");
