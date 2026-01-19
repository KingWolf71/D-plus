/* =============================================================================
   D+AI Comprehensive Feature Test Suite
   Tests ALL compiler features systematically
   ============================================================================= */

#pragma appname "D+AI-Comprehensive-Test"
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

print("D+AI COMPREHENSIVE FEATURE TEST SUITE");
print("-------------------------------------");

/* =============================================================================
   SECTION 0: Using Built-in Assertions
   Built-in functions:
   - assertEqual(expected, actual) - for integers
   - assertFloatEqual(expected, actual) - for floats (uses pragma floattolerance)
   - assertStringEqual(expected, actual) - for strings
   ============================================================================= */	


/* =============================================================================
   SECTION 1: DATA TYPES AND LITERALS
   ============================================================================= */
print("SECTION 1: Data Types and Literals");
print("-----------------------------------");

// Integer literals
print("Test: Positive integer literal assignment, Expected: 42");
testInt = 42;
print("Test: testInt = 42");
assertEqual(42, testInt);

print("Test: Negative integer literal assignment, Expected: -17");
testNegInt = -17;
print("Test: testNegInt = -17");
assertEqual(-17, testNegInt);

print("Test: Zero integer literal assignment, Expected: 0");
testZero = 0;
print("Test: testZero = 0");
assertEqual(0, testZero);

// Float literals
print("Test: Positive float literal assignment, Expected: 3.14159");
testFloat.f = 3.14159;
print("Test: testFloat ~= 3.14159 (float)");
assertFloatEqual(3.14159, testFloat);

print("Test: Negative float literal assignment, Expected: -2.718");
testNegFloat.f = -2.718;
print("Test: testNegFloat ~= -2.718 (float)");
assertFloatEqual(-2.718, testNegFloat);

print("Test: Zero float literal assignment, Expected: 0.0");
testFloatZero.f = 0.0;
print("Test: testFloatZero ~= 0.0 (float)");
assertFloatEqual(0.0, testFloatZero);

// String literals
print("Test: String literal assignment, Expected: Hello, World!");
testStr.s = "Hello, World!";
print("Hello (string)", "Test: World!", testStr);
assertStringEqual("Hello, World!", testStr);

print("Test: Empty string literal assignment, Expected: (empty)");
testEmptyStr.s = "";
print("Test: testEmptyStr = '' (string)");
assertStringEqual("", testEmptyStr);

/* =============================================================================
   SECTION 2: ARITHMETIC OPERATORS
   ============================================================================= */
print("SECTION 2: Arithmetic Operators");
print("-------------------------------");

a = 20;
b = 7;

// Addition
print("Test: Integer addition (20 + 7), Expected: 27");
resultAdd = a + b;
print("Test: resultAdd = 27");
assertEqual(27, resultAdd);

// Subtraction
print("Test: Integer subtraction (20 - 7), Expected: 13");
resultSub = a - b;
print("Test: resultSub = 13");
assertEqual(13, resultSub);

// Multiplication
print("Test: Integer multiplication (20 * 7), Expected: 140");
resultMul = a * b;
print("Test: resultMul = 140");
assertEqual(140, resultMul);

// Division
print("Test: Integer division (20 / 7), Expected: 2");
resultDiv = a / b;
print("Test: resultDiv = 2");
assertEqual(2, resultDiv);

// Modulo
print("Test: Modulo operation (20 % 7), Expected: 6");
resultMod = a % b;
print("Test: resultMod = 6");
assertEqual(6, resultMod);

// Negative operands
print("Test: Negative operand arithmetic (-10 + 5), Expected: -5");
negResult = -10 + 5;
print("Test: negResult = -5");
assertEqual(-5, negResult);

// Float arithmetic
print("Test: Float multiplication (10.5 * 2.5), Expected: 26.25");
floatA.f = 10.5;
floatB.f = 2.5;
floatResult.f = floatA * floatB;
print("Test: floatResult ~= 26.25 (float)");
assertFloatEqual(26.25, floatResult);

