// Test casting syntax: (int), (float), (string)
#pragma appname "Casting Test"
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

print("Testing explicit casting");
print("");

// Test 1: Cast float to int
x.f = 3.7;
y.i = (int)x;
print("Test 1: Cast float to int");
print("  x.f = ", x);
print("  y.i = (int)x = ", y);
print("");

// Test 2: Cast int to float
a.i = 42;
b.f = (float)a;
print("Test 2: Cast int to float");
print("  a.i = ", a);
print("  b.f = (float)a = ", b);
print("");

// Test 3: Cast int to string
num.i = 123;
str.s = (string)num;
print("Test 3: Cast int to string");
print("  num.i = ", num);
print("  str.s = (string)num = ", str);
print("");

// Test 4: Cast float to string
pi.f = 3.14159;
piStr.s = (string)pi;
print("Test 4: Cast float to string");
print("  pi.f = ", pi);
print("  piStr.s = (string)pi = ", piStr);
print("");

// Test 5: Cast in expression
result.i = (int)(3.9 + 2.1);
print("Test 5: Cast in expression");
print("  result.i = (int)(3.9 + 2.1) = ", result);
print("");

// Test 6: Multiple casts
val.f = 7.8;
temp.s = (string)val;
back.i = (int)val;
print("Test 6: Multiple casts from same value");
print("  val.f = ", val);
print("  temp.s = (string)val = ", temp);
print("  back.i = (int)val = ", back);
print("");

// Test 7: Cast in function calls
function double.i(n.i) {
    return n * 2;
}

floatNum.f = 5.7;
doubled = double((int)floatNum);
print("Test 7: Cast in function call");
print("  floatNum.f = ", floatNum);
print("  double((int)floatNum) = ", doubled);
print("");

// Test 8: Cast function return value
function getAverage.f() {
    return 42.6;
}

avgInt.i = (int)getAverage();
print("Test 8: Cast function return value");
print("  (int)getAverage() = ", avgInt);
print("");

// Test 9: Chained casts
chain.f = 9.9;
chainStr.s = (string)(int)chain;
print("Test 9: Chained cast (float->int->string)");
print("  chain.f = ", chain);
print("  (string)(int)chain = ", chainStr);
print("");

// Test 10: Cast in arithmetic
calc.i = (int)(3.7 * 2.5) + (int)(1.9 + 0.8);
print("Test 10: Cast in arithmetic");
print("  (int)(3.7 * 2.5) + (int)(1.9 + 0.8) = ", calc);
print("");

print("All casting tests completed!");
