# Spec 0038：修复检测器发布 workflow 的 runner context

## 1. 关联与基线

- Issue：[#38](https://github.com/Wdfccblcf/windows-ai-workstation-service/issues/38)
- 父发布 Issue：[#35](https://github.com/Wdfccblcf/windows-ai-workstation-service/issues/35)
- 初始发布 Spec PR：[#36](https://github.com/Wdfccblcf/windows-ai-workstation-service/pull/36)
- 初始发布 Impl PR：[#37](https://github.com/Wdfccblcf/windows-ai-workstation-service/pull/37)
- 修正规格基线：`origin/main@16828435fd6ef5aa28c542df5600ff04fe411636`
- 失败运行：[Actions run 29679575931](https://github.com/Wdfccblcf/windows-ai-workstation-service/actions/runs/29679575931)

本规格只修复 `.github/workflows/detector-release.yml` 的 context 可用位置错误，不改变检测器版本、公开制品、权限、tag、Release 资产或 attestation 契约。

## 2. 已观察故障

Impl PR #37 合并后，GitHub 在加载 workflow 时产生以下注解，且没有创建任何 job：

```text
Invalid workflow file: .github/workflows/detector-release.yml#L1
(Line: 29, Col: 22): Unrecognized named-value: 'runner'.
Located at position 1 within expression: runner.temp
```

失败运行绑定 main SHA `16828435fd6ef5aa28c542df5600ff04fe411636`，workflow 名称退化为文件路径，jobs API 返回 `total_count: 0`。因此这不是 runner 内脚本失败，而是 GitHub 在分配 runner 前的 workflow 加载失败。

正式 `detector-v1.0.2` tag、Release 与 attestations 此时均不存在，发布流程已在副作用前停止。

## 3. 根因

verify job 当前在 job 级 `env` 中声明：

```yaml
RELEASE_STAGE: ${{ runner.temp }}\detector-release
```

job 级字段由 GitHub 在 runner 分配前求值；`runner` context 在该位置不可用。GitHub 的 [Contexts reference](https://docs.github.com/en/actions/reference/workflows-and-actions/contexts) 要求按 workflow key 使用允许的 context，并说明 runner 进程环境变量应在 runner 执行的 step 中以操作系统语法读取。

Windows hosted runner 已向 step 提供 `RUNNER_TEMP` 默认环境变量，因此候选目录必须在 PowerShell step 运行时从 `$env:RUNNER_TEMP` 计算，而不是在 job 级 `env` 中求值 `runner.temp`。

## 4. 必须保持不变的边界

修正不得改变以下契约：

1. workflow 触发器仍只有 `detector-v*` tag push 和 `workflow_dispatch`。
2. manual dispatch 仍只运行 verify/staging，publish job 必须 skipped。
3. 顶层权限仍精确为 `contents: read`。
4. publish job 的权限仍恰好为 `contents: write`、`id-token: write`、`attestations: write`。
5. 所有 `uses:` owner 仍为 `actions`，不引入 PAT、外部 secret、第三方 Action 或 `pull_request_target`。
6. verify 顺序仍为 checkout、检测器契约、staging、artifact 上传。
7. publish 顺序仍为下载、白名单、两次 attestation、两次即时 verification、`gh release create --verify-tag`。
8. Release 仍只上传 5 个批准资产，`RELEASE_NOTES.md` 只作为正文。
9. 检测器版本仍为 `1.0.2`，首个 tag 仍为 `detector-v1.0.2`。
10. ZIP、独立 checksum、主 manifest、`release.json` 和 `PROVENANCE.md` 字节不得变化。

## 5. 精确实现

### 5.1 删除无效 job 级路径

verify job 的 `env` 只保留可在该位置使用的 `DETECTOR_TAG`。必须删除：

```yaml
RELEASE_STAGE: ${{ runner.temp }}\detector-release
```

verify job 的 job 级 `env` 不得再出现任何 `runner.*` 表达式。

### 5.2 在 staging step 运行期计算路径

`Stage exact release assets` 的 PowerShell 在调用准备脚本前执行：

```powershell
if ([string]::IsNullOrWhiteSpace($env:RUNNER_TEMP)) {
  throw 'RUNNER_TEMP is unavailable.'
}
$releaseStage = Join-Path $env:RUNNER_TEMP 'detector-release'
```

然后将 `$releaseStage` 传给：

```powershell
tools\prepare-detector-release.ps1 -OutputDirectory $releaseStage
```

不得改为仓库内目录，不得使用调用方输入拼接路径，也不得降低准备脚本现有的仓库隔离和空目录断言。

### 5.3 用 step output 传递路径

现有 `candidate` step 写入 `version`、`title` 和 `zip_name` 时，新增：

```text
release_stage=<absolute runner temp path>
```

继续使用 UTF-8 no BOM 写入 `$env:GITHUB_OUTPUT`。`Upload verified staging` 的 `path` 必须只引用：

```yaml
path: ${{ steps.candidate.outputs.release_stage }}
```

路径只在同一个 verify job 内传递，不新增 job output，也不传给 Linux publish job；publish job 继续只消费下载后的 artifact。

## 6. 测试修改

扩展 `tests/detector-release-publication.test.mjs`：

1. 截取 verify job 的 job 级 `env`，断言不存在 `runner.` 和 `RELEASE_STAGE`。
2. 断言 staging step 显式检查 `$env:RUNNER_TEMP`。
3. 断言使用 `Join-Path $env:RUNNER_TEMP 'detector-release'`。
4. 断言准备脚本接收 `-OutputDirectory $releaseStage`。
5. 断言 `candidate` step 输出 `release_stage=$releaseStage`。
6. 断言 upload action 的 `path` 精确使用 `steps.candidate.outputs.release_stage`。
7. 继续执行现有 tag-only、权限、Action owner、资产白名单、attestation 顺序和制品哈希断言。

Windows `tests/detector-release-publication.test.ps1` 不需要改变业务行为；它必须继续验证有效 staging、恶意 tag、非空目录保护、checksum 完整性和大小写不敏感的仓库隔离。

## 7. GitHub 加载验证

静态测试不能替代 GitHub 自身的 workflow 加载器。Impl PR 和 main 必须额外验证：

1. Impl head 不产生以 `.github/workflows/detector-release.yml` 为名称、`jobs=0` 的失败 run。
2. PR Quality、Pages、CodeQL 全绿。
3. Impl 合并后的 main push 不产生 invalid-workflow failure；tag-only 过滤器不应为普通 main push 创建发布 run。
4. main 的 manual dispatch 能找到名为 `Publish detector release` 的 workflow 并启动 verify job。
5. dry-run 的 verify job 成功，publish job skipped。
6. dry-run artifact 精确包含 5 个正式资产和 `RELEASE_NOTES.md`。
7. dry-run 前后同名 tag 与 Release 均不存在。

若第 1 或第 3 项发现任何 workflow 文件失败，即停止，不允许通过忽略额外失败 run 继续发布。

## 8. 验证计划

### 8.1 Spec PR

- 只新增本规格文件；
- `git diff --check`；
- PR Quality、Pages、CodeQL 全绿；
- review threads 为 0；
- 固定 final head squash 合并。

### 8.2 Impl PR 本地

- `git diff --check`
- `npm run check`
- 默认路径 `npm test`
- Pages project path `npm test`
- `tests/detector-release.test.ps1`
- `tests/detector-release-publication.test.ps1`
- `tests/audit-contract.test.ps1`
- `tests/acceptance-contract.test.ps1`
- `npm run audit:dependencies`
- 45/45 repository governance
- 既有生产制品 SHA-256 前后对比

### 8.3 Impl PR 与 main

- final head 固定；
- Quality、Pages、CodeQL 全绿；
- final head open CodeQL alerts 为 0；
- review threads 为 0，Ready/CLEAN/MERGEABLE；
- 固定 head squash 合并；
- main Quality、Pages、CodeQL 和 deployment 全绿；
- Impl head 与 main merge SHA 均没有 invalid-workflow failure。

### 8.4 live dry-run

从修正后的 main 执行：

```powershell
gh workflow run detector-release.yml `
  --repo Wdfccblcf/windows-ai-workstation-service `
  --ref main `
  -f tag=detector-v1.0.2
```

必须验收 verify 成功、publish skipped、artifact 文件集合和哈希精确，并确认 tag/Release 数量仍为 0。

## 9. 合并与恢复发布

1. Spec 与 Impl PR 均固定 head 合并，不直接 push `main`。
2. live dry-run 完成后回写 Issue #38 与父 Issue #35。
3. 以 `completed` 关闭 Issue #38。
4. 只有上述步骤全部通过，才恢复 Issue #35 的 annotated tag 创建与正式发布流程。
5. 正式 tag 最终必须指向修正 Impl PR 的 merge SHA，而不是初始 PR #37 的 merge SHA。

## 10. 回滚与前向修正

- tag 创建前任一失败：停止，不创建 tag，通过受保护 PR 修正。
- 不扩大 workflow 权限，不添加临时 PAT、第三方 Action 或 bypass。
- 已合并缺陷不通过重写历史处理；本 Issue、Spec PR 和 Impl PR 保留完整证据链。
- 若修正仍存在逻辑缺陷，建立新的 Issue → Spec PR → Impl PR，不在失败提交上移动或伪造发布 tag。

## 11. 完成条件

Issue #38、纯 Spec PR 和独立 Impl PR 完整关联；修正后的 workflow 可被 GitHub 加载，main manual dry-run 的 verify 成功且 publish skipped；没有 tag、Release 或 attestation 被提前创建；所有 CI、deployment、安全告警、artifact 文件集合和既有制品哈希无回归；证据回写后 Issue #38 以 `completed` 关闭，Issue #35 才恢复正式发布。
