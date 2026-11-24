#!/usr/bin/env bash
#
# Configure and build regex_perf with the QuickJS, Boost.Regex, Hermes, PCRE2, SRELL and Node.js
# engines, then run the benchmark on 3200.txt and verify that every engine was measured.
#
# The dependencies have to be built first with ci/build-deps.sh (or point DEPS_DIR at an already
# prepared directory).
#
# Environment:
#   DEPS_DIR    directory prepared by ci/build-deps.sh (default: ./.ci-deps)
#   BUILD_DIR   CMake build directory (default: ./build)
#   OUTPUT_DIR  where the benchmark results are written (default: ./ci-results)
#   REPEAT      number of benchmark repetitions (default: 3)
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEPS_DIR="${DEPS_DIR:-$ROOT_DIR/.ci-deps}"
BUILD_DIR="${BUILD_DIR:-$ROOT_DIR/build}"
OUTPUT_DIR="${OUTPUT_DIR:-$ROOT_DIR/ci-results}"
REPEAT="${REPEAT:-3}"

ENGINES=(boost pcre pcre-jit srell quickjs hermes nodejs)

log() {
    printf '=== %s\n' "$*"
}

for dir in \
    "$DEPS_DIR/quickjs" \
    "$DEPS_DIR/srell/srell-src/single-header" \
    "$DEPS_DIR/pcre2-build" \
    "$DEPS_DIR/boost" \
    "$DEPS_DIR/hermes" \
    "$DEPS_DIR/hermes-build"; do
    if [ ! -d "$dir" ]; then
        echo "error: '$dir' is missing; run ci/build-deps.sh first." >&2
        exit 1
    fi
done

log "configuring regex_perf"
# the top-level CMakeLists.txt still declares cmake_minimum_required(VERSION 3.0), which CMake 4
# rejects; the policy floor keeps the build working with a newer CMake as well
policy_args=()
if [ "$(cmake --version | head -1 | sed 's/^cmake version \([0-9]*\).*/\1/')" -ge 4 ]; then
    policy_args+=(-DCMAKE_POLICY_VERSION_MINIMUM=3.5)
fi

cmake -S "$ROOT_DIR" -B "$BUILD_DIR" -G Ninja \
    "${policy_args[@]}" \
    -DCMAKE_BUILD_TYPE=Release \
    -DINCLUDE_BOOST=local \
    -DBOOST_ROOT="$DEPS_DIR/boost" \
    -DBOOST_INCLUDEDIR="$DEPS_DIR/boost/include" \
    -DBOOST_LIBRARYDIR="$DEPS_DIR/boost/lib" \
    -DINCLUDE_PCRE2=local \
    -DPCRE2_BUILD_DIR="$DEPS_DIR/pcre2-build" \
    -DINCLUDE_QUICKJS=local \
    -DQUICKJS_SOURCE_DIR="$DEPS_DIR/quickjs" \
    -DINCLUDE_SRELL=local \
    -DSRELL_SOURCE_DIR="$DEPS_DIR/srell/srell-src/single-header" \
    -DINCLUDE_HERMES=local \
    -DHERMES_SOURCE_DIR="$DEPS_DIR/hermes" \
    -DHERMES_BUILD_DIR="$DEPS_DIR/hermes-build" \
    -DINCLUDE_NODEJS=local \
    -DINCLUDE_RUST=disabled \
    -DINCLUDE_CPPSTD=disabled \
    -DINCLUDE_ONIGURUMA=disabled \
    -DINCLUDE_TRE=disabled \
    -DINCLUDE_RE2=disabled \
    -DINCLUDE_CTRE=disabled \
    -DINCLUDE_YARA=disabled \
    -DINCLUDE_HYPERSCAN=disabled

log "building regex_perf"
cmake --build "$BUILD_DIR" --target regex_perf -j "$(nproc)"

BINARY="$BUILD_DIR/src/regex_perf"

# the engine table is compiled in, so the help output lists exactly the engines that were built
log "checking the enabled engines"
AVAILABLE="$("$BINARY" -h | sed -n 's/^available engines: //p')"
log "available engines: $AVAILABLE"
missing=0
for engine in "${ENGINES[@]}"; do
    case " $AVAILABLE " in
        *" $engine "*) ;;
        *)
            echo "error: engine '$engine' was not built into regex_perf" >&2
            missing=1
            ;;
    esac
done
if [ "$missing" -ne 0 ]; then
    exit 1
fi

mkdir -p "$OUTPUT_DIR"
CSV="$OUTPUT_DIR/results.csv"
LOG="$OUTPUT_DIR/benchmark.log"

log "running the benchmark (repeat: $REPEAT)"
args=(-f "$ROOT_DIR/3200.txt" -n "$REPEAT" -o "$CSV")
for engine in "${ENGINES[@]}"; do
    args+=(-e "$engine")
done
"$BINARY" "${args[@]}" 2>&1 | tee "$LOG"

# every engine has a "<engine> [ms]" column; a column without a single valid time means the engine
# failed or timed out on every pattern, which the summary alone does not report
log "verifying the benchmark results"
python3 - "$CSV" "${ENGINES[@]}" <<'PY'
import csv
import sys

path, engines = sys.argv[1], sys.argv[2:]
with open(path, newline="") as f:
    rows = list(csv.DictReader(f, delimiter=";"))

failed = []
for engine in engines:
    column = f"{engine} [ms]"
    if column not in rows[0]:
        failed.append(f"{engine}: column '{column}' is missing")
        continue
    times = [float(row[column]) for row in rows if row[column].strip()]
    measured = [t for t in times if 0 < t < 999999]
    print(f"{engine}: {len(measured)}/{len(times)} patterns measured")
    if not measured:
        failed.append(f"{engine}: no pattern was measured")

if failed:
    for message in failed:
        print(f"error: {message}", file=sys.stderr)
    sys.exit(1)
PY

log "results written to $OUTPUT_DIR"
