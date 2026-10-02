#!/bin/bash
# Tests de scripts/check-changelog-fragment.sh sobre un repo git temporal.
# Bash 3.2, sin dependencias. Exit != 0 si algun caso falla.
set -u
# Bajo un hook de git estas variables apuntarian el fixture al repo real.
unset GIT_DIR GIT_INDEX_FILE GIT_WORK_TREE GITHUB_BASE_REF
# Sin config de la maquina (hooks, templates, init.defaultBranch) el fixture es reproducible.
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$ROOT/scripts/check-changelog-fragment.sh"
fails=0
total=0
TMPS=""

cleanup() { [ -n "$TMPS" ] && rm -rf $TMPS; }
trap cleanup EXIT

check() { # nombre, condicion (0 = ok)
    total=$((total + 1))
    if [ "$2" -eq 0 ]; then echo "  ok  $1"; else echo "FAIL  $1"; fails=$((fails + 1)); fi
}

git_t() { git -c user.email=t@t -c user.name=t "$@"; }

# El script resuelve su raiz por ubicacion, asi que se copia al fixture.
# origin/main se simula con una ref local: la comparacion es contra la base, no contra la red.
# $1 = "sin-dir" parte de una base sin changelog.d/.
new_fixture() {
    FX="$(mktemp -d)"
    TMPS="$TMPS $FX"
    mkdir -p "$FX/scripts"
    cp "$SCRIPT" "$FX/scripts/check-changelog-fragment.sh" || { echo "FAIL  fixture: cp"; exit 1; }
    printf '# Changelog\n\n## [Unreleased]\n' > "$FX/CHANGELOG.md"
    if [ "${1:-}" != "sin-dir" ]; then
        mkdir -p "$FX/changelog.d"
        printf 'readme\n' > "$FX/changelog.d/README.md"
        printf -- '- viejo bullet\n' > "$FX/changelog.d/viejo.fixed.md"
    fi
    (cd "$FX" && git init -q -b main . && git add -A \
        && git_t commit -q -m base \
        && git update-ref refs/remotes/origin/main HEAD \
        && git checkout -q -b pr) \
        || { echo "FAIL  fixture: git"; exit 1; }
}
commit() { (cd "$FX" && git add -A && git_t commit -q -m "$1"); }
run() { out=$(cd "$FX" && GITHUB_BASE_REF=main bash scripts/check-changelog-fragment.sh 2>&1); rc=$?; }
frag() { printf -- '%s\n' "- $2" > "$FX/changelog.d/$1"; }

echo "== check-changelog-fragment"

# --- conteo
new_fixture
frag rama.added.md uno; commit f
run
[ "$rc" -eq 0 ] && echo "$out" | grep -q 'ok  un fragmento nuevo'
check "un fragmento nuevo pasa" $?

new_fixture
printf 'x\n' > "$FX/otro.txt"; commit "sin fragmento"
run
[ "$rc" -ne 0 ] && echo "$out" | grep -q 'agrega 0 fragmentos' && echo "$out" | grep -q 'changelog.d/<slug-de-rama>'
check "cero fragmentos falla y dice como nombrarlo" $?

new_fixture
frag a.added.md a; frag b.fixed.md b; commit dos
run
[ "$rc" -ne 0 ] && echo "$out" | grep -q 'agrega 2 fragmentos'
check "dos fragmentos fallan" $?

new_fixture
printf 'cambio\n' >> "$FX/changelog.d/README.md"; commit readme
run
[ "$rc" -ne 0 ] && echo "$out" | grep -q 'agrega 0 fragmentos'
check "tocar solo el README no cuenta como fragmento" $?

new_fixture
mkdir -p "$FX/changelog.d/sub"
printf 'r\n' > "$FX/changelog.d/sub/README.md"
frag a.added.md a; commit uno
run
[ "$rc" -eq 0 ]
check "un README anidado no suma al conteo" $?

new_fixture
(cd "$FX" && git mv changelog.d/viejo.fixed.md changelog.d/nuevo.fixed.md); commit rename
run
[ "$rc" -eq 0 ] && echo "$out" | grep -q 'ok  un fragmento nuevo'
check "un fragmento renombrado cuenta como exactamente uno nuevo" $?

new_fixture
printf -- '- editado\n' > "$FX/changelog.d/viejo.fixed.md"; commit modificado
run
[ "$rc" -ne 0 ] && echo "$out" | grep -q 'agrega 0 fragmentos'
check "modificar un fragmento existente no cuenta como nuevo" $?

new_fixture
frag temp.added.md t; commit agrega
(cd "$FX" && git rm -q changelog.d/temp.added.md); commit borra
run
[ "$rc" -ne 0 ] && echo "$out" | grep -q 'agrega 0 fragmentos'
check "fragmento agregado y borrado dentro de la rama no cuenta" $?

new_fixture "sin-dir"
mkdir -p "$FX/changelog.d"; frag a.added.md a; commit primero
run
[ "$rc" -eq 0 ]
check "changelog.d ausente en la base: el primer fragmento pasa" $?

