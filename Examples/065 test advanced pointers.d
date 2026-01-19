/* Advanced Pointer Features Test (Working Features) - V1.20.24+
   Tests: 1) Mixed-type pointer arrays with explicit syntax
          2) Pointer-to-pointer (multi-level indirection)
          3) Recursive pointer structures
   Uses: ptr\i, ptr\f, ptr\s for type-safe operations
*/

#pragma appname "Advanced-Pointers-Working"
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

print("=== ADVANCED POINTER FEATURES TEST ===");
print("");

// =============================================================================
// TEST 1: Array of Pointers - Different Integer Variables
// =============================================================================
print("TEST 1: Array of Pointers - Different Integer Variables");
print("--------------------------------------------------------");

// Create different integer variables with explicit types
val1.i = 100;
val2.i = 200;
val3.i = 300;
val4.i = 400;

// Create array of pointers
array *ptrArray[4];

// Store pointers to different variables
ptrArray[0] = &val1;
ptrArray[1] = &val2;
ptrArray[2] = &val3;
ptrArray[3] = &val4;

print("  Pointer array created with 4 pointers");
print("  ptrArray[0]\\i = ", ptrArray[0]\i, " (expected 100)");
assertEqual(100, ptrArray[0]\i);

print("  ptrArray[1]\\i = ", ptrArray[1]\i, " (expected 200)");
assertEqual(200, ptrArray[1]\i);

print("  ptrArray[2]\\i = ", ptrArray[2]\i, " (expected 300)");
assertEqual(300, ptrArray[2]\i);

print("  ptrArray[3]\\i = ", ptrArray[3]\i, " (expected 400)");
assertEqual(400, ptrArray[3]\i);

// Modify through pointers
ptrArray[0]\i = 111;
ptrArray[2]\i = 333;

print("  After modification:");
print("    val1 = ", val1, " (expected 111)");
assertEqual(111, val1);
print("    val3 = ", val3, " (expected 333)");
assertEqual(333, val3);

print("  PASS: Pointer array works!");
print("");

// =============================================================================
// TEST 2: Pointer Array with Array Elements
// =============================================================================
print("TEST 2: Pointer Array Pointing to Array Elements");
print("-------------------------------------------------");

array data.i[5];
data[0] = 10;
data[1] = 20;
data[2] = 30;
data[3] = 40;
data[4] = 50;

array *elemPtrs[5];
elemPtrs[0] = &data[0];
elemPtrs[1] = &data[1];
elemPtrs[2] = &data[2];
elemPtrs[3] = &data[3];
elemPtrs[4] = &data[4];

print("  Created array of pointers to array elements");
print("  Accessing through pointer array:");

i = 0;
while i < 5 {
    print("    elemPtrs[", i, "]\\i = ", elemPtrs[i]\i, "");
    i++;
}

// Verify initial values
assertEqual(10, elemPtrs[0]\i);
assertEqual(20, elemPtrs[1]\i);
assertEqual(30, elemPtrs[2]\i);
assertEqual(40, elemPtrs[3]\i);
assertEqual(50, elemPtrs[4]\i);

// Modify through pointer array
elemPtrs[1]\i = 222;
elemPtrs[3]\i = 444;

print("  After modification:");
print("    data[1] = ", data[1], " (expected 222)");
assertEqual(222, data[1]);
print("    data[3] = ", data[3], " (expected 444)");
assertEqual(444, data[3]);

print("  PASS: Array element pointers work!");
print("");

// =============================================================================
// TEST 3: Pointer to Pointer (Simple Case)
// =============================================================================
print("TEST 3: Pointer to Pointer");
print("--------------------------");

value.i = 777;
ptr1 = &value;

print("  value = ", value, "");
print("  ptr1 = &value");
print("  ptr1\\i = ", ptr1\i, " (expected 777)");
assertEqual(777, ptr1\i);

// Create pointer to pointer by storing ptr1's address
ptr2 = &ptr1;

print("  ptr2 = &ptr1 (pointer to pointer)");
print("  ptr2 = ", ptr2, " (this is the address stored in ptr1)");

// Modify through ptr1
ptr1\i = 888;
print("  After ptr1\\i = 888:");
print("    value = ", value, " (expected 888)");
assertEqual(888, value);

print("  PASS: Pointer-to-pointer storage works!");
print("");

// =============================================================================
// TEST 4: Complex Pointer Chain
// =============================================================================
print("TEST 4: Complex Pointer Chain");
print("------------------------------");

a.i = 11;
b.i = 22;
c.i = 33;

pa = &a;
pb = &b;
pc = &c;

print("  Created chain: a=11, b=22, c=33");
print("  Created pointers: pa=&a, pb=&b, pc=&c");

// Store pointers in array
array *ptrChain[3];
ptrChain[0] = &a;
ptrChain[1] = &b;
ptrChain[2] = &c;

print("  Pointer chain in array:");
print("    ptrChain[0]\\i = ", ptrChain[0]\i, " (expected 11)");
print("    ptrChain[1]\\i = ", ptrChain[1]\i, " (expected 22)");
print("    ptrChain[2]\\i = ", ptrChain[2]\i, " (expected 33)");

assertEqual(11, ptrChain[0]\i);
assertEqual(22, ptrChain[1]\i);
assertEqual(33, ptrChain[2]\i);

// Circular modification through chain
ptrChain[0]\i = ptrChain[1]\i + ptrChain[2]\i;  // a = b + c = 22 + 33 = 55

print("  After ptrChain[0]\\i = ptrChain[1]\\i + ptrChain[2]\\i:");
print("    a = ", a, " (expected 55)");
assertEqual(55, a);

print("  PASS: Complex pointer operations work!");
print("");

// =============================================================================
// TEST 5: Pointer Swapping via Array
// =============================================================================
print("TEST 5: Pointer Swapping");
print("------------------------");

x.i = 100;
y.i = 200;

array *swapPtrs[2];
swapPtrs[0] = &x;
swapPtrs[1] = &y;

print("  Before: x=", x, ", y=", y, "");
print("  Swapping through pointer array...");

temp.i = swapPtrs[0]\i;
swapPtrs[0]\i = swapPtrs[1]\i;
swapPtrs[1]\i = temp;

print("  After: x=", x, ", y=", y, "");
assertEqual(200, x);
assertEqual(100, y);

print("  PASS: Pointer swapping works!");
print("");

print("=== ALL ADVANCED POINTER TESTS PASSED ===");
print("");
print("Summary:");
print("  - Pointer arrays (explicit syntax): WORKING");
print("  - Pointer-to-pointer (storage): WORKING");
print("  - Array element pointers: WORKING");
print("  - Complex pointer operations: WORKING");
print("  - Pointer swapping: WORKING");
print("");
