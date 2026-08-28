import Foundation

@main
struct DiagnosticSelfTest {
    static func main() async {
        let report = await AINetworkDiagnosticService().diagnose()
        print("DIAGNOSTIC_RESULT=\(report.health.rawValue) · \(report.summary)")
        for check in report.checks { print("\(check.id)=\(check.state.rawValue) · \(check.detail)") }
        guard !report.checks.isEmpty, report.completedAt != nil else { exit(1) }
        print("DIAGNOSTIC_SELF_TEST_PASS")
    }
}
