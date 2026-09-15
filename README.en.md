# PulseDock

<p align="center"><img src="Resources/PulseDock.png" width="112" alt="PulseDock icon"></p>

<p align="center"><strong>A macOS work-status cockpit for AI developers</strong></p>

<p align="center">See whether it is time to focus, debug, or let a job run—without opening another dashboard.</p>

<p align="center"><a href="README.md">简体中文</a> | <a href="README.en.md">English</a></p>

<p align="center">
  <a href="https://github.com/asfx0412/PulseDock/releases/latest"><img alt="Latest release" src="https://img.shields.io/github/v/release/asfx0412/PulseDock?display_name=tag&amp;sort=semver"></a>
  <a href="https://github.com/asfx0412/PulseDock/stargazers"><img alt="GitHub stars" src="https://img.shields.io/github/stars/asfx0412/PulseDock?style=flat&amp;label=stars&amp;color=ffca28"></a>
  <a href="https://hits.sh/github.com/asfx0412/PulseDock/"><img alt="Repository views" src="https://hits.sh/github.com/asfx0412/PulseDock.svg?label=views&amp;color=0ea5e9&amp;labelColor=555555"></a>
  <img alt="Platform" src="https://img.shields.io/badge/macOS-26%2B-black">
  <img alt="Architecture" src="https://img.shields.io/badge/Apple%20Silicon-arm64-8a2be2">
  <img alt="Swift" src="https://img.shields.io/badge/Swift-6.2-f05138">
</p>

<p align="center"><a href="https://github.com/asfx0412/PulseDock/releases/latest">Download latest</a> · <a href="#get-started-in-three-minutes">Get started</a> · <a href="#why-pulsedock">Why PulseDock</a></p>

PulseDock is for macOS developers who need to keep an eye on AI services, remote machines, and their focus rhythm at the same time. Its collapsible floating panel brings together the current foreground app, focus timer, network and quota state, weather, and optional device signals—showing the information worth acting on now. Data stays local where possible; secrets live in macOS Keychain and never enter this repository or configuration exports.

> **Who it is for:** AI developers on an Apple Silicon Mac who use Codex locally and may need network, SSH/GPU, or focus signals. It is not a general team-monitoring service, and it never reads web pages, chats, window titles, typed content, or files.

## Why PulseDock

| Advantage | Problem it solves | How PulseDock approaches it |
|---|---|---|
| **One glance instead of ten tabs** | It is hard to know what needs attention while coding, debugging, and running jobs | A low-distraction workspace combines foreground app, work status, focus timer, AI network, quotas, and system signals; details stay one expansion away |
| **Designed for AI development workflows** | Quotas, reachability, and remote GPUs are scattered across terminals, web pages, and tools | Read-only local Codex status plus optional Clash/Mihomo, SSH/GPU, Slurm, and API-quota connectors; enable only what you use |
| **Local-first with explicit boundaries** | Monitoring tools can create privacy and credential concerns | Activity stops at the app layer; secrets use Keychain; the timeline stays local; diagnostics and exports omit API keys, passwords, and unsanitized commands |

## What you can do

### Right now: a status panel that stays out of your way

- See the foreground app, work status, weather, focus timer, AI network, key quotas, and system signals.
- Use `⌥ Space` to show or hide the panel and `⌥ ⇧ Space` to switch between compact and expanded views.
- Keep the last successful value with a clear refresh state when a source is temporarily unavailable, instead of turning one transient failure into an alarm.

### When needed: expand into a development-environment overview

- **Insights:** today, 7-day, and 30-day app activity plus Codex token activity.
- **Devices:** optional SSH hosts, load, GPU memory, temperature/power, and Slurm jobs.
- **Diagnostics:** copyable DNS, TLS, proxy-port, OpenAI/Codex endpoint, and UI-responsiveness evidence.
- **Timeline:** local records of network, device, quota, thermal, Clash, and focus-timer events and recoveries.
- **Audio:** CC0 ambient audio, work music, and internet radio; silent until you choose to play something.

## How it works

<p align="center"><img src="docs/images/pulsedock-value-map.svg" width="800" alt="PulseDock turns development-workflow signals into a next-step decision"></p>

<p align="center"><sub>This is a product-value diagram, not a UI screenshot. Use the <a href="https://github.com/asfx0412/PulseDock/releases/latest">latest Release</a> and changelog for the current stable build, package, and changes.</sub></p>

## Get started in three minutes

### 1. Install

