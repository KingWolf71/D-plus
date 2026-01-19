// Debug sp=1 bug with minimal code
#pragma console on
#pragma appname "Test107Debug"
#pragma ListASM on
#pragma DumpASM on
#pragma consolesize "680x740"
#pragma consoleposition "30,50"
#pragma asmdecimal on

struct Item {
    name.s;
    value.i;
}

list items.Item;

item.Item = {};
item.name = "Apple";
item.value = 10;
listAdd(items, item);

print("Calling listFirst+listGet:");
listFirst(items);
g.Item = listGet(items);
print("Result: ", g.name);

print("Done.");
