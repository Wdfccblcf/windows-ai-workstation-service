# Spec 0041：补强 Pages 发布完整性与可追溯部署

## 1. 关联与基线

- 跟踪 Issue：[#41](https://github.com/Wdfccblcf/windows-ai-workstation-service/issues/41)
- 原始审查来源：[#12](https://github.com/Wdfccblcf/windows-ai-workstation-service/pull/12)
- 规格基线：`origin/main@eade27e5f10be8131298e63fb0f626ac04a5ffe8`
- 既有 Pages 规格：[`0011-pages-workflow-deployment.md`](./0011-pages-workflow-deployment.md)

本规格只补强 GitHub Pages workflow 的并发排队、发布前 Windows 契约门禁，以及线上 smoke 覆盖面。它不改变公开页面内容、下载资产字节、站点 URL、Pages 环境名称或仓库权限模型。

## 2. 问题陈述

PR #12 的三条审查意见在历史 PR 合并后仍保持 unresolved，当前 `main` 也仍存在对应缺口：

1. production concurrency 使用 `cancel-in-progress: false`，但没有显式声明无限排队；并发 push 的可追溯部署语义没有被代码化。
2. 线上 smoke 覆盖主页、说明页与部分下载文件，但遗漏 `/downloads/client-intake.md`。
3. deploy 只依赖 Ubuntu build，没有等待 Windows 上的发布契约测试；因此 Pages 可在 Windows 契约回归时继续部署。

本规格将这三项作为一个原子发布完整性边界：每个 `main` push 都排队、部署前同时通过站点构建与 Windows 发布契约、部署后验证完整的公开下载集合。

## 3. 决策

### 3.1 production 使用保序排队

顶层 `concurrency` 保留现有 PR 与 production 分组逻辑，并保持：

```yaml
cancel-in-progress: false
```

同时新增：

```yaml
queue: max
```

目标是让同一 production group 的每个 `main` push 都等待前序运行完成，而不是取消、替换或只保留最新一次运行。PR group 继续与 production 隔离。

不采用 latest-wins，也不把 SHA 拼入 production group；后者会绕开串行化并允许多个生产部署并发执行。

### 3.2 deploy 同时依赖 build 与 Windows release contracts

在 `.github/workflows/pages.yml` 增加独立 job：

```yaml
release-contracts:
  runs-on: windows-latest
```

该 job 必须 checkout 当前提交、安装 Node 依赖，并运行现有发布/验收契约所需的 Windows 测试。至少包括：

- `npm ci`
- `npm run check`
- `npm test`
- `tests/detector-release.test.ps1`
- `tests/detector-release-publication.test.ps1`
- `tests/audit-contract.test.ps1`
- `tests/acceptance-contract.test.ps1`

如仓库已有单一脚本或 npm 命令完整覆盖上述集合，可以调用该入口，但测试契约不得减少。

deploy 的依赖必须精确包含两个前置 job：

```yaml
needs: [build, release-contracts]
```

deploy 仍只在非 PR 的 `main` push 上运行；PR 必须运行 build 与 release-contracts 作为验证，但不得部署 Pages。

### 3.3 线上 smoke 覆盖 client intake

部署后的 smoke 必须把以下相对路径纳入同一套 base-path、2xx 与正文验证：

```text
/downloads/client-intake.md
```

该路径与既有公开下载路径使用同一个最终 Pages origin，不得通过 raw GitHub URL、仓库 contents API 或本地 artifact 代替线上验证。

## 4. 必须保持不变的边界

1. Pages workflow 仍只由 `main` push、pull request 和手动 dispatch 的既有触发器驱动。
2. 顶层权限继续最小化；build 与 release-contracts 不获得写权限。
3. deploy 继续绑定 `github-pages` environment，并只在 `main` 的非 PR 运行执行。
4. Pages artifact 的创建、上传和部署 Action owner 不变，不引入第三方 Action、PAT 或外部 secret。
5. 站点 base path、canonical URL、公开 HTML 与下载资产内容不改变。
6. Windows job 不发布 Release、不创建 tag、不上传 attestation，也不产生生产副作用。
7. 现有 Quality、Pages 和 CodeQL 检查仍全部保留。

## 5. 契约测试

扩展 `tests/pages-workflow.test.mjs`，至少断言：

1. 顶层 production concurrency 同时包含 `cancel-in-progress: false` 与 `queue: max`。
2. production group 没有包含提交 SHA，PR group 与 production group 仍相互隔离。
3. 存在 `release-contracts` job，且 runner 精确为 `windows-latest`。
4. Windows job checkout 当前 PR/head，并执行本规格要求的完整测试集合。
5. Windows job 没有写权限、发布命令或 production environment。
6. deploy 的 `needs` 同时包含且只包含 `build` 与 `release-contracts`。
7. deploy 的 main-only/non-PR 条件不变。
8. 线上 smoke 路径集合包含 `/downloads/client-intake.md`。
9. client-intake 使用部署输出的 Pages URL，执行 base-path 与 2xx 验证。

如果 workflow 文本测试无法可靠区分 YAML list 顺序，应比较集合而不是依赖序列；但不得仅搜索孤立字符串而忽略 job 边界。

## 6. CI 与运行时验证

### 6.1 Spec PR

- 只新增本规格文件；
- `git diff --check`；
- PR Quality、Pages、CodeQL 全绿；
- review threads 为 0；
- 固定 final head 后再合并。

### 6.2 Impl PR

- `git diff --check`
- `npm run check`
- `npm test`
- Windows PowerShell 契约测试全部通过
- Pages workflow 契约测试通过
- PR Quality、Pages、CodeQL 全绿
- PR run 中 build 与 release-contracts 成功，deploy skipped
- final head open CodeQL alerts 为 0
- review threads 为 0，且 PR 可合并

### 6.3 合并后的 main

- main push 的 build 与 release-contracts 都成功后，deploy 才开始；
- deployment 成功且 environment URL 指向预期 Pages 站点；
- online smoke 对 `/downloads/client-intake.md` 返回 2xx，并通过 base-path/正文检查；
- 与前一生产运行重叠时，新运行处于 queued/pending，前一运行不被取消；
- 两次运行最终按顺序完成，且各自保留独立可追溯的 deployment/run 记录；
- main Quality、Pages、CodeQL 均成功，open CodeQL alerts 为 0。

## 7. 合并顺序与审查线程

1. 先合并纯 Spec PR，不在该 PR 中修改 workflow 或测试。
2. 从最新 `main` 创建独立 Impl PR。
3. Impl 合并并完成 main 运行时验证后，分别回写 PR #12 的三条历史审查线程。
4. 只有在线证据可访问且契约测试通过，才 Resolve 对应线程并关闭 Issue #41。
5. 任一验证失败时保留线程 open，在同一实现 PR 中前向修正；不得直接 push 受保护的 `main`。

## 8. 回滚与故障处理

- Windows contract 失败：deploy 必须不运行；修复测试或产品契约后重新执行完整 workflow。
- build 失败：deploy 必须不运行；release-contracts 的成功不能绕过 build。
- deploy 或 online smoke 失败：保留失败 deployment 证据，通过新的受保护 PR 前向修正。
- concurrency 语法被 GitHub 拒绝：视为 workflow 加载失败，不能以跳过运行或移除测试代替修复。
- 排队验证不能通过人为取消前序生产运行制造成功；必须观察两个独立 `main` run 的真实排队与完成顺序。

## 9. 完成条件

Issue #41、纯 Spec PR 与独立 Impl PR 形成完整证据链；production concurrency 明确使用 `queue: max` 且不取消正在运行的部署；deploy 同时受 Ubuntu build 与 Windows release-contracts 门禁；线上 smoke 覆盖 `/downloads/client-intake.md`；PR 与 main 的 Quality、Pages、CodeQL 和 Windows 契约全部通过；历史三条审查线程回写最终证据并 Resolve 后，Issue #41 才以 `completed` 关闭。
