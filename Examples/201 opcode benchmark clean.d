// Opcode Benchmark Test - Clean Version (no print in hot paths)
// Version 2.0 - Pure computation, results printed only at end

#pragma appname "Opcode-Benchmark-Clean"
#pragma console on
#pragma consolesize "680x740"
#pragma consoleposition "30,50"
#pragma ListASM off
#pragma DumpASM off
#pragma PasteToClipboard on
#pragma CreateLog on
#pragma LogName "[default]"
#pragma asmdecimal on

// Global array for array tests
array testArr.i[1000];

// Global results storage
r1.i = 0;
r2.i = 0;
r3.i = 0;
r4.i = 0;
r5.i = 0;
r6.i = 0;
r7.f = 0.0;
r8.i = 0;
r9.i = 0;
r10.i = 0;
r11.i = 0;
r12.i = 0;

ITERATIONS = 50000;

// ============================================
// TEST 1: Local Variable Operations (LFETCH/LSTORE)
// ============================================
func testLocalVars(n.i) {
    a.i = 0;
    b.i = 0;
    c.i = 0;
    d.i = 0;
    e.i = 0;
    i.i = 0;

    while (i < n) {
        a = i;
        b = a;
        c = b;
        d = c;
        e = d;
        a = e;
        b = a + 1;
        c = b + 1;
        d = c + 1;
        e = d + 1;
        i = i + 1;
    }
    return e;
}

// ============================================
// TEST 2: Arithmetic Operations (ADD/SUB/MUL/DIV)
// ============================================
func testArithmetic(n.i) {
    sum.i = 0;
    i.i = 0;

    while (i < n) {
        a.i = i * 3;
        b.i = a + 7;
        c.i = b - 2;
        d.i = c * 2;
        e.i = d / 3;
        sum = sum + e;
        i = i + 1;
    }
    return sum;
}

// ============================================
// TEST 3: Comparison Operations (EQ/NE/GT/LT/GTE/LTE)
// ============================================
func testComparisons(n.i) {
    count.i = 0;
    i.i = 0;

    while (i < n) {
        if (i > 25000) {
            count = count + 1;
        }
        if (i < 25000) {
            count = count + 1;
        }
        if (i == 25000) {
            count = count + 10;
        }
        if (i != 25000) {
            count = count + 1;
        }
        if (i >= 25000) {
            count = count + 1;
        }
        if (i <= 25000) {
            count = count + 1;
        }
        i = i + 1;
    }
    return count;
}

// ============================================
// TEST 4: Function Call Overhead (CALL/RET)
// ============================================
func addOne(x.i) {
    return x + 1;
}

func addTwo(x.i) {
    return addOne(addOne(x));
}

func addFour(x.i) {
    return addTwo(addTwo(x));
}

func testFunctionCalls(n.i) {
    sum.i = 0;
    i.i = 0;

    while (i < n) {
        sum = addFour(sum);
        i = i + 1;
    }
    return sum;
}

// ============================================
// TEST 5: Conditional Jumps (JZ/JMP)
// ============================================
func testJumps(n.i) {
    count.i = 0;
    i.i = 0;

    while (i < n) {
        j.i = 0;
        while (j < 10) {
            if (j < 5) {
                count = count + 1;
            } else {
                count = count + 2;
            }
            j = j + 1;
        }
        i = i + 1;
    }
    return count;
}

// ============================================
// TEST 6: Array Operations
// ============================================
func testArrays(n.i) {
    i.i = 0;
    while (i < 1000) {
        testArr[i] = i * 2;
        i = i + 1;
    }

    sum.i = 0;
    j.i = 0;
    while (j < n) {
        idx.i = j % 1000;
        sum = sum + testArr[idx];
        j = j + 1;
    }
    return sum;
}

