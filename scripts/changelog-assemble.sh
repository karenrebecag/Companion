#!/bin/bash
# Ensambla changelog.d/<slug>.<categoria>.md bajo "## [Unreleased]" de CHANGELOG.md.
# Bash 3.2, herramientas del sistema (awk/sort BSD), sin dependencias.
# Uso: scripts/changelog-assemble.sh [--dry-run]
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FRAG_DIR="$ROOT/changelog.d"
CHANGELOG="$ROOT/CHANGELOG.md"
VALID="added|changed|fixed|security"

dry=0
case "${1:-}" in
    "") ;;
    --dry-run) dry=1 ;;
    *) echo "uso: changelog-assemble.sh [--dry-run]" >&2; exit 2 ;;
esac

die() { echo "changelog-assemble: $1" >&2; exit 1; }

# LC_ALL=C fija el orden entre maquinas; el glob ya ordena igual, pero sort lo hace explicito.
frags=$(ls "$FRAG_DIR"/*.md 2>/dev/null | LC_ALL=C sort | grep -v '/README\.md$')
[ -z "$frags" ] && exit 0

# Los nombres se iteran sin comillas (Bash 3.2, sin mapfile): un espacio los partiria.
bad=$(echo "$frags" | sed 's#.*/##' | grep -v '^[A-Za-z0-9._-]*$' | head -1)
[ -z "$bad" ] || die "$bad: el nombre solo admite letras, digitos, '.', '_' y '-'"

[ -f "$CHANGELOG" ] || die "no existe CHANGELOG.md"
grep -q '^## \[Unreleased\]' "$CHANGELOG" || die "CHANGELOG.md no tiene '## [Unreleased]'"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# Validar todo antes de escribir: un fragmento malo no debe dejar el CHANGELOG a medias.
for f in $frags; do
    base=$(basename "$f" .md)
    cat=${base##*.}
    slug=${base%.*}
    if [ "$slug" = "$base" ] || [ -z "$slug" ]; then
        die "$(basename "$f"): el nombre debe ser <slug>.<$VALID>.md"
    fi
    case "$cat" in
        added|changed|fixed|security) ;;
        *) die "$(basename "$f"): categoria '$cat' desconocida; usa $VALID" ;;
    esac
    grep -q '[^[:space:]]' "$f" || die "$(basename "$f"): el fragmento esta vacio"
done

for f in $frags; do
    cat=${f%.md}
    cat=${cat##*.}
    # El primer caracter en mayuscula coincide con el encabezado ### de Keep a Changelog.
    head=$(echo "$cat" | awk '{print toupper(substr($0,1,1)) substr($0,2)}')
    # Sin lineas en blanco finales para que los bullets de distintos fragmentos queden contiguos.
    awk 'NF{while(b-->0)print ""; b=0; print; next} {b++}' "$f" >> "$work/new.$head"
done

awk -v dir="$work" '
BEGIN {
    n = split("Added Changed Fixed Security", order, " ")
    for (i = 1; i <= n; i++) {
        rank[order[i]] = i
        file = dir "/new." order[i]
        body[order[i]] = ""
        while ((getline line < file) > 0) body[order[i]] = body[order[i]] line "\n"
        close(file)
        has[order[i]] = (body[order[i]] != "")
    }
}
# Primera pasada: que encabezados ya existen bajo Unreleased.
NR == FNR {
    if ($0 ~ /^## /) inun = ($0 ~ /^## \[Unreleased\]/)
    else if (inun && $0 ~ /^### /) exists[substr($0, 5)] = 1
    next
}
function emit_missing(limit,    i) {
    for (i = 1; i <= n; i++)
        if (has[order[i]] && !exists[order[i]] && !done[order[i]] && i < limit) {
            printf "### %s\n%s\n", order[i], body[order[i]]
            done[order[i]] = 1
        }
}
function flush_pending() {
    if (pend != "") { printf "%s", body[pend]; done[pend] = 1; pend = "" }
}
# Sin reiniciar, la segunda lectura hereda el estado final de la primera.
FNR == 1 { inun = 0 }
{
    if (pend != "") {
        # Un blanco tras el encabezado se respeta; los bullets nuevos van pegados a los viejos.
        if ($0 == "") { print; flush_pending(); prevblank = 1; next }
        flush_pending()
    }
    if ($0 ~ /^## /) {
        if (inun) { emit_missing(n + 1) }
        inun = ($0 ~ /^## \[Unreleased\]/)
    } else if (inun && $0 ~ /^### /) {
        h = substr($0, 5)
        emit_missing(rank[h] ? rank[h] : n + 1)
        print
        if (has[h] && !done[h]) pend = h
        prevblank = 0
        next
    }
    print
    prevblank = ($0 == "")
}
END {
    flush_pending()
    if (inun) {
        # Unreleased era la ultima seccion: separar con una linea en blanco.
        pending = 0
        for (i = 1; i <= n; i++) if (has[order[i]] && !exists[order[i]] && !done[order[i]]) pending = 1
        if (pending && !prevblank) print ""
        emit_missing(n + 1)
    }
}
' "$CHANGELOG" "$CHANGELOG" > "$work/out" || die "fallo el ensamblado"

if [ "$dry" -eq 1 ]; then
    cat "$work/out"
    exit 0
fi

cat "$work/out" > "$CHANGELOG"
for f in $frags; do
    # Un fragmento aun sin git add no esta en el indice; rm normal basta.
    git -C "$ROOT" rm -q -f -- "$f" 2>/dev/null || rm -f "$f"
done
echo "changelog-assemble: $(echo "$frags" | wc -l | tr -d ' ') fragmento(s) ensamblados"
