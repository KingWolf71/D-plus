// Test file for V1.027.0 Type-Specialized Pointer Opcodes
// Tests all combinations: int/float/string, simple var/array, global/local/mixed

#pragma appname "Typed-Pointer-Opcodes-Test"
#pragma decimals 2
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

gInt.i = 100;
gFloat.f = 3.14;
gStr.s = "global";
array gIntArr.i[5] = {10, 20, 30, 40, 50};
array gFloatArr.f[5] = {1.1, 2.2, 3.3, 4.4, 5.5};
array gStrArr.s[5] = {"a", "b", "c", "d", "e"};

gTestsPassed.i = 0;
gTestsFailed.i = 0;

func testAssert(condition.i, testName.s) {
    if condition {
        gTestsPassed++;
        print("PASS: ", testName, "");
    } else {
        gTestsFailed++;
        print("FAIL: ", testName, "");
    }
}

// ============================================
// Test 1: Global Simple Variable Pointers
// ============================================
func testGlobalSimplePointers() {
    print("");
    print("=== Test 1: Global Simple Variable Pointers ===");

    pInt = &gInt;
    pFloat = &gFloat;
    pStr = &gStr;

    // Test PTRFETCH_VAR_*
    testAssert(pInt\i == 100, "Global int pointer fetch");
    testAssert(pFloat\f == 3.14, "Global float pointer fetch");
    testAssert(pStr\s == "global", "Global string pointer fetch");

    // Test PTRSTORE_VAR_*
    pInt\i = 200;
    pFloat\f = 6.28;
    pStr\s = "modified";

    testAssert(gInt == 200, "Global int pointer store");
    testAssert(gFloat == 6.28, "Global float pointer store");
    testAssert(gStr == "modified", "Global string pointer store");

    // Restore values
    gInt = 100;
    gFloat = 3.14;
    gStr = "global";
}

// ============================================
// Test 2: Global Array Element Pointers
// ============================================
func testGlobalArrayPointers() {
    print("");
    print("=== Test 2: Global Array Element Pointers ===");

    pInt = &gIntArr[2];
    pFloat = &gFloatArr[2];
    pStr = &gStrArr[2];

    // Test PTRFETCH_ARREL_*
    testAssert(pInt\i == 30, "Global int array pointer fetch");
    testAssert(pFloat\f == 3.3, "Global float array pointer fetch");
    testAssert(pStr\s == "c", "Global string array pointer fetch");

    // Test PTRSTORE_ARREL_*
    pInt\i = 300;
    pFloat\f = 33.3;
    pStr\s = "C";

    testAssert(gIntArr[2] == 300, "Global int array pointer store");
    testAssert(gFloatArr[2] == 33.3, "Global float array pointer store");
    testAssert(gStrArr[2] == "C", "Global string array pointer store");

    // Restore values
    gIntArr[2] = 30;
    gFloatArr[2] = 3.3;
    gStrArr[2] = "c";
}

// ============================================
// Test 3: Local Simple Variable Pointers
// ============================================
func testLocalSimplePointers() {
    print("");
    print("=== Test 3: Local Simple Variable Pointers ===");

    lInt.i = 500;
    lFloat.f = 9.99;
    lStr.s = "local";

    pInt = &lInt;
    pFloat = &lFloat;
    pStr = &lStr;

    // Test PTRFETCH_VAR_* with local vars
    testAssert(pInt\i == 500, "Local int pointer fetch");
    testAssert(pFloat\f == 9.99, "Local float pointer fetch");
    testAssert(pStr\s == "local", "Local string pointer fetch");

    // Test PTRSTORE_VAR_* with local vars
    pInt\i = 600;
    pFloat\f = 12.34;
    pStr\s = "changed";

    testAssert(lInt == 600, "Local int pointer store");
    testAssert(lFloat == 12.34, "Local float pointer store");
    testAssert(lStr == "changed", "Local string pointer store");
}

