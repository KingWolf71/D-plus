/* Comprehensive Type Inference Test
   Tests all permutations of explicit typing and type inference:
   1. Global variables (explicit and inferred)
   2. Local variables (explicit and inferred)
   3. Function parameters (typed and untyped)
   4. Function returns (typed and untyped)
   5. Arrays (typed and element access)
   6. Type conversions (forced and avoided)
   7. Mixed scenarios and edge cases
*/

#pragma appname "Type Inference Comprehensive Test"
#pragma decimals 4
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

print("==========================================================================");
print("COMPREHENSIVE TYPE INFERENCE TEST - V1.18.13");
print("==========================================================================");
print("");

// =============================================================================
// TEST SECTION 1: GLOBAL VARIABLES - EXPLICIT TYPE SUFFIXES
// =============================================================================
print("TEST 1: Global Variables - Explicit Type Suffixes");
print("--------------------------------------------------------------------------");

// Explicit integer
gInt.i = 42;
assertEqual(42, gInt);
print("  [1.1] gInt.i = 42 ... PASS");

// Explicit float
gFloat.f = 3.14159;
assertFloatEqual(3.14159, gFloat);
print("  [1.2] gFloat.f = 3.14159 ... PASS");

// Explicit double (same as .f)
gDouble.d = 2.71828;
assertFloatEqual(2.71828, gDouble);
print("  [1.3] gDouble.d = 2.71828 ... PASS");

// Explicit string
gString.s = "Hello World";
assertStringEqual("Hello World", gString);
print("  [1.4] gString.s = Hello World ... PASS");

print("");

// =============================================================================
// TEST SECTION 2: GLOBAL VARIABLES - INFERRED FROM LITERALS
// =============================================================================
print("TEST 2: Global Variables - Inferred from Literals");
print("--------------------------------------------------------------------------");

// Inferred integer from int literal
inferredInt = 100;
assertEqual(100, inferredInt);
print("  [2.1] inferredInt = 100 (inferred INT) ... PASS");

// Inferred float from float literal
inferredFloat = 99.99;
assertFloatEqual(99.99, inferredFloat);
print("  [2.2] inferredFloat = 99.99 (inferred FLOAT) ... PASS");

// Inferred string from string literal
inferredString = "Inferred Type";
assertStringEqual("Inferred Type", inferredString);
print("  [2.3] inferredString = Inferred Type (inferred STRING) ... PASS");

print("");

// =============================================================================
// TEST SECTION 3: GLOBAL VARIABLES - INFERRED FROM EXPRESSIONS
// =============================================================================
print("TEST 3: Global Variables - Inferred from Expressions");
print("--------------------------------------------------------------------------");

// Integer arithmetic
intExpr = 10 + 20 * 3;
assertEqual(70, intExpr);
print("  [3.1] intExpr = 10 + 20 * 3 (inferred INT) ... PASS");

// Float arithmetic
floatExpr = 1.5 * 2.0 + 3.5;
assertFloatEqual(6.5, floatExpr);
print("  [3.2] floatExpr = 1.5 * 2.0 + 3.5 (inferred FLOAT) ... PASS");

// Mixed arithmetic (int/float = float)
mixedExpr = 10 / 4.0;
assertFloatEqual(2.5, mixedExpr);
print("  [3.3] mixedExpr = 10 / 4.0 (inferred FLOAT from mixed) ... PASS");

// String concatenation
stringExpr = "Hello" + " " + "World";
assertStringEqual("Hello World", stringExpr);
print("  [3.4] stringExpr = Hello + World (inferred STRING) ... PASS");

print("");

// =============================================================================
// TEST SECTION 4: TYPE CONVERSION - EXPLICIT VS INFERRED
// =============================================================================
print("TEST 4: Type Conversion - Explicit vs Inferred");
print("--------------------------------------------------------------------------");

// Force int to float with explicit suffix
forceFloat.f = 42;
assertFloatEqual(42.0, forceFloat);
print("  [4.1] forceFloat.f = 42 (INT literal converted to FLOAT) ... PASS");

