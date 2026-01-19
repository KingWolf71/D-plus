// Test pointer arithmetic in functions
#pragma console on
#pragma ListASM on
#pragma consolesize "680x740"
#pragma consoleposition "30,50"
#pragma asmdecimal on

array data.i[5];
data[0] = 10;
data[1] = 20;
data[2] = 30;
data[3] = 40;
data[4] = 50;

// Test pointer arithmetic in global scope
ptr = &data[0];
print("Global scope test:");
print("ptr\\i = ", ptr\i);
ptr = ptr + 1;
print("After ptr = ptr + 1:");
print("ptr\\i = ", ptr\i);

// Test pointer arithmetic in function
func testPtrArith(p) {
    print("Function scope test:");
    print("p\\i = ", p\i);
    p = p + 1;
    print("After p = p + 1:");
    print("p\\i = ", p\i);
    return p\i;
}

result = testPtrArith(&data[0]);
print("Returned: ", result);
