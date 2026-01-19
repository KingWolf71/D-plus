/* Comprehensive Pointer Test (V1.20.24+)
   Tests all pointer features with explicit type syntax
   Uses: ptr\i, ptr\f, ptr\s for type-safe pointer operations
*/

#pragma appname "Pointer-Comprehensive-Test"
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

// Helper function for swapping via pointers
func swap(a, b) {
    temp.i = a\i;
    a\i = b\i;
    b\i = temp;
}

// Find minimum value in array using pointers
func findMin(ptr, size) {
    min.i = ptr\i;
    p = ptr;
    i = 1;
    p = p + 1;  // Start from second element

    while i < size {
        if p\i < min {
            min = p\i;
        }
        p = p + 1;
        i = i + 1;
    }

    return min;
}

// Reverse array using pointers
func reverseArray(ptr, size) {
    left = ptr;
    right = ptr;

    // Move right pointer to end
    i = 0;
    while i < size - 1 {
        right++;
        i++;
    }

    // Swap elements from ends
    i = 0;
    while i < size / 2 {
        swap(left, right);
        left++;
        right--;
        i++;
    }
}

// Main test code
print("=== Comprehensive Pointer Test ===");

// Test 1: Swap function with pointers
print("Test 1: Swap Function");

x.i = 10;
y.i = 20;

print("Before swap: x = ", x, ", y = ", y, "");

swap(&x, &y);

print("After swap: x = ", x, ", y = ", y, "");
assertEqual(20, x);
assertEqual(10, y);

// Test 2: Array operations with pointers
print("Test 2: Array Operations");

array numbers.i[5];
numbers[0] = 50;
numbers[1] = 20;
numbers[2] = 80;
numbers[3] = 10;
numbers[4] = 40;

print("Original array: ");
i = 0;
while i < 5 {
    print(numbers[i], " ");
    i = i + 1;
}
print("");

min = findMin(&numbers[0], 5);
print("Minimum value: ", min, "");
assertEqual(10, min);

reverseArray(&numbers[0], 5);

print("Reversed array: ");
i = 0;
while i < 5 {
    print(numbers[i], " ");
    i = i + 1;
}
print("");

// Verify reversed array
assertEqual(40, numbers[0]);
assertEqual(10, numbers[1]);
assertEqual(80, numbers[2]);
assertEqual(20, numbers[3]);
assertEqual(50, numbers[4]);

// Test 3: Linked-list-like structure using array of pointers
print("Test 3: Pointer-Based Data Structure");

node1.i = 100;
node2.i = 200;
node3.i = 300;
node4.i = 400;

array *nodes[4];
nodes[0] = &node1;
nodes[1] = &node2;
nodes[2] = &node3;
nodes[3] = &node4;

print("Traversing pointer structure: ");
i = 0;
while i < 4 {
    print(nodes[i]\i);
    if i < 3 {
        print(" -> ");
    }
    i = i + 1;
}
print("");

// Verify original values
assertEqual(100, nodes[0]\i);
assertEqual(200, nodes[1]\i);
assertEqual(300, nodes[2]\i);
assertEqual(400, nodes[3]\i);

// Modify values through pointers
nodes[0]\i = 111;
nodes[2]\i = 333;

print("After modification: ");
print(node1, " -> ", node2, " -> ", node3, " -> ", node4, "");

// Verify modifications
assertEqual(111, node1);
assertEqual(200, node2);
assertEqual(333, node3);
assertEqual(400, node4);

// Test 4: Pointer indirection
print("Test 4: Pointer Indirection");

value.i = 42;
ptr1 = &value;

print("value = ", value, "");
print("ptr1\\i = ", ptr1\i, "");
assertEqual(42, ptr1\i);

ptr1\i = 99;
print("After ptr1\\i = 99, value = ", value, "");
assertEqual(99, value);

print("");
print("=== All Comprehensive Tests Complete ===");
print("  - Swap function: PASSED");
print("  - Array minimum: PASSED");
print("  - Array reversal: PASSED");
print("  - Pointer structures: PASSED");
print("  - Pointer indirection: PASSED");
print("");
print("Pointers are working correctly!");
print("");