// Mixed int/float
print("Test: Mixed int/float addition (10 + 2.5), Expected: 12.5");
mixedResult.f = 10 + 2.5;
print("Test: mixedResult ~= 12.5 (float)");
assertFloatEqual(12.5, mixedResult);

/* =============================================================================
   SECTION 3: COMPARISON OPERATORS
   ============================================================================= */
print("SECTION 3: Comparison Operators");
print("-------------------------------");

x = 10;
y = 20;
z = 10;

// Less than
print("Test: Less than (10 < 20), Expected: 1");
testLT = (x < y);
print("Test: testLT = 1");
assertEqual(1, testLT);

// Greater than
print("Test: Greater than (20 > 10), Expected: 1");
testGT = (y > x);
print("Test: testGT = 1");
assertEqual(1, testGT);

// Less than or equal
print("Test: Less than or equal (10 <= 10), Expected: 1");
testLE = (x <= z);
print("Test: testLE = 1");
assertEqual(1, testLE);

// Greater than or equal
print("Test: Greater than or equal (20 >= 10), Expected: 1");
testGE = (y >= x);
print("Test: testGE = 1");
assertEqual(1, testGE);

// Equality
print("Test: Equality (10 == 10), Expected: 1");
testEQ = (x == z);
print("Test: testEQ = 1");
assertEqual(1, testEQ);

// Inequality
print("Test: Inequality (10 != 20), Expected: 1");
testNE = (x != y);
print("Test: testNE = 1");
assertEqual(1, testNE);

// Float comparisons
print("Test: Float equality (3.14 == 3.14), Expected: 1");
f1.f = 3.14;
f2.f = 3.14;
testFloatEQ = (f1 == f2);
print("Test: testFloatEQ = 1");
assertEqual(1, testFloatEQ);

/* =============================================================================
   SECTION 4: LOGICAL OPERATORS
   ============================================================================= */
print("SECTION 4: Logical Operators");
print("----------------------------");

p = 5;
q = 15;
r = 25;

// AND operator
print("Test: AND operator (5 < 15 && 15 < 25), Expected: 1");
testAND = (p < q && q < r);
print("Test: testAND = 1");
assertEqual(1, testAND);

// OR operator
print("Test: OR operator (5 > 100 || 15 < 20), Expected: 1");
testOR = (p > 100 || q < 20);
print("Test: testOR = 1");
assertEqual(1, testOR);

// Complex logical expression
print("Test: Complex logical ((5 < 15 && 15 < 25) || 5 == 5), Expected: 1");
testComplex = ((p < q && q < r) || p == 5);
print("Test: testComplex = 1");
assertEqual(1, testComplex);

// Nested conditions
print("Test: Nested conditions (true && true), Expected: 1");
testNested1 = (p < q);
testNested2 = (q < r);
testNestedResult = (testNested1 && testNested2);
print("Test: testNestedResult = 1");
assertEqual(1, testNestedResult);

/* =============================================================================
   SECTION 5: CONTROL FLOW - IF/ELSE
   ============================================================================= */
print("SECTION 5: Control Flow - If/Else");
print("----------------------------------");

// Simple if
testVal = 10;
if (testVal == 10) {
    print("Simple if: PASS");
}

// If-else
if (testVal < 5) {
    print("If-else: FAIL");
} else {
    print("If-else: PASS");
}

// Nested if-else
score = 85;
if (score >= 90) {
    print("Grade: A");
} else {
    if (score >= 80) {
        print("Grade: B (correct for 85)");
    } else {
        if (score >= 70) {
            print("Grade: C");
        } else {
            print("Grade: F");
        }
    }
}

// Multiple conditions
age = 25;
hasLicense = 1;
if (age >= 18 && hasLicense == 1) {
    print("Can drive: YES (correct)");
}

