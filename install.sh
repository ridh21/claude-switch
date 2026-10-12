#!/usr/bin/env bash
# Installer for people who do not use Homebrew.
# Usage: curl -fsSL https://raw.githubusercontent.com/ridh21/claude-switch/main/install.sh | bash

set -euo pipefail

REPO_RAW="https://raw.githubusercontent.com/ridh21/claude-switch/main"
PREFIX="${PREFIX:-$HOME/.local}"
BIN_DIR="$PREFIX/bin"

mkdir -p "$BIN_DIR"
curl -fsSL "$REPO_RAW/bin/cswitch" -o "$BIN_DIR/cswitch"
chmod +x "$BIN_DIR/cswitch"
echo "Installed cswitch to $BIN_DIR/cswitch"

case ":$PATH:" in
  *":$BIN_DIR:"*) ;;
  *) echo "Add $BIN_DIR to your PATH:  export PATH=\"$BIN_DIR:\$PATH\"" ;;
esac
