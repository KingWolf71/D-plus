/* Test String Array Access
   Diagnose why ops[1] returns empty string
*/

#pragma appname "String-Array-Test"
#pragma console on
#pragma consolesize "680x740"
#pragma consoleposition "30,50"
#pragma ftoi "truncate"
#pragma floattolerance 0.0001
#pragma GlobalStack 1024
#pragma FunctionStack 32
#pragma EvalStack 256
#pragma LocalStack 64
#pragma CreateLog off
#pragma DefaultFPS 32
#pragma ThreadKillWait 1800
#pragma version on
#pragma modulename on
#pragma PasteToClipboard on
#pragma ListASM on
#pragma asmdecimal on

// Global string array - same as game 24
array ops.s[4];

// Initialize
ops[0] = "+";
ops[1] = "-";
ops[2] = "*";
ops[3] = "/";

print("=== String Array Test ===");
print("");

// Direct fetch each element
print("Direct access:");
print("  ops[0] = '", ops[0], "'");
print("  ops[1] = '", ops[1], "'");
print("  ops[2] = '", ops[2], "'");
print("  ops[3] = '", ops[3], "'");
print("");

// Loop fetch
print("Loop access:");
i = 0;
while i < 4 {
    print("  ops[", i, "] = '", ops[i], "'");
    i = i + 1;
}
print("");

// Verify each character
print("Character verification:");
print("  ops[0] should be '+': ", ops[0], "");
print("  ops[1] should be '-': ", ops[1], "");
print("  ops[2] should be '*': ", ops[2], "");
print("  ops[3] should be '/': ", ops[3], "");
print("");

// Test in expression
print("Expression test (1 + 2 = ", ops[0], " pattern):");
result = 1 + 2;
print("  1 ", ops[0], " 2 = ", result, "");
print("");

print("=== Test Complete ===");
