import Darwin
import Foundation

private final class BoundedSSHOutputCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()
    private let limit: Int

    init(limit: Int) { self.limit = limit }

    func append(_ value: Data) {
        guard !value.isEmpty else { return }
        lock.lock(); defer { lock.unlock() }
        guard data.count < limit else { return }
        data.append(value.prefix(limit - data.count))
    }

    func text() -> String {
        lock.lock(); defer { lock.unlock() }
        return String(decoding: data, as: UTF8.self)
    }
}

actor SSHMonitorService {
    func probe(_ device: RemoteDeviceConfiguration) async -> RemoteDeviceSnapshot {
        guard Self.validAlias(device.sshAlias) else {
            return RemoteDeviceSnapshot(id: device.id, health: .offline, checkedAt: Date(), message: "SSH 别名仅允许字母、数字、点、下划线和连字符")
        }
        let started = Date()
        let result = await Task.detached(priority: .utility) {
            Self.run(alias: device.sshAlias, collectOwners: device.collectProcessOwners, collectJobs: device.collectSchedulerJobs, disclosureMode: device.taskDisclosureMode)
        }.value
        if result.status != 0, result.output.contains("__PD_CONNECTED__=1") {
            var partial = Self.parse(id: device.id, text: result.output, latencyMS: Date().timeIntervalSince(started) * 1_000, stderr: result.error)
            partial.health = .degraded
            partial.diagnosticEvidence = [partial.diagnosticEvidence, "SSH 登录已成功，但 GPU/任务等详细采集超过 36 秒，已保留本次完整字段和上次缓存。"].filter { !$0.isEmpty }.joined(separator: "\n")
            partial.message = "SSH 可用；远程详细采集超时"
            return partial
        }
        guard result.status == 0 else {
            let rawDetail = result.error.isEmpty ? "SSH 进程退出码 \(result.status)" : String(result.error.prefix(360))
            let diagnosis = Self.classifySSHFailure(rawDetail)
            let evidence = "分类：\(diagnosis.reason)\n建议：\(diagnosis.recovery)\n原始 SSH 输出：\(rawDetail)"
            return RemoteDeviceSnapshot(id: device.id, health: .offline, latencyMS: Date().timeIntervalSince(started) * 1_000, codexDiscoveryDetail: "未执行（SSH 不可用）", codexEndpointDetail: "未执行（SSH 不可用）", diagnosticEvidence: evidence, checkedAt: Date(), message: "SSH 不可用：\(diagnosis.reason)")
        }
        return Self.parse(id: device.id, text: result.output, latencyMS: Date().timeIntervalSince(started) * 1_000, stderr: result.error)
    }

    nonisolated static func validAlias(_ value: String) -> Bool {
        !value.isEmpty && value.range(of: "^[A-Za-z0-9._-]+$", options: .regularExpression) != nil
    }

    nonisolated static func classifySSHFailure(_ raw: String) -> (reason: String, recovery: String) {
        let lower = raw.lowercased()
        if lower.contains("host key verification failed") { return ("主机密钥校验失败", "在终端运行 ssh <别名>，确认服务器指纹变更；不要删除 known_hosts 后盲目信任。") }
        if lower.contains("permission denied") { return ("认证失败（密钥/agent/账号权限）", "在终端运行 ssh -v <别名>，检查 ssh-agent 是否加载正确密钥及远端 authorized_keys。") }
        if lower.contains("connection refused") { return ("目标主机拒绝 SSH 连接", "确认主机在线、sshd 正在监听，以及跳板机/安全组允许当前来源。") }
        if lower.contains("no route to host") || lower.contains("network is unreachable") { return ("到主机的网络路由不可达", "检查 VPN/Clash 规则、公司网络和跳板机连通性；此问题发生在登录前。") }
        if lower.contains("could not resolve hostname") || lower.contains("name or service not known") { return ("SSH 别名或 DNS 无法解析", "确认 ~/.ssh/config 中 Host / HostName 配置；必要时在终端运行 ssh -G <别名> 查看实际目标。") }
        if lower.contains("timed out") || lower.contains("operation timeout") || raw.contains("超时") { return ("SSH 连接在 8 秒内未建立", "可能是网络路由、VPN/Clash、跳板机或目标主机不可达；可点击“立即刷新”重试，并用 ssh -vvv <别名> 进一步定位。") }
        return ("SSH 进程异常退出", "点击“立即刷新”复测；若持续失败，复制诊断并在终端运行 ssh -vvv <别名> 查看认证和连接阶段。")
    }

    private nonisolated static func run(alias: String, collectOwners: Bool, collectJobs: Bool, disclosureMode: RemoteTaskDisclosureMode) -> (status: Int32, output: String, error: String) {
        var command = """
        echo '__PD_CONNECTED__=1'
        printf '__PD_HOST__='; hostname 2>/dev/null || true
        printf '__PD_LOAD__='; cut -d' ' -f1 /proc/loadavg 2>/dev/null || sysctl -n vm.loadavg 2>/dev/null | tr -dc '0-9. ' | awk '{print $1}'
        printf '__PD_MEM__='; awk '/MemTotal/{t=$2}/MemAvailable/{a=$2}END{if(t>0)printf \"%.1f\\n\",(t-a)*100/t}' /proc/meminfo 2>/dev/null || true
        printf '__PD_DISK__='; df -P / 2>/dev/null | awk 'NR==2{gsub(/%/,\"\",$5);print $5}'
        pd_codex=''
        for pd_candidate in "$(command -v codex 2>/dev/null)" "$HOME/.local/bin/codex" "$HOME/.npm-global/bin/codex" "$HOME/bin/codex"; do
          if [ -n "$pd_candidate" ] && [ -x "$pd_candidate" ]; then pd_codex="$pd_candidate"; break; fi
        done
        if [ -n "$pd_codex" ]; then printf '__PD_CODEX__=found|%s|' "$pd_codex"; "$pd_codex" --version 2>/dev/null | head -1; else echo '__PD_CODEX__=missing'; fi
        printf '__PD_ENDPOINT__='; curl -sS -m 8 -o /dev/null -w '%{http_code}' -X POST -H 'content-type: application/json' -d '{}' https://chatgpt.com/backend-api/codex/responses 2>&1; echo
        echo '__PD_GPUS_BEGIN__'
        if command -v nvidia-smi >/dev/null 2>&1; then nvidia-smi --query-gpu=index,uuid,name,utilization.gpu,memory.used,memory.total,temperature.gpu,power.draw --format=csv,noheader,nounits 2>/dev/null; fi
        echo '__PD_GPUS_END__'
        echo '__PD_PROCS_BEGIN__'
        pd_procs=''
        pd_procs_status='unavailable'
        if command -v nvidia-smi >/dev/null 2>&1; then
          if command -v timeout >/dev/null 2>&1; then
            pd_procs=$(timeout 8s nvidia-smi --query-compute-apps=gpu_uuid,pid,process_name,used_gpu_memory --format=csv,noheader,nounits 2>/dev/null)
            pd_procs_exit=$?
            if [ "$pd_procs_exit" -eq 124 ]; then pd_procs_status='timeout'; elif [ "$pd_procs_exit" -eq 0 ]; then pd_procs_status='ok'; else pd_procs_status='error'; fi
          else
            pd_procs=$(nvidia-smi --query-compute-apps=gpu_uuid,pid,process_name,used_gpu_memory --format=csv,noheader,nounits 2>/dev/null)
            if [ "$?" -eq 0 ]; then pd_procs_status='ok'; else pd_procs_status='error'; fi
          fi
          printf '%s\n' "$pd_procs"
        fi
        echo '__PD_PROCS_END__'
        printf '__PD_PROCS_STATUS__=%s\n' "$pd_procs_status"
        """
        if collectOwners || disclosureMode == .redactedCommand {
            command += """

            echo '__PD_PS_BEGIN__'
            if [ -n "$pd_procs" ]; then
              printf '%s\n' "$pd_procs" | awk -F',' '{gsub(/ /,"",$2); print $2}' | awk '!seen[$0]++' | while IFS= read -r pd_pid; do
                case "$pd_pid" in (*[!0-9]*|'') continue;; esac
                ps -p "$pd_pid" -o user=,pid=,etime=,comm= 2>/dev/null
              done
            fi
            echo '__PD_PS_END__'
            """
        }
        if disclosureMode == .redactedCommand {
            command += """

            echo '__PD_ARGS_BEGIN__'
            if [ -n "$pd_procs" ]; then
              printf '%s\n' "$pd_procs" | awk -F',' '{gsub(/ /,"",$2); print $2}' | awk '!seen[$0]++' | while IFS= read -r pd_pid; do
                case "$pd_pid" in (*[!0-9]*|'') continue;; esac
                pd_args=$(ps -p "$pd_pid" -o args= 2>/dev/null | tr '\\n' ' ')
                printf '%s|%s\\n' "$pd_pid" "$pd_args"
              done
            fi
            echo '__PD_ARGS_END__'
            """
        }
        if collectJobs {
            command += "\necho '__PD_JOBS_BEGIN__'; if command -v squeue >/dev/null 2>&1; then squeue -h -u \"$(id -un)\" -o '%i|%j|%T|%M|%l|%e' 2>/dev/null; pd_jobs_status='ok'; else pd_jobs_status='unavailable'; fi; echo '__PD_JOBS_END__'; printf '__PD_JOBS_STATUS__=%s\\n' \"$pd_jobs_status\"\n"
        }
        // Force the fixed read-only payload through POSIX sh. Otherwise ssh
        // asks the account's login shell to interpret it, and fish/csh users
        // can connect in Terminal while PulseDock's probe fails syntactically.
        let encodedCommand = Data(command.utf8).base64EncodedString()
        let remoteCommand = "printf %s \(encodedCommand) | base64 -d | /bin/sh"
        let process = Process(); let output = Pipe(); let error = Pipe()
        let outputCollector = BoundedSSHOutputCollector(limit: 2_000_000)
        let errorCollector = BoundedSSHOutputCollector(limit: 128_000)
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        process.arguments = ["-o", "BatchMode=yes", "-o", "ClearAllForwardings=yes", "-o", "ConnectTimeout=8", "-o", "ServerAliveInterval=5", "-o", "ServerAliveCountMax=1", alias, remoteCommand]
        process.standardOutput = output; process.standardError = error
        output.fileHandleForReading.readabilityHandler = { outputCollector.append($0.availableData) }
        error.fileHandleForReading.readabilityHandler = { errorCollector.append($0.availableData) }
        do { try process.run() }
        catch let runError {
            output.fileHandleForReading.readabilityHandler = nil
            error.fileHandleForReading.readabilityHandler = nil
            return (-1, "", runError.localizedDescription)
        }
        let deadline = Date().addingTimeInterval(36)
        while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
        if process.isRunning {
            process.terminate()
            let terminationDeadline = Date().addingTimeInterval(0.7)
            while process.isRunning, Date() < terminationDeadline { Thread.sleep(forTimeInterval: 0.02) }
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            process.waitUntilExit()
            output.fileHandleForReading.readabilityHandler = nil
            error.fileHandleForReading.readabilityHandler = nil
            outputCollector.append(output.fileHandleForReading.readDataToEndOfFile())
            errorCollector.append(error.fileHandleForReading.readDataToEndOfFile())
            let out = outputCollector.text()
            let err = errorCollector.text()
            return (-2, out, err.isEmpty ? "远程详细采集超时（36 秒）" : err)
        }
        output.fileHandleForReading.readabilityHandler = nil
        error.fileHandleForReading.readabilityHandler = nil
        outputCollector.append(output.fileHandleForReading.readDataToEndOfFile())
        errorCollector.append(error.fileHandleForReading.readDataToEndOfFile())
        let out = outputCollector.text()
        let err = errorCollector.text()
        return (process.terminationStatus, out, err)
    }

    private nonisolated static func parse(id: UUID, text: String, latencyMS: Double, stderr: String) -> RemoteDeviceSnapshot {
        let boundedText = String(text.prefix(2_000_000))
        let lines = boundedText.split(separator: "\n", omittingEmptySubsequences: false).prefix(12_000)
        func value(_ key: String) -> String? { lines.first(where: { $0.hasPrefix(key) }).map { String($0.dropFirst(key.count).prefix(2_048)) } }
        func block(_ begin: String, _ end: String) -> [String] {
            guard let a = boundedText.range(of: begin), let b = boundedText.range(of: end, range: a.upperBound..<boundedText.endIndex) else { return [] }
            return boundedText[a.upperBound..<b.lowerBound].split(separator: "\n").prefix(2_048).map { String($0.prefix(2_048)) }.filter { !$0.isEmpty }
        }
        var parseIssues: [String] = []
        let parsedGPUs = block("__PD_GPUS_BEGIN__", "__PD_GPUS_END__").compactMap { line -> RemoteGPU? in
            let p = line.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            guard p.count >= 6, let index = Int(p[0]), (0...1_024).contains(index),
                  let used = Int(p[4]), used >= 0,
                  let total = Int(p[5]), total > 0, total <= 16_777_216 else { return nil }
            let util = Double(p[3]).flatMap { $0.isFinite && (0...100).contains($0) ? $0 : nil }
            let temperature = p.count > 6 ? Double(p[6]).flatMap { $0.isFinite && (-50...200).contains($0) ? $0 : nil } : nil
            let power = p.count > 7 ? Double(p[7]).flatMap { $0.isFinite && (0...10_000).contains($0) ? $0 : nil } : nil
            let safeUsed = min(used, total)
            if used > total, parseIssues.count < 8 { parseIssues.append("GPU \(index) 显存已用值超过总量，已按总量夹紧") }
            let rawUUID = String(p[1].prefix(128))
            let uuid = rawUUID == "N/A" || rawUUID == "[N/A]" ? "" : rawUUID
            return RemoteGPU(index: index, uuid: uuid, name: String(p[2].prefix(160)), utilizationPercent: util, memoryUsedMiB: safeUsed, memoryTotalMiB: total, temperatureCelsius: temperature, powerWatts: power)
        }
        // Driver output can occasionally repeat a GPU row. Never construct a
        // dictionary from untrusted remote output with uniqueKeysWithValues:
        // duplicate keys are a process-terminating precondition failure.
        var gpuByIndex: [Int: RemoteGPU] = [:]
        var seenGPUUUIDs: Set<String> = []
        let gpus = parsedGPUs.filter { gpu in
            if let existing = gpuByIndex[gpu.index] {
                if existing != gpu, parseIssues.count < 8 { parseIssues.append("冲突 GPU 索引 \(gpu.index) 已保留首条") }
                return false
            }
            guard gpu.uuid.isEmpty || seenGPUUUIDs.insert(gpu.uuid).inserted else {
                if parseIssues.count < 8 { parseIssues.append("重复 GPU UUID 已忽略") }
                return false
            }
            gpuByIndex[gpu.index] = gpu
            return true
        }
        var indexByUUID: [String: Int] = [:]
        for gpu in gpus where !gpu.uuid.isEmpty && indexByUUID[gpu.uuid] == nil {
            indexByUUID[gpu.uuid] = gpu.index
        }
        var metadata: [Int: (String, String)] = [:]
        for line in block("__PD_PS_BEGIN__", "__PD_PS_END__") {
            let p = line.split(whereSeparator: \Character.isWhitespace).map(String.init)
            guard p.count >= 4, let pid = Int(p[1]), metadata[pid] == nil else { continue }
            metadata[pid] = (p[0], p[2])
        }
        var commands: [Int: String] = [:]
        for line in block("__PD_ARGS_BEGIN__", "__PD_ARGS_END__") {
            let p = line.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
            guard p.count == 2, let pid = Int(p[0]), commands[pid] == nil else { continue }
            commands[pid] = redactCommand(p[1])
        }
        struct ProcessAccumulator { var name: String; var memory: Int; var gpuIndices: Set<Int> }
        var grouped: [Int: ProcessAccumulator] = [:]
        var seenGPUProcessPairs: Set<String> = []
        for line in block("__PD_PROCS_BEGIN__", "__PD_PROCS_END__") {
            let p = line.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            guard p.count >= 4, let pid = Int(p[1]), pid > 0, let memory = Int(p[3]), memory >= 0, memory <= 16_777_216 else { continue }
            guard seenGPUProcessPairs.insert("\(p[0])|\(pid)").inserted else { continue }
            var entry = grouped[pid] ?? ProcessAccumulator(name: URL(fileURLWithPath: p[2]).lastPathComponent, memory: 0, gpuIndices: [])
            entry.memory = entry.memory > Int.max - memory ? Int.max : entry.memory + memory
            if let gpuIndex = indexByUUID[p[0]] { entry.gpuIndices.insert(gpuIndex) }
            grouped[pid] = entry
        }
        let processes = grouped.map { pid, entry in
            RemoteGPUProcess(pid: pid, name: entry.name, memoryMiB: entry.memory, gpuIndices: entry.gpuIndices.sorted(), user: metadata[pid]?.0, elapsed: metadata[pid]?.1, redactedCommand: commands[pid])
        }.sorted { $0.memoryMiB > $1.memoryMiB }
        let processStatus = value("__PD_PROCS_STATUS__=") ?? "incomplete"
        let taskCollectionDetail: String
        switch processStatus {
        case "ok": taskCollectionDetail = processes.isEmpty ? "本轮未发现 NVIDIA 计算进程" : "已读取 \(processes.count) 个 GPU 任务"
        case "timeout": taskCollectionDetail = "GPU 进程查询超过 8 秒；显存仍可用，但本轮无法读取任务与脱敏命令"
        case "unavailable": taskCollectionDetail = "远端未提供 NVIDIA 进程查询"
        case "error": taskCollectionDetail = "NVIDIA 进程查询返回错误"
        default: taskCollectionDetail = "远程采集未完成，任务信息不可用"
        }
        var seenJobIDs: Set<String> = []
        let jobs = block("__PD_JOBS_BEGIN__", "__PD_JOBS_END__").compactMap { line -> RemoteScheduledJob? in
            let p = line.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            guard p.count >= 6 else { return nil }
            let jobID = String(p[0].prefix(80))
            guard !jobID.isEmpty, seenJobIDs.insert(jobID).inserted else { return nil }
            return RemoteScheduledJob(jobID: jobID, name: String(p[1].prefix(160)), state: String(p[2].prefix(40)), elapsed: String(p[3].prefix(40)), timeLimit: String(p[4].prefix(40)), expectedEnd: String(p[5].prefix(80)))
        }
        let schedulerStatus = value("__PD_JOBS_STATUS__=") ?? "not-requested"
        let schedulerCollectionDetail: String
        switch schedulerStatus {
        case "ok": schedulerCollectionDetail = jobs.isEmpty ? "Slurm 可用；当前 SSH 用户没有排队或运行中的任务" : "已读取 \(jobs.count) 个当前 SSH 用户的 Slurm 任务"
        case "unavailable": schedulerCollectionDetail = "远端未安装 Slurm/squeue，无法从调度器识别任务"
        default: schedulerCollectionDetail = "本轮未完成 Slurm 任务采集"
        }
        let codexRaw = value("__PD_CODEX__=") ?? "missing"
        let codexParts = codexRaw.split(separator: "|", maxSplits: 2, omittingEmptySubsequences: false).map(String.init)
        let codexFound = codexParts.first == "found"
        let codexPath = codexFound && codexParts.count > 1 ? codexParts[1] : nil
        let codexVersion = codexFound && codexParts.count > 2 ? codexParts[2] : nil
        let discovery = codexFound ? "已在受控探测路径发现 Codex：\(codexPath ?? "--")" : "默认 SSH 探测 PATH 与常见用户级路径中未发现 Codex；这不等于远端未安装。"
        let endpointRaw = value("__PD_ENDPOINT__=") ?? ""
        let endpoint = extractHTTPStatus(endpointRaw)
        let endpointDetail = describeEndpoint(raw: endpointRaw, status: endpoint)
        let requiredMarkers = ["__PD_CONNECTED__=1", "__PD_GPUS_BEGIN__", "__PD_GPUS_END__", "__PD_PROCS_BEGIN__", "__PD_PROCS_END__"]
        let missingMarkers = requiredMarkers.filter { !boundedText.contains($0) }
        // The endpoint probe is an optional, unauthenticated diagnostic.  A
        // missing HTTP status must not turn an otherwise reachable GPU host
        // into a permanent orange "partial failure" card.  Keep real parser
        // incompleteness and 5xx service failures as degraded conditions.
        let degraded = endpoint.map { $0 >= 500 } == true || !missingMarkers.isEmpty || !parseIssues.isEmpty
        let collectionIssue = missingMarkers.isEmpty ? "" : "采集数据不完整：缺少 \(missingMarkers.joined(separator: "、"))"
        let parseIssue = parseIssues.isEmpty ? "" : "解析修正：\(parseIssues.joined(separator: "；"))"
        let evidenceParts = ["端点：\(endpointDetail)", collectionIssue, parseIssue, !stderr.isEmpty ? "SSH stderr：\(String(stderr.prefix(280)))" : ""].filter { !$0.isEmpty }
        func finiteNumber(_ raw: String?) -> Double? {
            guard let number = raw.flatMap(Double.init), number.isFinite else { return nil }
            return number
        }
        func percent(_ raw: String?) -> Double? { finiteNumber(raw).map { max(0, min(100, $0)) } }
        let message: String
        if degraded { message = "主机采集不完整；\(endpointDetail)" }
        else if endpoint == nil || endpoint == 0 { message = "SSH 与资源采集正常；Codex 端点探测未获得状态（独立诊断）" }
        else { message = "SSH 与资源采集正常；\(endpointDetail)" }
        return RemoteDeviceSnapshot(id: id, health: degraded ? .degraded : .healthy, hostName: value("__PD_HOST__=") ?? "--", latencyMS: latencyMS, load1: finiteNumber(value("__PD_LOAD__=")), memoryUsedPercent: percent(value("__PD_MEM__=")), diskUsedPercent: percent(value("__PD_DISK__=")), codexFound: codexFound, codexVersion: codexVersion, codexPath: codexPath, codexDiscoveryDetail: discovery, codexEndpointStatus: endpoint, codexEndpointDetail: endpointDetail, diagnosticEvidence: evidenceParts.joined(separator: "\n"), gpus: gpus, gpuProcesses: processes, taskCollectionDetail: taskCollectionDetail, scheduledJobs: jobs, schedulerCollectionDetail: schedulerCollectionDetail, checkedAt: Date(), message: message)
    }

    nonisolated static func parseForTesting(id: UUID = UUID(), text: String, latencyMS: Double = 10, stderr: String = "") -> RemoteDeviceSnapshot {
        parse(id: id, text: text, latencyMS: latencyMS, stderr: stderr)
    }

    private nonisolated static func extractHTTPStatus(_ raw: String) -> Int? {
        guard let regex = try? NSRegularExpression(pattern: "(?<![0-9])[0-9]{3}(?![0-9])") else { return nil }
        let range = NSRange(raw.startIndex..., in: raw)
        let codes: [Int] = regex.matches(in: raw, range: range).compactMap { match -> Int? in
            guard let matchRange = Range(match.range, in: raw) else { return nil }
            return Int(raw[matchRange])
        }
        return codes.last
    }

    private nonisolated static func describeEndpoint(raw: String, status: Int?) -> String {
        let lower = raw.lowercased()
        if lower.contains("could not resolve") || lower.contains("couldn't resolve") { return "DNS 解析失败" }
        if lower.contains("ssl") || lower.contains("tls") || lower.contains("certificate") { return "TLS/证书握手失败" }
        if lower.contains("connection refused") { return "代理或目标端口拒绝连接" }
        if lower.contains("timed out") || lower.contains("timeout") { return "HTTPS 请求超时" }
        switch status {
        case 401, 403: return "HTTP \(status!)：端点可达，但远端 curl 未携带 Codex 认证"
        case 429: return "HTTP 429：端点可达，但服务限流"
        case let code? where code >= 500: return "HTTP \(code)：服务端异常"
        case let code? where code > 0: return "HTTP \(code)：端点可达"
        default: return raw.isEmpty ? "端点未返回 HTTP 状态" : "端点请求失败：\(String(raw.prefix(180)))"
        }
    }

    private nonisolated static func redactCommand(_ raw: String) -> String {
        var value = raw.replacingOccurrences(of: #"(?i)(--?(?:token|api[-_]?key|secret|password)(?:=|\s+))[^\s]+"#, with: "$1[REDACTED]", options: .regularExpression)
        value = value.replacingOccurrences(of: #"(?i)\b([a-z_][a-z0-9_]*(?:token|api[_-]?key|secret|password|passwd|authorization|auth)[a-z0-9_]*)=(?:\"[^\"]*\"|'[^']*'|[^\s]+)"#, with: "$1=[REDACTED]", options: .regularExpression)
        value = value.replacingOccurrences(of: #"(?i)(authorization\s*[:=]\s*bearer\s+)[^\s]+"#, with: "$1[REDACTED]", options: .regularExpression)
        value = value.replacingOccurrences(of: #"(?i)([?&](?:token|api[_-]?key|key|secret|password|auth)=)[^&\s]+"#, with: "$1[REDACTED]", options: .regularExpression)
        value = value.replacingOccurrences(of: #"/Users/[^/\s]+"#, with: "~/…", options: .regularExpression)
        value = value.replacingOccurrences(of: #"/home/[^/\s]+"#, with: "~/…", options: .regularExpression)
        value = value.replacingOccurrences(of: #"/root(?:/[^\s]*)?"#, with: "~/…", options: .regularExpression)
        if value.count > 220 { value = String(value.prefix(217)) + "…" }
        return value
    }
}