/* =============================================================================
   SECTION 6: CONTROL FLOW - WHILE LOOPS
   ============================================================================= */
print("SECTION 6: Control Flow - While Loops");
print("--------------------------------------");

// Simple while loop
print("Count up 1-5: ");
counter = 1;
while (counter <= 5) {
    print(counter, " ");
    counter++;
}

// While with condition
print("Count down 10-7: ");
countdown = 10;
while (countdown >= 7) {
    print(countdown, " ");
    countdown--;
}

// Nested while loops
print("Multiplication table (3x3):");
i = 1;
while (i <= 3) {
    j = 1;
    while (j <= 3) {
        product = i * j;
        print(product, " ");
        j++;
    }
    i++;
}

// While with break-like logic (sum until > 100)
print("Sum until > 100: ");
sum = 0;
num = 1;
while (sum <= 100) {
    sum += num;
    num++;
}
print(sum, " (first sum > 100)");

/* =============================================================================
   SECTION 7: FUNCTIONS - BASIC
   ============================================================================= */
print("SECTION 7: Functions - Basic");
print("----------------------------");

// Function with no parameters
func greet.i() {
    return 42;
}

print("Test: Function with no parameters greet(), Expected: 42");
greeting = greet();
print("Test: greeting = 42");
assertEqual(42, greeting);

// Function with one parameter
func square.i(n.i) {
    return n * n;
}

print("Test: Function square(5), Expected: 25");
sq5 = square(5);
print("Test: sq5 = 25");
assertEqual(25, sq5);

// Function with two parameters
func add.i(a.i, b.i) {
    return a + b;
}

print("Test: Function add(7, 5), Expected: 12");
sum12 = add(7, 5);
print("Test: sum12 = 12");
assertEqual(12, sum12);

// Function with three parameters
func volume.i(length.i, width.i, height.i) {
    return length * width * height;
}

print("Test: Function volume(3, 4, 5), Expected: 60");
vol = volume(3, 4, 5);
print("Test: vol = 60");
assertEqual(60, vol);

// Function returning int (integer division)
func divide.i(a.i, b.i) {
    return a / b;
}

print("Test: Function divide(22, 7), Expected: 3");
divResult = divide(22, 7);
print("Test: divResult = 3");
assertEqual(3, divResult);

/* =============================================================================
   SECTION 8: FUNCTIONS - RECURSION
   ============================================================================= */
print("SECTION 8: Functions - Recursion");
print("--------------------------------");

// Factorial
func factorial.i(n.i) {
    if (n <= 1) {
        return 1;
    }
    return n * factorial(n - 1);
}

fact5 = factorial(5);
print("Test: fact5 = 120");
assertEqual(120, fact5);

fact7 = factorial(7);
print("Test: fact7 = 5040");
assertEqual(5040, fact7);

// Fibonacci
func fibonacci.i(n.i) {
    if (n <= 1) {
        return n;
    }
    return fibonacci(n - 1) + fibonacci(n - 2);
}

fib8 = fibonacci(8);
print("Test: fib8 = 21");
assertEqual(21, fib8);

fib10 = fibonacci(10);
print("Test: fib10 = 55");
assertEqual(55, fib10);

// Sum of digits (recursive)
func sumDigits.i(n.i) {
    if (n < 10) {
        return n;
    }
    return (n % 10) + sumDigits(n / 10);
}

digitSum = sumDigits(12345);
print("Test: digitSum = 15");
assertEqual(15, digitSum);

/* =============================================================================
   SECTION 9: FUNCTIONS - NESTED CALLS
   ============================================================================= */
print("SECTION 9: Functions - Nested Calls");
print("-----------------------------------");

func double.i(n.i) {
    return n * 2;
}

func triple.i(n.i) {
    return n * 3;
}

// Nested function calls
nested1 = double(triple(5));
print("Test: nested1 = 30");
assertEqual(30, nested1);

// Triple nesting
nested2 = double(double(double(3)));
print("Test: nested2 = 24");
assertEqual(24, nested2);

