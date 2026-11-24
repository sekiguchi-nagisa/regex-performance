#!/usr/bin/env bash
#
# Build the regex engines that are not available from the distribution packages, so that
# src/CMakeLists.txt can enable QuickJS, Boost.Regex, Hermes, PCRE2, SRELL and Node.js.
#
# Every engine is checked out at a pinned revision (see the *_REF variables below) and is only
# built once: an engine whose build artifacts are already present is skipped, so the script works
# both in a fresh CI job and on top of a restored cache (see .github/workflows/benchmark-ci.yml).
#
# Typical use:
#   ci/build-deps.sh                    # build everything into <repo>/.ci-deps
#   DEPS_DIR=/tmp/deps ci/build-deps.sh # build into another directory
#   QUICKJS_REF=v0.19.0 ci/build-deps.sh  # try a newer QuickJS
#
# The build directories below are the ones the CMake options expect:
#   -DQUICKJS_SOURCE_DIR=$DEPS_DIR/quickjs
#   -DSRELL_SOURCE_DIR=$DEPS_DIR/srell/srell-src/single-header
#   -DPCRE2_BUILD_DIR=$DEPS_DIR/pcre2-build
#   -DHERMES_SOURCE_DIR=$DEPS_DIR/hermes -DHERMES_BUILD_DIR=$DEPS_DIR/hermes-build
#   -DBOOST_ROOT=$DEPS_DIR/boost
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEPS_DIR="${DEPS_DIR:-$ROOT_DIR/.ci-deps}"
JOBS="${JOBS:-$(nproc)}"

# pinned revisions. Node.js is not built here: the adapter only needs the `node` executable.
QUICKJS_REF="${QUICKJS_REF:-v0.18.0}"
SRELL_REF="${SRELL_REF:-v2026.11}"
PCRE2_REF="${PCRE2_REF:-pcre2-10.49}"
HERMES_REF="${HERMES_REF:-f7b0b8632a926720a777564d1264c027a95bb49f}"
BOOST_VERSION="${BOOST_VERSION:-1.88.0}"

log() {
    printf '=== %s\n' "$*"
}

# fetch_source <name> <url> <ref>
#
# Clone <url> at <ref> into $DEPS_DIR/<name>. A tag, a branch and a commit id are all accepted,
# which is why the revision is fetched explicitly instead of using `git clone --branch`.
fetch_source() {
    local name=$1 url=$2 ref=$3 dir="$DEPS_DIR/$1"

    if [ -d "$dir/.git" ]; then
        log "$name: already fetched, skipping"
        return
    fi

    log "$name: fetching $ref from $url"
    rm -rf "$dir"
    git init -q "$dir"
    git -C "$dir" remote add origin "$url"
    git -C "$dir" fetch -q --depth 1 origin "$ref"
    git -C "$dir" -c advice.detachedHead=false checkout -q FETCH_HEAD
}

mkdir -p "$DEPS_DIR"

log "dependency directory: $DEPS_DIR"
log "QuickJS: $QUICKJS_REF"
log "SRELL:   $SRELL_REF"
log "PCRE2:   $PCRE2_REF"
log "Hermes:  $HERMES_REF"
log "Boost:   $BOOST_VERSION"

# QuickJS: src/quickjs.cmake compiles libregexp.c and libunicode.c from the source tree.
if [ ! -f "$DEPS_DIR/quickjs/libregexp.c" ]; then
    fetch_source quickjs https://github.com/quickjs-ng/quickjs.git "$QUICKJS_REF"
else
    log "quickjs: already fetched, skipping"
fi

# SRELL: header-only, src/srell.cmake only needs the single-header variant.
if [ ! -f "$DEPS_DIR/srell/srell-src/single-header/srell.hpp" ]; then
    fetch_source srell https://github.com/upa-url/srell.git "$SRELL_REF"
else
    log "srell: already fetched, skipping"
fi

