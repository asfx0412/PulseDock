import Foundation

@main
struct SelfTest {
    static func main() async {
        var failures: [String] = []
        func check(_ condition: @autoclosure () -> Bool, _ message: String) {
            if !condition() { failures.append(message) }
        }

        check(DisplayFormat.speed(1_500_000) == "1.5 MB/s", "网速格式化")
        var identity = IPIdentity()
        identity.countryCode = "CN"
        check(identity.isMainlandChina, "中国大陆 IP 分类")
        identity.countryCode = "US"
        check(identity.scopeLabel == "境外出口", "境外 IP 分类")

        let clash = ClashQuotaService.parse(url: ClashQuotaService.profilesURL)
        check(clash.state == .available, "Clash 订阅流量读取")
        check(clash.totalBytes >= clash.usedBytes, "Clash 剩余流量计算")
        check(clash.remainingPercent >= 0 && clash.remainingPercent <= 100, "Clash 流量百分比范围")
        check(clash.name == "良心云", "Clash 订阅名称")

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 8 * 3_600)!
        let weekdayMorning = calendar.date(from: DateComponents(year: 2026, month: 8, day: 7, hour: 10))!
        let weekend = calendar.date(from: DateComponents(year: 2026, month: 8, day: 8, hour: 10))!
        check(WorkScheduleLogic.status(date: weekdayMorning, calendar: calendar, startMinutes: 540, endMinutes: 1080, overtimeActive: false) == .working, "工作日状态")
        check(WorkScheduleLogic.status(date: weekend, calendar: calendar, startMinutes: 540, endMinutes: 1080, overtimeActive: false) == .weekendRest, "周末休息状态")
        check(WorkScheduleLogic.status(date: weekend, calendar: calendar, startMinutes: 540, endMinutes: 1080, overtimeActive: true) == .weekendOvertime, "周末加班状态")
        let lunch = calendar.date(from: DateComponents(year: 2026, month: 8, day: 7, hour: 12, minute: 30))!
        check(WorkScheduleLogic.status(date: lunch, calendar: calendar, startMinutes: 540, endMinutes: 1080, lunchStartMinutes: 720, lunchEndMinutes: 780, overtimeActive: false) == .lunch, "午休状态")
        let holiday = calendar.date(from: DateComponents(year: 2026, month: 10, day: 2, hour: 10))!
        check(ChinaHolidayCalendar.dayInfo(for: holiday, calendar: calendar).kind == .holiday, "中国法定节假日")
        check(WorkScheduleLogic.status(date: holiday, calendar: calendar, startMinutes: 540, endMinutes: 1080, holidayKind: .holiday, overtimeActive: false) == .holidayRest, "法定节假日休息")
        let overnight = calendar.date(from: DateComponents(year: 2026, month: 8, day: 8, hour: 1))!
        check(WorkScheduleLogic.status(date: overnight, calendar: calendar, startMinutes: 22 * 60, endMinutes: 2 * 60, workWeekdays: [2,3,4,5,6], overtimeActive: false) == .working, "跨午夜班次")
        let deadline = Date(timeIntervalSince1970: 1_000)
        check(PomodoroTimeLogic.remainingSeconds(deadline: deadline, now: Date(timeIntervalSince1970: 940)) == 60, "番茄钟绝对截止时间")
        check(PomodoroTimeLogic.remainingSeconds(deadline: deadline, now: Date(timeIntervalSince1970: 1_100)) == 0, "睡眠后计时校正")

        let cpu = CPUReader()
        _ = cpu.read()
        try? await Task.sleep(for: .milliseconds(250))
        let cpuValue = cpu.read()
        check((0...100).contains(cpuValue), "CPU 取值范围")

        let memory = MemoryReader.readPercent()
        check((0...100).contains(memory), "内存取值范围")
        let gpu = GPUReader.readPercent()
        check((0...100).contains(gpu), "GPU 取值范围")

        let traffic = NetworkTrafficReader()
        _ = traffic.read()
        try? await Task.sleep(for: .milliseconds(100))
        let speed = traffic.read()
        check(speed.download >= 0 && speed.upload >= 0, "网络流量取值范围")

        let temperatureReader = HardwareTemperatureReader()
        let dieTemperature = temperatureReader.readDieTemperature()
        let batteryTemperature = PowerReader.batteryTemperature()
        if let value = dieTemperature ?? batteryTemperature {
            check((10...115).contains(value), "温度取值范围")
        } else {
            failures.append("没有可用温度传感器")
        }

        if ProcessInfo.processInfo.environment["PULSEDOCK_SKIP_NETWORK_TESTS"] != "1" {
            let probe = NetworkProbe()
            let latency = await probe.latency()
            check(latency.0 != nil, "HTTPS 延迟探测：\(latency.1 ?? "未知错误")")
            do {
                let ip = try await probe.lookupIP()
                check(ip.address.contains("." ) || ip.address.contains(":"), "公网 IP 格式")
                check(!ip.countryCode.isEmpty, "公网 IP 国家定位")
                print("出口 IP: \(ip.address) · \(ip.locationLine) · \(ip.isp)")
            } catch {
                failures.append("公网 IP 查询：\(error.localizedDescription)")
            }
        } else {
            print("网络自测：受执行环境限制，已跳过")
        }

        print(String(format: "CPU %.1f%% · GPU %.1f%% · 内存 %.1f%% · 芯片温度 %@ · 电池温度 %@",
                     cpuValue, gpu, memory,
                     dieTemperature.map { String(format: "%.1f°C", $0) } ?? "不可用",
                     batteryTemperature.map { String(format: "%.1f°C", $0) } ?? "不可用"))
        if dieTemperature == nil { print("PMU 传感器: \(temperatureReader.availableSensorNames.joined(separator: ", "))") }
        print("Clash: \(clash.name) · 剩余 \(clash.remainingLabel) / \(clash.totalLabel) · \(clash.updateIntervalLabel)")

        if failures.isEmpty {
            print("SELF_TEST_PASS")
        } else {
            for failure in failures { print("FAIL: \(failure)") }
            exit(1)
        }
    }
}
