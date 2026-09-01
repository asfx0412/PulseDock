# PulseDock 6.14.0 测试报告

测试日期：2026-09-01

## 自动化结果

- `./scripts/test.sh`：通过。
- 新增 `Version614ReliabilitySelfTest`：通过，覆盖 30/120/600 秒退避、Codex/天气旧值保留、Cursor 两项设置明细与工作台综合剩余摘要。
- `PULSEDOCK_SKIP_TESTS=1 ./scripts/build.sh`：通过。
- Release：arm64、ad-hoc 代码签名、ZIP 完整性、解包后签名和本地化资源校验均通过。

## 已知人工/在线验证项

- 需用新版 Codex app-server 实机验证 3–8 秒初始化延迟、自动恢复与 popover 交互。
- 需在真实 DNS/TLS/代理失败后观察 30 秒、2 分钟、10 分钟自动重试。
- 需核验 GitHub Actions Secret、公钥配对、签名清单与 6.13.2→6.14.0 在线升级/回滚；该项未完成则阻断自动更新正式发布。

## 构建产物

- `PulseDock-6.14.0.zip`
- SHA-256：`c526a32298ae6d52c9fc4cd380381ad96db87d2eac66938e92f35f83bd920788`
