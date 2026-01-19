// Test listSize only
#pragma console on
#pragma appname "ListSizeOnly"
#pragma ListASM on
#pragma consolesize "680x740"
#pragma consoleposition "30,50"
#pragma asmdecimal on

list items;
listAdd(items, 10);

sz = listSize(items);
print("Size: ", sz);
