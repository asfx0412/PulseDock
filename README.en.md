# PulseDock

<p align="center">
  <img src="Resources/PulseDock.png" width="112" alt="PulseDock icon">
</p>

<p align="center">A lightweight macOS work-status panel for AI developers</p>

<p align="center"><a href="README.md">简体中文</a> | <a href="README.en.md">English</a></p>

<p align="center">
  <a href="https://github.com/asfx0412/PulseDock/releases"><img alt="Version" src="https://img.shields.io/badge/version-6.12.3-2f80ed"></a>
  <img alt="Platform" src="https://img.shields.io/badge/macOS-26%2B-black">
  <img alt="Architecture" src="https://img.shields.io/badge/Apple%20Silicon-arm64-8a2be2">
  <img alt="Swift" src="https://img.shields.io/badge/Swift-6.2-f05138">
</p>

PulseDock puts AI network health, Codex usage, Clash usage, SSH/GPU devices, app activity, a focus timer, weather, work calendars, and focus audio into a low-distraction floating panel. Data is handled locally where possible. Secrets stay in macOS Keychain and are never written to this repository or configuration exports.

> Current version: **6.12.3**. Builds target Apple Silicon and macOS 26. Packages are ad-hoc signed; Developer ID notarization and automatic updates are not available yet.

## Preview

<p align="center">
  <img src="docs/images/pulsedock-overview.png" width="620" alt="PulseDock workspace example">
</p>

<p align="center"><sub>Privacy-safe product example. Location, app name, and quota values are sample data.</sub></p>

## Highlights

| Area | What it does | Privacy boundary |
|---|---|---|
| Workspace | Work state, current app, weather, focus timer, AI network state, quotas, and system metrics | The compact panel prioritizes what needs attention now |
| Insights | Today/7-day/30-day app rankings, Codex token activity, holidays, and trends | Does not read window titles, web pages, chats, typed content, or files |
| Devices | Multiple SSH hosts, load, GPU memory, temperature/power, Slurm tasks, and Codex endpoint evidence | Reuses `~/.ssh/config` and ssh-agent; never stores private keys or passwords |
| Timeline | Network, device, quota, thermal, Clash, and timer events with evidence and recovery | Stored locally; no telemetry upload |
| Diagnostics | DNS, TLS, proxy ports, OpenAI/Codex endpoints, and UI responsiveness | Copyable reports omit API keys, passwords, and unsanitized commands |
| Settings | Work hours, shortcuts, themes, weather, Clash, API quotas, SSH, Feishu, and languages | Secrets are held in one Keychain vault |
| Audio | 24 CC0 ambient tracks, work music, internet radio, favorites, timer, and playback modes | No music-account login, no playback history, no offline audio library |

## Requirements

- An Apple Silicon (arm64) Mac;
- macOS 26.0 or later;
- Xcode Command Line Tools to build from source;
- A locally installed and signed-in Codex CLI to show Codex usage;
- For SSH/GPU monitoring, a host alias in `~/.ssh/config` that supports non-interactive key-based login.

Intel Macs and older macOS releases are not currently built or tested.

## Install

### From GitHub Releases

