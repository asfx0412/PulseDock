import Foundation

enum InternetRadioDirectoryError: LocalizedError {
    case unavailable
    case invalidResponse
    case noSecureStations

    var errorDescription: String? {
        switch self {
        case .unavailable: "第三方电台目录暂时不可用"
        case .invalidResponse: "电台目录返回了无效数据"
        case .noSecureStations: "没有找到可安全播放的 HTTPS 音源"
        }
    }
}

struct InternetRadioDirectoryPage: Sendable, Equatable {
    var items: [MediaStreamItem]
    var rawCount: Int
    var requestedLimit: Int
    /// A multi-region page is made from several independent cursors.  Its
    /// aggregate raw count cannot by itself say whether any one cursor has a
    /// following page, so callers may supply the merged answer explicitly.
    var moreCandidatesOverride: Bool? = nil

    var hasMoreCandidates: Bool { moreCandidatesOverride ?? (rawCount >= requestedLimit) }
}

/// A deliberately small, read-only Radio Browser client. It requests station
/// metadata only; AVPlayer does not touch a stream until the user presses play.
actor InternetRadioDirectoryService {
    private struct Station: Decodable {
        var stationuuid: String?
        var name: String?
        var url_resolved: String?
        var homepage: String?
        var country: String?
        var countrycode: String?
        var language: String?
        var tags: String?
        var codec: String?
        var bitrate: Int?
        var lastcheckok: Int?
    }

    private let hosts = [
        "https://de1.api.radio-browser.info",
        "https://at1.api.radio-browser.info",
        "https://nl1.api.radio-browser.info"
    ]
    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 15
        session = URLSession(configuration: configuration)
    }

    func search(kind: MediaKind, query: String = "", tag: String? = nil, countryCodes: [String] = [], languageTerms: [String] = [], limit: Int = 24, offset: Int = 0) async throws -> [MediaStreamItem] {
        return try await searchPage(kind: kind, query: query, tag: tag, countryCodes: countryCodes, languageTerms: languageTerms, limit: limit, offset: offset).items
    }

    /// Returns both the safe decoded items and the number of raw directory
    /// candidates.  Pagination must be driven by the latter: six safe cards
    /// do not prove that the public catalogue has ended, and fewer than six
    /// safe cards do not prove that a later raw batch is empty.
    func searchPage(kind: MediaKind, query: String = "", tag: String? = nil, countryCodes: [String] = [], languageTerms: [String] = [], limit: Int = 24, offset: Int = 0) async throws -> InternetRadioDirectoryPage {
        // A multi-region scene cannot be a single global popularity query:
        // regional Chinese stations may never enter that first global page.
        if countryCodes.count > 1 {
            let pages = await withTaskGroup(of: (Int, InternetRadioDirectoryPage?).self, returning: [(Int, InternetRadioDirectoryPage?)].self) { group in
                for (index, countryCode) in countryCodes.enumerated() {
                    group.addTask { [kind, query, tag, languageTerms, limit, offset] in
                        do {
                            return (index, try await self.searchPage(kind: kind, query: query, tag: tag, countryCodes: [countryCode], languageTerms: languageTerms, limit: limit, offset: offset))
                        } catch {
                            return (index, nil)
                        }
                    }
                }
                var collected: [(Int, InternetRadioDirectoryPage?)] = []
                for await page in group { collected.append(page) }
                return collected.sorted { $0.0 < $1.0 }
            }
            try Task.checkCancellation()
            var merged: [MediaStreamItem] = []
            var seen = Set<String>()
            var rawCount = 0
            var hasMore = false
            for (_, page) in pages {
                guard let page else { continue }
                rawCount += page.rawCount
                hasMore = hasMore || page.hasMoreCandidates
                for item in page.items where seen.insert(item.id).inserted { merged.append(item) }
            }

            // `language=chinese` is the most useful first pass, but regional
            // catalogues commonly label the same content as Mandarin or
            // Cantonese.  Backfill only when the primary result cannot fill a
            // six-card page, and keep the country predicate on every request.
            let fallbacks = languageTerms.filter { term in
                let value = term.lowercased()
                return value != "chinese" && value != "zh"
            }
            if merged.count < 6, !fallbacks.isEmpty {
                let fallbackPages = await withTaskGroup(of: (Int, InternetRadioDirectoryPage?).self, returning: [(Int, InternetRadioDirectoryPage?)].self) { group in
                    var index = 0
                    for countryCode in countryCodes {
                        for language in fallbacks {
                            let requestIndex = index
                            index += 1
                            group.addTask { [kind, query, tag, limit, offset] in
                                do {
                                    return (requestIndex, try await self.searchPage(kind: kind, query: query, tag: tag, countryCodes: [countryCode], languageTerms: [language], limit: limit, offset: offset))
                                } catch {
                                    return (requestIndex, nil)
                                }
                            }
                        }
                    }
                    var collected: [(Int, InternetRadioDirectoryPage?)] = []
                    for await page in group { collected.append(page) }
                    return collected.sorted { $0.0 < $1.0 }
                }
                for (_, page) in fallbackPages {
                    guard let page else { continue }
                    rawCount += page.rawCount
                    hasMore = hasMore || page.hasMoreCandidates
                    for item in page.items where seen.insert(item.id).inserted { merged.append(item) }
                }
            }
            return InternetRadioDirectoryPage(
                items: merged,
                rawCount: rawCount,
                requestedLimit: max(1, min(120, limit)),
                moreCandidatesOverride: hasMore
            )
        }
        var lastError: Error = InternetRadioDirectoryError.unavailable
        let boundedLimit = max(1, min(120, limit))
        for host in hosts {
            try Task.checkCancellation()
            do {
                guard var components = URLComponents(string: host + "/json/stations/search") else { continue }
                var items = [
                    URLQueryItem(name: "hidebroken", value: "true"),
                    URLQueryItem(name: "is_https", value: "true"),
                    URLQueryItem(name: "order", value: "clickcount"),
                    URLQueryItem(name: "reverse", value: "true"),
                    URLQueryItem(name: "limit", value: String(boundedLimit)),
                    URLQueryItem(name: "offset", value: String(max(0, offset)))
                ]
                let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { items.append(URLQueryItem(name: "name", value: trimmed)) }
                if let tag, !tag.isEmpty { items.append(URLQueryItem(name: "tag", value: tag)) }
                // Ask the directory for Chinese-labelled records up front;
                // country popularity alone buries regional Chinese stations.
                if let language = languageTerms.first(where: { $0 != "zh" }) {
                    items.append(URLQueryItem(name: "language", value: language))
                }
                // Radio Browser accepts a single country-code predicate.  A
                // multi-region scene is filtered after decoding instead.
                if countryCodes.count == 1 { items.append(URLQueryItem(name: "countrycode", value: countryCodes[0])) }
                components.queryItems = items
                guard let url = components.url else { continue }
                var request = URLRequest(url: url)
                request.setValue("PulseDock/6.12.3 (macOS; personal desktop monitor)", forHTTPHeaderField: "User-Agent")
                request.setValue("application/json", forHTTPHeaderField: "Accept")
                let (bytes, response) = try await session.bytes(for: request)
                guard let http = response as? HTTPURLResponse,
                      (200..<300).contains(http.statusCode),
                      http.expectedContentLength <= 2_000_000 || http.expectedContentLength < 0 else {
                    throw InternetRadioDirectoryError.invalidResponse
                }
                var data = Data()
                data.reserveCapacity(http.expectedContentLength > 0 ? min(Int(http.expectedContentLength), 2_000_000) : 32_768)
                for try await byte in bytes {
                    try Task.checkCancellation()
                    guard data.count < 2_000_000 else { throw InternetRadioDirectoryError.invalidResponse }
                    data.append(byte)
                }
                let rawCount = (try? JSONSerialization.jsonObject(with: data) as? [Any])?.count ?? -1
                let decoded = try Self.decode(data, kind: kind, countryCodes: countryCodes, languageTerms: languageTerms)
                // A valid empty array is a successful search with no matches.
                // Do not continue to another mirror and replace it with that
                // mirror's unrelated TLS/DNS error.
                if rawCount == 0 { return InternetRadioDirectoryPage(items: [], rawCount: 0, requestedLimit: boundedLimit) }
                // A full raw page with zero compatible HTTPS streams still
                // has a meaningful next cursor. Return it instead of treating
                // filtering as an end-of-catalogue network error.
                return InternetRadioDirectoryPage(items: decoded, rawCount: max(0, rawCount), requestedLimit: boundedLimit)
            } catch {
                if error is CancellationError { throw error }
                lastError = error
            }
        }
        throw lastError
    }

    nonisolated static func decode(_ data: Data, kind: MediaKind, countryCodes: [String] = [], languageTerms: [String] = []) throws -> [MediaStreamItem] {
        let stations: [Station]
        do { stations = try JSONDecoder().decode([Station].self, from: data) }
        catch { throw InternetRadioDirectoryError.invalidResponse }

        var seenIDs = Set<String>()
        var seenURLs = Set<String>()
        let result = stations.prefix(120).compactMap { station -> MediaStreamItem? in
            guard station.lastcheckok == 1,
                  let rawID = station.stationuuid?.trimmingCharacters(in: .whitespacesAndNewlines), !rawID.isEmpty,
                  let name = station.name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty,
                  let rawStream = station.url_resolved,
                  let stream = URL(string: rawStream), stream.scheme?.lowercased() == "https",
                  stream.user == nil, stream.password == nil,
                  isPublicStreamHost(stream.host),
                  supported(codec: station.codec, stream: stream),
                  countryMatches(station.countrycode, country: station.country, allowed: countryCodes),
                  languageMatches(station.language, allowed: languageTerms),
                  contentMatches(kind: kind, name: name, tags: station.tags) else { return nil }
            let normalized = stream.absoluteString.lowercased()
            let normalizedID = rawID.lowercased()
            guard seenIDs.insert(normalizedID).inserted, seenURLs.insert(normalized).inserted else { return nil }
            let homepage = station.homepage.flatMap(URL.init(string:)).flatMap { $0.scheme?.lowercased() == "https" ? $0 : nil }
                ?? URL(string: "https://www.radio-browser.info/")!
            let details = [station.country, station.language, station.codec?.uppercased()].compactMap { value in
                guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
                return String(trimmed.prefix(48))
            }.joined(separator: " · ")
            return MediaStreamItem(
                id: "radio-browser:\(String(normalizedID.prefix(128)))", kind: kind, title: String(name.prefix(120)),
                subtitle: details.isEmpty ? "网络直播流" : details,
                symbol: kind == .music ? "music.note" : "radio",
                streamURL: stream, sourcePage: homepage,
                provider: "Radio Browser", license: "第三方电台目录",
                country: station.country, language: station.language,
                codec: station.codec, bitrateKbps: station.bitrate,
                isLive: true
            )
        }
        return Array(result.prefix(120))
    }

    private nonisolated static func isPublicStreamHost(_ rawHost: String?) -> Bool {
        guard let host = rawHost?.lowercased(), host.contains("."),
              host != "localhost", !host.hasSuffix(".localhost"), !host.hasSuffix(".local") else { return false }
        if host == "::1" || host.hasPrefix("fe80:") || host.hasPrefix("fc") || host.hasPrefix("fd") { return false }
        let parts = host.split(separator: ".").compactMap { Int($0) }
        if parts.count == 4, parts.allSatisfy({ (0...255).contains($0) }) {
            let a = parts[0], b = parts[1]
            if a == 0 || a == 10 || a == 127 || a >= 224 { return false }
            if a == 169 && b == 254 { return false }
            if a == 172 && (16...31).contains(b) { return false }
            if a == 192 && b == 168 { return false }
            if a == 100 && (64...127).contains(b) { return false }
        }
        return true
    }

    private nonisolated static func supported(codec: String?, stream: URL) -> Bool {
        let value = codec?.uppercased() ?? ""
        if value.contains("MP3") || value.contains("AAC") || value.contains("HLS") { return true }
        let lower = stream.path.lowercased()
        return lower.hasSuffix(".mp3") || lower.hasSuffix(".aac") || lower.hasSuffix(".m3u8")
    }

    private nonisolated static func countryMatches(_ code: String?, country: String?, allowed: [String]) -> Bool {
        guard !allowed.isEmpty else { return true }
        if allowed.contains((code ?? "").uppercased()) { return true }
        let names: [String: String] = [
            "china": "CN", "hong kong": "HK", "macao": "MO", "macau": "MO", "taiwan": "TW",
            "singapore": "SG", "malaysia": "MY", "united states": "US", "canada": "CA",
            "australia": "AU", "new zealand": "NZ", "united kingdom": "GB"
        ]
        let label = country?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        return names[label].map(allowed.contains) ?? false
    }

    private nonisolated static func languageMatches(_ language: String?, allowed: [String]) -> Bool {
        guard !allowed.isEmpty else { return true }
        let reported = (language ?? "").lowercased()
        return allowed.contains { reported.contains($0.lowercased()) }
    }

    /// Work music is deliberately not a second radio tab.  The public
    /// directory is noisy, so we require an explicit music-style tag and
    /// reject station/frequency/spoken-program labels.  Radio remains broad.
    private nonisolated static func contentMatches(kind: MediaKind, name: String, tags: String?) -> Bool {
        guard kind == .music else { return true }
        let haystack = "\(name) \(tags ?? "")".lowercased()
        let excluded = [" radio", "fm", "广播", "電台", "talk", "news", "podcast", "sport", "财经", "新闻"]
        guard !excluded.contains(where: { haystack.contains($0) }) else { return false }
        let musicSignals = ["music", "lofi", "lo-fi", "chill", "jazz", "classical", "piano", "instrumental", "ambient", "soundtrack", "study", "音乐", "音樂", "钢琴", "古典", "爵士", "纯音"]
        return musicSignals.contains(where: { haystack.contains($0) })
    }
}
