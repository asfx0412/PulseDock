import Foundation

struct MainThreadResponsivenessSnapshot: Sendable, Equatable {
    var sampleCount = 0
    var latestDelayMilliseconds = 0.0
    var p95DelayMilliseconds = 0.0
    var p99DelayMilliseconds = 0.0
    var maximumDelayMilliseconds = 0.0
    var over100MillisecondsCount = 0
    var over250MillisecondsCount = 0
    var over500MillisecondsCount = 0
    var updatedAt: Date?

    static let idle = MainThreadResponsivenessSnapshot()

    var isDegraded: Bool {
        maximumDelayMilliseconds >= 500 || p95DelayMilliseconds >= 100
    }

    var evidenceLabel: String {
        guard sampleCount > 0 else { return "正在收集界面响应样本" }
        return String(
            format: "P95 %.0f ms · P99 %.0f ms · 最大 %.0f ms · >500 ms %d 次",
            p95DelayMilliseconds,
            p99DelayMilliseconds,
            maximumDelayMilliseconds,
            over500MillisecondsCount
        )
    }
}

/// Pure rolling accumulator so percentile and threshold behavior can be tested
/// without timers, sleeping, or UI automation.
struct MainThreadResponsivenessAccumulator: Sendable {
    let capacity: Int
    private var delays: [Double] = []
    private var lastUpdatedAt: Date?

    init(capacity: Int = 300) {
        self.capacity = max(1, capacity)
    }

    mutating func record(delayMilliseconds: Double, at date: Date = Date()) {
        delays.append(max(0, delayMilliseconds))
        if delays.count > capacity {
            delays.removeFirst(delays.count - capacity)
        }
        lastUpdatedAt = date
    }

    var snapshot: MainThreadResponsivenessSnapshot {
        guard !delays.isEmpty else { return .idle }
        let sorted = delays.sorted()
        return MainThreadResponsivenessSnapshot(
            sampleCount: delays.count,
            latestDelayMilliseconds: delays.last ?? 0,
            p95DelayMilliseconds: percentile(0.95, in: sorted),
            p99DelayMilliseconds: percentile(0.99, in: sorted),
            maximumDelayMilliseconds: sorted.last ?? 0,
            over100MillisecondsCount: delays.count { $0 >= 100 },
            over250MillisecondsCount: delays.count { $0 >= 250 },
            over500MillisecondsCount: delays.count { $0 >= 500 },
            updatedAt: lastUpdatedAt
        )
    }

    private func percentile(_ percentile: Double, in sorted: [Double]) -> Double {
        let rank = max(0, min(sorted.count - 1, Int(ceil(percentile * Double(sorted.count))) - 1))
        return sorted[rank]
    }
}

/// Dispatches one lightweight ping at a time from a private timer queue to the
/// main queue. If the UI thread stalls, the pending ping measures the delay;
/// further timer ticks are coalesced so a stall cannot flood the main queue.
/// Only aggregate durations are stored: no window titles, clicks, text, or
/// application identity is recorded.
final class MainThreadResponsivenessMonitor: @unchecked Sendable {
    private let interval: TimeInterval
    private let queue = DispatchQueue(label: "PulseDock.MainThreadResponsiveness", qos: .utility)
    private let lock = NSLock()
    private var timer: DispatchSourceTimer?
    private var generation: UInt64 = 0
    private var pingPending = false
    private var accumulator: MainThreadResponsivenessAccumulator

    init(interval: TimeInterval = 0.2, windowCapacity: Int = 300) {
        self.interval = max(0.05, interval)
        accumulator = MainThreadResponsivenessAccumulator(capacity: windowCapacity)
    }

    func start() {
        lock.lock()
        guard timer == nil else { lock.unlock(); return }
        generation &+= 1
        let activeGeneration = generation
        let source = DispatchSource.makeTimerSource(queue: queue)
        timer = source
        lock.unlock()

        source.schedule(deadline: .now() + interval, repeating: interval, leeway: .milliseconds(20))
        source.setEventHandler { [weak self] in
            self?.enqueuePing(generation: activeGeneration)
        }
        source.resume()
    }

    func stop() {
        lock.lock()
        generation &+= 1
        let source = timer
        timer = nil
        pingPending = false
        lock.unlock()
        source?.setEventHandler {}
        source?.cancel()
    }

    func snapshot() -> MainThreadResponsivenessSnapshot {
        lock.lock()
        defer { lock.unlock() }
        return accumulator.snapshot
    }

    private func enqueuePing(generation requestedGeneration: UInt64) {
        lock.lock()
        guard timer != nil, generation == requestedGeneration, !pingPending else {
            lock.unlock()
            return
        }
        pingPending = true
        let scheduledAt = DispatchTime.now().uptimeNanoseconds
        lock.unlock()

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let arrivedAt = DispatchTime.now().uptimeNanoseconds
            let delay = Double(arrivedAt - scheduledAt) / 1_000_000
            self.lock.lock()
            defer { self.lock.unlock() }
            guard self.timer != nil, self.generation == requestedGeneration else {
                self.pingPending = false
                return
            }
            self.accumulator.record(delayMilliseconds: delay)
            self.pingPending = false
        }
    }
}
