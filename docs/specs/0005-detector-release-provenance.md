# Spec 0005：检测器发布包来源与内部契约

- 状态：Proposed
- 跟踪 Issue：[\#5](https://github.com/Wdfccblcf/windows-ai-workstation-service/issues/5)
- 基线：`origin/main@9e4daf3e4daf37ed957b31d4e6872ec55d8b30a7`
- 前置规格：[Spec 0002](./0002-cross-platform-release-integrity.md)
- 计划实现：独立 Impl PR，基于本 Spec PR 合并后的最新 `origin/main`

## 1. 问题与证据

当前自动化会重新计算公开 ZIP 的外层 SHA256，但不会检查 ZIP 内实际执行的代码。`windows-ai-detector-release-v1.0.2.zip` 包含 7 个条目，其中 `scan-app.ps1`、`verify-package.ps1`、`Start-Windows-AI-Scan.cmd` 与包内 README 在仓库源码树中没有对应文件。

因此，只要同时替换 ZIP 和外层哈希，现有测试仍可能通过；普通 PR diff 无法显示检测器外壳、启动器或包内校验器是否新增了联网、提权、修复或额外可执行内容。

已确认的 v1.0.2 内容：

| ZIP 条目 | 现有来源 | SHA256 |
|---|---|---|
| `audit.ps1` | 根目录与公开下载脚本 | `872f2dd7…c7202a2` |
| `scan-app.ps1` | 仅 ZIP | `112ee05d…2f483` |
| `verify-package.ps1` | 仅 ZIP | `0d130744…2549` |
| `Start-Windows-AI-Scan.cmd` | 仅 ZIP | `34c2eb3a…52f` |
| `README.md` | 仅 ZIP | `cb85189a…e2863a1` |
| `release.json` | 仅 ZIP | `3e8d5e20…806c55` |
| `SHA256SUMS.txt` | 包内生成清单 | 不自校验 |

包内 `release.json` 还声明 `testSummarySha256=1e672f9a…bd2f` 与 `18/18 passed`，但对应详细摘要不在仓库、ZIP 或现有工作区中。该事实必须被记录，不能通过推测补造证明。

## 2. 目标

1. 让客户真正执行的人工维护代码可以在 GitHub PR 中直接审查。
2. 让 CI 证明当前 ZIP 的条目全集、源映射、内部哈希、安全元数据和自检结果满足固定契约。
3. 保持 v1.0.2 ZIP、外层哈希、下载 URL、页面和运行行为完全不变。
4. 明确哪些结论可由当前仓库验证，哪些只是不可追溯的历史元数据。

## 3. 非目标

- 不重新打包、重发或改名 v1.0.2。
- 不修改 WinForms UI、19 项检测逻辑、退出码、权限或网络行为。
- 不恢复、推测或伪造缺失的 18/18 详细测试摘要。
- 不在本项中实现下一版本的确定性打包器或代码签名。
- 不改变 GitHub Pages 部署或站点可访问性结构。

## 4. 来源映射

新增 `detector/releases/v1.0.2/`：

- `scan-app.ps1`：ZIP 同名条目的规范源；保留 UTF-8 BOM 与 LF。
- `verify-package.ps1`：ZIP 同名条目的规范源；保留 UTF-8 BOM 与 LF。
- `Start-Windows-AI-Scan.cmd`：ZIP 同名条目的规范源；LF。
- `README.md`：ZIP 同名条目的规范源；LF。
- `release.json`：历史元数据的可审查快照；测试比较 JSON 语义，不把行尾当作产品契约。
- `PROVENANCE.md`：记录 ZIP 外层哈希、条目映射、验证命令和历史证明缺口。

不复制 `audit.ps1`。其规范源仍是根目录 `audit.ps1`，并要求与 `public/downloads/audit.ps1` 及 ZIP 条目逐字节一致。

不复制包内 `SHA256SUMS.txt`。它是派生清单，由契约测试解析并逐项复算。

## 5. 契约测试

新增 `tests/detector-release.test.ps1`，兼容 Windows PowerShell 5.1，且只读取仓库文件、只在系统临时目录创建可清理副本。

### 5.1 ZIP 结构

- 条目集合必须精确等于 7 个预期名称。
- 不允许目录、重复名称、绝对路径、`..` 或反斜杠路径变体。
- 不允许 `Start-Repair-App.cmd`、额外脚本、二进制程序或其他未批准条目。

### 5.2 源与字节

- ZIP 内 `audit.ps1`、根目录脚本与公开下载脚本必须逐字节一致。
- ZIP 内 scanner、verifier、CMD 与 README 必须与版本化源逐字节一致。
- `release.json` 必须与快照在解析后的 JSON 语义上相等。
- 当前公开 ZIP、主清单及独立 ZIP 校验文件的已发布哈希不得改变。

### 5.3 包内清单

- 每行必须是 64 位小写十六进制、两个空格和安全相对文件名。
- 必须恰好覆盖除清单自身外的 6 个条目。
- 重复、缺失、意外、越界或格式错误条目必须失败。
- 每个声明哈希必须等于 ZIP 内相应条目的实际字节哈希。

### 5.4 安全元数据

- `schemaVersion` 必须为 `1.0`。
- `releaseType` 必须为 `detection-only`。
- `version` 必须与文件名 `1.0.2` 一致。
- `supportedOS` 必须仅包含 `Windows 11`。
- `repairIncluded` 与 `administratorPermissionRequested` 必须为 `false`。
- `testSummarySha256` 只验证为历史快照中的 64 位哈希；不得将其解释为当前可复核摘要。

### 5.5 自检

- 将 ZIP 解压到唯一临时目录。
- 运行 `scan-app.ps1 -SelfTest -DetectionOnly`，要求退出码为 0 且输出明确的 `SELFTEST PASS`。
- 自检不得加载 GUI、请求管理员权限、联网或写入仓库。
- 无论成功失败都在 `finally` 中清理临时目录。

## 6. CI 与文档

- 在现有 Quality 工作流的 Windows job 中增加检测器契约步骤。
- Ubuntu job 保持现有 Node/站点测试，不执行 Windows GUI 外壳。
- README 增加源快照位置和本地命令：

      powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\detector-release.test.ps1

- `PROVENANCE.md` 必须明确：可验证的是当前 ZIP 内容、哈希、安全字段与自检；缺失的历史 18/18 详细摘要不可验证。

## 7. 实现计划

1. 从本 Spec PR 合并后的最新 `origin/main` 创建 `agent/impl-5-detector-provenance`。
2. 从已发布 ZIP 提取并核对 5 个源/元数据快照，保留规定的 BOM 与行尾。
3. 实现只读 PowerShell 契约测试与临时目录清理。
4. 更新 Windows CI 与 README。
5. 运行 PowerShell 语法解析、检测器契约测试、`npm run check`、`npm test` 与 `git diff --check`。
6. 证明 ZIP、外层校验文件和页面源均未进入 diff。
7. 推送 Draft Impl PR，等待 Windows/Ubuntu 检查后再合并并关闭 Issue #5。

## 8. 验证矩阵

| 场景 | 期望 |
|---|---|
| 当前 v1.0.2 ZIP | 契约测试通过 |
| 增加或删除 ZIP 条目 | 失败 |
| 更改 scanner/verifier/CMD/README 任一字节 | 失败 |
| 更改包内 audit 或规范源 | 失败 |
| 包内清单重复、缺项、多项或哈希错误 | 失败 |
| 启用修复、提权或非 Windows 11 支持 | 失败 |
| 解压后 GUI 外壳自检 | 退出 0，输出 `SELFTEST PASS` |
| Windows GitHub Actions | 站点测试与检测器契约均通过 |
| Ubuntu GitHub Actions | 现有站点测试通过 |

## 9. 发布、回滚与完成定义

本项不发布新产品字节；合并后只增加透明源码、测试和文档。若契约测试误报，应修复测试或来源映射，不得通过放宽条目全集、安全字段或字节比较恢复绿色。

完成要求：Spec PR 与 Impl PR 均合并；Issue #5 自动关闭；Windows/Ubuntu 均通过；最新 `origin/main` 本地复验通过；已发布 ZIP 和外层哈希与基线完全一致。
