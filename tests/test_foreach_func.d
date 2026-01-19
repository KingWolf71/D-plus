// Test: foreach inside function
#pragma console on
#pragma appname "ForeachFuncTest"
#pragma ListASM on
#pragma consolesize "680x740"
#pragma consoleposition "30,50"
#pragma asmdecimal on

print("=== FOREACH FUNC TEST ===");
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

// Test 1: Global foreach
print("Test 1: Global foreach");
foreach items {
    p.Item = listGet(items);
    print("  Got: ", p.name);
}
print("");

// Test 2: Foreach inside function
func testForeach() {
    print("Test 2: Foreach inside function");
    foreach items {
        p.Item = listGet(items);
        print("  Got: ", p.name);
    }
}
testForeach();
print("");

print("=== DONE ===");
