/* Closer replica of test 64 - uses i in multiple loops */
#pragma console on
#pragma ListASM on
#pragma consolesize "680x740"
#pragma consoleposition "30,50"
#pragma asmdecimal on

// Functions first
func swap(a, b) {
    temp.i = a\i;
    a\i = b\i;
    b\i = temp;
}

func findMin(ptr, size) {
    min.i = ptr\i;
    p = ptr;
    i = 1;
    p = p + 1;
    while i < size {
        if p\i < min {
            min = p\i;
        }
        p = p + 1;
        i = i + 1;
    }
    return min;
}

// Main code - like test 64 from Test 3 onwards
node1.i = 100;
node2.i = 200;
node3.i = 300;
node4.i = 400;

array *nodes[4];
nodes[0] = &node1;
nodes[1] = &node2;
nodes[2] = &node3;
nodes[3] = &node4;

print("Traversing pointer structure: ");
i = 0;
while i < 4 {
    print("i=", i, " val=", nodes[i]\i, "");
    if i < 3 {
        print(" -> ");
    }
    i = i + 1;
}
print("");
