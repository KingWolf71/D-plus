// Test listFirst as statement (no assignment)
#pragma console on
#pragma appname "ListFirstStmt"
#pragma consolesize "680x740"
#pragma consoleposition "30,50"
#pragma asmdecimal on

list items;
listAdd(items, 10);
listFirst(items);
print("Done");
