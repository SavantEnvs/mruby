#!/usr/bin/env bash
#
# mayhem/test.sh — RUN mruby's OWN functional test suite (mrbtest), already built by
# mayhem/build.sh into build/oracle/bin/mrbtest (mruby's normal, uninstrumented flags).
#
# mrbtest is upstream's real assertion suite (test/t/*.rb + every mrbgem's test/*.rb, ~2500
# assertions over the VM, the compiler, String/Array/Hash/Regexp/Time/Struct/BigInt/...). It
# asserts VALUES, not exit codes, so a PATCH that neuters mruby to a no-op fails it.
#
# This script only RUNS the pre-built binary and maps its summary to a CTRF report; it never
# compiles (a missing runner is a build.sh bug and fails loudly).
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
: "${SRC:=/mayhem}"
cd "$SRC"

# emit_ctrf <tool> <passed> <failed> [skipped] [pending] [other]
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

MRBTEST="$SRC/build/oracle/bin/mrbtest"
if [ ! -x "$MRBTEST" ]; then
  echo "ERROR: $MRBTEST is missing — mayhem/build.sh must build the test suite" >&2
  emit_ctrf "mrbtest" 0 1 0
  exit 1
fi

OUT="$(mktemp)"
"$MRBTEST" >"$OUT" 2>&1
rc=$?
tail -20 "$OUT"

# mrbtest's summary block:
#     Total: 2555
#        OK: 2492
#        KO: 0
#     Crash: 0
#      Skip: 63
num() { sed -n -E "s/^[[:space:]]*$1:[[:space:]]*([0-9]+).*/\1/p" "$OUT" | tail -1; }
total="$(num Total)"; ok="$(num OK)"; ko="$(num KO)"; crash="$(num Crash)"; skip="$(num Skip)"
rm -f "$OUT"

# No parseable summary => the suite did not really run (e.g. the binary was neutered). That is a
# FAILURE, never a silent pass.
if [ -z "$total" ] || [ -z "$ok" ] || [ -z "$ko" ]; then
  echo "ERROR: mrbtest produced no parseable summary (exit $rc) — the suite did not run" >&2
  emit_ctrf "mrbtest" 0 1 0
  exit 1
fi

failed=$(( ko + ${crash:-0} ))
# Sanity: the reported assertions must add up AND the suite must actually have asserted something.
if [ "$ok" -eq 0 ] || [ "$total" -eq 0 ]; then
  echo "ERROR: mrbtest reported 0 passing assertions (Total=$total OK=$ok) — the suite did not run" >&2
  emit_ctrf "mrbtest" 0 1 0
  exit 1
fi
if [ "$rc" -ne 0 ] && [ "$failed" -eq 0 ]; then
  echo "ERROR: mrbtest exited $rc without reporting a failure" >&2
  failed=1
fi

emit_ctrf "mrbtest" "$ok" "$failed" "${skip:-0}"
