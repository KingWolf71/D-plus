/* Array of Pointers Test (V1.20.24+)
   Tests arrays that contain pointers with explicit type syntax
   Uses: ptrs[i]\i, ptrs[i]\f, ptrs[i]\s
*/

#pragma appname "Array-of-Pointers-Test"
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

print("=== Array of Pointers Test ===");

// Test 1: Array of integer pointers
print("Test 1: Array of Integer Pointers");

a.i = 10;
b.i = 20;
c.i = 30;
d.i = 40;

array *ptrs[4];       // Array of 4 integer pointers

ptrs[0] = &a;
ptrs[1] = &b;
ptrs[2] = &c;
ptrs[3] = &d;

print("Values via pointer array:");
i = 0;
while i < 4 {
    printf("ptrs[%d]\\i = %d\n", i, ptrs[i]\i);
    i = i + 1;
}

// Verify values
assertEqual(10, ptrs[0]\i);
assertEqual(20, ptrs[1]\i);
assertEqual(30, ptrs[2]\i);
assertEqual(40, ptrs[3]\i);

// Test 2: Modify through pointer array
print("Test 2: Modify Through Pointer Array");

ptrs[0]\i = 100;
ptrs[1]\i = 200;
ptrs[2]\i = 300;
ptrs[3]\i = 400;

print("After modification:");
printf("a = %d, b = %d, c = %d, d = %d\n", a, b, c, d);

assertEqual(100, a);
assertEqual(200, b);
assertEqual(300, c);
assertEqual(400, d);

// Test 3: Reorder pointers
print("Test 3: Pointer Array Reordering");

// Swap pointers - temp needs to hold pointer values
// First assign from address to make temp a pointer type
temp = &a;        // temp is now a pointer
temp = ptrs[0];   // Copy pointer from array
ptrs[0] = ptrs[3];
ptrs[3] = temp;

temp = ptrs[1];   // Reuse temp
ptrs[1] = ptrs[2];
ptrs[2] = temp;

print("After swapping pointers:");
i = 0;
while i < 4 {
    printf("ptrs[%d]\\i = %d\n", i, ptrs[i]\i);
    i = i + 1;
}

// After swap: ptrs[0] now points to d, ptrs[1] to c, ptrs[2] to b, ptrs[3] to a
assertEqual(400, ptrs[0]\i);  // d
assertEqual(300, ptrs[1]\i);  // c
assertEqual(200, ptrs[2]\i);  // b
assertEqual(100, ptrs[3]\i);  // a

// Test 4: Array of string pointers
print("Test 4: Array of String Pointers");

s1.s = "Hello";
s2.s = "World";
s3.s = "Pointer";

array *strs[3];
strs[0] = &s1;
strs[1] = &s2;
strs[2] = &s3;

i = -1;
while( ++i < 3) {
    print(strs[i]\s, " ");
}
print("");

// Verify string values
assertStringEqual("Hello", strs[0]\s);
assertStringEqual("World", strs[1]\s);
assertStringEqual("Pointer", strs[2]\s);

// Modify through string pointer array
strs[1]\s = "Universe";

print("After strs[1]\\s = 'Universe':");
printf("s1 = %s, s2 = %s, s3 = %s\n", s1, s2, s3);

assertStringEqual("Hello", s1);
assertStringEqual("Universe", s2);
assertStringEqual("Pointer", s3);

// Test 5: Pointers to array elements
print("Test 5: Pointers to Array Elements");

array values.i[5];
values[0] = 5;
values[1] = 10;
values[2] = 15;
values[3] = 20;
values[4] = 25;

// Create array of pointers to array elements
array *elemPtrs[3];
elemPtrs[0] = &values[1];   // Point to values[1]
elemPtrs[1] = &values[2];   // Point to values[2]
elemPtrs[2] = &values[3];   // Point to values[3]

print("Array element pointers:");
i = -1;
while( ++i < 3 ){
    printf("elemPtrs[%d]\\i = %d\n", i, elemPtrs[i]\i);
}

// Verify original values
assertEqual(10, elemPtrs[0]\i);
assertEqual(15, elemPtrs[1]\i);
assertEqual(20, elemPtrs[2]\i);

// Modify array elements through pointer array
elemPtrs[0]\i = 111;
elemPtrs[1]\i = 222;
elemPtrs[2]\i = 333;

print("After modification via pointers:");
i = -1;
while( ++i < 5) {
    printf("values[%d] = %d\n", i, values[i]);
}

// Verify modified values
assertEqual(5, values[0]);    // Unchanged
assertEqual(111, values[1]);  // Modified via elemPtrs[0]
assertEqual(222, values[2]);  // Modified via elemPtrs[1]
assertEqual(333, values[3]);  // Modified via elemPtrs[2]
assertEqual(25, values[4]);   // Unchanged

putc('\n');
print("=== Array of Pointers Tests Complete ===");
print("  - Integer pointer arrays: PASSED");
print("  - String pointer arrays: PASSED");
print("  - Pointer reordering: PASSED");
print("  - Array element pointers: PASSED");
print("");
