// Minimal test - assignment only
#pragma console on
#pragma appname "Min"
#pragma ListASM on
#pragma consolesize "680x740"
#pragma consoleposition "30,50"
#pragma asmdecimal on

list items;
listAdd(items, 10);
result = listFirst(items);
print(result);
