// AVL Tree Test 2 - Dual Trees (Integer + String)
// Tests two separate AVL trees with random insertions and deletions
// Total nodes: 22-25 across both trees

#pragma appname "AVL-Tree-Test-2"
#pragma decimals 3
#pragma console on
#pragma consolesize "680x740"
#pragma consoleposition "30,50"
#pragma FastPrint on
#pragma RunThreaded on
#pragma ftoi "truncate"
#pragma version on
#pragma modulename on
#pragma GlobalStack 2048
#pragma FunctionStack 256
#pragma EvalStack 512
#pragma LocalStack 256
#pragma CreateLog on
#pragma LogName "[default]"
#pragma DefaultFPS 32
#pragma ThreadKillWait 1800
#pragma asmdecimal on
#pragma ListASM on

#define MAX_NODES 64

// =============================================================================
// INTEGER AVL TREE (Tree 1)
// =============================================================================
arr t1_payload[MAX_NODES];
arr t1_height[MAX_NODES];
arr t1_left[MAX_NODES];
arr t1_right[MAX_NODES];
t1_root = -1;
t1_count = 0;

func t1_getHeight(n) {
    if (n == -1) { return 0; }
    return t1_height[n];
}

func t1_getBalance(n) {
    if (n == -1) { return 0; }
    return t1_getHeight(t1_left[n]) - t1_getHeight(t1_right[n]);
}

func t1_updateHeight(n) {
    lh = t1_getHeight(t1_left[n]);
    rh = t1_getHeight(t1_right[n]);
    if (lh > rh) {
        t1_height[n] = lh + 1;
    } else {
        t1_height[n] = rh + 1;
    }
}

func t1_newNode(value) {
    n = t1_count;
    t1_count = t1_count + 1;
    t1_payload[n] = value;
    t1_height[n] = 1;
    t1_left[n] = -1;
    t1_right[n] = -1;
    return n;
}

func t1_rotateRight(y) {
    x = t1_left[y];
    B = t1_right[x];
    t1_right[x] = y;
    t1_left[y] = B;
    t1_updateHeight(y);
    t1_updateHeight(x);
    return x;
}

func t1_rotateLeft(x) {
    y = t1_right[x];
    B = t1_left[y];
    t1_left[y] = x;
    t1_right[x] = B;
    t1_updateHeight(x);
    t1_updateHeight(y);
    return y;
}

func t1_insertNode(n, value) {
    if (n == -1) { return t1_newNode(value); }

    if (value < t1_payload[n]) {
        t1_left[n] = t1_insertNode(t1_left[n], value);
    } else if (value > t1_payload[n]) {
        t1_right[n] = t1_insertNode(t1_right[n], value);
    } else {
        return n;
    }

    t1_updateHeight(n);
    balance = t1_getBalance(n);

    if (balance > 1) {
        if (value < t1_payload[t1_left[n]]) {
            return t1_rotateRight(n);
        }
    }
    if (balance < -1) {
        if (value > t1_payload[t1_right[n]]) {
            return t1_rotateLeft(n);
        }
    }
    if (balance > 1) {
        if (value > t1_payload[t1_left[n]]) {
            t1_left[n] = t1_rotateLeft(t1_left[n]);
            return t1_rotateRight(n);
        }
    }
    if (balance < -1) {
        if (value < t1_payload[t1_right[n]]) {
            t1_right[n] = t1_rotateRight(t1_right[n]);
            return t1_rotateLeft(n);
        }
    }
    return n;
}

func t1_insert(value) {
    t1_root = t1_insertNode(t1_root, value);
}

func t1_findMin(n) {
    current = n;
    while (t1_left[current] != -1) {
        current = t1_left[current];
    }
    return current;
}

