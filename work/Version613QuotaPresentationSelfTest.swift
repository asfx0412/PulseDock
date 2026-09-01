import Foundation

@main
enum Version613QuotaPresentationSelfTest {
    static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
            exit(1)
        }
    }

    static func main() {
        let builtIn = APIConnectorConfiguration.codexLocalDefault
        require(builtIn.id == APIConnectorConfiguration.codexLocalID, "Codex connector must use a stable singleton id")
        require(builtIn.kind == .codexLocalQuota && builtIn.enabled && builtIn.pinned, "Codex migration default must be enabled and pinned")
        require(builtIn.showOnDashboard, "Codex migration default should be available in the Workbench")
        require(!APIConnectorKind.codexLocalQuota.requiresAPIKey, "Codex local reader must never request an API key")
        require(APIConnectorKind.codexLocalQuota.isBuiltInSingleton, "Codex must be marked as a non-removable singleton")

        let duplicateID = UUID()
        let malformed = [
            APIConnectorConfiguration(id: APIConnectorConfiguration.codexLocalID, name: "not Codex", kind: .customRateLimit, endpoint: "https://one.example"),
            APIConnectorConfiguration(id: duplicateID, name: "one", kind: .customRateLimit, endpoint: "https://two.example"),
            APIConnectorConfiguration(id: duplicateID, name: "two", kind: .cursorLocalUsage, endpoint: APIConnectorKind.cursorLocalUsage.defaultEndpoint)
        ]
        let sanitized = APIConnectorConfiguration.sanitizeForStorage(malformed)
        require(sanitized.filter { $0.kind == .codexLocalQuota }.count == 1, "migration must add exactly one Codex singleton")
        require(!sanitized.filter { $0.kind != .codexLocalQuota }.contains(where: { $0.id == APIConnectorConfiguration.codexLocalID }), "ordinary connector must never occupy reserved Codex id")
        require(Set(sanitized.map(\.id)).count == sanitized.count, "migration must repair all duplicate connector ids")
        require(APIConnectorConfiguration.sanitizeForStorage(sanitized) == sanitized, "connector migration must be idempotent")

        let legacyPins = APIConnectorConfiguration.sanitizeForStorage([
            APIConnectorConfiguration(name: "GLM", kind: .glmCodingPlan, endpoint: "https://example.com/glm", pinned: true, sortOrder: 0),
            APIConnectorConfiguration(name: "Cursor", kind: .cursorLocalUsage, endpoint: APIConnectorKind.cursorLocalUsage.defaultEndpoint, pinned: true, sortOrder: 1)
        ])
        require(legacyPins.filter(\.pinned).count == 1, "compact panel must have at most one pinned quota")
        require(legacyPins.filter(\.showOnDashboard).count >= 2, "legacy compact pins must remain visible on the Workbench")

        let id = UUID()
        let source = APIConnectorConfiguration(name: "GLM", kind: .glmCodingPlan, endpoint: APIConnectorKind.glmCodingPlan.defaultEndpoint)
        let snapshot = APIConnectorSnapshot(
            id: id,
            state: .available,
            updatedAt: Date(timeIntervalSince1970: 1_000),
            message: "fixture",
            usageWindows: [
                APIUsageWindow(id: "monthly", title: "月度", windowNumber: nil, usedPercent: 10, resetAt: nil),
                APIUsageWindow(id: "short", title: "短周期", windowNumber: nil, usedPercent: 55, resetAt: nil)
            ]
        )
        let presentation = QuotaPresentation.connector(source, snapshot: snapshot, now: Date(timeIntervalSince1970: 1_001))
        require(presentation.value == "45%", "multi-window presentation must show the source's lowest remaining percent")
        require(presentation.remainingPercent == 45, "presentation uses the source's lowest window only")
        require(presentation.freshness == .fresh, "available snapshot should be fresh")

        let locked = APIConnectorSnapshot(
            id: id,
            state: .waitingUnlock,
            remainingTokens: "旧值",
            updatedAt: Date(timeIntervalSince1970: 1_000),
            message: "等待解锁凭据保险库；显示上次成功快照",
            usageWindows: snapshot.usageWindows
        )
        require(QuotaPresentation.connector(source, snapshot: locked, now: Date()).freshness == .waitingUnlock, "locked vault must have a neutral waiting state")
        let lockedPresentation = QuotaPresentation.connector(source, snapshot: locked, now: Date(timeIntervalSince1970: 1_001))
        require(lockedPresentation.value == "45%" && lockedPresentation.detail.contains("上次成功"), "locked stale data must stay gray/read-only with last-success evidence")

        // A. A fresh source exposes a display payload.
        require(snapshot.hasDisplayPayload, "available quota values must be recognized as display payload")
        // B. Beginning a refresh copies old values and timestamp into loading.
        var loading = APIConnectorSnapshot(id: id, state: .loading, message: "正在刷新…")
        require(loading.copyDisplayPayload(from: snapshot), "loading snapshot must retain last successful payload")
        require(loading.usageWindows == snapshot.usageWindows && loading.updatedAt == snapshot.updatedAt, "loading must retain windows and original freshness time")
        // C. A lock after loading still obtains its payload from that loading snapshot.
        var waiting = APIConnectorSnapshot(id: id, state: .waitingUnlock, message: "等待解锁凭据保险库；未发起网络请求")
        require(waiting.copyDisplayPayload(from: loading), "waiting state must retain an in-flight loading payload")
        require(waiting.remainingTokens == snapshot.remainingTokens && waiting.updatedAt == snapshot.updatedAt, "lock must not replace old data with lock time")
        // D. A source without a previous payload cannot manufacture stale data.
        var emptyWaiting = APIConnectorSnapshot(id: id, state: .waitingUnlock, message: "等待解锁凭据保险库；未发起网络请求")
        let emptyPrevious = APIConnectorSnapshot(id: id, state: .loading, message: "正在刷新…")
        require(!emptyPrevious.hasDisplayPayload && !emptyWaiting.copyDisplayPayload(from: emptyPrevious), "empty loading data must not be presented as stale success")
        // E. A retained waiting snapshot stays neutral but retains the provider's lowest window value.
        let retainedWaiting = QuotaPresentation.connector(source, snapshot: waiting, now: Date(timeIntervalSince1970: 1_001))
        require(retainedWaiting.freshness == .waitingUnlock && retainedWaiting.value == "45%", "waiting presentation must be neutral while preserving independent quota detail")
        print("PulseDock 6.13 quota presentation self-test passed")
    }
}
