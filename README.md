# Regex Performance
[![Build Status](https://travis-ci.org/rust-leipzig/regex-performance.svg?branch=master)](https://travis-ci.org/rust-leipzig/regex-performance)

## Introduction
Regular expressions are commonly used in pattern search algorithms.
This tool is based on the work of John Maddock (See his own regex comparison [here](http://www.boost.org/doc/libs/1_41_0/libs/regex/doc/gcc-performance.html))
and the sljit project (See their regex comparison [here](http://sljit.sourceforge.net/regex_perf.html)).

## Requirements

### Modern Clang 19.1.6 Toolchain (Recommended)
When using the modern toolchain build, all dependencies are automatically handled by the build script. Just ensure you have access to the toolchain environment:
- Access to `/ssd/hblib-installer/ubuntu-20.04/tools/sourceme.sh`
- CMake 3.24.2 (included in toolchain)
- Clang 19.1.6 (included in toolchain)
- All regex engine dependencies built automatically

### Legacy System Requirements
| dependency | version  |
|------------|----------|
| Cmake      | >=3.0    |
| Ragel      | 6.9      |
| Python     | >=3.0    |
| Boost (*2)  | >=1.57   |
| Pcap       | >=0.8    |
| Autoconf   | 2.69 (*) |
| Automake   | 1.15 (*) |
| Autopoint  | 0.19.7 (*)|
| Gettext    | 0.19.7 (*)|
| Libtool    | 2.4.6 (*)|
| Git        | 2.11.0 (*)|

(*) Tested with named version only. Older versions may work too.
(*2) Needs boost-regex to be installed as a component

## Supported engines
The following regex engines are supported and covered by the tool:
- [CTRE](https://github.com/hanickadot/compile-time-regular-expressions)
- [Hyperscan](https://github.com/01org/hyperscan)
- [Oniguruma](https://github.com/kkos/oniguruma)
- [RE2](https://github.com/google/re2)
- [Tre](https://github.com/laurikari/tre)
- [PCRE2](http://www.pcre.org)
- [Rust regex crate](https://doc.rust-lang.org/regex/regex/index.html)
- [Regress regex crate](https://docs.rs/regress/)
- [Boost regex](https://www.boost.org/doc/libs/1_78_0/libs/regex/doc/html/index.html)
- [C++ Standard regex](https://en.cppreference.com/w/cpp/regex)
- [YARA](https://github.com/VirusTotal/yara)
- [SRELL](https://github.com/upa-url/srell)
- [QuickJS libregexp](https://github.com/quickjs-ng/quickjs)
- [Hermes](https://github.com/facebook/hermes)
- [Node.js (V8)](https://nodejs.org)

The engines are built from their sources. In the case an installed engine should be used,
the corresponding cmake variable `INCLUDE_<name>` has to be set to `system`. The configuration script
tries to locate the library and uses the library for linking the benchmark.
The same variable can be set to `disabled` to exclude an engine.

SRELL, QuickJS, Hermes and the Node.js engine are ECMAScript-compatible Unicode engines, so they
are the closest comparison targets for an ECMAScript-style engine. They are disabled by default
because they need an external source/build tree or an installed `node`:

| variable | meaning |
|----------|---------|
| `INCLUDE_SRELL=local` + `SRELL_SOURCE_DIR` | directory that contains `srell.hpp` (the `single-header` variant) |
| `INCLUDE_QUICKJS=local` + `QUICKJS_SOURCE_DIR` | QuickJS tree that contains `libregexp.c` |
| `INCLUDE_HERMES=local` + `HERMES_SOURCE_DIR` / `HERMES_BUILD_DIR` | Hermes source tree and the CMake build that contains `lib/Regex/libhermesRegex.a` |
| `INCLUDE_NODEJS=local` + `NODEJS_EXECUTABLE` | the `node` executable (looked up on `PATH` by `find_program`) |
| `INCLUDE_PCRE2=local` + `PCRE2_BUILD_DIR` | a PCRE2 build with `libpcre2-8.a` and JIT support |

The Node.js engine runs out of process, so its memory columns stay `0`. See "Memory measurement"
below for the in-process heap numbers.

The configuration script distinguishes between nightly and other Rust toolchains to enable the SIMD-feature
which is currently available in the nightly built only. The SIMD-feature improves the throughput of the
regex crate for defined expressions.

## Building the tool
The different engines have different requirements which are not described here.
Please see the related project documentations.

On Ubuntu 20.04 these were necessary installs to get the build done from a stock AWS box
```bash
$ apt install build-essential cmake rustc cargo automake autoconf autopoint autogen \
   libtool libprotobuf-dev libprotobuf-c-dev protobuf-compiler ninja-build \
   ragel libpcap pcaputils pkg-config libboost-dev flex bison
```

### Modern Clang 19.1.6 Toolchain Build (Recommended)

For optimal performance with the latest toolchain, use the automated build script with the modern Clang 19.1.6 toolchain:

```bash
# Source the modern toolchain environment
source /ssd/hblib-installer/ubuntu-20.04/tools/sourceme.sh

# Clean build from scratch
./build_deps_simple.sh

# Build the main project
mkdir -p build && cd build
CC=clang CXX=clang++ cmake ..
make -j$(nproc)
```

This approach:
- Uses Clang 19.1.6 compiler with LLVM tools
- Builds all dependencies with modern toolchain
- Includes latest RE2 with Abseil dependencies
- Supports all 11 regex engines with optimal performance

### Legacy Build Method

In the case all depencies are fulfilled, just configure and build the cmake based project:

```bash
mkdir build && cd build
cmake ..
make
```

The `make` command will build all engines and the test tool `regex_perf`.

To build the test tool or a library only, call `make` with corresponding target, i.e.:

```bash
make regex_perf
```

## Usage
The test tool calls each engine with a defined set of different regular expression on a given file.
The repository contains a ~16Mbyte large text file (3200.txt) which can be used for measuring.

```bash
# When using modern toolchain, source the environment first
source /ssd/hblib-installer/ubuntu-20.04/tools/sourceme.sh
build/src/regex_perf -f 3200.txt
```

For legacy builds:
```bash
./src/regex_perf -f ./3200.txt
```

By default, the tool repeats each test 5 times and prints the best time of each test.
The overall time to process each regular expression is measured and accounted.
The scoring algorithhm distributes the fastest engine 5 points, the second fastest 4 points and so on.
The score points help to limit the impact of a slow regular expression eninge test in comparision to
the absolut time value.

You can specify a file to write the test results per expression and engine:
```bash
./src/regex_perf -f ./3200.txt -o ./results.csv
```
The test tool writes the results in a csv-compatible format.

`-e NAME` restricts the measured engines and `-p PATTERN` replaces the built-in pattern set; both
can be repeated, and `-h` lists the available engine names. Naming an engine with `-e` is also how a
single engine is measured without building all of them:

```bash
./src/regex_perf -f ./3200.txt -e pcre-jit -e srell
./src/regex_perf -f ./3200.txt -e srell -p 'Twain' -p '\p{Sm}'
```

## Continuous integration

`.github/workflows/benchmark-ci.yml` builds the QuickJS, Boost.Regex, Hermes, PCRE2, SRELL and
Node.js engines, links them into `regex_perf`, and runs the benchmark on `3200.txt` to verify that
all of them can be measured. It runs every Monday at 03:00 UTC and can be started manually with
*Run workflow*.

The two scripts used by the workflow can also be run locally:

```bash
# build the engines at their pinned revisions into ./.ci-deps
ci/build-deps.sh

# build regex_perf from those dependencies, run the benchmark and check the CSV
ci/build-and-bench.sh
```

`ci/build-deps.sh` is incremental: engines whose build artifacts already exist are skipped, which
is also how the workflow reuses its dependency cache. The revisions are pinned with the
`QUICKJS_REF`, `SRELL_REF`, `PCRE2_REF`, `HERMES_REF` and `BOOST_VERSION` environment variables, so
a newer engine can be tried without editing the script. `ci/build-and-bench.sh` writes
`ci-results/results.csv` and `ci-results/benchmark.log`, and fails if one of the six engines is
missing from the binary or was not measured at all. Both directories are git-ignored.

## Memory measurement

Every adapter that links the engine into the benchmark executable also reports the heap usage of
its own work, split into two numbers:

* `instance`: the live bytes of the compiled regex instance.
* `runtime`: the peak extra bytes allocated while scanning the input.

The numbers are printed next to the timings and written to the CSV (`<engine> [mem_inst]` and
`<engine> [mem_run]` columns). `memory_tracker.cpp` provides them by replacing the global
malloc/calloc/realloc/free and C++ operator new/delete and accounting every live block by its
usable size. Because all engines are linked into the same executable, each adapter measures a
delta around its own work:

```c
const size_t base = memory_tracker_live();
/* build the compiled regex */
res->mem_instance = memory_tracker_live() - base;

memory_tracker_reset_peak();
const size_t scan_base = memory_tracker_live();
/* run all the matches */
res->mem_runtime = memory_tracker_peak() - scan_base;
```

The tracker is enabled on glibc (Linux) and is a no-op elsewhere, in which case both numbers stay
`0`. It tracks heap allocations only: memory obtained directly from the OS (e.g. `mmap`) or held
on the stack is not included. The Node.js engine runs in another process, so its columns are `0`.

## Spreadsheet generator

We included a spreadsheet generator for easy visualization of the results. 
Once you have ran the results and obtained the `results.csv` file, you can create a spreadsheet
with (assuming you are still in the build directory)
```bash
python3 ../genspreadsheet.py results.csv
```
It will save an Excel spreadsheet with the name `regex-results-YYYYMMDD-HHMMSS.xlsx` in the current
directory. 

## Compiling with clang + libc++

Unfortunately it is not possible to run both standard C++ from GCC/stdlibc++ and clang+libc++ at the 
same time, it is just the way that cmake selects a single compiler. 

To run with clang+libc++ use the following recipe:
```bash
mkdir build && cd build
cmake \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_EXE_LINKER_FLAGS="-lc++abi -lc++"  \
    -DCMAKE_CXX_COMPILER=/usr/local/bin/clang++ \
    -DCMAKE_C_COMPILER=/usr/local/bin/clang \
    -DCMAKE_CXX_FLAGS_INIT="-std=c++20 -stdlib=libc++ -march=native -mtune=native" \
    -G Ninja ..
```

## Current Build Status

**Latest Update (2025-09-28)**: Successfully rebuilt from scratch with modern Clang 19.1.6 toolchain
- ✅ All 11 regex engines working: CTRE, Boost, C++ std, PCRE (3 variants), RE2, Oniguruma, TRE, Rust regex (2 variants)
- ✅ Latest RE2 with Abseil dependencies properly linked
- ✅ Performance tests running successfully
- ⚠️ CTRE has known issues with case-insensitive patterns and word boundaries
- 🚀 Best performers: Rust regex, PCRE-JIT, RE2

## Results

These results were obtained in an AMD Threadripper 3960X (Zen2) at 3.8 GHz running Ubuntu 20.04.5 LTS.

![Updated Performance Results](results_threadripper.png "Performance Results")

IceLake Xeon Platinum 8375C @ 2.90GHz (AWS C6i instance) - no mitigations

![IceLake Server](results_icelake.png "Results Ice Lake")