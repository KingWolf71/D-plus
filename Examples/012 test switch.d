// Test file for switch statement
// V1.024.5

#pragma console on
#pragma consolesize "680x740"
#pragma decimals 3
#pragma consolesize "680x740"
#pragma consoleposition "30,50"
#pragma ListASM on
#pragma FastPrint on
#pragma RunThreaded on
#pragma ftoi "truncate"
#pragma version on
#pragma modulename on
#pragma PasteToClipboard on
#pragma floattolerance 0.001
#pragma GlobalStack 1024
#pragma FunctionStack 32
#pragma EvalStack 256
#pragma LocalStack 64
#pragma CreateLog off
#pragma DefaultFPS 32
#pragma ThreadKillWait 1800
#pragma DumpASM on
#pragma asmdecimal on

print("=== Switch Tests ===");
print("");

// Basic switch
print("Test 1: Basic switch");
x.i = 2;
switch (x) {
    case 1:
        print("One");
        break;
    case 2:
        print("Two");
        break;
    case 3:
        print("Three");
        break;
    default:
        print("Other");
}
print("");

// Switch with fallthrough
print("Test 2: Switch with fallthrough");
x = 1;
switch (x) {
    case 1:
        print("One ");
    case 2:
        print("Two ");
    case 3:
        print("Three");
        break;
    default:
        print("Other");
}
print("");

// Switch in loop
print("Test 3: Switch in loop");
for (i.i = 0; i < 5; i++) {
    switch (i) {
        case 0:
            print("Zero ");
            break;
        case 1:
            print("One ");
            break;
        case 2:
            print("Two ");
            break;
        default:
            print("Many ");
    }
}
print("");

// Default case
print("Test 4: Default case");
x = 99;
switch (x) {
    case 1:
        print("One");
        break;
    default:
        print("Default hit!");
}
print("");

// Switch with expression
print("Test 5: Switch with expression");
a.i = 3;
b.i = 2;
switch (a + b) {
    case 4:
        print("Four");
        break;
    case 5:
        print("Five");
        break;
    case 6:
        print("Six");
        break;
}
print("");

print("=== All switch tests complete ===");
