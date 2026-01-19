// Minimal test for struct without function
#pragma console on
#pragma ListASM on
#pragma consolesize "680x740"
#pragma consoleposition "30,50"
#pragma asmdecimal on

struct Point {
    x.f;
    y.f;
}

pt.Point = { };
pt.x = 10.0;
pt.y = 20.0;

print("pt.x = ", pt.x);
print("pt.y = ", pt.y);
