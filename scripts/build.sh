#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
cd "$PROJECT_DIR"

if [[ -d /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk && -x /Library/Developer/CommandLineTools/usr/bin/swiftc ]]; then
  DEFAULT_SDK_PATH="/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk"
  DEFAULT_SWIFTC="/Library/Developer/CommandLineTools/usr/bin/swiftc"
else
  DEFAULT_SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
  DEFAULT_SWIFTC="$(xcrun --find swiftc)"
fi
SDK_PATH="${PULSEDOCK_SDK_PATH:-$DEFAULT_SDK_PATH}"
SWIFTC="${PULSEDOCK_SWIFTC:-$DEFAULT_SWIFTC}"
BUILD_DIR="$PROJECT_DIR/.build"
APP_PATH="$PROJECT_DIR/outputs/PulseDock.app"
VERSION="$(tr -d '[:space:]' < "$PROJECT_DIR/VERSION")"
DMG_PATH="$PROJECT_DIR/outputs/PulseDock-$VERSION.dmg"
ZIP_PATH="$PROJECT_DIR/outputs/PulseDock-$VERSION.zip"

mkdir -p "$BUILD_DIR/objects" "$BUILD_DIR/release" "$BUILD_DIR/module-cache" "$BUILD_DIR/icon" outputs

PLIST_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"
[[ "$VERSION" == "$PLIST_VERSION" ]] || { echo "VERSION ($VERSION) does not match Info.plist ($PLIST_VERSION)" >&2; exit 1; }
plutil -lint Resources/Info.plist >/dev/null
for strings in Resources/*.lproj/Localizable.strings; do plutil -lint "$strings" >/dev/null; done
if [[ "${PULSEDOCK_SKIP_TESTS:-0}" != "1" ]]; then
  "$PROJECT_DIR/scripts/test.sh"
fi

clang -fobjc-arc -target arm64-apple-macosx26.0 -isysroot "$SDK_PATH" \
  -c Sources/TemperatureBridge/TemperatureBridge.m \
  -I Sources/TemperatureBridge/include \
  -o "$BUILD_DIR/objects/TemperatureBridge.o"

CLANG_MODULE_CACHE_PATH="$BUILD_DIR/module-cache" "$SWIFTC" \
  -target arm64-apple-macosx26.0 -sdk "$SDK_PATH" -parse-as-library -O \
  -Xfrontend -interface-compiler-version -Xfrontend 6.3.2 \
  Sources/PulseDock/*/*.swift "$BUILD_DIR/objects/TemperatureBridge.o" \
  -framework AppKit -framework SwiftUI -framework Charts -framework Carbon \
  -framework IOKit -framework SystemConfiguration -framework Foundation -framework UserNotifications -framework Security -framework CryptoKit -framework CoreLocation -framework MapKit \
  -framework LocalAuthentication -framework AVFoundation -framework Network -o "$BUILD_DIR/release/PulseDock"

rm -rf "$APP_PATH"
mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources"
cp "$BUILD_DIR/release/PulseDock" "$APP_PATH/Contents/MacOS/PulseDock"
cp Resources/Info.plist "$APP_PATH/Contents/Info.plist"
for locale_dir in Resources/*.lproj; do
  [[ -d "$locale_dir" ]] && cp -R "$locale_dir" "$APP_PATH/Contents/Resources/"
done

if [[ -f Resources/PulseDock.png ]]; then
  cp Resources/PulseDock.png "$BUILD_DIR/icon/icon_1024x1024.png"
elif sips -s format png Resources/PulseDock.svg --out "$BUILD_DIR/icon/icon_1024x1024.png" >/dev/null 2>&1; then
  true
fi
if [[ -f "$BUILD_DIR/icon/icon_1024x1024.png" ]]; then
  ICONSET="$BUILD_DIR/icon/PulseDock.iconset"
  rm -rf "$ICONSET"
  mkdir -p "$ICONSET"
  for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$BUILD_DIR/icon/icon_1024x1024.png" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    retina=$((size * 2))
    sips -z "$retina" "$retina" "$BUILD_DIR/icon/icon_1024x1024.png" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
  done
  if ! iconutil -c icns "$ICONSET" -o "$APP_PATH/Contents/Resources/PulseDock.icns" >/dev/null 2>&1; then
    cp "$BUILD_DIR/icon/icon_1024x1024.png" "$APP_PATH/Contents/Resources/PulseDock.png"
  fi
fi

codesign --force --deep --sign - "$APP_PATH"
rm -f "$DMG_PATH"
rm -f "$ZIP_PATH"
# ZIP is deterministic and works on every supported macOS environment. DMG
# generation can block behind DiskImageMounter sessions, so it is intentionally
# not part of the normal release path.
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_PATH"
codesign --verify --deep --strict "$APP_PATH"
lipo -archs "$APP_PATH/Contents/MacOS/PulseDock" | grep -q 'arm64'
unzip -tqq "$ZIP_PATH"
VERIFY_DIR="$(mktemp -d /private/tmp/PulseDock-release-verify.XXXXXX)"
ditto -x -k "$ZIP_PATH" "$VERIFY_DIR"
codesign --verify --deep --strict "$VERIFY_DIR/PulseDock.app"
for locale in zh-Hans zh-Hant en ja ko; do
  [[ -f "$VERIFY_DIR/PulseDock.app/Contents/Resources/$locale.lproj/Localizable.strings" ]] || { echo "Missing locale: $locale" >&2; exit 1; }
done
rm -rf "$VERIFY_DIR"
echo "$APP_PATH"
echo "$ZIP_PATH"
shasum -a 256 "$ZIP_PATH"
