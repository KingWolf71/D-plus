// Minimal test for local string array crash
#pragma console on
#pragma appname "LocalStrArrTest"
#pragma consolesize "680x740"
#pragma consoleposition "30,50"
#pragma asmdecimal on

function testLocalStrings() {
    array local_strings.s[3];
    local_strings[0] = "One";
    local_strings[1] = "Two";
    local_strings[2] = "Three";

    print("  Local string array:");
    m = 0;
    while m < 3 {
        print("    local_strings[", m, "] = ", local_strings[m]);
        m = m + 1;
    }

    print("  Asserting local_strings[1] = ", local_strings[1]);
}

testLocalStrings();
print("Done!");