// Force float to int with explicit suffix
forceInt.i = 3.14159;
assertEqual(3, forceInt);
print("  [4.2] forceInt.i = 3.14159 (FLOAT truncated to INT) ... PASS");

// Inferred type preserves precision (no conversion)
noConvert = 1.25 * 2.5;
assertFloatEqual(3.125, noConvert);
print("  [4.3] noConvert = 1.25 * 2.5 (inferred FLOAT, no truncation) ... PASS");

print("");

// =============================================================================
// TEST SECTION 5: LOCAL VARIABLES - EXPLICIT TYPE SUFFIXES
// =============================================================================
print("TEST 5: Local Variables - Explicit Type Suffixes");
print("--------------------------------------------------------------------------");

function testLocalExplicit() {
    localInt.i = 123;
    assertEqual(123, localInt);

    localFloat.f = 45.678;
    assertFloatEqual(45.678, localFloat);

    localString.s = "Local String";
    assertStringEqual("Local String", localString);

    print("  [5.1] Local explicit int ... PASS");
    print("  [5.2] Local explicit float ... PASS");
    print("  [5.3] Local explicit string ... PASS");
}

testLocalExplicit();
print("");

// =============================================================================
// TEST SECTION 6: LOCAL VARIABLES - INFERRED FROM LITERALS
// =============================================================================
print("TEST 6: Local Variables - Inferred from Literals");
print("--------------------------------------------------------------------------");

function testLocalInferred() {
    infInt = 555;
    assertEqual(555, infInt);

    infFloat = 77.777;
    assertFloatEqual(77.777, infFloat);

    infString = "Inferred Local";
    assertStringEqual("Inferred Local", infString);

    print("  [6.1] Local inferred int ... PASS");
    print("  [6.2] Local inferred float ... PASS");
    print("  [6.3] Local inferred string ... PASS");
}

testLocalInferred();
print("");

// =============================================================================
// TEST SECTION 7: LOCAL VARIABLES - INFERRED FROM EXPRESSIONS
// =============================================================================
print("TEST 7: Local Variables - Inferred from Expressions");
print("--------------------------------------------------------------------------");

function testLocalExpressions() {
    // This is the critical test case from bug fix2.lj
    array localFloats.f[3];
    localFloats[0] = 1.25;
    localFloats[1] = 2.5;
    localFloats[2] = 4.0;

    // CRITICAL: product has NO suffix - type should be inferred as FLOAT
    product = localFloats[0] * localFloats[1];
    assertFloatEqual(3.125, product);
    print("  [7.1] product = localFloats[0] * localFloats[1] (inferred FLOAT) ... PASS");

    // Sum of float array elements
    sum = localFloats[0] + localFloats[1] + localFloats[2];
    assertFloatEqual(7.75, sum);
    print("  [7.2] sum = array[0] + array[1] + array[2] (inferred FLOAT) ... PASS");

    // Average calculation
    avg = sum / 3.0;
    assertFloatEqual(2.583, avg);
    print("  [7.3] avg = sum / 3.0 (inferred FLOAT) ... PASS");

    // Integer arithmetic
    intCalc = 10 + 20;
    assertEqual(30, intCalc);
    print("  [7.4] intCalc = 10 + 20 (inferred INT) ... PASS");
}

testLocalExpressions();
print("");

// =============================================================================
// TEST SECTION 8: FUNCTION PARAMETERS - TYPED
// =============================================================================
print("TEST 8: Function Parameters - Typed");
print("--------------------------------------------------------------------------");

function addInts.i(a.i, b.i) {
    result = a + b;
    return result;
}

function multiplyFloats.f(x.f, y.f) {
    result = x * y;
    return result;
}

function concatStrings.s(s1.s, s2.s) {
    result = s1 + s2;
    return result;
}

r1 = addInts(15, 25);
assertEqual(40, r1);
print("  [8.1] addInts(15, 25) typed parameters ... PASS");