# --- main avanza y se mezcla en la rama
new_fixture
frag mia.added.md mia; commit mia
(cd "$FX" && git checkout -q main && printf -- '- de main\n' > changelog.d/main.added.md \
    && git add -A && git_t commit -q -m "main avanza" \
    && git update-ref refs/remotes/origin/main HEAD \
    && git checkout -q pr && git_t merge -q main -m merge) || echo "FAIL  fixture: merge"
run
[ "$rc" -eq 0 ] && echo "$out" | grep -q 'ok  un fragmento nuevo'
check "los fragmentos de main mezclados en la rama no se cuentan" $?

# --- nombre del fragmento
for bad in foo.txt a.bogus.md sub/x.added.md a.added.txt; do
    new_fixture
    mkdir -p "$FX/changelog.d/$(dirname "$bad")"
    printf -- '- x\n' > "$FX/changelog.d/$bad"; commit n
    run
    [ "$rc" -ne 0 ] && echo "$out" | grep -q "$bad" && echo "$out" | grep -q 'slug-de-rama'
    check "nombre invalido $bad falla nombrandolo" $?
done
for good in a.added.md a.b.fixed.md; do
    new_fixture
    frag "$good" x; commit n
    run
    [ "$rc" -eq 0 ]
    check "nombre valido $good pasa" $?
done

# --- CHANGELOG.md
new_fixture
frag a.added.md a
printf -- '- a mano\n' >> "$FX/CHANGELOG.md"; commit mano
run
[ "$rc" -ne 0 ] && echo "$out" | grep -q 'edita CHANGELOG.md'
check "editar CHANGELOG.md con un fragmento falla nombrandolo" $?

new_fixture
printf -- '- a mano\n' >> "$FX/CHANGELOG.md"; commit mano
run
[ "$rc" -ne 0 ] && echo "$out" | grep -q 'edita CHANGELOG.md'
check "editar CHANGELOG.md sin fragmentos falla" $?

# --- ensamblado
new_fixture
printf -- '- viejo bullet\n' >> "$FX/CHANGELOG.md"
(cd "$FX" && git rm -q changelog.d/viejo.fixed.md); commit ensamblado
run
[ "$rc" -eq 0 ] && echo "$out" | grep -q 'ensamblado'
check "ensamblado fiel (borra fragmentos, agrega sus lineas) pasa" $?

new_fixture
printf -- '- viejo bullet\n' >> "$FX/CHANGELOG.md"
printf 'mas\n' >> "$FX/changelog.d/README.md"
(cd "$FX" && git rm -q changelog.d/viejo.fixed.md); commit "ensamblado y readme"
run
[ "$rc" -eq 0 ]
check "ensamblado que tambien edita el README pasa" $?

new_fixture
printf '# Changelog\n\n## [Unreleased]\n- reescrito\n' > "$FX/CHANGELOG.md"
(cd "$FX" && git rm -q changelog.d/viejo.fixed.md); commit "reescribe"
run
[ "$rc" -ne 0 ]
check "borrar fragmento y reescribir una linea vieja falla" $?

new_fixture
printf -- '- viejo bullet\n- linea ajena\n' >> "$FX/CHANGELOG.md"
(cd "$FX" && git rm -q changelog.d/viejo.fixed.md); commit "ajena"
run
[ "$rc" -eq 0 ]
check "ensamblado con una linea extra pero fiel pasa (solo se exige que no falte nada)" $?

new_fixture
printf -- '- otra cosa\n' >> "$FX/CHANGELOG.md"
(cd "$FX" && git rm -q changelog.d/viejo.fixed.md); commit "no relacionada"
run
[ "$rc" -ne 0 ] && echo "$out" | grep -q 'viejo.fixed.md'
check "borrar fragmento y agregar solo una linea no relacionada falla nombrandolo" $?

new_fixture
(cd "$FX" && git rm -q changelog.d/viejo.fixed.md); commit borrado
run
[ "$rc" -ne 0 ] && echo "$out" | grep -q 'agrega 0 fragmentos'
check "borrar fragmentos sin ensamblar falla" $?

new_fixture
printf -- '- viejo bullet\n' >> "$FX/CHANGELOG.md"
frag n.added.md nuevo
(cd "$FX" && git rm -q changelog.d/viejo.fixed.md); commit mezcla
run
[ "$rc" -ne 0 ]
check "ensamblado mas fragmento nuevo falla" $?

# --- local
new_fixture
printf 'x\n' > "$FX/otro.txt"; commit local
out=$(cd "$FX" && bash scripts/check-changelog-fragment.sh 2>&1); rc=$?
[ "$rc" -eq 0 ] && echo "$out" | grep -qi 'omitido'
check "sin GITHUB_BASE_REF se omite con aviso" $?

new_fixture
out=$(cd "$FX" && GITHUB_BASE_REF=nope bash scripts/check-changelog-fragment.sh 2>&1); rc=$?
[ "$rc" -ne 0 ] && echo "$out" | grep -q 'origin/nope'
check "base no encontrada falla nombrando la ref" $?

echo
echo "$((total - fails))/$total pasaron"
[ "$fails" -eq 0 ]
