#!/bin/bash
# Tests de scripts/changelog-assemble.sh sobre un repo git temporal.
# Bash 3.2, sin dependencias. Exit != 0 si algun caso falla.
set -u
# Bajo un hook de git estas variables apuntarian el fixture al repo real.
unset GIT_DIR GIT_INDEX_FILE GIT_WORK_TREE

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$ROOT/scripts/changelog-assemble.sh"
fails=0
total=0
TMPS=""

cleanup() { [ -n "$TMPS" ] && rm -rf $TMPS; }
trap cleanup EXIT

check() { # nombre, condicion (0 = ok)
    total=$((total + 1))
    if [ "$2" -eq 0 ]; then echo "  ok  $1"; else echo "FAIL  $1"; fails=$((fails + 1)); fi
}

# Fixture: repo git con el script copiado, porque el script resuelve su raiz por ubicacion.
new_fixture() {
    FX="$(mktemp -d)"
    TMPS="$TMPS $FX"
    mkdir -p "$FX/scripts" "$FX/changelog.d"
    cp "$SCRIPT" "$FX/scripts/changelog-assemble.sh" || { echo "FAIL  fixture: cp"; exit 1; }
    printf '# Changelog\n\n## [Unreleased]\n\n### Fixed\n- viejo fixed\n\n### Added\n- viejo added\n\n## [0.1.0]\n\n### Added\n- historico\n' > "$FX/CHANGELOG.md"
    printf 'readme\n' > "$FX/changelog.d/README.md"
    (cd "$FX" && git init -q . && git add -A \
        && git -c user.email=t@t -c user.name=t commit -q -m init) \
        || { echo "FAIL  fixture: git"; exit 1; }
}
ln_of() { grep -n -- "$1" "$FX/CHANGELOG.md" | head -1 | cut -d: -f1; }
# Se commitea para que "git rm" deje un borrado visible en el indice, como en un PR real.
frag() {
    printf '%s\n' "$2" > "$FX/changelog.d/$1"
    (cd "$FX" && git add "changelog.d/$1" \
        && git -c user.email=t@t -c user.name=t commit -q -m "frag $1")
}
run() { (cd "$FX" && bash scripts/changelog-assemble.sh "$@" 2>&1); }

echo "== changelog-assemble"

# 1. inserta al tope de una seccion existente
new_fixture
frag "rama-a.fixed.md" "- **Nuevo fix (2026-10-01).** Texto."
out=$(run); rc=$?
awk '/^### Fixed/{getline; print; exit}' "$FX/CHANGELOG.md" | grep -q "Nuevo fix"
check "inserta al tope de ### Fixed existente" $?
[ ! -e "$FX/changelog.d/rama-a.fixed.md" ] && [ -e "$FX/changelog.d/README.md" ]
check "borra el fragmento y respeta el README" $?
(cd "$FX" && git status --porcelain changelog.d | grep -q '^D ')
check "usa git rm (borrado en el indice)" $?
grep -q "historico" "$FX/CHANGELOG.md" && [ "$(grep -c '^## \[0.1.0\]' "$FX/CHANGELOG.md")" -eq 1 ]
check "no toca lo que esta bajo versiones anteriores" $?

# 2. crea encabezado faltante en el orden Keep a Changelog (Changed entre Added y Fixed)
new_fixture
frag "rama-b.changed.md" "- cambio b"
run >/dev/null
added=$(grep -n '^### Added' "$FX/CHANGELOG.md" | head -1 | cut -d: -f1)
changed=$(grep -n '^### Changed' "$FX/CHANGELOG.md" | head -1 | cut -d: -f1)
fixed=$(grep -n '^### Fixed' "$FX/CHANGELOG.md" | head -1 | cut -d: -f1)
# Orden esperado: Added < Changed < Fixed; el fixture trae Fixed antes de Added,
# asi que Changed debe quedar antes de Fixed (primer encabezado con rango mayor).
[ -n "$changed" ] && [ "$changed" -lt "$fixed" ]
check "crea ### Changed antes del primer encabezado posterior (Fixed)" $?

# 3. Security se crea al final de Unreleased, antes de la version previa
new_fixture
frag "rama-c.security.md" "- sec c"
run >/dev/null
sec=$(grep -n '^### Security' "$FX/CHANGELOG.md" | cut -d: -f1)
ver=$(grep -n '^## \[0.1.0\]' "$FX/CHANGELOG.md" | cut -d: -f1)
[ -n "$sec" ] && [ "$sec" -lt "$ver" ] && sed -n "$((sec + 1))p" "$FX/CHANGELOG.md" | grep -q "sec c"
check "crea ### Security al final de Unreleased" $?
sed -n "$((ver - 1))p" "$FX/CHANGELOG.md" | grep -q '^$'
check "deja linea en blanco antes de la version previa" $?

