import Foundation

@main
enum Version6SelfTest {
    static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
            exit(1)
        }
    }

    static func main() throws {
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("PulseDock-Version6SelfTest-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }
        let ledgerURL = temporaryRoot.appendingPathComponent("events.json")
        let ledger = EventLedger(fileURL: ledgerURL)
        let started = Date().addingTimeInterval(-125)

        ledger.beginOrUpdate(
            key: "network.external",
            category: .network,
            severity: .warning,
            title: "AI 网络异常",
            evidence: "TLS 握手失败",
            source: "本地诊断",
            at: started
        )
        ledger.beginOrUpdate(
            key: "network.external",
            category: .network,
            severity: .critical,
            title: "AI 网络异常",
            evidence: "连续两次 TLS 失败",
            source: "本地诊断",
            at: started.addingTimeInterval(10)
        )
        require(ledger.events.count == 1, "同一活跃事件应更新而不是重复添加")
        require(ledger.events[0].severity == .critical, "事件严重性应可升级")

        ledger.recover(key: "network.external", evidence: "POST 204", at: started.addingTimeInterval(125))
        require(ledger.events[0].recoveredAt != nil, "恢复时间应被记录")
        require(ledger.events[0].evidence.contains("恢复：POST 204"), "恢复证据应使用真实参数")
        require(ledger.events[0].durationLabel == "2 分钟", "持续时间应正确格式化")

        let reloaded = EventLedger(fileURL: ledgerURL)
        require(reloaded.events == ledger.events, "事件账本应原子持久化并可重载")

        let process = RemoteGPUProcess(pid: 42, name: "python", memoryMiB: 1024, gpuIndices: [0])
        require(process.id == 42, "GPU 进程标识应使用真实 PID")

        let remote = RemoteDeviceConfiguration(name: "G1-002", sshAlias: "g1-002")
        let connector = APIConnectorConfiguration(name: "Example", endpoint: "https://api.example.com/v1/models")
        let bundle = PulseDockConfigurationBundle(
            focusMinutes: 25,
            breakMinutes: 5,
            longBreakMinutes: 20,
            sessionsBeforeLongBreak: 4,
            workStartMinutes: 540,
            workEndMinutes: 1_080,
            lunchStartMinutes: 720,
            lunchEndMinutes: 780,
            workWeekdays: [2, 3, 4, 5, 6],
            idleThresholdSeconds: 120,
            remoteDevices: [remote],
            apiConnectors: [connector],
            clashControllerEnabled: true,
            clashControllerURL: "127.0.0.1:9090",
            alertCooldownMinutes: 30
        )
        let encoded = try JSONEncoder().encode(bundle)
        let decoded = try JSONDecoder().decode(PulseDockConfigurationBundle.self, from: encoded)
        require(decoded.remoteDevices == [remote], "SSH 设备定义应可导出/导入")
        require(decoded.apiConnectors == [connector], "API 连接器定义应可导出/导入")
        let exportedJSON = String(decoding: encoded, as: UTF8.self)
        require(!exportedJSON.contains("feishuWebhook"), "配置载荷不得包含飞书 Webhook 字段")
        require(!exportedJSON.contains("apiKey"), "配置载荷不得包含 API Key 字段")
        require(!exportedJSON.contains("clashControllerSecret"), "配置载荷不得包含 Clash Secret 字段")

        print("PulseDock 6.0 self-test passed")
    }
}
