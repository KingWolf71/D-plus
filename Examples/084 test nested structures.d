// Test Nested Structures (V1.022.50)
// Syntax: inner.StructType - field of another struct type
// Access: outer\inner\field - chained field access
// V1.022.48: Auto-declare struct on first field access
// V1.022.49: Fixed map position bug
// V1.022.50: Added array of nested structs with function tests

#pragma appname "Nested-Structs-Test"
#pragma decimals 3
#pragma console on
#pragma consolesize "680x740"
#pragma consoleposition "30,50"
#pragma ListASM on
#pragma FastPrint on
#pragma RunThreaded on
#pragma ftoi "truncate"
#pragma version on
#pragma modulename on
#pragma PasteToClipboard on
#pragma floattolerance 0.0001
#pragma GlobalStack 1024
#pragma FunctionStack 32
#pragma EvalStack 256
#pragma LocalStack 64
#pragma CreateLog off
#pragma DefaultFPS 32
#pragma ThreadKillWait 1800
#pragma asmdecimal on

print("=== NESTED STRUCTURES TEST (V1.022.50) ===");
print("");

// =============================================================================
// Define base structures (must be defined BEFORE used in other structs)
// =============================================================================
struct Point {
    x.i;
    y.i;
}

struct Color {
    r.i;
    g.i;
    b.i;
}

struct Size {
    width.i;
    height.i;
}

// =============================================================================
// TEST 1: Basic nested structure
// =============================================================================
print("TEST 1: Basic nested structure");
print("------------------------------");

struct Rectangle {
    pos.Point;
    size.Size;
    name.s;
}

// V1.022.48: Auto-declare struct on first field access
rect.Rectangle\pos\x = 10;
rect\pos\y = 20;
rect\size\width = 100;
rect\size\height = 50;
rect\name = "TestRect";

print("  rect\\pos\\x = ", rect\pos\x, " (expected 10)");
assertEqual(10, rect\pos\x);

print("  rect\\pos\\y = ", rect\pos\y, " (expected 20)");
assertEqual(20, rect\pos\y);

print("  rect\\size\\width = ", rect\size\width, " (expected 100)");
assertEqual(100, rect\size\width);

print("  rect\\size\\height = ", rect\size\height, " (expected 50)");
assertEqual(50, rect\size\height);

print("  rect\\name = ", rect\name, " (expected TestRect)");
assertStringEqual("TestRect", rect\name);

print("  PASS: Basic nested structure works!");
print("");

// =============================================================================
// TEST 2: Multiple nested structures
// =============================================================================
print("TEST 2: Multiple nested structures");
print("---------------------------------");

struct Window {
    topLeft.Point;
    bottomRight.Point;
    background.Color;
    title.s;
}

// V1.022.48: Auto-declare struct on first field access
win.Window\topLeft\x = 0;
win\topLeft\y = 0;
win\bottomRight\x = 800;
win\bottomRight\y = 600;
win\background\r = 255;
win\background\g = 128;
win\background\b = 64;
win\title = "Main Window";

print("  win\\topLeft\\x = ", win\topLeft\x, " (expected 0)");
assertEqual(0, win\topLeft\x);

print("  win\\bottomRight\\x = ", win\bottomRight\x, " (expected 800)");
assertEqual(800, win\bottomRight\x);

print("  win\\bottomRight\\y = ", win\bottomRight\y, " (expected 600)");
assertEqual(600, win\bottomRight\y);

print("  win\\background\\r = ", win\background\r, " (expected 255)");
assertEqual(255, win\background\r);

print("  win\\background\\g = ", win\background\g, " (expected 128)");
assertEqual(128, win\background\g);

print("  win\\background\\b = ", win\background\b, " (expected 64)");
assertEqual(64, win\background\b);

print("  win\\title = ", win\title, " (expected Main Window)");
assertStringEqual("Main Window", win\title);

print("  PASS: Multiple nested structures work!");
print("");

