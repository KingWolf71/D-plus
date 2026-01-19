/* Binomial Transform Test
   -b version: Uses for loops and break for early mismatch detection
   Based on: https://rosettacode.org/wiki/Binomial_transform

   NOTE: D+AI doesn't support passing arrays as parameters,
   so we use global arrays that functions access directly.
*/

#pragma appname "Binomial-Transform-B"
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
    for (fi = 2; fi <= num; fi++) {  // Use 'fi' to avoid collision with global 'idx'
        result = result * fi;
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
    for (n = 0; n < gSize; n++) {
        sum = 0;
        for (k = 0; k <= n; k++) {
            sum = sum + binomial(n, k) * gInput[k];
        }
        gOutput[n] = sum;
    }
}

// Inverse transform: gOutput[n] = sum((-1)^(n-k) * binomial(n,k) * gInput[k])
function btInverse() {
    for (n = 0; n < gSize; n++) {
        sum = 0;
        for (k = 0; k <= n; k++) {
            sign = 1;
            if ((n - k) % 2 == 1) {
                sign = 0 - 1;
            }
            sum = sum + sign * binomial(n, k) * gInput[k];
        }
        gOutput[n] = sum;
    }
}

// Self-inverting transform: alternating signs based on k
function btSelfInverting() {
    for (n = 0; n < gSize; n++) {
        sum = 0;
        for (k = 0; k <= n; k++) {
            sign = 1;
            if (k % 2 == 1) {
                sign = 0 - 1;
            }
            sum = sum + sign * binomial(n, k) * gInput[k];
        }
        gOutput[n] = sum;
    }
}

// =============================================================================
// TESTS
// =============================================================================

print("========================================");
print("   BINOMIAL TRANSFORM TEST (-b)");
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
for (idx = 0; idx < 8; idx++) {
    gInput[idx] = catalan[idx];
}

// Forward transform
btForward();

// Copy result to transformed array
for (idx = 0; idx < 8; idx++) {
    transformed[idx] = gOutput[idx];
}

print("Forward transform:  [", transformed[0], ", ", transformed[1], ", ", transformed[2], ", ", transformed[3], ", ", transformed[4], ", ", transformed[5], ", ", transformed[6], ", ", transformed[7], "]");

// Now do inverse: copy transformed to gInput
for (idx = 0; idx < 8; idx++) {
    gInput[idx] = transformed[idx];
}

// Inverse transform
btInverse();

// Copy result to recovered array
for (idx = 0; idx < 8; idx++) {
    recovered[idx] = gOutput[idx];
}

print("Inverse (recovered):[", recovered[0], ", ", recovered[1], ", ", recovered[2], ", ", recovered[3], ", ", recovered[4], ", ", recovered[5], ", ", recovered[6], ", ", recovered[7], "]");

// Compare arrays with early break on mismatch
match = 1;
for (idx = 0; idx < 8; idx++) {
    if (catalan[idx] != recovered[idx]) {
        match = 0;
        break;  // No need to check further
    }
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
for (idx = 0; idx < 6; idx++) {
    gInput[idx] = simple[idx];
}

// First self-inverting transform
btSelfInverting();

// Copy result to first array
for (idx = 0; idx < 6; idx++) {
    first[idx] = gOutput[idx];
}

print("First transform: [", first[0], ", ", first[1], ", ", first[2], ", ", first[3], ", ", first[4], ", ", first[5], "]");

// Copy first to gInput for second transform
for (idx = 0; idx < 6; idx++) {
    gInput[idx] = first[idx];
}

// Second self-inverting transform
btSelfInverting();

// Copy result to second array
for (idx = 0; idx < 6; idx++) {
    second[idx] = gOutput[idx];
}

print("Second transform:[", second[0], ", ", second[1], ", ", second[2], ", ", second[3], ", ", second[4], ", ", second[5], "]");

// Compare simple and second with early break on mismatch
match = 1;
for (idx = 0; idx < 6; idx++) {
    if (simple[idx] != second[idx]) {
        match = 0;
        break;  // No need to check further
    }
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
