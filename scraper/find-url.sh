#!/bin/bash
# Usage: ./find-url.sh <package-name>
# Example: ./find-url.sh nano

if [ -z "$1" ]; then
    echo "Usage: $0 <package-name>"
    exit 1
fi

PKG="$1"

echo "Searching for: $PKG"
echo ""

# Search in main repo
curl -s "http://ports.ubuntu.com/ubuntu-ports/dists/noble/main/binary-arm64/Packages.gz" | \
    gunzip | \
    grep -A 15 "^Package: ${PKG}$" | \
    grep -E "^Package:|^Version:|^Filename:|^Depends:|^Description:" | \
    head -6

echo ""
echo "Searching in universe repo..."
curl -s "http://ports.ubuntu.com/ubuntu-ports/dists/noble/universe/binary-arm64/Packages.gz" | \
    gunzip | \
    grep -A 15 "^Package: ${PKG}$" | \
    grep -E "^Package:|^Version:|^Filename:|^Depends:|^Description:" | \
    head -6
