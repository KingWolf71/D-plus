// Minimal pointer arithmetic test with debug output
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
    print("Before dereference, p=", p);
    val1 = p\i;
    print("val1=", val1);
    p = p + 1;  // This should use PTRADD
    print("After p+1, p=", p);
    val2 = p\i;
    print("val2=", val2);
    return val1 + val2;
}

result = testPtr(&data[0]);
print("Result: ", result);
print("Expected: 30 (10+20)");
