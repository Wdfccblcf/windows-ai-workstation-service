# Spec 0020：仓库治理、依赖漏洞门禁与私密披露通道

- 状态：Proposed
- 跟踪 Issue：[#20](https://github.com/Wdfccblcf/windows-ai-workstation-service/issues/20)
- 基线：`origin/main@c66462778d22452c1328e3fd3ff8235652eafb1a`
- 计划实现：独立 Impl PR，基于本 Spec PR 合并后的最新 `origin/main`

## 1. 问题与基线证据

截至 2026-07-18，代码库已有 Ubuntu/Windows Quality、Pages artifact、发布制品、隐私输出和可访问性契约，但 GitHub 仓库级设置仍允许绕过这些门禁。对上述基线的只读审计结果为：

- 默认分支为 `main`；Actions 默认 token 为只读，且不能审批 Pull Request；
- secret scanning 与 secret scanning push protection 已启用；
- Pages 使用 GitHub Actions source，强制 HTTPS；
- `npm audit` 当前报告 0 个漏洞；
- `main` 未受 branch protection 保护，rulesets 为空；
- Actions 允许所有 Action，未限制为 GitHub-owned；
- Dependabot alerts 未启用，读取接口返回 disabled；
- Dependabot security updates 未启用；
- private vulnerability reporting 未启用，但 `SECURITY.md` 已要求报告者使用该私密渠道。

这意味着具写权限的主体仍可直接 push、force-push 或删除 `main`，而不运行 required checks；依赖漏洞不会持续形成仓库告警；安全研究者也无法按公开安全政策使用承诺的私密入口。

## 2. 官方依据

- [Branch protection REST API](https://docs.github.com/en/rest/branches/branch-protection)
- [Managing a branch protection rule](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-protected-branches)
- [Configuring Dependabot alerts](https://docs.github.com/en/code-security/how-tos/secure-your-supply-chain/secure-your-dependencies/configure-dependabot-alerts)
- [Dependabot alerts concepts](https://docs.github.com/en/code-security/concepts/supply-chain-security/dependabot-alerts)
- [Configuring private vulnerability reporting](https://docs.github.com/en/code-security/how-tos/report-and-fix-vulnerabilities/configure-vulnerability-reporting/configure-for-a-repository)
- [Actions permissions REST API](https://docs.github.com/en/rest/actions/permissions)
- [Ruleset status-check troubleshooting](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/troubleshooting-rules)

## 3. 目标

1. 让 `main` 的所有变更必须经 Pull Request，并严格通过现有三个跨平台/Pages required checks。
2. 让保护规则对管理员同样生效，禁止 force push 和删除，保持线性历史并要求解决 review conversation。
3. 将 Actions 来源收紧为 GitHub-owned，同时保留最小 workflow 权限。
4. 启用 Dependabot alerts 和 private vulnerability reporting，使依赖告警与安全政策可实际使用。
5. 在版本库内增加 high/critical 依赖漏洞门禁、静态治理契约与只读实时设置验证器。
6. 通过“先让 Impl PR 全绿、再迁移设置、再在新设置下复跑”的顺序证明规则可执行，并为每一步保留回滚路径。

## 4. 非目标与有意保留的边界

- 不启用 Dependabot automated security updates 或 version update PR；仓库继续遵守每项改动均经 Issue → Spec PR → Impl PR 的流程。
- 不要求第二位 reviewer；单维护者仓库的批准数固定为 0，但仍必须经 PR 和 required checks。
- 不启用 merge queue、强制签名提交或 Action SHA pinning。
- 不允许第三方或 verified creator Action；当前 workflow 仅使用 `actions/*` 官方 Action。
- 不改变业务页面、体检/验收逻辑、检测器 ZIP、下载制品、服务价格或部署内容。
- 验证器只读，不读取或打印 Dependabot 告警正文、secret scanning 告警正文、凭据或用户信息。

## 5. 版本化实现范围

### 5.1 依赖漏洞命令与 CI

`package.json` 新增：

```json
"audit:dependencies": "npm audit --audit-level=high"
```

Quality workflow 在 `npm ci` 后、类型检查前增加 `Audit production dependencies`。该步骤只在 Linux matrix job 执行一次，避免同一 lockfile 在 Windows 重复扫描：

```yaml
- name: Audit production dependencies
  if: runner.os == 'Linux'
  run: npm run audit:dependencies
```

Pages build 在 `npm ci` 后增加同名步骤且无条件执行。`npm audit --audit-level=high` 允许 low/moderate 结果继续，但 high/critical 结果必须以非零状态阻止合并或部署。它不得使用 `--force`、`npm audit fix` 或自动修改 lockfile。

### 5.2 静态治理契约

新增 `tests/repository-security.test.mjs`，并由现有 `npm test` 自动发现。测试必须只读取版本库文件，并至少断言：

- `audit:dependencies` 的命令和阈值精确；
- Quality 只在 Linux job 执行依赖审计；Pages build 必定执行依赖审计；
- 两个 workflow 继续保持根级 `contents: read`，不出现 `pull_request_target`、第三方 Action、`npm audit fix` 或 `--force`；
- `SECURITY.md` 包含仓库 Security Advisories 的新私密报告入口；
- 治理文档包含三个 required check 名称、0 approvals、GitHub-owned Actions、Dependabot alerts、私密披露与回滚边界。

### 5.3 只读实时验证器

新增 `tools/verify-repository-governance.ps1`，兼容 Windows PowerShell 5.1，源码保持 ASCII，使用 GitHub CLI 的当前认证。脚本默认验证 `Wdfccblcf/windows-ai-workstation-service`，可通过参数显式覆盖仓库名，但不得执行 PUT、POST、PATCH 或 DELETE。

脚本必须验证：

- 默认分支、secret scanning、push protection、Dependabot security updates 状态；
- Actions repository permissions 和 selected Actions 设置；
- workflow 默认权限只读且不能批准 PR；
- `main` branch protection 的 strict、三个精确 context、管理员执行、PR 要求、0 approvals、linear history、conversation resolution、force push/delete 禁止；
- Dependabot alerts API 可读取，只输出 open alert 数量，不输出告警对象；
- private vulnerability reporting 已启用；
- Pages source 为 workflow 且强制 HTTPS。

成功时仅输出逐项 PASS 和不敏感计数；任一不符以非零退出码失败。脚本不得打印 API 响应正文、token、用户资料路径、告警摘要、依赖包名或漏洞标识符。

### 5.4 文档

- 新增 `docs/repository-governance.md`，记录当前目标设置、日常验证命令、变更流程、故障定位与逆序回滚。
- 更新 `SECURITY.md`，将私密披露入口链接到 `https://github.com/Wdfccblcf/windows-ai-workstation-service/security/advisories/new`，明确不得在公开 Issue/PR 披露敏感漏洞。
- 更新 `README.md`，记录依赖审计与只读治理验证命令。

## 6. 实时仓库目标配置

### 6.1 `main` branch protection

对 `PUT /repos/Wdfccblcf/windows-ai-workstation-service/branches/main/protection` 使用以下语义等价请求体：

```json
{
  "required_status_checks": {
    "strict": true,
    "checks": [
      { "context": "Verify (ubuntu-latest)" },
      { "context": "Verify (windows-latest)" },
      { "context": "Build Pages artifact" }
    ]
  },
  "enforce_admins": true,
  "required_pull_request_reviews": {
    "dismiss_stale_reviews": false,
    "require_code_owner_reviews": false,
    "required_approving_review_count": 0,
    "require_last_push_approval": false
  },
  "restrictions": null,
  "required_linear_history": true,
  "allow_force_pushes": false,
  "allow_deletions": false,
  "block_creations": false,
  "required_conversation_resolution": true,
  "lock_branch": false,
  "allow_fork_syncing": false
}
```

Required checks 采用 GitHub UI/API 实际报告的 job 名称，不使用 workflow 文件名。三个 check 必须精确且不得以易冲突的通用名称替换。

### 6.2 Actions 来源与默认权限

对 repository Actions permissions 使用：

```json
{
  "enabled": true,
  "allowed_actions": "selected",
  "sha_pinning_required": false
}
```

selected Actions 配置为：

```json
{
  "github_owned_allowed": true,
  "verified_allowed": false,
  "patterns_allowed": []
}
```

现有默认 workflow permissions 继续为 `read`，`can_approve_pull_request_reviews=false`。不强制 SHA pinning 的理由是当前仅使用已审计的 `actions/*` 官方 Action 和受维护 major tags；这项取舍需由静态契约防止无意引入第三方 Action。

### 6.3 依赖与披露设置

- `PUT /repos/Wdfccblcf/windows-ai-workstation-service/vulnerability-alerts` 启用 Dependabot alerts/dependency graph；
- 保持 automated security fixes disabled；
- `PUT /repos/Wdfccblcf/windows-ai-workstation-service/private-vulnerability-reporting` 启用私密漏洞报告；
- 不更改 secret scanning 和 push protection，它们必须继续为 enabled。

## 7. 迁移事务与验证顺序

1. 合并本 Spec PR；从其合并后的最新 `origin/main` 创建 Impl 分支。
2. 完成所有版本化改动和本地回归，在全新 clone 中复验后创建 Draft Impl PR。
3. 等待 Impl PR 第一次 Quality Ubuntu/Windows 与 Pages build 全绿；Pages deploy 必须跳过。
4. 将 Impl PR 转为 Ready，并读取迁移前快照：branch protection、Actions permissions、selected Actions、Dependabot alerts、automated security fixes、private vulnerability reporting、workflow defaults、repo security 和 Pages。
5. 先启用 private vulnerability reporting，再启用 Dependabot alerts。
6. 将 Actions 收紧为 selected + GitHub-owned only，并立即读取验证。
7. 最后创建 `main` branch protection，避免在前置配置或 PR 检查尚未稳定时锁住主分支。
8. 运行只读治理验证器；任一断言失败则停止并按第 9 节逆序回滚。
9. 在新设置生效后重新运行同一个 Impl PR 的 Quality 和 Pages workflows；三个 required checks 必须再次全绿。
10. 以固定 head SHA squash 合并 Impl PR。管理员执行规则必须生效；不得使用 bypass、直接 push 或 force merge。
11. 等待 `main` 的 Quality、Pages build/deploy，确认 deployment SHA 等于合并 SHA；再次运行只读验证器和线上关键资源 smoke test。
12. 将设置快照、API 结果摘要、run/job、退出码和部署证据回写 Issue #20，关闭 Issue。

## 8. 验收标准

- Spec PR 与 Impl PR 均从创建时最新 `origin/main` 派生并合并。
- `main` 只能经 PR 更新；strict 和三个 required checks 精确生效，管理员不能绕过。
- linear history 与 conversation resolution 启用；force push/delete 禁止；批准数为 0。
- Actions 仅允许 GitHub-owned；默认 token 仍为 read 且不能批准 PR。
- Dependabot alerts enabled、API 可读取，当前 open alerts 数只以计数报告。
- Dependabot security updates 保持 disabled。
- private vulnerability reporting enabled，`SECURITY.md` 私密入口可用。
- 本地与 CI 均真实执行 `npm audit --audit-level=high`，当前为 0 vulnerabilities。
- 静态契约和只读实时验证器均通过，且日志不包含告警正文或敏感信息。
- PR 与主分支 Quality/Pages 全绿，Pages deployment SHA 等于主分支合并 SHA，线上关键资源返回成功。

## 9. 回滚

若迁移阶段失败，按逆序恢复快照：

1. 删除新建的 `main` branch protection，或恢复其迁移前响应；
2. Actions permissions 和 selected Actions 恢复为迁移前值（本轮预期为 `allowed_actions=all`）；
3. 若本轮刚启用 Dependabot alerts，则禁用；
4. 若本轮刚启用 private vulnerability reporting，则禁用；
5. 如实现已合并且代码门禁本身需撤销，创建新的 Issue/Spec/Impl revert PR，不强推、不改写历史。

任何回滚均不得关闭 secret scanning、push protection、HTTPS、只读 workflow 默认权限或删除运行/部署证据。

## 10. 风险与完成定义

主要风险是 required check context 拼写错误、Actions allowlist 阻断现有 workflow，或保护规则在迁移中途锁住管理员。迁移顺序通过“CI 先绿、Actions 次之、branch protection 最后”降低风险；设置后复跑同一 PR 可证明 allowlist 与 required checks 不是只在纸面上成立。

Dependabot alerts 可能在未来发现漏洞，但本轮不自动创建修复 PR；新告警应作为下一轮独立 Issue 的输入。`npm audit` 是 lockfile 的补充门禁，不代替 GitHub Advisory Database 告警。

完成定义：Spec PR 和 Impl PR 均合并，Issue #20 关闭；版本化测试、本地审计、只读实时设置验证、保护规则下 PR 复跑、主分支 CI、Pages deployment 与线上 smoke test全部通过；实时设置精确符合本 Spec；未打印安全告警正文、未使用 bypass、未直接写入受保护 `main`。
