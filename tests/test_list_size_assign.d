// Test listSize with assignment
#pragma console on
#pragma appname "ListSizeAssign"
#pragma consolesize "680x740"
#pragma consoleposition "30,50"
#pragma asmdecimal on

list items;
listAdd(items, 10);
sz = listSize(items);
print("Size: ", sz);
