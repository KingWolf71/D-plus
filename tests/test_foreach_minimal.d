// Minimal foreach stack test
#pragma console on
#pragma appname "ForeachStackTest"
#pragma consolesize "680x740"
#pragma consoleposition "30,50"
#pragma asmdecimal on

print("=== FOREACH STACK TEST ===");

list items.i;
listAdd(items, 1);
listAdd(items, 2);
listAdd(items, 3);

// Test 1: Global foreach
print("Test 1: Global foreach");
foreach items {
    x.i = listGetInt(items);
    print("  Got: ", x);
}
print("After global foreach");

// Test 2: Function foreach
func testForeach() {
    print("Test 2: Function foreach");
    foreach items {
        y.i = listGetInt(items);
        print("  Got: ", y);
    }
    print("After function foreach");
}
testForeach();

print("=== DONE ===");