func t1_deleteNode(n, value) {
    if (n == -1) { return -1; }

    if (value < t1_payload[n]) {
        t1_left[n] = t1_deleteNode(t1_left[n], value);
    } else if (value > t1_payload[n]) {
        t1_right[n] = t1_deleteNode(t1_right[n], value);
    } else {
        if (t1_left[n] == -1) { return t1_right[n]; }
        if (t1_right[n] == -1) { return t1_left[n]; }
        minNode = t1_findMin(t1_right[n]);
        t1_payload[n] = t1_payload[minNode];
        t1_right[n] = t1_deleteNode(t1_right[n], t1_payload[minNode]);
    }

    t1_updateHeight(n);
    balance = t1_getBalance(n);

    if (balance > 1) {
        if (t1_getBalance(t1_left[n]) >= 0) { return t1_rotateRight(n); }
    }
    if (balance > 1) {
        if (t1_getBalance(t1_left[n]) < 0) {
            t1_left[n] = t1_rotateLeft(t1_left[n]);
            return t1_rotateRight(n);
        }
    }
    if (balance < -1) {
        if (t1_getBalance(t1_right[n]) <= 0) { return t1_rotateLeft(n); }
    }
    if (balance < -1) {
        if (t1_getBalance(t1_right[n]) > 0) {
            t1_right[n] = t1_rotateRight(t1_right[n]);
            return t1_rotateLeft(n);
        }
    }
    return n;
}

func t1_delete(value) {
    t1_root = t1_deleteNode(t1_root, value);
}

func t1_inorder(n) {
    if (n != -1) {
        t1_inorder(t1_left[n]);
        print(t1_payload[n], " ");
        t1_inorder(t1_right[n]);
    }
}

func t1_countNodes(n) {
    if (n == -1) { return 0; }
    return 1 + t1_countNodes(t1_left[n]) + t1_countNodes(t1_right[n]);
}

func t1_verifyAVL(n) {
    if (n == -1) { return 1; }
    balance = t1_getBalance(n);
    if (balance < -1) { return 0; }
    if (balance > 1) { return 0; }
    if (t1_verifyAVL(t1_left[n]) == 0) { return 0; }
    if (t1_verifyAVL(t1_right[n]) == 0) { return 0; }
    return 1;
}

// =============================================================================
// STRING AVL TREE (Tree 2)
// =============================================================================
arr t2_payload.s[MAX_NODES];
arr t2_height[MAX_NODES];
arr t2_left[MAX_NODES];
arr t2_right[MAX_NODES];
t2_root = -1;
t2_count = 0;

// Note: strcmp(a, b) is a built-in function that returns -1/0/1

func t2_getHeight(n) {
    if (n == -1) { return 0; }
    return t2_height[n];
}

func t2_getBalance(n) {
    if (n == -1) { return 0; }
    return t2_getHeight(t2_left[n]) - t2_getHeight(t2_right[n]);
}

func t2_updateHeight(n) {
    lh = t2_getHeight(t2_left[n]);
    rh = t2_getHeight(t2_right[n]);
    if (lh > rh) {
        t2_height[n] = lh + 1;
    } else {
        t2_height[n] = rh + 1;
    }
}

func t2_newNode(value.s) {
    n = t2_count;
    t2_count = t2_count + 1;
    t2_payload[n] = value;
    t2_height[n] = 1;
    t2_left[n] = -1;
    t2_right[n] = -1;
    return n;
}

func t2_rotateRight(y) {
    x = t2_left[y];
    B = t2_right[x];
    t2_right[x] = y;
    t2_left[y] = B;
    t2_updateHeight(y);
    t2_updateHeight(x);
    return x;
}

func t2_rotateLeft(x) {
    y = t2_right[x];
    B = t2_left[y];
    t2_left[y] = x;
    t2_right[x] = B;
    t2_updateHeight(x);
    t2_updateHeight(y);
    return y;
}

func t2_insertNode(n, value.s) {
    if (n == -1) { return t2_newNode(value); }

    cmp = strcmp(value, t2_payload[n]);
    if (cmp < 0) {
        t2_left[n] = t2_insertNode(t2_left[n], value);
    } else if (cmp > 0) {
        t2_right[n] = t2_insertNode(t2_right[n], value);
    } else {
        return n;
    }

    t2_updateHeight(n);
    balance = t2_getBalance(n);

    if (balance > 1) {
        if (strcmp(value, t2_payload[t2_left[n]]) < 0) {
            return t2_rotateRight(n);
        }
    }
    if (balance < -1) {
        if (strcmp(value, t2_payload[t2_right[n]]) > 0) {
            return t2_rotateLeft(n);
        }
    }
    if (balance > 1) {
        if (strcmp(value, t2_payload[t2_left[n]]) > 0) {
            t2_left[n] = t2_rotateLeft(t2_left[n]);
            return t2_rotateRight(n);
        }
    }
    if (balance < -1) {
        if (strcmp(value, t2_payload[t2_right[n]]) < 0) {
            t2_right[n] = t2_rotateRight(t2_right[n]);
            return t2_rotateLeft(n);
        }
    }
    return n;
}

