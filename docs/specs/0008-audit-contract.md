# Spec 0008：只读体检器隐私与输出契约

- 状态：Proposed
- 跟踪 Issue：[\#8](https://github.com/Wdfccblcf/windows-ai-workstation-service/issues/8)
- 基线：`origin/main@3507fd8cfab7702e4e36b2328896769db865462d`
- 计划实现：独立 Impl PR，基于本 Spec PR 合并后的最新 `origin/main`

## 1. 问题与证据

现有 Quality 工作流会验证站点、下载校验和和检测器 ZIP，但不执行根目录 `audit.ps1`。因此脚本的 Strict 脱敏、19 项顺序检测、JSON/Markdown/日志/进度协议与退出码没有自动回归保护。

在 Windows 11 本机的只读基线中，脚本当前满足：

- 19 个检查；
- 21 条进度事件：start + 19 check + complete；
- `schemaVersion=1.0`、`scriptVersion=1.1.0`、`privacyMode=Strict`；
- 环境相关总体状态为 fail 时退出 1；
- 注入的两个假 API Key sentinel 未出现在任何输出；
- 不执行下载、修复、提权或系统配置修改。

这些是手工证据，无法阻止后续 PR 破坏契约。

## 2. 目标

1. 在 Windows CI 中真实执行 Strict 体检器。
2. 锁定与机器安装状态无关的结构、顺序、汇总、进度与退出码契约。
3. 使用明确的假 sentinel 证明输出不包含密钥值或完整用户资料路径。
4. 让测试在开发者工作站与 GitHub Windows Runner 上都稳定，不要求具体检查结果全绿。

## 3. 非目标

- 不修改 `audit.ps1` 的 19 项业务逻辑、阈值、建议或状态优先级。
- 不固定某台机器的 pass/warn/fail/blocked 分布。
- 不使用真实 API Key，不调用任何付费 API。
- 不执行联网下载、Docker 拉取、管理员操作、修复、PATH 或注册表变更。
- 不改造 `tools/acceptance.ps1`、检测器 GUI、ZIP 或站点。

## 4. 进程与临时目录

新增 `tests/audit-contract.test.ps1`，兼容 Windows PowerShell 5.1：

1. 在系统临时目录下生成 `windows-ai-audit-contract-<GUID>`，不在仓库写审计输出。
2. 保存当前 `OPENAI_API_KEY` 与 `ANTHROPIC_API_KEY` 的进程级值。
3. 设置两个非真实 sentinel；子 PowerShell 继承它们。
4. 用 `powershell.exe -NoProfile -ExecutionPolicy Bypass -File audit.ps1 -OutputPath <temp> -PrivacyMode Strict` 执行。
5. 不把子进程的报告正文或环境值写到 CI 日志。
6. 在 `finally` 中恢复原环境变量。
7. 只在解析后的绝对路径位于系统临时根目录、且目录名匹配固定 GUID 前缀时递归删除。

sentinel 必须明显是测试值，并且测试失败消息只指出文件名，不回显 sentinel 本身。

## 5. 固定检查序列

`audit.json.checks[*].id` 必须严格等于以下顺序，不能缺失、重复或交换：

1. `system-os`
2. `hardware-summary`
3. `disk-system`
4. `path-health`
5. `tool-git`
6. `tool-python`
7. `tool-uv`
8. `tool-node`
9. `tool-npm`
10. `path-conflict-git`
11. `path-conflict-python`
12. `path-conflict-node`
13. `tool-editor`
14. `platform-wsl`
15. `platform-docker`
16. `platform-compose`
17. `ai-cli`
18. `mcp-status`
19. `api-key-presence`

每项必须具有非空 `id`、`category`、`label`、`message`、`recommendation`，具有字符串 `detectedVersion`，且 `status` 只能是 pass/warn/fail/blocked。

## 6. JSON 与退出码契约

- 输出目录必须恰好包含 `audit.json`、`audit-report.md`、`audit.log` 与 `audit-progress.jsonl`。
- `schemaVersion=1.0`、`scriptVersion=1.1.0`、`privacyMode=Strict`。
- checks 必须是第 5 节的 19 项。
- summary 的 pass/warn/fail/blocked 必须等于实际状态计数，总和为 19。
- overallStatus 必须按 `fail > blocked > warn > pass` 从 checks 推导。
- overallStatus=pass 时子进程退出 0；其他合法 overallStatus 时退出 1；退出 2 永远失败。
- `api-key-presence` 的 message 必须包含两个测试变量名及“存在”状态，但不得包含变量值。

## 7. 进度事件契约

`audit-progress.jsonl` 必须恰好 21 行且每行是独立有效 JSON：

- 第 1 行：event=start、sequence=0、total=19、percent=0。
- 第 2–20 行：event=check；sequence=1–19；id 和 status 与同位置 check 一致；total=19；percent 单调不减并等于 `min(100, round(sequence / 19 * 100))`。
- 第 21 行：event=complete、sequence=19、total=19、percent=100、status=overallStatus。
- 每项 `schemaVersion=1.0` 且 timestamp 可解析为日期时间。
- check 事件的 category 与 label 必须对应 `audit.json`。

## 8. 报告、日志与隐私契约

- Markdown 必须包含体检报告标题、总体状态、汇总和隐私提示。
- Markdown 状态结果行必须恰好 19 行。
- 日志必须包含脚本开始、19 个检查结果和完成记录。
- 将 4 个输出按 UTF-8 文本合并检查，禁止出现：
  - 两个 sentinel 值；
  - 当前完整 UserProfile（非空时，忽略大小写）；
  - 当前用户名（非空且长度足以避免误报时，按完整词忽略大小写）。
- 允许出现环境变量名称、`<USERPROFILE>`、`<USER>`、`<REDACTED>` 与“存在/不存在”。

## 9. CI 与本地命令

在现有 Quality 工作流的 Windows job 中，检测器发布契约之后运行：

    powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\audit-contract.test.ps1

Ubuntu job 跳过，因为脚本读取 Windows CIM、WSL 与 Windows 工具状态。

README 必须说明：测试接受环境相关的退出 0 或 1，只验证二者与 overallStatus 一致；它不要求当前机器 19 项全部通过。

## 10. 实现计划

1. 从 Spec PR 合并后的最新 `origin/main` 创建 `agent/impl-8-audit-contract`。
2. 实现安全的子进程、环境恢复和临时目录清理。
3. 实现第 5–8 节断言，错误消息只输出契约名称与文件名。
4. 更新 Windows CI 与 README。
5. 运行 PowerShell 5.1 语法解析、审计契约、检测器契约、`npm run check`、`npm test` 和 `git diff --check`。
6. 证明 `audit.ps1`、`public/downloads/*` 与页面源未进入 diff。
7. 推送 Draft Impl PR，等待 Windows/Ubuntu 结果后再合并并关闭 Issue #8。

## 11. 验证矩阵

| 场景 | 期望 |
|---|---|
| 当前工作站 Strict 体检 | 契约通过，具体状态分布可变 |
| GitHub Windows Runner Strict 体检 | 契约通过，具体状态分布可变 |
| 任一 sentinel 或完整用户资料路径出现在输出 | 失败且不回显敏感值 |
| 检查缺失、重复、乱序或字段无效 | 失败 |
| summary、overallStatus 或退出码不一致 | 失败 |
| progress 数量、顺序、ID、percent 或状态不一致 | 失败 |
| 成功或断言失败 | 环境变量恢复，临时目录安全清理 |

## 12. 完成定义

Spec PR 与 Impl PR 均合并；Issue #8 自动关闭；Windows Runner 真实执行并通过审计契约；Ubuntu 原有检查通过；最新 `origin/main` 本地复验通过；核心脚本、ZIP、下载哈希和站点行为零变化。
