#!/bin/bash
# ThreadSanitizer sobre la suite completa: el mismo comando en CI y en local
# (docs/specs/tsan-gate.md). Exit != 0 si TSan avisa o si un test falla.
#
# Corre en el .build por defecto, igual que el job de CI en su runner limpio.
# No lo corras a la vez que gates.sh en el mismo checkout: el build con y sin
# sanitizer comparte .build/<triple>/debug y uno pisa los binarios del otro.
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# Serial por la misma razon que Gate 4 en CI: 3 vCPU y helpers con semaforos
# matan de inanicion al pool cooperativo en paralelo. TSAN_JOBS limita el
# build en una Mac compartida.
test_flags="--no-parallel"
[ -n "${TSAN_JOBS:-}" ] && test_flags="$test_flags --jobs $TSAN_JOBS"

out=$(cd "$ROOT" && swift test --sanitize=thread $test_flags 2>&1)
rc=$?
warnings=$(echo "$out" | grep -c "WARNING: ThreadSanitizer" || true)

echo "$out" | grep -E 'Test run with' | tail -1
# Un aviso de TSan mata al helper de tests con senal 6 aunque cada test diga
# "passed": el gate se decide por el codigo de salida, y los avisos se
# imprimen enteros para no tener que reproducirlos a mano.
# Un aviso falla por si solo: si un cambio de TSAN_OPTIONS dejara salir 0, el
# gate no puede quedar en verde con avisos impresos.
if [ "$warnings" -gt 0 ]; then
    echo "FAIL  ThreadSanitizer: $warnings avisos"
    echo "$out" | awk '/WARNING: ThreadSanitizer/,/^SUMMARY: ThreadSanitizer/'
    exit 1
fi
if [ $rc -ne 0 ]; then
    echo "FAIL  swift test --sanitize=thread salio con $rc"
    # Un build roto no deja ninguna linea de tests: sin el error del
    # compilador el log de CI solo diria el codigo de salida.
    echo "$out" | grep -E '✘|↳|Issue recorded|Expectation failed|error:' | head -40
    echo "-- final de la salida --"
    echo "$out" | tail -20
    exit 1
fi
echo "  ok  TSan sin avisos"
