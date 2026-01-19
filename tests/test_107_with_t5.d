// Test 107 with tests 1-5 to find stack leak
#pragma console on
#pragma appname "Test107WithT5"
#pragma ListASM on
#pragma consolesize "680x740"
#pragma consoleposition "30,50"
#pragma asmdecimal on

print("=== TEST 107 WITH TEST 5 ===");
print("");

struct Item {
    name.s;
    value.i;
}

list items.Item;

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

// TEST 3: Local scope with explicit alloc
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

// TEST 4: Local iteration
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

// TEST 5: Pass to function
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

// TEST 6: Foreach with nested calls
func printFirst() {
    listFirst(items);
    p.Item = listGet(items);
    print("    (printFirst got: ", p.name, ")");
}

func testNestedCalls() {
    print("TEST 6: Nested function calls with foreach");
    foreach items {
        p.Item = listGet(items);
        print("  Got: ", p.name, " = ", p.value);
        printFirst();
    }
    print("  Expected: Apple=10, Banana=20, Cherry=30 (with printFirst after each)");
}
testNestedCalls();
print("");

print("=== ALL TESTS COMPLETE ===");
