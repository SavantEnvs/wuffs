#!/usr/bin/env bash
#
# mayhem/build.sh — build wuffs' fuzz harnesses (fuzz/c/std/*_fuzzer.c*, the OSS-Fuzz set) and its own
# functional tests (test/c/std/*.c). Wuffs is a single-file C library that each harness #includes, so the
# library is compiled sanitized, instrumented and with DWARF 3 as part of every harness translation unit.
set -euo pipefail

[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer}"
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${CC:=clang}" ; : "${CXX:=clang++}" ; : "${LIB_FUZZING_ENGINE:=-fsanitize=fuzzer}"
: "${MAYHEM_JOBS:=$(nproc)}"
: "${COVERAGE_FLAGS=}"
export SANITIZER_FLAGS DEBUG_FLAGS CC CXX LIB_FUZZING_ENGINE MAYHEM_JOBS COVERAGE_FLAGS

cd "$SRC"

# gen/ is gitignored upstream, so `git clean -ffdX` removes it and this script recreates it.
OBJ="$SRC/gen/mayhem-obj"
mkdir -p "$OBJ" "$SRC/gen/tests"

# Leak detection off at build time (ASan stays on); standalone driver as a C object so a C++ harness
# does not mangle its LLVMFuzzerTestOneInput reference.
$CXX $SANITIZER_FLAGS $DEBUG_FLAGS -c "$SRC/mayhem/lsan_off.cc" -o "$OBJ/lsan_off.o"
$CC -x c $SANITIZER_FLAGS $DEBUG_FLAGS -c "$STANDALONE_FUZZ_MAIN" -o "$OBJ/standalone_main.o"

build_harness() {
  local src="$1" name drv
  name="$(basename "$src")"; name="${name%_fuzzer.*}"
  case "$src" in *.cc) drv="$CXX" ;; *) drv="$CC" ;; esac
  # -O1 matches OSS-Fuzz's default level. -fno-sanitize=function is the only relaxed UBSan check: Wuffs'
  # by-design vtable upcasts call through a differently-typed function pointer on every decode, which
  # would abort every input. ASan and all other UBSan checks still halt.
  $drv -O1 $SANITIZER_FLAGS -fno-sanitize=function $DEBUG_FLAGS $LIB_FUZZING_ENGINE "$src" "$OBJ/lsan_off.o" -o "$SRC/$name"
  $drv -O1 $SANITIZER_FLAGS -fno-sanitize=function $DEBUG_FLAGS "$src" "$OBJ/standalone_main.o" "$OBJ/lsan_off.o" -o "$SRC/$name-standalone"
}

build_test() {
  local src="$1" name
  name="$(basename "$src" .c)"
  # The oracle build keeps the project's normal flags: no sanitizers, no DWARF pin.
  $CC -std=c99 -O1 $COVERAGE_FLAGS "$src" -o "$SRC/gen/tests/$name"
}

export -f build_harness build_test
export OBJ

ls fuzz/c/std/*_fuzzer.c fuzz/c/std/*_fuzzer.cc | xargs -P "$MAYHEM_JOBS" -I{} bash -c 'build_harness {}'
ls test/c/std/*.c | xargs -P "$MAYHEM_JOBS" -I{} bash -c 'build_test {}'