# PCRE2: src/pcre2.cmake links the static 8-bit library with JIT support. PCRE2_STATIC_PIC is
# required because regex_perf is linked as a PIE executable. The JIT needs the sljit submodule.
if [ ! -f "$DEPS_DIR/pcre2-build/libpcre2-8.a" ]; then
    if [ ! -d "$DEPS_DIR/pcre2/.git" ]; then
        fetch_source pcre2 https://github.com/PCRE2Project/pcre2.git "$PCRE2_REF"
    else
        log "pcre2: already fetched, skipping"
    fi
    log "pcre2: building the static 8-bit library with JIT"
    git -C "$DEPS_DIR/pcre2" submodule update -q --init --depth 1 deps/sljit
    cmake -S "$DEPS_DIR/pcre2" -B "$DEPS_DIR/pcre2-build" -G Ninja \
        -DCMAKE_BUILD_TYPE=Release \
        -DPCRE2_SUPPORT_JIT=ON \
        -DPCRE2_STATIC_PIC=ON \
        -DPCRE2_SUPPORT_UNICODE=ON \
        -DPCRE2_BUILD_TESTS=OFF \
        -DPCRE2_BUILD_PCRE2GREP=OFF
    cmake --build "$DEPS_DIR/pcre2-build" --target pcre2-8-static -j "$JOBS"
else
    log "pcre2: already built, skipping"
fi

# Boost.Regex: src/boost.cmake locates it with find_package(Boost), so it has to be installed
# into a prefix; only the regex component is built.
BOOST_SRC="$DEPS_DIR/boost_${BOOST_VERSION//./_}"
BOOST_ARCHIVE="$DEPS_DIR/downloads/boost_${BOOST_VERSION//./_}.tar.bz2"
if [ ! -f "$DEPS_DIR/boost/lib/libboost_regex.a" ]; then
    if [ ! -d "$BOOST_SRC" ]; then
        log "boost: downloading $BOOST_VERSION"
        mkdir -p "$DEPS_DIR/downloads"
        [ -f "$BOOST_ARCHIVE" ] ||
            curl -fsSL -o "$BOOST_ARCHIVE" \
                "https://archives.boost.io/release/$BOOST_VERSION/source/$(basename "$BOOST_ARCHIVE")"
        tar -xjf "$BOOST_ARCHIVE" -C "$DEPS_DIR"
    else
        log "boost: already extracted, skipping download"
    fi
    log "boost: building Boost.Regex"
    (
        cd "$BOOST_SRC"
        ./bootstrap.sh --with-libraries=regex --prefix="$DEPS_DIR/boost" >/dev/null
        ./b2 install -q \
            --prefix="$DEPS_DIR/boost" \
            --with-regex \
            link=static \
            threading=multi \
            variant=release \
            cxxstd=17 \
            -j "$JOBS"
    )
else
    log "boost: already built, skipping"
fi

# Hermes: src/hermes.cmake links the static libraries of an existing Hermes build tree. Only the
# regex engine and the support code it needs are built, so the tools, the test suite and the
# Node-API tests are disabled (the Node-API tests also require the `hermes` tool target).
if [ ! -f "$DEPS_DIR/hermes-build/lib/Regex/libhermesRegex.a" ]; then
    if [ ! -d "$DEPS_DIR/hermes/.git" ]; then
        fetch_source hermes https://github.com/facebook/hermes.git "$HERMES_REF"
    else
        log "hermes: already fetched, skipping"
    fi
    log "hermes: building hermesRegex and hermesSupport"
    cmake -S "$DEPS_DIR/hermes" -B "$DEPS_DIR/hermes-build" -G Ninja \
        -DCMAKE_BUILD_TYPE=Release \
        -DHERMES_ENABLE_TOOLS=OFF \
        -DHERMES_ENABLE_TEST_SUITE=OFF \
        -DHERMES_ENABLE_NAPI=OFF
    cmake --build "$DEPS_DIR/hermes-build" --target hermesRegex hermesSupport -j "$JOBS"
else
    log "hermes: already built, skipping"
fi

# Node.js: the adapter runs the installed executable, nothing is built here.
if ! command -v node >/dev/null 2>&1; then
    echo "error: the 'node' executable was not found; install Node.js first." >&2
    exit 1
fi
log "node: $(node --version) ($(command -v node))"

log "all dependencies are ready in $DEPS_DIR"
