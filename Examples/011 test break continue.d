// Test file for break and continue statements
// V1.024.5

#pragma console on
#pragma consolesize "680x740"
#pragma decimals 3
#pragma ListASM on
#pragma FastPrint on
#pragma RunThreaded on
#pragma ftoi "truncate"
#pragma version on
#pragma modulename on
#pragma PasteToClipboard on
#pragma floattolerance 0.001
#pragma GlobalStack 1024
#pragma FunctionStack 32
#pragma EvalStack 256
#pragma LocalStack 64
#pragma CreateLog off
#pragma DefaultFPS 32
#pragma ThreadKillWait 1800
#pragma DumpASM on
#pragma consoleposition "30,50"
#pragma asmdecimal on

print("=== Break/Continue Tests ===\n");

// While with break
print("Test 1: While loop with break at 5");
i.i = 0;
while (i < 10) {
    if (i == 5) break;
    printf("%d ", i);
    i++;
}
print("");

// While with continue
print("Test 2: While loop with continue (skip even numbers)");
i = 0;
while (i < 10) {
    i++;
    if (i % 2 == 0) continue;
    printf("%d ", i);
}
print("");

// Nested loops with break using inline for declarations
print("Test 3: Nested loops - inner break");
for (i.i = 0; i < 3; i++) {
    printf("Outer: %d Inner: ", i);
    for (j.i = 0; j < 10; j++) {
        if (j == 3) break;
        printf("%d ", j);
    }
    print("");
}

// While with multiple continues
print("Test 4: While with multiple continues");
i = 0;
count.i = 0;
while (i < 20) {
    i++;
    if (i % 2 == 0) continue;
    if (i % 5 == 0) continue;
    printf("%d ", i);
    count++;
}
printf("\nCount: %d\n", count);

print("=== All break/continue tests complete ===");