func t2_insert(value.s) {
    t2_root = t2_insertNode(t2_root, value);
}

func t2_findMin(n) {
    current = n;
    while (t2_left[current] != -1) {
        current = t2_left[current];
    }
    return current;
}

func t2_deleteNode(n, value.s) {
    if (n == -1) { return -1; }

    cmp = strcmp(value, t2_payload[n]);
    if (cmp < 0) {
        t2_left[n] = t2_deleteNode(t2_left[n], value);
    } else if (cmp > 0) {
        t2_right[n] = t2_deleteNode(t2_right[n], value);
    } else {
        if (t2_left[n] == -1) { return t2_right[n]; }
        if (t2_right[n] == -1) { return t2_left[n]; }
        minNode = t2_findMin(t2_right[n]);
        t2_payload[n] = t2_payload[minNode];
        t2_right[n] = t2_deleteNode(t2_right[n], t2_payload[minNode]);
    }

    t2_updateHeight(n);
    balance = t2_getBalance(n);

    if (balance > 1) {
        if (t2_getBalance(t2_left[n]) >= 0) { return t2_rotateRight(n); }
    }
    if (balance > 1) {
        if (t2_getBalance(t2_left[n]) < 0) {
            t2_left[n] = t2_rotateLeft(t2_left[n]);
            return t2_rotateRight(n);
        }
    }
    if (balance < -1) {
        if (t2_getBalance(t2_right[n]) <= 0) { return t2_rotateLeft(n); }
    }
    if (balance < -1) {
        if (t2_getBalance(t2_right[n]) > 0) {
            t2_right[n] = t2_rotateRight(t2_right[n]);
            return t2_rotateLeft(n);
        }
    }
    return n;
}

func t2_delete(value.s) {
    t2_root = t2_deleteNode(t2_root, value);
}

func t2_inorder(n) {
    if (n != -1) {
        t2_inorder(t2_left[n]);
        print("'", t2_payload[n], "' ");
        t2_inorder(t2_right[n]);
    }
}

func t2_countNodes(n) {
    if (n == -1) { return 0; }
    return 1 + t2_countNodes(t2_left[n]) + t2_countNodes(t2_right[n]);
}

func t2_verifyAVL(n) {
    if (n == -1) { return 1; }
    balance = t2_getBalance(n);
    if (balance < -1) { return 0; }
    if (balance > 1) { return 0; }
    if (t2_verifyAVL(t2_left[n]) == 0) { return 0; }
    if (t2_verifyAVL(t2_right[n]) == 0) { return 0; }
    return 1;
}

