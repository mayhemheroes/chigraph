#!/usr/bin/env bash
#
# mayhem/build.sh — build chigraph's fuzz harnesses + the upstream test suite.
#
# Runs inside the commit image (mayhem/Dockerfile) as `mayhem` in /mayhem. chigraph uses the
# LLVM *C* API; the base image's clang-19 headers dropped APIs chigraph still calls
# (LLVMDIBuilderInsertDeclareAtEnd), so we build against the LLVM-18 dev packages the Dockerfile
# installs and point CMake at llvm-config-18. The stock clang/clang++ (19) driver is fine as the
# compiler — only the linked LLVM library/headers must be 18.
set -euo pipefail

# clang rejects SOURCE_DATE_EPOCH='' (empty) — must be unset or a valid integer.
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer}"
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${CC:=clang}" ; : "${CXX:=clang++}" ; : "${LIB_FUZZING_ENGINE:=-fsanitize=fuzzer}"
: "${MAYHEM_JOBS:=$(nproc)}"
: "${COVERAGE_FLAGS=}"
export SANITIZER_FLAGS DEBUG_FLAGS CC CXX LIB_FUZZING_ENGINE MAYHEM_JOBS COVERAGE_FLAGS

cd "$SRC"

LLVM_CONFIG=/usr/bin/llvm-config-18
LLVM_INC="$("$LLVM_CONFIG" --includedir)"
LLVM_LDLIBS="$("$LLVM_CONFIG" --ldflags --libs --system-libs)"

# chigraph is only wired for the LLVM native target here; keep the optional debugger (LLDB) and
# fetcher (libgit2) OFF and network tests OFF — none are needed by the harnessed code path.
COMMON_CMAKE=(
  -GNinja
  -DCMAKE_C_COMPILER="$CC" -DCMAKE_CXX_COMPILER="$CXX"
  -DLLVM_CONFIG="$LLVM_CONFIG"
  -DCG_BUILD_DEBUGGER=OFF
  -DCG_BUILD_FETCHER=OFF
  -DCG_BUILD_NETWORK_TESTS=OFF
  -DCG_BUILD_EXAMPLES=OFF
)

# ---------------------------------------------------------------------------------------------
# 1) Sanitized project build — libchigraphcore/libchigraphsupport carry ASan+UBSan + DWARF<4 so the
#    FUZZED code (not just the harness) is instrumented. Static libs; no test binaries here.
# ---------------------------------------------------------------------------------------------
cmake -S "$SRC" -B "$SRC/build" "${COMMON_CMAKE[@]}" \
  -DCG_BUILD_TESTS=OFF \
  -DCMAKE_C_FLAGS="$SANITIZER_FLAGS $DEBUG_FLAGS" \
  -DCMAKE_CXX_FLAGS="$SANITIZER_FLAGS $DEBUG_FLAGS"
cmake --build "$SRC/build" -j"$MAYHEM_JOBS" --target chigraphcore chigraphsupport

CORE_A="$SRC/build/lib/libchigraphcore.a"
SUPPORT_A="$SRC/build/lib/libchigraphsupport.a"

INCLUDES=(-I"$SRC/lib/core/include" -I"$SRC/lib/support/include" -I"$LLVM_INC"
  -D_GNU_SOURCE -D__STDC_CONSTANT_MACROS -D__STDC_FORMAT_MACROS -D__STDC_LIMIT_MACROS)
# chigraph's headers/impl use exceptions + RTTI; llvm-config would add -fno-exceptions/-fno-rtti,
# so we DON'T pull llvm-config --cxxflags — just its include dir — and keep exceptions on.
LINK_LIBS=("$CORE_A" "$SUPPORT_A" $LLVM_LDLIBS -lboost_program_options)

# ---------------------------------------------------------------------------------------------
# 2) Build each harness twice: the libFuzzer binary, and a $STANDALONE_FUZZ_MAIN reproducer.
#    The standalone driver is compiled as C first so its LLVMFuzzerTestOneInput ref keeps C linkage.
# ---------------------------------------------------------------------------------------------
$CC $SANITIZER_FLAGS $DEBUG_FLAGS -c "$STANDALONE_FUZZ_MAIN" -o /tmp/standalone_main.o

build_harness() {
  local src="$1" out="$2"
  # shellcheck disable=SC2086
  $CXX -std=c++17 $SANITIZER_FLAGS $DEBUG_FLAGS $LIB_FUZZING_ENGINE "${INCLUDES[@]}" \
    "$src" "${LINK_LIBS[@]}" -o "/mayhem/$out"
  # shellcheck disable=SC2086
  $CXX -std=c++17 $SANITIZER_FLAGS $DEBUG_FLAGS "${INCLUDES[@]}" \
    "$src" /tmp/standalone_main.o "${LINK_LIBS[@]}" -o "/mayhem/$out-standalone"
}

build_harness "$SRC/mayhem/fuzz_chi_compile.cpp"          fuzz_chi
build_harness "$SRC/mayhem/fuzz_unmangleFunctionName.cpp" fuzz_unmangleFunctionName

# ---------------------------------------------------------------------------------------------
# 3) Build the upstream test suite with NORMAL (non-sanitized) flags so test.sh only RUNS it.
#    Produces build-tests/test/api_tests and build-tests/test/error/error_tester + ctest registry.
# ---------------------------------------------------------------------------------------------
cmake -S "$SRC" -B "$SRC/build-tests" "${COMMON_CMAKE[@]}" \
  -DCMAKE_BUILD_TYPE=RelWithDebInfo \
  -DCG_BUILD_TESTS=ON \
  -DCMAKE_C_FLAGS="$COVERAGE_FLAGS" \
  -DCMAKE_CXX_FLAGS="$COVERAGE_FLAGS"
cmake --build "$SRC/build-tests" -j"$MAYHEM_JOBS" --target api_tests error_tester

echo "build.sh: OK — harnesses: /mayhem/fuzz_chi /mayhem/fuzz_unmangleFunctionName (+ -standalone)"
