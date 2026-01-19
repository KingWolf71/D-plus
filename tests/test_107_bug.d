// Minimal reproduction of sp=1 bug
#pragma console on
#pragma appname "Test107Bug"
#pragma ListASM on
#pragma consolesize "680x740"
#pragma consoleposition "30,50"
#pragma asmdecimal on

print("=== SP BUG TEST ===");

struct Item {
    name.s;
    value.i;
}

list items.Item;

item.Item = {};
item.name = "Apple";
item.value = 10;
listAdd(items, item);

print("List size: ", listSize(items));

// THE BUG IS HERE:
listFirst(items);
g.Item = listGet(items);
print("Got: ", g.name);

print("=== DONE ===");
