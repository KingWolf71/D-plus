// Test file for error reporting and type system
// This file tests the LJ type inference and locking system

#pragma appname "test error reporting"
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
#pragma floattolerance 0.001
#pragma GlobalStack 1024
#pragma FunctionStack 32
#pragma EvalStack 256
#pragma LocalStack 64
#pragma CreateLog off
#pragma DefaultFPS 32
#pragma ThreadKillWait 1800
#pragma asmdecimal on


// Test 1: First assignment to float (should warn: "variable a declared as float")
func test_float_declaration() {
    a = 5.3;     // WARNING: variable a declared as float
    print("Test 1: a =", a);
}

// Test 2: First assignment to string (should warn: "variable s declared as string")
func test_string_declaration() {
    s = "hello there";  // WARNING: variable s declared as string
    print("Test 2: s =", s);
}

// Test 3: Suffix conflict (should ERROR: "s is already declared as string")
// NOTE: This will cause compilation error - commented out for now
// func test_suffix_conflict() {
//     s = "test";    // s is string
//     s.f = 4.7;     // ERROR: s is already declared as string
// }

// Test 4: Type conversion float to string (should warn: "converting float to string")
func test_float_to_string() {
    t = "initial";   // WARNING: variable t declared as string
    t = 15.7;        // WARNING: converting float to string (FTOS)
    print("Test 4: t =", t);
}

// Test 5: Type conversion float to int (should warn: "converting float to int")
func test_float_to_int() {
    x = 10;      // x is INT (no warning for int)
    x = 3.14;    // WARNING: converting float to int (FTOI)
    print("Test 5: x =", x);
}

// Test 6: Type conversion int to float (should warn: "converting int to float")
func test_int_to_float() {
    y = 5.5;     // WARNING: variable y declared as float
    y = 10;      // WARNING: converting int to float (ITOF)
    print("Test 6: y =", y);
}

// Test 7: No warnings for int (default type)
func test_int_no_warning() {
    n = 42;      // INT - no warning (default type)
    print("Test 7: n =", n);
}

// Run all tests
print("=== Type System Tests ===");
print("");
test_float_declaration();
print("");
test_string_declaration();
print("");
test_float_to_string();
print("");
test_float_to_int();
print("");
test_int_to_float();
print("");
test_int_no_warning();
print("");
print("=== Tests Complete ===");
