// Opcode Benchmark Test - Designed to stress-test all key VM opcodes
// Version 1.0 - Comprehensive coverage for optimization analysis

#pragma appname "Opcode-Benchmark"
#pragma console on
#pragma consolesize "680x740"
#pragma consoleposition "30,50"
#pragma ListASM off
#pragma DumpASM off
#pragma PasteToClipboard on
#pragma CreateLog on
#pragma LogName "[default]"
#pragma asmdecimal on

// Global array for Section 6
array testArr.i[1000];

print("================================================");
print("        OPCODE BENCHMARK TEST");
print("================================================");
print("");

ITERATIONS = 10000;
INNER_LOOPS = 100;

// ============================================
// SECTION 1: Local Variable Operations (LFETCH/LSTORE)
// ============================================
print("Section 1: Local Variable Stress Test");

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

result.i = testLocalVars(ITERATIONS);
print("  Local vars result: ", result);

// ============================================
// SECTION 2: Arithmetic Operations (ADD/SUB/MUL/DIV)
// ============================================
print("Section 2: Arithmetic Stress Test");

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

result = testArithmetic(ITERATIONS);
print("  Arithmetic result: ", result);

// ============================================
// SECTION 3: Comparison Operations (EQ/NE/GT/LT/GTE/LTE)
// ============================================
print("Section 3: Comparison Stress Test");

func testComparisons(n.i) {
    count.i = 0;
    i.i = 0;

    while (i < n) {
        if (i > 5000) {
            count = count + 1;
        }
        if (i < 5000) {
            count = count + 1;
        }
        if (i == 5000) {
            count = count + 10;
        }
        if (i != 5000) {
            count = count + 1;
        }
        if (i >= 5000) {
            count = count + 1;
        }
        if (i <= 5000) {
            count = count + 1;
        }
        i = i + 1;
    }
    return count;
}

result = testComparisons(ITERATIONS);
print("  Comparisons result: ", result);

// ============================================
// SECTION 4: Function Call Overhead (CALL/RET)
// ============================================
print("Section 4: Function Call Stress Test");

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

result = testFunctionCalls(ITERATIONS);
print("  Function calls result: ", result);

// ============================================
// SECTION 5: Conditional Jumps (JZ/JMP)
// ============================================
print("Section 5: Conditional Jump Stress Test");

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

result = testJumps(ITERATIONS);
print("  Jumps result: ", result);

// ============================================
// SECTION 6: Array Operations
// ============================================
print("Section 6: Array Stress Test");

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

result = testArrays(ITERATIONS);
print("  Arrays result: ", result);

// ============================================
// SECTION 7: Float Operations
// ============================================
print("Section 7: Float Stress Test");

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

resultf.f = testFloats(ITERATIONS);
print("  Floats result: ", resultf);

// ============================================
// SECTION 8: Nested Loops (Combined stress)
// ============================================
print("Section 8: Nested Loop Stress Test");

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

result = testNestedLoops(100);
print("  Nested loops result: ", result);

// ============================================
// SECTION 9: Switch Statement
// ============================================
print("Section 9: Switch Statement Stress Test");

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

result = testSwitch(ITERATIONS);
print("  Switch result: ", result);

// ============================================
// SECTION 10: Increment/Decrement Operators
// ============================================
print("Section 10: Increment/Decrement Stress Test");

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

result = testIncDec(ITERATIONS);
print("  Inc/Dec result: ", result);

// ============================================
// SECTION 11: Logical Operations (AND/OR)
// ============================================
print("Section 11: Logical Operations Stress Test");

func testLogical(n.i) {
    count.i = 0;
    i.i = 0;

    while (i < n) {
        a.i = i > 1000;
        b.i = i < 9000;
        c.i = i > 2000;
        d.i = i < 8000;

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

result = testLogical(ITERATIONS);
print("  Logical result: ", result);

// ============================================
// SECTION 12: Mixed Heavy Computation
// ============================================
print("Section 12: Mixed Heavy Computation");

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

result = testMixed(1000);
print("  Mixed result: ", result);

// ============================================
// SUMMARY
// ============================================
print("");
print("================================================");
print("        BENCHMARK COMPLETE");
print("================================================");
print("");
print("Check profiler output for opcode statistics.");
print("Focus optimization on opcodes with:");
print("  1. Highest call counts");
print("  2. Highest total time");
print("  3. Highest per-call time");
