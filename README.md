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

检查范围包括系统、硬件摘要、磁盘、PATH、Git、Python、uv、Node、npm、编辑器、WSL、Docker、AI CLI 与 MCP 状态。状态统一为 pass / warn / fail / blocked；退出码为 0=全部通过、1=存在待处理项、2=脚本执行失败。

Strict 模式不会输出用户名、完整用户路径、设备序列号、账号名、令牌或环境变量值。API Key 只显示“存在/不存在”。脚本不执行联网下载、不修改系统配置、不创建 API Key。

## 验收

标准套餐：

    powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\acceptance.ps1 -Package Standard -OutputPath .\acceptance-output

完整套餐在获得客户同意联网拉取测试镜像后，可增加 Full 与 AllowNetworkPull 参数。验收脚本会在指定输出目录内创建临时 Git、Python 和 Node 测试项目；不会修改全局 Git 配置，也不会读取密钥。

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
    npm run dev
    npm run check
    npm test

站点采用 Next.js 静态导出，构建产物发布到 `gh-pages` 分支并由 GitHub Pages 托管。

## 发布完整性

公开 PowerShell 脚本与 SHA256 清单以 LF 作为规范字节，`.gitattributes` 会在 Windows 和 Linux 检出时保持一致。不要在生成校验和后转换脚本行尾。

`npm test` 会重新计算静态导出中的 `audit.ps1` 与检测器 ZIP 哈希，并同时核对主清单和独立 ZIP 校验文件；清单格式错误、重复、缺失或出现意外条目都会失败。Pull Request 与 `main` 推送还会在 Windows 和 Ubuntu 上运行：

    npm ci
    npm run check
    npm test

## 许可

audit.ps1、tools 目录中的公开脚本及网站源代码采用 MIT License。案例文字、页面设计、报价文案、封面图、PDF 和其他营销素材不属于 MIT 代码授权，详见 CONTENT-LICENSE.md。