1. Open the [latest Release](https://github.com/asfx0412/PulseDock/releases/latest) and download `PulseDock-<version>.zip`.
2. Unzip it and drag `PulseDock.app` into Applications.
3. For the first launch, Control-click `PulseDock.app` in Finder and choose **Open**.
4. If macOS still blocks it, verify the source and choose **Open Anyway** in **System Settings → Privacy & Security**.
5. Allow notifications only if you want timer, work-status, or thermal-risk reminders.

Packages are currently ad-hoc signed and not yet notarized by Apple. After verifying the ZIP came from this project's GitHub Release, you can remove the download quarantine attribute in Terminal if Gatekeeper still blocks it:

```sh
xattr -dr com.apple.quarantine /Applications/PulseDock.app
open /Applications/PulseDock.app
```

Use this only for a release package you trust. Quit the old app from the floating-panel context menu or menu bar before replacing it during an upgrade; closing the panel does not quit the app.

### 2. Start with the defaults

The floating panel, foreground-app history, focus timer, manually selected weather, and basic local system signals work without entering a secret. Codex, remote devices, Clash/Mihomo, API quotas, and Feishu are optional connectors: they are accessed only after you explicitly configure them.

### 3. Add your environment when useful

- **Codex usage:** with Codex CLI installed and signed in locally, PulseDock reads usage windows and token activity through local `app-server` read-only endpoints. It does not read, export, or refresh the login token and does not consume reset credits.
- **Weather and location:** manual location is the default and never changes because of your public IP or proxy. Location permission is requested only if you explicitly enable automatic current-location following. The last valid weather result remains when location fails.
- **SSH/GPU:** first confirm `ssh <host-alias>` supports non-interactive key-based login, then add the same alias on the Devices page. PulseDock uses `BatchMode=yes` and never opens a background password prompt.
- **Clash/Mihomo:** it connects only to compatible local metadata, a loopback controller, or a local Unix socket; subscription URLs are not displayed or exported.
- **API quotas and Feishu:** enter credentials only in Settings. They are saved in Keychain; configuration exports, the timeline, and copyable diagnostics omit secrets.

## Privacy and feature boundaries

| Area | Explicit boundary |
|---|---|
| App activity | Records only the macOS foreground application. It does not read window titles, web pages, ChatGPT/Codex pages, chats, keystrokes, or files. |
| Credentials | API keys, webhooks, and controller secrets are in macOS Keychain. They stay in memory while editing and are saved only when you do so. |
| Data | Non-secret preferences use UserDefaults; activity and timeline data live in `~/Library/Application Support/PulseDock/`; no telemetry is uploaded. |
| Diagnostics and screenshots | Copied reports omit secrets and unsanitized commands. Before filing an issue or sharing an image, still review hosts, usernames, addresses, balances, locations, and LAN details yourself. |

See [SECURITY.md](SECURITY.md) for the complete security model and [DATA_SOURCE_CATALOG.md](DATA_SOURCE_CATALOG.md) for sources, refresh intervals, and fallbacks.

## Requirements

- An Apple Silicon (arm64) Mac;
- macOS 26.0 or later;
- Xcode Command Line Tools to build from source;
- A locally installed and signed-in Codex CLI for Codex usage;
- For SSH/GPU monitoring, a host alias in `~/.ssh/config` that supports non-interactive key-based login.

Intel Macs and older macOS releases are not currently built or tested.

## Build from source

```sh
xcode-select --install
git clone https://github.com/asfx0412/PulseDock.git
cd PulseDock
chmod +x scripts/test.sh scripts/build.sh
./scripts/test.sh
./scripts/build.sh
open outputs/PulseDock.app
```

The build produces a local `PulseDock.app` and ZIP. Read the contribution guide before working on the project.

## Further information

- [Chinese user guide](outputs/PulseDock使用文档.md)
- [Changelog](CHANGELOG.md)
- [Security and privacy](SECURITY.md)
- [Contributing](CONTRIBUTING.md)

## Compatibility and installation notes

- Only Apple Silicon + macOS 26 are built and tested.
- The package is not notarized, so first launch requires explicit user confirmation.

## Uninstall

1. If you also want to remove credentials, choose **Clear Credential Vault** in PulseDock first.
2. Quit PulseDock completely.
3. Delete `PulseDock.app`.
4. To remove local history, back up and then delete `~/Library/Application Support/PulseDock/` and related PulseDock UserDefaults.

## License

No open-source license has been selected yet. Until a `LICENSE` file is added, all rights are reserved; copying, modification, and redistribution are not authorized.
