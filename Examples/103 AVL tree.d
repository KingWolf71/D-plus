// AVL Tree Implementation for LJ
// Based on Rosetta Code C implementation
// Uses array-based nodes instead of pointers (no malloc needed)
//
// An AVL tree is a self-balancing binary search tree where
// the heights of two child subtrees differ by at most one.

#pragma appname "AVL Tree Demo"
#pragma decimals 3
#pragma console on
#pragma consolesize "680x740"
#pragma consoleposition "30,50"
#pragma FastPrint on
#pragma RunThreaded on
#pragma ftoi "truncate"
#pragma version on
#pragma ListASM on
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

// =============================================================================
// AVL Tree using Array-Based Nodes
// =============================================================================
// Instead of pointers, we use array indices:
//   -1 = NULL (no child)
//   0+ = valid node index

#define MAX_NODES 256

// Node storage arrays (parallel arrays for each field)
arr payload[MAX_NODES];     // Node values
arr height[MAX_NODES];      // Node heights
arr lchild[MAX_NODES];      // Left child index (-1 = none)
arr rchild[MAX_NODES];      // Right child index (-1 = none)

root = -1;                  // Root node index (-1 = empty tree)
nodeCount = 0;              // Number of nodes allocated

// =============================================================================
// Helper Functions
// =============================================================================

// Get height of a node (returns 0 for null nodes)
func getHeight(n) {
    if (n == -1) {
        return 0;
    }
    return height[n];
}

// Calculate balance factor: left height - right height
func getBalance(n) {
    if (n == -1) {
        return 0;
    }
    ln = lchild[n];
    rn = rchild[n];
    lh = getHeight(ln);
    rh = getHeight(rn);
    return lh - rh;
}

// Update height of a node based on children
func updateHeight(n) {
    lh = getHeight(lchild[n]);
    rh = getHeight(rchild[n]);
    if (lh > rh) {
        height[n] = lh + 1;
    } else {
        height[n] = rh + 1;
    }
}

// Allocate a new node
func newNode(value) {
    if (nodeCount >= MAX_NODES) {
        print("ERROR: Tree full!");
        return -1;
    }
    n = nodeCount;
    nodeCount = nodeCount + 1;
    payload[n] = value;
    height[n] = 1;
    lchild[n] = -1;
    rchild[n] = -1;
    return n;
}

// =============================================================================
// Rotation Functions
// =============================================================================

// Right rotation around node y
//       y                x
//      / \              / \
//     x   C    -->     A   y
//    / \                  / \
//   A   B                B   C
func rotateRight(y) {
    x = lchild[y];
    B = rchild[x];

    // Perform rotation
    rchild[x] = y;
    lchild[y] = B;

    // Update heights (y first, then x)
    updateHeight(y);
    updateHeight(x);

    return x;
}

// Left rotation around node x
//     x                  y
//    / \                / \
//   A   y      -->     x   C
//      / \            / \
//     B   C          A   B
func rotateLeft(x) {
    y = rchild[x];
    B = lchild[y];

    // Perform rotation
    lchild[y] = x;
    rchild[x] = B;

    // Update heights (x first, then y)
    updateHeight(x);
    updateHeight(y);

    return y;
}

// =============================================================================
// Insert Function
// =============================================================================

// Insert a value into subtree rooted at node n
// Returns new root of subtree
func insertNode(n, value) {
    // Base case: empty subtree
    if (n == -1) {
        return newNode(value);
    }

    // BST insert
    if (value < payload[n]) {
        lchild[n] = insertNode(lchild[n], value);
    } else if (value > payload[n]) {
        rchild[n] = insertNode(rchild[n], value);
    } else {
        // Duplicate value - ignore
        return n;
    }

    // Update height
    updateHeight(n);

    // Get balance factor
    balance = getBalance(n);

    // Left Left Case
    if (balance > 1) {
        if (value < payload[lchild[n]]) {
            return rotateRight(n);
        }
    }

    // Right Right Case
    if (balance < -1) {
        if (value > payload[rchild[n]]) {
            return rotateLeft(n);
        }
    }

    // Left Right Case
    if (balance > 1) {
        if (value > payload[lchild[n]]) {
            lchild[n] = rotateLeft(lchild[n]);
            return rotateRight(n);
        }
    }

    // Right Left Case
    if (balance < -1) {
        if (value < payload[rchild[n]]) {
            rchild[n] = rotateRight(rchild[n]);
            return rotateLeft(n);
        }
    }

    return n;
}

// Public insert function
func insert(value) {
    root = insertNode(root, value);
}

// =============================================================================
// Search Function
// =============================================================================

func search(n, value) {
    if (n == -1) {
        return 0;  // Not found
    }
    if (value == payload[n]) {
        return 1;  // Found
    }
    if (value < payload[n]) {
        return search(lchild[n], value);
    }
    return search(rchild[n], value);
}

func find(value) {
    return search(root, value);
}

// =============================================================================
// Find Minimum (for delete)
// =============================================================================

func findMin(n) {
    current = n;
    while (lchild[current] != -1) {
        current = lchild[current];
    }
    return current;
}

// =============================================================================
// Delete Function
// =============================================================================

