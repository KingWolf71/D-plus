/* Test simple pointer increment */
#pragma console on
#pragma ListASM on
#pragma consolesize "680x740"
#pragma consoleposition "30,50"
#pragma asmdecimal on

array data.i[5];
data[0] = 10;
data[1] = 20;
data[2] = 30;
data[3] = 40;
data[4] = 50;

// Get pointer to start of array
ptr = &data[0];

// Dereference to mark as pointer
dummy.i = ptr\i;

print("ptr\\i = ", ptr\i);  // Should be 10

// Increment pointer
ptr++;

print("After ptr++: ptr\i = ", ptr\i);  // Should be 20

// Increment again
ptr++;

print("After ptr++ again: ptr\i = ", ptr\i);  // Should be 30

// Decrement
ptr--;

print("After ptr--: ptr\i = ", ptr\i);  // Should be 20

assertEqual(20, ptr\i);