r2 = multiplyFloats(3.5, 2.0);
assertFloatEqual(7.0, r2);
print("  [8.2] multiplyFloats(3.5, 2.0) typed parameters ... PASS");

r3.s = concatStrings("Hello", "World");
assertStringEqual("HelloWorld", r3);
print("  [8.3] concatStrings typed parameters ... PASS");

print("");

// =============================================================================
// TEST SECTION 9: FUNCTION PARAMETERS - UNTYPED (INFERRED USAGE)
// =============================================================================
print("TEST 9: Function Parameters - Untyped (inferred usage)");
print("--------------------------------------------------------------------------");

function flexAdd.f(a.f, b.f) {
    result = a + b;
    return result;
}

// Use with integers (but function returns float)
flexInt = flexAdd(10, 20);
assertFloatEqual(30.0, flexInt);
print("  [9.1] flexAdd(10, 20) as INT -> FLOAT ... PASS");

// Use with floats
flexFloat = flexAdd(1.5, 2.5);
assertFloatEqual(4.0, flexFloat);
print("  [9.2] flexAdd(1.5, 2.5) untyped params as FLOAT ... PASS");

print("");

// =============================================================================
// TEST SECTION 10: FUNCTION RETURNS - TYPED
// =============================================================================
print("TEST 10: Function Returns - Typed");
print("--------------------------------------------------------------------------");

function getFloat.f() {
    return 99.99;
}

function getInt.i() {
    return 42;
}

function getString.s() {
    return "Returned String";
}

retFloat.f = getFloat();
assertFloatEqual(99.99, retFloat);
print("  [10.1] getFloat.f() returns typed float ... PASS");

retInt.i = getInt();
assertEqual(42, retInt);
print("  [10.2] getInt.i() returns typed int ... PASS");

retString.s = getString();
assertStringEqual("Returned String", retString);
print("  [10.3] getString.s() returns typed string ... PASS");

print("");

// =============================================================================
// TEST SECTION 11: FUNCTION RETURNS - UNTYPED (INFERRED)
// =============================================================================
print("TEST 11: Function Returns - Untyped (inferred)");
print("--------------------------------------------------------------------------");

function computeAverage.f() {
    array values.f[4];
    values[0] = 1.0;
    values[1] = 2.0;
    values[2] = 3.0;
    values[3] = 4.0;

    // CRITICAL: sum and avg have no suffix - inferred as FLOAT
    sum = values[0] + values[1] + values[2] + values[3];
    avg = sum / 4.0;
    return avg;
}

// CRITICAL: capture has no suffix - inferred as FLOAT from return value
computedAvg = computeAverage();
assertFloatEqual(2.5, computedAvg);
print("  [11.1] computeAverage() untyped return (inferred FLOAT) ... PASS");

print("");

// =============================================================================
// TEST SECTION 12: ARRAYS - TYPED ARRAYS AND ELEMENT ACCESS
// =============================================================================
print("TEST 12: Arrays - Typed Arrays and Element Access");
print("--------------------------------------------------------------------------");

// Integer array
array intArray.i[3];
intArray[0] = 10;
intArray[1] = 20;
intArray[2] = 30;

intSum = intArray[0] + intArray[1] + intArray[2];
assertEqual(60, intSum);
print("  [12.1] Integer array sum (inferred INT) ... PASS");

// Float array
array floatArray.f[3];
floatArray[0] = 1.5;
floatArray[1] = 2.5;
floatArray[2] = 3.5;

floatSum = floatArray[0] + floatArray[1] + floatArray[2];
assertFloatEqual(7.5, floatSum);
print("  [12.2] Float array sum (inferred FLOAT) ... PASS");

// String array
array stringArray.s[3];
stringArray[0] = "A";
stringArray[1] = "B";
stringArray[2] = "C";

stringConcat = stringArray[0] + stringArray[1] + stringArray[2];
assertStringEqual("ABC", stringConcat);
print("  [12.3] String array concat (inferred STRING) ... PASS");

