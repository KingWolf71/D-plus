// Test Array Resize (V1.022.64) - Simplified
// Syntax: array data[newSize] - resize existing array

#pragma appname "Array-Resize-Test"
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

print("=== ARRAY RESIZE TEST (V1.022.64) ===");
print("");

// TEST 1: Simple integer array - just check if resize compiles
print("TEST 1: Create and populate small array");
print("---------------------------------------");

array data.i[3];
data[0] = 100;
data[1] = 200;
data[2] = 300;

print("  data[0] = ", data[0], " (expected 100)");
print("  data[1] = ", data[1], " (expected 200)");
print("  data[2] = ", data[2], " (expected 300)");
assertEqual(100, data[0]);
assertEqual(200, data[1]);
assertEqual(300, data[2]);
print("  Initial array works!");
print("");

// TEST 2: Now resize - this should emit ARRAYRESIZE opcode
print("TEST 2: Resize array from 3 to 6");
print("--------------------------------");

array data.i[6];

print("  Array resized to 6 elements");

// Check original elements still there
print("  data[0] = ", data[0], " (expected 100)");
assertEqual(100, data[0]);
print("  data[1] = ", data[1], " (expected 200)");
assertEqual(200, data[1]);
print("  data[2] = ", data[2], " (expected 300)");
assertEqual(300, data[2]);
print("  Original elements preserved!");

// Try to use new elements
print("  Setting data[3] = 400...");
data[3] = 400;
print("  data[3] = ", data[3], " (expected 400)");
assertEqual(400, data[3]);

print("  Setting data[5] = 600...");
data[5] = 600;
print("  data[5] = ", data[5], " (expected 600)");
assertEqual(600, data[5]);

print("");
print("=== ARRAY RESIZE TEST PASSED ===");
