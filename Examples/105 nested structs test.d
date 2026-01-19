// Nested Structures Test (V1.029.0)
// Demonstrates struct flattening for collections
// Compiler flattens nested structs to flat primitives

#pragma appname "Nested-Structs-Test"
#pragma decimals 2
#pragma console on
#pragma consolesize "680x740"
#pragma consoleposition "30,50"
#pragma FastPrint on
#pragma version on
#pragma ListASM on
#pragma FastPrint on
#pragma RunThreaded on
#pragma ftoi "truncate":wets finger 
#pragma modulename on
#pragma PasteToClipboard on
#pragma floattolerance 0.001
#pragma GlobalStack 1024
#pragma FunctionStack 32
#pragma EvalStack 256
#pragma LocalStack 64
#pragma CreateLog off
#pragma DefaultFPS 32
#pragma ThreadKillWait 1800
//#pragma DumpASM on
#pragma asmdecimal on

print("=== NESTED STRUCTURES TEST (V1.029.0) ===");
print("");

// ============================================
// PART 1: Simple Nested Struct
// ============================================
print("PART 1: Simple Nested Struct");
print("-----------------------------");

struct Point {
    x.f;
    y.f;
}

struct Rectangle {
    topLeft.Point;      // Nested struct
    bottomRight.Point;  // Nested struct
    color.i;
}

// When flattened, Rectangle becomes:
// Field 0: topLeft.x (float) - offset 0
// Field 1: topLeft.y (float) - offset 8
// Field 2: bottomRight.x (float) - offset 16
// Field 3: bottomRight.y (float) - offset 24
// Field 4: color (int) - offset 32

rect1.Rectangle = { };
rect1.topLeft.x = 10.5;
rect1.topLeft.y = 20.5;
rect1.bottomRight.x = 100.5;
rect1.bottomRight.y = 200.5;
rect1.color = 255;

print("Rectangle 1:");
print("  topLeft: (", rect1.topLeft.x, ", ", rect1.topLeft.y, ")");
print("  bottomRight: (", rect1.bottomRight.x, ", ", rect1.bottomRight.y, ")");
print("  color: ", rect1.color);
print("");

// ============================================
// PART 2: Three-Level Nesting
// ============================================
print("PART 2: Three-Level Nesting");
print("----------------------------");

struct Vector2D {
    dx.f;
    dy.f;
}

struct Transform {
    position.Point;
    velocity.Vector2D;
    scale.f;
}

struct GameObject {
    id.i;
    name.s;
    transform.Transform;
    active.i;
}

// When flattened, GameObject becomes:
// Field 0: id (int)
// Field 1: name (string)
// Field 2: transform.position.x (float)
// Field 3: transform.position.y (float)
// Field 4: transform.velocity.dx (float)
// Field 5: transform.velocity.dy (float)
// Field 6: transform.scale (float)
// Field 7: active (int)

player.GameObject = { };
player.id = 1;
player.name = "Player1";
player.transform.position.x = 100.0;
player.transform.position.y = 50.0;
player.transform.velocity.dx = 5.5;
player.transform.velocity.dy = -2.3;
player.transform.scale = 1.5;
player.active = 1;

print("Player GameObject:");
print("  id: ", player.id);
print("  name: ", player.name);
print("  position: (", player.transform.position.x, ", ", player.transform.position.y, ")");
print("  velocity: (", player.transform.velocity.dx, ", ", player.transform.velocity.dy, ")");
print("  scale: ", player.transform.scale);
print("  active: ", player.active);
print("");

// ============================================
// PART 3: Nested Struct in Array
// ============================================
print("PART 3: Nested Struct in Array");
print("-------------------------------");

arr enemies.GameObject[5];

// Initialize enemies
i = 0;
while (i < 5) {
    enemies[i]\id = 100 + i;
    enemies[i]\name = "Enemy";
    enemies[i]\transform\position\x = 200.0 + i * 50;
    enemies[i]\transform\position\y = 100.0 + i * 30;
    enemies[i]\transform\velocity\dx = -3.0;
    enemies[i]\transform\velocity\dy = 0.0;
    enemies[i]\transform\scale = 1.0;
    enemies[i]\active = 1;
    i = i + 1;
}

