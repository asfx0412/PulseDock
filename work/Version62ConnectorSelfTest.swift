import Foundation

@main
enum Version62ConnectorSelfTest {
    static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8)); exit(1) }
    }

    static func main() async {
        require(APIConnectorKind.glmCodingPlan.defaultEndpoint == "https://open.bigmodel.cn/api/monitor/usage/quota/limit", "GLM 必须使用只读用量端点")
        require(APIConnectorKind.deepSeekBalance.defaultEndpoint == "https://api.deepseek.com/user/balance", "DeepSeek 必须使用官方余额端点")
        require(!APIConnectorKind.cursorLocalUsage.requiresAPIKey, "Cursor 本地会话不得要求或保存 API Key")
        let service = APIConnectorService()
        let glm = APIConnectorConfiguration(name: "GLM", kind: .glmCodingPlan, endpoint: APIConnectorKind.glmCodingPlan.defaultEndpoint)
        let snapshot = await service.probe(glm, apiKey: "")
        require(snapshot.state == .unavailable && snapshot.message.contains("API Key"), "GLM 空 Key 不得发起请求")
        let deepSeek = APIConnectorConfiguration(name: "DeepSeek", kind: .deepSeekBalance, endpoint: APIConnectorKind.deepSeekBalance.defaultEndpoint)
        let deepSeekSnapshot = await service.probe(deepSeek, apiKey: "")
        require(deepSeekSnapshot.state == .unavailable && deepSeekSnapshot.message.contains("API Key"), "DeepSeek 空 Key 不得发起请求")
        let unsafe = APIConnectorConfiguration(name: "Unsafe", endpoint: "http://example.test")
        let unsafeSnapshot = await service.probe(unsafe, apiKey: "")
        require(unsafeSnapshot.state == .error, "通用连接器必须拒绝非 HTTPS")
        let fixture = Data(#"{"data":{"limits":[{"type":"TIME_LIMIT","percentage":1},{"type":"TOKENS_LIMIT","name":"5 小时额度","percentage":6},{"type":"TOKENS_LIMIT","percentage":165}]}}"#.utf8)
        let decoded = APIConnectorService.decodeGLMCodingPlan(id: glm.id, data: fixture)
        require(decoded.state == .available && decoded.usageWindows.count == 3, "GLM 多周期数据必须拆分为结构化窗口")
        require(decoded.usageWindows[0].title == "月度 / MCP" && decoded.usageWindows[0].windowNumber == nil, "单一类型不应显示冗余编号")
        require(decoded.usageWindows[1].title == "5 小时额度" && decoded.usageWindows[1].windowNumber == 1, "上游窗口名称应优先于默认文案")
        require(decoded.usageWindows[2].windowNumber == 2 && decoded.usageWindows[2].usedPercent == 100, "重复窗口编号应独立且百分比必须夹紧")
        let evolved = Data(#"{"success":true,"data":{"quotaLimits":[{"quotaType":"TOKENS_LIMIT","display_name":"滚动窗口","currentValue":"25","maxValue":"100","nextResetTime":1787400000},{"quotaType":"TIME_LIMIT","remainingPercent":"80"}]}}"#.utf8)
        let evolvedSnapshot = APIConnectorService.decodeGLMCodingPlan(id: glm.id, data: evolved)
        require(evolvedSnapshot.usageWindows.map(\.usedPercent) == [25, 20], "GLM decoder must accept evolved numeric strings and remaining percentages")
        let html = APIConnectorService.decodeGLMCodingPlan(id: glm.id, data: Data("<html>gateway</html>".utf8))
        require(html.state == .unavailable && html.message.contains("HTML"), "GLM HTML proxy pages need an explicit diagnosis")
        let businessError = APIConnectorService.decodeGLMCodingPlan(id: glm.id, data: Data(#"{"success":false,"msg":"too many requests"}"#.utf8))
        require(businessError.message.contains("too many requests"), "GLM business errors must retain a bounded reason")
        print("PulseDock 6.6 connector self-test passed")
    }
}
