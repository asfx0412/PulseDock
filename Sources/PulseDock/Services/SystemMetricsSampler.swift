import Foundation

/// A complete, immutable metrics update. Expensive IOKit and interface scans
/// are collected away from the main actor; MonitorStore only publishes this
/// snapshot after the collection has completed.
struct SystemMetricsSnapshot: Sendable, Equatable {
    var cpuUsage: Double
    var memoryUsage: Double
    var gpuUsage: Double
    var downloadSpeed: Double
    var uploadSpeed: Double
    var temperature: Double?
    var temperatureSource: String
    var thermalState: String
    var batteryPercent: Double?
    var proxyActive: Bool
    var sampledAt: Date
    var collectionDurationMilliseconds: Double

    /// Kept internal for the deterministic concurrency regression test. It is
    /// also useful when copying a future responsiveness diagnostic, but does
    /// not contain user or application data.
    var collectionRanOnMainThread: Bool
}

struct SystemMetricsCoreSample: Sendable, Equatable {
    var cpuUsage: Double
    var memoryUsage: Double
    var gpuUsage: Double
    var downloadSpeed: Double
    var uploadSpeed: Double
    var thermalState: String
    var batteryPercent: Double?
    var proxyActive: Bool
}

struct TemperatureMetricSample: Sendable, Equatable {
    var value: Double?
    var source: String
}

/// Small value type separated from the sampler so throttling can be verified
/// without reading real hardware in unit tests.
struct PeriodicSamplingPolicy: Sendable {
    let interval: TimeInterval
    private(set) var lastSampleAt: Date?

    init(interval: TimeInterval) {
        self.interval = max(0, interval)
    }

    mutating func consumeIfDue(at date: Date) -> Bool {
        guard let lastSampleAt else {
            self.lastSampleAt = date
            return true
        }
        guard date.timeIntervalSince(lastSampleAt) >= interval else { return false }
        self.lastSampleAt = date
        return true
    }
}

/// A dedicated serial utility queue prevents both main-thread hardware scans
/// and overlapping access to the stateful CPU/network delta readers. A custom
/// queue is intentional here: actor isolation provides serialization, but does
/// not itself promise a particular OS thread.
final class SystemMetricsSampler: @unchecked Sendable {
    typealias CoreReader = @Sendable () -> SystemMetricsCoreSample
    typealias TemperatureReader = @Sendable () -> TemperatureMetricSample

    private let readCore: CoreReader
    private let readTemperature: TemperatureReader
    private let queue = DispatchQueue(label: "PulseDock.SystemMetricsSampler", qos: .utility)
    private var temperaturePolicy: PeriodicSamplingPolicy
    private var cachedTemperature = TemperatureMetricSample(value: nil, source: "芯片温度")

    init(temperatureInterval: TimeInterval = 8) {
        let cpu = CPUReader()
        let traffic = NetworkTrafficReader()
        let hardwareTemperature = HardwareTemperatureReader()
        readCore = {
            let speeds = traffic.read()
            return SystemMetricsCoreSample(
                cpuUsage: cpu.read(),
                memoryUsage: MemoryReader.readPercent(),
                gpuUsage: GPUReader.readPercent(),
                downloadSpeed: speeds.download,
                uploadSpeed: speeds.upload,
                thermalState: PowerReader.thermalLabel,
                batteryPercent: PowerReader.batteryPercent(),
                proxyActive: ProxyDetector.systemProxyEnabled()
            )
        }
        readTemperature = {
            if let value = hardwareTemperature.readDieTemperature() {
                return TemperatureMetricSample(value: value, source: "芯片最高温")
            }
            return TemperatureMetricSample(value: PowerReader.batteryTemperature(), source: "电池温度")
        }
        temperaturePolicy = PeriodicSamplingPolicy(interval: temperatureInterval)
    }

    init(
        temperatureInterval: TimeInterval = 8,
        coreReader: @escaping CoreReader,
        temperatureReader: @escaping TemperatureReader
    ) {
        readCore = coreReader
        readTemperature = temperatureReader
        temperaturePolicy = PeriodicSamplingPolicy(interval: temperatureInterval)
    }

    func sample(at date: Date = Date()) async -> SystemMetricsSnapshot {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                continuation.resume(returning: collect(at: date))
            }
        }
    }

    private func collect(at date: Date) -> SystemMetricsSnapshot {
        let started = DispatchTime.now().uptimeNanoseconds
        let ranOnMainThread = Thread.isMainThread
        let core = readCore()
        if temperaturePolicy.consumeIfDue(at: date) {
            cachedTemperature = readTemperature()
        }
        let finished = DispatchTime.now().uptimeNanoseconds
        return SystemMetricsSnapshot(
            cpuUsage: core.cpuUsage,
            memoryUsage: core.memoryUsage,
            gpuUsage: core.gpuUsage,
            downloadSpeed: core.downloadSpeed,
            uploadSpeed: core.uploadSpeed,
            temperature: cachedTemperature.value,
            temperatureSource: cachedTemperature.source,
            thermalState: core.thermalState,
            batteryPercent: core.batteryPercent,
            proxyActive: core.proxyActive,
            sampledAt: date,
            collectionDurationMilliseconds: Double(finished - started) / 1_000_000,
            collectionRanOnMainThread: ranOnMainThread
        )
    }
}
