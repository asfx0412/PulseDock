import Foundation
import SwiftUI

struct ClashQuotaSnapshot: Sendable, Equatable {
    enum State: Sendable { case loading, available, unavailable, error }

    var state: State
    var identifier: String = "clash-default"
    var sourceApp: String = "Clash"
    var name: String
    var usedBytes: UInt64
    var totalBytes: UInt64
    var expiresAt: Date?
    var updatedAt: Date?
    var autoUpdateEnabled: Bool
    var updateIntervalMinutes: Int?
    var message: String

    static let loading = ClashQuotaSnapshot(
        state: .loading, identifier: "clash-loading", sourceApp: "Clash", name: "Clash", usedBytes: 0, totalBytes: 0,
        expiresAt: nil, updatedAt: nil, autoUpdateEnabled: false,
        updateIntervalMinutes: nil, message: "正在读取 Clash 订阅"
    )

    var remainingBytes: UInt64 { totalBytes > usedBytes ? totalBytes - usedBytes : 0 }
    var usedPercent: Double { totalBytes > 0 ? Double(usedBytes) / Double(totalBytes) * 100 : 0 }
    var remainingPercent: Double { max(0, 100 - usedPercent) }
    var remainingLabel: String { Self.storage(remainingBytes) }
    var totalLabel: String { Self.storage(totalBytes) }
    var usedLabel: String { Self.storage(usedBytes) }
    var compactLabel: String { state == .available ? Self.storage(remainingBytes, compact: true) : "--" }

    var updateIntervalLabel: String {
        guard autoUpdateEnabled, let minutes = updateIntervalMinutes else { return "自动更新关闭" }
        if minutes == 1_440 { return "每天" }
        if minutes % 1_440 == 0 { return "每 \(minutes / 1_440) 天" }
        if minutes % 60 == 0 { return "每 \(minutes / 60) 小时" }
        return "每 \(minutes) 分钟"
    }

    var nextUpdateAt: Date? {
        guard autoUpdateEnabled, let updatedAt, let updateIntervalMinutes else { return nil }
        return updatedAt.addingTimeInterval(TimeInterval(updateIntervalMinutes * 60))
    }

    private static func storage(_ bytes: UInt64, compact: Bool = false) -> String {
        let gib = Double(bytes) / pow(1024, 3)
        if gib >= 1 {
            if compact { return String(format: "%.0fGiB", gib) }
            if abs(gib.rounded() - gib) < 0.05 { return String(format: "%.0f GiB", gib) }
            return String(format: "%.1f GiB", gib)
        }
        return String(format: compact ? "%.0fMiB" : "%.0f MiB", Double(bytes) / pow(1024, 2))
    }
}

enum PomodoroPhase: String, Sendable {
    case idle, focus, breakTime, longBreak, paused

    var label: String {
        switch self {
        case .idle: "准备专注"
        case .focus: "专注中"
        case .breakTime: "休息中"
        case .longBreak: "长休息"
        case .paused: "已暂停"
        }
    }

    var color: Color {
        switch self {
        case .focus: .red
        case .breakTime, .longBreak: .green
        case .paused: .orange
        case .idle: .secondary
        }
    }
}

enum PomodoroTimeLogic {
    static func remainingSeconds(deadline: Date, now: Date = Date()) -> Int {
        max(0, Int(deadline.timeIntervalSince(now).rounded(.up)))
    }
}

enum WorkStatus: Sendable, Equatable {
    case beforeWork, working, lunch, offWork, overtime, weekendRest, weekendOvertime, holidayRest, holidayWork

    var label: String {
        switch self {
        case .beforeWork: "上班前"
        case .working: "工作中"
        case .lunch: "午休中"
        case .offWork: "已下班"
        case .overtime: "工作日加班"
        case .weekendRest: "周末休息"
        case .weekendOvertime: "周末加班"
        case .holidayRest: "法定节假日"
        case .holidayWork: "节假日工作"
        }
    }

