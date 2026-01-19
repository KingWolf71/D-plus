#pragma appname "Macro Float Test"
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

#define SQUARE(x) ((x) * (x))
#define DOUBLE_AND_SQUARE(x) SQUARE((x) + (x))
#define SUM_THEN_DOUBLE_AND_SQUARE(a, b) DOUBLE_AND_SQUARE((a) + (b))

// Test with integers first
print("Integer test: ", SUM_THEN_DOUBLE_AND_SQUARE(2, 3));

// Test with floats
print("Float test: ", SUM_THEN_DOUBLE_AND_SQUARE(2.25, 3.33));

// Simple float addition
f1.f = 2.25;
f2.f = 3.33;
sum.f = f1 + f2;
print("Simple float add: ", sum);

// Test: does the issue happen with literal floats?
test.f = 2.25 + 3.33;
print("Literal float add: ", test);
