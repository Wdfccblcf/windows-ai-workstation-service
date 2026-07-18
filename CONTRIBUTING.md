# 贡献指南

感谢你改进 Windows AI 工作站体检服务。本仓库采用 **Issue → Spec PR → Impl PR → evidence/close** 的可审计流程；所有变更都从最新 `origin/main` 开始，不能把规格和实现混在同一个 PR。

## 隐私与安全

不要在公开 Issue、Pull Request、日志或截图中提交真实 API Key、token、密码、验证码、客户数据、用户名、完整用户路径、设备序列号或其他可识别信息。请先脱敏，只保留复现所需的最小证据。

安全漏洞或包含敏感细节的行为举报请使用 [私密报告入口](https://github.com/Wdfccblcf/windows-ai-workstation-service/security/advisories/new)。行为举报标题以 `[Conduct]` 开头。不要为了提交报告而公开个人身份或敏感证据。

## 变更分类

- `bug`：可复现的错误、回归或契约违例。
- `optimization`：性能、可靠性、安全性、可维护性、可访问性或流程改进。
- `docs`：不改变产品/运行时行为的文档修正。
- `revert`：对已合并变更的可审计回滚。

## 强制流程

1. 同步并记录最新 `origin/main` SHA。
2. 创建 Issue，至少写清基线与证据、为什么值得改、实现边界、非目标、计划、验收标准、风险与回滚。
3. 从该基线建立纯规格 **Spec PR**。Spec 只定义契约、验证和回滚，不能混入实现代码或实时设置写入。
4. Spec 合并后重新同步 `origin/main`，从新的最新 SHA 建立独立 **Impl PR**。
5. Impl PR 先保持 Draft；完成本地验证、fresh install、PR checks、review threads 和必要的可回滚迁移。
6. 固定 final head SHA，确认 branch protection 与 CodeQL Ruleset 全绿后转为 Ready 并合并。禁止 bypass、直接 push `main`、force push 或改写历史。
7. 等待 main CI、CodeQL、Pages deployment 与线上 smoke；把 run、deployment、哈希和实时设置证据回写 Issue。
8. 勾选全部 Issue 验收项，并以 `completed` 原因关闭。

## Issue 最低信息

- `origin/main@<sha>` 与可复验证据；
- 问题/机会以及预期收益；
- 允许修改的文件或实时设置；
- 明确非目标，避免范围漂移；
- 有序计划与回滚顺序；
- 可判定的验收 checklist；
- 隐私、安全、兼容性与发布制品影响。

## PR 最低信息

- PR 类型、关联 Issue 和关联 Spec；
- 创建时 base SHA 与 final head SHA；
- 为什么改、改了什么、没有改什么；
- 本地、fresh clone、PR checks 的命令和结果；
- 依赖、安全、隐私、实时设置、生产制品与 SHA256 影响；
- 失败回滚与合并后验收；
- review threads、固定 head 与 Issue 回写状态。

## 本地验证

```powershell
npm ci
npm run audit:dependencies
npm run check
npm test

$env:NEXT_PUBLIC_BASE_PATH = '/windows-ai-workstation-service'
npm test
Remove-Item Env:NEXT_PUBLIC_BASE_PATH

powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\detector-release.test.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\audit-contract.test.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\acceptance-contract.test.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\verify-repository-governance.ps1
```

当前完整测试应由 `npm test` 自动发现，实时治理验证成功时输出 45 项 PASS。若本地 registry、GitHub API 或 runner 暂时不可用，请明确记录为环境限制，不要把未运行或超时写成通过。

## 合并纪律

- PR 必须基于创建时最新 `origin/main`，合并前保持 base 最新；
- Draft 阶段允许迭代，Ready 前必须清空 review threads；
- 以固定 final head SHA 合并，任何新提交都重新等待完整 checks；
- CodeQL pending 或达到门禁阈值时不得合并；
- 合并后的 main、deployment 和线上验证是完成定义的一部分，不以 PR merge 本身代替验收。
