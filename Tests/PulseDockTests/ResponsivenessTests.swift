import Foundation
import XCTest
@testable import PulseDock

final class ResponsivenessTests: XCTestCase {
    func testTemperaturePolicySamplesImmediatelyThenThrottles() {
        let start = Date(timeIntervalSince1970: 1_000)
        var policy = PeriodicSamplingPolicy(interval: 8)
        XCTAssertTrue(policy.consumeIfDue(at: start))
        XCTAssertFalse(policy.consumeIfDue(at: start.addingTimeInterval(7.99)))
        XCTAssertTrue(policy.consumeIfDue(at: start.addingTimeInterval(8)))
        XCTAssertFalse(policy.consumeIfDue(at: start.addingTimeInterval(9)))
    }

    func testResponsivenessAccumulatorUsesRollingWindowAndThresholds() {
        var accumulator = MainThreadResponsivenessAccumulator(capacity: 5)
        [10.0, 20, 120, 300, 700, 30].forEach {
            accumulator.record(delayMilliseconds: $0, at: Date(timeIntervalSince1970: $0))
        }
        let snapshot = accumulator.snapshot
        XCTAssertEqual(snapshot.sampleCount, 5)
        XCTAssertEqual(snapshot.latestDelayMilliseconds, 30)
        XCTAssertEqual(snapshot.maximumDelayMilliseconds, 700)
        XCTAssertEqual(snapshot.p95DelayMilliseconds, 700)
        XCTAssertEqual(snapshot.p99DelayMilliseconds, 700)
        XCTAssertEqual(snapshot.over100MillisecondsCount, 3)
        XCTAssertEqual(snapshot.over250MillisecondsCount, 2)
        XCTAssertEqual(snapshot.over500MillisecondsCount, 1)
        XCTAssertTrue(snapshot.isDegraded)
    }

    @MainActor
    func testSystemMetricsSamplerCollectsOffMainActorAndCachesTemperature() async {
        let core = SystemMetricsCoreSample(
            cpuUsage: 12,
            memoryUsage: 34,
            gpuUsage: 56,
            downloadSpeed: 78,
            uploadSpeed: 90,
            thermalState: "正常",
            batteryPercent: 88,
            proxyActive: true
        )
        let sampler = SystemMetricsSampler(
            temperatureInterval: 8,
            coreReader: { core },
            temperatureReader: { TemperatureMetricSample(value: 66, source: "测试温度") }
        )
        let start = Date(timeIntervalSince1970: 1_000)
        let first = await sampler.sample(at: start)
        let cached = await sampler.sample(at: start.addingTimeInterval(2))

        XCTAssertFalse(first.collectionRanOnMainThread)
        XCTAssertEqual(first.temperature, 66)
        XCTAssertEqual(cached.temperature, 66)
        XCTAssertEqual(first.cpuUsage, 12)
        XCTAssertEqual(first.downloadSpeed, 78)
        XCTAssertGreaterThanOrEqual(first.collectionDurationMilliseconds, 0)
    }
}
