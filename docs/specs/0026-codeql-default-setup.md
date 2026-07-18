# Spec 0026：CodeQL 默认代码扫描与治理契约

- 状态：Proposed
- 跟踪 Issue：[#26](https://github.com/Wdfccblcf/windows-ai-workstation-service/issues/26)
- 基线：`origin/main@d34fc7d3fa2a5d6bef37beb1103b1234730bcce6`
- 计划实现：独立 Impl PR，基于本 Spec PR 合并后的最新 `origin/main`

## 1. 问题与证据

最新基线已经具备依赖审计、Dependabot、secret scanning、push protection、受保护主分支和只读 workflow token，但尚无第一方代码扫描：

- `GET /repos/Wdfccblcf/windows-ai-workstation-service/code-scanning/default-setup` 返回 `state=not-configured`；
- `GET /repos/Wdfccblcf/windows-ai-workstation-service/code-scanning/alerts` 返回 `404 no analysis found`；
- npm audit、Dependabot open alerts 与 secret scanning open alerts 均为 0，不能替代 JavaScript/TypeScript 和 Actions workflow 的静态安全查询。

仓库为 GitHub.com 公开仓库，Actions 已启用，主要代码语言属于 CodeQL 支持范围。GitHub 官方建议符合条件的仓库优先采用低维护的默认配置，并说明 JavaScript/TypeScript 不需要特殊构建配置：

- [About setup types for code scanning](https://docs.github.com/en/code-security/concepts/code-scanning/setup-types)
- [Configure code scanning](https://docs.github.com/en/code-security/how-tos/find-and-fix-code-vulnerabilities/configure-code-scanning)
- [REST API endpoints for code scanning](https://docs.github.com/en/rest/code-scanning/code-scanning)

## 2. 目标状态

CodeQL default setup 必须满足：

| 字段 | 目标值 |
| --- | --- |
| `state` | `configured` |
| `languages` | 包含 `actions` 与 `javascript-typescript` |
| `query_suite` | `default` |
| `threat_model` | `remote` |
| `runner_type` | `standard` |
| `runner_label` | `null` |

选择默认配置而非 advanced setup 的原因：本仓库没有需要自定义构建的编译语言、私有 registry 或自定义 query pack；默认配置可自动维护语言检测和运行计划，减少 workflow 与 Actions 版本维护面。

## 3. 实现边界

Impl PR 只允许修改：

1. `tools/verify-repository-governance.ps1`
2. `tests/repository-security.test.mjs`
3. `docs/repository-governance.md`
4. `SECURITY.md`（仅当需要链接 CodeQL 验证/alert 处置说明）

实时仓库设置只允许修改 CodeQL default setup。不得修改现有分支保护、required status checks、Actions allowlist、workflow token、Pages、Dependabot、secret scanning、private vulnerability reporting 或仓库可见性。

不得新增 `.github/workflows/codeql.yml`。不得启用预览版 Code Quality、第三方扫描器、付费服务或自动 alert dismiss。

## 4. 迁移协议

迁移必须在 Impl PR 中可审计地执行：

1. 读取并保存迁移前 default setup 完整 JSON，预期 `state=not-configured`。
2. 再次确认 `main` 与 Impl PR 基线未漂移，现有 30 项治理验证通过。
3. 调用 CodeQL default setup REST 更新端点，显式提交：

   ```json
   {
     "state": "configured",
     "languages": ["actions", "javascript-typescript"],
     "query_suite": "default",
     "threat_model": "remote",
     "runner_type": "standard"
   }
   ```

4. 记录 API 返回的 validation run ID/URL；轮询至完成，不以仅收到 `202 Accepted` 作为成功。
5. 重新读取配置并逐字段验证目标状态。
6. 等待至少一次成功 analysis；确认 alerts API 从 `no analysis found` 变为可用。
7. 若 open alert 非 0，逐条记录 rule、severity、位置和处置理由，另开 Issue；不得静默关闭、dismiss 或降低查询套件。

迁移写入前后必须记录快照。网络失败时只重试幂等读；PATCH 的结果不明确时先重新 GET 判定真实状态，再决定是否补发，不能盲目重复切换。

## 5. 实时治理验证器

`tools/verify-repository-governance.ps1` 必须继续兼容 Windows PowerShell 5.1、保持只读，并在现有 30 项检查后新增：

- `codeql-default-setup-configured`
- `codeql-actions-language-enabled`
- `codeql-javascript-typescript-language-enabled`
- `codeql-query-suite-default`
- `codeql-threat-model-remote`
- `codeql-standard-runner`
- `code-scanning-open-alert-count-0`

验证器必须区分以下情况：

- API/认证/网络失败：验证器失败并输出失败检查名；
- 配置未启用或字段漂移：验证器失败；
- alerts API 尚无 analysis：验证器失败，不能把 404 当作 0；
- alerts API 可用且数组为空：open alert 检查通过。

现有重试、JSON 解析、错误汇总与非零退出码契约保持不变。成功汇总应从 30 增至 37 checks。

## 6. 静态回归契约

`tests/repository-security.test.mjs` 必须验证治理脚本仍包含：

- default setup 与 alerts 两个 REST 路径；
- 目标 `configured`、`actions`、`javascript-typescript`、`default`、`remote`、`standard` 断言；
- alerts 的 `state=open` 过滤；
- 7 个稳定检查名；
- 不包含 default setup PATCH、alert dismiss/close 或 advanced workflow 写入逻辑。

静态测试的目标是防止实时治理检查被无意删除；它不伪装成 GitHub API 集成测试。实时值仍由 PowerShell 验证器和 API 证据负责。

## 7. 验证计划

本地实现验证：

1. `git diff --check`
2. `npm run check`
3. 根路径 `npm test`，现有 15 项加新增契约全部通过
4. 设置 `NEXT_PUBLIC_BASE_PATH=/windows-ai-workstation-service` 后再次 `npm test`
5. Windows PowerShell 5.1 三条生产契约：detector、audit、acceptance
6. 扩展后的 `tools/verify-repository-governance.ps1`，37/37
7. `npm run audit:dependencies`，0 vulnerabilities

远端验证：

1. Spec 与 Impl PR 的三个受保护 checks 全绿；
2. CodeQL validation/analysis run 成功；
3. default setup API 字段精确；
4. alerts API 可用且 open=0，或有独立跟踪 Issue；
5. main Quality、Pages build/deploy 全绿；
6. deployment SHA 等于 Impl merge SHA；
7. 线上首页、audit、detector ZIP 和 checksum 均为 200 且哈希不变。

## 8. 分支保护边界

本轮不向 `required_status_checks` 直接添加猜测的 CodeQL check context。默认配置由 GitHub 管理，首次 PR/默认分支分析的精确 check identity 需先观察；错误的 required context 会让所有 PR 永久等待。

代码扫描是否作为强制合并门禁，应在有稳定运行历史和精确工具身份后通过独立 Issue/Spec/Impl 评估。当前闭环由“配置字段 + 成功 analysis + alerts API + 37 项治理验证”组成，同时保持现有三个 required checks 不变。

## 9. 风险与回滚

风险包括首次 analysis 失败、GitHub 托管 runner 临时不可用、语言别名返回差异、意外 alert 和配置对 Actions 分钟的影响。迁移阶段不得为了通过而降低查询、忽略 alert 或放宽现有治理。

若无法稳定完成 analysis，立即 PATCH：

```json
{
  "state": "not-configured"
}
```

然后 GET 验证恢复，并通过新的 Issue/Spec/Impl revert PR 回滚验证器、测试与文档。不得强推、改写历史或回退无关安全功能。

## 10. 完成定义

Spec PR 与 Impl PR 均从各自创建时最新 `origin/main` 派生并合并；CodeQL default setup 达到目标字段；至少一次 analysis 成功；alerts API 可用且没有未跟踪的 open alert；37 项治理验证、本地测试、受保护 PR checks、main CI、Pages deployment 和线上资源全部通过；Issue #26 写入证据并关闭。
