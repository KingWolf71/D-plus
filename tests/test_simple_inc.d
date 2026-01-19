/* Simple increment test */
#pragma console on
#pragma ListASM on
#pragma consolesize "680x740"
#pragma consoleposition "30,50"
#pragma asmdecimal on

// Simple function with i++ and pointer++
func test(ptr, size) {
    i = 0;
    while i < size {
        print("i=", i, " ptr=", ptr\i, "");
        ptr++;
        i++;
    }
}

array numbers.i[3];
numbers[0] = 10;
numbers[1] = 20;
numbers[2] = 30;

test(&numbers[0], 3);
