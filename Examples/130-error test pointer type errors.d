/* Pointer Type Error Test - V1.20.26+
   This file contains INTENTIONAL ERRORS to demonstrate compile-time checking
   It should FAIL to compile with clear error messages

   To test: Try compiling this file and verify you get:
   "Variable 'x' is not a pointer - cannot use pointer field access (\i, \f, \s)"
*/

#pragma appname "Pointer-Type-Errors"
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

print("This should not compile!");

// ERROR TEST 1: Using \i on a regular integer variable
x.i = 42;
print(x\i);  // ERROR: x is not a pointer!

// If you got here, the type checking failed to catch the error
print("ERROR: Type checking did not work!");
