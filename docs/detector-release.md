# 检测器发布流程

本文定义 Windows AI 检测器的版本、GitHub Release、artifact attestation、验证和失败处理流程。规范来源为 [Spec 0035](./specs/0035-detector-github-release.md)，跟踪 Issue 为 [#35](https://github.com/Wdfccblcf/windows-ai-workstation-service/issues/35)。

## 版本命名

检测器使用独立组件 tag：

```text
detector-v<major>.<minor>.<patch>
```

检测器版本不与站点私有 npm package 版本联动。所有公开检测器继续保持 `detection-only` 只读边界，不包含修复，不申请管理员权限。tag 版本必须同时匹配版本目录、`release.json`、ZIP、独立 checksum 和 Release notes。首个正式发布 tag 是 `detector-v1.0.2`。

## 发布资产

每个 Release 只允许以下 5 类资产：

1. 版本化检测器 ZIP；
2. ZIP 独立 SHA-256 文件；
3. 主 `SHA256SUMS.txt`；
4. `release.json`；
5. `PROVENANCE.md`。

`RELEASE_NOTES.md` 只作为 Release body，不重复上传。发布流程只能复制已跟踪字节，不重新压缩或生成检测器内容。

## 权限模型

`.github/workflows/detector-release.yml` 顶层权限为 `contents: read`。Windows verify job 继承只读权限，运行现有检测器契约并准备 staging。

只有合法 `detector-v*` tag push 且 verify 成功时，publish job 才获得：

- `contents: write`，创建对应 tag 的 GitHub Release；
- `id-token: write`，取得短期 OIDC 身份；
- `attestations: write`，写入 GitHub artifact attestation。

workflow 不使用 PAT、外部 secret、第三方 Action、付费证书或 `pull_request_target`。手动 dispatch 不能进入 publish job。

## 每个版本的强制顺序

1. 从最新 `origin/main` 创建独立 Issue，记录版本内容、原因、资产、风险和验收。
2. 创建纯规格 Spec PR，固定版本、tag、权限、attestation 与回滚。
3. Spec 合并后，从新的最新 `origin/main` 创建 Impl PR。
4. 在 Impl PR 中验证 candidate、Windows 契约、两路径构建和所有 CI。
5. 使用固定 final head 合并 Impl PR，并等待 main CI 与 Pages deployment。
6. 在 main 上执行 manual dispatch dry-run。
7. dry-run 成功且 tag/Release 仍不存在时，从 Impl merge SHA 创建 annotated tag。
8. push tag，等待 publish workflow 生成并验证 attestations，再创建 Release。
9. 下载公开资产，比较 digest、SHA-256 与 attestation。
10. 回写 Issue checklist 和 run、tag、Release、asset、hash 证据。

任何步骤失败都必须停止后续步骤，不能绕过、直接 push `main` 或临时扩大 workflow 权限。

## 本地候选验证

Windows PowerShell 5.1：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\detector-release.test.ps1

$stage = Join-Path ([IO.Path]::GetTempPath()) 'detector-release-manual'
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\prepare-detector-release.ps1 `
  -TagName detector-v1.0.2 `
  -OutputDirectory $stage
```

输出目录必须位于仓库外并且不存在或为空。脚本失败时不会清空调用方预先存在的目录，也不会创建 tag、Release 或网络请求。

## main dry-run

实现合并后运行：

```powershell
gh workflow run detector-release.yml `
  --repo Wdfccblcf/windows-ai-workstation-service `
  --ref main `
  -f tag=detector-v1.0.2
```

验收条件：

- `Verify detector release candidate` 成功；
- `Attest and publish detector release` 显示 skipped；
- workflow artifact 含 5 个正式资产和 `RELEASE_NOTES.md`；
- 远端仍没有同名 tag 或 Release。

## 正式发布

只在 main 同步、工作树干净、main CI/dry-run 全绿后执行：

```powershell
git tag -a detector-v1.0.2 -m "Windows AI detector v1.0.2" <impl-merge-sha>
git push origin detector-v1.0.2
```

不得使用 `--force`。tag workflow 成功后验证：

```powershell
gh release view detector-v1.0.2 --repo Wdfccblcf/windows-ai-workstation-service
gh release download detector-v1.0.2 `
  --repo Wdfccblcf/windows-ai-workstation-service `
  --pattern 'windows-ai-detector-release-v1.0.2.zip' `
  --pattern 'SHA256SUMS.txt'
gh attestation verify .\windows-ai-detector-release-v1.0.2.zip `
  -R Wdfccblcf/windows-ai-workstation-service
gh attestation verify .\SHA256SUMS.txt `
  -R Wdfccblcf/windows-ai-workstation-service
```

还必须通过 Releases API 确认 5 个资产的名称和 digest，并确认 tag target 等于 Impl merge SHA。

## 停止与前向修正

- dry-run 失败：不创建 tag。
- tag workflow 瞬时失败：只 rerun 同一 tag 和提交。
- tag workflow 逻辑失败：不移动或删除 tag；建立新的 Issue/Spec/Impl 前向修正。
- Release 发布后：不替换同名资产、不重写 tag、不删除后重发同名版本。
- 内容或元数据需要更正：发布新的检测器版本。
- 涉及漏洞：只在 private vulnerability report 中处理敏感细节。