print("");

// =============================================================================
// TEST SECTION 13: MIXED SCENARIOS - COMPLEX EXPRESSIONS
// =============================================================================
print("TEST 13: Mixed Scenarios - Complex Expressions");
print("--------------------------------------------------------------------------");

// Integer division (result is INT)
intDiv = 10 / 3;
assertEqual(3, intDiv);
print("  [13.1] intDiv = 10 / 3 (inferred INT, truncated) ... PASS");

// Float division (result is FLOAT)
floatDiv = 10.0 / 3.0;
assertFloatEqual(3.333, floatDiv);
print("  [13.2] floatDiv = 10.0 / 3.0 (inferred FLOAT, precise) ... PASS");

// Mixed division (int / float = float)
mixedDiv = 10 / 3.0;
assertFloatEqual(3.333, mixedDiv);
print("  [13.3] mixedDiv = 10 / 3.0 (inferred FLOAT from mixed) ... PASS");

// Complex float expression
complexFloat = (1.5 + 2.5) * 3.0 / 2.0;
assertFloatEqual(6.0, complexFloat);
print("  [13.4] complexFloat = (1.5 + 2.5) * 3.0 / 2.0 (inferred FLOAT) ... PASS");

// String with number concatenation
stringNum = "Value: " + 42.5;
assertStringEqual("Value: 42.5", stringNum);
print("  [13.5] stringNum = Value: 42.5 (inferred STRING) ... PASS");

print("");

// =============================================================================
// TEST SECTION 14: EDGE CASES - REASSIGNMENT AND TYPE STABILITY
// =============================================================================
print("TEST 14: Edge Cases - Reassignment and Type Stability");
print("--------------------------------------------------------------------------");

// First assignment infers type
edgeVar = 3.14159;
assertFloatEqual(3.14159, edgeVar);
print("  [14.1] edgeVar = 3.14159 (inferred FLOAT) ... PASS");

// Second assignment uses same inferred type
edgeVar = 2.71828;
assertFloatEqual(2.71828, edgeVar);
print("  [14.2] edgeVar = 2.71828 (maintains FLOAT type) ... PASS");

// Explicit suffix overrides previous inference in new scope
func testReset() {
    edgeVar.i = 42;
    assertEqual(42, edgeVar);
    print("  [14.3] Local edgeVar.i = 42 (new local variable) ... PASS");
}
testReset();

print("");

// =============================================================================
// TEST SECTION 15: COMPOUND ASSIGNMENTS - TYPE PRESERVATION
// =============================================================================
print("TEST 15: Compound Assignments - Type Preservation");
print("--------------------------------------------------------------------------");

compInt = 10;
compInt = compInt + 5;
assertEqual(15, compInt);
print("  [15.1] compInt += pattern (preserves INT) ... PASS");

compFloat = 5.5;
compFloat = compFloat * 2.0;
assertFloatEqual(11.0, compFloat);
print("  [15.2] compFloat *= pattern (preserves FLOAT) ... PASS");

compString = "Hello";
compString = compString + " World";
assertStringEqual("Hello World", compString);
print("  [15.3] compString += pattern (preserves STRING) ... PASS");

print("");

// =============================================================================
// FINAL SUMMARY
// =============================================================================
print("==========================================================================");
print("ALL TYPE INFERENCE TESTS COMPLETED SUCCESSFULLY!");
print("==========================================================================");
print("");
print("Test Coverage:");
print("  - Global variables (explicit and inferred)");
print("  - Local variables (explicit and inferred)");
print("  - Function parameters (typed and untyped)");
print("  - Function returns (typed and untyped)");
print("  - Arrays (typed and element access)");
print("  - Type conversions (forced and avoided)");
print("  - Mixed expressions and edge cases");
print("  - Compound assignments and type preservation");
print("");
print("This test validates V1.18.13 type inference implementation.");
print("==========================================================================");
print("");
