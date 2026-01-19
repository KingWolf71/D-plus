/* Function Test - Compact
   Tests: int/float/string returns, nesting, recursion
*/

#pragma appname "Function Test"
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

// Integer function
func add(a, b) {
    return a + b;
}

// Float function
func divide.f(x.f, y.f) {
    return x / y;
}

// String function
func greet.s(name.s) {
    return "Hi " + name.s;
}

// Nested call
func addSquares(a, b) {
    return a * a + b * b;
}

// Simple recursion
func factorial(n) {
    if (n <= 1) {
        return 1;
    }
    return n * factorial(n - 1);
}

// TESTS
print("=== Integer Test ===");
r1 = add(10, 5);
printf("add(10,5) = %d\n", r1);

print("\n=== Float Test ===");
r2.f = divide(100.0, 4.0);
printf("divide(100,4) = %f\n", r2);

print("\n=== String Test ===");
s.s = greet("Bob");
print(s);

print("\n=== Nested Test ===");
r3 = addSquares(3, 4);
printf("3*3 + 4*4 = %d\n", r3);

print("\n=== Recursion Test ===");
r4 = factorial(5);
printf("factorial(5) = %d\n", r4);

print("\n=== Done ===");
