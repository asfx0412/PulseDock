#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
cd "$PROJECT_DIR"

if [[ $# -ne 1 || ! "$1" =~ '^[A-Za-z0-9._-]+$' ]]; then
  echo "usage: ./scripts/test-remote.sh <ssh-config-alias>" >&2
  exit 64
fi

SDK_PATH="/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk"
SWIFTC="/Library/Developer/CommandLineTools/usr/bin/swiftc"
MODULE_CACHE="$PROJECT_DIR/.build/test-module-cache"
TEST_BINARY="/private/tmp/PulseDock-RemoteLiveSmokeTest"
mkdir -p "$MODULE_CACHE"

CLANG_MODULE_CACHE_PATH="$MODULE_CACHE" "$SWIFTC" \
  -target arm64-apple-macosx26.0 -sdk "$SDK_PATH" \
  work/RemoteLiveSmokeTest.swift \
  Sources/PulseDock/Models/RemoteModels.swift \
  Sources/PulseDock/Services/SSHMonitorService.swift \
  -framework Foundation -framework SwiftUI \
  -o "$TEST_BINARY"

"$TEST_BINARY" "$1"
