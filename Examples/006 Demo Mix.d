#pragma appname "Demo Mix"
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

print( "First line" );
print("");

a = (-1 * ((-1 * (5 * 15)) / 10));
print(a);
b = -a;
print(b);
print(-b);
print(-(1));

/*
  Hello world
 */
print("Hello, World!");

/*
  Show Ident and Integers
 */
phoenix_number = 142857;
print(phoenix_number);

/*** test printing, embedded \n and comments with lots of '*' ***/
print(42);
print("");
print("");
print("Hello World");
print("Good Bye");
print("ok");

print(- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -+ + +5);
print(((((((((3 + 2) * ((((((2))))))))))))));
 
if (1) { if (1) { if (1) { if (1) { if (1) { print(15); } } } } }
 
/* fibonacci of 44 is 701408733 */

 
n = 44;
i = 1;
a = 0;
b = 1;
while (i < n) {
    w = a + b;
    a = b;
    b = w;
    i++;
}
print(w);

 
/* 12 factorial is 479001600 */
 
n = 12;
result = 1;
i = 1;
while (i <= n) {
    result *= i;
    i++;
}
print(result);

 
/* Compute the gcd of 1071, 1029:  21 */
 
a = 1071;
b = 1029;
 
while (b != 0) {
    new_a = b;
    b     = a % b;
    a     = new_a;
}
print(a);
print("");
 
 
/* FizzBuzz */
i = 1;
while (i <= 25) {
    if (!(i % 15))
        print("FizzBuzz");
    else if (!(i % 3))
        print("Fizz");
    else if (!(i % 5))
        print("Buzz");
    else
        print(i);

    i++;
}

print("");

/*
 Simple prime number generator
 */
count = 1;
n = 1;
limit = 100;
while (n < limit) {
    k=3;
    p=1;
    n=n+2;
    while ((k*k<=n) && (p)) {
        p=n/k*k!=n;
        k=k+2;
    }
    if (p) {
        print(n, " is prime");
        count++;
    }
}
print("Total primes found: ", count); 
print( "Ended" );



