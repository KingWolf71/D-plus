#pragma console on
#pragma ListASM on
#pragma consolesize "680x740"
#pragma consoleposition "30,50"
#pragma asmdecimal on

arr.i[5];
arr[0] = 50;
arr[1] = 20;
arr[2] = 80;
arr[3] = 10;
arr[4] = 40;

function testStore() {
    ptr.i* = &arr[0];
    min.i = ptr\i;
    print("min = ", min);
    return min;
}

result.i = testStore();
print("Result = ", result);
