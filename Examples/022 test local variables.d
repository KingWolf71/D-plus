/* Test Local Variable Scoping
   - Variables inside functions are local
   - Variables outside functions are global
   - Functions can read globals
*/

#pragma appname "Local Variable Test"
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

print("Testing Local Variable Scoping\n");

// Global variables
globalVar = 100;
x = 10;

print("\n=== Test 1: Local variables ===\n");
printf("Before function: globalVar=%d x=%d\n", globalVar, x);

func test1() {
    localVar = 42;      // Local to test1
    x = 999;            // Local x (shadows global x)
    printf("Inside test1: localVar=%d x=%d\n", localVar, x);
    printf("Inside test1: globalVar=%d (reading global)\n", globalVar);
    return localVar;
}

result = test1();
printf("After function: result=%d\n", result);
printf("Global x unchanged: x=%d\n", x);
printf("Global globalVar: globalVar=%d\n", globalVar);

print("\n=== Test 2: Different functions, same local names ===\n");

func test2() {
    localVar = 111;     // Different localVar than test1
    printf("test2: localVar=%d\n", localVar);
    return localVar;
}

func test3() {
    localVar = 222;     // Yet another localVar
    printf("test3: localVar=%d\n", localVar);
    return localVar;
}

r1 = test2();
r2 = test3();
printf("test2 returned: %d\n", r1);
printf("test3 returned: %d\n", r2);

print("\n=== Test 3: Parameters are local ===\n");

func testParams(a, b) {
    sum = a + b;        // sum is local
    printf("testParams: a=%d b=%d sum=%d\n", a, b, sum);
    return sum;
}

a = 5;  // Global a
b = 7;  // Global b
r3 = testParams(100, 200);
print("After testParams:");
printf("  Global a=%d (unchanged)\n", a);
printf("  Global b=%d (unchanged)\n", b);
printf("  Result=%d\n", r3);

print("\n=== Test 4: Reading and writing globals ===\n");

counter = 0;  // Global counter

func increment() {
    counter = counter + 1;  // First 'counter' is local (write), second is global (read)
    printf("Inside increment: counter=%d (local copy)\n", counter);
    return counter;
}

printf("Before: global counter=%d\n", counter);
r4 = increment();
printf("After: global counter=%d (unchanged)\n", counter);
printf("Function returned: %d\n", r4);

print("\n=== All Tests Complete ===");
