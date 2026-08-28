import Foundation

@main
struct QuotaSelfTest {
    static func main() async {
        let snapshot = await CodexQuotaService().read()
        guard snapshot.state == .available,
              let remaining = snapshot.remainingPercent,
              (0...100).contains(remaining),
              let reset = snapshot.resetsAt,
              let window = snapshot.windowMinutes,
              window > 0 else {
            print("QUOTA_TEST_FAIL: \(snapshot.message)")
            exit(1)
        }
        print("Codex 剩余 \(snapshot.remainingLabel) · \(snapshot.windowLabel ?? "未知窗口") · 刷新 \(reset.formatted(date: .abbreviated, time: .shortened))")
        print("QUOTA_TEST_PASS")
    }
}
