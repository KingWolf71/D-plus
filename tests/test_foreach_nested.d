// Test: foreach with nested function call
#pragma console on
#pragma appname "ForeachNestedTest"
#pragma ListASM on
#pragma consolesize "680x740"
#pragma consoleposition "30,50"
#pragma asmdecimal on

print("=== FOREACH NESTED TEST ===");
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

// Helper function called from inside foreach
func helper() {
    print("  (helper called)");
}

// Test: Foreach with nested function call
func testNestedCall() {
    print("Test: Foreach with nested call");
    foreach items {
        p.Item = listGet(items);
        print("  Got: ", p.name);
        helper();  // <-- calling function inside foreach
    }
}
testNestedCall();
print("");

print("=== DONE ===");
