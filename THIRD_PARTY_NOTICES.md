# PulseDock 第三方来源与 clean-room 说明

更新日期：2026-08-25

## Codex Runway 研究边界

PulseDock 6.5.0 在产品研究阶段查看了 [Licoy/codex-runway](https://github.com/Licoy/codex-runway)。该项目采用 AGPL-3.0 许可证。PulseDock 只参考“多个额度窗口应分开呈现、活动统计与社区事件应分层”等产品问题，不复制其 Swift 源码、界面、文案、OAuth/多账户流程、资产、翻译或测试夹具。

PulseDock 的个人 Codex 额度与 Token 活动根据 OpenAI 官方 Codex app-server 的公开协议独立实现：

- [Codex app-server README](https://github.com/openai/codex/blob/main/codex-rs/app-server/README.md)
- [Codex app-server v2 schema](https://github.com/openai/codex/blob/main/codex-rs/app-server-protocol/schema/json/codex_app_server_protocol.v2.schemas.json)

实现只启动短生命周期本机 `codex app-server`，调用 `account/rateLimits/read` 与 `account/usage/read`；不读取、刷新或导出登录 Token，不消费重置券，也不实现 Runway 的多账户/OAuth 功能。

Codex Runway 的公共 `status.json` 仅作为明确标注的第三方社区事件源，不参与个人额度计算，不构成 OpenAI 承诺，也不用于推测未来重置时间。

## 网络音频

- 环境音：24 条固定、互不重复的 Freesound CC0 作品预览流。每条记录都保留 provider-qualified source ID、作者、作品页、CC0 许可页、标签、时长和最后核验日期；完整清单见 [AMBIENT_SOUND_CATALOG.md](AMBIENT_SOUND_CATALOG.md)。
- 2026-08-25 对 24 个作品页逐项确认 CC0，并只对预览地址执行一字节 Range 请求；当时均返回 HTTP 206 与 `audio/mpeg`。该检查只证明核验当日可访问，不保证第三方 CDN 永久在线。
- PulseDock 不把 Freesound 预览打包进应用，不在后台预取，也不建立离线资料库；只有用户点击播放后才连接对应 HTTPS 预览流。CC0 不强制署名，但仍在应用和清单中保留作者及作品页，便于审计和尊重创作者。
- 工作音乐与网络广播目录：[Radio Browser](https://www.radio-browser.info/) 公共目录。Radio Browser 只提供目录，不授予各电台节目内容的版权或地区播放许可。
- PulseDock 只接受 HTTPS MP3/AAC/HLS 流，默认不播放、不自动恢复、不下载、不保存播放历史。
- 搜索目录时，查询词会发送给 Radio Browser；点击播放后，音频提供方会收到正常网络请求并可看到公网出口 IP。

本版没有接入 Apple Music、Spotify、QQ 音乐、网易云音乐账号，没有读取这些服务的 Cookie、收藏或播放历史；也没有硬编码 SomaFM 直链或使用 Jamendo 测试 Client ID。

## PulseDock 自身许可证

仓库当前尚未选择 PulseDock 自身的开源许可证。对外公开 GitHub 仓库前，应由项目所有者明确选择许可证；本说明不替代许可证文件。
