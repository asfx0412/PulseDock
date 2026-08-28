#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
cd "$PROJECT_DIR"

SDK_PATH="/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk"
SWIFTC="/Library/Developer/CommandLineTools/usr/bin/swiftc"
MODULE_CACHE="$PROJECT_DIR/.build/test-module-cache"
TEST_ROOT="/private/tmp/PulseDock-tests"
mkdir -p "$MODULE_CACHE" "$TEST_ROOT"

compile_and_run() {
  local output="$1"
  shift
  CLANG_MODULE_CACHE_PATH="$MODULE_CACHE" "$SWIFTC" \
    -target arm64-apple-macosx26.0 -sdk "$SDK_PATH" \
    -Xfrontend -interface-compiler-version -Xfrontend 6.3.2 "$@" \
    -framework AppKit -framework Foundation -framework SwiftUI -framework Security -framework LocalAuthentication -framework AVFoundation -framework Network -framework Carbon \
    -o "$TEST_ROOT/$output"
  "$TEST_ROOT/$output"
}

compile_and_run interaction \
  work/Version612InteractionSelfTest.swift \
  Sources/PulseDock/App/FocusableFloatingPanel.swift \
  Sources/PulseDock/Views/FocusableTextField.swift

compile_and_run responsiveness \
  work/Version68ResponsivenessSelfTest.swift \
  Sources/PulseDock/Services/MainThreadResponsivenessMonitor.swift

compile_and_run formatting \
  work/Version65FormattingSelfTest.swift \
  Sources/PulseDock/Models/MonitorModels.swift \
  Sources/PulseDock/Models/ProductivityModels.swift \
  Sources/PulseDock/Models/WeatherModels.swift

compile_and_run insight_holiday \
  work/Version68InsightSelfTest.swift \
  Sources/PulseDock/Models/ProductivityModels.swift \
  Sources/PulseDock/Models/QuotaModels.swift \
  Sources/PulseDock/Models/InsightModels.swift

compile_and_run quota_media \
  work/Version65QuotaMediaSelfTest.swift \
  Sources/PulseDock/Models/QuotaModels.swift \
  Sources/PulseDock/Models/MediaModels.swift \
  Sources/PulseDock/Services/CodexQuotaService.swift \
  Sources/PulseDock/Services/InternetRadioDirectoryService.swift

compile_and_run audio_policy \
  work/Version65AudioPolicySelfTest.swift \
  Sources/PulseDock/Models/MediaModels.swift \
  Sources/PulseDock/Services/InternetRadioDirectoryService.swift \
  Sources/PulseDock/Services/AudioStreamPreflightService.swift \
  Sources/PulseDock/Services/DirectAudioRelay.swift \
  Sources/PulseDock/Services/AmbientSoundService.swift

compile_and_run feature_612 \
  work/Version612FeatureSelfTest.swift \
  Sources/PulseDock/App/GlobalHotKeyManager.swift \
  Sources/PulseDock/Models/WeatherModels.swift \
  Sources/PulseDock/Services/AudioStreamPreflightService.swift

compile_and_run remote \
  work/Version61RemoteSelfTest.swift \
  Sources/PulseDock/Models/RemoteModels.swift \
  Sources/PulseDock/Services/SSHMonitorService.swift \
  Sources/PulseDock/Services/RemoteNetworkScopeService.swift

compile_and_run ledger \
  work/Version6SelfTest.swift \
  Sources/PulseDock/Models/RemoteModels.swift \
  Sources/PulseDock/Models/ConfigurationModels.swift \
  Sources/PulseDock/Models/EventModels.swift \
  Sources/PulseDock/Models/APIConnectorModels.swift \
  Sources/PulseDock/Models/QuotaModels.swift \
  Sources/PulseDock/Services/EventLedger.swift

compile_and_run connector \
  work/Version62ConnectorSelfTest.swift \
  Sources/PulseDock/Models/APIConnectorModels.swift \
  Sources/PulseDock/Models/QuotaModels.swift \
  Sources/PulseDock/Services/CursorUsageService.swift \
  Sources/PulseDock/Services/APIConnectorService.swift

compile_and_run clash_controller \
  work/ClashControllerSelfTest.swift \
  Sources/PulseDock/Models/ProductivityModels.swift \
  Sources/PulseDock/Services/ClashControllerService.swift

compile_and_run keychain_policy \
  work/Version631KeychainSelfTest.swift \
  Sources/PulseDock/Services/SecretStore.swift \
  Sources/PulseDock/Services/CredentialVault.swift