    var symbol: String {
        switch self {
        case .beforeWork: "sunrise.fill"
        case .working: "briefcase.fill"
        case .lunch: "fork.knife"
        case .offWork: "house.fill"
        case .overtime, .weekendOvertime, .holidayWork: "moon.stars.fill"
        case .weekendRest, .holidayRest: "cup.and.saucer.fill"
        }
    }

    var color: Color {
        switch self {
        case .working: .blue
        case .overtime, .weekendOvertime, .holidayWork: .orange
        case .offWork, .weekendRest, .holidayRest, .lunch: .green
        case .beforeWork: .purple
        }
    }
}

enum WorkScheduleLogic {
    static func status(
        date: Date,
        calendar: Calendar = .current,
        startMinutes: Int,
        endMinutes: Int,
        lunchStartMinutes: Int = 12 * 60,
        lunchEndMinutes: Int = 13 * 60,
        workWeekdays: Set<Int> = [2, 3, 4, 5, 6],
        holidayKind: ChinaDayKind = .normal,
        manualDayOverride: Int = 0,
        overtimeActive: Bool
    ) -> WorkStatus {
        let minute = calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
        let crossMidnight = endMinutes <= startMinutes
        var effectiveDate = date
        if crossMidnight, minute < endMinutes {
            effectiveDate = calendar.date(byAdding: .day, value: -1, to: date) ?? date
        }
        let effectiveWeekday = calendar.component(.weekday, from: effectiveDate)
        let scheduledWorkday = workWeekdays.contains(effectiveWeekday)
        let officialWorkday = holidayKind == .makeupWorkday
        let officialHoliday = holidayKind == .holiday
        let isWorkday = manualDayOverride == 1 || (manualDayOverride == 0 && (officialWorkday || (scheduledWorkday && !officialHoliday)))

        if !isWorkday {
            if overtimeActive { return officialHoliday ? .holidayWork : .weekendOvertime }
            return officialHoliday ? .holidayRest : .weekendRest
        }

        let insideShift = crossMidnight ? (minute >= startMinutes || minute < endMinutes) : (minute >= startMinutes && minute < endMinutes)
        if insideShift {
            let insideLunch = lunchStartMinutes < lunchEndMinutes && minute >= lunchStartMinutes && minute < lunchEndMinutes
            return insideLunch ? .lunch : .working
        }
        if !crossMidnight, minute < startMinutes { return .beforeWork }
        return overtimeActive ? .overtime : .offWork
    }

    static func timeLabel(_ minutes: Int) -> String {
        String(format: "%02d:%02d", max(0, min(1_439, minutes)) / 60, max(0, min(1_439, minutes)) % 60)
    }
}

enum ChinaDayKind: String, Sendable, Equatable { case normal, holiday, makeupWorkday }

/// One holiday period exactly as published by the State Council notice.  A
/// makeup workday is related to a holiday period, but PulseDock deliberately
/// does not invent a one-to-one "swapped with" date when the notice does not
/// publish one.
struct ChinaHolidayPeriod: Sendable, Equatable, Identifiable {
    var id: String
    var name: String
    var holidayDateKeys: [String]
    var makeupWorkdayKeys: [String]

    var startDateKey: String { holidayDateKeys.first ?? "" }
    var endDateKey: String { holidayDateKeys.last ?? "" }
    var dayCount: Int { holidayDateKeys.count }
}

/// An auditable annual data set.  Adding a new year requires a source notice,
/// its publication date and document number rather than copying last year's
/// dates forward.
struct ChinaHolidayYearSchedule: Sendable, Equatable, Identifiable {
    var id: Int { year }
    var year: Int
    var title: String
    var noticeNumber: String
    var issuingAuthority: String
    var publishedDateKey: String
    var sourceURL: URL
    var periods: [ChinaHolidayPeriod]

