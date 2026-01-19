/* Game 24 Solver
   Based on: https://rosettacode.org/wiki/24_game

   Given 4 random digits (1-9), find expressions using +, -, *, /
   that evaluate to 24. Each digit must be used exactly once.
*/

#pragma appname "Game-24-Solver"
#pragma decimals 2
#pragma console on
#pragma consolesize "680x740"
#pragma consoleposition "30,50"
#pragma FastPrint on
#pragma RunThreaded on
#pragma ftoi "truncate"
#pragma floattolerance 0.0001
#pragma GlobalStack 1024
#pragma FunctionStack 32
#pragma EvalStack 256
#pragma LocalStack 64
#pragma CreateLog off
#pragma DefaultFPS 32
#pragma ThreadKillWait 1800
#pragma version on
#pragma modulename on
#pragma PasteToClipboard on
#pragma ListASM on
#pragma asmdecimal on

// Global arrays for the 4 digits and operator symbols
array digits[4];
array perm[4];
array ops.s[4];

// Count of solutions found
solutionCount = 0;

// Operator symbols for display
ops[0] = "+";
ops[1] = "-";
ops[2] = "*";
ops[3] = "/";

// Apply operator: returns a op b
func applyOp.f(a.f, b.f, op) {
    if op == 0 {
        return a + b;
    }
    if op == 1 {
        return a - b;
    }
    if op == 2 {
        return a * b;
    }
    if op == 3 {
        if b == 0.0 {
            return 99999.0;  // Division by zero - return impossible value
        }
        return a / b;
    }
    return 0.0;
}

// Check if result equals 24 (with tolerance for floating point)
func isTarget(val.f) {
    diff.f = val - 24.0;
    if diff < 0.0 {
        diff = 0.0 - diff;
    }
    if diff < 0.0001 {
        return 1;
    }
    return 0;
}

// Try expression pattern: ((a op1 b) op2 c) op3 d
func tryPattern1(a.f, b.f, c.f, d.f, op1, op2, op3) {
    r1.f = applyOp(a, b, op1);
    r2.f = applyOp(r1, c, op2);
    result.f = applyOp(r2, d, op3);
    return isTarget(result);
}

// Try expression pattern: (a op1 (b op2 c)) op3 d
func tryPattern2(a.f, b.f, c.f, d.f, op1, op2, op3) {
    r1.f = applyOp(b, c, op2);
    r2.f = applyOp(a, r1, op1);
    result.f = applyOp(r2, d, op3);
    return isTarget(result);
}

// Try expression pattern: (a op1 b) op2 (c op3 d)
func tryPattern3(a.f, b.f, c.f, d.f, op1, op2, op3) {
    r1.f = applyOp(a, b, op1);
    r2.f = applyOp(c, d, op3);
    result.f = applyOp(r1, r2, op2);
    return isTarget(result);
}

// Try expression pattern: a op1 ((b op2 c) op3 d)
func tryPattern4(a.f, b.f, c.f, d.f, op1, op2, op3) {
    r1.f = applyOp(b, c, op2);
    r2.f = applyOp(r1, d, op3);
    result.f = applyOp(a, r2, op1);
    return isTarget(result);
}

// Try expression pattern: a op1 (b op2 (c op3 d))
func tryPattern5(a.f, b.f, c.f, d.f, op1, op2, op3) {
    r1.f = applyOp(c, d, op3);
    r2.f = applyOp(b, r1, op2);
    result.f = applyOp(a, r2, op1);
    return isTarget(result);
}

// Print solution for pattern 1: ((a op1 b) op2 c) op3 d
func printSol1(a, b, c, d, op1, op2, op3) {
    print("  ((", a, " ", ops[op1], " ", b, ") ", ops[op2], " ", c, ") ", ops[op3], " ", d, " = 24");
}

// Print solution for pattern 2: (a op1 (b op2 c)) op3 d
func printSol2(a, b, c, d, op1, op2, op3) {
    print("  (", a, " ", ops[op1], " (", b, " ", ops[op2], " ", c, ")) ", ops[op3], " ", d, " = 24");
}

