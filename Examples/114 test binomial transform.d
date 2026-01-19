/* Binomial Transform Test
   Based on: https://rosettacode.org/wiki/Binomial_transform

   NOTE: D+AI doesn't support passing arrays as parameters,
   so we use global arrays that functions access directly.
*/

#pragma appname "Binomial Transform"
#pragma decimals 0
#pragma console on
#pragma consolesize "680x740"
#pragma consoleposition "30,50"
#pragma ListASM off
#pragma FastPrint on
#pragma ftoi "truncate"
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
#pragma asmdecimal on

// =============================================================================
// GLOBAL ARRAYS (used by transform functions)
// =============================================================================
array gInput.i[8];
array gOutput.i[8];
gSize = 8;

// =============================================================================
// HELPER FUNCTIONS
// =============================================================================

function factorial(num) {
    if (num < 2) { return 1; }
    result = 1;
    fi = 2;  // Use 'fi' to avoid collision with global 'idx'
    while (fi <= num) {
        result = result * fi;
        fi = fi + 1;
    }
    return result;
}

function binomial(n, k) {
    return factorial(n) / factorial(n - k) / factorial(k);
}

// =============================================================================
// BINOMIAL TRANSFORM FUNCTIONS
// Work on global arrays: gInput -> gOutput
// =============================================================================

// Forward transform: gOutput[n] = sum(binomial(n,k) * gInput[k]) for k=0 to n
function btForward() {
    n = 0;
    while (n < gSize) {
        sum = 0;
        k = 0;
        while (k <= n) {
            sum = sum + binomial(n, k) * gInput[k];
            k = k + 1;
        }
        gOutput[n] = sum;
        n = n + 1;
    }
}

// Inverse transform: gOutput[n] = sum((-1)^(n-k) * binomial(n,k) * gInput[k])
function btInverse() {
    n = 0;
    while (n < gSize) {
        sum = 0;
        k = 0;
        while (k <= n) {
            sign = 1;
            if ((n - k) % 2 == 1) {
                sign = 0 - 1;
            }
            sum = sum + sign * binomial(n, k) * gInput[k];
            k = k + 1;
        }
        gOutput[n] = sum;
        n = n + 1;
    }
}

// Self-inverting transform: alternating signs based on k
function btSelfInverting() {
    n = 0;
    while (n < gSize) {
        sum = 0;
        k = 0;
        while (k <= n) {
            sign = 1;
            if (k % 2 == 1) {
                sign = 0 - 1;
            }
            sum = sum + sign * binomial(n, k) * gInput[k];
            k = k + 1;
        }
        gOutput[n] = sum;
        n = n + 1;
    }
}

// =============================================================================
// TESTS
// =============================================================================

print("========================================");
print("   BINOMIAL TRANSFORM TEST");
print("========================================");
print("");

// Test 1: Factorial
print("=== Factorial Tests ===");
print("0! = ", factorial(0));
print("1! = ", factorial(1));
print("5! = ", factorial(5));
print("6! = ", factorial(6));
print("");

// Test 2: Binomial coefficients
print("=== Binomial Coefficient Tests ===");
print("C(5,0) = ", binomial(5, 0));
print("C(5,1) = ", binomial(5, 1));
print("C(5,2) = ", binomial(5, 2));
print("C(5,3) = ", binomial(5, 3));
print("C(5,5) = ", binomial(5, 5));
print("C(10,5) = ", binomial(10, 5));
print("");

// Test 3: Forward and Inverse transforms on Catalan numbers
print("=== Forward/Inverse Transform Test ===");

// Original sequence (Catalan numbers)
array catalan.i[8];
catalan[0] = 1;
catalan[1] = 1;
catalan[2] = 2;
catalan[3] = 5;
catalan[4] = 14;
catalan[5] = 42;
catalan[6] = 132;
catalan[7] = 429;

array transformed.i[8];
array recovered.i[8];

// Print original
print("Original (Catalan): [", catalan[0], ", ", catalan[1], ", ", catalan[2], ", ", catalan[3], ", ", catalan[4], ", ", catalan[5], ", ", catalan[6], ", ", catalan[7], "]");

// Copy catalan to gInput for forward transform
gSize = 8;
idx = 0;
while (idx < 8) {
    gInput[idx] = catalan[idx];
    idx = idx + 1;
}

// Forward transform
btForward();

// Copy result to transformed array
idx = 0;
while (idx < 8) {
    transformed[idx] = gOutput[idx];
    idx = idx + 1;
}

print("Forward transform:  [", transformed[0], ", ", transformed[1], ", ", transformed[2], ", ", transformed[3], ", ", transformed[4], ", ", transformed[5], ", ", transformed[6], ", ", transformed[7], "]");

// Now do inverse: copy transformed to gInput
idx = 0;
while (idx < 8) {
    gInput[idx] = transformed[idx];
    idx = idx + 1;
}

// Inverse transform
btInverse();

// Copy result to recovered array
idx = 0;
while (idx < 8) {
    recovered[idx] = gOutput[idx];
    idx = idx + 1;
}

print("Inverse (recovered):[", recovered[0], ", ", recovered[1], ", ", recovered[2], ", ", recovered[3], ", ", recovered[4], ", ", recovered[5], ", ", recovered[6], ", ", recovered[7], "]");

// Compare arrays
match = 1;
idx = 0;
while (idx < 8) {
    if (catalan[idx] != recovered[idx]) {
        match = 0;
    }
    idx = idx + 1;
}

if (match == 1) {
    print("PASS: Forward then Inverse recovers original!");
} else {
    print("FAIL: Sequences don't match!");
}
print("");

// Test 4: Self-inverting transform
print("=== Self-Inverting Transform Test ===");

// Simple sequence
array simple.i[6];
simple[0] = 1;
simple[1] = 2;
simple[2] = 3;
simple[3] = 4;
simple[4] = 5;
simple[5] = 6;

array first.i[6];
array second.i[6];

print("Original: [", simple[0], ", ", simple[1], ", ", simple[2], ", ", simple[3], ", ", simple[4], ", ", simple[5], "]");

// Copy simple to gInput
gSize = 6;
idx = 0;
while (idx < 6) {
    gInput[idx] = simple[idx];
    idx = idx + 1;
}

// First self-inverting transform
btSelfInverting();

// Copy result to first array
idx = 0;
while (idx < 6) {
    first[idx] = gOutput[idx];
    idx = idx + 1;
}

print("First transform: [", first[0], ", ", first[1], ", ", first[2], ", ", first[3], ", ", first[4], ", ", first[5], "]");

// Copy first to gInput for second transform
idx = 0;
while (idx < 6) {
    gInput[idx] = first[idx];
    idx = idx + 1;
}

// Second self-inverting transform
btSelfInverting();

// Copy result to second array
idx = 0;
while (idx < 6) {
    second[idx] = gOutput[idx];
    idx = idx + 1;
}

print("Second transform:[", second[0], ", ", second[1], ", ", second[2], ", ", second[3], ", ", second[4], ", ", second[5], "]");

// Compare simple and second
match = 1;
idx = 0;
while (idx < 6) {
    if (simple[idx] != second[idx]) {
        match = 0;
    }
    idx = idx + 1;
}

if (match == 1) {
    print("PASS: Self-inverting transform works!");
} else {
    print("FAIL: Double transform doesn't recover original!");
}

print("");
print("========================================");
print("   TEST COMPLETE");
print("========================================");