// =============================================================================
// TEST 3: Expressions with nested fields
// =============================================================================
print("TEST 3: Expressions with nested fields");
print("-------------------------------------");

// Calculate rectangle area
area.i = rect\size\width * rect\size\height;
print("  Rectangle area = ", area, " (expected 5000)");
assertEqual(5000, area);

// Calculate window dimensions
winWidth.i = win\bottomRight\x - win\topLeft\x;
winHeight.i = win\bottomRight\y - win\topLeft\y;
print("  Window width = ", winWidth, " (expected 800)");
assertEqual(800, winWidth);

print("  Window height = ", winHeight, " (expected 600)");
assertEqual(600, winHeight);

// Calculate color sum
colorSum.i = win\background\r + win\background\g + win\background\b;
print("  Color sum (R+G+B) = ", colorSum, " (expected 447)");
assertEqual(447, colorSum);

print("  PASS: Expressions with nested fields work!");
print("");

// =============================================================================
// TEST 4: Nested struct field assignment from expressions
// =============================================================================
print("TEST 4: Assignment from expressions");
print("----------------------------------");

// V1.022.48: Auto-declare on first use
rect2.Rectangle\pos\x = rect\pos\x + 50;
rect2\pos\y = rect\pos\y + 50;
rect2\size\width = rect\size\width / 2;
rect2\size\height = rect\size\height / 2;

print("  rect2\\pos\\x = ", rect2\pos\x, " (expected 60)");
assertEqual(60, rect2\pos\x);

print("  rect2\\pos\\y = ", rect2\pos\y, " (expected 70)");
assertEqual(70, rect2\pos\y);

print("  rect2\\size\\width = ", rect2\size\width, " (expected 50)");
assertEqual(50, rect2\size\width);

print("  rect2\\size\\height = ", rect2\size\height, " (expected 25)");
assertEqual(25, rect2\size\height);

print("  PASS: Assignment from expressions works!");
print("");

// =============================================================================
// TEST 5: Structure total size calculation
// =============================================================================
print("TEST 5: Structure total size calculation");
print("---------------------------------------");

// Point has 2 fields (x, y) = 2 slots
// Size has 2 fields (width, height) = 2 slots
// Rectangle has: pos(2) + size(2) + name(1) = 5 slots total

// Window has: topLeft(2) + bottomRight(2) + background(3) + title(1) = 8 slots

// We can verify slot allocation by modifying and reading values
// If slots overlap incorrectly, values would be corrupted

// Reset all values
rect\pos\x = 1;
rect\pos\y = 2;
rect\size\width = 3;
rect\size\height = 4;
rect\name = "Five";

// Read back - should all be correct
print("  rect\\pos\\x = ", rect\pos\x, " (expected 1)");
assertEqual(1, rect\pos\x);

print("  rect\\pos\\y = ", rect\pos\y, " (expected 2)");
assertEqual(2, rect\pos\y);

print("  rect\\size\\width = ", rect\size\width, " (expected 3)");
assertEqual(3, rect\size\width);

print("  rect\\size\\height = ", rect\size\height, " (expected 4)");
assertEqual(4, rect\size\height);

print("  rect\\name = ", rect\name, " (expected Five)");
assertStringEqual("Five", rect\name);

print("  PASS: Total size calculation correct!");
print("");

// =============================================================================
// TEST 6: Array of nested structures
// =============================================================================
print("TEST 6: Array of nested structures");
print("---------------------------------");

array rects.Rectangle[3];

// Initialize array elements
rects[0]\pos\x = 0;
rects[0]\pos\y = 0;
rects[0]\size\width = 10;
rects[0]\size\height = 10;
rects[0]\name = "Small";

rects[1]\pos\x = 100;
rects[1]\pos\y = 100;
rects[1]\size\width = 200;
rects[1]\size\height = 150;
rects[1]\name = "Medium";

