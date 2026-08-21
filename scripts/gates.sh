#!/bin/bash
# Compliance de Companion (rebuild). Bash 3.2, herramientas del sistema.
# Cuatro gates: build, estatico, arquitectura, tests. Exit != 0 si alguna falla.
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/Sources"
fails=0
warns=0
pass()    { echo "  ok  $1"; }
fail()    { echo "FAIL  $1"; fails=$((fails + 1)); }
warn()    { echo "warn  $1"; warns=$((warns + 1)); }
section() { echo; echo "== $1"; }

# ---------------------------------------------------------------- Gate 1: build
section "Gate 1 — build"
if (cd "$ROOT" && swift build 2>&1 | tail -5 | grep -q "Build complete"); then
    pass "swift build compila"
else
    fail "swift build fallo"
    (cd "$ROOT" && swift build 2>&1 | tail -15)
fi

# ------------------------------------------------------------- Gate 2: estatico
section "Gate 2 — estatico"
if grep -rnE "(sk-[A-Za-z0-9_-]{20,}|sk_[A-Za-z0-9]{20,}|gsk_[A-Za-z0-9]{16,}|xai-[A-Za-z0-9]{16,}|AKIA[0-9A-Z]{16})" \
        "$SRC" 2>/dev/null; then
    fail "posible secreto hardcodeado (lineas arriba)"
else
    pass "sin secretos hardcodeados"
fi

noise=$(grep -rn 'NSLog\|debugPrint\|[^.[:alnum:]_]print(' "$SRC" 2>/dev/null || true)
if [ -n "$noise" ]; then
    fail "salida de debug en Sources (usar Log):"
    echo "$noise"
else
    pass "sin print/NSLog/debugPrint"
fi

# Regla de la casa: 200-400 lineas tipico, 800 tope duro.
long=0
for f in $(find "$SRC" -name "*.swift"); do
    n=$(wc -l < "$f" | tr -d ' ')
    if [ "$n" -gt 800 ]; then
        fail "$(basename "$f") tiene $n lineas (tope 800)"
        long=1
    elif [ "$n" -gt 400 ]; then
        warn "$(basename "$f") tiene $n lineas (>400: candidato a partir)"
    fi
done
[ "$long" -eq 0 ] && pass "ningun archivo supera 800 lineas"

# Errores tragados: try? esta prohibido en Core y Services (la leccion mas
# cara del proyecto original). En UI se tolera con warn.
swallowed=$(grep -rn 'try?' "$SRC/CompanionCore" "$SRC/CompanionServices" 2>/dev/null || true)
if [ -n "$swallowed" ]; then
    fail "try? en Core/Services (manejar o propagar, nunca tragar):"
    echo "$swallowed"
else
    pass "sin try? en Core/Services"
fi

# TCC no muestra el prompt de microfono/voz sin usage descriptions: si se
# pierden del bundle, la voz falla en runtime y ningun test lo ve.
for key in NSMicrophoneUsageDescription NSSpeechRecognitionUsageDescription; do
    if grep -q "$key" "$ROOT/scripts/bundle.sh" 2>/dev/null; then
        pass "bundle declara $key"
    else
        fail "bundle.sh sin $key"
    fi
done

# --------------------------------------------------------- Gate 3: arquitectura
# Las dependencias entre targets ya las vigila SPM; esto vigila los imports
# de frameworks de Apple que rompen la pureza de cada capa.
section "Gate 3 — arquitectura"
check_imports() {
    dir="$1"; forbidden="$2"; label="$3"
    hits=$(grep -rnE "^import ($forbidden)$" "$SRC/$dir" 2>/dev/null || true)
    if [ -n "$hits" ]; then
        fail "$label:"
        echo "$hits"
    else
        pass "$label"
    fi
}
check_imports CompanionCore     "SwiftUI|AppKit|AVFoundation|WebKit|Combine" \
    "Core es puro (sin SwiftUI/AppKit/AVFoundation/WebKit/Combine)"
check_imports CompanionServices "SwiftUI" \
    "Services no importa SwiftUI"
check_imports CompanionUI       "AVFoundation|WebKit" \
    "UI no importa AVFoundation/WebKit"

# -------------------------------------------------------------- Gate 4: tests
section "Gate 4 — tests"
out=$(cd "$ROOT" && swift test 2>&1)
rc=$?
if [ $rc -eq 0 ]; then
    pass "swift test verde — $(echo "$out" | grep -oE 'with [0-9]+ tests? in [0-9]+ suites?' | tail -1)"
else
    fail "swift test fallo:"
    echo "$out" | tail -20
fi

# ------------------------------------------------------------------- Resumen
echo
echo "$fails fallos, $warns avisos"
exit $((fails > 0 ? 1 : 0))
