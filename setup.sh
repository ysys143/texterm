#!/usr/bin/env bash
# One-time setup: downloads KaTeX and verifies build tools are available.
set -e

echo "=== texterm setup ==="

# Check Xcode command-line tools
if ! xcrun --show-sdk-path --sdk macosx &>/dev/null; then
  echo "ERROR: Xcode command-line tools not found."
  echo "Install with: xcode-select --install"
  exit 1
fi

# Check Swift
if ! command -v swiftc &>/dev/null; then
  echo "ERROR: swiftc not found. Install Xcode or the Swift toolchain."
  exit 1
fi

echo "swiftc: $(swiftc --version | head -1)"

# Download KaTeX
make setup

echo ""
echo "Setup complete. Build and run with:"
echo "  make run"
