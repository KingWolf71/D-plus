/* Minimal float test 3 - no division */
#pragma console on
#pragma ListASM on
#pragma consolesize "680x740"
#pragma consoleposition "30,50"
#pragma asmdecimal on

print("Starting");

// Test: Global float multiply
gf.f = 22.0 * 7.0;
print("gf = ", gf);

print("Done");
