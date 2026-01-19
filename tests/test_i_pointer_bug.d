/* Test to reproduce i being treated as pointer */
#pragma console on
#pragma ListASM on
#pragma consolesize "680x740"
#pragma consoleposition "30,50"
#pragma asmdecimal on

// Function that uses pointers
func testPtr(ptr) {
    left = ptr;   // left gets marked as pointer
    right = ptr;  // right gets marked as pointer

    // This uses global i as a loop counter - should NOT be pointer
    i = 0;
    while i < 3 {
        print("i = ", i, "");
        i++;
    }
}

array numbers.i[3];
numbers[0] = 10;
numbers[1] = 20;
numbers[2] = 30;

// Call function with pointer
testPtr(&numbers[0]);

// Use global i as a loop counter - should NOT be pointer
print("After call:");
i = 0;
while i < 3 {
    print("numbers[", i, "] = ", numbers[i], "");
    i++;
}
