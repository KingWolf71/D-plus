// Simple test for .i, .f, .s type annotations
#pragma appname "Type Annotations Test"
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

print("Testing explicit type annotations (.i, .f, .s)");
print("");

// Test 1: Explicit integer annotation
x.i = 42;
print("Test 1: x.i = 42");
print("  x = ", x);
print("");

// Test 2: Explicit float annotation
pi.f = 3.14159;
print("Test 2: pi.f = 3.14159");
print("  pi = ", pi);
print("");

// Test 3: Explicit string annotation
name.s = "D+AI";
print("Test 3: name.s = D+AI");
print("  name = ", name);
print("");

// Test 4: Type conversion with annotation
floatVal.f = 9.8;
intVal.i = floatVal;  // Automatic conversion 9.8 -> 10
print("Test 4: intVal.i = floatVal (9.8)");
print("  floatVal = ", floatVal);
print("  intVal = ", intVal);
print("");

// Test 5: Function return with type annotation
function getFortyTwo() {
    return 42;
}

result.i = getFortyTwo();
print("Test 5: result.i = getFortyTwo()");
print("  result = ", result);
print("");

// Test 6: Explicit casting (new in v1.18.63)
source.f = 7.3;
casted.i = (int)source;
print("Test 6: Explicit cast (int)7.3");
print("  source.f = ", source);
print("  casted.i = (int)source = ", casted);
print("");

// Test 7: Cast to string
number.i = 999;
numStr.s = (string)number;
print("Test 7: Cast to string");
print("  number.i = ", number);
print("  numStr.s = (string)number = ", numStr);
print("");

print("All tests completed!");
