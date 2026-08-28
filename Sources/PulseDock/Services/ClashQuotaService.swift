import Foundation
import Darwin

actor ClashQuotaService {
    private var cachedCandidateURLs: [URL]?
    nonisolated static var profilesURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/io.github.clash-verge-rev.clash-verge-rev/profiles.yaml")
    }

    func read() async -> ClashQuotaSnapshot {
        await Task.detached(priority: .utility) { Self.parse(url: Self.profilesURL) }.value
    }

    func discover(customURL: URL? = nil) async -> [ClashQuotaSnapshot] {
        if cachedCandidateURLs == nil {
            cachedCandidateURLs = await Task.detached(priority: .utility) { Self.candidateURLs() }.value
        }
        var urls = cachedCandidateURLs ?? [Self.profilesURL]
        if let customURL { urls.insert(customURL, at: 0) }
        return await Task.detached(priority: .utility) {
            var snapshots: [ClashQuotaSnapshot] = []
            var seen = Set<String>()
            for url in urls where FileManager.default.fileExists(atPath: url.path) {
                for snapshot in Self.parseAll(url: url) where seen.insert(snapshot.identifier).inserted {
                    snapshots.append(snapshot)
                }
            }
            return snapshots.sorted { ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast) }
        }.value
    }

    nonisolated static func parse(url: URL) -> ClashQuotaSnapshot {
        parseAll(url: url).last ?? ClashQuotaSnapshot(
            state: .unavailable, name: "Clash", usedBytes: 0, totalBytes: 0,
            expiresAt: nil, updatedAt: nil, autoUpdateEnabled: false,
            updateIntervalMinutes: nil, message: "未找到兼容的 Clash 订阅流量数据"
        )
    }

    nonisolated static func parseAll(url: URL) -> [ClashQuotaSnapshot] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        let sourceApp = sourceName(for: url)

        struct Candidate {
            var uid = ""
            var type = ""
            var name = "Clash"
            var upload: UInt64?
            var download: UInt64?
            var total: UInt64?
            var expire: TimeInterval?
            var updated: TimeInterval?
            var interval: Int?
            var autoUpdate = false
        }

        func value(afterColon line: String) -> String {
            guard let colon = line.firstIndex(of: ":") else { return "" }
            return String(line[line.index(after: colon)...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        }

        var candidates: [Candidate] = []
        var current: Candidate?
        var section = ""
        for raw in text.split(whereSeparator: \Character.isNewline).map(String.init) {
            if raw.hasPrefix("- uid:") {
                if let current { candidates.append(current) }
                current = Candidate(uid: value(afterColon: raw))
                section = ""
                continue
            }
            guard current != nil else { continue }
            let indent = raw.prefix { $0 == " " }.count
            let line = raw.trimmingCharacters(in: .whitespaces)
            if indent == 2, line == "extra:" { section = "extra"; continue }
            if indent == 2, line == "option:" { section = "option"; continue }
            if indent == 2 {
                section = ""
                if line.hasPrefix("type:") { current?.type = value(afterColon: line) }
                else if line.hasPrefix("name:") { current?.name = value(afterColon: line) }
                else if line.hasPrefix("updated:") { current?.updated = TimeInterval(value(afterColon: line)) }
            } else if indent == 4, section == "extra" {
                if line.hasPrefix("upload:") { current?.upload = UInt64(value(afterColon: line)) }
                else if line.hasPrefix("download:") { current?.download = UInt64(value(afterColon: line)) }
                else if line.hasPrefix("total:") { current?.total = UInt64(value(afterColon: line)) }
                else if line.hasPrefix("expire:") { current?.expire = TimeInterval(value(afterColon: line)) }
            } else if indent == 4, section == "option" {
                if line.hasPrefix("update_interval:") { current?.interval = Int(value(afterColon: line)) }
                else if line.hasPrefix("allow_auto_update:") { current?.autoUpdate = value(afterColon: line).lowercased() == "true" }
            }
        }
        if let current { candidates.append(current) }

        return candidates.compactMap { profile in
            guard profile.type == "remote", let upload = profile.upload,
                  let download = profile.download, let total = profile.total, total > 0 else { return nil }
            return ClashQuotaSnapshot(
                state: .available,
                identifier: "\(sourceApp)|\(profile.uid.isEmpty ? profile.name : profile.uid)",
                sourceApp: sourceApp,
                name: profile.name.isEmpty ? "Clash" : profile.name,
                usedBytes: upload &+ download,
                totalBytes: total,
                expiresAt: profile.expire.map(Date.init(timeIntervalSince1970:)),
                updatedAt: profile.updated.map(Date.init(timeIntervalSince1970:)),
                autoUpdateEnabled: profile.autoUpdate,
                updateIntervalMinutes: profile.interval,
                message: "数据来自 \(sourceApp) 本地订阅元数据"
            )
        }
    }

    private nonisolated static func sourceName(for url: URL) -> String {
        let path = url.path.lowercased()
        if path.contains("clash-verge") { return "Clash Verge" }
        if path.contains("nyanpasu") { return "Clash Nyanpasu" }
        if path.contains("mihomo") || path.contains("clash-party") { return "Mihomo Party" }
        return "Clash 兼容配置"
    }

    private nonisolated static func candidateURLs() -> [URL] {
        let fm = FileManager.default
        let support = fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        var urls = [profilesURL]
        guard let directories = try? fm.contentsOfDirectory(at: support, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else { return urls }
        for directory in directories {
            let name = directory.lastPathComponent.lowercased()
            guard name.contains("clash") || name.contains("mihomo") || name.contains("nyanpasu") else { continue }
            let direct = directory.appendingPathComponent("profiles.yaml")
            if fm.fileExists(atPath: direct.path) { urls.append(direct) }
            guard let enumerator = fm.enumerator(at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }
            for case let file as URL in enumerator {
                let depth = file.pathComponents.count - directory.pathComponents.count
                if depth > 3 { enumerator.skipDescendants(); continue }
                if file.lastPathComponent == "profiles.yaml" { urls.append(file) }
            }
        }
        var seen = Set<String>()
        return urls.filter { seen.insert($0.standardizedFileURL.path).inserted }
    }
}

final class ClashProfilesWatcher: @unchecked Sendable {
    private let url: URL
    private let queue = DispatchQueue(label: "com.pulsedock.clash-watcher", qos: .utility)
    private var source: DispatchSourceFileSystemObject?
    private var descriptor: Int32 = -1
    var onChange: (@Sendable () -> Void)?

    init(url: URL = ClashQuotaService.profilesURL) { self.url = url }

    func start() {
        stop()
        descriptor = open(url.path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        let openedDescriptor = descriptor
        let next = DispatchSource.makeFileSystemObjectSource(fileDescriptor: openedDescriptor, eventMask: [.write, .rename, .delete], queue: queue)
        next.setEventHandler { [weak self] in
            guard let self else { return }
            self.onChange?()
            if !next.data.intersection([.rename, .delete]).isEmpty {
                self.stop()
                self.queue.asyncAfter(deadline: .now() + 1) { self.start() }
            }
        }
        next.setCancelHandler { [weak self] in
            close(openedDescriptor)
            if self?.descriptor == openedDescriptor { self?.descriptor = -1 }
        }
        source = next
        next.resume()
    }

    func stop() {
        source?.cancel()
        source = nil
    }
}
