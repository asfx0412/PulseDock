# PulseDock 文档维护规范

## 文档职责

| 文档 | 职责 | 版本信息规则 |
|---|---|---|
| `README.md` / `README.en.md` | 产品首页、目标用户、安装、核心边界 | 只链接 Latest Release 和动态徽章；不手写当前版本或本版 ZIP 名 |
| `CHANGELOG.md` | 已发布版本的变更历史 | 每个版本一个条目，和 Release notes 一致 |
| `outputs/PulseDock-<版本>发布说明.md` | 某个版本的用户可读 Release notes | 仅描述该版本，含最终 ZIP SHA-256 |
| `outputs/PulseDock-<版本>测试报告.md` | 某个版本的验证证据 | 仅记录该版本的实际测试 |
| `outputs/PulseDock使用文档.md` | 完整配置与排障说明 | 说明当前行为，不承担发布公告 |
| `docs/PRODUCT_MESSAGING.md` | 对外定位、卖点和表述边界 | 不声明未发布能力 |

## 每次发布前

1. 更新 `VERSION`、`Resources/Info.plist`、`CHANGELOG.md`、发布说明和测试报告；
2. 更新实际界面截图，或移除带旧版本号的截图；
3. 运行 `./scripts/check_docs.sh` 和 `./scripts/test.sh`；
4. 让一位未参与实现的人按 README 从 Release 安装一次；
5. 检查中英文 README 的功能、限制、安装与隐私边界是否对等；
6. 只在 GitHub Release 中发布对应 ZIP、清单和本版说明，README 不复制本版公告。

## 每月维护

- 检查 README、使用文档和社媒置顶内容是否仍与 Latest Release、支持平台和签名/公证状态一致；
- 检查外部链接、数据源、安装步骤和截图；
- 将真实用户问题转为可复现的 Issue 或 `BACKLOG.md` 条目，并在修复后关联 Release；
- 复审公开截图、日志、诊断样例是否暴露主机、用户名、IP、余额、位置或任何秘密；
- 不因“看起来过时”直接删除历史 Release 证据；仓库清理与 GitHub Release 存档应在独立变更中完成。

## 修改准则

- README 的承诺必须能被当前公开版本验证；
- 技术限制应靠近安装或相关功能出现的位置，不能只藏在文末；
- 同一事实只有一个权威来源，其他文档链接过去；
- 文档修复使用独立提交，避免与二进制发布或无关功能混在一起；
- 修改后至少执行 Markdown 链接/版本检查，并审阅 GitHub 渲染效果。
