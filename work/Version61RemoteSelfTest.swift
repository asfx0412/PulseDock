import Foundation

@main
enum Version61RemoteSelfTest {
    static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8)); exit(1) }
    }

    static func main() {
        let text = """
        __PD_CONNECTED__=1
        __PD_HOST__=a100-one
        __PD_LOAD__=2.15
        __PD_MEM__=20.0
        __PD_DISK__=84
        __PD_CODEX__=found|/home/test/.local/bin/codex|codex 1.2.3
        __PD_ENDPOINT__=401
        __PD_GPUS_BEGIN__
        0, GPU-a, NVIDIA A100, 92, 20257, 81920, 68, 310
        0, GPU-a, NVIDIA A100, 92, 20257, 81920, 68, 310
        1, GPU-b, NVIDIA A100, 0, 20823, 81920, 57, 110
        __PD_GPUS_END__
        __PD_PROCS_BEGIN__
        GPU-a, 1234, python, 7292
        GPU-b, 1234, python, 1854
        GPU-b, 5678, python3.10, 1684
        __PD_PROCS_END__
        __PD_PROCS_STATUS__=ok
        __PD_PS_BEGIN__
        zhangyu 1234 06:26:36 python
        zhangyu 1234 06:26:36 python
        zhangyu 5678 00:48 python3.10
        __PD_PS_END__
        __PD_ARGS_BEGIN__
        1234|HF_TOKEN=hidden-one WANDB_API_KEY=hidden-two python train.py --token secret-token --url https://example.com/run?api_key=hidden-three --config /root/private.yaml
        __PD_ARGS_END__
        """
        let snapshot = SSHMonitorService.parseForTesting(text: text)
        for _ in 0..<1_000 {
            let repeated = SSHMonitorService.parseForTesting(text: text)
            require(repeated.gpus.count == 2 && repeated.gpuProcesses.count == 2, "重复远端数据压力回归不得崩溃或重复累计")
        }
        require(snapshot.health == .healthy, "401 表示端点可达，不应标记为网络故障")
        require(snapshot.codexFound && snapshot.codexPath == "/home/test/.local/bin/codex", "应发现用户级 Codex")
        require(snapshot.gpus.count == 2 && snapshot.totalGPUUsedMiB == 41_080, "重复 GPU 行必须去重且显存汇总正确")
        require(snapshot.gpuMemorySummary.contains("GB"), "总显存必须使用易读的 GB")
        require(snapshot.gpuProcesses.count == 2, "重复 PID 必须归并，不能崩溃")
        require(snapshot.taskCollectionDetail.contains("2 个"), "任务采集成功必须显示数量")
        let process = snapshot.gpuProcesses.first { $0.pid == 1234 }
        require(process?.memoryMiB == 9_146 && process?.gpuIndices == [0, 1], "跨 GPU PID 的显存和 GPU 索引应正确归并")
        require(!(process?.redactedCommand?.contains("secret-token") ?? true), "命令中的 Token 必须脱敏")
        require(!(process?.redactedCommand?.contains("hidden-one") ?? true) && !(process?.redactedCommand?.contains("hidden-two") ?? true) && !(process?.redactedCommand?.contains("hidden-three") ?? true), "环境变量、URL 查询和 Authorization 类凭据必须脱敏")
        require(!(process?.redactedCommand?.contains("/root/") ?? true), "root 绝对路径必须脱敏")

        let hostile = """
        __PD_CONNECTED__=1
        __PD_CODEX__=missing
        __PD_ENDPOINT__=401
        __PD_GPUS_BEGIN__
        0, N/A, NVIDIA 4090, N/A, 900, 800, N/A, N/A
        0, GPU-conflict, NVIDIA 4090, 10, 100, 800, 40, 50
        1, N/A, NVIDIA 4090, 150, 100, 800, NaN, Inf
        __PD_GPUS_END__
        __PD_PROCS_BEGIN__
        __PD_PROCS_END__
        __PD_PROCS_STATUS__=ok
        __PD_JOBS_BEGIN__
        42|train|RUNNING|00:01|01:00|2026-08-24T12:00
        42|duplicate|RUNNING|00:01|01:00|2026-08-24T12:00
        __PD_JOBS_END__
        __PD_JOBS_STATUS__=ok
        """
        let hostileSnapshot = SSHMonitorService.parseForTesting(text: hostile)
        require(hostileSnapshot.gpus.count == 2 && Set(hostileSnapshot.gpus.map(\.index)).count == 2, "GPU index 必须在不可信输出中保持唯一")
        require(hostileSnapshot.gpus[0].memoryUsedMiB == 800 && hostileSnapshot.gpus[0].utilizationPercent == nil, "显存超限要夹紧，N/A 算力不得伪装成 0%")
        require(hostileSnapshot.gpus[1].utilizationPercent == nil && hostileSnapshot.gpus[1].temperatureCelsius == nil && hostileSnapshot.gpus[1].powerWatts == nil, "越界或非有限 GPU 辅助字段必须丢弃")
        require(hostileSnapshot.scheduledJobs.count == 1 && hostileSnapshot.health == .degraded, "重复任务必须去重，解析修正必须有降级证据")
        let dnsFailure = SSHMonitorService.parseForTesting(text: "__PD_CODEX__=missing\n__PD_ENDPOINT__=curl: (6) Could not resolve host: chatgpt.com000\n")
        require(dnsFailure.health == .degraded && dnsFailure.codexEndpointDetail.contains("DNS"), "DNS 失败应被明确分类")
        let timeout = SSHMonitorService.classifySSHFailure("ssh: connect to host 10.0.0.2 port 22: Operation timed out")
        require(timeout.reason.contains("8 秒") && timeout.recovery.contains("立即刷新"), "SSH 连接超时必须给出明确、可重试的建议")
        let denied = SSHMonitorService.classifySSHFailure("Permission denied (publickey)")
        require(denied.reason.contains("认证失败"), "认证失败必须被明确分类")
        let processTimeout = SSHMonitorService.parseForTesting(text: "__PD_CONNECTED__=1\n__PD_CODEX__=missing\n__PD_ENDPOINT__=401\n__PD_PROCS_STATUS__=timeout\n")
        require(processTimeout.taskCollectionDetail.contains("超过 8 秒"), "进程超时必须明确解释脱敏任务缺失原因")
        let local = RemoteNetworkScopeService.parseIPv4("192.168.50.12")!
        let sameTarget = RemoteNetworkScopeService.parseIPv4("192.168.50.99")!
        let otherTarget = RemoteNetworkScopeService.parseIPv4("192.168.51.99")!
        let mask = RemoteNetworkScopeService.parseIPv4("255.255.255.0")!
        require(RemoteNetworkScopeService.sameSubnet(local: local, mask: mask, target: sameTarget), "同一 /24 局域网必须允许 SSH 探测")
        require(!RemoteNetworkScopeService.sameSubnet(local: local, mask: mask, target: otherTarget), "不同子网不能仅凭掩码直接放行")
        require(RemoteNetworkScopeService.permitsRoutedPrivateTarget(hasPrivateTarget: true, tcpReachable: true), "不同私网子网但 SSH 端口可达时必须允许路由局域网探测")
        require(!RemoteNetworkScopeService.permitsRoutedPrivateTarget(hasPrivateTarget: true, tcpReachable: false), "不同私网子网且 SSH 端口不可达时必须继续暂停告警")
        require(!RemoteNetworkScopeService.permitsRoutedPrivateTarget(hasPrivateTarget: false, tcpReachable: true), "公网目标不能被局域网路由探测误分类")
        require(RemoteNetworkScopeService.permitsSpecificPhysicalRoute(destination: "10.33.48.138", interface: "en0", activeInterfaces: ["en0"]), "经活动物理网卡的专用主机路由必须识别为局域网")
        require(!RemoteNetworkScopeService.permitsSpecificPhysicalRoute(destination: "default", interface: "en0", activeInterfaces: ["en0"]), "默认路由不能将任意私网地址误判为局域网")
        require(!RemoteNetworkScopeService.permitsSpecificPhysicalRoute(destination: "10.33.48.138", interface: "utun3", activeInterfaces: ["en0"]), "VPN 或非活动物理网卡路由不能误判为局域网")
        require(RemoteNetworkScope.localLAN.shortLabel == "局域网" && RemoteNetworkScope.publicInternet.shortLabel == "公网", "设备卡必须区分局域网与公网范围")
        print("PulseDock 6.2 remote self-test passed")
    }
}
