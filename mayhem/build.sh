#!/usr/bin/env bash
#
# mayhem/build.sh — build mruby's fuzz harnesses (the upstream oss-fuzz/ ones) AND the
# upstream functional test suite (mrbtest), inside the commit image.
#
# Two INDEPENDENT mruby builds, in separate build dirs so both stay incrementally
# re-runnable (idempotent) and neither disturbs the other:
#
#   build/oracle  mayhem/build_config_test.rb  — mruby's own default flags + mruby-test.
#                 Produces build/oracle/bin/mrbtest, the assertion suite mayhem/test.sh runs.
#   build/fuzz    mayhem/build_config_fuzz.rb  — $SANITIZER_FLAGS (ASan+UBSan, halting) +
#                 $DEBUG_FLAGS (DWARF <= 3) + $FUZZ_COV (-fsanitize=fuzzer-no-link, the
#                 SanitizerCoverage the fuzzing engine needs; SANITIZER_FLAGS carries none).
#                 Produces build/fuzz/lib/libmruby.a, linked into every harness.
#
# Each harness is linked TWICE: once against $LIB_FUZZING_ENGINE (the Mayhem target,
# /mayhem/<name>) and once against $STANDALONE_FUZZ_MAIN (a run-once, non-fuzzer reproducer,
# /mayhem/<name>-standalone).
#
# AIR-GAPPED: everything the build needs (clang, ruby, rake, bison) is installed in the image
# by mayhem/Dockerfile; mruby's default gembox is :core-only, so rake fetches nothing. This
# script must re-run offline (SPEC §6.5).
set -euo pipefail

# clang rejects SOURCE_DATE_EPOCH='' (empty) — it must be unset or a valid integer.
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

# Build knobs from the ENV, with the base image's defaults. NB: SANITIZER_FLAGS uses `=`
# (not `:=`) on purpose so an explicit EMPTY value (--build-arg SANITIZER_FLAGS=) is honored
# and builds with NO sanitizers.
: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer}"
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${CC:=clang}" ; : "${CXX:=clang++}" ; : "${LIB_FUZZING_ENGINE:=-fsanitize=fuzzer}"
: "${STANDALONE_FUZZ_MAIN:=/opt/mayhem/StandaloneFuzzTargetMain.c}"
: "${MAYHEM_JOBS:=$(nproc)}"
: "${COVERAGE_FLAGS=}"
: "${SRC:=/mayhem}"

# SanitizerCoverage for the fuzzed library + harness TUs. Only meaningful when a sanitizer
# runtime is linked in: with SANITIZER_FLAGS deliberately emptied there is no runtime to
# provide the __sanitizer_cov_* callbacks, and mruby's OWN binaries (mrbc, mirb, ...) — which
# are plain executables, not fuzz targets — would fail to link. Coverage is irrelevant for
# that "natural crash" build anyway, so drop it there.
FUZZ_COV="-fsanitize=fuzzer-no-link"
[ -n "$SANITIZER_FLAGS" ] || FUZZ_COV=""

export SANITIZER_FLAGS DEBUG_FLAGS FUZZ_COV CC CXX LIB_FUZZING_ENGINE MAYHEM_JOBS COVERAGE_FLAGS

# mruby's gcc/clang toolchain REPLACES its entire default flag list with $CFLAGS/$CXXFLAGS/
# $LDFLAGS when those are set in the environment. We append our flags from the build configs
# instead, so make sure an inherited CFLAGS can't silently wipe mruby's own -O3/-std flags.
unset CFLAGS CXXFLAGS LDFLAGS || true

cd "$SRC"

RAKE=(rake -m -j "$MAYHEM_JOBS")

# ---------------------------------------------------------------------------------------
# 1) The functional-test (oracle) build — mruby's NORMAL flags, no sanitizers.
#    `test:build` builds the library, the bin tools and mrbtest.
# ---------------------------------------------------------------------------------------
echo ">>> [1/3] building the mruby test suite (oracle, uninstrumented)"
MRUBY_CONFIG="$SRC/mayhem/build_config_test.rb" "${RAKE[@]}" test:build

MRBTEST="$SRC/build/oracle/bin/mrbtest"
[ -x "$MRBTEST" ] || { echo "ERROR: expected test runner $MRBTEST was not produced" >&2; exit 1; }

# ---------------------------------------------------------------------------------------
# 2) The sanitized library the harnesses are fuzzed against.
# ---------------------------------------------------------------------------------------
echo ">>> [2/3] building libmruby.a with SANITIZER_FLAGS='$SANITIZER_FLAGS'"
MRUBY_CONFIG="$SRC/mayhem/build_config_fuzz.rb" "${RAKE[@]}"

LIBMRUBY="$SRC/build/fuzz/lib/libmruby.a"
[ -f "$LIBMRUBY" ] || { echo "ERROR: sanitized $LIBMRUBY was not produced" >&2; exit 1; }

# ---------------------------------------------------------------------------------------
# 3) The harnesses. Upstream keeps them in oss-fuzz/ — build EVERY one (OSS-Fuzz parity).
#    mruby_proto_fuzzer.cpp is deliberately NOT built: it needs libprotobuf-mutator, which
#    is neither a debian package nor vendorable without a network fetch at build time.
# ---------------------------------------------------------------------------------------
echo ">>> [3/3] building the fuzz harnesses"
INC=(-I"$SRC/include" -I"$SRC/build/fuzz/include")

# Preventively disable LeakSanitizer (build-time hook, ASan/UBSan stay on) — leaks aren't the
# bug class this fleet fuzzes for. Built only when a sanitizer runtime is actually linked in.
LSAN_OFF=()
if [ -n "$SANITIZER_FLAGS" ]; then
  "${CXX:-clang++}" -c $SANITIZER_FLAGS $DEBUG_FLAGS "$SRC/mayhem/lsan_off.cc" -o "$SRC/lsan_off.o"
  LSAN_OFF=("$SRC/lsan_off.o")
fi

for src in "$SRC"/oss-fuzz/mruby_*_fuzzer.c "$SRC"/oss-fuzz/mruby_fuzzer.c; do
  [ -f "$src" ] || continue
  name="$(basename "$src" .c)"

  # (a) the Mayhem target: harness + fuzzing engine
  # shellcheck disable=SC2086
  $CC $SANITIZER_FLAGS $DEBUG_FLAGS $FUZZ_COV $LIB_FUZZING_ENGINE \
      "${INC[@]}" "$src" "${LSAN_OFF[@]}" "$LIBMRUBY" -lm -o "$SRC/$name"

  # (b) the standalone reproducer: harness + LLVM's run-once driver (no libFuzzer runtime)
  # shellcheck disable=SC2086
  $CC $SANITIZER_FLAGS $DEBUG_FLAGS \
      "${INC[@]}" "$STANDALONE_FUZZ_MAIN" "$src" "${LSAN_OFF[@]}" "$LIBMRUBY" -lm -o "$SRC/$name-standalone"

  echo "    built $name + $name-standalone"
done

echo ">>> build.sh done"
ls -l "$SRC"/mruby_*fuzzer "$SRC"/mruby_*fuzzer-standalone
