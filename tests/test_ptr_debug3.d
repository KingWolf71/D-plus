/* Debug ptr++ issue - minimal */
#pragma console on
#pragma ListASM on
#pragma DumpASM on
#pragma consolesize "680x740"
#pragma consoleposition "30,50"
#pragma asmdecimal on

array numbers.i[3];
numbers[0] = 100;
numbers[1] = 200;
numbers[2] = 300;

func test() {
    /* Get pointer to array as local variable */
    p = &numbers[0];

    print("Before p++:");
    print(p\i);

    p++;  /* Should increment local pointer */

    print("After p++:");
    print(p\i);
}

test();
