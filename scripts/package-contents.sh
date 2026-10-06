# Sourced, never run. What may ship inside Companion.app: bundle.sh copies
# the extension through this list and package-smoke.sh audits the whole app
# with these functions. A whole-folder copy once shipped a hook's stray
# `Users/.../.git/claude-review.json` (git hides it: the path holds `.git`).
# Every audit fails closed: a listing that errors is a failure, never "clean".

# README.md and test/ stay out: Chrome never loads them.
# A new file under lib/ must be added here; a test compares this list with
# `git ls-files Extensions/browser`.
BROWSER_EXTENSION_FILES="
manifest.json
background.js
lib/cdp.js
lib/cursor.js
lib/dialog-wiring.js
lib/dialogs.js
lib/groups.js
lib/page.js
lib/redact.js
lib/wire.js
"

# $1 source folder (Extensions/browser)  $2 destination folder. A listed file
# that is missing, or reached through a symlink, fails the copy: a link could
# pull anything on this Mac into the app.
browser_extension_copy() {
    local src="$1" dst="$2" file part
    for file in $BROWSER_EXTENSION_FILES; do
        part="$file"
        while [ "$part" != "." ]; do
            if [ -L "$src/$part" ]; then
                echo "la extension no se copia: $src/$part es un symlink" >&2
                return 1
            fi
            part="$(dirname "$part")"
        done
        mkdir -p "$dst/$(dirname "$file")"
        cp "$src/$file" "$dst/$file"
    done
}

# The `.copy` resources of Package.swift, as <folder in Contents/Resources>:<source>.
# A test keeps this in step with Package.swift.
RESOURCE_FOLDERS="
Companion_CompanionServices.bundle/Skills:Sources/CompanionServices/Skills
Companion_CompanionServices.bundle/Diagram:Sources/CompanionServices/Diagram
Companion_CompanionUI.bundle/Fonts:Sources/CompanionUI/Fonts
Companion_CompanionUI.bundle/Mascot:Sources/CompanionUI/Mascot
"

# $1 folder  $2 allowed files, one per line, relative to $1. Prints every entry
# outside the list (folders end in /), every symlink even at a listed path,
# and `falta: <file>` for each listed file that is not a regular file.
# Returns non-zero when the folder cannot be listed.
package_strays() {
    local dir="$1" wanted="$2" listing allowed file parent entry rel
    listing="$(find "$dir" -mindepth 1)" || return 1
    allowed="$(printf '%s\n' "$wanted" | while IFS= read -r file; do
        [ -n "$file" ] || continue
        echo "$file"
        parent="$(dirname "$file")"
        while [ "$parent" != "." ]; do echo "$parent/"; parent="$(dirname "$parent")"; done
    done)"
    while IFS= read -r entry; do
        [ -n "$entry" ] || continue
        rel="${entry#"$dir"/}"
        if [ -L "$entry" ]; then printf '%s\n' "$rel"; continue; fi
        if [ -d "$entry" ]; then rel="$rel/"; fi
        grep -qxF -- "$rel" <<< "$allowed" || printf '%s\n' "$rel"
    done <<< "$listing"
    while IFS= read -r file; do
        [ -n "$file" ] || continue
        if [ -L "$dir/$file" ] || [ ! -f "$dir/$file" ]; then printf 'falta: %s\n' "$file"; fi
    done <<< "$wanted"
}

# $1 BrowserExtension folder inside the app.
browser_extension_strays() {
    package_strays "$1" "$(printf '%s\n' $BROWSER_EXTENSION_FILES)"
}

# Files that exist only on the owner's Mac: git ignores them (proprietary
# faces, All Rights Reserved, cannot ship in the MIT repo) and SwiftPM copies
# the whole folder, so they land in the app there and are absent on a clone.
# An allowlist rather than "ignored is fine": an ignored stray must still fail.
# A test compares this list with the font block of .gitignore.
LOCAL_ONLY_RESOURCES="
Sources/CompanionUI/Fonts/Gadey-Regular.otf
Sources/CompanionUI/Fonts/Hypodermic.otf
Sources/CompanionUI/Fonts/TBJInterval-Bold.otf
Sources/CompanionUI/Fonts/TBJInterval-Light.otf
Sources/CompanionUI/Fonts/TBJInterval-Regular.otf
"

# $1 folder shipped in the app  $2 repo root  $3 its source folder, relative
# to $2 (a `.copy` resource of Package.swift). SwiftPM copies the folder whole,
# so an untracked or ignored file there ships; the tracked files are the list,
# plus the LOCAL_ONLY_RESOURCES of this folder that are present (absent is the
# clone case, not a missing file).
resource_folder_strays() {
    local tracked file allowed
    tracked="$(git -C "$2" ls-files -z -- "$3" | tr '\0' '\n')" || return 1
    [ -n "$tracked" ] || { echo "git no ve archivos en $3" >&2; return 1; }
    allowed="$(printf '%s\n' "$tracked" | sed "s|^$3/||")"
    for file in $LOCAL_ONLY_RESOURCES; do
        case "$file" in "$3"/*) ;; *) continue ;; esac
        if [ -e "$1/${file#"$3"/}" ] || [ -L "$1/${file#"$3"/}" ]; then
            allowed="$allowed"$'\n'"${file#"$3"/}"
        fi
    done
    package_strays "$1" "$allowed"
}

# $1 .app. Prints every entry that must never ship: a path component named
# .git*, .DS_Store, claude-review* or .env*; a symlink that resolves outside
# the app (or nowhere); a text file carrying a /Users/ path. Binary files are
# skipped for /Users/: the Mach-O paths are S5's finding, not this scan's.
app_forbidden_entries() {
    local app listing entry rel target texts
    app="$(cd "$1" && pwd -P)" || return 1
    listing="$(find "$app" -mindepth 1)" || return 1
    while IFS= read -r entry; do
        [ -n "$entry" ] || continue
        rel="${entry#"$app"/}"
        case "${entry##*/}" in
            .git* | .DS_Store | claude-review* | .env*) printf '%s\n' "$rel"; continue ;;
        esac
        if [ -L "$entry" ]; then
            if ! target="$(realpath "$entry" 2>/dev/null)"; then
                printf '%s -> (no resuelve)\n' "$rel"
            else
                case "$target/" in "$app/"*) ;; *) printf '%s -> %s\n' "$rel" "$target" ;; esac
            fi
        fi
    done <<< "$listing"
    # grep: 0 = matches, 1 = none, anything else is an error and fails the scan.
    texts="$(grep -rlI --no-messages -- "/Users/" "$app")" || [ $? -eq 1 ] || return 1
    while IFS= read -r entry; do
        if [ -n "$entry" ]; then printf '%s\n' "${entry#"$app"/}"; fi
    done <<< "$texts"
}
