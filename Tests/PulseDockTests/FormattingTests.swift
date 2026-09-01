import XCTest
@testable import PulseDock

final class FormattingTests: XCTestCase {
    func testSpeedFormatting() {
        XCTAssertEqual(DisplayFormat.speed(0), "0 KB/s")
        XCTAssertEqual(DisplayFormat.speed(1_500), "2 KB/s")
        XCTAssertEqual(DisplayFormat.speed(1_500_000), "1.5 MB/s")
        XCTAssertEqual(DisplayFormat.speed(1_500_000_000), "1.5 GB/s")
    }

    func testIPScope() {
        var identity = IPIdentity()
        identity.countryCode = "CN"
        XCTAssertTrue(identity.isMainlandChina)
        XCTAssertEqual(identity.scopeLabel, "中国大陆")
        identity.countryCode = "US"
        identity.country = "United States"
        identity.city = "Los Angeles"
        identity.address = "2001:49f0:d0b3:ff00::3"
        XCTAssertFalse(identity.isMainlandChina)
        XCTAssertEqual(identity.scopeLabel, "境外出口")
        XCTAssertEqual(identity.locationHeadline, "美国 · Los Angeles")
        XCTAssertEqual(identity.addressFamilyLabel, "IPv6")
    }

    func testActivityFormatting() {
        XCTAssertEqual(ActivityFormat.duration(59), "59秒")
        XCTAssertEqual(ActivityFormat.duration(125), "2分")
        XCTAssertEqual(ActivityFormat.duration(3_900), "1小时5分")
    }

    func testWeatherPresentation() {
        XCTAssertEqual(WeatherPresentation.condition(code: 0), "晴")
        XCTAssertEqual(WeatherPresentation.condition(code: 95), "雷雨")
        XCTAssertEqual(WeatherPresentation.moonPhase(0.5), "满月")
        XCTAssertEqual(WeatherPresentation.symbol(code: 0, isDay: false, moonPhase: 0.5), "moon.stars.fill")
    }

    func testOfficialHolidayScheduleIsAuditable() {
        let schedule = ChinaHolidayCalendar.schedule(forYear: 2026)
        XCTAssertEqual(schedule?.noticeNumber, "国办发明电〔2025〕7号")
        XCTAssertEqual(schedule?.publishedDateKey, "2025-11-04")
        XCTAssertEqual(schedule?.periods.count, 7)
        XCTAssertNil(ChinaHolidayCalendar.schedule(forYear: 2027))
    }
}
