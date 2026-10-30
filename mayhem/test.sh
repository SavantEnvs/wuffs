#!/usr/bin/env bash
#
# mayhem/test.sh — RUN wuffs' own test programs (test/c/std/*.c, built by mayhem/build.sh into gen/tests).
# Each program is a known-answer suite: it decodes/hashes/checksums files under test/data and compares the
# result with expected values, then prints "<pkg> <cc> PASS (N tests)". A program counts only if that line
# appears with N>0, so a neutered binary (exit 0, no output) fails here.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
cd "$SRC"

emit_ctrf() {
  local tool="$1" passed="$2" failed="$3" skipped="${4:-0}" pending="${5:-0}" other="${6:-0}"
  local tests=$(( passed + failed + skipped + pending + other ))
  cat > "${CTRF_REPORT:-$SRC/ctrf-report.json}" <<JSON
{
  "results": {
    "tool": { "name": "$tool" },
    "summary": {
      "tests": $tests,
      "passed": $passed,
      "failed": $failed,
      "pending": $pending,
      "skipped": $skipped,
      "other": $other
    }
  }
}
JSON
  printf 'CTRF {"results":{"tool":{"name":"%s"},"summary":{"tests":%d,"passed":%d,"failed":%d,"pending":%d,"skipped":%d,"other":%d}}}\n' \
    "$tool" "$tests" "$passed" "$failed" "$pending" "$skipped" "$other"
  [ "$failed" -eq 0 ]
}

shopt -s nullglob
progs=(gen/tests/*)
if [ "${#progs[@]}" -eq 0 ]; then
  echo "no test programs in gen/tests — mayhem/build.sh must build them" >&2
  emit_ctrf "wuffs-testlib" 0 1
  exit 1
fi

passed=0; failed=0
for p in "${progs[@]}"; do
  out="$("$p" 2>&1)"; rc=$?
  n="$(printf '%s\n' "$out" | sed -n 's/.* PASS (\([0-9][0-9]*\) tests)$/\1/p' | tail -n1)"
  if [ "$rc" -eq 0 ] && [ -n "$n" ] && [ "$n" -gt 0 ]; then
    echo "ok   $(basename "$p"): $n tests"
    passed=$(( passed + n ))
  else
    echo "FAIL $(basename "$p") (rc=$rc)"; printf '%s\n' "$out" | tail -n 5
    failed=$(( failed + 1 ))
  fi
done

emit_ctrf "wuffs-testlib" "$passed" "$failed"
