#!/bin/bash
# Test-layer gate. Usage: check-test-layers.sh <root> [dump-package.json]
# R1: no @testable import in Tests/<dir> unless <dir> ends in "Tests".
# R2: import direction between test/support targets (see FORBIDDEN below).
# R3: (with a manifest) UI test targets carry no resources and the UI test
#     support target no defaultIsolation.
# Fails closed: a find/grep/parse error is a failure, never a silent pass.
# Bash 3.2, system tools only.
# Known limitation: imports are matched line by line, so the inside of a
# multi-line block comment is read as code (a false positive, never a false
# pass), and `/* x */ import X` on one line is not seen. Upgrade trigger: a
# real parser if either ever shows up in the test tree.
set -u

ROOT="${1:-}"
MANIFEST="${2:-}"
fails=0
note_fail() { echo "FAIL [$1] $2"; fails=$((fails + 1)); }

if [ -z "$ROOT" ] || [ ! -d "$ROOT/Tests" ]; then
    echo "FAIL [error] no Tests directory under '${ROOT}'"
    exit 2
fi

# Identifier-bounded, statement-anchored import: attributes (@testable,
# @_exported, @_spi(X)), an access level (SE-0409) and the `import struct X.Y`
# kinds may precede the module name, and `;` starts a new statement so a
# second import on the same line is still seen. A commented-out import or a
# longer module name never matches.
ATTRS='(@[A-Za-z_]+(\([^)]*\))?[[:space:]]+)*'
ACCESS='((public|internal|package|fileprivate|private)[[:space:]]+)?'
KINDS='((typealias|struct|class|enum|protocol|var|func|let)[[:space:]]+)?'
STMT='(^|;)[[:space:]]*'
import_pattern() { echo "${STMT}${ATTRS}${ACCESS}import[[:space:]]+${KINDS}($1)([^A-Za-z0-9_]|\$)"; }

# Echoes matching lines; returns 0 on match, 1 on none, 2 on grep error.
scan() {
    dir="$1"; pattern="$2"
    grep -rnE --include='*.swift' "$pattern" "$dir"
}

# Runs scan and reports hits under a rule tag; a grep error is its own failure.
report() {
    rule="$1"; message="$2"; dir="$3"; pattern="$4"
    # grep's exit code on a partial read is not portable (BSD can return 0
    # with hits elsewhere), so unreadable entries are detected up front.
    unreadable=$(find "$dir" \( -type d ! -perm -u+rx \) -o \( -type f -name '*.swift' ! -perm -u+r \) -print 2>&1); frc=$?
    if [ $frc -ne 0 ] || [ -n "$unreadable" ]; then
        note_fail "error" "unreadable entries under $dir"
        return
    fi
    hits=$(scan "$dir" "$pattern"); rc=$?
    if [ $rc -eq 0 ]; then
        note_fail "$rule" "$message"
        echo "$hits"
    elif [ $rc -ne 1 ]; then
        note_fail "error" "grep failed (rc=$rc) in $dir"
    fi
}

forbidden_for() {
    case "$1" in
        CompanionTestKit)
            echo "Companion[A-Za-z0-9_]*" ;;
        CompanionCoreTestSupport|CompanionCoreTests)
            echo "CompanionServices|CompanionUI|CompanionServicesTestSupport|CompanionUITestSupport" ;;
        CompanionServicesTestSupport|CompanionServicesTests)
            echo "CompanionUI|CompanionUITestSupport" ;;
        CompanionUITestSupport|CompanionUITests)
            echo "CompanionServices|CompanionServicesTestSupport" ;;
        *) echo "" ;;
    esac
}

testable_pattern="${STMT}${ATTRS}@testable[[:space:]]+${ATTRS}${ACCESS}import[[:space:]]"

for dir in "$ROOT"/Tests/*/; do
    [ -d "$dir" ] || continue
    name=$(basename "$dir")

    case "$name" in
        *Tests) ;;
        *) report R1 "@testable import outside a *Tests target ($name)" "$dir" "$testable_pattern" ;;
    esac

    forbidden=$(forbidden_for "$name")
    if [ -n "$forbidden" ]; then
        report R2 "$name imports a layer it may not" "$dir" "$(import_pattern "$forbidden")"
    fi
done

# ------------------------------------------------------------------------ R3
if [ -n "$MANIFEST" ]; then
    present=""
    for t in CompanionUITests CompanionUITestSupport; do
        [ -d "$ROOT/Tests/$t" ] && present="$present $t"
    done
    if [ ! -f "$MANIFEST" ]; then
        note_fail error "manifest not found: $MANIFEST"
    elif ! command -v python3 >/dev/null 2>&1; then
        note_fail error "python3 is required to read the manifest"
    else
        # shellcheck disable=SC2086
        r3=$(python3 - "$MANIFEST" $present <<'PY'
import json, sys
try:
    targets = {t["name"]: t for t in json.load(open(sys.argv[1]))["targets"]}
except Exception as e:
    print("FAIL [error] manifest unreadable: %s" % e)
    sys.exit(2)
bad = 0
# A folder with no manifest target would skip every check below.
for name in sys.argv[2:]:
    if name not in targets:
        print("FAIL [R3] Tests/%s exists but the manifest has no such target" % name)
        bad = 1
for name in ("CompanionUITests", "CompanionUITestSupport"):
    if targets.get(name, {}).get("resources"):
        print("FAIL [R3] %s declares resources" % name)
        bad = 1
for s in targets.get("CompanionUITestSupport", {}).get("settings", []):
    if "defaultIsolation" in s.get("kind", {}):
        print("FAIL [R3] CompanionUITestSupport sets defaultIsolation")
        bad = 1
sys.exit(bad)
PY
        ); rc=$?
        [ -n "$r3" ] && echo "$r3"
        [ $rc -ne 0 ] && fails=$((fails + 1))
    fi
fi

if [ $fails -gt 0 ]; then
    echo "$fails test-layer violation(s)"
    exit 1
fi
exit 0
