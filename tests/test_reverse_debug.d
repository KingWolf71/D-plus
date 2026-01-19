/* Test reverseArray function with debug output */
#pragma console on
#pragma ListASM on
#pragma consolesize "680x740"
#pragma consoleposition "30,50"
#pragma asmdecimal on

// Helper function for swapping via pointers
func swap(a, b) {
    temp.i = a\i;
    a\i = b\i;
    b\i = temp;
}

// Reverse array using pointers
func reverseArray(ptr, size) {
    // Mark ptr as pointer by dereferencing (type inference requires this)
    dummy.i = ptr\i;

    left = ptr;
    right = ptr;

    print("Initial: left=", left, " right=", right);

    // Move right pointer to end
    j = 0;
    while j < size - 1 {
        print("Loop1: j=", j, " before right++: right=", right);
        right++;
        print("Loop1: j=", j, " after right++: right=", right);
        j++;
    }

    print("After positioning: left=", left, " right=", right);
    print("left\\i=", left\i, " right\\i=", right\i);

    // Swap elements from ends
    j = 0;
    while j < size / 2 {
        print("Loop2: j=", j, " swapping left\\i=", left\i, " right\\i=", right\i);
        swap(left, right);
        print("Loop2: after swap left\\i=", left\i, " right\\i=", right\i);
        left++;
        right--;
        j++;
    }
}

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

print("Calling reverseArray...");
reverseArray(&numbers[0], 5);
print("Returned from reverseArray");

print("After reverse, global i = ", i);

print("Reversed array: ");
i = 0;
while i < 5 {
    print(numbers[i], " ");
    i = i + 1;
}
print("");
