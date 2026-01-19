/* Pointer array test with loop */
#pragma console on
#pragma ListASM on
#pragma consolesize "680x740"
#pragma consoleposition "30,50"
#pragma asmdecimal on

node1.i = 100;
node2.i = 200;
node3.i = 300;
node4.i = 400;

array *nodes[4];
nodes[0] = &node1;
nodes[1] = &node2;
nodes[2] = &node3;
nodes[3] = &node4;

print("Direct access:");
print("nodes[0]\\i = ", nodes[0]\i, "");
print("nodes[1]\\i = ", nodes[1]\i, "");
print("nodes[2]\\i = ", nodes[2]\i, "");
print("nodes[3]\\i = ", nodes[3]\i, "");

print("Loop access:");
i = 0;
while i < 4 {
    print("i=", i, " nodes[i]\\i = ", nodes[i]\i, "");
    i = i + 1;
}
