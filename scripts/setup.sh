#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"

echo "=== ghast setup ==="

# 1. Initialize ghostty submodule
if [ ! -f ghostty/build.zig ]; then
    echo "Initializing ghostty submodule..."
    git submodule update --init --recursive ghostty
else
    echo "Ghostty submodule already initialized."
fi

# 2. Build GhosttyKit xcframework
XCFRAMEWORK="$ROOT/ghostty/macos/GhosttyKit.xcframework"
if [ -d "$XCFRAMEWORK" ]; then
    echo "GhosttyKit.xcframework already exists, skipping build."
    echo "  (delete $XCFRAMEWORK and re-run to rebuild)"
else
    echo "Building GhosttyKit.xcframework (this takes a few minutes)..."
    cd ghostty
    zig build -Demit-xcframework=true -Dxcframework-target=universal -Doptimize=ReleaseFast
    cd "$ROOT"
    echo "GhosttyKit.xcframework built successfully."
fi

# 3. Generate Xcode project (requires xcodegen)
if command -v xcodegen &>/dev/null; then
    echo "Generating Xcode project..."
    xcodegen generate
    echo "ghast.xcodeproj generated."
else
    echo ""
    echo "WARNING: xcodegen not found. Install it to generate the Xcode project:"
    echo "  brew install xcodegen"
    echo "  xcodegen generate"
fi

echo ""
echo "=== Setup complete ==="
echo ""
echo "To build and run:"
echo "  open ghast.xcodeproj"
echo "  # or: xcodebuild -project ghast.xcodeproj -scheme ghast -configuration Debug build"
