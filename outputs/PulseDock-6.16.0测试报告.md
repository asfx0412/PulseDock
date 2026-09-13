# PulseDock 6.16.0 测试报告

日期：2026-09-13。发布前本地验证。

## 已完成的自动验证

- 完整 `./scripts/test.sh` 已通过，包括文档一致性检查，以及 6.0、6.2、6.4、6.6、6.8、6.9、6.12、6.13、6.14、6.14.1、6.15、6.16 社区重置信号、远程探测调度和 Clash 控制器验证。
- `git diff --check` 已通过。
- `PULSEDOCK_SKIP_TESTS=1 ./scripts/build.sh` 已成功完成。产物通过 arm64 检查、代码签名严格校验、ZIP 解包校验与本地化资源校验。
- 生成产物：`outputs/PulseDock.app` 与 `outputs/PulseDock-6.16.0.zip`。
- ZIP SHA-256：`6ec3c5cb086ab1c6acd537ecc2740becb3b136885fbb1b10b57cb6ed4948e6a8`。

## Touch ID 回归

- 已定位并修复首次指纹解锁后显示 `OSStatus -34018` 的问题：ad-hoc 签名没有 Apple Team Keychain access-group，不能创建 `.userPresence` 数据保护钥匙串项。
- Touch ID 新保险库路径不会读取、迁移或删除旧 v1 登录钥匙串；因此不会出现旧钥匙串密码框。
- 用户已确认当前 Touch ID 解锁逻辑可用。无指纹、未录入或被系统锁定时，允许 macOS 登录密码作为系统级回退；取消指纹认证不自动回退。

## 发布前仍需人工确认

1. 完全退出旧 App 后替换为本次 `PulseDock.app`，确认显示 `v6.16.0`。
2. 在存在旧登录钥匙串项的机器上选择“Touch ID 新保险库”，确认点“解锁凭据”后出现 Touch ID 而不是旧钥匙串密码框；重新填写密钥并保存，锁定后再次解锁验证。
3. 在没有 Touch ID、未录入 Touch ID 或系统锁定指纹的设备上，验证 macOS 密码回退及取消认证提示。
4. 对已启用的 Clash 自动订阅更新，确认它按设置间隔触发 provider 刷新；未启用时不应刷新订阅。
5. 使用测试用飞书 Webhook 验证仅社区重置信号可发送，设备/SSH/网络/温度事件不外发；避免在公开仓库、终端记录或发布附件中包含真实密钥。
6. 如需验证自动更新，用上一个公开版本安装到可写的隔离测试副本，在旧版菜单栏选择“检查更新”，确认下载、替换、重启和新版本号。

## 已知构建提示

- 编译器会提示 `CLGeocoder` 和 `kSecUseAuthenticationUIFail` 在新 macOS SDK 中已弃用；这是现有兼容路径的警告，不影响本次构建、签名或 ZIP 校验。后续可迁移至 MapKit 反向地理编码及纯 `LAContext.interactionNotAllowed` 路径。
