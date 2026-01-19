// D+AI v1.038.0 - SpiderBasic Runtime Builtins Test
// Tests Math, String, Cipher, and JSON functions

#pragma console on
#pragma consolesize "680x740"
#pragma consoleposition "30,50"
#pragma asmdecimal on

print("=== D+AI v1.038.0 Builtins Test ===\n");

// ============================================
// MATH LIBRARY TESTS
// ============================================
print("\n--- Math Library ---\n");

// Trigonometric functions (radians)
pi.f = 3.14159265358979;
print("sin(pi/2) = "); print(sin(pi / 2.0)); print("\n");
print("cos(0) = "); print(cos(0.0)); print("\n");
print("tan(pi/4) = "); print(tan(pi / 4.0)); print("\n");

// Inverse trig
print("asin(1) = "); print(asin(1.0)); print("\n");
print("acos(0) = "); print(acos(0.0)); print("\n");
print("atan(1) = "); print(atan(1.0)); print("\n");
print("atan2(1,1) = "); print(atan2(1.0, 1.0)); print("\n");

// Hyperbolic
print("sinh(0) = "); print(sinh(0.0)); print("\n");
print("cosh(0) = "); print(cosh(0.0)); print("\n");
print("tanh(0) = "); print(tanh(0.0)); print("\n");

// Logarithms and exponentials
print("log(2.718) = "); print(log(2.718281828)); print("\n");
print("log10(100) = "); print(log10(100.0)); print("\n");
print("exp(1) = "); print(exp(1.0)); print("\n");

// Rounding functions
print("floor(3.7) = "); print(floor(3.7)); print("\n");
print("ceil(3.2) = "); print(ceil(3.2)); print("\n");
print("round(3.5) = "); print(round(3.5)); print("\n");
print("sign(-5) = "); print(sign(-5.0)); print("\n");

// Float operations
print("mod(10.5, 3.0) = "); print(mod(10.5, 3.0)); print("\n");
print("fabs(-3.14) = "); print(fabs(-3.14)); print("\n");
print("fmin(2.5, 1.5) = "); print(fmin(2.5, 1.5)); print("\n");
print("fmax(2.5, 1.5) = "); print(fmax(2.5, 1.5)); print("\n");

// ============================================
// STRING LIBRARY TESTS
// ============================================
print("\n--- String Library ---\n");

testStr.s = "Hello World";

print("Original: '"); print(testStr); print("'\n");
print("left(5) = '"); print(left(testStr, 5)); print("'\n");
print("right(5) = '"); print(right(testStr, 5)); print("'\n");
print("mid(7,5) = '"); print(mid(testStr, 7, 5)); print("'\n");

padStr.s = "  trimmed  ";
print("trim('  trimmed  ') = '"); print(trim(padStr)); print("'\n");
print("ltrim = '"); print(ltrim(padStr)); print("'\n");
print("rtrim = '"); print(rtrim(padStr)); print("'\n");

print("lcase = '"); print(lcase(testStr)); print("'\n");
print("ucase = '"); print(ucase(testStr)); print("'\n");

print("chr(65) = '"); print(chr(65)); print("'\n");
print("asc('A') = "); print(asc("A")); print("\n");

print("findstring('World') = "); print(findstring(testStr, "World")); print("\n");
print("countstring('l') = "); print(countstring(testStr, "l")); print("\n");
print("replacestring('World','D+AI') = '"); print(replacestring(testStr, "World", "D+AI")); print("'\n");
print("removestring('l') = '"); print(removestring(testStr, "l")); print("'\n");
print("reversestring = '"); print(reversestring(testStr)); print("'\n");
print("insertstring(' Beautiful',6) = '"); print(insertstring(testStr, " Beautiful", 6)); print("'\n");

print("space(5) = '"); print(space(5)); print("'\n");
print("lset('Hi', 10) = '"); print(lset("Hi", 10)); print("'\n");
print("rset('Hi', 10) = '"); print(rset("Hi", 10)); print("'\n");

// String conversions
print("valf('3.14') = "); print(valf("3.14")); print("\n");
print("vali('42') = "); print(vali("42")); print("\n");
print("hex(255) = '"); print(hex(255)); print("'\n");
print("bin(15) = '"); print(bin(15)); print("'\n");

// Capitalize function
print("capitalize('hello world', 0) = '"); print(capitalize("hello world", 0)); print("'\n");
print("capitalize('HELLO WORLD', 1) = '"); print(capitalize("HELLO WORLD", 1)); print("'\n");
print("capitalize('hELLO wORLD', 2) = '"); print(capitalize("hELLO wORLD", 2)); print("'\n");

// ============================================
// CIPHER LIBRARY TESTS
// ============================================
print("\n--- Cipher Library ---\n");

testData.s = "Hello D+AI!";

print("md5('Hello D+AI!') = "); print(md5(testData)); print("\n");
print("sha1('Hello D+AI!') = "); print(sha1(testData)); print("\n");
print("sha256('Hello D+AI!') = "); print(sha256(testData)); print("\n");
print("crc32('Hello D+AI!') = "); print(crc32(testData)); print("\n");

// Base64
encoded.s = base64enc("Hello World");
print("base64enc('Hello World') = '"); print(encoded); print("'\n");
decoded.s = base64dec(encoded);
print("base64dec(encoded) = '"); print(decoded); print("'\n");

// ============================================
// JSON LIBRARY TESTS
// ============================================
print("\n--- JSON Library ---\n");

jsonStr.s = "{\"name\":\"D+AI\",\"version\":1.038,\"active\":true}";
print("Parsing: "); print(jsonStr); print("\n");

jsonHandle.i = jsonparse(jsonStr);
if jsonHandle > 0 {
   print("JSON parsed successfully, handle = "); print(jsonHandle); print("\n");

   jsonType.i = jsontype(jsonHandle);
   print("JSON type = "); print(jsonType); print("\n");

   jsonfree(jsonHandle);
   print("JSON freed\n");
} else {
   print("JSON parse failed\n");
}

// ============================================
// SUMMARY
// ============================================
print("\n=== All Tests Complete ===\n");
print("New builtins in v1.038.0:\n");
print("  Math: sin,cos,tan,asin,acos,atan,atan2,sinh,cosh,tanh,log,log10,exp,floor,ceil,round,sign,mod,fabs,fmin,fmax\n");
print("  String: left,right,mid,trim,ltrim,rtrim,lcase,ucase,chr,asc,findstring,replacestring,countstring,reversestring,insertstring,removestring,space,lset,rset,valf,vali,hex,bin,capitalize\n");
print("  Cipher: md5,sha1,sha256,sha512,crc32,base64enc,base64dec\n");
print("  JSON: jsonparse,jsonfree,jsonvalue,jsontype,jsonmember,jsonelement,jsonsize,jsonstring,jsonnumber,jsonbool,jsoncreate,jsonadd,jsonexport\n");
