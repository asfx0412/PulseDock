#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
cd "$PROJECT_DIR"

SDK_PATH="/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk"
SWIFTC="/Library/Developer/CommandLineTools/usr/bin/swiftc"
MODULE_CACHE="$PROJECT_DIR/.build/test-module-cache"
TEST_ROOT="/private/tmp/PulseDock-tests"
mkdir -p "$MODULE_CACHE" "$TEST_ROOT"

CLANG_MODULE_CACHE_PATH="$MODULE_CACHE" "$SWIFTC" \
  -target arm64-apple-macosx26.0 -sdk "$SDK_PATH" \
  work/CursorLiveSmokeTest.swift \
  Sources/PulseDock/Models/APIConnectorModels.swift \
  Sources/PulseDock/Models/QuotaModels.swift \
  Sources/PulseDock/Services/CursorUsageService.swift \
  -framework Foundation -framework SwiftUI \
  -o "$TEST_ROOT/cursor-live"

"$TEST_ROOT/cursor-live"
