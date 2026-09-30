#!/bin/bash
# Packaging smoke (wave 21c, D5/D9/D10). Runs the resource probe of a signed
# .app with this checkout unreadable, so the app can only pass on what it
# carries. On the build Mac the SwiftPM accessor falls back to the checkout's
# .build and "works" with a broken layout; that is the false green this
# script exists to rule out (docs/research/recursos-empaquetados-bundle-module.md §8).
#
# usage: scripts/package-smoke.sh <path/to/App.app>
# Exit 0 only when every assertion held. bundle.sh calls it after codesign and
# stops before installing when it fails.
set -euo pipefail

APP_ARG="${1:?usage: package-smoke.sh <path/to/App.app>}"
ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
APP="$(cd "$APP_ARG" && pwd -P)"
MARKER="COMPANION_RESOURCE_PROBE_OK"
BUNDLES="Companion_CompanionUI.bundle Companion_CompanionServices.bundle"
# A healthy probe finishes in well under a second; a hang is a failure.
PROBE_TIMEOUT=60

fails=0
ok()   { echo "  smoke ok    $*"; }
fail() { echo "  smoke FAIL  $*" >&2; fails=$((fails + 1)); }
die()  { echo "  smoke FAIL  $*" >&2; exit 1; }

# D10: Apple marks sandbox-exec deprecated. If it disappears the gate must
# fail and the decision reopens, never pass without isolation.
command -v sandbox-exec >/dev/null 2>&1 \
    || die "sandbox-exec no existe en esta Mac: el smoke no puede aislar el checkout (reabrir D10)"

WORK="$(mktemp -d)"
WORK="$(cd "$WORK" && pwd -P)"
trap 'rm -rf "$WORK"' EXIT
case "$WORK/" in "$ROOT/"*) die "el directorio temporal quedo dentro del checkout: $WORK" ;; esac

# Everything under the checkout, .build included, is unreadable.
PROFILE="(version 1)(allow default)(deny file-read* (subpath \"$ROOT\"))"

copy_app() { # $1 destination .app
    mkdir -p "$(dirname "$1")"
    ditto "$APP" "$1"
}

# Prints the exit code; stdout/stderr land in $2.out / $2.err.
run_probe() { # $1 .app  $2 output prefix
    local rc=0
    COMPANION_RESOURCE_PROBE=1 perl -e 'alarm shift; exec @ARGV' "$PROBE_TIMEOUT" \
        sandbox-exec -p "$PROFILE" "$1/Contents/MacOS/Companion" >"$2.out" 2>"$2.err" || rc=$?
    echo "$rc"
}

no_accessor_trap() { # $1 label  $2 prefix
    if grep -q "could not load resource bundle" "$2.err"; then
        fail "$1: stderr trae 'could not load resource bundle' (el accessor de SwiftPM hizo trap)"
    fi
}

# ---------------------------------------------------------------- self-test
echo "== smoke: sandbox self-test (D10)"
[ -r "$ROOT/Package.swift" ] && [ -d "$ROOT/.build" ] \
    || die "self-test sin control: faltan $ROOT/Package.swift o $ROOT/.build fuera del sandbox"
ISOLATED="$WORK/isolated/Companion.app"
copy_app "$ISOLATED"
sandbox-exec -p "$PROFILE" /bin/cat "$ISOLATED/Contents/Info.plist" >/dev/null 2>&1 \
    || die "el sandbox no deja leer ni fuera del checkout: el perfil no sirve de control"
if sandbox-exec -p "$PROFILE" /bin/cat "$ROOT/Package.swift" >/dev/null 2>&1; then
    die "el sandbox NO niega leer $ROOT/Package.swift: el smoke daria un falso verde"
fi
if sandbox-exec -p "$PROFILE" /bin/ls "$ROOT/.build" >/dev/null 2>&1; then
    die "el sandbox NO niega leer $ROOT/.build: el accessor podria caer ahi"
fi
ok "el sandbox niega el checkout y su .build, y deja leer la copia de la app"

# ---------------------------------------------------------------- layout
echo "== smoke: layout y firma"
root_entries="$(ls -A "$APP")"
[ "$root_entries" = "Contents" ] || fail "la raiz de la .app tiene algo mas que Contents: $(echo "$root_entries" | tr '\n' ' ')"
while IFS= read -r found; do
    [ "$(dirname "$found")" = "$APP/Contents/Resources" ] || fail "bundle fuera de Contents/Resources: $found"
done < <(find "$APP" -name '*.bundle' -type d -prune)
for bundle in $BUNDLES; do
    [ -d "$APP/Contents/Resources/$bundle" ] || fail "falta Contents/Resources/$bundle"
done
[ -e "$APP/Contents/Resources/Fonts" ] && fail "fuentes duplicadas en Contents/Resources/Fonts (van solo en el bundle de UI)"
[ -f "$APP/Contents/Resources/Companion_CompanionUI.bundle/Fonts/OFL.txt" ] \
    || fail "la licencia OFL no viaja con las fuentes en el bundle de UI"
