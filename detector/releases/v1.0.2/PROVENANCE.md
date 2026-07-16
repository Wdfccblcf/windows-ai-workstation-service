# Windows AI 检测器 v1.0.2 来源说明

本目录把已发布 `windows-ai-detector-release-v1.0.2.zip` 中人工维护的检测器外壳移出二进制包，供代码审查和自动校验。它不代表重新发布或重新打包；公开 ZIP 的规范 SHA256 仍为：

    7c8c3c5f0fa28daa90729808dd91bc6e4d3065ba79867f3968b6a303e883de80

## 来源映射

| ZIP 条目 | 规范来源 | 比较方式 |
|---|---|---|
| `audit.ps1` | 仓库根目录 `audit.ps1` | 逐字节 |
| `scan-app.ps1` | 本目录 `scan-app.ps1` | 逐字节 |
| `verify-package.ps1` | 本目录 `verify-package.ps1` | 逐字节 |
| `Start-Windows-AI-Scan.cmd` | 本目录同名文件 | 逐字节 |
| `README.md` | 本目录同名文件 | 逐字节 |
| `release.json` | 本目录同名快照 | JSON 语义 |
| `SHA256SUMS.txt` | ZIP 内派生清单 | 逐项复算 |

两个 PowerShell 快照保留 UTF-8 BOM 与 LF；CMD 和 README 保留 LF 且文件末尾没有额外换行。`release.json` 在仓库中使用 LF，测试忽略 JSON 排版和行尾差异。

## 可验证边界

契约测试可以证明当前仓库中的 ZIP：

- 只有 7 个批准条目；
- 包内脚本与上述规范源一致；
- 包内 SHA256 清单完整且逐项正确；
- 元数据仍声明 detection-only、无修复、无管理员权限请求；
- 解压后的扫描外壳可以通过无 GUI 的 19 项声明自检。

`release.json` 中记录的 `testSummarySha256` 与 `18/18 passed` 是历史发布元数据。对应详细测试摘要未保存在仓库或 ZIP 中，因此当前无法独立复核，也不会补写或推测一份摘要。新的契约测试不把该字段当作当前测试证明。

## 本地验证

在仓库根目录运行：

    powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\detector-release.test.ps1

测试只读取仓库文件，并在系统临时目录解压后执行 `-SelfTest -DetectionOnly`；临时目录会在 `finally` 中清理。
