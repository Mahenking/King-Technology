#!/bin/bash
# ============================================================
# 👑 King OS Repository Builder (Fully Automated)
# ============================================================
# Usage:
#   1. Add package names to packages.txt
#   2. Run: ./king-repo-build.sh
# ============================================================

set -e

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGES_LIST="$REPO_ROOT/packages.txt"
INDEX_FILE="$REPO_ROOT/index.json"
PACKAGES_DIR="$REPO_ROOT/packages"
TEMP_DIR="/tmp/king-repo-temp"
METADATA_DIR="$TEMP_DIR/metadata"
FIND_URL="$REPO_ROOT/scraper/find-package-url.sh"

# GitHub config (HARDCODED — no prompts)
GIT_URL="https://github.com/Mahenking/King-Technology.git"
GIT_BRANCH="main"

# Ubuntu suite
SUITE="noble"
UBUNTU_REPO="http://ports.ubuntu.com/ubuntu-ports"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# ============================================================
# INIT
# ============================================================
mkdir -p "$PACKAGES_DIR"
mkdir -p "$TEMP_DIR"

echo -e "${PURPLE}════════════════════════════════════════════════════════${NC}"
echo -e "${PURPLE}  👑 King OS Repository Builder (Automated)${NC}"
echo -e "${PURPLE}════════════════════════════════════════════════════════${NC}"
echo ""

# Prerequisites
echo -e "${BLUE}🔍 Checking prerequisites...${NC}"
for tool in python3 wget ar tar zstd git curl; do
    if ! command -v $tool &> /dev/null; then
        echo -e "${RED}❌ Missing: $tool${NC}"
        echo -e "${YELLOW}   Install: sudo apt install -y $tool${NC}"
        exit 1
    fi
done
echo -e "${GREEN}✅ All prerequisites met${NC}"
echo ""

# Check packages.txt
if [ ! -f "$PACKAGES_LIST" ]; then
    echo -e "${RED}❌ packages.txt not found${NC}"
    exit 1
fi

