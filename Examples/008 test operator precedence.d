// Test operator precedence for the expression in primes
#pragma appname "Operator Precedence Test"
#pragma console on
#pragma decimals 3
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

// Test: p=n/k*k!=n
// Should be: p = ((n/k)*k) != n
// Checks if n is NOT divisible by k

n = 9;
k = 3;

// Method 1: Using the compound expression
p1 = n/k*k!=n;
print("n=", n, " k=", k);
print("p1 = n/k*k!=n = ", p1);
print("Expected: 0 (since 9 is divisible by 3)");
print("");

// Method 2: Breaking it down with parentheses
temp = n/k;
print("n/k = ", temp);
temp2 = temp*k;
print("(n/k)*k = ", temp2);
p2 = temp2 != n;
print("p2 = (n/k)*k != n = ", p2);
print("");

// Test with non-divisible number
n = 11;
k = 3;
p3 = n/k*k!=n;
print("n=", n, " k=", k);
print("p3 = n/k*k!=n = ", p3);
print("Expected: 1 (since 11 is NOT divisible by 3)");
