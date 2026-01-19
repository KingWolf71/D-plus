/* Pointer array test with function and loop - mimics test 64 structure */
#pragma console on
#pragma ListASM on
#pragma consolesize "680x740"
#pragma consoleposition "30,50"
#pragma asmdecimal on

// Dummy function first (like test 64)
func dummy(x) {
    return x + 1;
}

node1.i = 100;
node2.i = 200;
node3.i = 300;
node4.i = 400;

array *nodes[4];
nodes[0] = &node1;
nodes[1] = &node2;
nodes[2] = &node3;
nodes[3] = &node4;

print("Loop access with function above:");
i = 0;
while i < 4 {
    print("i=", i, " nodes[i]\\i = ", nodes[i]\i, "");
    i = i + 1;
}
