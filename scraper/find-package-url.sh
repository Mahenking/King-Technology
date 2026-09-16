#!/bin/bash
# Find the latest .deb URL for a package from Ubuntu repos
# Usage: ./find-package-url.sh <package-name> [suite]
# Example: ./find-package-url.sh nano
#          ./find-package-url.sh nano noble

PKG="$1"
SUITE="${2:-noble}"

if [ -z "$PKG" ]; then
    echo "Usage: $0 <package-name> [suite]"
    exit 1
fi

# Search across all repos
for repo in main universe multiverse restricted; do
    URL=$(curl -s "http://ports.ubuntu.com/ubuntu-ports/dists/${SUITE}/${repo}/binary-arm64/Packages.gz" 2>/dev/null | \
        gunzip 2>/dev/null | \
        grep -A 20 "^Package: ${PKG}$" | \
        grep -E "^Filename:" | \
        head -1 | \
        cut -d' ' -f2-)
    
    if [ -n "$URL" ]; then
        echo "http://ports.ubuntu.com/ubuntu-ports/${URL}"
        exit 0
    fi
done

echo "NOT_FOUND"
exit 1
