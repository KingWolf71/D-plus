// Test 107 - Just test 1 (global scope)
#pragma console on
#pragma appname "Test107-T1"
#pragma consolesize "680x740"
#pragma consoleposition "30,50"
#pragma asmdecimal on

print("=== TEST 1 ONLY ===");
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

print("=== DONE ===");
