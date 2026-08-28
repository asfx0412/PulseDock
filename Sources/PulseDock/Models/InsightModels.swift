import Foundation

struct CodexUsageChartPoint: Sendable, Equatable, Identifiable {
    var id: Date { date }
    var date: Date
    var tokens: Int64
}

enum CodexUsageChartData {
    static func points(
        from buckets: [CodexDailyUsageBucket],
        calendar: Calendar = .current
    ) -> [CodexUsageChartPoint] {
        buckets.compactMap { bucket in
            ChinaHolidayCalendar.date(fromDateKey: bucket.startDate, calendar: calendar).map {
                CodexUsageChartPoint(date: $0, tokens: bucket.tokens)
            }
        }
        .sorted { $0.date < $1.date }
    }

    /// Returns a stable, sparse set of real dates.  Charts will not attempt to
    /// render every source label when the panel is narrow.
    static func sparseTickDates(
        for points: [CodexUsageChartPoint],
        maximumCount: Int = 4
    ) -> [Date] {
        guard !points.isEmpty, maximumCount > 0 else { return [] }
        if points.count <= maximumCount { return points.map(\.date) }
        if maximumCount == 1 { return [points[points.count / 2].date] }
        let lastIndex = points.count - 1
        var dates: [Date] = []
        for position in 0..<maximumCount {
            let index = Int((Double(position) * Double(lastIndex) / Double(maximumCount - 1)).rounded())
            let date = points[index].date
            if dates.last != date { dates.append(date) }
        }
        return dates
    }

    static func nearestPoint(
        to date: Date?,
        in points: [CodexUsageChartPoint]
    ) -> CodexUsageChartPoint? {
        guard let date else { return nil }
        return points.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
    }
}
