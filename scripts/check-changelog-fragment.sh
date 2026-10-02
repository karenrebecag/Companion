#!/bin/bash
# Exige exactamente un fragmento nuevo en changelog.d/ por PR y que solo el
# ensamblado toque CHANGELOG.md. Bash 3.2, herramientas BSD.
# Corre primero en gates.sh, antes del build, para fallar en segundos.
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

if [ -z "${GITHUB_BASE_REF:-}" ]; then
    echo "info  sin GITHUB_BASE_REF (corrida local): chequeo de fragmento omitido"
    exit 0
fi

base="origin/$GITHUB_BASE_REF"
if ! git -C "$ROOT" rev-parse --verify -q "$base" >/dev/null; then
    # Fallar cerrado: un checkout superficial sin la base dejaria pasar todo en silencio.
    echo "FAIL  no existe $base: el checkout necesita la base del PR (fetch-depth: 0)"
    exit 1
fi

# Mismas categorias que scripts/changelog-assemble.sh (VALID); si cambian, cambian en ambos.
NAME_RE='^changelog\.d/[^/]+\.(added|changed|fixed|security)\.md$'
USAGE="      Nombre: changelog.d/<slug-de-rama>.<added|changed|fixed|security>.md, en el nivel raiz
      Ejemplo: fix/voz-red -> changelog.d/fix-voz-red.fixed.md (ver changelog.d/README.md)"

# --no-renames: con deteccion de renombres, un fragmento movido saldria como R y no como A.
# Excluye README.md por nombre base, en cualquier subcarpeta.
changed() { # filtro de git (A|D)
    git -C "$ROOT" diff --no-renames --name-only --diff-filter="$1" "$base...HEAD" -- changelog.d \
        | grep -vE '(^|/)README\.md$' || true
}
count() { if [ -n "$1" ]; then printf '%s\n' "$1" | wc -l | tr -d ' '; else echo 0; fi; }

added=$(changed A)
deleted=$(changed D)
added_n=$(count "$added")
deleted_n=$(count "$deleted")
touches_changelog=$(git -C "$ROOT" diff --no-renames --name-only "$base...HEAD" -- CHANGELOG.md)

# Ensamblado de wave: borra fragmentos, no agrega ninguno y CHANGELOG.md solo
# gana lineas, todas las del texto de los fragmentos borrados. Sin esa
# comprobacion, "borre un fragmento" abriria la puerta a editar el historial.
is_faithful_assembly() {
    [ "$added_n" -eq 0 ] && [ "$deleted_n" -gt 0 ] && [ -n "$touches_changelog" ] || return 1
    # numstat marca binarios con "-": no son un ensamblado.
    gone=$(git -C "$ROOT" diff --no-renames --numstat "$base...HEAD" -- CHANGELOG.md | cut -f2)
    [ "$gone" = "0" ] || { echo "      CHANGELOG.md pierde lineas: el ensamblado solo agrega."; return 1; }
    mb=$(git -C "$ROOT" merge-base "$base" HEAD) || return 1
    plus=$(git -C "$ROOT" diff --no-renames -U0 "$base...HEAD" -- CHANGELOG.md \
        | grep '^+' | grep -v '^+++' | sed 's/^+//')
    ok=0
    for f in $deleted; do
        # Cada linea no vacia del fragmento debe estar entera entre las agregadas.
        while IFS= read -r line; do
            [ -z "${line//[[:space:]]/}" ] && continue
            printf '%s\n' "$plus" | grep -Fxq -- "$line" \
                || { echo "      el texto de $f no aparece en lo agregado a CHANGELOG.md."; ok=1; break; }
        done <<EOF
$(git -C "$ROOT" show "$mb:$f")
EOF
    done
    return $ok
}

if is_faithful_assembly; then
    echo "  ok  ensamblado de wave: $deleted_n fragmentos pasan a CHANGELOG.md"
    exit 0
fi

rc=0
if [ -n "$touches_changelog" ]; then
    echo "FAIL  el PR edita CHANGELOG.md; solo el ensamblado (scripts/changelog-assemble.sh) lo toca."
    echo "      Deja tu entrada como fragmento en changelog.d/ y revierte el cambio a CHANGELOG.md."
    rc=1
fi
bad=$(printf '%s\n' "$added" | grep -vE "$NAME_RE" | grep -v '^$' || true)
if [ -n "$bad" ]; then
    echo "FAIL  nombre de fragmento invalido:"
    printf '        %s\n' $bad
    echo "$USAGE"
    rc=1
fi
if [ "$added_n" -ne 1 ]; then
    echo "FAIL  el PR agrega $added_n fragmentos en changelog.d/ (debe ser exactamente 1)."
    echo "$USAGE"
    rc=1
fi
[ "$rc" -eq 0 ] && echo "  ok  un fragmento nuevo en changelog.d/"
exit $rc
