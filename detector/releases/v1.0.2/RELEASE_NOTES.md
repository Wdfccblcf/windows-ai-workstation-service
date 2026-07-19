# Windows AI detector v1.0.2

这是 Windows 11 AI 编程环境检测器的 detection-only 只读版本。它不包含修复引擎、软件安装、系统配置修改、管理员权限申请或自动上传。

本次 GitHub Release 发布仓库中既有的 v1.0.2 规范 ZIP，不重新打包，也不改变任何检测器字节。ZIP 的规范 SHA-256 为：

```text
7c8c3c5f0fa28daa90729808dd91bc6e4d3065ba79867f3968b6a303e883de80
```

## 下载后验证

在包含下载文件的目录运行：

```powershell
Get-FileHash -Algorithm SHA256 -LiteralPath .\windows-ai-detector-release-v1.0.2.zip
gh attestation verify .\windows-ai-detector-release-v1.0.2.zip -R Wdfccblcf/windows-ai-workstation-service
gh attestation verify .\SHA256SUMS.txt -R Wdfccblcf/windows-ai-workstation-service
```

哈希必须与上面的规范值一致；attestation 必须绑定到 `Wdfccblcf/windows-ai-workstation-service`。

## 当前可复核边界

- ZIP 只有 7 个批准条目；
- 人工维护脚本与仓库规范源逐字节一致；
- 包内 checksum 清单逐项复算；
- 元数据保持 detection-only、无修复、无管理员权限请求；
- 解压后无 GUI 自检当前通过 19 项声明。

`release.json` 保留历史 `18/18 passed` 与摘要哈希，但对应详细历史摘要没有留存，因此不能独立复核，也不作为本次发布证明。当前证据以仓库契约、tag workflow、公开资产摘要和 artifact attestation 为准。

不要在公开 Issue 或 Pull Request 中粘贴 API Key、token、客户数据、完整用户路径或未脱敏日志。敏感漏洞请使用[私密报告入口](https://github.com/Wdfccblcf/windows-ai-workstation-service/security/advisories/new)。
