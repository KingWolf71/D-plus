// Minimal test for struct parameter crash
#pragma console on
#pragma ListASM on
#pragma consolesize "680x740"
#pragma consoleposition "30,50"
#pragma asmdecimal on

struct Point {
    x.f;
    y.f;
}

func addToPoint(p.Point, dx.f) {
    p.x = p.x + dx;
}

pt.Point = { };
pt.x = 10.0;
pt.y = 20.0;

print("Before: pt.x = ", pt.x);
addToPoint(pt, 5.0);
print("After: pt.x = ", pt.x);
