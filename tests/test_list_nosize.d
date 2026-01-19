// List test without listSize
#pragma console on
#pragma appname "ListNoSize"
#pragma ListASM on
#pragma consolesize "680x740"
#pragma consoleposition "30,50"
#pragma asmdecimal on

list items;
listAdd(items, 10);
listAdd(items, 20);

print("Done.");