func deleteNode(n, value) {
    if (n == -1) {
        return -1;
    }

    // BST delete
    if (value < payload[n]) {
        lchild[n] = deleteNode(lchild[n], value);
    } else if (value > payload[n]) {
        rchild[n] = deleteNode(rchild[n], value);
    } else {
        // Node found - delete it

        // Node with one child or no child
        if (lchild[n] == -1) {
            return rchild[n];
        } else if (rchild[n] == -1) {
            return lchild[n];
        }

        // Node with two children
        // Get inorder successor (smallest in right subtree)
        minNode = findMin(rchild[n]);
        payload[n] = payload[minNode];
        rchild[n] = deleteNode(rchild[n], payload[minNode]);
    }

    // Update height
    updateHeight(n);

    // Rebalance
    balance = getBalance(n);

    // Left Left Case
    if (balance > 1) {
        if (getBalance(lchild[n]) >= 0) {
            return rotateRight(n);
        }
    }

    // Left Right Case
    if (balance > 1) {
        if (getBalance(lchild[n]) < 0) {
            lchild[n] = rotateLeft(lchild[n]);
            return rotateRight(n);
        }
    }

    // Right Right Case
    if (balance < -1) {
        if (getBalance(rchild[n]) <= 0) {
            return rotateLeft(n);
        }
    }

    // Right Left Case
    if (balance < -1) {
        if (getBalance(rchild[n]) > 0) {
            rchild[n] = rotateRight(rchild[n]);
            return rotateLeft(n);
        }
    }

    return n;
}

func delete(value) {
    root = deleteNode(root, value);
}

// =============================================================================
// Tree Traversal Functions
// =============================================================================

// In-order traversal (prints sorted order)
func inorder(n) {
    if (n != -1) {
        inorder(lchild[n]);
        print(payload[n], " ");
        inorder(rchild[n]);
    }
}

// Pre-order traversal
func preorder(n) {
    if (n != -1) {
        print(payload[n], " ");
        preorder(lchild[n]);
        preorder(rchild[n]);
    }
}

// Print tree structure (rotated 90 degrees)
func printTreeHelper(n, indent) {
    if (n != -1) {
        printTreeHelper(rchild[n], indent + 4);

        // Print indentation
        for (i = 0; i < indent; i++) {
            putc(' ');
        }
        print(payload[n], "(h=", height[n], ",b=", getBalance(n), ")");

        printTreeHelper(lchild[n], indent + 4);
    }
}

func printTree() {
    print("Tree structure (rotated, right is up):");
    printTreeHelper(root, 0);
    print("");
}

// =============================================================================
// Verification Functions
// =============================================================================

// Verify AVL property holds for entire tree
func verifyAVL(n) {
    if (n == -1) {
        return 1;  // Empty tree is valid
    }

    balance = getBalance(n);
    if (balance < -1) {
        print("AVL violation at node ", payload[n], ": balance = ", balance);
        return 0;
    }
    if (balance > 1) {
        print("AVL violation at node ", payload[n], ": balance = ", balance);
        return 0;
    }

    // Check children
    if (verifyAVL(lchild[n]) == 0) {
        return 0;
    }
    if (verifyAVL(rchild[n]) == 0) {
        return 0;
    }

    return 1;
}

// Count nodes in tree
func countNodes(n) {
    if (n == -1) {
        return 0;
    }
    return 1 + countNodes(lchild[n]) + countNodes(rchild[n]);
}

// =============================================================================
// Main Demo
// =============================================================================
{
    print("========================================");
    print("        AVL Tree Demonstration");
    print("========================================");
    print("");

    // Insert values
    print("Inserting: 10, 20, 30, 40, 50, 25");
    print("");

    insert(10);
    insert(20);
    insert(30);
    insert(40);
    insert(50);
    insert(25);

    printTree();

    print("In-order traversal (sorted): ");
    inorder(root);
    print("");
    print("");

    print("Pre-order traversal: ");
    preorder(root);
    print("");
    print("");

    // Verify AVL property
    print("Verifying AVL property...");
    if (verifyAVL(root)) {
        print("AVL property: VALID");
    } else {
        print("AVL property: VIOLATED!");
    }
    print("Node count: ", countNodes(root));
    print("");

    // Search tests
    print("Search tests:");
    print("  find(30) = ", find(30), " (expected 1)");
    print("  find(25) = ", find(25), " (expected 1)");
    print("  find(99) = ", find(99), " (expected 0)");
    print("");

    // Delete tests
    print("Deleting 20...");
    delete(20);
    printTree();

    print("In-order after delete: ");
    inorder(root);
    print("");
    print("");

    print("Verifying AVL after delete...");
    if (verifyAVL(root)) {
        print("AVL property: VALID");
    } else {
        print("AVL property: VIOLATED!");
    }
    print("");

    // Insert more values
    print("Inserting: 5, 15, 35, 45");
    insert(5);
    insert(15);
    insert(35);
    insert(45);

    printTree();

    print("Final in-order: ");
    inorder(root);
    print("");
    print("");

    print("Final verification...");
    if (verifyAVL(root)) {
        print("AVL property: VALID");
    } else {
        print("AVL property: VIOLATED!");
    }
    print("Total nodes: ", countNodes(root));
    print("");

    print("========================================");
    print("        AVL Tree Demo Complete");
    print("========================================");
}
