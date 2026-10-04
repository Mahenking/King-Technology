#!/bin/bash
# ============================================================
# 👑 King OS Repo - One-Click Setup
# ============================================================
# Your friend runs this ONCE on a fresh machine.
# ============================================================

set -e

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$REPO_ROOT/config/repo.conf"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m'

echo -e "${PURPLE}════════════════════════════════════════════════════════${NC}"
echo -e "${PURPLE}  👑 King OS Repo - Setup${NC}"
echo -e "${PURPLE}════════════════════════════════════════════════════════${NC}"
echo ""

# ============================================================
# STEP 1: Check prerequisites
# ============================================================
echo -e "${BLUE}🔍 Checking prerequisites...${NC}"

MISSING=()
for tool in python3 wget ar tar zstd git curl; do
    if ! command -v $tool &> /dev/null; then
        MISSING+=("$tool")
    fi
done

if [ ${#MISSING[@]} -gt 0 ]; then
    echo -e "${RED}❌ Missing tools: ${MISSING[*]}${NC}"
    echo ""
    echo -e "${YELLOW}Installing missing tools...${NC}"
    sudo apt update
    sudo apt install -y "${MISSING[@]}"
fi

echo -e "${GREEN}✅ All prerequisites met${NC}"
echo ""

# ============================================================
# STEP 2: Load config
# ============================================================
if [ ! -f "$CONFIG_FILE" ]; then
    echo -e "${RED}❌ Config file not found: $CONFIG_FILE${NC}"
    exit 1
fi

source "$CONFIG_FILE"

echo -e "${BLUE}📋 Repo Configuration:${NC}"
echo -e "${BLUE}   GitHub:   $GIT_URL${NC}"
echo -e "${BLUE}   Branch:   $GIT_BRANCH${NC}"
echo -e "${BLUE}   Ubuntu:   $UBUNTU_REPO ($UBUNTU_SUITE)${NC}"
echo -e "${BLUE}   Arch:     $UBUNTU_ARCH${NC}"
echo ""

# ============================================================
# STEP 3: Initialize Git repo
# ============================================================
echo -e "${BLUE}🔧 Initializing Git repo...${NC}"

cd "$REPO_ROOT"

if [ ! -d ".git" ]; then
    git init
    git branch -M main
    echo -e "${GREEN}✅ Git initialized${NC}"
else
    echo -e "${YELLOW}⏭️  Git already initialized${NC}"
fi

# Set remote
if ! git remote get-url origin >/dev/null 2>&1; then
    git remote add origin "$GIT_URL"
    echo -e "${GREEN}✅ Remote added: $GIT_URL${NC}"
else
    git remote set-url origin "$GIT_URL"
    echo -e "${GREEN}✅ Remote updated: $GIT_URL${NC}"
fi

# Configure git user
git config user.name "$GIT_USER"
git config user.email "${GIT_USER}@users.noreply.github.com"
echo -e "${GREEN}✅ Git user configured${NC}"
echo ""

# ============================================================
# STEP 4: Setup credentials (PAT)
# ============================================================
echo -e "${YELLOW}════════════════════════════════════════════════════════${NC}"
echo -e "${YELLOW}  🔐 GitHub Authentication Setup${NC}"
echo -e "${YELLOW}════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "${BLUE}You need a GitHub Personal Access Token (PAT).${NC}"
echo -e "${BLUE}If you don't have one, follow these steps:${NC}"
echo ""
echo -e "${CYAN}  1. Go to: https://github.com/settings/tokens${NC}"
echo -e "${CYAN}  2. Click 'Generate new token (classic)'${NC}"
echo -e "${CYAN}  3. Name: 'King OS Repo'${NC}"
echo -e "${CYAN}  4. Check the 'repo' scope${NC}"
echo -e "${CYAN}  5. Click 'Generate token'${NC}"
echo -e "${CYAN}  6. Copy the token (starts with ghp_)${NC}"
echo ""
read -p "   Do you have your PAT ready? (y/n): " HAS_PAT

if [ "$HAS_PAT" = "y" ] || [ "$HAS_PAT" = "Y" ]; then
    echo ""
    echo -e "${BLUE}Enter your PAT (input will be hidden):${NC}"
    read -s -p "   PAT: " PAT
    echo ""
    
    if [ -z "$PAT" ]; then
        echo -e "${RED}❌ No PAT entered${NC}"
        exit 1
    fi
    
    # Store credentials
    git config --global credential.helper store
    
    # Write credentials file
    CRED_FILE="$HOME/.git-credentials"
    echo "https://${GIT_USER}:${PAT}@github.com" > "$CRED_FILE"
    chmod 600 "$CRED_FILE"
    
    echo -e "${GREEN}✅ Credentials saved to $CRED_FILE${NC}"
else
    echo ""
    echo -e "${YELLOW}⚠️  You can add credentials later with:${NC}"
    echo -e "${CYAN}   git config --global credential.helper store${NC}"
    echo -e "${CYAN}   Then push once and enter your PAT${NC}"
fi
echo ""

# ============================================================
# STEP 5: Initialize empty files
# ============================================================
echo -e "${BLUE}📁 Initializing repo files...${NC}"

# Create packages dir
mkdir -p "$PACKAGES_DIR"

# Create packages.txt if missing
if [ ! -f "$PACKAGES_LIST" ]; then
    cat > "$PACKAGES_LIST" << 'EOF'
# King OS Master Package List
# Just list package names, one per line
# The script will find the latest version automatically

# ============ BASE SYSTEM ============
python3
curl
wget
git

# ============ DEVELOPMENT ============
gcc
cmake
make

# ============ TOOLS ============
htop
nano
vim
zip
unzip
tree
EOF
    echo -e "${GREEN}✅ packages.txt created${NC}"
fi

# Create empty index.json
if [ ! -f "$INDEX_FILE" ]; then
    echo '{"version":"1.0","generated":"","packages":{}}' > "$INDEX_FILE"
    echo -e "${GREEN}✅ index.json created${NC}"
fi

# Create empty sources.txt
if [ ! -f "$REPO_ROOT/sources.txt" ]; then
    echo '# Auto-generated by king-repo-build.sh' > "$REPO_ROOT/sources.txt"
    echo -e "${GREEN}✅ sources.txt created${NC}"
fi

echo ""

# ============================================================
# STEP 6: Test connection
# ============================================================
echo -e "${BLUE}🔗 Testing GitHub connection...${NC}"
if git ls-remote "$GIT_URL" &>/dev/null; then
    echo -e "${GREEN}✅ GitHub connection successful${NC}"
else
    echo -e "${YELLOW}⚠️  Could not reach GitHub — check your internet or credentials${NC}"
fi
echo ""

# ============================================================
# DONE
# ============================================================
echo -e "${PURPLE}════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  ✅ Setup Complete!${NC}"
echo -e "${PURPLE}════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "${CYAN}Next steps:${NC}"
echo -e "${CYAN}  1. Edit packages.txt to add/remove packages${NC}"
echo -e "${CYAN}  2. Run: ./king-repo-build.sh${NC}"
echo -e "${CYAN}  3. Watch the magic happen (auto-download + auto-push)${NC}"
echo ""
echo -e "${YELLOW}💡 Tip: Just add package names, one per line.${NC}"
echo -e "${YELLOW}   The script finds URLs and versions automatically.${NC}"
echo ""

