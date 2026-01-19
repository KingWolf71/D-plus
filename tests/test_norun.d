// No execution - just compile
#pragma appname "NoRun"
#pragma ListASM on
#pragma console on
#pragma consolesize "680x740"
#pragma consoleposition "30,50"
#pragma asmdecimal on

print("Creating list...");
list items;
listAdd(items, 10);
print("Assigning...");
result = listFirst(items);
print("result = ", result);
