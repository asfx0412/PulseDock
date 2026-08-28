import Foundation
import Darwin
import IOKit
import IOKit.ps

final class CPUReader: @unchecked Sendable {
    private var previous: (user: UInt64, system: UInt64, idle: UInt64, nice: UInt64)?

    func read() -> Double {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        let ticks = info.cpu_ticks
        let current = (UInt64(ticks.0), UInt64(ticks.1), UInt64(ticks.2), UInt64(ticks.3))
        defer { previous = current }
        guard let old = previous else { return 0 }
        let user = current.0 &- old.user
        let system = current.1 &- old.system
        let idle = current.2 &- old.idle
        let nice = current.3 &- old.nice
        let total = user + system + idle + nice
        guard total > 0 else { return 0 }
        return Double(user + system + nice) / Double(total) * 100
    }
}

enum MemoryReader {
    static func readPercent() -> Double {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        var pageSize: vm_size_t = 0
        guard host_page_size(mach_host_self(), &pageSize) == KERN_SUCCESS else { return 0 }
        let page = Double(pageSize)
        let usedPages = Double(stats.active_count + stats.wire_count + stats.compressor_page_count)
        let total = Double(ProcessInfo.processInfo.physicalMemory)
        return total > 0 ? min(100, usedPages * page / total * 100) : 0
    }
}

enum GPUReader {
    static func readPercent() -> Double {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AGXAccelerator"))
        guard service != 0 else { return 0 }
        defer { IOObjectRelease(service) }
        guard let property = IORegistryEntryCreateCFProperty(service, "PerformanceStatistics" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue(),
              let statistics = property as? [String: Any],
              let utilization = statistics["Device Utilization %"] as? NSNumber else { return 0 }
        return max(0, min(100, utilization.doubleValue))
    }
}

final class NetworkTrafficReader: @unchecked Sendable {
    private var previousBytes: (down: UInt64, up: UInt64)?
    private var previousTime: Date?

    func read() -> (download: Double, upload: Double) {
        var pointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&pointer) == 0, let first = pointer else { return (0, 0) }
        defer { freeifaddrs(pointer) }

        var down: UInt64 = 0
        var up: UInt64 = 0
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let item = cursor {
            let interface = item.pointee
            let name = String(cString: interface.ifa_name)
            if name != "lo0", interface.ifa_addr?.pointee.sa_family == UInt8(AF_LINK), let data = interface.ifa_data {
                let values = data.assumingMemoryBound(to: if_data.self).pointee
                down &+= UInt64(values.ifi_ibytes)
                up &+= UInt64(values.ifi_obytes)
            }
            cursor = interface.ifa_next
        }

        let now = Date()
        defer { previousBytes = (down, up); previousTime = now }
        guard let old = previousBytes, let oldTime = previousTime else { return (0, 0) }
        let interval = now.timeIntervalSince(oldTime)
        guard interval > 0, down >= old.down, up >= old.up else { return (0, 0) }
        return (Double(down - old.down) / interval, Double(up - old.up) / interval)
    }
}

enum PowerReader {
    static func batteryPercent() -> Double? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef],
              let source = list.first,
              let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
              let current = description[kIOPSCurrentCapacityKey] as? Double,
              let maximum = description[kIOPSMaxCapacityKey] as? Double,
              maximum > 0 else { return nil }
        return current / maximum * 100
    }

    static func batteryTemperature() -> Double? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        guard let property = IORegistryEntryCreateCFProperty(service, "Temperature" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue(),
              let number = property as? NSNumber else { return nil }
        let celsius = number.doubleValue / 100.0
        return (0...100).contains(celsius) ? celsius : nil
    }

    static var thermalLabel: String {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: "正常"
        case .fair: "偏热"
        case .serious: "较热"
        case .critical: "过热"
        @unknown default: "未知"
        }
    }
}

@_silgen_name("PDReadChipTemperature")
private func PDReadChipTemperature() -> Double

final class HardwareTemperatureReader: @unchecked Sendable {
    private(set) var availableSensorNames: [String] = ["Apple PMU/SMC"]

    func readDieTemperature() -> Double? {
        let value = PDReadChipTemperature()
        return (10...115).contains(value) ? value : nil
    }
}
