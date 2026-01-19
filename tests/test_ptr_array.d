/* Minimal pointer array test */
#pragma console on
#pragma ListASM on
#pragma consolesize "680x740"
#pragma consoleposition "30,50"
#pragma asmdecimal on

node1.i = 100;
node2.i = 200;
node3.i = 300;

array *nodes[3];
nodes[0] = &node1;
nodes[1] = &node2;
nodes[2] = &node3;

print("node1 = ", node1, "");
print("node2 = ", node2, "");
print("node3 = ", node3, "");

print("nodes[0]\\i = ", nodes[0]\i, "");
print("nodes[1]\\i = ", nodes[1]\i, "");
print("nodes[2]\\i = ", nodes[2]\i, "");
