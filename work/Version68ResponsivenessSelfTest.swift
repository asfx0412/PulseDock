import Foundation

@main
enum Version68ResponsivenessSelfTest {
    static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
            exit(1)
        }
    }

    static func main() {
        var accumulator = MainThreadResponsivenessAccumulator(capacity: 5)
        [10.0, 20, 120, 300, 700, 30].forEach {
            accumulator.record(delayMilliseconds: $0, at: Date(timeIntervalSince1970: $0))
        }
        let snapshot = accumulator.snapshot
        require(snapshot.sampleCount == 5, "滚动窗口必须裁剪旧样本")
        require(snapshot.latestDelayMilliseconds == 30, "必须保留最近响应延迟")
        require(snapshot.maximumDelayMilliseconds == 700, "必须保留窗口内最大延迟")
        require(snapshot.p95DelayMilliseconds == 700 && snapshot.p99DelayMilliseconds == 700, "P95/P99 最近排名应正确")
        require(snapshot.over100MillisecondsCount == 3, ">100 ms 计数错误")
        require(snapshot.over250MillisecondsCount == 2, ">250 ms 计数错误")
        require(snapshot.over500MillisecondsCount == 1, ">500 ms 计数错误")
        require(snapshot.isDegraded, "500 ms 卡顿必须标记为界面响应降级")
        require(!snapshot.evidenceLabel.contains("PulseDock"), "响应证据不应记录应用或内容身份")

        let monitor = MainThreadResponsivenessMonitor(interval: 0.05, windowCapacity: 10)
        monitor.start()
        monitor.start() // idempotence regression guard
        RunLoop.main.run(until: Date().addingTimeInterval(0.18))
        let baseline = monitor.snapshot()
        require(baseline.sampleCount > 0, "实际主线程 ping 应产生样本")
        Thread.sleep(forTimeInterval: 0.20) // intentionally simulate a blocked UI executor
        RunLoop.main.run(until: Date().addingTimeInterval(0.08))
        let live = monitor.snapshot()
        monitor.stop()
        monitor.stop()
        require(live.latestDelayMilliseconds >= 0, "延迟不得为负数")
        require(live.maximumDelayMilliseconds >= 100, "响应监测必须捕获故意模拟的主线程停顿")

        print("PulseDock 6.8 responsiveness self-test passed")
    }
}
