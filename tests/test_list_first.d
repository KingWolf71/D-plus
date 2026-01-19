// Test listFirst with assignment
#pragma console on
#pragma appname "ListFirst"
#pragma consolesize "680x740"
#pragma consoleposition "30,50"
#pragma asmdecimal on

list items;
listAdd(items, 10);
result = listFirst(items);
print("First: ", result);