print("Enemies array:");
i = 0;
while (i < 5) {
    print("  [", i, "] id=", enemies[i]\id, " pos=(", enemies[i]\transform\position\x, ",", enemies[i]\transform\position\y, ")");
    i = i + 1;
}
print("");

// ============================================
// PART 4: Nested Struct with Multiple Instances
// ============================================
print("PART 4: Multiple Nested Instances");
print("----------------------------------");

struct Color {
    r.i;
    g.i;
    b.i;
}

struct Material {
    diffuse.Color;
    specular.Color;
    shininess.f;
}

struct Mesh {
    vertexCount.i;
    material.Material;
    name.s;
}

cube.Mesh = { };
cube.vertexCount = 36;
cube.material.diffuse.r = 255;
cube.material.diffuse.g = 128;
cube.material.diffuse.b = 64;
cube.material.specular.r = 255;
cube.material.specular.g = 255;
cube.material.specular.b = 255;
cube.material.shininess = 32.0;
cube.name = "Cube";

print("Mesh 'Cube':");
print("  vertices: ", cube.vertexCount);
print("  diffuse RGB: (", cube.material.diffuse.r, ", ", cube.material.diffuse.g, ", ", cube.material.diffuse.b, ")");
print("  specular RGB: (", cube.material.specular.r, ", ", cube.material.specular.g, ", ", cube.material.specular.b, ")");
print("  shininess: ", cube.material.shininess);
print("");

// ============================================
// PART 5: Function with Nested Struct Parameter
// ============================================
print("PART 5: Functions with Nested Structs");
print("--------------------------------------");

func calculateArea.f(r.Rectangle) {
    width.f = r.bottomRight.x - r.topLeft.x;
    height.f = r.bottomRight.y - r.topLeft.y;
    return width * height;
}

func moveGameObject(obj.GameObject, dx.f, dy.f) {
    obj.transform.position.x = obj.transform.position.x + dx;
    obj.transform.position.y = obj.transform.position.y + dy;
}

area.f = calculateArea(rect1);
print("Rectangle area: ", area);

print("Moving player by (10, 20)...");
oldX.f = player.transform.position.x;
oldY.f = player.transform.position.y;
moveGameObject(player, 10.0, 20.0);
print("  Before: (", oldX, ", ", oldY, ")");
print("  After:  (", player.transform.position.x, ", ", player.transform.position.y, ")");
print("");

// ============================================
// PART 6: Copying Nested Structs
// ============================================
print("PART 6: Copying Nested Structs");
print("------------------------------");

rect2.Rectangle = { };
rect2 = rect1;  // Full struct copy (all flattened fields)

print("Copied rect1 to rect2:");
print("  rect2.topLeft: (", rect2.topLeft.x, ", ", rect2.topLeft.y, ")");
print("  rect2.bottomRight: (", rect2.bottomRight.x, ", ", rect2.bottomRight.y, ")");
print("  rect2.color: ", rect2.color);

// Modify rect2 to prove it's a copy
rect2.topLeft.x = 999.0;
print("After modifying rect2.topLeft.x = 999:");
print("  rect1.topLeft.x = ", rect1.topLeft.x, " (unchanged)");
print("  rect2.topLeft.x = ", rect2.topLeft.x, " (modified)");
print("");

// ============================================
// PART 7: Deeply Nested Access Pattern
// ============================================
print("PART 7: Deep Nesting Access");
print("---------------------------");

struct Level1 { val.i; }
struct Level2 { a.Level1; b.Level1; }
struct Level3 { x.Level2; y.Level2; }
struct Level4 { data.Level3; id.i; }

deep.Level4 = { };
deep.id = 42;
deep.data.x.a.val = 1;
deep.data.x.b.val = 2;
deep.data.y.a.val = 3;
deep.data.y.b.val = 4;

// Flattened to: id, data.x.a.val, data.x.b.val, data.y.a.val, data.y.b.val
print("Level4 struct (4 levels deep):");
print("  id: ", deep.id);
print("  data.x.a.val: ", deep.data.x.a.val);
print("  data.x.b.val: ", deep.data.x.b.val);
print("  data.y.a.val: ", deep.data.y.a.val);
print("  data.y.b.val: ", deep.data.y.b.val);