// Mix with arithmetic
nested3 = add(square(4), square(3));
print("Test: nested3 = 25");
assertEqual(25, nested3);

// Complex nesting
func compute.i(a.i, b.i, c.i) {
    return a * b + c;
}

nested4 = compute(square(2), triple(3), double(5));
print("Test: nested4 = 46");
assertEqual(46, nested4);

/* =============================================================================
   SECTION 10: FUNCTIONS - MULTIPLE RETURNS
   ============================================================================= */
print("SECTION 10: Functions - Multiple Returns");
print("----------------------------------------");

func classify.i(n.i) {
    if (n < 0) {
        return -1;
    }
    if (n == 0) {
        return 0;
    }
    return 1;
}

class1 = classify(-10);
print("Test: class1 = -1");
assertEqual(-1, class1);

class2 = classify(0);
print("Test: class2 = 0");
assertEqual(0, class2);

class3 = classify(42);
print("Test: class3 = 1");
assertEqual(1, class3);

// Early return
func findFirst.i(target.i) {
    i = 0;
    while (i < 100) {
        if (i == target) {
            return i;
        }
        i++;
    }
    return -1;
}

found = findFirst(17);
print("Test: found = 17");
assertEqual(17, found);

/* =============================================================================
   SECTION 11: BUILT-IN FUNCTIONS
   ============================================================================= */
print("SECTION 11: Built-in Functions");
print("------------------------------");

// abs()
absNeg = abs(-42);
print("Test: absNeg = 42");
assertEqual(42, absNeg);

absPos = abs(17);
print("Test: absPos = 17");
assertEqual(17, absPos);

absZero = abs(0);
print("Test: absZero = 0");
assertEqual(0, absZero);

// min()
minVal = min(15, 23);
print("Test: minVal = 15");
assertEqual(15, minVal);

minNeg = min(-5, -10);
print("Test: minNeg = -10");
assertEqual(-10, minNeg);

// max()
maxVal = max(15, 23);
print("Test: maxVal = 23");
assertEqual(23, maxVal);

maxNeg = max(-5, -10);
print("Test: maxNeg = -5");
assertEqual(-5, maxNeg);

// random() - just test it runs (no assertion, value is random)
rand1 = random(100);
print("random(100): ", rand1, " (should be 0-99)");

// Nested built-in calls
nestedBuiltin = abs(min(-10, -5));
print("Test: nestedBuiltin = 10");
assertEqual(10, nestedBuiltin);

/* =============================================================================
   SECTION 12: LOCAL VARIABLES
   ============================================================================= */
print("SECTION 12: Local Variables");
print("---------------------------");

globalX = 100;

func testLocal.i() {
    localX = 42;
    return localX;
}

resultLocal = testLocal();
print("Test: resultLocal = 42");
assertEqual(42, resultLocal);
print("Test: globalX = 100");
assertEqual(100, globalX);

// Parameters are local
globalA = 999;

func testParam.i(globalA.i) {
    return globalA * 2;
}

resultParam = testParam(5);
print("Test: resultParam = 10");
assertEqual(10, resultParam);
print("Test: globalA = 999");
assertEqual(999, globalA);

// Multiple local variables
func multiLocal.i(a.i, b.i) {
    temp1 = a * 2;
    temp2 = b * 3;
    return temp1 + temp2;
}

multiResult = multiLocal(4, 5);
print("Test: multiResult = 23");
assertEqual(23, multiResult);

/* =============================================================================
   SECTION 13: MACROS
   ============================================================================= */
print("SECTION 13: Macros");
print("------------------");

#define PI 3.14159
#define MAX_SIZE 1000

// Macro in expression
radius = 5;
area = PI * radius * radius;
print("Test: area ~= 78.53975 (float)");
assertFloatEqual(78.53975, area);

// Macro in condition
testMacro = (MAX_SIZE > 500);
print("Test: testMacro = 1");
assertEqual(1, testMacro);

