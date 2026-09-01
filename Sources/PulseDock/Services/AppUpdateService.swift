import AppKit
import CryptoKit
import Foundation
import Security

/// GitHub Releases based updater. It does not depend on an Apple Developer ID:
/// authenticity comes from the Ed25519 signature embedded in every manifest.
enum AppUpdateConfiguration {
    static let manifestURL = URL(string: "https://github.com/asfx0412/PulseDock/releases/latest/download/latest-macos-arm64.json")!

    // Run `swift scripts/generate_update_key.swift` once before the first release,
    // add its private value to GitHub Actions secrets, then paste its public value
    // here. Never commit the private value.
    static let publicKeyBase64 = "SsvXTiZd9Jfbx30iLpaaGF3eOeGN3HqgN7R4Sbrj7pA="
    static let lastAutomaticCheckKey = "PulseDock.update.lastAutomaticCheck"
    /// A small signed JSON manifest is fetched at this cadence while the app
    /// runs. No archive download happens until the user explicitly updates.
    static let automaticCheckInterval: TimeInterval = 2 * 60 * 60
}

struct AppUpdateManifest: Codable, Sendable {
    let version: String
    let url: URL
    let sha256: String
    let signature: String
    let publishedAt: String
    let notes: String

    /// This exact, newline-delimited form is signed by the release script.
    var signedPayload: Data {
        // `notes` is deliberately covered too: release text is security
        // relevant because it is presented immediately before install.
        Data([version, url.absoluteString, sha256.lowercased(), publishedAt, notes].joined(separator: "\n").utf8)
    }

    /// Kept alongside the canonical payload so release tooling and fixtures
    /// can prove that a changed release note is rejected by the same Ed25519
    /// rule used by the client.
    static func verifiesSignature(_ manifest: AppUpdateManifest, publicKeyBase64: String) -> Bool {
        guard let publicData = Data(base64Encoded: publicKeyBase64),
              let signature = Data(base64Encoded: manifest.signature),
              let key = try? Curve25519.Signing.PublicKey(rawRepresentation: publicData) else { return false }
        return key.isValidSignature(signature, for: manifest.signedPayload)
    }
}

enum AppUpdateError: LocalizedError {
    case notConfigured
    case invalidManifest
    case invalidSignature
    case invalidDownloadURL
    case invalidVersion
    case downloadTooLarge
    case hashMismatch
    case invalidArchive
    case installationUnavailable
    case installationFailed

    var errorDescription: String? {
        switch self {
        case .notConfigured: "自动更新尚未完成发布密钥配置。"
        case .invalidManifest: "更新清单格式无效。"
        case .invalidSignature: "更新签名校验失败，已拒绝安装。"
        case .invalidDownloadURL: "更新包地址不安全或无效。"
        case .invalidVersion: "更新版本或发布清单不符合安全规则。"
        case .downloadTooLarge: "更新包超过允许大小。"
        case .hashMismatch: "更新包校验失败，已拒绝安装。"
        case .invalidArchive: "更新包内容无效。"
        case .installationUnavailable: "当前 App 位置不可写，无法自动替换。"
        case .installationFailed: "无法启动更新安装器。"
        }
    }
}

