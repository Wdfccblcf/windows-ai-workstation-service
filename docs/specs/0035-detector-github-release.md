# Spec 0035：检测器 GitHub Release 与 artifact attestation

- 状态：Proposed
- 跟踪 Issue：[#35](https://github.com/Wdfccblcf/windows-ai-workstation-service/issues/35)
- 基线：`origin/main@00ec7f229a1fdd0e57d7f02b0f68c6813578b47d`
- 计划实现：独立 Impl PR，基于本 Spec PR 合并后的最新 `origin/main`

## 1. 问题与证据

仓库已经能够逐字节证明公开检测器 ZIP 的来源、内容、包内清单和 detection-only 边界，但还没有正式的软件发布对象：

- Git tag 数量为 0；
- GitHub Release 数量为 0；
- `windows-ai-detector-release-v1.0.2.zip` 只通过 Pages 的 default-branch 构建提供；
- 现有 SHA-256 证明字节一致，却没有把资产绑定到组件 tag、发布工作流和源提交；
- 用户无法通过 GitHub Release API 查看版本化资产与下载记录；
- ZIP 和 checksum manifest 没有 GitHub artifact attestation。

当前公开 ZIP 的规范 SHA-256 为：

```text
7c8c3c5f0fa28daa90729808dd91bc6e4d3065ba79867f3968b6a303e883de80
```

本规格依据：

- [About releases](https://docs.github.com/en/repositories/releasing-projects-on-github/about-releases)
- [Artifact attestations](https://docs.github.com/en/actions/concepts/security/artifact-attestations)
- [Using artifact attestations to establish provenance](https://docs.github.com/en/actions/how-tos/secure-your-work/use-artifact-attestations/use-artifact-attestations)

## 2. 决策摘要

1. 检测器使用独立组件 tag：`detector-v<major>.<minor>.<patch>`。
2. 首次正式发布现有 v1.0.2，不重新打包、不改变版本或字节。
3. `detector-v1.0.2` 必须指向 Impl PR 的 squash merge SHA。
4. 手动 `workflow_dispatch` 只执行验证和 staging dry-run，永远不能创建 tag 或 Release。
5. 只有受校验的 `detector-v*` tag push 能进入发布 job。
6. 发布 job 先生成并验证 attestations，再创建 GitHub Release。
7. workflow 只引用 GitHub-owned Actions，不使用 PAT、外部密钥、第三方服务或付费证书。
8. 已发布 tag 和同名 Release 资产不可移动、覆盖或重建；更正使用新版本。

## 3. 版本与 tag 契约

### 3.1 组件版本

检测器版本与站点私有 npm 工程版本相互独立：

- 检测器：`1.0.2`
- 站点 npm package：`0.1.0`

本轮不得为了对齐数字修改 `package.json`。

### 3.2 tag 格式

候选 tag 必须严格匹配：

```regex
^detector-v([0-9]+)\.([0-9]+)\.([0-9]+)$
```

不接受：

- 前导或尾随空白；
- `v1.0.2` 等缺少组件前缀的 tag；
- prerelease、build metadata、分支名或 SHA；
- 大小写变体；
- 路径分隔符和 shell 元字符。

从 tag 提取的版本必须同时等于：

1. `detector/releases/v<version>/release.json` 的 `version`；
2. `windows-ai-detector-release-v<version>.zip` 文件名版本；
3. 独立 checksum 文件名版本；
4. Release notes 标题版本；
5. GitHub Release title 版本。

### 3.3 tag 目标

正式 `detector-v1.0.2` 使用 annotated tag，并且：

- 目标必须是 Impl PR 的 squash merge SHA；
- 目标提交必须已位于 `main`；
- 创建前必须完成 main CI 和 workflow dispatch dry-run；
- push 后不得删除、移动或重指。

## 4. Release 资产契约

正式 Release 必须恰好上传以下 5 个资产：

1. `windows-ai-detector-release-v1.0.2.zip`
2. `windows-ai-detector-release-v1.0.2.zip.sha256.txt`
3. `SHA256SUMS.txt`
4. `release.json`
5. `PROVENANCE.md`

`RELEASE_NOTES.md` 作为 Release body 输入，不重复上传为资产。

资产必须来自 tag checkout 中已跟踪文件，只能复制到 staging，禁止重新压缩、格式化、换行转换或内容生成。staging 前后至少固定以下哈希：

| 文件 | 规范 SHA-256 |
|---|---|
| ZIP | `7c8c3c5f0fa28daa90729808dd91bc6e4d3065ba79867f3968b6a303e883de80` |
| ZIP checksum | `9362ed9823d07a056a4bca8e589751b97f2916132f686f5d0e49aa6d2cfe9e73` |
| 主 manifest | `7b57e822b9c9e30ada0fbf6c86b4f785e42a7cdef1b6c3e4ec978d7e1576e03f` |

`release.json` 和 `PROVENANCE.md` 由 staging 脚本按源文件重新计算哈希并记录在验证输出中，不硬编码为跨版本常量。

## 5. 候选发布准备脚本

新增 `tools/prepare-detector-release.ps1`，保持 Windows PowerShell 5.1 兼容、ASCII 源码和 `Set-StrictMode -Version Latest`。

### 5.1 输入

- `TagName`：必填，应用 3.2 的严格格式。
- `OutputDirectory`：必填，必须是不存在的目录或已存在但为空的目录。

脚本不得读取网络、GitHub token、用户 Git 配置、客户数据或凭据。

### 5.2 行为

1. 解析 tag 和版本。
2. 定位版本目录、ZIP、独立 checksum、主 manifest 和 notes。
3. 用显式 UTF-8 读取 `release.json` 并核对版本和 detection-only 元数据。
4. 解析两个 checksum 文件；拒绝重复、缺失、多余、绝对路径和路径穿越条目。
5. 对源文件重新计算 SHA-256。
6. 创建 staging 目录。
7. 只复制 5 个资产和一份仅供 workflow 使用的 `RELEASE_NOTES.md`。
8. 对 staging 文件复算 SHA-256，确认复制前后完全一致。
9. 输出版本、Release title、资产白名单和哈希摘要，不输出文件正文或环境隐私数据。

### 5.3 失败与清理

- 任一断言失败即非零退出；
- 若脚本创建了 staging 目录，失败时只允许清理该已验证目录；
- 不允许删除调用方预先存在的非空目录；
- 不修改仓库内任何文件；
- 不创建 tag、Release 或 attestation。

## 6. GitHub Actions workflow

新增 `.github/workflows/detector-release.yml`。

### 6.1 触发器

```yaml
on:
  push:
    tags:
      - "detector-v*"
  workflow_dispatch:
    inputs:
      tag:
        required: true
        default: "detector-v1.0.2"
```

glob 只是触发预过滤；最终合法性必须由准备脚本的严格 regex 决定。

### 6.2 顶层安全边界

- `permissions: contents: read`
- `concurrency` 以 event/ref 隔离，`cancel-in-progress: false`
- 禁止 `pull_request_target`
- 所有 `uses:` owner 必须为 `actions`
- workflow 输入通过 `env` 传给 PowerShell，禁止直接插入 `run` 字符串

### 6.3 verify job

Windows job 对 tag push 和 manual dispatch 都运行：

1. `actions/checkout@v6`
2. 运行现有 `tests/detector-release.test.ps1`
3. 运行 `tools/prepare-detector-release.ps1`
4. 生成稳定 step outputs：version、title、zip name
5. `actions/upload-artifact@v4` 上传 staging，保留 7 天

该 job 只有顶层 `contents: read`，不得获得写权限。

### 6.4 publish job

publish job 必须同时满足：

```text
github.event_name == 'push'
github.ref starts with refs/tags/detector-v
verify job succeeded
```

job 级权限恰好为：

```yaml
permissions:
  contents: write
  id-token: write
  attestations: write
```

执行顺序：

1. `actions/download-artifact@v5` 下载 verify job 的 staging。
2. 再次核对 5 个资产白名单和 notes 文件。
3. `actions/attest@v4` 为 ZIP 生成 attestation。
4. `actions/attest@v4` 为 `SHA256SUMS.txt` 生成 attestation。
5. 使用 `gh attestation verify` 立即验证两个 subject 均绑定当前仓库。
6. 使用 `gh release create` 和 `--verify-tag` 创建 Release，并显式列出 5 个资产。

不得使用宽泛 glob 上传资产，不得在 `gh release create` 前跳过 attestation verification。

### 6.5 dry-run 保证

当 event 为 `workflow_dispatch` 时：

- verify job 必须运行；
- staging artifact 必须生成；
- publish job 必须显示 skipped；
- tag、Release、attestation 均不得创建。

## 7. 发布说明与文档

新增 `detector/releases/v1.0.2/RELEASE_NOTES.md`，必须说明：

- 这是 detection-only 只读版本；
- 不包含修复、安装、管理员权限申请或自动上传；
- v1.0.2 ZIP 是现有规范字节的首次正式 GitHub Release，不是重新打包；
- 规范 ZIP SHA-256；
- 本地 checksum 和 `gh attestation verify` 命令；
- `release.json` 中历史 `18/18` 摘要不可独立复核，当前可复核证据是 19 项自检和仓库契约；
- 私密漏洞报告入口。

新增 `docs/detector-release.md`，记录：

- 版本命名和发布前置条件；
- Issue → Spec PR → Impl PR → dry-run → annotated tag → Release 顺序；
- 权限模型；
- 发布与下载后验证命令；
- 失败停止条件和 forward-only 修正策略。

README 只添加 Release 与验证入口，不改变现有 Pages 下载 URL。

## 8. 静态与运行时测试

新增 `tests/detector-release-publication.test.mjs`，只使用 Node 内置模块，至少验证：

1. workflow 触发器同时包含 tag 和 manual dry-run；
2. manual dispatch 被结构性排除在 publish job 之外；
3. 顶层 read、publish job 三项写权限精确；
4. workflow 无 `pull_request_target`、PAT、外部 secret 或第三方 Action；
5. verify → attest → verify attestation → release 的顺序；
6. `gh release create` 显式列出 5 个资产并使用 `--verify-tag`；
7. 准备脚本包含严格 tag、版本、checksum、空 staging 和复制后哈希契约；
8. notes、README 和发布文档包含隐私、安全、验证与 forward-only 边界；
9. 现有 ZIP、checksum、manifest 规范哈希没有变化。

`tests/repository-security.test.mjs` 必须把 release workflow 纳入 Action owner 和权限审计，但不得放宽 Quality/Pages 的只读断言。`docs/repository-governance.md` 记录唯一的 tag-only 发布写权限例外。

## 9. 验证计划

### 9.1 Spec PR

- 只新增本规格文件；
- `git diff --check`；
- PR Quality、Pages、CodeQL 全绿；
- review threads 清零；
- 固定 final head 合并。

### 9.2 Impl PR 本地

- `git diff --check`
- `npm run check`
- `npm test`
- Pages project-path `npm test`
- `tests/detector-release.test.ps1`
- `tests/audit-contract.test.ps1`
- `tests/acceptance-contract.test.ps1`
- 准备脚本正向与恶意 tag/非空 staging 负向测试
- 45/45 repository governance
- 所有既有生产资产 SHA-256 前后对比

### 9.3 Impl PR 与 main

- PR Quality、Pages、CodeQL 全绿；
- final head 开放 CodeQL alerts 为 0；
- Ready/CLEAN/MERGEABLE；
- 固定 final head squash 合并；
- main Quality、Pages、CodeQL 和 deployment 全绿。

### 9.4 live dry-run

从 Impl merge SHA 的 `main` 执行：

```powershell
gh workflow run detector-release.yml --ref main -f tag=detector-v1.0.2
```

验收 verify job 成功、publish job skipped，并再次确认 tag/Release 数量仍为 0。

### 9.5 正式发布

1. 在同步且干净的 `main` 上创建 annotated tag。
2. push `detector-v1.0.2`。
3. 等待 tag workflow 成功。
4. 验证 tag target 等于 Impl merge SHA。
5. 验证 Release title、body 和恰好 5 个资产。
6. 比较 GitHub asset digest、下载字节和仓库源字节。
7. 对下载 ZIP 和 manifest 运行 `gh attestation verify -R Wdfccblcf/windows-ai-workstation-service`。
8. 复验三类开放安全告警为 0。

## 10. 回滚与不可变策略

### tag 创建前

- dry-run 或任一检查失败即停止；
- 通过同一 Issue 的 Impl PR 修复；
- 不创建公开 tag 或 Release。

### tag 创建后、Release 创建前

- 瞬时失败只允许 rerun 同一 tag/提交的 workflow；
- 不移动或删除 tag；
- 若实现逻辑有缺陷，保留失败证据并通过新的 Issue/Spec/Impl 前向修复。

### Release 发布后

- 不替换同名资产；
- 不修改 tag 目标；
- 不删除后重新发布同名版本；
- 内容或元数据修正使用新版本和新 tag；
- 安全问题使用 private vulnerability report，并通过新版本发布修复。

## 11. 完成条件

Issue #35、Spec PR 和 Impl PR 均完整关联；`detector-v1.0.2` 指向已验证的 Impl merge SHA；正式 Release、5 个资产和两个 attestations 可由公开 GitHub 数据复核；main CI、Pages、安全告警、线上下载与既有制品哈希均无回归；Issue checklist 和证据回写后以 `completed` 关闭。