    func period(containing dateKey: String) -> ChinaHolidayPeriod? {
        periods.first { $0.holidayDateKeys.contains(dateKey) || $0.makeupWorkdayKeys.contains(dateKey) }
    }
}

struct ChinaHolidayDayInfo: Sendable, Equatable {
    var kind: ChinaDayKind
    var name: String?
    var period: ChinaHolidayPeriod?
    var isWeekend: Bool
    var scheduleYear: Int
    var hasOfficialSchedule: Bool

    var conciseLabel: String {
        switch kind {
        case .holiday: name ?? "法定休假"
        case .makeupWorkday: "调休上班"
        case .normal: isWeekend ? "周末" : "工作日"
        }
    }
}

struct ChinaHolidayUpcomingEvent: Sendable, Equatable, Identifiable {
    var id: String
    var date: Date
    var kind: ChinaDayKind
    var title: String
    var detail: String
}

struct ChinaHolidayCalendar {
    /// Source: State Council General Office, Notice of 2026 Holiday
    /// Arrangements, 国办发明电〔2025〕7号, published 2025-11-04.
    /// https://www.gov.cn/zhengce/zhengceku/202511/content_7047091.htm
    private static let schedule2026 = ChinaHolidayYearSchedule(
        year: 2026,
        title: "国务院办公厅关于2026年部分节假日安排的通知",
        noticeNumber: "国办发明电〔2025〕7号",
        issuingAuthority: "国务院办公厅",
        publishedDateKey: "2025-11-04",
        sourceURL: URL(string: "https://www.gov.cn/zhengce/zhengceku/202511/content_7047091.htm")!,
        periods: [
            ChinaHolidayPeriod(id: "2026-new-year", name: "元旦", holidayDateKeys: ["2026-01-01", "2026-01-02", "2026-01-03"], makeupWorkdayKeys: ["2026-01-04"]),
            ChinaHolidayPeriod(id: "2026-spring-festival", name: "春节", holidayDateKeys: (15...23).map { String(format: "2026-02-%02d", $0) }, makeupWorkdayKeys: ["2026-02-14", "2026-02-28"]),
            ChinaHolidayPeriod(id: "2026-qingming", name: "清明节", holidayDateKeys: ["2026-04-04", "2026-04-05", "2026-04-06"], makeupWorkdayKeys: []),
            ChinaHolidayPeriod(id: "2026-labor-day", name: "劳动节", holidayDateKeys: (1...5).map { String(format: "2026-05-%02d", $0) }, makeupWorkdayKeys: ["2026-05-09"]),
            ChinaHolidayPeriod(id: "2026-dragon-boat", name: "端午节", holidayDateKeys: ["2026-06-19", "2026-06-20", "2026-06-21"], makeupWorkdayKeys: []),
            ChinaHolidayPeriod(id: "2026-mid-autumn", name: "中秋节", holidayDateKeys: ["2026-09-25", "2026-09-26", "2026-09-27"], makeupWorkdayKeys: []),
            ChinaHolidayPeriod(id: "2026-national-day", name: "国庆节", holidayDateKeys: (1...7).map { String(format: "2026-10-%02d", $0) }, makeupWorkdayKeys: ["2026-09-20", "2026-10-10"])
        ]
    )

    private static let schedules: [Int: ChinaHolidayYearSchedule] = [2026: schedule2026]

    static func schedule(forYear year: Int) -> ChinaHolidayYearSchedule? { schedules[year] }