// =============================================================================
// MAIN TEST
// =============================================================================
{
    print("================================================");
    print("   AVL Tree Test 2 - Dual Trees (Int + String)");
    print("================================================");
    print("");

    // =========================================================================
    // INTEGER TREE: Insert 15 nodes with random pattern
    // =========================================================================
    print("=== INTEGER TREE (Tree 1) ===");
    print("");

    print("Phase 1: Initial insertions (15 values)");
    t1_insert(50);
    t1_insert(25);
    t1_insert(75);
    t1_insert(10);
    t1_insert(30);
    t1_insert(60);
    t1_insert(90);
    t1_insert(5);
    t1_insert(15);
    t1_insert(27);
    t1_insert(35);
    t1_insert(55);
    t1_insert(65);
    t1_insert(85);
    t1_insert(95);

    print("  Inserted: 50,25,75,10,30,60,90,5,15,27,35,55,65,85,95");
    print("  Count: ", t1_countNodes(t1_root));
    print("  In-order: ");
    t1_inorder(t1_root);
    print("");
    print("  AVL Valid: ", t1_verifyAVL(t1_root));
    print("");

    print("Phase 2: Random deletions (5 values)");
    t1_delete(30);
    t1_delete(75);
    t1_delete(5);
    t1_delete(55);
    t1_delete(90);
    print("  Deleted: 30, 75, 5, 55, 90");
    print("  Count: ", t1_countNodes(t1_root));
    print("  In-order: ");
    t1_inorder(t1_root);
    print("");
    print("  AVL Valid: ", t1_verifyAVL(t1_root));
    print("");

    print("Phase 3: More insertions (17 values)");
    t1_insert(42);
    t1_insert(8);
    t1_insert(72);
    t1_insert(88);
    t1_insert(3);
    t1_insert(18);
    t1_insert(33);
    t1_insert(48);
    t1_insert(58);
    t1_insert(68);
    t1_insert(78);
    t1_insert(92);
    t1_insert(97);
    t1_insert(99);
    t1_insert(2);
    t1_insert(22);
    t1_insert(44);
    print("  Inserted: 42,8,72,88,3,18,33,48,58,68,78,92,97,99,2,22,44");
    print("  Count: ", t1_countNodes(t1_root));
    print("  In-order: ");
    t1_inorder(t1_root);
    print("");
    print("  AVL Valid: ", t1_verifyAVL(t1_root));
    print("");

    intTreeCount = t1_countNodes(t1_root);
    print("Integer tree final count: ", intTreeCount);
    print("");

    // =========================================================================
    // STRING TREE: Insert nodes with random pattern
    // =========================================================================
    print("=== STRING TREE (Tree 2) ===");
    print("");

    print("Phase 1: Initial insertions (12 strings)");
    t2_insert("mango");
    t2_insert("apple");
    t2_insert("zebra");
    t2_insert("banana");
    t2_insert("kiwi");
    t2_insert("orange");
    t2_insert("grape");
    t2_insert("cherry");
    t2_insert("lemon");
    t2_insert("peach");
    t2_insert("plum");
    t2_insert("fig");

    print("  Inserted: mango,apple,zebra,banana,kiwi,orange,grape,cherry,lemon,peach,plum,fig");
    print("  Count: ", t2_countNodes(t2_root));
    print("  In-order: ");
    t2_inorder(t2_root);
    print("");
    print("  AVL Valid: ", t2_verifyAVL(t2_root));
    print("");

    print("Phase 2: Random deletions (3 strings)");
    t2_delete("kiwi");
    t2_delete("apple");
    t2_delete("peach");
    print("  Deleted: kiwi, apple, peach");
    print("  Count: ", t2_countNodes(t2_root));
    print("  In-order: ");
    t2_inorder(t2_root);
    print("");
    print("  AVL Valid: ", t2_verifyAVL(t2_root));
    print("");

    print("Phase 3: More insertions (16 strings)");
    t2_insert("apricot");
    t2_insert("melon");
    t2_insert("berry");
    t2_insert("date");
    t2_insert("elderberry");
    t2_insert("guava");
    t2_insert("honeydew");
    t2_insert("jackfruit");
    t2_insert("lime");
    t2_insert("nectarine");
    t2_insert("papaya");
    t2_insert("quince");
    t2_insert("raspberry");
    t2_insert("strawberry");
    t2_insert("tangerine");
    t2_insert("watermelon");
    print("  Inserted: apricot,melon,berry,date,elderberry,guava,honeydew,jackfruit,lime,nectarine,papaya,quince,raspberry,strawberry,tangerine,watermelon");
    print("  Count: ", t2_countNodes(t2_root));
    print("  In-order: ");
    t2_inorder(t2_root);
    print("");
    print("  AVL Valid: ", t2_verifyAVL(t2_root));
    print("");

    strTreeCount = t2_countNodes(t2_root);
    print("String tree final count: ", strTreeCount);
    print("");

    // =========================================================================
    // SUMMARY
    // =========================================================================
    print("================================================");
    print("                   SUMMARY");
    print("================================================");
    totalNodes = intTreeCount + strTreeCount;
    print("Integer tree nodes: ", intTreeCount);
    print("String tree nodes:  ", strTreeCount);
    print("Total nodes:        ", totalNodes);
    print("");

    if (t1_verifyAVL(t1_root) == 1) {
        print("Integer tree AVL: PASS");
    } else {
        print("Integer tree AVL: FAIL");
    }

    if (t2_verifyAVL(t2_root) == 1) {
        print("String tree AVL:  PASS");
    } else {
        print("String tree AVL:  FAIL");
    }

    print("");
    print("================================================");
    print("         AVL Tree Test 2 Complete");
    print("================================================");
}
