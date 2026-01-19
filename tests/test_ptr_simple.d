// Simpler test - global pointer
#pragma console on
#pragma ListASM on
#pragma consolesize "680x740"
#pragma consoleposition "30,50"
#pragma asmdecimal on

array data.i[3];
data[0] = 10;
data[1] = 20;
data[2] = 30;

ptr = &data[0];
val1 = ptr\i;     // This should mark ptr as pointer
ptr = ptr + 1;     // This should use PTRADD
val2 = ptr\i;
print("val1=", val1, " val2=", val2);
