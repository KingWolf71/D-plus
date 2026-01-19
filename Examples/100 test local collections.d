// Test Local Collections (V1.026.8)
// Tests local list and map variables inside functions

#pragma appname "Local-Collections-Test"
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

print("=== LOCAL COLLECTIONS TEST (V1.026.8) ===");
print("");

// ============================================
// TEST 1: Local Integer List
// ============================================
func testLocalIntList() {
    print("TEST 1: Local Integer List");
    print("--------------------------");

    list nums.i;

    listAdd(nums, 10);
    listAdd(nums, 20);
    listAdd(nums, 30);
    print("  Added 10, 20, 30");

    sz.i = listSize(nums);
    print("  Size: ", sz);
    assertEqual(sz, 3);

    listFirst(nums);
    v.i = listGet(nums);
    print("  First: ", v);
    assertEqual(v, 10);

    listNext(nums);
    v = listGet(nums);
    print("  Second: ", v);
    assertEqual(v, 20);

    listLast(nums);
    v = listGet(nums);
    print("  Last: ", v);
    assertEqual(v, 30);

    // Modify element
    listFirst(nums);
    listSet(nums, 100);
    v = listGet(nums);
    print("  Set first to 100, got: ", v);
    assertEqual(v, 100);

    // Iterate
    print("  Iteration:");
    listReset(nums);
    while listNext(nums) {
        val.i = listGet(nums);
        print("    ", val);
    }

    print("  PASS: Local int list works!");
    print("");
}

// ============================================
// TEST 2: Local String List
// ============================================
func testLocalStrList() {
    print("TEST 2: Local String List");
    print("-------------------------");

    list items.s;

    listAdd(items, "Apple");
    listAdd(items, "Banana");
    listAdd(items, "Cherry");
    print("  Added Apple, Banana, Cherry");

    sz.i = listSize(items);
    print("  Size: ", sz);
    assertEqual(sz, 3);

    listFirst(items);
    s.s = listGet(items);
    print("  First: ", s);
    assertEqualStr(s, "Apple");

    listLast(items);
    s = listGet(items);
    print("  Last: ", s);
    assertEqualStr(s, "Cherry");

    // Modify
    listFirst(items);
    listSet(items, "Apricot");
    s = listGet(items);
    print("  Set first to Apricot, got: ", s);
    assertEqualStr(s, "Apricot");

    // Iterate
    print("  Iteration:");
    listReset(items);
    while listNext(items) {
        item.s = listGet(items);
        print("    ", item);
    }

    print("  PASS: Local string list works!");
    print("");
}

// ============================================
// TEST 3: Local Float List
// ============================================
func testLocalFloatList() {
    print("TEST 3: Local Float List");
    print("------------------------");

    list prices.f;

    listAdd(prices, 1.5);
    listAdd(prices, 2.75);
    listAdd(prices, 3.99);
    print("  Added 1.5, 2.75, 3.99");

    sz.i = listSize(prices);
    print("  Size: ", sz);
    assertEqual(sz, 3);

    listFirst(prices);
    p.f = listGet(prices);
    print("  First: ", p);

    listLast(prices);
    p = listGet(prices);
    print("  Last: ", p);

    print("  PASS: Local float list works!");
    print("");
}

// ============================================
// TEST 4: Local Integer Map
// ============================================
func testLocalIntMap() {
    print("TEST 4: Local Integer Map");
    print("-------------------------");

    map scores.i;

    mapPut(scores, "Alice", 95);
    mapPut(scores, "Bob", 87);
    mapPut(scores, "Charlie", 92);
    print("  Added Alice=95, Bob=87, Charlie=92");

    sz.i = mapSize(scores);
    print("  Size: ", sz);
    assertEqual(sz, 3);

    sc.i = mapGet(scores, "Alice");
    print("  Alice's score: ", sc);
    assertEqual(sc, 95);

    sc = mapGet(scores, "Bob");
    print("  Bob's score: ", sc);
    assertEqual(sc, 87);

    // Contains check
    found.i = mapContains(scores, "Charlie");
    print("  Contains Charlie: ", found);
    assertEqual(found, 1);

    found = mapContains(scores, "David");
    print("  Contains David: ", found);
    assertEqual(found, 0);

    // Update
    mapPut(scores, "Alice", 100);
    sc = mapGet(scores, "Alice");
    print("  Updated Alice to 100, got: ", sc);
    assertEqual(sc, 100);

    // Delete
    mapDelete(scores, "Bob");
    found = mapContains(scores, "Bob");
    print("  Deleted Bob, contains: ", found);
    assertEqual(found, 0);

    sz = mapSize(scores);
    print("  Size after delete: ", sz);
    assertEqual(sz, 2);

    // Iterate
    print("  Iteration:");
    mapReset(scores);
    while mapNext(scores) {
        k.s = mapKey(scores);
        v.i = mapValue(scores);
        print("    ", k, " = ", v);
    }

    print("  PASS: Local int map works!");
    print("");
}

