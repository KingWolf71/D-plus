// Test: foreach loop for lists (V1.034.6)
// Tests the new foreach construct with stack-based iterator

#pragma appname "ForEach-Test"
#pragma console on
#pragma consolesize "680x740"
#pragma consoleposition "30,50"
#pragma ListASM on
#pragma DumpASM off
#pragma asmdecimal on

print("=== FOREACH TEST ===");
print("");

// Simple list of integers
list nums;
listAdd(nums, 10);
listAdd(nums, 20);
listAdd(nums, 30);

print("TEST 1: Simple foreach on list");
foreach nums {
    n = listGet(nums);
    print("  Value: ", n);
}
print("");

print("=== FOREACH TEST COMPLETE ===");
