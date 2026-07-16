# Spec 0002：跨平台发布完整性

- 状态：Proposed
- 跟踪 Issue：[\#2](https://github.com/Wdfccblcf/windows-ai-workstation-service/issues/2)
- 基线：`origin/main@88df7e27e84f31df18ff70c9b7abb5b910c181ca`
- 计划实现：独立 Impl PR，基于本 Spec PR 合并后的最新 `origin/main`

## 1. 问题与证据

项目把 SHA256 校验作为公开检测器的安全边界，但发布相关文本没有声明行尾契约。Windows 系统级 Git 配置 `core.autocrlf=true` 会把 `audit.ps1` 从 LF 检出为 CRLF，从而改变发布文件的字节和 SHA256。

在全新 Windows 克隆上已复现：

- `npm ci` 与 `npm run check` 通过；
- `npm test` 共 5 项，4 项通过、1 项失败；
- `SHA256SUMS.txt` 声明 `audit.ps1` 为 `872f2dd7…c7202a2`；
- Windows 静态导出中的 `audit.ps1` 为 `20d0a242…ae809`；
- ZIP 内 LF 版本仍为 `872f2dd7…c7202a2`；
- 两个脚本忽略行尾后内容一致；
- 仓库没有 `.gitattributes`，也没有自定义 Windows/Linux 质量 CI。

现有测试还使用带固定 `\n` 的完整字符串比较清单，因此测试本身也依赖宿主换行约定。

## 2. 目标

任何维护者在受支持的开发环境中构建时，都必须得到可由随附清单验证的发布文件；Windows 与 Linux 任一平台出现字节漂移、清单漂移或测试失败，都必须在合并前被 CI 阻止。

## 3. 非目标

- 不改变 19 项检测逻辑、状态语义或退出码。
- 不新增修复、安装、网络下载、提权或遥测能力。
- 不发布新的检测器版本，不改变现有下载文件名。
- 不修改套餐、价格、案例或营销内容。
- 不把 ZIP 解包后的所有源码重构为新的发布系统；可复现打包另立 Issue。

## 4. 设计决策

### 4.1 仓库字节契约

新增 `.gitattributes`：

- PowerShell、CMD、Markdown、JSON、JavaScript/TypeScript、CSS、YAML 和 SHA256 文本清单固定为 `text eol=lf`；
- ZIP、PDF、PNG、WebP 等发布资产固定为 `-text`；
- 规则必须覆盖当前公开下载及 CI 配置。

选择 LF 是因为当前清单与 ZIP 内脚本已经以 LF 为规范字节，不需要改动既有发布资产或版本号。Windows PowerShell 5.1 可以执行 LF 脚本。

### 4.2 清单解析契约

测试不得比较整份清单字符串。实现一个局部解析函数，逐行解析 `<64 位小写十六进制><两个空格><文件名>`：

- 接受 LF 或 CRLF 作为清单行分隔；
- 忽略末尾空行，但拒绝中间空行和格式错误行；
- 拒绝重复文件名；
- 要求条目集合与预期集合完全相等，拒绝缺项与意外项；
- 对每个条目读取实际文件并重新计算 SHA256；
- 独立 ZIP 校验文件必须只有一个预期条目，且与主清单一致。

测试验证的是发布字节，不对被校验文件做换行归一化。

### 4.3 CI 契约

新增一个最小质量工作流：

- 触发：针对 `main` 的 Pull Request，以及推送到 `main`；
- 矩阵：`windows-latest`、`ubuntu-latest`；
- Node：满足仓库 `engines` 的 Node 22；
- 步骤：检出、安装 Node、`npm ci`、`npm run check`、`npm test`；
- 权限：默认只读 `contents: read`；不上传客户数据，不使用仓库密钥。

Actions 使用实现时官方仓库的当前稳定主版本，并在 Impl PR 中记录选择依据。

## 5. 功能与安全要求

1. `out/downloads/audit.ps1` 的实际 SHA256 必须等于主清单对应条目。
2. 检测器 ZIP 的实际 SHA256 必须同时等于主清单与独立 `.sha256.txt`。
3. 清单格式错误、重复、缺项、意外项或哈希错误时，测试必须失败。
4. 站点页面、公开下载 URL、19 项检测脚本内容和 ZIP 字节不得因本项改变。
5. CI 不得申请写权限、使用付费 API、执行检测脚本或收集运行器环境报告。
6. README 必须说明 LF 是发布字节契约，并给出本地 `npm run check`、`npm test` 验证命令。

## 6. 实现计划

1. 从 Spec PR 合并后的最新 `origin/main` 创建 `agent/impl-2-release-integrity`。
2. 添加 `.gitattributes` 并检查 `git diff --check`。
3. 重构 `tests/rendered-html.test.mjs` 的校验和测试，增加正向与失败场景覆盖。
4. 添加双平台 GitHub Actions 质量工作流。
5. 更新 README 的开发与发布完整性说明。
6. 在 Windows 的干净检出语义下执行全套验证；推送后以 GitHub Actions 验证 Ubuntu/Windows。
7. Impl PR 使用 `Closes #2`，附基线、根因、测试结果和零功能变更说明。

## 7. 验证矩阵

| 场景 | 期望 |
|---|---|
| Windows，`core.autocrlf=true`，`npm run check` | 通过 |
| Windows，`core.autocrlf=true`，`npm test` | 全部通过 |
| Ubuntu，`npm run check` 与 `npm test` | 全部通过 |
| 主清单任一哈希被修改 | 测试失败 |
| 主清单条目重复、缺失或新增 | 测试失败 |
| 独立 ZIP 清单与主清单不一致 | 测试失败 |
| 正常静态导出 | 页面文案和下载 URL 保持不变 |

## 8. 发布与回滚

本项只影响仓库检出规则、测试、CI 和维护文档，不改变线上功能。合并 Impl PR 后先观察双平台工作流，再让 Pages 使用更新后的 `main`。

若 CI 因平台基础设施问题无法稳定运行，可以回滚工作流提交；不得通过放宽或删除 SHA256 断言来恢复绿色状态。若 `.gitattributes` 规则造成意外文件转换，回滚相应规则并重新审计发布资产的实际字节与哈希。

## 9. 完成定义

- Issue #2 的全部验收标准有自动化或命令证据；
- Spec PR 与 Impl PR 均以 `main` 为目标且分别合并；
- Impl PR 的 Windows、Ubuntu 检查均通过；
- 合并后的最新 `origin/main` 在本地复验通过；
- Issue #2 由 Impl PR 自动关闭。
