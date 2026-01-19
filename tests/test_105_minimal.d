// Minimal test to find crash in test 105
#pragma console on
#pragma version on
#pragma consolesize "680x740"
#pragma consoleposition "30,50"
#pragma asmdecimal on

print("=== TEST 105 MINIMAL ===");
print("");

// PART 1: Simple struct
print("PART 1: Simple struct");
struct Point {
    x.f;
    y.f;
}

p1.Point = { };
p1.x = 10.5;
p1.y = 20.5;
print("p1.x = ", p1.x);
print("p1.y = ", p1.y);
print("");

// PART 9: Lists with Structs
print("PART 9: Lists with Structs");

list pointList.Point;

p2.Point = { };
p2.x = 10.0;
p2.y = 20.0;
listAdd(pointList, p2);

print("List size: ", listSize(pointList));

print("");
print("=== DONE ===");
