#!/bin/bash
# King OS — Multi-Source Package URL Finder
# Usage: find-package-url.sh <package-name> [--verbose]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SOURCES_FILE="$REPO_ROOT/config/sources.conf"
CACHE_HELPER="$SCRIPT_DIR/index-cache.sh"

PKG=""
VERBOSE=0

for arg in "$@"; do
    case "$arg" in
        --verbose) VERBOSE=1 ;;
        *) [ -z "$PKG" ] && PKG="$arg" ;;
    esac
done

if [ -z "$PKG" ]; then
    echo "Usage: $0 <package-name> [--verbose]" >&2
    exit 1
fi

if [ ! -f "$SOURCES_FILE" ]; then
    echo "ERROR: sources.conf not found at $SOURCES_FILE" >&2
    exit 1
fi

log() { [ "$VERBOSE" -eq 1 ] && echo "$@" >&2; }

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

        log "🔍 Searching $name ($comp)..."

        INDEX=$("$CACHE_HELPER" "$repo_url" "$suite" "$comp" "$arch" 2>/dev/null)

        if [ "$INDEX" = "FETCH_FAILED" ] || [ ! -f "$INDEX" ]; then
            log "   ⚠️  Index fetch failed"
            continue
        fi

        FILENAME=$(grep -A 20 "^Package: ${PKG}$" "$INDEX" 2>/dev/null | \
                   grep -E "^Filename:" | head -1 | cut -d' ' -f2-)

        if [ -n "$FILENAME" ]; then
            echo "${repo_url}/${FILENAME}"
            exit 0
        fi
    done
done < "$SOURCES_FILE"

echo "NOT_FOUND"
exit 1