actor AppUpdateService {
    private let session: URLSession
    private var checking: Task<AppUpdateManifest?, Error>?
    private var downloads: [String: Task<URL, Error>] = [:]

    init(session: URLSession = .shared) { self.session = session }

    func checkForUpdate(currentVersion: String) async throws -> AppUpdateManifest? {
        if let checking { return try await checking.value }
        let task = Task { [session] in
            try await Self.fetchUpdate(session: session, currentVersion: currentVersion)
        }
        checking = task
        defer { checking = nil }
        return try await task.value
    }

    private static func fetchUpdate(session: URLSession, currentVersion: String) async throws -> AppUpdateManifest? {
        guard !AppUpdateConfiguration.publicKeyBase64.isEmpty else { throw AppUpdateError.notConfigured }
        let (data, response) = try await session.data(from: AppUpdateConfiguration.manifestURL)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200, data.count <= 256_000,
              let manifest = try? JSONDecoder().decode(AppUpdateManifest.self, from: data) else {
            throw AppUpdateError.invalidManifest
        }
        try verify(manifest)
        return SemanticVersion(manifest.version) > SemanticVersion(currentVersion) ? manifest : nil
    }

    func downloadAndStage(_ manifest: AppUpdateManifest) async throws -> URL {
        if let download = downloads[manifest.version] { return try await download.value }
        let task = Task { [session] in try await Self.downloadAndStage(manifest, session: session) }
        downloads[manifest.version] = task
        defer { downloads[manifest.version] = nil }
        return try await task.value
    }

    /// Removes an already-verified update staging root when installation could
    /// not be launched.  The path is deliberately constrained to the exact
    /// temporary `PulseDock-update-*/PulseDock.app` shape produced above, so
    /// an error path can never be turned into arbitrary file deletion.
    func discardStagedApp(_ stagedApp: URL) {
        guard let root = Self.stagingRoot(for: stagedApp) else { return }
        try? FileManager.default.removeItem(at: root)
    }

    private static func downloadAndStage(_ manifest: AppUpdateManifest, session: URLSession) async throws -> URL {
        try verify(manifest)
        guard validDownloadURL(manifest.url, version: manifest.version) else { throw AppUpdateError.invalidDownloadURL }
        let (temporaryURL, response) = try await session.download(from: manifest.url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw AppUpdateError.invalidDownloadURL }
        let attributes = try FileManager.default.attributesOfItem(atPath: temporaryURL.path)
        guard (attributes[.size] as? NSNumber)?.intValue ?? 0 <= 300 * 1024 * 1024 else { throw AppUpdateError.downloadTooLarge }
        let archiveData = try Data(contentsOf: temporaryURL, options: .mappedIfSafe)
        guard SHA256.hash(data: archiveData).hexString == manifest.sha256.lowercased() else { throw AppUpdateError.hashMismatch }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("PulseDock-update-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var keepStagingDirectory = false
        defer {
            if !keepStagingDirectory { try? FileManager.default.removeItem(at: root) }
        }
        let archive = root.appendingPathComponent("update.zip")
        try FileManager.default.moveItem(at: temporaryURL, to: archive)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", archive.path, root.path]
        try process.run(); process.waitUntilExit()
        let app = root.appendingPathComponent("PulseDock.app", isDirectory: true)
        guard process.terminationStatus == 0,
              let bundle = Bundle(url: app), bundle.bundleIdentifier == Bundle.main.bundleIdentifier,
              bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String == manifest.version,
              bundle.executableURL != nil,
              validatesCodeSignature(at: app),
              containsArm64Executable(at: app) else {
            try? FileManager.default.removeItem(at: root); throw AppUpdateError.invalidArchive
        }
        keepStagingDirectory = true
        return app
    }

    private static func verify(_ manifest: AppUpdateManifest) throws {
        guard SemanticVersion.isStrictRelease(manifest.version),
              manifest.sha256.range(of: "^[0-9a-fA-F]{64}$", options: .regularExpression) != nil,
              manifest.notes.utf8.count <= 32_000,
              ISO8601DateFormatter().date(from: manifest.publishedAt) != nil,
              validDownloadURL(manifest.url, version: manifest.version) else { throw AppUpdateError.invalidVersion }
        guard AppUpdateManifest.verifiesSignature(manifest, publicKeyBase64: AppUpdateConfiguration.publicKeyBase64) else { throw AppUpdateError.invalidSignature }
    }

    private static func validDownloadURL(_ url: URL, version: String) -> Bool {
        let expected = "/asfx0412/PulseDock/releases/download/v\(version)/PulseDock-\(version).zip"
        return url.scheme == "https" && url.host == "github.com" && url.port == nil && url.path == expected && url.query == nil && url.fragment == nil
    }

    private static func stagingRoot(for stagedApp: URL) -> URL? {
        let app = stagedApp.standardizedFileURL
        let root = app.deletingLastPathComponent().standardizedFileURL
        let temporary = FileManager.default.temporaryDirectory.standardizedFileURL
        guard app.lastPathComponent == "PulseDock.app",
              root.deletingLastPathComponent().standardizedFileURL == temporary,
              root.lastPathComponent.hasPrefix("PulseDock-update-") else { return nil }
        return root
    }

    private static func validatesCodeSignature(at app: URL) -> Bool {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(app as CFURL, SecCSFlags(), &code) == errSecSuccess,
              let code else { return false }
        return SecStaticCodeCheckValidity(code, SecCSFlags(), nil) == errSecSuccess
    }

    private static func containsArm64Executable(at app: URL) -> Bool {
        guard let executable = Bundle(url: app)?.executableURL else { return false }
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/lipo")
        process.arguments = ["-archs", executable.path]
        process.standardOutput = output
        guard (try? process.run()) != nil else { return false }
        process.waitUntilExit()
        let architectures = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        return process.terminationStatus == 0 && architectures.split(whereSeparator: \.isWhitespace).contains("arm64")
    }
}

@MainActor
final class AppUpdateController {
    private let service = AppUpdateService()
    private var isChecking = false

    func automaticallyCheckForUpdate() {
        let last = UserDefaults.standard.object(forKey: AppUpdateConfiguration.lastAutomaticCheckKey) as? Date ?? .distantPast
        guard Date().timeIntervalSince(last) >= AppUpdateConfiguration.automaticCheckInterval else { return }
        UserDefaults.standard.set(Date(), forKey: AppUpdateConfiguration.lastAutomaticCheckKey)
        checkForUpdate(userInitiated: false)
    }

    func checkForUpdate(userInitiated: Bool) {
        guard !isChecking else { return }
        isChecking = true
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
        Task { [weak self] in
            defer { self?.isChecking = false }
            do {
                guard let update = try await self?.service.checkForUpdate(currentVersion: version) else {
                    if userInitiated { self?.show(title: "PulseDock 已是最新版本", message: "当前版本 v\(version)。") }
                    return
                }
                self?.offer(update)
            } catch {
                if userInitiated { self?.show(title: "检查更新失败", message: error.localizedDescription) }
            }
        }
    }

    private func offer(_ update: AppUpdateManifest) {
        let alert = NSAlert()
        alert.messageText = "发现 PulseDock v\(update.version)"
        alert.informativeText = update.notes.isEmpty ? "新版本已可用。" : update.notes
        alert.addButton(withTitle: "下载并更新")
        alert.addButton(withTitle: "稍后")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        Task {
            do {
                let stagedApp = try await service.downloadAndStage(update)
                do {
                    try launchInstaller(stagedApp: stagedApp)
                } catch {
                    await service.discardStagedApp(stagedApp)
                    throw error
                }
                NSApp.terminate(nil)
            } catch { show(title: "更新失败", message: error.localizedDescription) }
        }
    }

    private func launchInstaller(stagedApp: URL) throws {
        let currentApp = Bundle.main.bundleURL.resolvingSymlinksInPath()
        let parent = currentApp.deletingLastPathComponent()
        guard FileManager.default.isWritableFile(atPath: parent.path) else { throw AppUpdateError.installationUnavailable }
        let stagingRoot = stagedApp.deletingLastPathComponent().standardizedFileURL
        let temporaryRoot = FileManager.default.temporaryDirectory.standardizedFileURL
        guard stagedApp.lastPathComponent == "PulseDock.app",
              stagingRoot.path.hasPrefix(temporaryRoot.path + "/PulseDock-update-") else { throw AppUpdateError.invalidArchive }
        let helper = FileManager.default.temporaryDirectory.appendingPathComponent("PulseDock-updater-\(UUID().uuidString).sh")
        let script = """
#!/bin/zsh
set -eu
app="$1"; staged="$2"; pid="$3"; staging_root="$4"; backup="${app}.previous"; failed="${app}.failed"
cleanup() { rm -rf "$staging_root"; rm -f "$0"; }
trap cleanup EXIT
while kill -0 "$pid" 2>/dev/null; do sleep 0.2; done
rm -rf "$backup"
rm -rf "$failed"
mv "$app" "$backup"
if mv "$staged" "$app"; then
  open "$app" --args --pulsedock-update-confirm "$backup"
  for i in {1..100}; do
    [[ ! -e "$backup" ]] && exit 0
    sleep 0.2
  done
  mv "$app" "$failed"
  mv "$backup" "$app"
  open "$app"
  rm -rf "$failed"
else
  mv "$backup" "$app"
fi
"""
        try script.write(to: helper, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: helper.path)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = [helper.path, currentApp.path, stagedApp.path, "\(ProcessInfo.processInfo.processIdentifier)", stagingRoot.path]
        do {
            try process.run()
        } catch {
            try? FileManager.default.removeItem(at: helper)
            try? FileManager.default.removeItem(at: stagingRoot)
            throw error
        }
    }

    private func show(title: String, message: String) {
        let alert = NSAlert(); alert.messageText = title; alert.informativeText = message; alert.addButton(withTitle: "好"); alert.runModal()
    }
}

private struct SemanticVersion: Comparable {
    let components: [Int]
    init(_ value: String) { components = value.split(separator: ".").map { Int($0.prefix { $0.isNumber }) ?? 0 } }
    static func isStrictRelease(_ value: String) -> Bool {
        value.range(of: "^[0-9]+\\.[0-9]+\\.[0-9]+$", options: .regularExpression) != nil
    }
    static func < (lhs: Self, rhs: Self) -> Bool {
        for index in 0..<max(lhs.components.count, rhs.components.count) {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right { return left < right }
        }
        return false
    }
}

private extension Digest {
    var hexString: String { map { String(format: "%02x", $0) }.joined() }
}
