/* Minimal float test */
#pragma console on
#pragma consolesize "680x740"
#pragma consoleposition "30,50"
#pragma asmdecimal on

// Test: Global float division
gf.f = 22.0 / 7.0;
print("Global float division: ", gf);

// Test: Function with float params
func addFloats(a.f, b.f) {
    result.f = a + b;
    print("  a = ", a, " b = ", b, " a+b = ", result);
    return result;
}

print("Testing float addition in function:");
r.f = addFloats(10.5, 3.5);
print("Returned: ", r);

print("Done");
