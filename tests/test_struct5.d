#pragma console on
#pragma consolesize "680x740"
#pragma consoleposition "30,50"
#pragma asmdecimal on

struct Point {
    x.f;
    y.f;
}

pt.Point = { };
print("After init");
pt.x = 10.0;
print("After assign");
print("x = ", pt.x);
