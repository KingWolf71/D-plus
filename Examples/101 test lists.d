// Test Lists (V1.026.0)
// Basic linked list operations

#pragma appname "List-Test"
#pragma decimals 3
#pragma console on
#pragma consolesize "680x740"
#pragma consoleposition "30,50"
#pragma ListASM on
#pragma FastPrint on
#pragma ftoi "truncate"
#pragma version on
#pragma DumpASM on
#pragma PasteToClipboard on
#pragma asmdecimal on

print("=== LIST TEST (V1.026.0) ===");
print("");

// TEST 1: List declaration
print("TEST 1: List Declaration");
print("------------------------");

list numbers.i;
print("  Integer list 'numbers' declared");

list names.s;
print("  String list 'names' declared");

list values.f;
print("  Float list 'values' declared");

print("  PASS: List declarations work!");
print("");

// TEST 2: Add elements
print("TEST 2: Add Elements");
print("-------------------");
listAdd(numbers, 10);
listAdd(numbers, 20);
listAdd(numbers, 30);
print("  Added 10, 20, 30 to numbers list");

n.i = listSize(numbers);
print("  List size: ", n);
assertEqual(n, 3);
print("  PASS: listAdd and listSize work!");
print("");

// TEST 3: Navigation
print("TEST 3: Navigation");
print("-----------------");

success.i = listFirst(numbers);
print("  listFirst returned: ", success);
assertEqual(success, 1);

val.i = listGet(numbers);
print("  First element: ", val);
assertEqual(val, 10);

success = listNext(numbers);
val = listGet(numbers);
print("  Next element: ", val);
assertEqual(val, 20);

success = listNext(numbers);
val = listGet(numbers);
print("  Next element: ", val);
assertEqual(val, 30);

success = listNext(numbers);
print("  Next after last: ", success);
assertEqual(success, 0);

print("  PASS: Navigation works!");
print("");

// TEST 4: listLast and listPrev
print("TEST 4: Last and Prev");
print("--------------------");

success = listLast(numbers);
val = listGet(numbers);
print("  Last element: ", val);
assertEqual(val, 30);

success = listPrev(numbers);
val = listGet(numbers);
print("  Prev element: ", val);
assertEqual(val, 20);

print("  PASS: listLast and listPrev work!");
print("");

// TEST 5: listSet
print("TEST 5: listSet");
print("--------------");

listFirst(numbers);
listSet(numbers, 100);
val = listGet(numbers);
print("  Set first to 100, got: ", val);
assertEqual(val, 100);

print("  PASS: listSet works!");
print("");

// TEST 6: listIndex and listSelect
print("TEST 6: Index and Select");
print("-----------------------");

listFirst(numbers);
idx.i = listIndex(numbers);
print("  Current index: ", idx);
assertEqual(idx, 0);

listSelect(numbers, 2);
val = listGet(numbers);
print("  Selected index 2, value: ", val);
assertEqual(val, 30);

print("  PASS: listIndex and listSelect work!");
print("");

// TEST 7: Iteration pattern
print("TEST 7: Iteration");
print("----------------");
print("  Elements:");
listReset(numbers);
while listNext(numbers) {
    v.i = listGet(numbers);
    print("    ", v);
}
print("  PASS: Iteration works!");
print("");

// TEST 8: String List Operations
print("TEST 8: String List");
print("------------------");

listAdd(names, "Alice");
listAdd(names, "Bob");
listAdd(names, "Charlie");
print("  Added Alice, Bob, Charlie to names list");

ns.i = listSize(names);
print("  String list size: ", ns);
assertEqual(ns, 3);

listFirst(names);
name.s = listGet(names);
print("  First name: ", name);
assertEqualStr(name, "Alice");

listNext(names);
name = listGet(names);
print("  Second name: ", name);
assertEqualStr(name, "Bob");

listLast(names);
name = listGet(names);
print("  Last name: ", name);
assertEqualStr(name, "Charlie");

listFirst(names);
listSet(names, "Alicia");
name = listGet(names);
print("  Set first to Alicia, got: ", name);
assertEqualStr(name, "Alicia");

print("  PASS: String list works!");
print("");

// TEST 9: String List Iteration
print("TEST 9: String List Iteration");
print("----------------------------");
print("  Names:");
listReset(names);
while listNext(names) {
    nm.s = listGet(names);
    print("    ", nm);
}
print("  PASS: String iteration works!");
print("");

print("=== ALL LIST TESTS PASSED ===");
