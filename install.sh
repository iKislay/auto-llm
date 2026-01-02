#!/bin/bash

set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

INSTALL_DIR="${INSTALL_DIR:-$HOME/.local/bin}"
BINARY_NAME="auto-llm"
REPO_URL="https://raw.githubusercontent.com/iKislay/auto-llm/main"

echo "🔂 Installing Auto-LLM..."
echo ""

# Create install directory if it doesn't exist
mkdir -p "$INSTALL_DIR"

# Download the script
echo "📥 Downloading $BINARY_NAME..."
if ! curl -fsSL "$REPO_URL/auto_llm.sh" -o "$INSTALL_DIR/$BINARY_NAME"; then
    echo -e "${RED}❌ Failed to download $BINARY_NAME${NC}" >&2
    exit 1
fi

# Make it executable
chmod +x "$INSTALL_DIR/$BINARY_NAME"

echo -e "${GREEN}✅ $BINARY_NAME installed to $INSTALL_DIR/$BINARY_NAME${NC}"

# Check if install directory is in PATH
if [[ ":$PATH:" != *":$INSTALL_DIR:"* ]]; then
    echo -e "${YELLOW}⚠️  Warning: $INSTALL_DIR is not in your PATH${NC}"
    echo ""
    echo "To add it to your PATH, add this line to your shell profile:"
    echo ""

    # Detect shell
    if [[ "$SHELL" == *"zsh"* ]]; then
        echo "  echo 'export PATH=\"\$HOME/.local/bin:\$PATH\"' >> ~/.zshrc"
        echo "  source ~/.zshrc"
    elif [[ "$SHELL" == *"bash"* ]]; then
        echo "  echo 'export PATH=\"\$HOME/.local/bin:\$PATH\"' >> ~/.bashrc"
        echo "  source ~/.bashrc"
    else
        echo "  export PATH=\"\$HOME/.local/bin:\$PATH\""
    fi
    echo ""
fi

# Check for dependencies
echo ""
echo "🔍 Checking dependencies..."

missing_deps=()
optional_deps=()

# LLM CLIs (at least one required)
has_claude=false
has_gemini=false

if command -v claude &> /dev/null; then
    has_claude=true
    echo -e "  ${GREEN}✓${NC} Claude CLI installed"
else
    optional_deps+=("Claude CLI")
    echo -e "  ${YELLOW}○${NC} Claude CLI not installed"
fi

if command -v gemini &> /dev/null; then
    has_gemini=true
    echo -e "  ${GREEN}✓${NC} Gemini CLI installed"
else
    optional_deps+=("Gemini CLI")
    echo -e "  ${YELLOW}○${NC} Gemini CLI not installed"
fi

if [ "$has_claude" = "false" ] && [ "$has_gemini" = "false" ]; then
    echo -e "${YELLOW}⚠️  Neither Claude CLI nor Gemini CLI is installed.${NC}"
    echo "   You'll need at least one to use auto-llm."
fi

# Required dependencies
if command -v gh &> /dev/null; then
    echo -e "  ${GREEN}✓${NC} GitHub CLI (gh)"
else
    missing_deps+=("GitHub CLI (gh)")
    echo -e "  ${RED}✗${NC} GitHub CLI (gh) - required for PR automation"
fi

if command -v jq &> /dev/null; then
    echo -e "  ${GREEN}✓${NC} jq"
else
    missing_deps+=("jq")
    echo -e "  ${RED}✗${NC} jq - required for JSON parsing"
fi

echo ""

# Show installation instructions for missing deps
if [ ${#missing_deps[@]} -gt 0 ]; then
    echo -e "${YELLOW}📦 Install missing required dependencies:${NC}"
    echo ""
    if [[ "$OSTYPE" == "darwin"* ]]; then
        echo "  brew install gh jq"
    elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
        echo "  # GitHub CLI: https://github.com/cli/cli#installation"
        echo "  sudo apt-get install jq  # or equivalent for your distro"
    fi
    echo ""
fi

if [ "$has_claude" = "false" ] && [ "$has_gemini" = "false" ]; then
    echo -e "${BLUE}📦 Install an LLM CLI:${NC}"
    echo ""
    echo "  Claude CLI: https://claude.ai/code"
    echo "  Gemini CLI: https://ai.google.dev/gemini-api/docs/quickstart"
    echo ""
fi

echo ""
echo -e "${GREEN}🎉 Installation complete!${NC}"
echo ""
echo "Get started with:"
echo "  $BINARY_NAME --provider claude -p \"your task\" -m 5"
echo ""
echo "Or set a default provider:"
echo "  export LLM_PROVIDER=claude  # or gemini"
echo "  $BINARY_NAME -p \"your task\" -m 5"
echo ""
echo "For more information, visit: https://github.com/iKislay/auto-llm"