sum.i = deep.data.x.a.val + deep.data.x.b.val + deep.data.y.a.val + deep.data.y.b.val;
print("  Sum of all vals: ", sum);
print("");

// ============================================
// PART 8: Local Struct Variables
// ============================================
print("PART 8: Local Struct Variables");
print("-------------------------------");

func createPoint.f(px.f, py.f) {
    local.Point = { };
    local.x = px;
    local.y = py;
    // Return sum to verify local struct worked
    return local.x + local.y;
}

func createAndModifyRect.f() {
    // Local nested struct
    localRect.Rectangle = { };
    localRect.topLeft.x = 1.0;
    localRect.topLeft.y = 2.0;
    localRect.bottomRight.x = 10.0;
    localRect.bottomRight.y = 20.0;
    localRect.color = 100;

    // Compute area locally
    w.f = localRect.bottomRight.x - localRect.topLeft.x;
    h.f = localRect.bottomRight.y - localRect.topLeft.y;
    return w * h;
}

localSum.f = createPoint(5.5, 3.3);
print("Local Point sum (5.5 + 3.3): ", localSum);

localArea.f = createAndModifyRect();
print("Local Rectangle area (9 * 18 = 162): ", localArea);
print("");

// ============================================
// PART 9: Lists with Structs
// ============================================
print("PART 9: Lists with Structs");
print("--------------------------");

// Create a list of Point structs
list pointList.Point;

// Add points to the list
p1.Point = { };
p1.x = 10.0;
p1.y = 20.0;
listAdd(pointList, p1);

p1.x = 30.0;
p1.y = 40.0;
listAdd(pointList, p1);

p1.x = 50.0;
p1.y = 60.0;
listAdd(pointList, p1);

print("Point list size: ", listSize(pointList));

// Iterate and print
listReset(pointList);
idx = 0;
while (listNext(pointList)) {
    retrieved.Point = listGet(pointList);
    print("  Point[", idx, "]: (", retrieved.x, ", ", retrieved.y, ")");
    idx = idx + 1;
}
print("");

// ============================================
// PART 10: Maps with Structs
// ============================================
print("PART 10: Maps with Structs");
print("--------------------------");

// Create a map of Point structs
map pointMap.Point;

// Add points with string keys
origin.Point = { };
origin.x = 0.0;
origin.y = 0.0;
mapPut(pointMap, "origin", origin);

center.Point = { };
center.x = 50.0;
center.y = 50.0;
mapPut(pointMap, "center", center);

corner.Point = { };
corner.x = 100.0;
corner.y = 100.0;
mapPut(pointMap, "corner", corner);

print("Point map size: ", mapSize(pointMap));

// Retrieve and print
if (mapContains(pointMap, "origin")) {
    got.Point = mapGet(pointMap, "origin");
    print("  origin: (", got.x, ", ", got.y, ")");
}

if (mapContains(pointMap, "center")) {
    got = mapGet(pointMap, "center");
    print("  center: (", got.x, ", ", got.y, ")");
}

if (mapContains(pointMap, "corner")) {
    got = mapGet(pointMap, "corner");
    print("  corner: (", got.x, ", ", got.y, ")");
}
print("");

// ============================================
// PART 11: Local Collections
// ============================================
print("PART 11: Local Collections");
print("--------------------------");

func sumLocalList() {
    // Local list inside function
    list localNums.i;

    listAdd(localNums, 10);
    listAdd(localNums, 20);
    listAdd(localNums, 30);

    total.i = 0;
    listReset(localNums);
    while (listNext(localNums)) {
        total = total + listGet(localNums);
    }
    return total;
}

func countLocalMap() {
    // Local map inside function
    map localData.i;

    mapPut(localData, "a", 1);
    mapPut(localData, "b", 2);
    mapPut(localData, "c", 3);

    return mapSize(localData);
}

listTotal.i = sumLocalList();
print("Local list sum (10+20+30=60): ", listTotal);

mapCount.i = countLocalMap();
print("Local map count (3): ", mapCount);
print("");

print("=== ALL NESTED STRUCT TESTS COMPLETE ===");
