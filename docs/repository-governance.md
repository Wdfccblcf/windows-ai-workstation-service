# 仓库治理与安全门禁

本文记录 `Wdfccblcf/windows-ai-workstation-service` 的实时 GitHub 设置目标、日常验证、变更纪律和回滚路径。基础治理来源为 [Spec 0020](./specs/0020-repository-governance.md)，CodeQL 扩展来源为 [Spec 0026](./specs/0026-codeql-default-setup.md)，对应 [Issue #20](https://github.com/Wdfccblcf/windows-ai-workstation-service/issues/20) 与 [Issue #26](https://github.com/Wdfccblcf/windows-ai-workstation-service/issues/26)。

## 目标状态

### 主分支保护

`main` 的任何更新必须经 Pull Request，并要求分支保持最新。Required checks 精确为：

- `Verify (ubuntu-latest)`
- `Verify (windows-latest)`
- `Build Pages artifact`

保护规则对管理员生效，要求 linear history 和解决全部 review conversation，禁止 force push 与分支删除。仓库当前是单维护者模式，因此保留 `0 approvals`；这不允许绕过 PR 或 required checks。

### Actions 权限

- repository Actions enabled；
- `allowed_actions=selected`，只允许 GitHub-owned Actions；
- verified creators 和自定义 patterns 均不允许；
- 不强制 SHA pinning，现有 workflow 只引用已审计的 `actions/*` major tags；
- workflow 默认 token 为 read，不能审批 Pull Request；
- workflow 根权限保持 `contents: read`，Pages deploy job 仅在必要边界获得 `pages: write` 与 `id-token: write`。

### 依赖与漏洞披露

- secret scanning 与 push protection 保持 enabled；
- Dependabot alerts enabled；
- Dependabot automated security updates 保持 disabled，避免绕过 Issue → Spec PR → Impl PR；
- private vulnerability reporting enabled；
- `npm run audit:dependencies` 在本地、Quality Linux job 和 Pages build 执行，high/critical 漏洞阻止合并或部署；
- SECURITY.md 的私密入口为 `https://github.com/Wdfccblcf/windows-ai-workstation-service/security/advisories/new`。

### CodeQL 代码扫描

- CodeQL 使用 GitHub 托管的 default setup，不维护独立 advanced workflow；
- 扫描语言固定包含 `actions` 与 `javascript-typescript`；
- query suite 为 `default`，threat model 为 `remote`，使用标准 GitHub runner；
- default setup 在默认/受保护分支 push、面向这些分支的 Pull Request 和 GitHub 管理的周期计划上运行；
- code scanning open alerts 必须为 0。新 alert 不得自动关闭或忽略，应脱敏记录规则、严重度和位置并建立独立 Issue；
- 不把猜测的 CodeQL check context 加入通用 required status checks；
- 唯一 active repository ruleset `CodeQL merge protection` 只覆盖默认分支、没有 bypass actor，并以专用 `code_scanning` rule 要求 CodeQL 提供结果；
- 普通 alert 达到 error 时阻断，security alert 达到 high 或更高时阻断。低于门禁阈值的 open alert 仍会让只读治理验证失败，不能静默忽略。

## 日常验证

验证依赖 lockfile：

```powershell
npm ci
npm run audit:dependencies
```

使用已认证、对仓库有读取权限的 GitHub CLI 验证实时设置：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\verify-repository-governance.ps1
```

验证器只读，成功时打印 45 个 PASS 和检查总数。它验证 Dependabot 与 code scanning open alerts 都为 0，并精确验证 CodeQL merge ruleset，但不会打印告警正文、包名、漏洞标识符、secret scanning 告警或 API token。

每次治理变更后还应确认：

1. Pull Request 的 Ubuntu、Windows 和 Pages build 全绿；
2. Pages deploy 在 Pull Request 中跳过；
3. 合并后主分支的 Quality 与 Pages build/deploy 全绿；
4. Pages deployment SHA 等于合并 SHA；
5. 线上首页、`audit.ps1`、检测器 ZIP 和 checksum 返回成功，发布字节未意外改变。

## 变更流程

所有治理、依赖升级和安全配置变更均执行：

1. 从最新 `origin/main` 建立 Issue，记录缺口、证据、原因和验收标准；
2. 从最新 `origin/main` 建立纯规格 Spec PR，固定设置、迁移顺序和回滚；
3. Spec 合并后再次从最新 `origin/main` 建立 Impl PR；
4. 本地和全新 clone 验证后创建 Draft PR；
5. PR 初次 CI 全绿后才修改实时设置；
6. 记录设置前快照，按“私密报告 → Dependabot alerts → Actions allowlist → branch protection → CodeQL default setup → CodeQL merge ruleset”迁移；
7. 运行只读验证器，并在新设置下复跑 PR workflows；
8. 使用固定 head SHA 合并，不 bypass、不直接 push `main`；
9. 回写 run、job、设置摘要、部署 SHA 和线上 smoke evidence。

Dependabot 告警不会自动产生安全更新 PR。新告警应先建独立 Issue，再按同一流程分析与修复。

CodeQL default setup 变更必须显式固定语言、query suite、threat model 和 runner。收到配置 API 的 `202 Accepted` 后仍需等待 validation/analysis 成功，并确认 alerts API 可读；`404 no analysis found` 不是零告警。

CodeQL merge protection 必须使用专用 `code_scanning` ruleset、只覆盖 `~DEFAULT_BRANCH` 且没有 bypass。迁移后的 Impl PR 必须实际观察 CodeQL pending 时被阻止、成功后恢复可合并，不能只验证设置 JSON。

## 故障定位

- Required check 长期 pending：确认 context 与 job 显示名完全一致，并确认 workflow 会在 Pull Request 事件触发。
- Action 被拒绝：确认 workflow 只引用 `actions/*`；不要临时开放所有 Actions，应通过新的规格评估来源。
- Dependabot alerts API 不可读：确认 alerts 已启用且当前 `gh` 身份有仓库管理或安全读取权限。
- CodeQL 配置为 `not-configured`：确认仓库公开、Actions enabled，并按 Spec 0026 的快照与回滚协议启用 default setup。
- CodeQL alerts API 返回 `no analysis found`：等待或检查 default setup validation run；不能把 404 当作空数组。
- CodeQL 产生 open alert：不要 dismiss 或降低 query suite；脱敏记录并建立独立 Issue 处理。
- PR 在 CodeQL 完成后仍被 ruleset 阻止：核对工具名、目标 commit/reference 是否都有分析、ruleset scope 和两个阈值；不要临时添加 bypass。
- 私密报告入口不可用：确认 private vulnerability reporting enabled，并使用仓库 Security 页面而非公开 Issue。
- `npm audit` 失败：只记录脱敏摘要并建立独立 Issue；不要在 CI 中运行 `npm audit fix` 或 `--force`。

## 逆序回滚

实时设置迁移失败时按迁移前快照逆序回滚：

1. 若本轮刚创建 CodeQL merge ruleset，则按唯一 ID 删除并验证 active rules 恢复；
2. 若本轮刚启用 CodeQL default setup，则恢复为 `not-configured` 并验证；
3. 删除或恢复 `main` branch protection；
4. 恢复 Actions permissions 与 selected Actions；
5. 若本轮刚启用 Dependabot alerts，则禁用；
6. 若本轮刚启用 private vulnerability reporting，则禁用；
7. 重新运行只读验证和受影响 workflow。

已合并的版本化实现如需撤销，必须新建 Issue、Spec PR 和 Impl revert PR。禁止强推、改写历史、删除运行/部署证据，且不得关闭 secret scanning、push protection、HTTPS 或 workflow 默认只读权限。
