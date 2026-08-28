import Foundation

@main
enum Version68InsightSelfTest {
    static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
            exit(1)
        }
    }

    static func main() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!

        let schedule = ChinaHolidayCalendar.schedule(forYear: 2026)
        require(schedule?.noticeNumber == "国办发明电〔2025〕7号", "official notice must be auditable")
        require(schedule?.publishedDateKey == "2025-11-04", "official publication date")
        require(schedule?.periods.count == 7, "all seven national holiday periods")
        require(schedule?.periods.first(where: { $0.name == "春节" })?.dayCount == 9, "Spring Festival day count")
        require(schedule?.periods.first(where: { $0.name == "国庆节" })?.makeupWorkdayKeys == ["2026-09-20", "2026-10-10"], "National Day makeup relationship")

        let holiday = ChinaHolidayCalendar.date(fromDateKey: "2026-10-02", calendar: calendar)!
        let makeup = ChinaHolidayCalendar.date(fromDateKey: "2026-10-10", calendar: calendar)!
        let weekend = ChinaHolidayCalendar.date(fromDateKey: "2026-08-30", calendar: calendar)!
        require(ChinaHolidayCalendar.dayInfo(for: holiday, calendar: calendar).conciseLabel == "国庆节", "holiday day presentation")
        require(ChinaHolidayCalendar.dayInfo(for: makeup, calendar: calendar).kind == .makeupWorkday, "makeup day classification")
        require(ChinaHolidayCalendar.dayInfo(for: weekend, calendar: calendar).conciseLabel == "周末", "ordinary weekend classification")

        let unknown = ChinaHolidayCalendar.date(fromDateKey: "2027-01-01", calendar: calendar)!
        require(!ChinaHolidayCalendar.dayInfo(for: unknown, calendar: calendar).hasOfficialSchedule, "unknown year must not be guessed")

        let today = ChinaHolidayCalendar.date(fromDateKey: "2026-08-25", calendar: calendar)!
        let events = ChinaHolidayCalendar.upcomingEvents(after: today, limit: 3, calendar: calendar)
        require(events.map(\.title) == ["国庆节调休上班", "中秋节", "国庆节"], "next three holiday and makeup events")

        let buckets = (1...14).map {
            CodexDailyUsageBucket(startDate: String(format: "2026-08-%02d", $0), tokens: Int64($0 * 100))
        } + [CodexDailyUsageBucket(startDate: "not-a-date", tokens: 1)]
        let points = CodexUsageChartData.points(from: buckets, calendar: calendar)
        require(points.count == 14, "invalid chart dates must be discarded")
        let ticks = CodexUsageChartData.sparseTickDates(for: points, maximumCount: 4)
        require(ticks.count == 4 && ticks.first == points.first?.date && ticks.last == points.last?.date, "chart uses four sparse real-date ticks")
        let selected = calendar.date(byAdding: .hour, value: 8, to: points[6].date)!
        require(CodexUsageChartData.nearestPoint(to: selected, in: points)?.tokens == 700, "chart selection returns full point value")

        print("PulseDock 6.8 insight and holiday self-test passed")
    }
}
