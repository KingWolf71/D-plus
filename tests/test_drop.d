#pragma listasm on

func test() {
    return 42;
}

// Call without using return value - should generate DROP
test();
test();
test();

print("Done");
