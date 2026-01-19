// Minimal pointer arithmetic test
#pragma console on
#pragma ListASM on
#pragma consolesize "680x740"
#pragma consoleposition "30,50"
#pragma asmdecimal on

array data.i[3];
data[0] = 10;
data[1] = 20;
data[2] = 30;

func testPtr(p) {
    // p is a pointer parameter
    val1 = p\i;
    p = p + 1;  // This should use PTRADD, but uses ADD
    val2 = p\i;
    return val1 + val2;
}

result = testPtr(&data[0]);
print("Result: ", result);
print("Expected: 30 (10+20)");
