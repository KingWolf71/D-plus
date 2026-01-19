#pragma appname "String Concatenation Test"
#pragma decimals 3
#pragma console on
#pragma consolesize "680x740"
#pragma consoleposition "30,50"
#pragma ListASM on
#pragma FastPrint on
#pragma RunThreaded off
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

// Test 1: String + String
bstr.s = "Today" + "," + " is a great" + " " + "day";
print(bstr);

// Test 2: String + Integer
msg.s = "Count: " + 42;
print(msg);

// Test 3: String + Float
pi_msg.s = "Pi = " + 3.14159;
print(pi_msg);

// Test 4: Mixed concatenation from original test
bstr2.s = bstr + " " + 231.9961123;
printf("Result: %s\n", bstr2);

// Test 5: Expression result
calc.s = "22/7 = " + 22.0/7.0;
print(calc);

s1.s = "W";
printf("s1 = %s\n", s1);
s2.s = "W" + "X";
printf("s2 = %s\n", s2);
print("Done");
