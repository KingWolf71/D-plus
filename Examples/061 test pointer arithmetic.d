/* Array Pointer Arithmetic Test (V1.20.24+)
   Tests pointer arithmetic with array elements using explicit type syntax
   Demonstrates &nums[index] syntax with ptr\i, ptr\f, ptr\s
*/

#pragma appname "Array-Pointer-Arithmetic-Test"
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

print("=== Array Pointer Arithmetic Tests ===");

// Test 1: Basic array element pointer
print("Test 1: Basic Array Element Pointer");
print("");

array nums.i[5];
nums[0] = 10;
nums[1] = 20;
nums[2] = 30;
nums[3] = 40;
nums[4] = 50;

ptr = &nums[0];          // Get pointer to first element
printf("nums[0] = %d\n", nums[0]);
printf("ptr\\i = %d\n", ptr\i);
assertEqual(10, ptr\i);

ptr\i = 100;            // Modify through pointer
print("After ptr\\i = 100:");
printf("nums[0] = %d\n", nums[0]);
assertEqual(100, nums[0]);

// Test 2: Pointer to middle element
print("\nTest 2: Pointer to Middle Element\n");

ptr = &nums[2];          // Point to nums[2]
printf("ptr\\i (nums[2]) = %d\n", ptr\i);
assertEqual(30, ptr\i);

ptr\i = 333;
print("After ptr\\i = 333:");
printf("nums[2] = %d\n", nums[2]);
assertEqual(333, nums[2]);

// Test 3: Pointer arithmetic - forward traversal
print("\nTest 3: Pointer Arithmetic (Forward)\n");

ptr = &nums[0];
i = 0;

print("Forward traversal using pointer arithmetic:");
while i < 5 {
    printf("ptr\\i = %d\n", ptr\i);
    ptr = ptr + 1;      // Move to next element
    i = i + 1;
}

// Test 4: Pointer arithmetic - backward traversal
print("\nTest 4: Pointer Arithmetic (Backward)\n");

ptr = &nums[4];          // Start at last element
i = 4;

print("Backward traversal using pointer arithmetic:");
while i >= 0 {
    printf("ptr\\i = %d\n", ptr\i);
    ptr--;              // Move to previous element
    i--;
}

// Test 5: Modify array via pointer arithmetic
print("\nTest 5: Modify Array via Pointer Arithmetic\n");

ptr = &nums[0];
i = 0;

while i < 5 {
    ptr\i = (int)(ptr\i * 2);    // Double each value - explicit cast for int array
    ptr = ptr + 1;
    i = i + 1;
}

print("After doubling all values:");
i = 0;
while i < 5 {
    printf("nums[%d] = %d\n", i, nums[i]);
    i = i + 1;
}

// Verify the doubled values
assertEqual(200, nums[0]);   // Was 100, doubled to 200
assertEqual(40, nums[1]);    // Was 20, doubled to 40
assertEqual(666, nums[2]);   // Was 333, doubled to 666
assertEqual(80, nums[3]);    // Was 40, doubled to 80
assertEqual(100, nums[4]);   // Was 50, doubled to 100

// Test 6: Float array pointers
print("\nTest 6: Float Array Pointers\n");

array farr.f[3];
farr[0] = 1.1;
farr[1] = 2.2;
farr[2] = 3.3;

fptr = &farr[0];
i = 0;

print("Float array via pointer:");
while i < 3 {
    printf("fptr\\f = %f\n", fptr\f);
    fptr = fptr + 1;
    i = i + 1;
}

// Verify float values
fptr = &farr[0];
assertFloatEqual(1.1, fptr\f);
fptr = fptr + 1;
assertFloatEqual(2.2, fptr\f);
fptr = fptr + 1;
assertFloatEqual(3.3, fptr\f);

// Test 7: String array pointers
print("\nTest 7: String Array Pointers\n");

array sarr.s[3];
sarr[0] = "First";
sarr[1] = "Second";
sarr[2] = "Third";

sptr = &sarr[0];
i = 0;

print("String array via pointer:");
while i < 3 {
    printf("sptr\\s = %s\n", sptr\s);
    sptr = sptr + 1;
    i = i + 1;
}

// Verify string values
sptr = &sarr[0];
assertStringEqual("First", sptr\s);
sptr = sptr + 1;
assertStringEqual("Second", sptr\s);
sptr = sptr + 1;
assertStringEqual("Third", sptr\s);

// Test 8: Pointer offset calculation
print("\nTest 8: Pointer with Offset\n");

ptr = &nums[1];          // Point to nums[1] (value 40)
printf("ptr\\i (nums[1]) = %d\n", ptr\i);
assertEqual(40, ptr\i);

ptr2 = ptr + 2;         // Point to nums[3] (value 80)
printf("ptr+2 -> \\i (nums[3]) = %d\n", ptr2\i);
assertEqual(80, ptr2\i);

print("");
print("=== Array Pointer Arithmetic Tests Complete ===");
print("  - Integer array pointers: PASSED");
print("  - Float array pointers: PASSED");
print("  - String array pointers: PASSED");
print("  - Pointer arithmetic (forward/backward): PASSED");
print("  - Array modification via pointers: PASSED");
print("  - Pointer offset calculations: PASSED");
print("");
