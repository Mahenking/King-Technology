#!/bin/bash
# ============================================================
# 👑 King OS — Multi-Source Package URL Finder (v2)
# ============================================================
# Usage: find-package-urls.sh <package-name> [--verbose] [--all]
#
# Reads config/sources.conf, searches every enabled source,
# emits ALL matching URLs (one per line), deduplicated.
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

PKG=""
VERBOSE=0

for arg in "$@"; do
    case "$arg" in
        --verbose) VERBOSE=1 ;;
        --all)     VERBOSE=1 ;;  # for now same as verbose
        *) [ -z "$PKG" ] && PKG="$arg" ;;
    esac
done

if [ -z "$PKG" ]; then
    echo "Usage: $0 <package-name> [--verbose]" >&2
    exit 2
fi

if [ ! -f "$SOURCES_FILE" ]; then
    echo "ERROR: sources.conf not found at $SOURCES_FILE" >&2
    exit 2
fi

if [ ! -x "$CACHE_HELPER" ]; then
    echo "ERROR: index-cache.sh not executable at $CACHE_HELPER" >&2
    exit 2
fi

log() { [ "$VERBOSE" -eq 1 ] && echo "$@" >&2; }

FOUND=0
SEEN_URLS=""

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

        # Grab every Filename: line for this package
        # Use awk for reliable block parsing (Package: ... next blank line)
        MATCHES=$(awk -v pkg="$PKG" '
            /^Package: / {
                match_pkg = ($2 == pkg)
                next
            }
            match_pkg && /^Filename: / {
                print $2
                next
            }
            /^$/ {
                match_pkg = 0
            }
        ' "$INDEX")

        if [ -z "$MATCHES" ]; then
            continue
        fi

        while IFS= read -r relpath; do
            [ -z "$relpath" ] && continue
            FULL_URL="${repo_url}/${relpath}"

            # Dedup
            if echo "$SEEN_URLS" | grep -qxF "$FULL_URL"; then
                continue
            fi
            SEEN_URLS="${SEEN_URLS}${FULL_URL}
"
            echo "$FULL_URL"
            FOUND=$((FOUND + 1))
        done <<< "$MATCHES"

        log "   Found $FOUND URL(s) so far"
    done
done < "$SOURCES_FILE"

if [ "$FOUND" -eq 0 ]; then
    exit 1
fi

exit 0
