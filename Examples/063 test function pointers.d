/* Function Pointers Test
   Tests function pointers and indirect function calls
*/

#pragma appname "Function-Pointers-Test"
#pragma decimals 3
#pragma console on
#pragma consolesize "680x740"
#pragma consoleposition "30,50"
#pragma ListASM on
#pragma FastPrint on
#pragma RunThreaded on
#pragma ftoi "truncate"
#pragma version on
#pragma modulename on
#pragma PasteToClipboard on
#pragma floattolerance 0.0001
#pragma GlobalStack 1024
#pragma FunctionStack 32
#pragma EvalStack 256
#pragma LocalStack 64
#pragma CreateLog off
#pragma DefaultFPS 32
#pragma ThreadKillWait 1800
#pragma asmdecimal on

// Math operation functions
func add(a, b) {
    return a + b;
}

func subtract(a, b) {
    return a - b;
}

func multiply(a, b) {
    return a * b;
}

func divide(a, b) {
    if b == 0 {
        print("Error: Division by zero");
        return 0;
    }
    return a / b;
}

// Function that takes a function pointer as parameter
func applyOperation(x, y, op) {
    return op(x, y);
}

// Main test code
print("=== Function Pointer Test ===");

// Test 1: Basic function pointer
print("Test 1: Basic Function Pointer");

funcptr = &add;
result = funcptr(10, 5);
print("add(10, 5) via pointer = ", result, "");

funcptr = &subtract;
result = funcptr(10, 5);
print("subtract(10, 5) via pointer = ", result, "");

funcptr = &multiply;
result = funcptr(10, 5);
print("multiply(10, 5) via pointer = ", result, "");

funcptr = &divide;
result = funcptr(10, 5);
print("divide(10, 5) via pointer = ", result, "");

// Test 2: Array of function pointers (calculator)
print("Test 2: Calculator with Function Pointer Array");

array *operations[4];
operations[0] = &add;
operations[1] = &subtract;
operations[2] = &multiply;
operations[3] = &divide;

array opNames.s[4];
opNames[0] = "add";
opNames[1] = "subtract";
opNames[2] = "multiply";
opNames[3] = "divide";

x = 20;
y = 4;
i = 0;

while i < 4 {
    result = operations[i](x, y);
    print(opNames[i++], "(", x, ", ", y, ") = ", result, "");
}

// Test 3: Function pointer as parameter
print("Test 3: Function Pointer as Parameter");

result = applyOperation(15, 3, &add);
print("applyOperation(15, 3, add) = ", result, "");

result = applyOperation(15, 3, &multiply);
print("applyOperation(15, 3, multiply) = ", result, "");

// Test 4: Dynamic operation selection
print("Test 4: Dynamic Operation Selection");

choice = 2;  // Choose multiply
print("Choice = ", choice, " (multiply)");

result = operations[choice](7, 6);
print("Result: 7 * 6 = ", result, "");

print("=== Function Pointer Tests Complete ===");
