# Windows AI Workstation Service

面向国内 Windows 11 新手的 AI 编程环境只读体检与人工远程搭建服务。公开仓库只包含网站、只读体检脚本、验收脚本及公开文档；修复工具、客户处理手册和客户数据不会进入公开仓库。

## 公开体检

在 PowerShell 中运行：

    powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\audit.ps1 -OutputPath .\audit-output -PrivacyMode Strict

脚本输出：

- audit.json
- audit-report.md
- audit.log
- audit-progress.jsonl（19 项顺序检测的脱敏进度事件，供本地检测器或秒哒进度页读取）

面向客户的检测专用发布包为 `public/downloads/windows-ai-detector-release-v1.0.2.zip`。它不包含修复引擎、软件安装、系统功能修改或管理员权限申请；私有修复工具不会进入公开构建。

正式版本使用独立组件 tag `detector-v<semver>` 和 [GitHub Releases](https://github.com/Wdfccblcf/windows-ai-workstation-service/releases)。下载后除核对 SHA-256 外，还可以验证资产是否由本仓库的受控 GitHub Actions workflow 发布：

    gh attestation verify .\windows-ai-detector-release-v1.0.2.zip -R Wdfccblcf/windows-ai-workstation-service
    gh attestation verify .\SHA256SUMS.txt -R Wdfccblcf/windows-ai-workstation-service

完整的 Issue → Spec PR → Impl PR → dry-run → annotated tag → Release 流程、权限边界和失败处理见 [`docs/detector-release.md`](docs/detector-release.md)。Pages 下载继续保留，Release 不会重新打包或替换同版本字节。

检查范围包括系统、硬件摘要、磁盘、PATH、Git、Python、uv、Node、npm、编辑器、WSL、Docker、AI CLI 与 MCP 状态。状态统一为 pass / warn / fail / blocked；退出码为 0=全部通过、1=存在待处理项、2=脚本执行失败。

Strict 模式不会输出用户名、完整用户路径、设备序列号、账号名、令牌或环境变量值。API Key 只显示“存在/不存在”。脚本不执行联网下载、不修改系统配置、不创建 API Key。

## 验收

标准套餐：

    powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\acceptance.ps1 -Package Standard -OutputPath .\acceptance-output

完整套餐在获得客户同意联网拉取测试镜像后，可增加 Full 与 AllowNetworkPull 参数。验收脚本会在指定输出目录内创建临时 Git、Python 和 Node 测试项目；不会修改全局 Git 配置，也不会读取密钥。

Windows Quality 还会在系统临时目录中真实运行一次 Standard 验收并检查 JSON、Markdown、结果顺序、总体状态、退出码、隐私和清理契约。测试接受与当前机器一致的退出码 0 或 1，不要求 Git、Python、Node 和 Codex 四项全部通过；它不运行 Full 或 Docker、不允许联网拉取、不使用真实密钥，并验证用户级 Git 配置文件的存在性和 SHA256 在执行前后不变：

    powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\acceptance-contract.test.ps1

## 服务边界

- 首期仅支持 Windows 11。
- 客户先在平台完成资金托管，并自行备份数据。
- 密码、验证码和密钥由客户本人输入；客户全程在场。
- 不提供破解、账号绕过、无人值守远控、数据恢复、恶意软件清理、硬件维修或公司管控设备解锁。
- 网络封锁、第三方账号或额度、Docker 深度数据损坏可记为外部阻塞。
- 默认不创建 OpenAI 或其他付费 API Key。

## 本地开发

需要 Node.js 22.13 或更高版本：

    npm ci
    npm run audit:dependencies
    npm run dev
    npm run check
    npm test

`npm run audit:dependencies` 对当前 lockfile 执行只读依赖审计，high 或 critical 漏洞会以非零退出码阻止 Quality 与 Pages 构建；该命令不会自动修改依赖。

仓库管理员可用已认证的 GitHub CLI 只读复核主分支保护、Actions 来源、Dependabot、私密漏洞报告和 Pages 设置。验证器只输出设置结论与 open Dependabot alert 数量，不输出漏洞正文：

    powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\verify-repository-governance.ps1

完整目标配置、变更流程与回滚步骤见 `docs/repository-governance.md`。

站点采用 Next.js 静态导出，由 `.github/workflows/pages.yml` 从 `main` 构建 `out/` artifact 并通过 GitHub Pages environment 发布。Pull Request 会验证相同的 artifact，但只有 `refs/heads/main` 能进入部署 job；构建默认只读，部署 job 单独使用 `pages: write` 与 `id-token: write`。

本地复现 GitHub Pages 项目子路径构建：

    $env:NEXT_PUBLIC_BASE_PATH="/windows-ai-workstation-service"
    npm test
    Remove-Item Env:NEXT_PUBLIC_BASE_PATH

仓库 Pages source 必须设置为 GitHub Actions。旧 `gh-pages` 分支只保留为迁移回滚证据，不再是日常发布入口。

## 发布完整性

公开 PowerShell 脚本与 SHA256 清单以 LF 作为规范字节，`.gitattributes` 会在 Windows 和 Linux 检出时保持一致。不要在生成校验和后转换脚本行尾。

`npm test` 会重新计算静态导出中的 `audit.ps1` 与检测器 ZIP 哈希，并同时核对主清单和独立 ZIP 校验文件；清单格式错误、重复、缺失或出现意外条目都会失败。Pull Request 与 `main` 推送还会在 Windows 和 Ubuntu 上运行：

    npm ci
    npm run check
    npm test

检测器 v1.0.2 的 WinForms 外壳、包内校验器、启动 CMD、README 与发布元数据快照位于 `detector/releases/v1.0.2/`，便于直接审查。Windows 上还可以验证 ZIP 条目全集、源文件字节、包内清单、安全元数据与无 GUI 自检：

    powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\detector-release.test.ps1

该验证不会重新打包或修改发布文件。历史 `release.json` 引用的 18/18 详细测试摘要没有留存在仓库或 ZIP 中，不能作为当前可复核证明；现有可验证边界详见 `detector/releases/v1.0.2/PROVENANCE.md`。

候选 Release 还可以在仓库外的空 staging 目录中验证 tag、版本、资产白名单和复制前后哈希：

    powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\prepare-detector-release.ps1 -TagName detector-v1.0.2 -OutputDirectory $env:TEMP\detector-release-stage

该脚本不联网、不创建 tag 或 Release，也不修改仓库文件。

Windows 上还会真实运行根目录体检脚本，验证 Strict 脱敏、19 项顺序检查、21 条进度事件、汇总和退出码契约：

    powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\audit-contract.test.ps1

体检结果取决于当前机器，契约测试接受与总体状态一致的退出码 0 或 1，不要求 19 项全部通过。测试使用假 API Key 标记验证输出不泄漏变量值或完整用户路径，不使用真实密钥、不联网、不提权，也不修改系统配置。

## 许可

audit.ps1、tools 目录中的公开脚本及网站源代码采用 MIT License。案例文字、页面设计、报价文案、封面图、PDF 和其他营销素材不属于 MIT 代码授权，详见 CONTENT-LICENSE.md。
