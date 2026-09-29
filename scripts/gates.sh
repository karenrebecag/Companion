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
swallowed=$(grep -rnE '(^|[^[:alnum:]_])try\?' "$SRC/CompanionCore" "$SRC/CompanionServices" 2>/dev/null || true)
if [ -n "$swallowed" ]; then
    fail "try? en Core/Services (manejar o propagar, nunca tragar):"
    echo "$swallowed"
else
    pass "sin try? en Core/Services"
fi

# Revision de seguridad 2026-09-25 (CRITICAL-1): la cache en disco de
# URLSession guardaba keys y cuerpos con contexto de pantalla. Toda sesion
# sale de NoStoreSession (ChatTransport.swift); cualquier otra se rechaza.
cache_hits=$(grep -rnE 'URLSession\.shared|URLSessionConfiguration\.(default|ephemeral)|configuration: *\.(default|ephemeral)|URLCache\(' \
        "$SRC" --include='*.swift' 2>/dev/null \
    | grep -vE '/ChatTransport\.swift:|/LegacyURLCachePurge\.swift:' || true)
# Una sesion propia (con delegate) vale solo si su configuracion es la comun;
# se mira la linea del constructor y la siguiente.
session_hits=$(grep -rnE -A1 'URLSession\((configuration:.*)?$|URLSession\(configuration:' \
        "$SRC" --include='*.swift' 2>/dev/null \
    | grep -E 'configuration:' | grep -v 'NoStoreSession' \
    | grep -vE '/ChatTransport\.swift[-:]' || true)
if [ -n "$cache_hits$session_hits" ]; then
    fail "URLSession fuera de NoStoreSession (cachea keys y cuerpos en disco):"
    printf '%s\n' "$cache_hits" "$session_hits" | grep -v '^$'
else
    pass "toda URLSession sale de NoStoreSession (sin cache en disco)"
fi

# TCC no muestra el prompt de microfono/voz sin usage descriptions: si se
# pierden del bundle, la voz falla en runtime y ningun test lo ve.
for key in NSMicrophoneUsageDescription NSSpeechRecognitionUsageDescription NSScreenCaptureUsageDescription NSLocationWhenInUseUsageDescription NSLocationUsageDescription NSContactsUsageDescription; do
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
check_imports CompanionCore     "SwiftUI|AppKit|AVFoundation|WebKit|Combine|CoreLocation|MapKit" \
    "Core es puro (sin SwiftUI/AppKit/AVFoundation/WebKit/Combine/CoreLocation/MapKit)"
check_imports CompanionServices "SwiftUI" \
    "Services no importa SwiftUI"
check_imports CompanionUI       "AVFoundation|WebKit" \
    "UI no importa AVFoundation/WebKit"

# Revision 16h-2 ronda 3: la proyeccion de sesion tiene un solo escritor, el
# reductor (SessionMachine.swift + SessionMachineJobs.swift + SessionMachineDictation.swift).
# Fuera de Core
# solo se copia su salida entera (SessionModel: `= machine.projection`).
proj_write='(^|[^[:alnum:]_])projection(\??\.[[:alnum:]_?.]+|\[[^]]*\])*[[:space:]]*([-+]?=[^=]|\.(append|remove[[:alnum:]]*|insert)\()'
proj_hits=$(grep -rnE "$proj_write" "$SRC" --include='*.swift' 2>/dev/null \
    | grep -vE '/CompanionCore/SessionMachine(Jobs|Dictation)?\.swift:' \
    | grep -vE '(let|var)[[:space:]]+projection[[:space:]:=]|= machine\.projection$' || true)
if [ -n "$proj_hits" ]; then
    fail "escritura de la proyeccion fuera del reductor:"
    echo "$proj_hits"
else
    pass "la proyeccion solo la escribe el reductor"
fi
# Una extension de SessionMachine en otro archivo heredaria el setter de
# `projection` y esquivaria el chequeo de arriba.
ext_hits=$(grep -rnE '^[[:space:]]*(public[[:space:]]+|internal[[:space:]]+)?extension[[:space:]]+SessionMachine([^[:alnum:]_]|$)' \
        "$SRC" --include='*.swift' 2>/dev/null \
    | grep -vE '/CompanionCore/SessionMachine(Jobs|Dictation)?\.swift:' || true)
if [ -n "$ext_hits" ]; then
    fail "extension SessionMachine fuera de SessionMachine(Jobs|Dictation).swift:"
    echo "$ext_hits"
else
    pass "SessionMachine solo se extiende en su propio archivo"
fi