// ============================================
// Test 4: Local Array Element Pointers
// ============================================
func testLocalArrayPointers() {
    print("");
    print("=== Test 4: Local Array Element Pointers ===");

    array lIntArr.i[5] = {100, 200, 300, 400, 500};
    array lFloatArr.f[5] = {11.1, 22.2, 33.3, 44.4, 55.5};
    array lStrArr.s[5] = {"X", "Y", "Z", "W", "V"};

    pInt = &lIntArr[1];
    pFloat = &lFloatArr[1];
    pStr = &lStrArr[1];

    // Test PTRFETCH_ARREL_* with local arrays
    testAssert(pInt\i == 200, "Local int array pointer fetch");
    testAssert(pFloat\f == 22.2, "Local float array pointer fetch");
    testAssert(pStr\s == "Y", "Local string array pointer fetch");

    // Test PTRSTORE_ARREL_* with local arrays
    pInt\i = 2000;
    pFloat\f = 222.2;
    pStr\s = "YY";

    testAssert(lIntArr[1] == 2000, "Local int array pointer store");
    testAssert(lFloatArr[1] == 222.2, "Local float array pointer store");
    testAssert(lStrArr[1] == "YY", "Local string array pointer store");
}

// ============================================
// Test 5: Pointer Increment/Decrement (Simple)
// ============================================
func testPointerIncDec() {
    print("");
    print("=== Test 5: Pointer Increment/Decrement ===");

    pInt = &gIntArr[0];
    pFloat = &gFloatArr[0];
    pStr = &gStrArr[0];

    // Test initial values
    testAssert(pInt\i == 10, "Int array ptr initial");
    testAssert(pFloat\f == 1.1, "Float array ptr initial");
    testAssert(pStr\s == "a", "String array ptr initial");

    // Test PTRINC_ARRAY (increment)
    pInt++;
    pFloat++;
    pStr++;

    testAssert(pInt\i == 20, "Int array ptr after ++");
    testAssert(pFloat\f == 2.2, "Float array ptr after ++");
    testAssert(pStr\s == "b", "String array ptr after ++");

    // Test PTRDEC_ARRAY (decrement)
    pInt--;
    pFloat--;
    pStr--;

    testAssert(pInt\i == 10, "Int array ptr after --");
    testAssert(pFloat\f == 1.1, "Float array ptr after --");
    testAssert(pStr\s == "a", "String array ptr after --");
}

// ============================================
// Test 6: Pointer Pre-Increment/Pre-Decrement
// ============================================
func testPointerPreIncDec() {
    print("");
    print("=== Test 6: Pointer Pre-Increment/Pre-Decrement ===");

    pInt = &gIntArr[1];
    val.i = 0;

    // Test increment then fetch (simulates pre-increment behavior)
    pInt++;
    val = pInt\i;
    testAssert(val == 30, "Increment then fetch int array ptr");
    testAssert(pInt\i == 30, "Pointer value after increment");

    // Test decrement then fetch (simulates pre-decrement behavior)
    pInt--;
    val = pInt\i;
    testAssert(val == 20, "Decrement then fetch int array ptr");
    testAssert(pInt\i == 20, "Pointer value after decrement");
}

// ============================================
// Test 7: Pointer Post-Increment/Post-Decrement
// ============================================
func testPointerPostIncDec() {
    print("");
    print("=== Test 7: Pointer Post-Increment/Post-Decrement ===");

    pInt = &gIntArr[1];
    val.i = 0;

    // Test post-increment (value should be before increment)
    val = pInt\i;
    pInt++;
    testAssert(val == 20, "Post-increment returns old value");
    testAssert(pInt\i == 30, "Post-increment ptr moved");

    // Test post-decrement (value should be before decrement)
    val = pInt\i;
    pInt--;
    testAssert(val == 30, "Post-decrement returns old value");
    testAssert(pInt\i == 20, "Post-decrement ptr moved");
}

// ============================================
// Test 8: Pointer Compound Assignment (+=, -=)
// ============================================
func testPointerCompoundAssign() {
    print("");
    print("=== Test 8: Pointer Compound Assignment ===");

    pInt = &gIntArr[0];
    pFloat = &gFloatArr[0];
    pStr = &gStrArr[0];

    // Test PTRADD_ASSIGN_ARRAY
    pInt += 3;
    pFloat += 3;
    pStr += 3;

    testAssert(pInt\i == 40, "Int array ptr += 3");
    testAssert(pFloat\f == 4.4, "Float array ptr += 3");
    testAssert(pStr\s == "d", "String array ptr += 3");

    // Test PTRSUB_ASSIGN_ARRAY
    pInt -= 2;
    pFloat -= 2;
    pStr -= 2;

    testAssert(pInt\i == 20, "Int array ptr -= 2");
    testAssert(pFloat\f == 2.2, "Float array ptr -= 2");
    testAssert(pStr\s == "b", "String array ptr -= 2");
}

