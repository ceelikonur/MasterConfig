#!/bin/bash
# MasterConfig Setup — run this on a fresh Mac after cloning

set -e

echo "=== MasterConfig Setup ==="

# Check prerequisites
command -v node >/dev/null 2>&1 || { echo "Error: node not found. Install via: brew install node"; exit 1; }
command -v xcodegen >/dev/null 2>&1 || { echo "Error: xcodegen not found. Install via: brew install xcodegen"; exit 1; }
command -v claude >/dev/null 2>&1 || { echo "Error: claude not found. Install Claude Code first: https://claude.ai/claude-code"; exit 1; }

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"

# Install MCP dependencies
echo "Installing MCP dependencies..."
cd "$REPO_DIR/MasterConfig/MCP" && npm install && cd "$REPO_DIR"

# Register orchestrator MCP server with Claude
echo "Registering orchestrator MCP server..."
claude mcp add orchestrator node "$REPO_DIR/MasterConfig/MCP/orchestrator-mcp-server.js"

# Create orchestrator state directory
mkdir -p ~/.claude/orchestrator/messages
echo '[]' > ~/.claude/orchestrator/tasks.json

# Generate Xcode project
echo "Generating Xcode project..."
xcodegen generate

# Build
echo "Building..."
xcodebuild -project MasterConfig.xcodeproj -scheme MasterConfig -configuration Debug build -quiet

# Copy to Applications
echo "Installing to /Applications..."
BUILD_DIR=$(find ~/Library/Developer/Xcode/DerivedData -name "MasterConfig-*" -type d | head -1)
cp -R "$BUILD_DIR/Build/Products/Debug/MasterConfig.app" /Applications/MasterConfig.app

echo ""
echo "=== Setup complete! ==="
echo "Run: open /Applications/MasterConfig.app"