# Regression guard: background launch and periodic loops must not read Keychain.
if sed -n '/func start()/,/func stop()/p' Sources/PulseDock/App/MonitorStore.swift | grep -q 'SecretStore.read'; then
  echo "Background start path unexpectedly reads Keychain" >&2
  exit 1
fi

if sed -n '/init()/,/func start()/p' Sources/PulseDock/App/MonitorStore.swift | grep -q 'SecretStore.read'; then
  echo "Store initialization unexpectedly reads Keychain" >&2
  exit 1
fi

if ! grep -q 'interactionNotAllowed = true' Sources/PulseDock/Services/SecretStore.swift; then
  echo "Keychain wrapper no longer guarantees non-interactive access" >&2
  exit 1
fi

if ! grep -q 'kSecUseAuthenticationUIFail' Sources/PulseDock/Services/SecretStore.swift; then
  echo "Keychain query may still open authentication UI" >&2
  exit 1
fi

if grep -E '@Published var (clashControllerSecret|feishuWebhook|feishuSigningSecret).*didSet' Sources/PulseDock/App/MonitorStore.swift >/dev/null; then
  echo "Secret fields must not write Keychain on every keystroke" >&2
  exit 1
fi

if sed -n '/func unlockCredentialVault()/,/func importReadableLegacyCredentials()/p' Sources/PulseDock/App/MonitorStore.swift | grep -q 'migrateLegacyCredentials()'; then
  echo "Vault unlock must not enumerate legacy Keychain records" >&2
  exit 1
fi

if rg -q 'AVAudioEngine|本机实时合成' Sources/PulseDock; then
  echo "Rejected procedural ambient audio is still active" >&2
  exit 1
fi

if ! rg -q 'CC0' Sources/PulseDock/Services/AmbientSoundService.swift || ! rg -q 'https://cdn.freesound.org' Sources/PulseDock/Services/AmbientSoundService.swift; then
  echo "Ambient catalog must expose verified open-source provenance" >&2
  exit 1
fi

if rg -q 'NSAllowsArbitraryLoads' Resources/Info.plist; then
  echo "Audio feature must not weaken App Transport Security" >&2
  exit 1
fi

if ! rg -q 'Radio Browser' Sources/PulseDock/Services/InternetRadioDirectoryService.swift; then
  echo "Network radio must retain third-party source attribution" >&2
  exit 1
fi

if ! /usr/libexec/PlistBuddy -c 'Print :LSMultipleInstancesProhibited' Resources/Info.plist | grep -q true; then
  echo "Single-instance launch protection is missing" >&2
  exit 1
fi

if rg -q 'Dictionary\(uniqueKeysWithValues:' Sources/PulseDock; then
  echo "PulseDock must not trust imported, remote or HTTP data to contain unique dictionary keys" >&2
  exit 1
fi

# Heavy IOKit/system metric reads must stay behind the serial sampler actor;
# MonitorStore may only publish the completed immutable snapshot.
if sed -n '/private func applySystemMetrics/,/private func runProbe/p' Sources/PulseDock/App/MonitorStore.swift | rg -q 'PDReadChipTemperature|readDieTemperature|MemoryReader|GPUReader|traffic\.read|cpu\.read'; then
  echo "MonitorStore main actor performs direct system metric reads" >&2
  exit 1
fi

if ! sed -n '/metricTask = Task/,/probeTask = Task/p' Sources/PulseDock/App/MonitorStore.swift | rg -q 'await self\.systemMetricsSampler\.sample'; then
  echo "Periodic metrics loop no longer awaits the serial background sampler" >&2
  exit 1
fi

VERSION="$(tr -d '[:space:]' < VERSION)"
PLIST_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"
[[ "$VERSION" == "$PLIST_VERSION" ]] || { echo "VERSION and Info.plist disagree" >&2; exit 1; }
for strings in Resources/*.lproj/Localizable.strings; do plutil -lint "$strings" >/dev/null; done
if ! rg -q 'CFBundleShortVersionString' Sources/PulseDock/Views/PanelViews.swift; then
  echo "Visible version label must read the application bundle version" >&2
  exit 1
fi
if rg -q 'Text\("v[0-9]+\.[0-9]+' Sources/PulseDock/Views/PanelViews.swift; then
  echo "Visible version label must not hard-code a release number" >&2
  exit 1
fi

echo "PulseDock deterministic test suite passed"