// Print solution for pattern 3: (a op1 b) op2 (c op3 d)
func printSol3(a, b, c, d, op1, op2, op3) {
    print("  (", a, " ", ops[op1], " ", b, ") ", ops[op2], " (", c, " ", ops[op3], " ", d, ") = 24");
}

// Print solution for pattern 4: a op1 ((b op2 c) op3 d)
func printSol4(a, b, c, d, op1, op2, op3) {
    print("  ", a, " ", ops[op1], " ((", b, " ", ops[op2], " ", c, ") ", ops[op3], " ", d, ") = 24");
}

// Print solution for pattern 5: a op1 (b op2 (c op3 d))
func printSol5(a, b, c, d, op1, op2, op3) {
    print("  ", a, " ", ops[op1], " (", b, " ", ops[op2], " (", c, " ", ops[op3], " ", d, ")) = 24");
}

// Try all operator combinations for a given permutation
func tryAllOps(a, b, c, d) {
    af.f = a;
    bf.f = b;
    cf.f = c;
    df.f = d;

    op1 = 0;
    while op1 < 4 {
        op2 = 0;
        while op2 < 4 {
            op3 = 0;
            while op3 < 4 {
                // Try all 5 expression patterns
                if tryPattern1(af, bf, cf, df, op1, op2, op3) {
                    printSol1(a, b, c, d, op1, op2, op3);
                    solutionCount = solutionCount + 1;
                }
                if tryPattern2(af, bf, cf, df, op1, op2, op3) {
                    printSol2(a, b, c, d, op1, op2, op3);
                    solutionCount = solutionCount + 1;
                }
                if tryPattern3(af, bf, cf, df, op1, op2, op3) {
                    printSol3(a, b, c, d, op1, op2, op3);
                    solutionCount = solutionCount + 1;
                }
                if tryPattern4(af, bf, cf, df, op1, op2, op3) {
                    printSol4(a, b, c, d, op1, op2, op3);
                    solutionCount = solutionCount + 1;
                }
                if tryPattern5(af, bf, cf, df, op1, op2, op3) {
                    printSol5(a, b, c, d, op1, op2, op3);
                    solutionCount = solutionCount + 1;
                }
                op3 = op3 + 1;
            }
            op2 = op2 + 1;
        }
        op1 = op1 + 1;
    }
}

// Generate all 24 permutations of 4 digits and try each
func solve() {
    // All 24 permutations of indices 0,1,2,3
    // Using nested loops for all permutations
    i0 = 0;
    while i0 < 4 {
        i1 = 0;
        while i1 < 4 {
            if i1 != i0 {
                i2 = 0;
                while i2 < 4 {
                    if i2 != i0 {
                        if i2 != i1 {
                            i3 = 0;
                            while i3 < 4 {
                                if i3 != i0 {
                                    if i3 != i1 {
                                        if i3 != i2 {
                                            // Try this permutation
                                            tryAllOps(digits[i0], digits[i1], digits[i2], digits[i3]);
                                        }
                                    }
                                }
                                i3 = i3 + 1;
                            }
                        }
                    }
                    i2 = i2 + 1;
                }
            }
            i1 = i1 + 1;
        }
        i0 = i0 + 1;
    }
}

// Main program
print("=== Game 24 Solver ===");
print("");

// Generate 4 random digits (1-9)
digits[0] = random(9) + 1;
digits[1] = random(9) + 1;
digits[2] = random(9) + 1;
digits[3] = random(9) + 1;

print("Digits: ", digits[0], ", ", digits[1], ", ", digits[2], ", ", digits[3], "");
print("");
print("Finding all ways to make 24...");
print("");

// Find all solutions
solve();

print("");
if solutionCount == 0 {
    print("No solution found for these digits!");
} else {
    print("Total solutions found: ", solutionCount, " (includes duplicates)");
}

print("");
print("=== Game 24 Complete ===");
