# Spec 0017：客户验收脚本的 Windows 输出与隐私契约

- 状态：Proposed
- 跟踪 Issue：[#17](https://github.com/Wdfccblcf/windows-ai-workstation-service/issues/17)
- 基线：`origin/main@1defea135c70f04ab6645f1a12ed4bfe199e831c`
- 计划实现：独立 Impl PR，基于本 Spec PR 合并后的最新 `origin/main`

## 1. 问题与证据

`tools/acceptance.ps1` 是 README 提供给客户最终交付使用的真实验收脚本。它会创建临时 Git 仓库、Python 虚拟环境和 Node 脚本，检查 AI CLI，生成 JSON 与 Markdown 验收单，并用退出码表达总体状态。

当前 Quality workflow 不执行该脚本。2026-07-18 在 Windows PowerShell 5.1 上对 Standard / Codex 场景做无网络基线实跑，得到：

- 退出码 0；
- `schemaVersion=1.0`；
- 4 个结果 ID：`git-init`、`python-venv`、`node-script`、`ai-cli-status`；
- `acceptance.json` 与 `acceptance-report.md`；
- 无 `acceptance-error.log` 和 `work-*` 残留。

这些只是手工证据。结果顺序、字段、总体状态、退出码、临时目录清理、Git 全局配置不变性和输出隐私都没有自动回归保护。

## 2. 目标

1. 在 Windows PowerShell 5.1 中真实执行 Standard 验收路径。
2. 固定与机器安装状态无关的 JSON、Markdown、结果顺序、退出码和清理契约。
3. 接受 Git、Python、Node 与 Codex 是否可用造成的状态差异，不要求 runner 全绿。
4. 证明验收输出不包含测试密钥、完整用户资料路径或足够长的用户名。
5. 证明脚本执行前后用户级 Git 配置文件的存在性与字节哈希不变。
6. 将契约接入 Quality 的 Windows job，让每个 PR 和 `main` push 自动执行。

## 3. 非目标

- 不修改 `tools/acceptance.ps1` 的业务判断、消息、超时、套餐或 Docker 行为。
- 不运行 Full 套餐、Docker 引擎、测试容器或 `-AllowNetworkPull`。
- 不安装软件、不调用网络 API、不创建或使用真实 API Key。
- 不固定当前机器 4 项的 pass/fail 分布。
- 不修改站点、下载文件、检测器 ZIP、根目录体检脚本或 Pages workflow。

## 4. 执行边界

新增 `tests/acceptance-contract.test.ps1`，并兼容 Windows PowerShell 5.1：

1. 从 `$PSScriptRoot` 解析仓库根与 `tools/acceptance.ps1`。
2. 在系统临时根目录下生成 `windows-ai-acceptance-contract-<32 hex GUID>`。
3. 设置进程级假 `OPENAI_API_KEY` 与 `ANTHROPIC_API_KEY` sentinel。
4. 使用 `$PSHOME\powershell.exe -NoProfile -ExecutionPolicy Bypass` 启动子 PowerShell。
5. 参数固定为 `-Package Standard -AiCli Codex -OutputPath <temp>`，不得传 `-AllowNetworkPull`。
6. 捕获并抑制子进程 stdout/stderr，避免 runner 的环境信息进入 CI 日志。
7. 在 `finally` 中恢复两个环境变量并执行带绝对路径、系统临时根和 GUID 前缀三重校验的递归清理。

测试不得在仓库根、当前目录或用户资料目录写验收输出。

## 5. 输出目录契约

子进程退出 0 或 1 后，临时输出根必须恰好包含两个普通文件：

1. `acceptance.json`
2. `acceptance-report.md`

不得存在：

- `acceptance-error.log`；
- `work-*` 目录；
- `.git`、`.venv`、`smoke.py` 或 `smoke.js`；
- 任何其他文件、目录或重解析点。

这同时证明 `SessionRoot` 已被生产脚本清理。测试自己的 `finally` 只负责在断言完成或失败后删除整个契约临时根。

## 6. JSON 契约

`acceptance.json` 必须满足：

- `schemaVersion="1.0"`；
- `generatedAt` 可解析为 `DateTimeOffset`；
- `package="Standard"`；
- `aiCli="Codex"`；
- `overallStatus` 只允许 pass/warn/fail/blocked；
- `note` 是非空字符串；
- `results` 恰好 4 项，ID 与顺序严格为：
  1. `git-init`
  2. `python-venv`
  3. `node-script`
  4. `ai-cli-status`
- 每项必须有非空字符串 `id`、`label`、`status`、`message`；
- 每项 `status` 只允许 pass/warn/fail/blocked。

总体状态必须从结果按 `fail > blocked > warn > pass` 推导，不能信任脚本单独写入的值。

## 7. 退出码契约

- 推导后的 overall 为 pass：子进程必须退出 0；
- 推导后的 overall 为 warn、blocked 或 fail：子进程必须退出 1；
- 退出 2 代表脚本执行失败，契约测试必须失败；
- 其他退出码、无退出码或超时同样失败。

测试不把“runner 上 Codex 未安装导致退出 1”视为失败，只检查退出码与结构化总体状态一致。

## 8. Markdown 契约

`acceptance-report.md` 必须包含：

- Windows AI 验收单标题；
- `Standard` 套餐；
- 与 JSON 一致的总体状态；
- 恰好 4 行 pass/warn/fail/blocked 结果表格；
- 恰好 3 行未勾选的人工确认项。

报告中的 4 个结果标签和状态必须逐项对应 JSON。具体机器相关消息可以变化，但不得为空。

## 9. 隐私与 Git 配置不变性

执行前记录两个进程级环境变量并设置唯一假 sentinel。将 JSON 与 Markdown 按 UTF-8 合并后，禁止出现：

- 两个 sentinel 值；
- 完整用户资料路径；
- 当前用户名（长度至少 4 时按完整词、不区分大小写检查）。

Git 配置快照覆盖：

- `GIT_CONFIG_GLOBAL` 指定路径（若存在）；
- `<UserProfile>\.gitconfig`；
- `<UserProfile>\.config\git\config`；
- `XDG_CONFIG_HOME\git\config`（若存在）。

每个候选路径只在内存中保存规范绝对路径、存在性和 SHA256，不打印配置正文、用户名、邮箱或 credential helper。执行前后候选集合、存在性与哈希必须完全相同。

## 10. CI 与 README

在 `.github/workflows/quality.yml` 的 Windows job 中，紧随 audit privacy contract 后运行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\acceptance-contract.test.ps1
```

Ubuntu job 明确通过 `if: runner.os == 'Windows'` 跳过。workflow 继续保持 `contents: read`，不得新增 secret、权限或第三方 Action。

README 在“验收”或“发布完整性”中说明：契约接受与当前机器一致的退出 0/1，不要求 4 项全绿；测试不运行 Full/Docker、不联网、不使用真实密钥，并验证临时目录清理与用户级 Git 配置不变。

## 11. 实现与验证计划

1. 合并本 Spec PR，不夹带测试、workflow 或 README 变更。
2. 从合并后的最新 `origin/main` 创建 `agent/impl-17-acceptance-contract`。
3. 新增契约测试，使用 ASCII 源码与运行时 code point 组装必要中文断言，规避 PowerShell 5.1 无 BOM 解码问题。
4. 本地运行语法解析、验收契约、审计契约、检测器契约、`npm run check`、根路径和项目子路径 `npm test`、`git diff --check`。
5. 证明 `tools/acceptance.ps1`、`audit.ps1`、`public/`、检测器源与 Pages workflow 未进入 diff。
6. 在全新克隆中复验后创建 Draft Impl PR。
7. 等待 Quality Ubuntu/Windows 与 Pages PR build；确认 Windows runner 真实执行验收契约、Pages deploy skipped。
8. 转 Ready 并固定 head squash 合并，等待最新 `origin/main` 的 Quality 和 Pages 部署。
9. 将 run、job、退出码与清理证据回写 Issue #17。

## 12. 风险、回滚与完成定义

Python venv 会让 Windows job 增加约 20–40 秒；为避免重复成本，本轮只执行一个 Standard 场景。机器差异通过不固定状态分布来吸收，结构、隐私和退出码仍严格断言。

若 Windows runner 因环境差异失败，先检查是否暴露了真实契约缺陷；只有证明确为测试假设错误时才调整测试，不放宽隐私、清理或退出码要求。回滚只需 revert Impl 合并提交，不改写历史。

完成定义：Spec PR 与 Impl PR 均合并，Issue #17 关闭；本地和 GitHub Windows runner 均真实执行契约；PR 与主分支 Quality、Pages 均通过；用户级 Git 配置和生产验收脚本字节零变化；无网络、Docker、真实密钥或仓库内临时输出。
