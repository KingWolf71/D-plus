#pragma appname "Float Demo"
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

#define A1(x) (x) + 1
#define B2(x) A1((x) * 2)
#define C3(x) B2((x) - 3)
#define D4(x) C3((x) * (x))
#define E5(x) D4((x) + 5)

#define MAX(a,b) ((a) > (b) ? (a) : (b))
#define SQUARE(x) ((x) * (x)) 
#define DOUBLE_AND_SQUARE(x) SQUARE((x) + (x))
#define SUM_THEN_DOUBLE_AND_SQUARE(a, b) DOUBLE_AND_SQUARE((a) + (b))

n = 1 + 4;
print(n);

print(A1(4));

ar = 10.77654;
print( ar );

fl = 10.77654;
fl = fl * 91.023;
ex.f = 2e10;

print( fl, ",", ex - fl);

bstr.s = "Today" + "," + "is a great" + " " + "day";
print(bstr+"!","!!", " ",22.0/7.0);
bstr2.s = bstr + 231.9961123;
print("And now?", bstr2);

// Automatic conversion to float 
print( fl + ar);

f1 = 1.41;
m = 8.1;

fl = 6.8741;
l.f = 4.7/m + m;
big = 211789;

print( l, " , ", fl + fl, " ", #PI );
ex2.f = 789.123;

print( MAX(ex2,fl) );
print( MAX(10,big) );

//should print 100
print("macro1=", SUM_THEN_DOUBLE_AND_SQUARE(2, 3));
conv2f.f = SUM_THEN_DOUBLE_AND_SQUARE(2.25, 3.33);
print("macro2=", conv2f);
print("should be 157=",E5(4));
print(A1(4));
n = A1(4);
print(n);

/*
//Output

5
5
10.7765
980.9130,19999999019.0870
Today,is a great day!!! 3.1429
And now?Today,is a great day231.9961
991.6895
8.6802 , 13.7482 3.1416
789.1230
211789.0000
macro1=100
macro2=124.5456
should be 157=157
5
5

*/
