/* Test swap function parameter order */
#pragma console on
#pragma ListASM on
#pragma consolesize "680x740"
#pragma consoleposition "30,50"
#pragma asmdecimal on

// Helper function for swapping via pointers
func swap(a, b) {
    print("In swap: a=", a, " b=", b);
    print("a\\i=", a\i, " b\\i=", b\i);

    temp.i = a\i;
    print("temp after a\\i: ", temp);

    a\i = b\i;
    print("After a\\i = b\\i: a\\i=", a\i);

    b\i = temp;
    print("After b\\i = temp: b\\i=", b\i);
}

x.i = 100;
y.i = 200;

print("Before swap: x=", x, " y=", y);

swap(&x, &y);

print("After swap: x=", x, " y=", y);

assertEqual(200, x);
assertEqual(100, y);