1. Open [Releases](https://github.com/asfx0412/PulseDock/releases) and download `PulseDock-<version>.zip`.
2. Unzip it and drag `PulseDock.app` into Applications.
3. On first launch, Control-click `PulseDock.app` in Finder and choose **Open**.
4. If macOS still blocks it, open **System Settings → Privacy & Security** and choose **Open Anyway** after verifying the source.
5. Allow notifications if you want timer, work-status, or thermal-risk reminders.

Quit the old app from the floating-panel context menu or menu bar before replacing it during an upgrade. Closing the panel does not quit the app.

### Build from source

```sh
xcode-select --install
git clone https://github.com/asfx0412/PulseDock.git
cd PulseDock
chmod +x scripts/test.sh scripts/build.sh
./scripts/test.sh
./scripts/build.sh
open outputs/PulseDock.app
```

The build creates `outputs/PulseDock.app` and `outputs/PulseDock-6.12.3.zip`. It is ad-hoc signed locally; a production distribution still needs Developer ID signing and Apple notarization.

## First-time setup

### Panel and shortcuts

- `⌥ Space`: show or hide the panel by default;
- `⌥ ⇧ Space`: expand or collapse it by default;
- Record a different combination in **Settings → Shortcuts**;
- If a shortcut is invalid, conflicts, or cannot be registered, PulseDock keeps the previous working one.

### Codex usage

PulseDock reads usage windows and token activity through the local Codex `app-server`. It does not read, export, or refresh your Codex login token and does not consume reset credits.

1. Install Codex using the [official OpenAI Codex CLI guide](https://learn.chatgpt.com/docs/codex/cli).
2. Run `codex` in Terminal and complete the official sign-in flow.
3. Reopen PulseDock or refresh the Codex card.

### Weather and location

- A manually selected location is the default and does not change with public IP or proxy nodes.
- Location permission is requested only after you explicitly enable automatic current-location following.
- If location lookup fails, the last valid weather result remains visible.

### SSH/GPU devices

First verify the alias in Terminal:

```sh
ssh <host-alias>
```

Then add the same `Host` alias on the Devices page. PulseDock uses `BatchMode=yes`, so it will not open a remote-password prompt in the background. Use ssh-agent and select the appropriate network scope: LAN-only, VPN required, or publicly reachable. Viewing sanitized launch commands is an explicit per-device option.

### Clash/Mihomo

PulseDock reads compatible local subscription metadata saved by Clash Verge/Mihomo and does not reveal subscription URLs. To refresh a provider through the running core:

1. Keep the External Controller loopback-only, or use Clash Verge’s local Unix socket.
2. Choose **Auto Discover** in PulseDock.
3. If a secret is needed, unlock the credential vault and enter it there.
4. Verify `/version`, then sync the provider.

### API quotas and Feishu

Enter GLM, DeepSeek, Feishu webhook, and Mihomo secrets only in PulseDock settings. They remain in memory while you edit and are written to Keychain only after saving. Configuration exports, the timeline, and diagnostics exclude secrets.

## Data and secret handling

- Non-secret preferences: UserDefaults;
- Activity and timeline data: `~/Library/Application Support/PulseDock/`;
- API keys, webhooks, signing secrets, and controller secrets: the `com.pulsedock.monitor` item in macOS Keychain.

Do not commit `.env` files, SSH private keys, API keys, webhooks, cookies, subscription URLs, unsanitized diagnostics, or screenshots containing real hosts, usernames, locations, quotas, or LAN details. `.gitignore` excludes common secret files, local build directories, and release artifacts.

If a secret ever reaches Git history, removing the current file is insufficient: revoke or rotate the secret immediately, then clean the history. See [SECURITY.md](SECURITY.md) for the complete security model.

## Data sources

- Codex usage and token activity: local Codex `app-server`, read-only;
- Codex community reset signal: public Codex Runway JSON, not an OpenAI commitment;
- Weather, sunrise/sunset, and moon phase: Open-Meteo;
- Holidays: project data compiled from public State Council General Office schedules;
- Clash: compatible local metadata and an optional local Mihomo controller;
- SSH/GPU: system `ssh`, local SSH configuration, and fixed read-only remote commands;
- Ambient audio: reviewed Freesound recordings with CC0 licenses;
- Work music and radio: the public Radio Browser directory.

See [DATA_SOURCE_CATALOG.md](DATA_SOURCE_CATALOG.md) for refresh schedules, authentication material, and fallbacks.

## Test

```sh
./scripts/test.sh
```

The offline suite covers quota parsing, network scope, malformed SSH/GPU input, sanitization, the credential vault, audio-URL safety, Chinese input, and shortcut regressions. A live SSH smoke test requires an explicitly authorized alias:

```sh
./scripts/test-remote.sh <host-alias>
```

See [TESTING.md](TESTING.md) and [RELEASE_CHECKLIST.md](RELEASE_CHECKLIST.md) for complete release gates.

## Uninstall

1. If you also want to remove credentials, choose **Clear Credential Vault** in PulseDock first.
2. Quit PulseDock completely.
3. Delete `PulseDock.app`.
4. To remove local history, back up and then delete `~/Library/Application Support/PulseDock/` and related PulseDock UserDefaults.

## Documentation

- [Chinese README](README.md)
- [User guide (Chinese)](outputs/PulseDock使用文档.md)
- [Changelog](CHANGELOG.md)
- [Security and privacy](SECURITY.md)
- [Data source catalog](DATA_SOURCE_CATALOG.md)
- [Ambient-audio sources and licenses](AMBIENT_SOUND_CATALOG.md)
- [Product specification](PRODUCT_SPEC.md)
- [Architecture](ARCHITECTURE.md)
- [Testing](TESTING.md)
- [Contributing](CONTRIBUTING.md)

## Current limitations

- Only Apple Silicon and macOS 26 are built and tested;
- The package is not notarized, so first launch requires explicit user confirmation;
- Automatic updates are not available;
- Cursor personal usage relies on a local, non-public internal interface and degrades explicitly when upstream fields change;
- Radio Browser is a third-party directory and cannot guarantee every stream is available in every region.

## License

No open-source license has been selected yet. Until a `LICENSE` file is added, all rights are reserved; copying, modification, and redistribution are not authorized.
