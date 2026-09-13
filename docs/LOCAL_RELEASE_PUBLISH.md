# PulseDock 本地验收与一键发布

此流程只用于 PulseDock 开发仓库，不能从已安装的 `PulseDock.app` 内执行。脚本不保存 GitHub Token，也不拥有更新私钥；GitHub Actions 才拥有 `PULSEDOCK_UPDATE_PRIVATE_KEY_BASE64`，用于生成更新清单签名。

## 前置条件

1. 在 macOS 开发机登录执行发布的 GitHub 账号：

   ```sh
   scripts/github_login.sh
   gh auth status -h github.com
   ```

2. 进入**本仓库根目录**，而不是 `outputs/`、App 包或其他项目：

   ```sh
   cd "/Users/adminmima0000/Nutstore Files/我的坚果云/pulsedock"
   git remote -v
   ```

   远端应为 `asfx0412/PulseDock`；当前分支应是准备发布的 PulseDock 代码。

3. 安装 Xcode Command Line Tools，并确保 `swift`、`codesign`、`ditto`、`git`、`gh` 可用。GitHub 仓库 Actions Secret `PULSEDOCK_UPDATE_PRIVATE_KEY_BASE64` 必须已配置；私钥绝不能出现在终端历史、仓库、`.env` 或 App 中。

4. 版本文件、Info.plist、发布说明和测试报告必须一致：

   ```sh
   cat VERSION
   /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist
   ls "outputs/PulseDock-$(tr -d '[:space:]' < VERSION)发布说明.md" \
      "outputs/PulseDock-$(tr -d '[:space:]' < VERSION)测试报告.md"
   ```

5. 在运行脚本前审阅工作树。脚本拒绝已暂存改动、敏感文件和验收后被修改的文件；普通未跟踪文件及有意删除的文件会被列入发布清单，并仅在最终键入版本号确认后一起提交。这样新服务代码、发布脚本、测试和本版本文档可一键纳入发布，而历史 `outputs` 删除仍会显式展示给你确认。

   ```sh
   git status --short
   git diff --check
   ```

## 只做本地验收

先完成真机交互测试，再在仓库根目录执行：

```sh
scripts/prepare_local_release.sh 6.15.3
```

该命令会运行确定性测试和 arm64 构建，验证 ZIP、签名、版本、发布说明、测试报告和改动清单，并生成：

```text
.build/release-ready-6.15.3.json
```

它不会提交、push、创建 tag、访问 GitHub 或发布 Release。修改源码、版本、发布说明或 ZIP 后，必须重新执行此步骤。

## 明确的一键发布

仅在本地安装试用、人工验收和上述准备均通过后执行：

```sh
scripts/prepare_local_release.sh 6.15.3 --publish
```

脚本会要求再次键入完整版本号。确认后才会：

1. 再次检查本地验收快照仍匹配当前工作树，并显示新增、修改、删除的完整发布清单；
2. 用当前 `gh auth` 登录身份提交本次批准文件（包括已确认的新文件和删除），创建并推送 `v6.15.3`；
3. 等待 GitHub Actions 重新构建、签名 manifest 并创建 Release；
4. 从公开 Release 下载 ZIP 和 manifest，使用 App 内置公钥复验 Ed25519 签名和 SHA-256；
5. 将 Release URL、资产和验证时间写入 `.build/release-result-6.15.3.json`。

如果 tag 已存在、凭据过期或不匹配、Actions Secret 缺失、工作流失败、公开资产无法验签，脚本会停止并报告原因，不会将失败伪装成已发布。

## 自动更新回归

发布后，以隔离副本而非日常 App 验证升级：

1. 将上一个 Release 解压到 `/Applications/PulseDock Update Test.app`，确认父目录可写；
2. 启动旧版，在菜单栏选择“检查更新…”，确认显示新版本说明；
3. 确认下载，检查旧 App 被替换、重启成功并显示新版本；
4. 如需再次测试，以旧 Release ZIP 手动恢复隔离副本。更新器只升级到更高版本，不自动降级。