# 4. varios fragmentos de la misma categoria, orden estable por nombre
new_fixture
frag "b.added.md" "- bravo"
frag "a.added.md" "- alfa"
run >/dev/null
a=$(grep -n -- '- alfa' "$FX/CHANGELOG.md" | cut -d: -f1)
b=$(grep -n -- '- bravo' "$FX/CHANGELOG.md" | cut -d: -f1)
[ -n "$a" ] && [ -n "$b" ] && [ "$a" -lt "$b" ]
check "agrupa y ordena por nombre dentro de la categoria" $?

# 5. bullet multilinea intacto
new_fixture
printf -- '- **Titulo (2026-10-01).** Linea uno\n  linea dos con acentos: ñ y emoji-free.\n' > "$FX/changelog.d/m.fixed.md"
(cd "$FX" && git add changelog.d/m.fixed.md)
run >/dev/null
grep -q '^  linea dos con acentos: ñ' "$FX/CHANGELOG.md"
check "conserva bullets multilinea y UTF-8" $?

# 6. --dry-run imprime sin escribir
new_fixture
frag "d.fixed.md" "- dry"
before=$(cat "$FX/CHANGELOG.md")
out=$(run --dry-run)
echo "$out" | grep -q -- '- dry'
check "--dry-run imprime el resultado" $?
[ "$before" = "$(cat "$FX/CHANGELOG.md")" ] && [ -e "$FX/changelog.d/d.fixed.md" ]
check "--dry-run no escribe ni borra fragmentos" $?

# 7. idempotente: sin fragmentos es no-op
new_fixture
before=$(cat "$FX/CHANGELOG.md")
out=$(run); rc=$?
[ "$rc" -eq 0 ] && [ "$before" = "$(cat "$FX/CHANGELOG.md")" ]
check "sin fragmentos: exit 0 y CHANGELOG intacto" $?
frag "i.added.md" "- una vez"
run >/dev/null; run >/dev/null
[ "$(grep -c -- '- una vez' "$FX/CHANGELOG.md")" -eq 1 ]
check "correr dos veces no duplica" $?

# 8. categoria desconocida: error claro y nada se escribe
new_fixture
frag "ok.added.md" "- bueno"
frag "x.bogus.md" "- malo"
before=$(cat "$FX/CHANGELOG.md")
out=$(run); rc=$?
[ "$rc" -ne 0 ] && echo "$out" | grep -q "bogus" && echo "$out" | grep -q "added|changed|fixed|security"
check "categoria desconocida falla nombrando el archivo y las validas" $?
[ "$before" = "$(cat "$FX/CHANGELOG.md")" ] && [ -e "$FX/changelog.d/ok.added.md" ]
check "ante error no escribe ni borra nada" $?

# 9. nombre sin categoria y fragmento vacio
new_fixture
frag "sincategoria.md" "- x"
out=$(run); rc=$?
[ "$rc" -ne 0 ] && echo "$out" | grep -q "sincategoria.md"
check "nombre sin categoria falla" $?
new_fixture
printf '\n\n' > "$FX/changelog.d/vacio.fixed.md"
out=$(run); rc=$?
[ "$rc" -ne 0 ] && echo "$out" | grep -qi "vacio"
check "fragmento vacio falla" $?

# 10. argumento desconocido
new_fixture
out=$(run --nope); rc=$?
[ "$rc" -ne 0 ]
check "argumento desconocido falla" $?

# 11. CHANGELOG sin [Unreleased]
new_fixture
printf '# Changelog\n' > "$FX/CHANGELOG.md"
frag "u.fixed.md" "- u"
out=$(run); rc=$?
[ "$rc" -ne 0 ] && echo "$out" | grep -q "Unreleased"
check "sin ## [Unreleased] falla con mensaje claro" $?

# 12. Unreleased es la ultima seccion y no tiene encabezados (BUG: inun sin reiniciar)
new_fixture
printf '# Changelog\n\n## [Unreleased]\n' > "$FX/CHANGELOG.md"
(cd "$FX" && git add -A && git -c user.email=t@t -c user.name=t commit -q -m last)
frag "p.added.md" "- uno"
frag "q.added.md" "- dos"
frag "r.security.md" "- sec"
run >/dev/null
u=$(ln_of '^## \[Unreleased\]'); a=$(ln_of '^### Added'); s=$(ln_of '^### Security')
[ -n "$a" ] && [ "$a" -gt "$u" ] && [ "$s" -gt "$a" ]
check "Unreleased ultimo y vacio: encabezados quedan debajo y en orden" $?
[ "$(sed -n "$((a + 1)),$((a + 2))p" "$FX/CHANGELOG.md")" = "$(printf -- '- uno\n- dos')" ]
check "Unreleased ultimo: bullets pegados al encabezado" $?

