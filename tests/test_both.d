// Test both patterns
#pragma console on
#pragma appname "BothTest"
#pragma ListASM on
#pragma consolesize "680x740"
#pragma consoleposition "30,50"
#pragma asmdecimal on

print("Start");
list items;
listAdd(items, 10);
listFirst(items);
result = listFirst(items);
print("result = ", result);
print("Done");
