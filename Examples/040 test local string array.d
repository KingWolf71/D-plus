// Minimal test for local string array bug
#pragma appname "Test Local String Array"
#pragma decimals 3
#pragma console on
#pragma consolesize "680x740"
#pragma consoleposition "30,50"
#pragma ListASM on
#pragma FastPrint on
#pragma RunThreaded on
#pragma ftoi "truncate"
#pragma version on
#pragma modulename on
#pragma PasteToClipboard on
#pragma floattolerance 0.0001
#pragma GlobalStack 1024
#pragma FunctionStack 32
#pragma EvalStack 256
#pragma LocalStack 64
#pragma CreateLog off
#pragma DefaultFPS 32
#pragma ThreadKillWait 1800
#pragma asmdecimal on

print("Testing local string array...");

function testLocalStrings() {
    array local_strings.s[3];
    local_strings[0] = "One";
    local_strings[1] = "Two";
    local_strings[2] = "Three";

    printf("  local_strings[0] = %s\n", local_strings[0]);
    printf("  local_strings[1] = %s\n", local_strings[1]);
    printf("  local_strings[2] = %s\n", local_strings[2]);
}

testLocalStrings();
print("Test completed!");