/* =============================================================================
   SECTION 14: STRING OPERATIONS
   ============================================================================= */
print("SECTION 14: String Operations");
print("-----------------------------");

str1 = "Hello";
str2 = "World";

// String concatenation via print
print("Concatenation: ", str1, " ", str2);

// Mixed string and number
name = "Value";
value = 42;
print("Mixed: ", name, " = ", value);

/* =============================================================================
   SECTION 15: EDGE CASES AND STRESS TESTS
   ============================================================================= */
print("SECTION 15: Edge Cases and Stress Tests");
print("---------------------------------------");

// Large numbers
largeNum = 999999;
print("Large number: ", largeNum);

// Deep recursion (not too deep to avoid stack overflow)
deepFact = factorial(10);
print("Test: deepFact = 3628800");
assertEqual(3628800, deepFact);

// Many parameters
func sixParams.i(a.i, b.i, c.i, d.i, e.i, f.i) {
    return a + b + c + d + e + f;
}

sixSum = sixParams(1, 2, 3, 4, 5, 6);
print("Test: sixSum = 21");
assertEqual(21, sixSum);

// Complex expression
complex = ((10 + 5) * 3 - 7) / 2 + 4;
print("Test: complex = 23");
assertEqual(23, complex);

// Deep nesting of operators
deepNest = 1 + 2 * 3 + 4 * 5 - 6 / 2;
print("Test: deepNest = 24");
assertEqual(24, deepNest);

/* =============================================================================
   SECTION 16: OPTIMIZATION TESTS
   ============================================================================= */
print("SECTION 16: Optimization Tests");
print("------------------------------");

// Constant folding
constFold1 = 10 + 5;
print("Test: constFold1 = 15");
assertEqual(15, constFold1);

constFold2 = 20 * 3;
print("Test: constFold2 = 60");
assertEqual(60, constFold2);

// Identity optimization
identX = 42;
identAdd = identX + 0;
print("Test: identAdd = 42");
assertEqual(42, identAdd);

identMul = identX * 1;
print("Test: identMul = 42");
assertEqual(42, identMul);

identSub = identX - 0;
print("Test: identSub = 42");
assertEqual(42, identSub);

identDiv = identX / 1;
print("Test: identDiv = 42");
assertEqual(42, identDiv);

identZero = identX * 0;
print("Test: identZero = 0");
assertEqual(0, identZero);

// Works well till here

/* =============================================================================
   SECTION 17: REAL-WORLD ALGORITHMS
   ============================================================================= */
print("SECTION 17: Real-world Algorithms");
print("---------------------------------");

// GCD (Greatest Common Divisor)
func gcd.i(a.i, b.i) {
    while (b != 0) {
        temp = b;
        b = a % b;
        a = temp;
    }
    return a;
}

gcdResult = gcd(48, 18);
print("Test: gcdResult = 6");
assertEqual(6, gcdResult);

// Prime checker
func isPrime.i(n.i) {
    if (n <= 1) {
        return 0;
    }
    if (n == 2) {
        return 1;
    }
    i = 2;
    while (i * i <= n) {
        if (n % i == 0) {
            return 0;
        }
        i++;
    }
    return 1;
}

prime17 = isPrime(17);
print("Test: prime17 = 1");
assertEqual(1, prime17);

prime18 = isPrime(18);
print("Test: prime18 = 0");
assertEqual(0, prime18);

// Power function
func power.i(base.i, exp.i) {
    if (exp == 0) {
        return 1;
    }
    result = 1;
    i = 0;
    while (i < exp) {
        result *= base;
        i++;
    }
    return result;
}

pow2_10 = power(2, 10);
print("Test: pow2_10 = 1024");
assertEqual(1024, pow2_10);

pow3_4 = power(3, 4);
print("Test: pow3_4 = 81");
assertEqual(81, pow3_4);

