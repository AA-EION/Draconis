#!/usr/bin/env bash
# Bootstrap Draconis dev environment.
# - Ensures xcodegen is installed (via Homebrew)
# - Generates Draconis.xcodeproj from project.yml
# - Optionally opens it in Xcode

set -euo pipefail

cd "$(dirname "$0")"

require_macos() {
    if [[ "$(uname -s)" != "Darwin" ]]; then
        echo "✘ Draconis only builds on macOS (you are on $(uname -s))." >&2
        exit 1
    fi
}

require_xcodegen() {
    if command -v xcodegen >/dev/null 2>&1; then
        return
    fi
    echo "→ xcodegen not found. Installing via Homebrew…"
    if ! command -v brew >/dev/null 2>&1; then
        echo "✘ Homebrew is required. Install from https://brew.sh first." >&2
        exit 1
    fi
    brew install xcodegen
}

require_macos
require_xcodegen

echo "→ Generating Draconis.xcodeproj …"
xcodegen generate --spec project.yml

if [[ "${1:-}" == "--open" ]]; then
    echo "→ Opening Xcode …"
    open Draconis.xcodeproj
fi

echo "✓ Done. Build with:"
echo "    xcodebuild -project Draconis.xcodeproj -scheme Draconis -configuration Release"
echo "Or open Draconis.xcodeproj in Xcode and press ⌘R."
