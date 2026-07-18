# Spec 0029：CodeQL Ruleset 合并保护

- 状态：Proposed
- 跟踪 Issue：[#29](https://github.com/Wdfccblcf/windows-ai-workstation-service/issues/29)
- 基线：`origin/main@1e49fc6d8a5152d341f9fd2c73077a8c4b3ae0d2`
- 计划实现：独立 Impl PR，基于本 Spec PR 合并后的最新 `origin/main`

## 1. 问题与证据

CodeQL default setup 已配置并在 Pull Request 与 `main` 上成功扫描 `actions` 和 `javascript-typescript`，但最终残余审计显示：

- `GET /repos/Wdfccblcf/windows-ai-workstation-service/rulesets` 返回空数组；
- `main` required status checks 只有 Quality Ubuntu/Windows 和 Pages build；
- CodeQL 会报告结果，但没有仓库规则阻止“分析缺失、仍在运行或达到严重度阈值”的 commit 合并。

GitHub 官方提供专门的 `code_scanning` ruleset。该规则要求指定工具同时为目标 commit 与 reference 提供结果，并按普通告警和安全告警阈值决定是否允许 reference 更新：

- [Set code scanning merge protection](https://docs.github.com/en/code-security/how-tos/find-and-fix-code-vulnerabilities/manage-your-configuration/set-merge-protection)
- [REST API endpoints for rules](https://docs.github.com/en/rest/repos/rules)

## 2. 目标 Ruleset

仓库必须恰好存在一个符合以下完整契约的 ruleset：

| 字段 | 目标值 |
| --- | --- |
| `name` | `CodeQL merge protection` |
| `target` | `branch` |
| `enforcement` | `active` |
| `bypass_actors` | 空数组 |
| `conditions.ref_name.include` | 仅 `~DEFAULT_BRANCH` |
| `conditions.ref_name.exclude` | 空数组 |
| `rules` | 仅一个 `code_scanning` rule |
| tool | `CodeQL` |
| `alerts_threshold` | `errors` |
| `security_alerts_threshold` | `high_or_higher` |

选择专用 ruleset 而不是把字符串 `CodeQL` 追加到通用 status checks，是因为前者验证 code scanning 工具结果和 alert 严重度语义，不依赖 UI check 名称猜测。

普通告警以 error 阻断，安全告警以 high 或更高阻断。低/中安全 alert 与 warning 不被此规则直接阻断，但 37 项治理验证仍要求 open code scanning alerts=0，因此任何发现都必须跟踪，不能静默忽略。

实现观察：GitHub 创建响应将上述契约原样返回，并额外报告 `current_user_can_bypass=never`。治理验证以稳定的 `bypass_actors=[]` 为版本化断言，同时把该运行时字段作为无维护者旁路的迁移证据，不将账户相关字段硬编码进脚本。

## 3. 创建请求

实时迁移使用 repository rulesets REST API，请求语义必须等价于：

```json
{
  "name": "CodeQL merge protection",
  "target": "branch",
  "enforcement": "active",
  "bypass_actors": [],
  "conditions": {
    "ref_name": {
      "include": ["~DEFAULT_BRANCH"],
      "exclude": []
    }
  },
  "rules": [
    {
      "type": "code_scanning",
      "parameters": {
        "code_scanning_tools": [
          {
            "tool": "CodeQL",
            "alerts_threshold": "errors",
            "security_alerts_threshold": "high_or_higher"
          }
        ]
      }
    }
  ]
}
```

不得创建 disabled/evaluate 规则后宣称完成，不得添加其他 rule、scope 或 bypass actor。

## 4. 版本化实现边界

Impl PR 只允许修改：

1. `tools/verify-repository-governance.ps1`
2. `tests/repository-security.test.mjs`
3. `docs/repository-governance.md`
4. 本 Spec（仅允许记录 GitHub 实际 REST 响应的等价表示）

不得修改 workflow、产品源码、依赖、生产 PowerShell、release ZIP、checksum、Pages 或现有 branch protection。实时设置只允许创建目标 ruleset。

## 5. 实时治理验证

`tools/verify-repository-governance.ps1` 必须保持 Windows PowerShell 5.1 兼容、只读和三次重试，并从 37 项扩展到 45 项：

- `codeql-merge-ruleset-exactly-one`
- `codeql-merge-ruleset-active`
- `codeql-merge-ruleset-default-branch-only`
- `codeql-merge-ruleset-bypass-empty`
- `codeql-merge-rule-exactly-one`
- `codeql-merge-tool-codeql`
- `codeql-alert-threshold-errors`
- `codeql-security-threshold-high-or-higher`

验证器先列出 repository rulesets，按区分大小写的精确名称筛选并要求数量为 1，再按 ID 读取完整规则。目标、include/exclude、bypass、rule 数量、tool 数量与阈值必须精确；额外 rule/tool/scope 都应失败。

原有 37 项继续验证 CodeQL 配置和 open alert=0。本轮不能通过放宽旧检查换取新检查通过。

## 6. 静态回归契约

`tests/repository-security.test.mjs` 必须验证治理脚本包含：

- repository rulesets list 与 by-ID REST 路径；
- 精确 ruleset 名称、默认分支 token、code_scanning、CodeQL 和两个阈值；
- 8 个稳定检查名；
- 没有 POST/PATCH/DELETE、bypass 创建或 alert dismiss 逻辑。

静态测试仅防止只读治理检查被删除；实时配置仍由 PowerShell 验证器和 API 证据负责。

## 7. 迁移与合并门禁验证

1. Impl PR 初始 head 在 ruleset 尚为空时完成本地测试与现有 PR Quality/Pages/CodeQL。
2. 保存：
   - repository rulesets 完整列表；
   - `GET /rules/branches/main` 活跃规则；
   - main branch protection；
   - CodeQL default setup。
3. 创建 ruleset，记录 ID、完整响应和创建时间。
4. GET by-ID 与 `GET /rules/branches/main` 验证目标字段及 active rule。
5. 在 active ruleset 下向 Impl PR 推送最终版本化证据修正。
6. 立即观察并记录 CodeQL 未完成时 PR 为不可合并/blocked；不得在此窗口执行 merge。
7. 等待 CodeQL 两种语言、汇总检查和原三个 required checks 全部成功；再次确认 PR CLEAN/MERGEABLE。
8. 运行 45/45 治理验证，固定 final head 合并。

第 6 步是实际门禁 smoke test：证明 ruleset 不只是存在于设置 JSON，而是真的参与 PR 合并判定。不得通过制造漏洞、提交凭据或关闭扫描来测试失败路径。

## 8. 验证计划

本地：

1. `git diff --check`
2. `npm run check`
3. 根路径与 Pages 子路径各 `npm test`
4. detector、audit、acceptance 三条 PowerShell 生产契约
5. 迁移前 verifier 预期只在 `codeql-merge-ruleset-exactly-one` 失败
6. 迁移后 verifier 45/45

远端：

1. Spec/Impl PR Quality、Pages、CodeQL 全绿；
2. active rules API 返回 code_scanning rule；
3. pending→blocked、success→CLEAN/MERGEABLE 证据；
4. main Quality、Pages、CodeQL 全绿；
5. deployment SHA 等于 merge SHA；
6. 三类 open alerts=0，线上四项资源 200 且哈希不变。

## 9. 风险与回滚

主要风险是错误 scope/工具名/阈值造成所有 PR 永久阻塞，或 API 创建了重复 ruleset。迁移前后必须以 GET 判定真实状态；POST 结果不明确时不得盲目重复创建。

若验证失败，使用创建响应中的唯一 ruleset ID 调用 DELETE；随后确认 repository rulesets 恢复空数组、main active rules 不再含本规则、旧 branch protection 与 CodeQL 配置不变。版本化文件通过新的 Issue/Spec/Impl revert PR 回滚；禁止强推或绕过现有保护。

## 10. 完成定义

Spec PR 与 Impl PR 均从各自创建时最新 `origin/main` 派生并合并；目标 ruleset 唯一、active、默认分支 only、无 bypass、唯一 CodeQL 工具与阈值精确；真实 PR 证明 pending 时被阻止且成功后可合并；45 项治理、PR/main CI、CodeQL、Pages deployment、三类告警与线上资源全部通过；Issue #29 写入证据并关闭。
