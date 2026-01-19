// Test: foreach with nested function that accesses the same list
#pragma console on
#pragma appname "ForeachNested2Test"
#pragma ListASM on
#pragma consolesize "680x740"
#pragma consoleposition "30,50"
#pragma asmdecimal on

print("=== FOREACH NESTED2 TEST ===");
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

print("List size: ", listSize(items));
print("");

// Function that accesses the same list
func printFirst() {
    listFirst(items);
    p.Item = listGet(items);
    print("    (printFirst got: ", p.name, ")");
}

// Test: Foreach with nested function that accesses list
func testNestedAccess() {
    print("Test: Foreach with nested list access");
    foreach items {
        p.Item = listGet(items);
        print("  Got: ", p.name);
        printFirst();  // <-- accesses same list
    }
}
testNestedAccess();
print("");

print("=== DONE ===");
