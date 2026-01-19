/* Float Function Test
   Diagnose float parameter passing and return values
*/

#pragma appname "Float-Function-Test"
#pragma decimals 4
#pragma console on
#pragma consolesize "680x740"
#pragma consoleposition "30,50"
#pragma ftoi "truncate"
#pragma floattolerance 0.0001
#pragma GlobalStack 1024
#pragma FunctionStack 32
#pragma EvalStack 256
#pragma LocalStack 64
#pragma CreateLog off
#pragma DefaultFPS 32
#pragma ThreadKillWait 1800
#pragma version on
#pragma modulename on
#pragma PasteToClipboard on
#pragma ListASM on
#pragma asmdecimal on

// Test 1: Simple float parameter - func.f declares float return type
func testFloatParam.f(x.f) {
    print("  Inside testFloatParam: x = ", x, "");
    return x;
}

// Test 2: Two float parameters
func addFloats.f(a.f, b.f) {
    result.f = a + b;
    print("  Inside addFloats: a=", a, " b=", b, " result=", result, "");
    return result;
}

// Test 3: Float division
func divideFloats.f(a.f, b.f) {
    result.f = a / b;
    print("  Inside divideFloats: a=", a, " b=", b, " result=", result, "");
    return result;
}

// Test 4: Mixed int and float params
func mixedParams.f(x, y.f) {
    print("  Inside mixedParams: x(int)=", x, " y(float)=", y, "");
    result.f = x + y;
    return result;
}

// Test 5: Float comparison
func isEqual24(val.f) {
    print("  Inside isEqual24: val=", val, "");
    if val == 24.0 {
        print("    val == 24.0 is TRUE");
        return 1;
    }
    print("    val == 24.0 is FALSE");
    return 0;
}

// Test 6: Float comparison with tolerance
func isNear24(val.f) {
    diff.f = val - 24.0;
    print("  Inside isNear24: val=", val, " diff=", diff, "");
    if diff < 0.0 {
        diff = 0.0 - diff;
        print("    After abs: diff=", diff, "");
    }
    if diff < 0.01 {
        print("    diff < 0.01 is TRUE");
        return 1;
    }
    print("    diff < 0.01 is FALSE");
    return 0;
}

print("=== Float Function Diagnostics ===");
print("");

// Test 1: Pass literal float
print("Test 1: Pass float literal 3.14");
r1.f = testFloatParam(3.14);
print("  Returned: ", r1, "");
print("");

// Test 2: Pass float variable
print("Test 2: Pass float variable");
myFloat.f = 2.5;
print("  myFloat = ", myFloat, "");
r2.f = testFloatParam(myFloat);
print("  Returned: ", r2, "");
print("");

// Test 3: Pass integer converted to float
print("Test 3: Pass integer as float param");
myInt = 7;
print("  myInt = ", myInt, "");
r3.f = testFloatParam(myInt);
print("  Returned: ", r3, "");
print("");

// Test 4: Add two floats
print("Test 4: Add two floats (10.5 + 3.5)");
r4.f = addFloats(10.5, 3.5);
print("  Returned: ", r4, " (expected 14.0)");
print("");

// Test 5: Division
print("Test 5: Division (10.0 / 4.0)");
r5.f = divideFloats(10.0, 4.0);
print("  Returned: ", r5, " (expected 2.5)");
print("");

// Test 6: Division that should give 24
print("Test 6: Division (48.0 / 2.0)");
r6.f = divideFloats(48.0, 2.0);
print("  Returned: ", r6, " (expected 24.0)");
print("");

// Test 7: Check if result equals 24
print("Test 7: Check if 24.0 == 24");
check1 = isEqual24(24.0);
print("  isEqual24(24.0) returned: ", check1, "");
print("");

// Test 8: Check with calculated value
print("Test 8: Check calculated 24");
calc.f = 6.0 * 4.0;
print("  calc = 6.0 * 4.0 = ", calc, "");
check2 = isEqual24(calc);
print("  isEqual24(calc) returned: ", check2, "");
print("");

// Test 9: isNear24 with exact value
print("Test 9: isNear24 with 24.0");
check3 = isNear24(24.0);
print("  isNear24(24.0) returned: ", check3, "");
print("");

// Test 10: isNear24 with calculated value
print("Test 10: isNear24 with calculated value");
calc2.f = 8.0 * 3.0;
print("  calc2 = 8.0 * 3.0 = ", calc2, "");
check4 = isNear24(calc2);
print("  isNear24(calc2) returned: ", check4, "");
print("");

// Test 11: Integer to float in function
print("Test 11: Integer array element to float");
array nums[4];
nums[0] = 1;
nums[1] = 2;
nums[2] = 3;
nums[3] = 4;
print("  nums = [", nums[0], ", ", nums[1], ", ", nums[2], ", ", nums[3], "]");
product.f = nums[0] * nums[1] * nums[2] * nums[3];
print("  product = ", product, " (expected 24.0)");
check5 = isNear24(product);
print("  isNear24(product) returned: ", check5, "");
print("");

// Test 12: Chain of operations like Game 24
print("Test 12: Chain ((1 + 2) + 3) * 4");
step1.f = 1.0 + 2.0;
print("  step1 = 1.0 + 2.0 = ", step1, "");
step2.f = step1 + 3.0;
print("  step2 = step1 + 3.0 = ", step2, "");
step3.f = step2 * 4.0;
print("  step3 = step2 * 4.0 = ", step3, "");
check6 = isNear24(step3);
print("  isNear24(step3) returned: ", check6, "");
print("");

print("=== Diagnostics Complete ===");