rects[2]\pos\x = 500;
rects[2]\pos\y = 500;
rects[2]\size\width = 800;
rects[2]\size\height = 600;
rects[2]\name = "Large";

print("  rects[0]\\pos\\x = ", rects[0]\pos\x, " (expected 0)");
assertEqual(0, rects[0]\pos\x);

print("  rects[1]\\size\\width = ", rects[1]\size\width, " (expected 200)");
assertEqual(200, rects[1]\size\width);

print("  rects[2]\\name = ", rects[2]\name, " (expected Large)");
assertStringEqual("Large", rects[2]\name);

// Loop through array
totalArea.i = 0;
i = 0;
while i < 3 {
    a.i = rects[i]\size\width * rects[i]\size\height;
    totalArea = totalArea + a;
    print("  rects[", i, "] area = ", a);
    i++;
}
print("  Total area = ", totalArea, " (expected 510100)");
assertEqual(510100, totalArea);

print("  PASS: Array of nested structures works!");
print("");

// =============================================================================
// TEST 7: Function modifying nested structure fields
// =============================================================================
print("TEST 7: Function modifying nested structure fields");
print("-------------------------------------------------");

// Function to move a rectangle by offset
func moveRect(idx, dx, dy) {
    rects[idx]\pos\x = rects[idx]\pos\x + dx;
    rects[idx]\pos\y = rects[idx]\pos\y + dy;
    print("  moveRect: moved rects[", idx, "] by (", dx, ", ", dy, ")");
}

// Function to scale a rectangle
func scaleRect(idx, factor) {
    rects[idx]\size\width = rects[idx]\size\width * factor;
    rects[idx]\size\height = rects[idx]\size\height * factor;
    print("  scaleRect: scaled rects[", idx, "] by factor ", factor);
}

// Function to rename a rectangle
func renameRect(idx, newName.s) {
    rects[idx]\name = newName;
    print("  renameRect: renamed rects[", idx, "] to '", newName, "'");
}

// Original values for rects[0]: pos(0,0), size(10,10), name="Small"
print("  Before: rects[0] pos=(",rects[0]\pos\x,",",rects[0]\pos\y,") size=(",rects[0]\size\width,"x",rects[0]\size\height,") name=",rects[0]\name);

// Call functions to modify
moveRect(0, 25, 35);
scaleRect(0, 3);
renameRect(0, "Modified");

// Verify changes persisted
print("  After: rects[0] pos=(",rects[0]\pos\x,",",rects[0]\pos\y,") size=(",rects[0]\size\width,"x",rects[0]\size\height,") name=",rects[0]\name);

print("  rects[0]\\pos\\x = ", rects[0]\pos\x, " (expected 25)");
assertEqual(25, rects[0]\pos\x);

print("  rects[0]\\pos\\y = ", rects[0]\pos\y, " (expected 35)");
assertEqual(35, rects[0]\pos\y);

print("  rects[0]\\size\\width = ", rects[0]\size\width, " (expected 30)");
assertEqual(30, rects[0]\size\width);

print("  rects[0]\\size\\height = ", rects[0]\size\height, " (expected 30)");
assertEqual(30, rects[0]\size\height);

print("  rects[0]\\name = ", rects[0]\name, " (expected Modified)");
assertStringEqual("Modified", rects[0]\name);

print("  PASS: Function modifying nested structure fields works!");
print("");

print("=== ALL NESTED STRUCTURE TESTS PASSED ===");
print("");
print("Summary:");
print("  - Nested struct definition: WORKING");
print("  - Nested field assignment (outer\\inner\\field = val): WORKING");
print("  - Nested field read (outer\\inner\\field): WORKING");
print("  - Multiple nested fields: WORKING");
print("  - Expressions with nested fields: WORKING");
print("  - Slot allocation for nested structs: WORKING");
print("  - Array of nested structures: WORKING");
print("  - Function modifying nested struct fields: WORKING");
print("");
