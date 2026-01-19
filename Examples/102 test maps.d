// Test Maps (V1.026.0)
// Basic map operations (string key -> value)

#pragma appname "Map-Test"
#pragma decimals 3
#pragma console on
#pragma consolesize "680x740"
#pragma consoleposition "30,50"
#pragma ListASM on
#pragma FastPrint on
#pragma ftoi "truncate"
#pragma version on
#pragma modulename on
#pragma DumpASM on
#pragma PasteToClipboard on
#pragma asmdecimal on


print("=== MAP TEST (V1.026.0) ===");
print("");

// TEST 1: Map declaration
print("TEST 1: Map Declaration");
print("-----------------------");

map ages.i;
print("  Integer map 'ages' declared (string -> int)");

map labels.s;
print("  String map 'labels' declared (string -> string)");

map scores.f;
print("  Float map 'scores' declared (string -> float)");

print("  PASS: Map declarations work!");
print("");

// TEST 2: Put/Get Operations
print("TEST 2: Put/Get Operations");
print("-------------------------");
mapPut(ages, "Alice", 30);
mapPut(ages, "Bob", 25);
mapPut(ages, "Charlie", 35);
print("  Added Alice=30, Bob=25, Charlie=35");

age.i = mapGet(ages, "Alice");
print("  Alice's age: ", age);
assertEqual(age, 30);

age = mapGet(ages, "Bob");
print("  Bob's age: ", age);
assertEqual(age, 25);

age = mapGet(ages, "Charlie");
print("  Charlie's age: ", age);
assertEqual(age, 35);

print("  PASS: mapPut and mapGet work!");
print("");

// TEST 3: Map Size
print("TEST 3: Map Size");
print("---------------");
sz.i = mapSize(ages);
print("  Map size: ", sz);
assertEqual(sz, 3);
print("  PASS: mapSize works!");
print("");

// TEST 4: mapContains
print("TEST 4: mapContains");
print("------------------");
found.i = mapContains(ages, "Alice");
print("  Contains 'Alice': ", found);
assertEqual(found, 1);

found = mapContains(ages, "Unknown");
print("  Contains 'Unknown': ", found);
assertEqual(found, 0);

print("  PASS: mapContains works!");
print("");

// TEST 5: Update existing key
print("TEST 5: Update Key");
print("-----------------");
mapPut(ages, "Alice", 31);
age = mapGet(ages, "Alice");
print("  Updated Alice to 31, got: ", age);
assertEqual(age, 31);
print("  PASS: Update works!");
print("");

// TEST 6: mapDelete
print("TEST 6: mapDelete");
print("----------------");
mapDelete(ages, "Bob");
found = mapContains(ages, "Bob");
print("  Deleted Bob, contains: ", found);
assertEqual(found, 0);

sz = mapSize(ages);
print("  Size after delete: ", sz);
assertEqual(sz, 2);
print("  PASS: mapDelete works!");
print("");

// TEST 7: Get non-existent key (returns 0)
print("TEST 7: Non-existent Key");
print("-----------------------");
age = mapGet(ages, "Nobody");
print("  Get 'Nobody': ", age);
assertEqual(age, 0);
print("  PASS: Non-existent returns 0!");
print("");

// TEST 8: Map iteration
print("TEST 8: Map Iteration");
print("--------------------");
print("  Entries:");
mapReset(ages);
while mapNext(ages) {
    k.s = mapKey(ages);
    v.i = mapValue(ages);
    print("    ", k, " = ", v);
}
print("  PASS: Iteration works!");
print("");

// TEST 9: mapClear
print("TEST 9: mapClear");
print("---------------");
mapClear(ages);
sz = mapSize(ages);
print("  Size after clear: ", sz);
assertEqual(sz, 0);
print("  PASS: mapClear works!");
print("");

// TEST 10: String Map Operations
print("TEST 10: String Map");
print("------------------");

mapPut(labels, "btn1", "Submit");
mapPut(labels, "btn2", "Cancel");
mapPut(labels, "btn3", "Help");
print("  Added btn1=Submit, btn2=Cancel, btn3=Help");

lbl.s = mapGet(labels, "btn1");
print("  btn1 label: ", lbl);
assertEqualStr(lbl, "Submit");

lbl = mapGet(labels, "btn2");
print("  btn2 label: ", lbl);
assertEqualStr(lbl, "Cancel");

lbl = mapGet(labels, "btn3");
print("  btn3 label: ", lbl);
assertEqualStr(lbl, "Help");

sz = mapSize(labels);
print("  String map size: ", sz);
assertEqual(sz, 3);

print("  PASS: String map put/get works!");
print("");

// TEST 11: String Map Update and Contains
print("TEST 11: String Map Update");
print("-------------------------");

mapPut(labels, "btn1", "OK");
lbl = mapGet(labels, "btn1");
print("  Updated btn1 to OK, got: ", lbl);
assertEqualStr(lbl, "OK");

found = mapContains(labels, "btn2");
print("  Contains 'btn2': ", found);
assertEqual(found, 1);

found = mapContains(labels, "btn99");
print("  Contains 'btn99': ", found);
assertEqual(found, 0);

print("  PASS: String map update and contains work!");
print("");

// TEST 12: String Map Iteration
print("TEST 12: String Map Iteration");
print("----------------------------");
print("  Labels:");
mapReset(labels);
while mapNext(labels) {
    key.s = mapKey(labels);
    val.s = mapValue(labels);
    print("    ", key, " = ", val);
}
print("  PASS: String map iteration works!");
print("");

// TEST 13: String Map Delete and Clear
print("TEST 13: String Map Delete/Clear");
print("-------------------------------");
mapDelete(labels, "btn2");
found = mapContains(labels, "btn2");
print("  Deleted btn2, contains: ", found);
assertEqual(found, 0);

sz = mapSize(labels);
print("  Size after delete: ", sz);
assertEqual(sz, 2);

mapClear(labels);
sz = mapSize(labels);
print("  Size after clear: ", sz);
assertEqual(sz, 0);

print("  PASS: String map delete/clear works!");
print("");

print("=== ALL MAP TESTS PASSED ===");