    static func dayInfo(for date: Date, calendar: Calendar = .current) -> ChinaHolidayDayInfo {
        let key = dateKey(date, calendar: calendar)
        let year = calendar.component(.year, from: date)
        let schedule = schedule(forYear: year)
        let period = schedule?.period(containing: key)
        let weekday = calendar.component(.weekday, from: date)
        let isWeekend = weekday == 1 || weekday == 7
        if let period, period.holidayDateKeys.contains(key) {
            return ChinaHolidayDayInfo(kind: .holiday, name: period.name, period: period, isWeekend: isWeekend, scheduleYear: year, hasOfficialSchedule: true)
        }
        if let period, period.makeupWorkdayKeys.contains(key) {
            return ChinaHolidayDayInfo(kind: .makeupWorkday, name: period.name, period: period, isWeekend: isWeekend, scheduleYear: year, hasOfficialSchedule: true)
        }
        return ChinaHolidayDayInfo(kind: .normal, name: nil, period: nil, isWeekend: isWeekend, scheduleYear: year, hasOfficialSchedule: schedule != nil)
    }

    static func upcomingEvents(
        after date: Date,
        limit: Int = 3,
        calendar: Calendar = .current
    ) -> [ChinaHolidayUpcomingEvent] {
        guard limit > 0 else { return [] }
        let start = calendar.startOfDay(for: date)
        let currentYear = calendar.component(.year, from: start)
        let availableSchedules = [schedule(forYear: currentYear), schedule(forYear: currentYear + 1)].compactMap { $0 }
        var events: [ChinaHolidayUpcomingEvent] = []
        for schedule in availableSchedules {
            for period in schedule.periods {
                if let holidayStart = Self.date(fromDateKey: period.startDateKey, calendar: calendar), holidayStart >= start {
                    events.append(ChinaHolidayUpcomingEvent(
                        id: "holiday-\(period.id)", date: holidayStart, kind: .holiday, title: period.name,
                        detail: "\(period.startDateKey) 至 \(period.endDateKey) · \(period.dayCount) 天"
                    ))
                }
                for key in period.makeupWorkdayKeys {
                    if let workday = Self.date(fromDateKey: key, calendar: calendar), workday >= start {
                        events.append(ChinaHolidayUpcomingEvent(
                            id: "makeup-\(period.id)-\(key)", date: workday, kind: .makeupWorkday,
                            title: "\(period.name)调休上班", detail: key
                        ))
                    }
                }
            }
        }
        return Array(events.sorted { $0.date < $1.date }.prefix(limit))
    }

    static func dateKey(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    static func date(fromDateKey key: String, calendar: Calendar = .current) -> Date? {
        let values = key.split(separator: "-").compactMap { Int($0) }
        guard values.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: values[0], month: values[1], day: values[2]))
    }
}

struct ActiveApplicationSnapshot: Sendable, Equatable {
    var name = ""
    var bundleIdentifier = ""
    var idleSeconds = 0.0
    var isTrackable = false
    var isEngaged = false
    var label: String {
        guard !name.isEmpty else { return "未识别前台应用" }
        return "\(name) · \(isEngaged ? "使用中" : "空闲")"
    }
}

struct AppActivityEntry: Codable, Sendable, Equatable, Identifiable {
    var bundleIdentifier: String
    var name: String
    var foregroundSeconds: Int
    var engagedSeconds: Int

    var id: String { bundleIdentifier }
}

struct AppActivityRanking: Sendable, Equatable, Identifiable {
    var bundleIdentifier: String
    var name: String
    var foregroundSeconds: Int
    var engagedSeconds: Int
    var share: Double

    var id: String { bundleIdentifier }
    var durationLabel: String { ActivityFormat.duration(engagedSeconds) }
    var foregroundLabel: String { ActivityFormat.duration(foregroundSeconds) }
    var shareLabel: String { String(format: "%.0f%%", share * 100) }
}

enum ActivityFormat {
    static func duration(_ seconds: Int) -> String {
        let safe = max(0, seconds)
        if safe >= 3_600 {
            let hours = safe / 3_600
            let minutes = (safe % 3_600) / 60
            return minutes > 0 ? "\(hours)小时\(minutes)分" : "\(hours)小时"
        }
        if safe >= 60 { return "\(safe / 60)分" }
        return "\(safe)秒"
    }
}
