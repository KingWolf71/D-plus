// Minimal test: struct list with local variable retrieval (V1.031.32)
// Tests the STORE_STRUCT issue with local struct variables

#pragma appname "Struct-List-Minimal"
#pragma console on
#pragma consolesize "680x740"
#pragma consoleposition "30,50"
#pragma ListASM off
#pragma DumpASM off
#pragma PasteToClipboard on
#pragma CreateLog on
#pragma LogName "[default]"
#pragma asmdecimal on

print("=== STRUCT LIST MINIMAL TEST ===");
print("");

// Simple struct
struct Item {
    name.s;
    value.i;
}

// Global list of structs
list items.Item;

// Add some test items at global scope
item.Item = {};
item.name = "Apple";
item.value = 10;
listAdd(items, item);

item.name = "Banana";
item.value = 20;
listAdd(items, item);

item.name = "Cherry";
item.value = 30;
listAdd(items, item);

print("Added 3 items to list");
print("List size: ", listSize(items));
print("");

// TEST 1: Global scope retrieval
print("TEST 1: Global scope retrieval");
listFirst(items);
g.Item = listGet(items);
print("  Got: ", g.name, " = ", g.value);
print("");

// TEST 2: Local scope retrieval (single item)
func testLocalSingle() {
    print("TEST 2: Local scope single retrieval");
    listFirst(items);
    p.Item = listGet(items);
    print("  Got: ", p.name, " = ", p.value);
    print("  Expected: Apple = 10");
}
testLocalSingle();
print("");

// TEST 3: Local scope with explicit alloc (like test 106 pattern)
func testLocalWithAlloc() {
    print("TEST 3: Local scope with explicit alloc");
    listFirst(items);
    p.Item = {};
    p = listGet(items);
    print("  Got: ", p.name, " = ", p.value);
    print("  Expected: Apple = 10");
}
testLocalWithAlloc();
print("");

// TEST 4: Local iteration (like test 106 printAllContacts)
func testLocalIteration() {
    print("TEST 4: Local iteration through list");
    listReset(items);
    while (listNext(items)) {
        p.Item = {};
        p = listGet(items);
        print("  Got: ", p.name, " = ", p.value);
    }
    print("  Expected: Apple=10, Banana=20, Cherry=30");
}
testLocalIteration();
print("");

// TEST 5: Passing local struct string to another function (like test 106 pattern)
func printItem(n.s, v.i) {
    print("  printItem got: ", n, " = ", v);
}

func testPassToFunction() {
    print("TEST 5: Pass local struct strings to function");
    listReset(items);
    while (listNext(items)) {
        p.Item = {};
        p = listGet(items);
        printItem(p.name, p.value);
    }
    print("  Expected: Apple=10, Banana=20, Cherry=30");
}
testPassToFunction();
print("");

// TEST 6: RESTORED with foreach - nested functions work correctly now
// The foreach uses stack-based iterator, so nested functions don't corrupt the outer loop
func printFirst() {
    // This would corrupt the outer loop with while/listNext, but not with foreach
    listFirst(items);
    p.Item = listGet(items);
    print("    (printFirst got: ", p.name, ")");
}

func testNestedCalls() {
    print("TEST 6: Nested function calls with foreach");
    foreach items {
        p.Item = listGet(items);
        print("  Got: ", p.name, " = ", p.value);
        // Call function that also accesses the list - this works with foreach!
        printFirst();
    }
    print("  Expected: Apple=10, Banana=20, Cherry=30 (with printFirst after each)");
}
testNestedCalls();
print("");

print("=== ALL TESTS COMPLETE ===");
