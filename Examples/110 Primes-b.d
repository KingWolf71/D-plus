/*
 Simple prime number generator
 Uses break to exit inner loop early
 */

#pragma appname "Primes-B"
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

count = 1;
n = 1;
limit = 100;
while (n < limit) {
    k=3;
    p=1;
    n=n+2;
    while (k*k<=n) {
        if (n/k*k==n) {
            p=0;
            break;  // Found a divisor, no need to continue
        }
        k=k+2;
    }
    if (p) {
        print(n, " is prime");
        count++;
    }
}
print("Total primes found: ", count );
