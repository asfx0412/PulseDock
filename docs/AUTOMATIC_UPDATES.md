# 免费自动更新发布流程

PulseDock 的更新包使用 Ed25519 签名，而不依赖 Apple Developer ID。客户端只接受由发布私钥签出的 GitHub Release 清单，并在下载后校验 SHA-256；因此 GitHub 账号、网络链路或下载地址被篡改时，更新不会安装。

## 首次配置（只做一次）

1. 在本机项目目录运行 `swift scripts/generate_update_key.swift`。
2. 将输出的 **Public key** 填入 `Sources/PulseDock/Services/AppUpdateService.swift` 的 `AppUpdateConfiguration.publicKeyBase64`，并提交该公钥。必须以独立签名/验签 fixture 验证配对，不能仅凭 Secret 存在就视为可发布。
3. 在 GitHub 仓库的 **Settings → Secrets and variables → Actions** 新建 secret：`PULSEDOCK_UPDATE_PRIVATE_KEY_BASE64`，值为输出的 **Private key**。
4. 私钥只保存在你受控的密码管理器与 GitHub Actions secret，绝不能提交、写入 Issue、聊天或 Release 附件；若泄漏，立即重新生成一对密钥并发一个使用新公钥的常规版本。

## 发布

1. 将 `VERSION`、`Resources/Info.plist` 和更新日志调整为同一版本号。
2. 提交并推送代码，创建与版本严格匹配的 tag，例如 `v6.14.0`。
3. GitHub Actions 构建 ZIP、生成 `latest-macos-arm64.json`、为其签名，并上传到该 Release；签名覆盖版本、固定下载地址、SHA-256、发布时间和发布说明，Release 也使用同一份说明。
4. 已安装 App 每 **2 小时**检查一次；菜单栏也可通过“检查更新…”立即检查。下载后会校验签名、SHA-256、Bundle ID、版本、arm64 与代码签名；新版必须启动确认，否则恢复旧 App。

## 分发边界

这条路线不需要 Apple Developer Program，但并不会消除 Gatekeeper 对未公证 App 的首次启动提示。更新签名只保障“更新来自持有私钥的发布者且包未被篡改”；它不等同于 Apple 的 Developer ID 或公证信任。

客户端更新源固定为 `asfx0412/PulseDock` 的 GitHub Releases，且只接受严格匹配 `v<版本>/PulseDock-<版本>.zip` 的 HTTPS `github.com` 下载地址。只有仓库公开，或改为提供客户端可认证访问的专用测试分发源时，普通已安装 App 才能实际下载更新。

私有仓库的 Release 下载需要 GitHub 登录权限；普通 App 不携带 GitHub Token，因此私有内测 Release 不能宣称在线自动更新可用。Secret 配对、完整 Release 构建、签名反验和旧版→新版真实升级/回滚任一未通过，均禁止声明自动更新已正式发布。