/* =============================================================================
   SECTION 18: TYPE SYSTEM AND AUTOMATIC CONVERSION
   ============================================================================= */
print("SECTION 18: Type System and Automatic Conversion");
print("------------------------------------------------");

// Explicit type declarations
intVar = 42;
floatVar.f = 3.14159;
stringVar.s = "Hello";

print("Int var: ", intVar, " (expected: 42)");
print("Float var: ", floatVar, " (expected: 3.14159)");
print("String var: ", stringVar, " (expected: Hello)");

// Typed function signatures
func squareInt.i(num.i) {
    return num * num;
}

func squareFloat.f(num.f) {
    return num * num;
}

// Test INT function with INT param
sqInt = squareInt(5);
print("Test: sqInt = 25");
assertEqual(25, sqInt);

// Test FLOAT function with FLOAT param
sqFloat.f = squareFloat(2.5);
print("Test: sqFloat ~= 6.25 (float)");
assertFloatEqual(6.25, sqFloat);

// Parameter type conversion: FLOAT -> INT (explicit cast required)
floatParam.f = 3.7;
sqConverted = squareInt((int)floatParam);
print("Test: sqConverted = 9");
assertEqual(9, sqConverted);

// Parameter type conversion: INT -> FLOAT (explicit cast required)
intParam = 4;
sqFloatConverted.f = squareFloat((float)intParam);
print("Test: sqFloatConverted ~= 16.0 (float)");
assertFloatEqual(16.0, sqFloatConverted);

// Assignment type conversion: INT -> FLOAT (explicit cast required)
assignInt = 42;
assignFloat.f = (float)assignInt;
print("Test: assignFloat ~= 42.0 (float)");
assertFloatEqual(42.0, assignFloat);

// Assignment type conversion: FLOAT -> INT (explicit cast required)
assignFloatVal.f = 9.8;
assignIntVal = (int)assignFloatVal;
print("Test: assignIntVal = 9");
assertEqual(9, assignIntVal);

// Function return type conversion (explicit casts in following tests)
func returnInt.i() {
    return 100;
}

func returnFloat.f() {
    return 2.718;
}

// INT function result to FLOAT variable (explicit cast)
floatFromInt.f = (float)returnInt();
print("Test: floatFromInt ~= 100.0 (float)");
assertFloatEqual(100.0, floatFromInt);

// FLOAT function result to INT variable (explicit cast)
intFromFloat = (int)returnFloat();
print("Test: intFromFloat = 2");
assertEqual(2, intFromFloat);

// Automatic return type conversion
func returnIntButGiveFloat.i() {
    return (int)3.14159;  // Explicit cast in return
}

func returnFloatButGiveInt.f() {
    return (float)42;  // Explicit cast in return
}

piAsInt = returnIntButGiveFloat();
print("Test: piAsInt = 3");
assertEqual(3, piAsInt);

intAsFloat.f = returnFloatButGiveInt();
print("Test: intAsFloat ~= 42.0 (float)");
assertFloatEqual(42.0, intAsFloat);

// Complex type conversion chain (with explicit casts)
func complexChain.f(a.f, b.i) {
    tempInt = (int)a;           // FLOAT -> INT explicit cast
    tempFloat.f = (float)b;     // INT -> FLOAT explicit cast
    return (float)tempInt + tempFloat;
}

chainResult.f = complexChain(5.8, 3);
print("Test: chainResult ~= 8.0 (float)");
assertFloatEqual(8.0, chainResult);

// Nested calls with type conversion
func addInts.i(a.i, b.i) {
    return a + b;
}

func multiplyFloats.f(x.f, y.f) {
    return x * y;
}

// Pass float function result to int function (explicit cast)
nestedConv = addInts((int)multiplyFloats(2.5, 2.0), 10);
print("Test: nestedConv = 15");
assertEqual(15, nestedConv);

/* =============================================================================
   SECTION 19: TERNARY OPERATOR
   ============================================================================= */