// ============================================
// TEST 5: Local String Map
// ============================================
func testLocalStrMap() {
    print("TEST 5: Local String Map");
    print("------------------------");

    map labels.s;

    mapPut(labels, "ok", "OK");
    mapPut(labels, "cancel", "Cancel");
    mapPut(labels, "help", "Help");
    print("  Added ok=OK, cancel=Cancel, help=Help");

    sz.i = mapSize(labels);
    print("  Size: ", sz);
    assertEqual(sz, 3);

    lbl.s = mapGet(labels, "ok");
    print("  'ok' label: ", lbl);
    assertEqualStr(lbl, "OK");

    lbl = mapGet(labels, "cancel");
    print("  'cancel' label: ", lbl);
    assertEqualStr(lbl, "Cancel");

    // Update
    mapPut(labels, "ok", "Okay");
    lbl = mapGet(labels, "ok");
    print("  Updated 'ok' to Okay, got: ", lbl);
    assertEqualStr(lbl, "Okay");

    // Iterate
    print("  Iteration:");
    mapReset(labels);
    while mapNext(labels) {
        key.s = mapKey(labels);
        val.s = mapValue(labels);
        print("    ", key, " = ", val);
    }

    // Clear
    mapClear(labels);
    sz = mapSize(labels);
    print("  Size after clear: ", sz);
    assertEqual(sz, 0);

    print("  PASS: Local string map works!");
    print("");
}

// ============================================
// TEST 6: Local Float Map
// ============================================
func testLocalFloatMap() {
    print("TEST 6: Local Float Map");
    print("-----------------------");

    map rates.f;

    mapPut(rates, "USD", 1.0);
    mapPut(rates, "EUR", 0.92);
    mapPut(rates, "GBP", 0.79);
    print("  Added USD=1.0, EUR=0.92, GBP=0.79");

    sz.i = mapSize(rates);
    print("  Size: ", sz);
    assertEqual(sz, 3);

    r.f = mapGet(rates, "EUR");
    print("  EUR rate: ", r);

    r = mapGet(rates, "GBP");
    print("  GBP rate: ", r);

    print("  PASS: Local float map works!");
    print("");
}

// ============================================
// TEST 7: Multiple Local Collections in One Function
// ============================================
func testMultipleCollections() {
    print("TEST 7: Multiple Collections");
    print("----------------------------");

    list intList.i;
    list strList.s;
    map intMap.i;
    map strMap.s;

    // Populate all
    listAdd(intList, 1);
    listAdd(intList, 2);

    listAdd(strList, "X");
    listAdd(strList, "Y");

    mapPut(intMap, "a", 10);
    mapPut(intMap, "b", 20);

    mapPut(strMap, "p", "P-value");
    mapPut(strMap, "q", "Q-value");

    // Verify all
    assertEqual(listSize(intList), 2);
    assertEqual(listSize(strList), 2);
    assertEqual(mapSize(intMap), 2);
    assertEqual(mapSize(strMap), 2);

    print("  All 4 collections created and populated");

    // Access each
    listFirst(intList);
    v1.i = listGet(intList);
    print("  intList first: ", v1);
    assertEqual(v1, 1);

    listFirst(strList);
    s1.s = listGet(strList);
    print("  strList first: ", s1);
    assertEqualStr(s1, "X");

    m1.i = mapGet(intMap, "a");
    print("  intMap['a']: ", m1);
    assertEqual(m1, 10);

    m2.s = mapGet(strMap, "p");
    print("  strMap['p']: ", m2);
    assertEqualStr(m2, "P-value");

    print("  PASS: Multiple collections work!");
    print("");
}

// ============================================
// TEST 8: Nested Function Calls with Local Collections
// ============================================
func innerFunc(n.i) {
    list temp.i;
    listAdd(temp, n);
    listAdd(temp, n * 2);
    listAdd(temp, n * 3);

    sum.i = 0;
    listReset(temp);
    while listNext(temp) {
        sum = sum + listGet(temp);
    }
    return sum;
}

func testNestedCalls() {
    print("TEST 8: Nested Function Calls");
    print("-----------------------------");

    list results.i;

    // Call inner function multiple times
    r1.i = innerFunc(10);
    r2.i = innerFunc(5);
    r3.i = innerFunc(3);

    listAdd(results, r1);
    listAdd(results, r2);
    listAdd(results, r3);

    print("  innerFunc(10) = ", r1, " (expected 60)");
    assertEqual(r1, 60);  // 10 + 20 + 30

    print("  innerFunc(5) = ", r2, " (expected 30)");
    assertEqual(r2, 30);  // 5 + 10 + 15

    print("  innerFunc(3) = ", r3, " (expected 18)");
    assertEqual(r3, 18);  // 3 + 6 + 9

    sz.i = listSize(results);
    print("  Results list size: ", sz);
    assertEqual(sz, 3);

    print("  PASS: Nested calls work!");
    print("");
}

// Run all tests
testLocalIntList();
testLocalStrList();
testLocalFloatList();
testLocalIntMap();
testLocalStrMap();
testLocalFloatMap();
testMultipleCollections();
testNestedCalls();

print("=== ALL LOCAL COLLECTION TESTS PASSED ===");