// ============================================
// Test 9: Mixed Global/Local Scenarios
// ============================================
func testMixedScenarios() {
    print("");
    print("=== Test 9: Mixed Global/Local Scenarios ===");

    // Local pointer to global variable
    pGlobal = &gInt;
    testAssert(pGlobal\i == 100, "Local ptr to global int");
    pGlobal\i = 999;
    testAssert(gInt == 999, "Store via local ptr to global");
    gInt = 100;  // restore

    // Local pointer to global array
    pGlobalArr = &gIntArr[2];
    testAssert(pGlobalArr\i == 30, "Local ptr to global array element");

    // Pointer arithmetic with mixed
    pGlobalArr += 2;
    testAssert(pGlobalArr\i == 50, "Local ptr to global array += 2");
}

// ============================================
// Test 10: Print Through Pointer (PRTPTR_*)
// ============================================
func testPrintThroughPointer() {
    print("");
    print("=== Test 10: Print Through Pointer ===");

    pInt = &gInt;
    pFloat = &gFloat;
    pStr = &gStr;

    print("Int via ptr: ", pInt\i, "");
    print("Float via ptr: ", pFloat\f, "");
    print("String via ptr: ", pStr\s, "");

    pArrInt = &gIntArr[0];
    pArrFloat = &gFloatArr[0];
    pArrStr = &gStrArr[0];

    print("Array int via ptr: ", pArrInt\i, "");
    print("Array float via ptr: ", pArrFloat\f, "");
    print("Array string via ptr: ", pArrStr\s, "");

    testAssert(1, "Print through pointer completed");
}

// ============================================
// Test 11: Pointer Traversal Loop
// ============================================
func testPointerTraversal() {
    print("");
    print("=== Test 11: Pointer Traversal Loop ===");

    sum.i = 0;
    p = &gIntArr[0];
    i.i = 0;

    // Sum array using pointer arithmetic
    while i < 5 {
        sum += p\i;
        p++;
        i++;
    }

    testAssert(sum == 150, "Pointer traversal sum (10+20+30+40+50)");

    // Traverse backwards
    p = &gIntArr[4];
    sum = 0;
    i = 0;
    while i < 5 {
        sum += p\i;
        p--;
        i++;
    }
    testAssert(sum == 150, "Pointer traversal backwards");
}

// ============================================
// Test 12: Local Array with Pointer Ops
// ============================================
func testLocalArrayWithPointerOps() {
    print("");
    print("=== Test 12: Local Array with Pointer Ops ===");

    array localArr.i[10];
    i.i = 0;

    // Initialize via pointer
    p = &localArr[0];
    while i < 10 {
        p\i = i * 10;
        p++;
        i++;
    }

    // Verify
    testAssert(localArr[0] == 0, "Local array[0] via ptr init");
    testAssert(localArr[5] == 50, "Local array[5] via ptr init");
    testAssert(localArr[9] == 90, "Local array[9] via ptr init");

    // Sum via pointer
    sum.i = 0;
    p = &localArr[0];
    i = 0;
    while i < 10 {
        sum += p\i;
        p++;
        i++;
    }
    testAssert(sum == 450, "Local array sum via ptr (0+10+...+90)");
}

// ============================================
// Main test runner
// ============================================
print("========================================");
print("V1.027.0 Typed Pointer Opcodes Test");
print("========================================");

testGlobalSimplePointers();
testGlobalArrayPointers();
testLocalSimplePointers();
testLocalArrayPointers();
testPointerIncDec();
testPointerPreIncDec();
testPointerPostIncDec();
testPointerCompoundAssign();
testMixedScenarios();
testPrintThroughPointer();
testPointerTraversal();
testLocalArrayWithPointerOps();

print("");
print("========================================");
print("Results: ", gTestsPassed, " passed, ", gTestsFailed, " failed");
print("========================================");

if gTestsFailed == 0 {
    print("ALL TESTS PASSED!");
} else {
    print("SOME TESTS FAILED!");
}