# 13. los bullets existentes siguen, en orden, justo despues del nuevo
new_fixture
frag "e.fixed.md" "- nuevo"
run >/dev/null
f=$(ln_of '^### Fixed')
[ "$(sed -n "$((f + 1)),$((f + 2))p" "$FX/CHANGELOG.md")" = "$(printf -- '- nuevo\n- viejo fixed')" ]
check "el bullet viejo queda inmediatamente despues del nuevo" $?

# 14. fragmentos sin newline final terminan en lineas separadas
new_fixture
printf -- '- sin nl uno' > "$FX/changelog.d/a.added.md"
printf -- '- sin nl dos' > "$FX/changelog.d/b.added.md"
run >/dev/null
a=$(ln_of '^### Added')
[ "$(sed -n "$((a + 1)),$((a + 3))p" "$FX/CHANGELOG.md")" = "$(printf -- '- sin nl uno\n- sin nl dos\n- viejo added')" ]
check "sin newline final: lineas separadas" $?

# 15. lineas en blanco finales no dejan hueco
new_fixture
printf -- '- con blancos\n\n\n' > "$FX/changelog.d/a.fixed.md"
run >/dev/null
f=$(ln_of '^### Fixed')
[ "$(sed -n "$((f + 1)),$((f + 2))p" "$FX/CHANGELOG.md")" = "$(printf -- '- con blancos\n- viejo fixed')" ]
check "blancos finales del fragmento no abren hueco" $?

# 16. las cuatro categorias en una corrida: Added, Changed, Fixed, Security
new_fixture
# El fixture base trae Fixed antes de Added; aqui se parte de una seccion vacia.
printf '# Changelog\n\n## [Unreleased]\n\n## [0.1.0]\n\n### Added\n- historico\n' > "$FX/CHANGELOG.md"
(cd "$FX" && git add -A && git -c user.email=t@t -c user.name=t commit -q -m clean)
frag "a.security.md" "- s"
frag "b.fixed.md" "- f"
frag "c.changed.md" "- c"
frag "d.added.md" "- a"
run >/dev/null
heads=$(awk '/^## \[0.1.0\]/{exit} /^### /{printf "%s ", $2}' "$FX/CHANGELOG.md")
[ "$heads" = "Added Changed Fixed Security " ]
check "orden final Added, Changed, Fixed, Security sin duplicados" $?

# 17. fragmento de cero bytes
new_fixture
: > "$FX/changelog.d/z.fixed.md"
out=$(run); rc=$?
[ "$rc" -ne 0 ] && echo "$out" | grep -q "z.fixed.md"
check "fragmento de cero bytes se rechaza" $?

# 18. encabezado seguido de blanco y bullet viejo: la lista sigue contigua
new_fixture
printf '# Changelog\n\n## [Unreleased]\n\n### Fixed\n\n- viejo\n\n## [0.1.0]\n' > "$FX/CHANGELOG.md"
(cd "$FX" && git add -A && git -c user.email=t@t -c user.name=t commit -q -m blank)
frag "n.fixed.md" "- nuevo"
run >/dev/null
f=$(ln_of '^### Fixed')
[ "$(sed -n "$((f + 1)),$((f + 3))p" "$FX/CHANGELOG.md")" = "$(printf '\n- nuevo\n- viejo')" ]
check "blanco tras el encabezado: nuevo y viejo contiguos" $?

# 19. nombres: x.md rechazado, slug con punto aceptado, espacios rechazados
new_fixture
frag "x.md" "- x"
out=$(run); rc=$?
[ "$rc" -ne 0 ] && echo "$out" | grep -q "x.md"
check "x.md (sin categoria) se rechaza" $?
new_fixture
frag "a.b.fixed.md" "- con punto"
run >/dev/null
[ -n "$(ln_of 'con punto')" ]
check "slug con punto: categoria fixed" $?
new_fixture
frag "con espacio.fixed.md" "- e"
out=$(run); rc=$?
[ "$rc" -ne 0 ] && echo "$out" | grep -q "con espacio.fixed.md"
check "nombre con espacios da error claro" $?

echo
echo "$((total - fails))/$total pasaron"
[ "$fails" -eq 0 ]