print("SECTION 19: Ternary Operator");
print("----------------------------");

// Basic ternary operator
ternary1 = (5 > 3) ? 100 : 200;
print("Test: ternary1 = 100");
assertEqual(100, ternary1);

ternary2 = (2 > 7) ? 100 : 200;
print("Test: ternary2 = 200");
assertEqual(200, ternary2);

// Ternary with variables
ternX = 15;
ternY = 20;
ternMax = (ternX > ternY) ? ternX : ternY;
print("Test: ternMax = 20");
assertEqual(20, ternMax);

ternMin = (ternX < ternY) ? ternX : ternY;
print("Test: ternMin = 15");
assertEqual(15, ternMin);

// Nested ternary
nestedTern = (10 > 5) ? ((3 > 1) ? 111 : 222) : 333;
print("Test: nestedTern = 111");
assertEqual(111, nestedTern);

// Ternary in expression
ternExpr = 50 + ((7 > 4) ? 10 : 20);
print("Test: ternExpr = 60");
assertEqual(60, ternExpr);

// Ternary with zero/equality
ternZero = (0 == 0) ? 999 : 888;
print("Test: ternZero = 999");
assertEqual(999, ternZero);

// Ternary MAX macro
#define MAX(a,b) ((a) > (b) ? (a) : (b))
#define MIN(a,b) ((a) < (b) ? (a) : (b))

macroMax1 = MAX(42, 17);
print("Test: macroMax1 = 42");
assertEqual(42, macroMax1);

macroMax2 = MAX(-5, -10);
print("Test: macroMax2 = -5");
assertEqual(-5, macroMax2);

macroMin1 = MIN(42, 17);
print("Test: macroMin1 = 17");
assertEqual(17, macroMin1);

// Float ternary
floatTern1.f = (3.7 > 2.1) ? 5.5 : 8.8;
print("Test: floatTern1 ~= 5.5 (float)");
assertFloatEqual(5.5, floatTern1);

// Ternary in function call
func useResult.i(val.i) {
    return val * 2;
}

ternFunc = useResult((8 > 3) ? 10 : 5);
print("Test: ternFunc = 20");
assertEqual(20, ternFunc);

// Complex ternary expression - THE CRITICAL BUG FIX TEST!
complexCond = (10 + 5 > 12) ? (3 * 4) : (5 + 1);
print("Test: complexCond = 12");
assertEqual(12, complexCond);

/* =============================================================================
   SECTION 20: LOGICAL NOT OPERATOR
   ============================================================================= */
print("SECTION 20: Logical NOT Operator");
print("--------------------------------");

// Basic NOT
notTrue = !(5 > 10);
print("Test: notTrue = 1");
assertEqual(1, notTrue);

notFalse = !(10 > 5);
print("Test: notFalse = 0");
assertEqual(0, notFalse);

// NOT with zero
notZero = !(0);
print("Test: notZero = 1");
assertEqual(1, notZero);

notNonZero = !(42);
print("Test: notNonZero = 0");
assertEqual(0, notNonZero);

// NOT with equality
notEqual = !(5 == 5);
print("Test: notEqual = 0");
assertEqual(0, notEqual);

// Double NOT
doubleNot = !!(10);
print("Test: doubleNot = 1");
assertEqual(1, doubleNot);

// NOT in complex expression
testNotComplex = (!(3 > 5) && (7 > 4));
print("Test: testNotComplex = 1");
assertEqual(1, testNotComplex);

// NOT with inequality
testNotIneq = !(10 != 10);
print("Test: testNotIneq = 1");
assertEqual(1, testNotIneq);

/* =============================================================================
   FINAL SUMMARY
   ============================================================================= */
print("");
print("========================================");
print("  COMPREHENSIVE TEST SUITE COMPLETE");
print("========================================");
print("");
print("Note: Built-in assertions automatically report failures.");
print("If you see this message, all tests passed!");
print("");
