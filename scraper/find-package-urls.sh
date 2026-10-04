#!/bin/bash
# ============================================================
# 👑 King OS — Multi-Source Package URL Finder (v3)
# ============================================================
# Usage: find-package-urls.sh <name>[@<version>] [--verbose]
#
# If @version given, returns only matching version URLs.
# If not, returns all versions found.
#
# Exit codes:
#   0 = at least one URL found
#   1 = no matches
#   2 = config error
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SOURCES_FILE="$REPO_ROOT/config/sources.conf"
CACHE_HELPER="$SCRIPT_DIR/index-cache.sh"

RAW=""
VERBOSE=0

for arg in "$@"; do
    case "$arg" in
        --verbose) VERBOSE=1 ;;
        *) [ -z "$RAW" ] && RAW="$arg" ;;
    esac
done

if [ -z "$RAW" ]; then
    echo "Usage: $0 <name>[@<version>] [--verbose]" >&2
    exit 2
fi

PKG_NAME="$RAW"
WANT_VERSION=""
if [[ "$RAW" == *@* ]]; then
    PKG_NAME="${RAW%@*}"
    WANT_VERSION="${RAW#*@}"
fi

if [ -z "$PKG_NAME" ]; then
    echo "ERROR: empty package name" >&2
    exit 2
fi

[ -f "$SOURCES_FILE" ] || { echo "ERROR: sources.conf missing" >&2; exit 2; }
[ -x "$CACHE_HELPER" ] || { echo "ERROR: index-cache.sh not executable" >&2; exit 2; }

log() { [ "$VERBOSE" -eq 1 ] && echo "$@" >&2; }

FOUND=0
SEEN_URLS=$'\n'

while IFS='|' read -r name repo_url suite arch components; do
    name=$(echo "$name" | xargs)
    repo_url=$(echo "$repo_url" | xargs)
    suite=$(echo "$suite" | xargs)
    arch=$(echo "$arch" | xargs)
    components=$(echo "$components" | xargs)

    [[ -z "$name" || "$name" =~ ^# ]] && continue
    [[ -z "$repo_url" || -z "$suite" || -z "$arch" || -z "$components" ]] && continue

    IFS=',' read -ra COMP_ARR <<< "$components"

    for comp in "${COMP_ARR[@]}"; do
        comp=$(echo "$comp" | xargs)
        [ -z "$comp" ] && continue

        log "🔍 Searching $name ($suite/$comp)..."

        INDEX=$("$CACHE_HELPER" "$repo_url" "$suite" "$comp" "$arch" 2>/dev/null)

        if [ "$INDEX" = "FETCH_FAILED" ] || [ ! -f "$INDEX" ]; then
            log "   ⚠️  Index fetch failed"
            continue
        fi

        # awk walks blocks: Package line + Version + Filename
        # Captures Filename only for matching name (and version if given)
        MATCHES=$(awk -v pkg="$PKG_NAME" -v want="$WANT_VERSION" '
            BEGIN { match_pkg = 0; match_ver = 0 }
            /^Package: / {
                match_pkg = ($2 == pkg) ? 1 : 0
                match_ver = (want == "") ? 1 : 0
                next
            }
            match_pkg && /^Version: / {
                if (want == "" || $2 == want) match_ver = 1
                next
            }
            match_pkg && match_ver && /^Filename: / {
                print $2
                next
            }
            /^$/ {
                match_pkg = 0
                match_ver = 0
            }
        ' "$INDEX")

        if [ -z "$MATCHES" ]; then
            continue
        fi

        while IFS= read -r relpath; do
            [ -z "$relpath" ] && continue
            FULL_URL="${repo_url}/${relpath}"

            if echo "$SEEN_URLS" | grep -qxF "$FULL_URL"; then
                continue
            fi
            SEEN_URLS+="${FULL_URL}"$'\n'
            echo "$FULL_URL"
            FOUND=$((FOUND + 1))
        done <<< "$MATCHES"
    done
done < "$SOURCES_FILE"

[ "$FOUND" -eq 0 ] && exit 1
exit 0
