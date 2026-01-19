// Test listSize
#pragma console on
#pragma appname "ListSizeTest"
#pragma ListASM on
#pragma consolesize "680x740"
#pragma consoleposition "30,50"
#pragma asmdecimal on

list items;
listAdd(items, 10);
listAdd(items, 20);

x = listSize(items);
print("Size: ", x);

print("Done.");
