// Test simple list operations without listSize
#pragma console on
#pragma appname "SimpleList"
#pragma consolesize "680x740"
#pragma consoleposition "30,50"
#pragma asmdecimal on

print("=== SIMPLE LIST TEST ===");

struct Item {
    name.s;
    value.i;
}

list items.Item;

item.Item = {};
item.name = "Apple";
item.value = 10;
listAdd(items, item);

print("Added item");

// The bug: listFirst as statement leaves return value on stack
listFirst(items);
g.Item = listGet(items);
print("Got: ", g.name);

print("=== DONE ===");
