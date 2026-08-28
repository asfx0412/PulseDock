import Foundation

@main
struct CursorLiveSmokeTest {
    static func main() async {
        let snapshot = await CursorUsageService().readCurrentPeriodUsage(id: UUID())
        let hasSummary = snapshot.summary != "--"
        print("cursor_state=\(snapshot.state) has_summary=\(hasSummary) has_reset=\(snapshot.resetAt != nil)")
        if snapshot.state == .error { exit(1) }
    }
}
