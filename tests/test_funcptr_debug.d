/* Debug function pointer test */
#pragma console on
#pragma ListASM on
#pragma consolesize "680x740"
#pragma consoleposition "30,50"
#pragma asmdecimal on

func add(a, b) {
    return a + b;
}

print("Test:");
funcptr = &add;
print("funcptr assigned");
result = funcptr(10, 5);
print("result = ", result);
