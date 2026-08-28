# PulseDock 架构说明

## 分层

1. **采集层**：本机指标、网络、额度、天气、Clash、SSH、活动度和音频流。
2. **领域层**：把不同来源归一为带来源、时间、证据和状态的快照。
3. **事件层**：比较新旧快照，生成发生/恢复事件并去重。
4. **状态仓库**：`MonitorStore` 负责调度、生命周期、持久化偏好和界面绑定。
5. **呈现层**：紧凑浮窗、完整页面、菜单栏/Dock 与通知。

## macOS 代码映射

- `Sources/PulseDock/App`：应用、窗口和全局状态。
- `Sources/PulseDock/Models`：平台依赖较少的数据模型。
- `Sources/PulseDock/Services`：每种数据源一个服务；失败不得越层伪装。
- `Sources/PulseDock/Views`：SwiftUI 页面与 AppKit 交互桥接。
- `Sources/TemperatureBridge`：macOS IOKit/传感器桥。
- `Resources`：Info.plist、图标和本地化资源。
- `scripts` / `work`：构建、确定性测试和只读冒烟测试。

## 生命周期

启动不读取安全存储。基础监控启动后，各采集循环独立节流。用户主动解锁统一保险库后，秘密进入本次运行内存；退出时停止任务、播放器、观察者并清空内存凭据。

## 持久化

- UserDefaults：非秘密设置与设备/连接器定义。
- Application Support：活动账本和事件时间线。
- Keychain：唯一统一凭据保险库。
- 不持久化：Cursor access token、声音网络缓存、SSH 密码、远端输出全文。

## Codex 6.5 clean-room 数据流

`CodexQuotaService` 启动短生命周期 `codex app-server`，依次初始化并只读调用 `account/rateLimits/read` 与 `account/usage/read`。响应按请求 ID 独立收集；Token 活动接口不可用时不影响有效额度快照。多窗口按窗口时长命名，不使用含糊的 `#1/#2`。

PulseDock 只借鉴 Codex Runway 的信息分层。由于其仓库采用 AGPL-3.0，本项目不复制其 Swift 源码、OAuth、界面、文案、资产或测试夹具；实现依据 OpenAI 官方 app-server 文档独立完成。

## 媒体 6.6 数据流

- `MediaModels`：跨平台媒体类型、目录项、场景与播放状态。
- `InternetRadioDirectoryService`：ephemeral URLSession、描述性 User-Agent、`limit + offset` 分页、HTTPS/编解码过滤、UUID 与 URL 去重；合法空数组即为成功结果。
- `AmbientSoundService`：当前名称为兼容旧绑定，实际承担单播放器、分页、收藏和播放策略协调；generation 阻止旧流回调污染新流。
- `DirectAudioRelay`：只为当前用户选择的公共 HTTPS MP3/AAC 流建立会话级 `127.0.0.1` 随机端口中转；目标、重定向与路径均经过限制，生命周期绑定播放器。
- `FocusableTextField`：声音搜索的 AppKit 编辑桥，保证 key window、first responder、marked text 与 SwiftUI 状态更新之间的边界。
- `PanelViews`：环境音目录、复古磁带机与网络收音机只呈现状态，不持有网络或播放器生命周期。

AVPlayer 的系统临时网络缓冲不等同于离线下载；PulseDock 不建立媒体资料库、不保存播放历史、不自动恢复播放。

## 远程设备调度

远程设备持久化 `networkScope / pinned / sortOrder`。监控同时最多启动 3 个 SSH 采集；局域网/VPN 条件不满足时进入 `expectedOffline`，暂停探测与飞书告警；NWPathMonitor 观察到路径变化后宽限 90 秒，连续 3 次失败才生成异常事件。SSH stdout/stderr 在进程运行期间并发排空并限长，解析器拒绝超限数值与截断结构。同类 Wi-Fi 切换是否产生 NWPath 回调取决于系统，因此不将“识别每一个 SSID”作为已交付能力。
