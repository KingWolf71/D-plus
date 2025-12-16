# LJ2 Test Suite Documentation

## Overview

The LJ2 test suite provides automated testing for the LJ2 compiler and VM. It supports categorized testing, crash detection, timeout handling, and detailed reporting.

## Test Suite Scripts

| Script | Description |
|--------|-------------|
| `test-suite.ps1` | Main test runner with all options |
| `test-all.ps1` | Run all tests (excluding bugfix*) |
| `test-quick.ps1` | Quick smoke test (one from each category) |
| `test-basic.ps1` | Control flow, operators, functions (001-025) |
| `test-arrays.ps1` | Array tests (040-044) |
| `test-pointers.ps1` | Pointer tests (060-069) |
| `test-structures.ps1` | Structure tests (080-087) |
| `test-collections.ps1` | Lists, maps, AVL trees (100-107) |
| `test-algorithms.ps1` | Primes, Mandelbrot, etc. (110-114) |
| `test-comprehensive.ps1` | Comprehensive test suite (120-122) |
| `test-nocomprehensive.ps1` | All except comprehensive (faster) |
| `test-errors.ps1` | Error handling tests (130-131) |

## Usage

### Basic Usage

```powershell
# Run all tests
.\test-all.ps1

# Run quick smoke test
.\test-quick.ps1

# Run specific category
.\test-arrays.ps1
.\test-pointers.ps1
.\test-structures.ps1
```

### Advanced Options

```powershell
# Main test suite with options
.\test-suite.ps1 [category] [-ShowOutput] [-StopOnError] [-ListOnly] [-AutoClose N] [-Timeout N]
```

**Parameters:**

| Parameter | Default | Description |
|-----------|---------|-------------|
| `Category` | all | Test category to run |
| `-ShowOutput` | false | Display test output for all tests |
| `-StopOnError` | false | Stop on first failure |
| `-ListOnly` | false | List tests without running |
| `-AutoClose` | 3 | Seconds before LJ2 auto-closes (0 to disable) |
| `-Timeout` | 30 | Max seconds per test before timeout |

### Examples

```powershell
# List tests in a category
.\test-suite.ps1 -Category arrays -ListOnly

# Run with verbose output
.\test-suite.ps1 -Category basic -ShowOutput

# Stop on first error for debugging
.\test-suite.ps1 -Category pointers -StopOnError -ShowOutput

# Custom timeout for slow tests
.\test-suite.ps1 -Category algorithms -Timeout 60

# Disable auto-close for manual inspection
.\test-suite.ps1 -Category quick -AutoClose 0
```

## Test Categories

| Category | Prefix | Description | Count |
|----------|--------|-------------|-------|
| basic | 001-025 | Control flow, operators, functions, type inference | ~19 |
| arrays | 040-044 | Array operations, resize, sort, strings | ~6 |
| pointers | 060-069 | Pointer basics, arithmetic, function pointers | ~10 |
| structures | 080-087 | Struct definition, arrays, nesting, pointers | ~7 |
| collections | 100-107 | Lists, maps, AVL trees | ~10 |
| algorithms | 110-114 | Primes, game 24, Mandelbrot, Julia set | ~10 |
| comprehensive | 120-122 | Full test suites | 3 |
| errors | 130-131 | Error handling and reporting | 2 |
| quick | mixed | One test from each category (smoke test) | 8 |
| nocomprehensive | all-120s | All tests except comprehensive | ~64 |

## Crash and Error Detection

The test suite detects various failure modes:

| Exit Code | Status | Description |
|-----------|--------|-------------|
| 0 | PASS | Test completed successfully |
| 124 | TIMEOUT | Test exceeded time limit (killed by timeout) |
| 134 | CRASH | SIGABRT - Aborted |
| 136 | CRASH | SIGFPE - Floating point exception |
| 139 | CRASH | SIGSEGV - Segmentation fault |
| other | FAIL | Non-zero exit or error in output |

**Output patterns detected:** `error`, `exception`, `failed`, `panic`, `segmentation`, `core dumped`

## Output Format

```
========================================
  LJ2 Test Suite Runner
  Category: quick
  AutoClose: 3s | Timeout: 30s
========================================

Running 8 tests...

[1/8] Testing: 001 Simple while.lj... PASS (2.45s)
[2/8] Testing: 002 if else.lj... PASS (2.31s)
[3/8] Testing: crash_test.lj... CRASH (0.12s) - CRASH (Segmentation fault)
[4/8] Testing: hang_test.lj... TIMEOUT (30.05s) - TIMEOUT (exceeded 30s)
[5/8] Testing: error_test.lj... FAIL (2.18s) - Error in output

========================================
  Test Results Summary
========================================

  Total:    8
  Passed:   5
  Failed:   3
  Crashed:  1
  Timeout:  1
  Time:     42.35s

Failed tests:
  [CRASH] crash_test.lj
  [TIMEOUT] hang_test.lj
  [FAIL] error_test.lj
        Error in output
```

## Auto-Close Feature

The LJ2 compiler supports an `--autoclose` command-line option that shows a countdown before exiting. This is useful for automated testing.

### Command Line Usage

```bash
# Default 15 seconds countdown
./lj2_linux "file.lj" --autoclose
./lj2_linux "file.lj" -a

# Custom countdown (5 seconds)
./lj2_linux "file.lj" --autoclose 5
./lj2_linux "file.lj" --autoclose=5
./lj2_linux "file.lj" -a=5

# No auto-close (default behavior)
./lj2_linux "file.lj"
```

### Console Output

When auto-close is enabled, after program execution:

```
[program output]

Closing in 5 seconds...
Closing in 4 seconds...
Closing in 3 seconds...
Closing in 2 seconds...
Closing in 1 seconds...
Closing now.
```

## File Naming Convention

Test files follow a numbering scheme:

- `001-025` - Basic language features
- `040-049` - Array operations
- `060-069` - Pointer operations
- `080-089` - Structure operations
- `100-109` - Collections (lists, maps)
- `110-119` - Algorithm examples
- `120-129` - Comprehensive tests
- `130-139` - Error handling tests

**Excluded files:** Files starting with `bug` (e.g., `bug fix.lj`) are automatically excluded from all test runs.

## Adding New Tests

1. Create test file in `Examples/` with appropriate number prefix
2. File will automatically be included in the matching category
3. Use `assertEqual()`, `assertFloatEqual()`, `assertStringEqual()` for validation
4. Tests pass if exit code is 0 and no error patterns in output

## Troubleshooting

### Test hangs
- Increase timeout: `-Timeout 60`
- Disable auto-close for debugging: `-AutoClose 0`
- Check for infinite loops in test code

### Test crashes
- Run with `-ShowOutput -StopOnError` to see details
- Check for null pointer access, array bounds, stack overflow

### WSL issues
- Ensure Ubuntu-24.04 WSL distribution is installed
- Verify `lj2_linux` binary exists and is executable
- Check PUREBASIC_HOME path in test script