// ============================================
// TEST 7: Float Operations
// ============================================
func testFloats(n.i) {
    sum.f = 0.0;
    i.i = 0;

    while (i < n) {
        a.f = i * 1.5;
        b.f = a + 2.5;
        c.f = b * 0.75;
        d.f = c / 1.25;
        sum = sum + d;
        i = i + 1;
    }
    return sum;
}

// ============================================
// TEST 8: Nested Loops (Combined stress)
// ============================================
func testNestedLoops(n.i) {
    total.i = 0;
    i.i = 0;

    while (i < n) {
        j.i = 0;
        while (j < 10) {
            k.i = 0;
            while (k < 10) {
                total = total + 1;
                k = k + 1;
            }
            j = j + 1;
        }
        i = i + 1;
    }
    return total;
}

// ============================================
// TEST 9: Switch Statement
// ============================================
func testSwitch(n.i) {
    count.i = 0;
    i.i = 0;

    while (i < n) {
        v.i = i % 5;
        switch (v) {
            case 0:
                count = count + 1;
            case 1:
                count = count + 2;
            case 2:
                count = count + 3;
            case 3:
                count = count + 4;
            default:
                count = count + 5;
        }
        i = i + 1;
    }
    return count;
}

// ============================================
// TEST 10: Increment/Decrement Operators
// ============================================
func testIncDec(n.i) {
    a.i = 0;
    b.i = n;
    i.i = 0;

    while (i < n) {
        a++;
        b--;
        i++;
    }
    return a + b;
}

// ============================================
// TEST 11: Logical Operations (AND/OR)
// ============================================
func testLogical(n.i) {
    count.i = 0;
    i.i = 0;

    while (i < n) {
        a.i = i > 5000;
        b.i = i < 45000;
        c.i = i > 10000;
        d.i = i < 40000;

        if (a && b) {
            count = count + 1;
        }
        if (c || d) {
            count = count + 1;
        }
        i = i + 1;
    }
    return count;
}

// ============================================
// TEST 12: Mixed Heavy Computation (Fibonacci)
// ============================================
func fibonacci(n.i) {
    if (n <= 1) {
        return n;
    }
    a.i = 0;
    b.i = 1;
    i.i = 2;
    while (i <= n) {
        temp.i = a + b;
        a = b;
        b = temp;
        i = i + 1;
    }
    return b;
}

func testMixed(n.i) {
    sum.i = 0;
    i.i = 0;

    while (i < n) {
        fib.i = fibonacci(20);
        sum = sum + fib;
        i = i + 1;
    }
    return sum;
}

// ============================================
// RUN ALL TESTS (no print statements here)
// ============================================
r1 = testLocalVars(ITERATIONS);
r2 = testArithmetic(ITERATIONS);
r3 = testComparisons(ITERATIONS);
r4 = testFunctionCalls(ITERATIONS);
r5 = testJumps(ITERATIONS);
r6 = testArrays(ITERATIONS);
r7 = testFloats(ITERATIONS);
r8 = testNestedLoops(500);
r9 = testSwitch(ITERATIONS);
r10 = testIncDec(ITERATIONS);
r11 = testLogical(ITERATIONS);
r12 = testMixed(5000);

// ============================================
// RESULTS (print only after all computation)
// ============================================
print("================================================");
print("     OPCODE BENCHMARK - CLEAN (v2.0)");
print("================================================");
print("Iterations: ", ITERATIONS);
print("");
print("Results:");
print("  1. Local vars:    ", r1);
print("  2. Arithmetic:    ", r2);
print("  3. Comparisons:   ", r3);
print("  4. Function calls:", r4);
print("  5. Jumps:         ", r5);
print("  6. Arrays:        ", r6);
print("  7. Floats:        ", r7);
print("  8. Nested loops:  ", r8);
print("  9. Switch:        ", r9);
print(" 10. Inc/Dec:       ", r10);
print(" 11. Logical:       ", r11);
print(" 12. Mixed/Fib:     ", r12);
print("");
print("================================================");
print("Check profiler for opcode timing data.");
print("PRT* opcodes should be minimal now.");
print("================================================");
