# PulseDock 安全与隐私边界

## 本地秘密

- 飞书 Webhook、飞书签名密钥、API Key 和 Clash Controller Secret 仅存 macOS Keychain。
- PulseDock 启动和后台轮询不读取 Keychain；只有用户点击“解锁凭据”后才读取一个统一保险库，并在本次运行复用内存副本。
- 统一保险库同时充当额度可见性门禁：每次启动未解锁前，Codex、Cursor、Clash 与 API 额度不读取、不显示；锁定时立即清空额度快照和内存中的本地会话数据。
- 6.4.2 解锁时只读取统一保险库，不再自动枚举旧分散凭据。旧凭据迁移必须由用户主动触发，并且只做禁止认证 UI 的读取。
- 解锁后的“保存全部变更”“保存并刷新”和飞书保存使用非交互 Keychain 写入；系统拒绝时保留本次会话内存值并显示原因。
- Cursor 实验模式不存储任何 Cursor 凭据：每次刷新仅只读取得 access token，在内存中请求后释放；绝不读取 refresh token。
- 配置导出不包含上述秘密，也不包含 SSH 私钥、密码、订阅 URL 或登录 Cookie。
- 应用通过系统声明与运行时检测保持单实例，避免多个进程同时争用保险库。

## 专注声音与网络媒体

- 默认不播放；只在用户点击后连接公开 CC0 录音流。
- 工作音乐与网络广播只读取 Radio Browser 第三方公开目录；只接受 HTTPS MP3/AAC/HLS，不为兼容 HTTP 电台放宽 ATS。
- 不需要账户、Cookie 或 Token，不读取 Apple Music、Spotify、QQ 音乐、网易云音乐凭据、收藏或历史，不建立持久离线缓存。
- 声音卡显示作者、许可和来源页；停止、退出或定时结束会释放播放器。
- “不下载”指不建立离线音频资料库；AVPlayer 仍会产生由 macOS 管理的临时网络缓冲。
- 智能直连只绑定随机 `127.0.0.1` 端口和会话随机路径；只接受当前选择的公共 HTTPS MP3/AAC，拒绝 localhost、私网、链路本地、userinfo、HTTP 降级和不安全重定向。
- 直连中转不修改 Clash、PAC、系统代理、DNS 或证书；停止、换台和退出会关闭监听与上游请求。HLS 在完成安全播放列表改写前不进入直连回退。

## SSH

- 复用系统 `/usr/bin/ssh`、`~/.ssh/config` 与 ssh-agent；PulseDock 不保存远程认证材料。
- 自动探测使用固定只读命令，不写远端 shell 配置、systemd 环境、IDE 启动器或全局代理。
- 启动命令仅在逐台显式启用后读取，并对 Token、密钥、密码和用户目录脱敏。
- 诊断复制内容必须经过长度限制与秘密过滤。
- stdout/stderr 在 SSH 运行期间排空并限长；远端文本按不可信输入处理，重复键、超长字段、非法 UTF-8、极值和缺失 marker 不得终止应用。
- 局域网/VPN 网络条件不满足属于预期离线，不触发飞书；网络变化宽限后仍需连续失败才告警。

## 本机活跃统计

- 只保存应用名称、bundle identifier 和有效时长。
- 不读取窗口标题、浏览器 URL、聊天内容、剪贴板或项目文件。

## 第三方数据

- Codex Runway 社区重置信号必须标为第三方，不代表 OpenAI 官方承诺。
- Codex 官方额度和 Token 活动只通过本机 `codex app-server` 读取；PulseDock 不消费重置券、不自行刷新 OAuth、不写回认证文件。
- Codex Runway 采用 AGPL-3.0。PulseDock 只参考功能概念与信息层级，禁止复制其源码、OAuth 客户端、实质性 UI、资产、翻译或测试夹具。
- 天气、节假日、飞书、DeepSeek 等数据必须在界面标明来源和更新时间。
- Cursor 本地额度与 GLM Coding Plan 用量必须标注数据源类型；Cursor 不是官方个人 API，GLM 用量查询不得借由模型补全请求产生套餐消耗。
- Clash Verge Unix Socket 只允许已知的本机固定路径；不得把用户输入的任意 socket 路径传给外部命令，也不得在命令行或日志中携带 Controller Secret。

## 报告问题

提交诊断截图或日志前，请确认其中没有 SSH 主机真实地址、用户名、Webhook、API Key、订阅地址和未脱敏命令。