# Literales de padding/spacing/cornerRadius: un solo sistema de tokens.
# Valvula: // token-exempt:  (WHY en el mismo comentario)
spacing_hits=$(grep -rnE \
    '\.padding\([0-9]|\.padding\(\.(horizontal|vertical|top|bottom|leading|trailing|all), *[0-9]|spacing: *[0-9]|cornerRadius\([0-9]' \
    "$SRC/CompanionUI" --include='*.swift' 2>/dev/null \
    | grep -v 'token-exempt:' || true)
if [ -n "$spacing_hits" ]; then
    fail "CompanionUI: padding/spacing literal (usar Space/Radius):"
    echo "$spacing_hits"
else
    pass "CompanionUI sin literales de padding/spacing (cornerRadius: lo cubre el contrato)"
fi

# Reticula: el escaneo profundo (radios, frames, aritmetica sobre Space,
# .system(size:), opacidad sobre roles, duraciones, copy con ?? o ternario)
# vive en conformance/ui-contract.json y lo ejecuta uiConformanceTests dentro
# de Gate 4. Aqui solo se hace visible la deuda: el numero solo puede bajar.
if [ -f "$ROOT/conformance/ui-contract.json" ]; then
    debt=$(python3 -c "
import json
b = json.load(open('$ROOT/conformance/ui-contract.json'))['baseline']
print(f\"{len(b)} archivos, {sum(sum(v.values()) for v in b.values())} infracciones\")
" 2>/dev/null || echo "no medible")
    pass "reticula: ratchet en $debt (Gate 4 lo aplica)"
else
    fail "falta conformance/ui-contract.json"
fi

# El libro de puertas del HUD (12d): cada puerta cita los tests que la
# prueban; hudGatesTests (Gate 4) falla si cita uno que ya no existe.
if [ -f "$ROOT/conformance/hud-gates.json" ]; then
    gates=$(python3 -c "
import json
print(len(json.load(open('$ROOT/conformance/hud-gates.json'))['gates']))
" 2>/dev/null || echo "?")
    pass "libro de puertas del HUD: $gates puertas (Gate 4 lo aplica)"
else
    fail "falta conformance/hud-gates.json"
fi

# Copy que no pasa por el catalogo: la UI nace monolingue otra vez. Se mira
# donde el usuario lee — Text(...), help, accessibilityLabel — y se exime lo
# que no es copy (identificadores, simbolos SF) con token-exempt.
copy_hits=$(grep -rnE \
    '(Text\(|\.help\(|\.accessibilityLabel\()"[^"]{3,}"' \
    "$SRC/CompanionUI" --include='*.swift' 2>/dev/null \
    | grep -v 'token-exempt:' || true)
if [ -n "$copy_hits" ]; then
    fail "CompanionUI: texto literal fuera del catalogo (usar Localized):"
    echo "$copy_hits"
else
    pass "CompanionUI sin texto literal pegado a Text( (?? y ternarios los cubre el contrato)"
fi

# -------------------------------------------------------------- Gate 4: tests
section "Gate 4 — tests"
# HACK: serial solo en CI. El runner de GitHub tiene 3 vCPU y la suite
# bloquea threads reales con semaforos (runOk/runAsync): en paralelo el pool
# cooperativo se muere de inanicion en cascada (corrida 36447876523, 13
# dispatchers caidos a los ~5s). En local (mas cores) el paralelo se queda
# como esta. Upgrade trigger: migrar los helpers de semaforo a espera
# estructurada y quitar el flag.
test_flags=""
[ "${CI:-}" = "true" ] && test_flags="--no-parallel"
out=$(cd "$ROOT" && swift test $test_flags 2>&1)
rc=$?
if [ $rc -eq 0 ]; then
    pass "swift test verde — $(echo "$out" | grep -oE 'with [0-9]+ tests? in [0-9]+ suites?' | tail -1)"
else
    fail "swift test fallo:"
    echo "$out" | tail -20
    # Debugging 2026-09-28: las ultimas 20 lineas casi nunca alcanzan cuando
    # falla un dispatcher que agrupa muchos sub-tests (Issue recorded llega
    # antes del resumen) — sin esto el detalle se perdia y solo quedaba
    # "fallo con 1 issue" para adivinar cual.
    echo
    echo "-- detalle del fallo (busqueda en toda la salida, no solo el final) --"
    echo "$out" | grep -E '✘|↳|Issue recorded|Expectation failed'
fi

# ------------------------------------------------------------------- Resumen
echo
echo "$fails fallos, $warns avisos"
exit $((fails > 0 ? 1 : 0))