[ -f "$APP/Contents/Resources/BrowserExtension/manifest.json" ] \
    || fail "falta Contents/Resources/BrowserExtension/manifest.json (D9)"
if codesign --verify --strict "$APP" 2>"$WORK/codesign.err"; then
    ok "codesign --verify --strict"
else
    fail "codesign --verify --strict: $(cat "$WORK/codesign.err")"
fi
[ "$fails" -eq 0 ] && ok "bundles solo en Contents/Resources, fuentes en un solo lugar, extension presente"

# ---------------------------------------------------------------- probe passes
expected_skills=$(find "$ROOT/Sources/CompanionServices/Skills" -mindepth 2 -maxdepth 2 -name SKILL.md | wc -l | tr -d ' ')

assert_probe_passes() { # $1 label  $2 .app
    local label="$1" app="$2" prefix="$WORK/$1" before=$fails rc key line path
    rc=$(run_probe "$app" "$prefix")
    if [ "$rc" -ge 128 ]; then
        fail "$label: el probe murio por senal (rc=$rc)"
    elif [ "$rc" -ne 0 ]; then
        fail "$label: el probe salio con $rc"
    fi
    grep -qx "$MARKER" "$prefix.out" || fail "$label: no llego el marcador $MARKER"
    no_accessor_trap "$label" "$prefix"
    for key in bundle.ui bundle.services browserExtension; do
        line="$(grep -m1 "^probe ok $key=" "$prefix.out" || true)"
        path="${line#probe ok "$key"=}"
        # Bundle reports /var/... for a copy under /private/var: compare real
        # paths. A link into the checkout resolves there and still fails.
        [ -n "$path" ] && path="$( (cd "$path" 2>/dev/null && pwd -P) || echo "$path")"
        case "$path/" in
            "$app/Contents/Resources/"*) ;;
            *) fail "$label: $key no resolvio dentro de $app/Contents/Resources: '${path:-sin linea}'" ;;
        esac
    done
    grep -qx "probe ok skills=$expected_skills" "$prefix.out" \
        || fail "$label: skills no coincide con los $expected_skills Skills/*/SKILL.md del arbol"
    if [ "$fails" -eq "$before" ]; then
        ok "$label: marcador, rc=0, bundleURLs dentro de Contents/Resources"
    else
        sed 's/^/    /' "$prefix.out" "$prefix.err" >&2
    fi
}

echo "== smoke: probe con el checkout inaccesible"
assert_probe_passes isolated "$ISOLATED"
RELOCATED="$WORK/otra carpeta/Companion movida.app"
copy_app "$RELOCATED"
assert_probe_passes relocated "$RELOCATED"

# ---------------------------------------------------------------- negative controls
# A probe that reported green without its resources would make every check
# above meaningless; these copies must fail, cleanly, by name.
assert_probe_fails() { # $1 label  $2 .app  $3 check names that must FAIL
    local label="$1" app="$2" prefix="$WORK/$1" before=$fails rc name
    rc=$(run_probe "$app" "$prefix")
    if [ "$rc" -eq 0 ]; then
        fail "$label: el probe paso sin sus recursos"
    elif [ "$rc" -ge 128 ]; then
        fail "$label: murio por senal (rc=$rc) en vez de reportar"
    fi
    grep -qx "$MARKER" "$prefix.out" && fail "$label: imprimio el marcador sin sus recursos"
    no_accessor_trap "$label" "$prefix"
    for name in $3; do
        grep -q "^probe FAIL $name=" "$prefix.out" || fail "$label: no reporto el fallo de $name"
    done
    if [ "$fails" -eq "$before" ]; then
        ok "$label: rc=$rc, sin trap, reporta: $3"
    else
        sed 's/^/    /' "$prefix.out" "$prefix.err" >&2
    fi
}

echo "== smoke: controles negativos"
NO_BUNDLES="$WORK/no-bundles/Companion.app"
copy_app "$NO_BUNDLES"
for bundle in $BUNDLES; do rm -rf "${NO_BUNDLES:?}/Contents/Resources/$bundle"; done
assert_probe_fails no-bundles "$NO_BUNDLES" "bundle.ui lproj.en lproj.es font mascot bundle.services skills mermaid"

NO_EXTENSION="$WORK/no-extension/Companion.app"
copy_app "$NO_EXTENSION"
rm -rf "${NO_EXTENSION:?}/Contents/Resources/BrowserExtension"
assert_probe_fails no-extension "$NO_EXTENSION" "browserExtension"

echo
if [ "$fails" -gt 0 ]; then
    echo "smoke de empaquetado: $fails fallos" >&2
    exit 1
fi
echo "smoke de empaquetado: verde"
