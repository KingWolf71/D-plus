/* Minimal fibonacci test */
#pragma appname "Fib Test"
#pragma console on
#pragma ListASM on
#pragma consolesize "680x740"
#pragma consoleposition "30,50"
#pragma asmdecimal on

func fibonacci(n) {
    if (n <= 1) {
        return n;
    }
    return fibonacci(n - 1) + fibonacci(n - 2);
}

result = fibonacci(2);
print("fibonacci(2) = ", result, " (should be 1)");