# Read package names (skip comments and empty lines)
PACKAGES=()
while IFS= read -r line; do
    [[ "$line" =~ ^#.*$ ]] && continue
    [[ -z "$line" ]] && continue
    PACKAGES+=("$(echo "$line" | tr -d '[:space:]')")
done < "$PACKAGES_LIST"

echo -e "${CYAN}📦 Found ${#PACKAGES[@]} packages in packages.txt${NC}"
echo ""

if [ ${#PACKAGES[@]} -eq 0 ]; then
    echo -e "${YELLOW}⚠️  No packages to process${NC}"
    exit 0
fi

# ============================================================
# LOAD INDEX
# ============================================================
if [ ! -f "$INDEX_FILE" ]; then
    echo '{"version":"1.0","generated":"","packages":{}}' > "$INDEX_FILE"
fi

# ============================================================
# PROCESS EACH PACKAGE
# ============================================================
UPDATED=0
SKIPPED=0
FAILED=0
UPDATED_PACKAGES=()
DELETED_PACKAGES=()

for PKG in "${PACKAGES[@]}"; do
    echo -e "${PURPLE}════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}🔷 Package: $PKG${NC}"
    echo ""
    
    # Step 1: Find latest URL
    echo -e "${BLUE}   🔍 Searching for latest version...${NC}"
    URL=$("$FIND_URL" "$PKG" "$SUITE" 2>/dev/null || echo "NOT_FOUND")
    
    if [ "$URL" = "NOT_FOUND" ] || [ -z "$URL" ]; then
        echo -e "${RED}   ❌ Package not found in Ubuntu repos${NC}"
        FAILED=$((FAILED + 1))
        continue
    fi
    
    echo -e "${GREEN}   ✅ Found: $URL${NC}"
    
    FILENAME=$(basename "$URL")
    echo -e "${GREEN}   📄 Filename: $FILENAME${NC}"
    echo ""
    
    # Step 2: Download .deb
    DOWNLOAD_PATH="$TEMP_DIR/$FILENAME"
    echo -e "${BLUE}   ⬇️  Downloading...${NC}"
    if ! wget -q --show-progress -O "$DOWNLOAD_PATH" "$URL"; then
        echo -e "${RED}   ❌ Download failed${NC}"
        FAILED=$((FAILED + 1))
        continue
    fi
    echo -e "${GREEN}   ✅ Downloaded: $(du -h "$DOWNLOAD_PATH" | cut -f1)${NC}"
    echo ""
    
    # Step 3: Extract metadata
    echo -e "${BLUE}   🔍 Reading metadata...${NC}"
    rm -rf "$METADATA_DIR"
    mkdir -p "$METADATA_DIR"
    
    cd "$METADATA_DIR"
    ar x "$DOWNLOAD_PATH" 2>/dev/null
    
    CONTROL_ARCHIVE=""
    for f in control.tar*; do
        [ -f "$f" ] && CONTROL_ARCHIVE="$f" && break
    done
    
    if [ -z "$CONTROL_ARCHIVE" ]; then
        echo -e "${RED}   ❌ No control file${NC}"
        FAILED=$((FAILED + 1))
        cd "$REPO_ROOT"
        continue
    fi
    
    case "$CONTROL_ARCHIVE" in
        *.gz) tar -xzf "$CONTROL_ARCHIVE" ;;
        *.xz) tar -xJf "$CONTROL_ARCHIVE" ;;
        *.zst) tar --use-compress-program=unzstd -xf "$CONTROL_ARCHIVE" ;;
        *) tar -xf "$CONTROL_ARCHIVE" ;;
    esac
    
    PKG_NAME=$(grep "^Package:" control | cut -d' ' -f2- | tr -d '\r')
    PKG_VERSION=$(grep "^Version:" control | cut -d' ' -f2- | tr -d '\r')
    PKG_ARCH=$(grep "^Architecture:" control | cut -d' ' -f2- | tr -d '\r')
    PKG_DEPENDS_RAW=$(grep "^Depends:" control | cut -d' ' -f2- | tr -d '\r' || echo "")
    PKG_DESC=$(grep "^Description:" control | cut -d' ' -f2- | tr -d '\r' | head -1)
    
    PKG_DEPENDS=""
    if [ -n "$PKG_DEPENDS_RAW" ]; then
        PKG_DEPENDS=$(echo "$PKG_DEPENDS_RAW" | sed 's/([^)]*)//g' | sed 's/, */,/g' | sed 's/ *$//')
    fi
    
    cd "$REPO_ROOT"
    
    echo -e "${GREEN}   📋 Name:        $PKG_NAME${NC}"
    echo -e "${GREEN}   📋 Version:     $PKG_VERSION${NC}"
    echo -e "${GREEN}   📋 Arch:        $PKG_ARCH${NC}"
    echo -e "${GREEN}   📋 Depends:     ${PKG_DEPENDS:-none}${NC}"
    echo ""
    
    # Step 4: Check existing version
    OLD_VERSION=$(python3 -c "
import json
try:
    with open('$INDEX_FILE') as f:
        data = json.load(f)
    pkg = data.get('packages', {}).get('$PKG_NAME')
    if pkg:
        print(pkg.get('version', ''))
except:
    pass
")
    
    if [ "$OLD_VERSION" = "$PKG_VERSION" ]; then
        echo -e "${YELLOW}   ⏭️  Same version already in repo — skipping${NC}"
        SKIPPED=$((SKIPPED + 1))
        rm -f "$DOWNLOAD_PATH"
        continue
    fi
    
    # Step 5: Delete old versions of this package
    if [ -n "$OLD_VERSION" ]; then
        echo -e "${YELLOW}   🔄 Old version found: $OLD_VERSION${NC}"
        echo -e "${BLUE}   🗑️  Deleting old .kpk files...${NC}"
        DELETED=$(find "$PACKAGES_DIR" -name "${PKG_NAME}-*-${PKG_ARCH}.kpk" -type f)
        if [ -n "$DELETED" ]; then
            echo "$DELETED" | while read f; do
                echo -e "${YELLOW}     Removing: $(basename "$f")${NC}"
                rm -f "$f"
            done
            DELETED_PACKAGES+=("$PKG_NAME ($OLD_VERSION)")
        fi
    fi
    
    # Step 6: Convert to .kpk
    echo -e "${BLUE}   🔄 Converting to .kpk...${NC}"
    
    EXTRACT_DIR="$TEMP_DIR/build-$PKG_NAME"
    rm -rf "$EXTRACT_DIR"
    mkdir -p "$EXTRACT_DIR"
    
    cp "$DOWNLOAD_PATH" "$EXTRACT_DIR/"
    cd "$EXTRACT_DIR"
    ar x "$(basename "$DOWNLOAD_PATH")"
    
    for data_file in data.tar*; do
        [ -f "$data_file" ] || continue
        case "$data_file" in
            *.gz) tar -xzf "$data_file" ;;
            *.xz) tar -xJf "$data_file" ;;
            *.zst) tar --use-compress-program=unzstd -xf "$data_file" ;;
            *) tar -xf "$data_file" ;;
        esac
        rm -f "$data_file"
    done
    
    rm -f control.tar* debian-binary
    
    cat > manifest.json << MANIFESTEOF
{
  "name": "$PKG_NAME",
  "version": "$PKG_VERSION",
  "arch": "$PKG_ARCH",
  "built_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
MANIFESTEOF
    
    KPK_FILENAME="${PKG_NAME}-${PKG_VERSION}-${PKG_ARCH}.kpk"
    KPK_PATH="$PACKAGES_DIR/$KPK_FILENAME"
    
    tar --use-compress-program=zstd -cf "$KPK_PATH" -C "$EXTRACT_DIR" .
    
    if [ ! -f "$KPK_PATH" ]; then
        echo -e "${RED}   ❌ Packaging failed${NC}"
        FAILED=$((FAILED + 1))
        cd "$REPO_ROOT"
        continue
    fi
    
    KPK_SIZE=$(stat -c%s "$KPK_PATH")
    KPK_SHA256=$(sha256sum "$KPK_PATH" | cut -d' ' -f1)
    
    echo -e "${GREEN}   ✅ Created: $KPK_FILENAME${NC}"
    echo -e "${GREEN}   ✅ Size:    $(numfmt --to=iec $KPK_SIZE)${NC}"
    echo -e "${GREEN}   ✅ SHA256:  ${KPK_SHA256:0:16}...${NC}"
    echo ""
    
    # Step 7: Update index.json
    python3 << PYEOF
import json
from datetime import datetime, UTC

with open('$INDEX_FILE', 'r') as f:
    index = json.load(f)

if 'packages' not in index:
    index['packages'] = {}

index['packages']['$PKG_NAME'] = {
    'version': '$PKG_VERSION',
    'arch': '$PKG_ARCH',
    'filename': 'packages/$KPK_FILENAME',
    'sha256': '$KPK_SHA256',
    'size': $KPK_SIZE,
    'depends': [d for d in '$PKG_DEPENDS'.split(',') if d],
    'description': '''$PKG_DESC''',
    'date_added': datetime.now(UTC).strftime('%Y-%m-%d'),
    'reboot_required': False,
}

index['generated'] = datetime.now(UTC).isoformat()

with open('$INDEX_FILE', 'w') as f:
    json.dump(index, f, indent=2)
PYEOF
    
    echo -e "${GREEN}   ✅ Index updated${NC}"
    echo ""
    
    UPDATED=$((UPDATED + 1))
    UPDATED_PACKAGES+=("$PKG_NAME → $PKG_VERSION")
    
    # Cleanup
    rm -rf "$EXTRACT_DIR"
    rm -f "$DOWNLOAD_PATH"
    rm -rf "$METADATA_DIR"
done

# ============================================================
# SUMMARY
# ============================================================
echo ""
echo -e "${PURPLE}════════════════════════════════════════════════════════${NC}"
echo -e "${PURPLE}  📊 Build Summary${NC}"
echo -e "${PURPLE}════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "${GREEN}   ✅ Updated:  $UPDATED${NC}"
echo -e "${YELLOW}   ⏭️  Skipped:  $SKIPPED${NC}"
echo -e "${RED}   ❌ Failed:   $FAILED${NC}"
echo ""

if [ ${#UPDATED_PACKAGES[@]} -gt 0 ]; then
    echo -e "${CYAN}   Updated packages:${NC}"
    for pkg in "${UPDATED_PACKAGES[@]}"; do
        echo -e "${CYAN}     • $pkg${NC}"
    done
    echo ""
fi

if [ ${#DELETED_PACKAGES[@]} -gt 0 ]; then
    echo -e "${YELLOW}   Deleted old versions:${NC}"
    for pkg in "${DELETED_PACKAGES[@]}"; do
        echo -e "${YELLOW}     • $pkg${NC}"
    done
    echo ""
fi

# ============================================================
# AUTO PUSH TO GITHUB
# ============================================================
if [ $UPDATED -gt 0 ]; then
    echo -e "${PURPLE}════════════════════════════════════════════════════════${NC}"
    echo -e "${PURPLE}  🚀 Pushing to GitHub (Auto)${NC}"
    echo -e "${PURPLE}════════════════════════════════════════════════════════${NC}"
    echo ""
    
    cd "$REPO_ROOT"
    
    # Ensure git repo initialized
    if [ ! -d ".git" ]; then
        git init
        git branch -M main
    fi
    
    # Ensure remote configured
    if ! git remote get-url origin >/dev/null 2>&1; then
        git remote add origin "$GIT_URL"
    fi
    
    # Stage all changes
    git add -A
    
    # Commit
    COMMIT_MSG="Auto-update: $(date +%Y-%m-%d) — $UPDATED packages updated"
    git commit -m "$COMMIT_MSG" || echo -e "${YELLOW}   (No changes to commit)${NC}"
    
    # Push
    echo -e "${BLUE}   📤 Pushing...${NC}"
    git push --set-upstream origin main 2>&1 | tail -5
    
    echo ""
    echo -e "${GREEN}   ✅ Pushed to GitHub${NC}"
fi

# ============================================================
# CLEANUP
# ============================================================
rm -rf "$TEMP_DIR"

echo ""
echo -e "${PURPLE}════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  ✅ King OS Repo Build Complete!${NC}"
echo -e "${PURPLE}════════════════════════════════════════════════════════${NC}"
echo ""

