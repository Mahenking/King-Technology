#!/bin/bash
# King OS — Package Index Cache Helper
# Usage: index-cache.sh <repo_url> <suite> <component> <arch>

REPO_URL="$1"; SUITE="$2"; COMPONENT="$3"; ARCH="$4"

if [ -z "$REPO_URL" ] || [ -z "$SUITE" ] || [ -z "$COMPONENT" ] || [ -z "$ARCH" ]; then
    echo "Usage: $0 <repo_url> <suite> <component> <arch>" >&2
    exit 1
fi

CACHE_DIR="${KINGOS_INDEX_CACHE:-/tmp/kingos-index-cache}"
mkdir -p "$CACHE_DIR"

KEY=$(echo "${REPO_URL}|${SUITE}|${COMPONENT}|${ARCH}" | md5sum | cut -d' ' -f1)
CACHE_FILE="$CACHE_DIR/${KEY}.Packages"

if [ -f "$CACHE_FILE" ]; then
    AGE=$(( $(date +%s) - $(stat -c %Y "$CACHE_FILE") ))
    if [ "$AGE" -lt 86400 ]; then
        echo "$CACHE_FILE"
        exit 0
    fi
fi

URL="${REPO_URL}/dists/${SUITE}/${COMPONENT}/binary-${ARCH}/Packages.gz"
TMP_GZ="$CACHE_DIR/${KEY}.Packages.gz"

if curl -s -f -o "$TMP_GZ" "$URL"; then
    gunzip -c "$TMP_GZ" > "$CACHE_FILE" && { echo "$CACHE_FILE"; exit 0; }
fi

URL_XZ="${REPO_URL}/dists/${SUITE}/${COMPONENT}/binary-${ARCH}/Packages.xz"
if curl -s -f -o "${CACHE_DIR}/${KEY}.Packages.xz" "$URL_XZ"; then
    xz -dc "${CACHE_DIR}/${KEY}.Packages.xz" > "$CACHE_FILE" && { echo "$CACHE_FILE"; exit 0; }
fi

echo "FETCH_FAILED" >&2
exit 2
