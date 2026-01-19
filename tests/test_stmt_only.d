// Test listFirst as statement only
#pragma console on
#pragma appname "StmtTest"
#pragma consolesize "680x740"
#pragma consoleposition "30,50"
#pragma asmdecimal on

print("Creating list...");
list items;
listAdd(items, 10);
print("Calling listFirst as statement...");
listFirst(items);
print("Done - sp should be 0");
