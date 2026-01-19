// Debug test
#pragma console on
#pragma appname "Debug"
#pragma ListASM on
#pragma consolesize "680x740"
#pragma consoleposition "30,50"
#pragma asmdecimal on

print("Starting...");
list items;
listAdd(items, 10);
print("Before assignment...");
result = listFirst(items);
print("After assignment: ", result);
