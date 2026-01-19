/* Basic Pointer Test (V1.20.24+)
   Tests fundamental pointer operations with explicit type syntax
   Uses: ptr\i (integer), ptr\f (float), ptr\s (string)
*/

#pragma appname "Pointer-Basic-Test"
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
#pragma GlobalStack 1024
#pragma FunctionStack 32
#pragma EvalStack 256
#pragma LocalStack 64
#pragma CreateLog off
#pragma DefaultFPS 32
#pragma ThreadKillWait 1800
#pragma asmdecimal on

// Test 1: Basic integer pointer operations
print("=== Test 1: Basic Integer Pointer Operations ===");

x.i = 42;
printf("x = %d\n", x);

ptr = &x;              // Get address of x
printf("ptr\\i = %d\n", ptr\i);    // Should print 42
assertEqual(42, ptr\i);

ptr\i = 100;           // Modify x through pointer
print("After ptr\\i = 100:");

printf("x = %d\n", x);             // Should print 100
assertEqual(100, x);
printf("ptr\\i = %d\n", ptr\i);    // Should print 100
assertEqual(100, ptr\i);

// Test 2: Multiple pointers to same variable
print("");
print("=== Test 2: Multiple Pointers ===");

y.i = 9;
p1 = &y;
p2 = &y;

printf("y = %d\n", y);
assertEqual(9, y);

p1\i = 20;
print("After p1\\i = 20:");
printf("y = %d, p2\\i = %d\n", y, p2\i);  // Both should print 20
assertEqual(20, y);
assertEqual(20, p2\i);

// Test 3: Pointer reassignment
print("\n=== Test 3: Pointer Reassignment ===");

a.i = 10;
b.i = 20;
p = &a;

printf("a = %d, b = %d\n", a, b);
printf("p\\i = %d (pointing to a)\n", p\i);  // Should print 10
assertEqual(10, p\i);

p = &b;             // Reassign pointer to b
print("After p = &b:");
printf("p\\i = %d (pointing to b)\n", p\i);  // Should print 20
assertEqual(20, p\i);

p\i = 99;
print("After p\\i = 99:");
printf("a = %d, b = %d\n", a, b);  // a=10, b=99
assertEqual(10, a);
assertEqual(99, b);

// Test 4: Float pointers
print("\n=== Test 4: Float Pointers ===");

f.f = 3.14;
fp = &f;

printf("f = %f\n", f);
printf("fp\\f = %f\n", fp\f);
assertFloatEqual(3.14, fp\f);

fp\f = 2.718;
print("After fp\\f = 2.718:");
printf("f = %f\n", f);
assertFloatEqual(2.718, f);

// Test 5: String pointers
print("\n=== Test 5: String Pointers ===");

s.s = "Hello";
sp = &s;

printf("s = %s\n", s);
printf("sp\\s = %s\n", sp\s);
assertStringEqual("Hello", sp\s);

sp\s = "World";
print("After sp\\s = 'World':");
printf("sp\\s = %s\n", sp\s);
printf("s = %s\n", s);
assertStringEqual("World", s);

print("");
print("=== All Basic Pointer Tests Complete ===");
print("  - Integer pointers with ptr\\i: PASSED");
print("  - Float pointers with ptr\\f: PASSED");
print("  - String pointers with ptr\\s: PASSED");
print("  - Pointer reassignment: PASSED");
print("  - Multiple pointers: PASSED");
print("");
