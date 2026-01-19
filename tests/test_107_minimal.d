// Minimal reproduction of test 107 sp=1 issue
#pragma console on
#pragma appname "Test107Minimal"
#pragma ListASM on
#pragma consolesize "680x740"
#pragma consoleposition "30,50"
#pragma asmdecimal on

print("=== TEST 107 MINIMAL ===");
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

// printFirst - accesses the same list
func printFirst() {
    listFirst(items);
    p.Item = listGet(items);
    print("    (printFirst got: ", p.name, ")");
}

// testNestedCalls - foreach with nested function call
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

print("=== DONE ===");
