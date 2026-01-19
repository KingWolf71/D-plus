// === D+AI Array Sort Stress Test ===
// -b version: Uses for loops and break for early exit
// Tests sorting 5000 float elements using quicksort
// Prints every 100th element to verify sorted order

#pragma appname "Quicksort-B"
#pragma decimals 3
#pragma console on
#pragma consolesize "680x740"
#pragma consoleposition "30,50"
#pragma ListASM on
#pragma FastPrint on
#pragma RunThreaded on
#pragma ftoi "truncate"
#pragma version on
#pragma modulename on
#pragma PasteToClipboard on
#pragma floattolerance 0.0001
#pragma GlobalStack 64000
#pragma FunctionStack 64000
#pragma EvalStack 32000
#pragma LocalStack 1024
#pragma CreateLog off
#pragma DefaultFPS 32
#pragma ThreadKillWait 1800
#pragma asmdecimal on

#define		ELEMENTS 50000
//#define		ELEMENTS 200

print("=================================");
print("Array Sort Stress Test (-b)");
print(ELEMENTS, " float elements - Quicksort");
print("=================================");
print("");

// Declare array of ELEMENTS floats


array data.f[ELEMENTS];

// Fill array with random values
print("Filling array with ",  ELEMENTS," random values...");
rnd.f = 0.0;

for (i = 0; i < ELEMENTS; i++) {
	rnd = (random(1000, 40000000) + 0.1 )/ random(500,257733);
    data[i] = rnd;
}

print("Array filled.");
print("");

// Print first few elements before sort
print("Before sort - first 10 elements:");
print("  data[0] = ", data[0]);
print("  data[1] = ", data[1]);
print("  data[2] = ", data[2]);
print("  data[9] = ", data[9]);
print("");

// Quicksort implementation
function quicksort(arr_slot, left, right) {
    if (left < right) {
        // Partition
        pivot_idx = partition(arr_slot, left, right);

        // Recursively sort left and right partitions
        quicksort(arr_slot, left, pivot_idx - 1);
        quicksort(arr_slot, pivot_idx + 1, right);
    }
}

function partition(arr_slot, left, right) {
    // Use rightmost element as pivot
    // V1.022.71: Type annotation (.f) creates local automatically - shadows global 'i'
    pivot.f = data[right];
    i.i = left - 1;    // Type annotation = local (shadows global i)

    for (j.i = left; j < right; j++) {
        if (data[j] <= pivot) {
            i++;
            // Swap data[i] and data[j]
            temp.f = data[i];  // Type annotation = local
            data[i] = data[j];
            data[j] = temp;
        }
    }

    // Place pivot in correct position
    i++;
    temp2.f = data[i];  // Type annotation = local
    data[i] = data[right];
    data[right] = temp2;

    return i;
}

// Sort the array
print("Sorting array using quicksort...");
quicksort(0, 0, (ELEMENTS - 1) );
print("Sort complete!");
print("");

// Print after sort - first few elements
print("After sort - first 10 elements:");
print("  data[0] = ", data[0]);
print("  data[1] = ", data[1]);
print("  data[2] = ", data[2]);
print("  data[9] = ", data[9]);
print("");

// Print every 100th element to verify sort
print("Every 100th element (should be ascending):");
print("=================================");
for (i = 0; i < ELEMENTS; i += 100) {
    print("  data[", i, "] = ", data[i]);
}
print("=================================");
print("");

// Verify sorted order - break on first error
print("Verifying array is sorted...");
errors = 0;
for (i = 0; i < (ELEMENTS - 1); i++) {
    if (data[i] > data[i + 1]) {
        print("ERROR: data[", i, "] = ", data[i], " > data[", i + 1, "] = ", data[i + 1]);
        errors = errors + 1;
        break;  // Stop on first error
    }
}

if (errors == 0) {
    print("PASS: All ", ELEMENTS - 1, " adjacent pairs are in correct order!");
} else {
    print("FAIL: Found error in sort order");
}
print("");

// Performance summary
print("=================================");
print("Stress Test Complete!");
print("Array size: ", ELEMENTS, " elements");
print("Total comparisons: ~O(n log n)");
print("Specialized opcodes used:");
print("  - ARRFETCH_FLT_G_OPT");
print("  - ARRSTORE_FLT_G_OPT_OPT");
print("  - ARRSTORE_FLT_G_OPT_STACK");
print("=================================");
