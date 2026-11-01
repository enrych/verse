#!/bin/sh
# One-time setup: installs XcodeGen if needed, enables the repo's git hooks,
# and generates the Xcode project.
set -e
cd "$(dirname "$0")/.."
command -v xcodegen >/dev/null 2>&1 || brew install xcodegen
git config core.hooksPath .githooks
xcodegen
echo "Done. Open Verse.xcodeproj and press ⌘R. The project now regenerates itself after git pull."
