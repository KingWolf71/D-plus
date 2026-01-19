// Test just the string array function that fails in test 043
#pragma console on
#pragma appname "StrArrOnly"
#pragma ListASM on
#pragma consolesize "680x740"
#pragma consoleposition "30,50"
#pragma asmdecimal on

// All the functions before testLocalStrings() in test 043

// Global arrays like test 043
array g_ints.i[5];
array g_floats.f[3];
array g_strings.s[4];

// Initialize globals
g_ints[0] = 10;
g_floats[0] = 1.5;
g_strings[0] = "Hello";

// Test 6 equivalent
function testLocalInts() {
    array local_ints.i[3];
    local_ints[0] = 100;
    local_ints[1] = 200;
    local_ints[2] = 300;
    print("local_ints[0] = ", local_ints[0]);
}

// Test 7 equivalent
function testLocalFloats() {
    array local_floats.f[2];
    local_floats[0] = 1.25;
    local_floats[1] = 2.5;
    k = 0;
    while k < 2 {
        print("    local_floats[", k, "] = ", local_floats[k]);
        k = k + 1;
    }
    product = local_floats[0] * local_floats[1];
    print("  Product = ", product);
}

// Test 8 - the one that crashes
function testLocalStrings() {
    array local_strings.s[3];
    local_strings[0] = "One";
    local_strings[1] = "Two";
    local_strings[2] = "Three";
    m = 0;
    while m < 3 {
        print("    local_strings[", m, "] = ", local_strings[m]);
        m = m + 1;
    }
    print("  Asserting local_strings[1] = ", local_strings[1]);
}

print("Calling testLocalInts...");
testLocalInts();
print("Calling testLocalFloats...");
testLocalFloats();
print("Calling testLocalStrings...");
testLocalStrings();
print("All done!");
