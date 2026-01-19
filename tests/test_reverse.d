/* Test reverseArray function */
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

    // Move right pointer to end
    j = 0;
    while j < size - 1 {
        right++;
        j++;
    }

    // Swap elements from ends
    j = 0;
    while j < size / 2 {
        swap(left, right);
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

reverseArray(&numbers[0], 5);

print("Reversed array: ");
i = 0;
while i < 5 {
    print(numbers[i], " ");
    i = i + 1;
}
print("");

// Expected: 40 10 80 20 50
assertEqual(40, numbers[0]);
assertEqual(10, numbers[1]);
assertEqual(80, numbers[2]);
assertEqual(20, numbers[3]);
assertEqual(50, numbers[4]);
