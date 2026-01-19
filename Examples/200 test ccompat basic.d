// Test C Compatibility Layer - V1.037
// Tests C-style syntax transformation

#pragma ccompat on
#pragma console on
#pragma consolesize "680x740"
#pragma consoleposition "30,50"
#pragma asmdecimal on

// Test 1: C-style variable declarations
int a = 5;
int b = 10;
float c = 3.14;
string msg = "Hello World";

printf("=== C Compatibility Tests ===\n");
printf("int a = 5: %d\n", a);
printf("int b = 10: %d\n", b);
printf("float c = 3.14: %f\n", c);
printf("string msg = \"Hello World\": %s\n", msg);

// Test 2: C-style function definition
int square(int x) {
    return x * x;
}

// Test 3: C-style function with multiple params
int add(int x, int y) {
    return x + y;
}

// Test function calls
int sq = square(4);
printf("square(4) = %d\n", sq);

int sum = add(3, 7);
printf("add(3, 7) = %d\n", sum);

// Test strlen -> len
int length = len(msg);
printf("len(msg) = %d\n", length);

printf("\n=== All C Compatibility Tests Passed ===\n");
