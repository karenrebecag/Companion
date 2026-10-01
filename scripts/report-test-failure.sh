#!/bin/bash
# Usage: report-test-failure.sh <rc> <swift-test-output-file>
# Explains a failed `swift test` that the tail of its output does not. When
# the test process dies, swift test still exits 1, SwiftPM prints the signal
# on stderr ahead of the buffered test output, and SIGKILL/SIGTERM/SIGINT
# print nothing at all; docs/research/gate4-reporte-sin-resumen.md.
# Prints the exit code, any signal, and the tests that started but never
# finished. Exits 0: the caller has already failed the gate. Bash 3.2.
set -u

rc="${1:-}"
out="${2:-}"
case "$rc" in ''|*[!0-9]*) echo "report-test-failure: usage: <rc> <output file>"; exit 2 ;; esac
if [ ! -r "$out" ]; then
    echo "report-test-failure: cannot read $out"
    exit 2
fi

echo "rc=$rc"
# Only when swift test itself was killed; its buffered stdout may be lost.
if [ "$rc" -gt 128 ]; then
    echo "senal: SIG$(kill -l "$rc" 2>/dev/null || echo "?") (rc $rc); la salida pudo quedar truncada"
fi

sig_line=$(grep -m1 -E 'exited with unexpected signal code [0-9]+' "$out")
if [ -n "$sig_line" ]; then
    code=$(echo "$sig_line" | sed -E 's/.*unexpected signal code ([0-9]+).*/\1/')
    echo "el proceso de tests murio por SIG$(kill -l "$code" 2>/dev/null || echo "?"): $sig_line"
fi

grep -q 'Test run with' "$out" && exit 0
echo "el proceso de tests murio sin resumen (no hay \"Test run with\")"
[ -z "$sig_line" ] && echo "sin linea de senal: SIGKILL, SIGTERM, SIGINT o un exit() del codigo"
# A test is open from its started line until a line names it with a verb;
# a parameterized test puts "with N test cases" between the name and the verb.
awk '
# Swift Testing announces the whole run with the same shape as a test, and
# each parameterized case with a start that never gets an end line.
/^◇ Test run started\.$/ { next }
/^◇ Test case passing / { next }
/^◇ Test .* started\.$/ {
    name = $0; sub(/^◇ Test /, "", name); sub(/ started\.$/, "", name)
    if (!(name in seen)) { seen[name] = 1; order[++count] = name }
    next
}
/^[^ ]+ Test / && / (passed|failed|was cancelled) after / {
    name = $0; sub(/^[^ ]+ Test /, "", name)
    if (match(name, / with [0-9]+ test cases? (passed|failed|was cancelled) after /)) name = substr(name, 1, RSTART - 1)
    else if (match(name, / (passed|failed|was cancelled) after /)) name = substr(name, 1, RSTART - 1)
    closed[name] = 1
}
END { for (i = 1; i <= count; i++) if (!(order[i] in closed)) print "sin cierre: " order[i] }
' "$out"
exit 0
