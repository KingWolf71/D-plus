// Test listFirst as assignment only
#pragma console on
#pragma appname "AssignTest"
#pragma consolesize "680x740"
#pragma consoleposition "30,50"
#pragma asmdecimal on

print("Creating list...");
list items;
listAdd(items, 10);
print("Assigning result = listFirst(items)...");
result = listFirst(items);
print("result = ", result);
print("Done - sp should be 0");
