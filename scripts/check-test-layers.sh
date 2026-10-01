#!/bin/bash
# Test-layer gate. Usage: check-test-layers.sh <root> [dump-package.json]
# R1: no @testable import in Tests/<dir> unless <dir> ends in "Tests".
# R2: import direction between test/support targets (see FORBIDDEN below).
# R3: (with a manifest) UI test targets carry no resources; the four support
#     targets are regular, settings-free and depend only on what the layer
#     table allows; the four layer test targets depend only on their own
#     set; no non-test target depends on a support or test target; no
#     product lists a support or test target, or a target the manifest lacks
#     (a missing/malformed `products` fails; an empty list passes); every
#     Tests/ folder with Swift files has a manifest target, and no Swift file
#     sits directly under Tests/; no CompanionTests target (the transitional
#     one is retired); every layer-table target is in the manifest. A target
#     named *TestSupport, CompanionTestKit, or any non-test target whose
#     normalised path is under Tests/ (any case), counts as support and must
#     have a layer-table entry.
# R4: no @_exported import anywhere under Tests/.
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
exported_pattern="${STMT}${ATTRS}@_exported[[:space:]]+${ATTRS}${ACCESS}import[[:space:]]"

for dir in "$ROOT"/Tests/*/; do
    [ -d "$dir" ] || continue
    name=$(basename "$dir")

    case "$name" in
        *Tests) ;;
        *) report R1 "@testable import outside a *Tests target ($name)" "$dir" "$testable_pattern" ;;
    esac

    report R4 "@_exported import in $name; imports must be explicit" "$dir" "$exported_pattern"

    forbidden=$(forbidden_for "$name")
    if [ -n "$forbidden" ]; then
        report R2 "$name imports a layer it may not" "$dir" "$(import_pattern "$forbidden")"
    fi
done

# ------------------------------------------------------------------------ R3
if [ -n "$MANIFEST" ]; then
    # Every folder that holds Swift files must have a manifest target, or the
    # checks below would silently skip it (Tests/Fixtures holds none).
    present=""
    for d in "$ROOT"/Tests/*/; do
        [ -d "$d" ] || continue
        if [ -n "$(find "$d" -name '*.swift' -print -quit 2>/dev/null)" ]; then
            present="$present $(basename "$d")"
        fi
    done
    # A file directly under Tests/ belongs to no target folder: SwiftPM
    # ignores it and its tests never run.
    for f in "$ROOT"/Tests/*.swift; do
        [ -f "$f" ] && note_fail R3 "Tests/$(basename "$f") is outside every target folder; its tests never run"
    done
    if [ ! -f "$MANIFEST" ]; then
        note_fail error "manifest not found: $MANIFEST"
    elif ! command -v python3 >/dev/null 2>&1; then
        note_fail error "python3 is required to read the manifest"
    else
        # shellcheck disable=SC2086
        r3=$(python3 - "$MANIFEST" $present <<'PY'
import json, posixpath, sys
try:
    manifest = json.load(open(sys.argv[1]))
    targets = {t["name"]: t for t in manifest["targets"]}
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

def deps(t):
    names = set()
    for d in t.get("dependencies", []):
        for key in ("byName", "target"):
            if key in d:
                names.add(d[key][0])
    return names

# Allowed Companion* dependencies per support target (the layer table).
ALLOWED = {
    "CompanionTestKit": set(),
    "CompanionCoreTestSupport": {"CompanionCore", "CompanionTestKit"},
    "CompanionServicesTestSupport": {"CompanionServices", "CompanionCoreTestSupport", "CompanionTestKit"},
    "CompanionUITestSupport": {"CompanionUI", "CompanionCoreTestSupport", "CompanionTestKit"},
}
for name, allowed in ALLOWED.items():
    t = targets.get(name)
    if t is None:
        continue
    if t.get("type") != "regular":
        print("FAIL [R3] %s is of type %s, not regular" % (name, t.get("type")))
        bad = 1
    if t.get("settings"):
        print("FAIL [R3] %s declares settings" % name)
        bad = 1
    for dep in sorted(d for d in deps(t) if d.startswith("Companion") and d not in allowed):
        print("FAIL [R3] %s depends on %s" % (name, dep))
        bad = 1

# WHY by name and by path: a hardcoded list would let a new support target
# skip every check here, and a name pattern alone misses one called anything
# else (CompanionFakes). dump-package gives everything under Tests/ its path,
# so a non-test target there is test code whatever its name. The path is kept
# as written and APFS ignores case, so "./Tests/x" or "tests/x" must count
# too. A support target without a table entry has no layer to enforce, so it
# fails until the table says what it may depend on.
def is_support(name):
    if name in ALLOWED or name == "CompanionTestKit" or name.endswith("TestSupport"):
        return True
    t = targets.get(name)
    if t is None or t.get("type") == "test" or not isinstance(t.get("path"), str):
        return False
    path = posixpath.normpath(t["path"]).lower()
    return path == "tests" or path.startswith("tests/")

SUPPORT = {n for n in targets if is_support(n)} | set(ALLOWED)
for name in sorted(SUPPORT - set(ALLOWED)):
    print("FAIL [R3] support target %s has no layer-table entry" % name)
    bad = 1
if "CompanionTests" in targets:
    print("FAIL [R3] CompanionTests target is retired; tests live in their layer's target")
    bad = 1

# Test targets: exactly their Package.swift sets.
CORE_TS = {"CompanionCore", "CompanionCoreTestSupport", "CompanionTestKit"}
TEST_ALLOWED = {
    "CompanionCoreTests": CORE_TS,
    "CompanionServicesTests": CORE_TS | {"CompanionServices", "CompanionServicesTestSupport"},
    "CompanionUITests": CORE_TS | {"CompanionUI", "CompanionUITestSupport"},
    "CompanionIntegrationTests": CORE_TS | {
        "CompanionServices", "CompanionUI", "CompanionServicesTestSupport", "CompanionUITestSupport"},
}
# A layer target dropped from the manifest, with no folder left behind either,
# would skip its checks above in silence.
for name in sorted(set(ALLOWED) | set(TEST_ALLOWED)):
    if name not in targets:
        print("FAIL [R3] layer target %s is missing from the manifest" % name)
        bad = 1
for name, allowed in TEST_ALLOWED.items():
    t = targets.get(name)
    if t is None:
        continue
    for dep in sorted(d for d in deps(t) if d.startswith("Companion") and d not in allowed):
        print("FAIL [R3] %s depends on %s" % (name, dep))
        bad = 1

# Every non-test, non-support target, whatever its name.
for name, t in sorted(targets.items()):
    if t.get("type") == "test" or name in SUPPORT:
        continue
    for dep in sorted(d for d in deps(t)
                      if d in SUPPORT or is_support(d) or targets.get(d, {}).get("type") == "test"):
        print("FAIL [R3] production target %s depends on %s" % (name, dep))
        bad = 1

# Products: test code must not ship. A missing or malformed `products` is a
# failure, never a skip.
products = manifest.get("products")
if not isinstance(products, list):
    print("FAIL [R3] manifest products missing or not a list")
    bad = 1
else:
    for p in products:
        listed = p.get("targets") if isinstance(p, dict) else None
        if (not isinstance(p, dict) or not isinstance(p.get("name"), str)
                or not isinstance(listed, list) or not all(isinstance(x, str) for x in listed)):
            print("FAIL [R3] malformed product entry: %r" % (p,))
            bad = 1
            continue
        for tname in sorted(listed):
            if tname not in targets:
                print("FAIL [R3] product %s lists %s, which the manifest does not define" % (p["name"], tname))
                bad = 1
            elif tname in SUPPORT or targets[tname].get("type") == "test":
                print("FAIL [R3] product %s lists %s, a support or test target" % (p["name"], tname))
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
