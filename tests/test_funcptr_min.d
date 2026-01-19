/* Minimal function pointer test */
#pragma console on
#pragma ListASM on
#pragma consolesize "680x740"
#pragma consoleposition "30,50"
#pragma asmdecimal on

func add(a, b) {
    return a + b;
}

func multiply(a, b) {
    return a * b;
}

print("Testing function pointers:");

// Direct call first to verify functions work
print("Direct add(10, 5) = ", add(10, 5));
print("Direct multiply(10, 5) = ", multiply(10, 5));

// Function pointer calls
funcptr = &add;
result = funcptr(10, 5);
print("Via pointer add(10, 5) = ", result);

funcptr = &multiply;
result = funcptr(10, 5);
print("Via pointer multiply(10, 5) = ", result);
