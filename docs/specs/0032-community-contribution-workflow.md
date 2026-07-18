# Spec 0032：社区贡献入口与 Issue/Spec/Impl 流程

- 状态：Proposed
- 跟踪 Issue：[#32](https://github.com/Wdfccblcf/windows-ai-workstation-service/issues/32)
- 基线：`origin/main@bc33e7bf5bed85686a5e87d046c010bff95866f3`
- 计划实现：独立 Impl PR，基于本 Spec PR 合并后的最新 `origin/main`

## 1. 问题与证据

最新仓库已经有受保护主分支、45 项治理、CodeQL 合并门禁和完整 Issue/Spec/Impl 历史，但 GitHub Community Profile API 返回 57%，以下入口均缺失：

- CONTRIBUTING
- issue template
- pull request template
- code of conduct

这意味着当前流程纪律依赖维护者手工复制，GitHub 新建 Issue/PR 页面不会主动要求贡献者填写优化原因、计划、验收、回滚、隐私边界和关联文档。

GitHub 官方说明 CONTRIBUTING 会出现在贡献入口并在创建 Issue/PR 时展示；Issue/PR 模板可标准化提交信息，Community Profile 会检测这些文件：

- [About community profiles](https://docs.github.com/en/communities/setting-up-your-project-for-healthy-contributions/about-community-profiles-for-public-repositories)
- [Setting guidelines for contributors](https://docs.github.com/en/communities/setting-up-your-project-for-healthy-contributions/setting-guidelines-for-repository-contributors)
- [About issue and pull request templates](https://docs.github.com/en/communities/using-templates-to-encourage-useful-issues-and-pull-requests/about-issue-and-pull-request-templates)
- [Creating a pull request template](https://docs.github.com/en/communities/using-templates-to-encourage-useful-issues-and-pull-requests/creating-a-pull-request-template-for-your-repository)

## 2. 文件边界

Impl PR 只允许新增：

1. `CONTRIBUTING.md`
2. `CODE_OF_CONDUCT.md`
3. `.github/ISSUE_TEMPLATE/optimization.yml`
4. `.github/ISSUE_TEMPLATE/bug.yml`
5. `.github/ISSUE_TEMPLATE/config.yml`
6. `.github/pull_request_template.md`
7. `tests/community-contract.test.mjs`

只在确有必要时允许修改：

- `README.md`，添加贡献入口；
- `docs/repository-governance.md`，说明模板维护契约。

不得修改应用源码、CSS、workflow、依赖、生产 PowerShell、ZIP、checksum、实时仓库设置或现有治理门禁。

## 3. CONTRIBUTING 契约

`CONTRIBUTING.md` 必须使用简体中文并包含：

1. 隐私/安全开场：不得公开 API Key、token、密码、客户数据、完整用户路径或未脱敏日志；漏洞和敏感行为举报走私密入口。
2. 变更分类：bug、optimization、docs、revert。
3. 强制顺序：
   - 从最新 `origin/main` 建 Issue；
   - 建纯规格 Spec PR，不能混入实现；
   - Spec 合并后重新从最新 `origin/main` 建 Impl PR；
   - 记录本地/fresh/PR/main/deployment/线上证据；
   - 回写 Issue checklist 并以 completed 关闭。
4. Issue 最低内容：基线、证据、为什么、边界/非目标、计划、验收、风险/回滚。
5. PR 最低内容：关联 Issue/Spec、base/head、变更清单、本地/fresh CI、隐私/制品影响、回滚。
6. 合并纪律：Draft→Ready、固定 head、不得 bypass、不得直接 push main、review threads 清零。
7. 本地验证命令：install/audit/check/test、Pages 子路径、三条 PowerShell 契约和 45 项治理。

## 4. Issue Forms

两个 Issue Form 使用 `.yml` 扩展名，但文件正文采用 JSON 语法。JSON 是 YAML 1.2 的合法子集，这样可用 Node 内置 `JSON.parse` 做严格语法与字段验证，无需新增 YAML 依赖。

### 4.1 optimization.yml

顶层必须有有效 `name`、`description`、`title` 和 `body`。稳定字段 ID：

- `baseline`
- `reason`
- `scope`
- `non_goals`
- `plan`
- `acceptance`
- `rollback`
- `privacy`

除说明性 markdown 外，所有 textarea 与 privacy checkboxes 均 required。验收默认值使用未勾选 checklist，计划要求有序步骤。

### 4.2 bug.yml

稳定字段 ID：

- `reproduction`
- `expected`
- `actual`
- `environment`
- `evidence`
- `impact`
- `acceptance`
- `rollback`
- `privacy`

日志/截图字段必须提示脱敏；privacy checkbox 必须明确不提交真实凭据、客户数据和可识别路径。

### 4.3 config.yml

- `blank_issues_enabled=false`
- 只有一个 contact link；
- name 明确为私密安全或行为举报；
- URL 精确为 `https://github.com/Wdfccblcf/windows-ai-workstation-service/security/advisories/new`；
- about 提醒不要公开敏感信息。

不得配置外部表单、付费支持或无模板入口。

## 5. Pull Request 模板

`.github/pull_request_template.md` 必须包含：

- PR type checklist：Spec / Impl / Revert / Docs；
- linked Issue 与 linked Spec；
- base SHA 与 final head SHA；
- 为什么改、变更内容、明确非目标；
- plan/implementation 对照；
- 本地、fresh clone、PR checks、main/deployment/online 的证据区；
- security/privacy、生产制品/hash、依赖与实时设置影响；
- 风险与回滚；
- final checklist：Issue/Spec/Impl 顺序、固定 head、无 bypass、review threads、Issue 回写。

模板是信息契约而非安全门禁；branch protection、CodeQL Ruleset 和 CI 仍是强制执行层。

## 6. 行为准则

`CODE_OF_CONDUCT.md` 使用 GitHub `codes_of_conduct/contributor_covenant` API 当前提供的 Contributor Covenant 2.0 正文，只替换 `[INSERT CONTACT METHOD]`：

- 使用现有 private vulnerability reporting URL；
- 要求标题以 `[Conduct]` 开头；
- 不要求公开个人身份、证据或联系方式；
- 保留原始 attribution、版本与链接。

这样既让 GitHub 稳定识别标准准则，又提供实际可用的私密执行入口。

## 7. 静态契约测试

`tests/community-contract.test.mjs` 必须仅使用 Node 内置模块，并验证：

1. 7 个目标文件存在；
2. 三个 `.yml` 文件可被 `JSON.parse` 严格解析；
3. 两个 form 的顶层键、稳定字段 ID、required 与 privacy 文案；
4. config 禁止 blank issue 且 contact link 精确；
5. PR 模板包含关联、原因、计划、验证、隐私、哈希、回滚和固定 head；
6. CONTRIBUTING 包含 Issue→Spec→Impl 顺序、命令与禁止 bypass；
7. Code of Conduct 不再含占位符，包含私密 URL、`[Conduct]` 与 Contributor Covenant attribution；
8. 文件中不出现明显凭据模式或真实本地用户路径。

测试加入现有 `node --test tests/*.test.mjs` 自动发现，不修改 package script 或 workflow。

## 8. 验证计划

本地：

1. `git diff --check`
2. `node --test tests/community-contract.test.mjs`
3. `npm run check`
4. 根路径与 Pages 子路径各 `npm test`，测试总数由 17 增加
5. detector、audit、acceptance 三条 PowerShell 契约
6. 45/45 repository governance
7. 变更路径白名单与生产产物 SHA256 零变化

远端：

1. Spec/Impl PR Quality、Pages、CodeQL 全绿；
2. CodeQL Ruleset 在 pending 时继续阻止，成功后允许固定 head 合并；
3. main Quality、Pages、CodeQL 全绿；
4. deployment SHA 等于 Impl merge SHA；
5. Community Profile API 的四个原缺失文件均非 null，`health_percentage=100`；
6. 三类 open alerts=0，45 项治理和线上资源哈希不变。

## 9. 风险与回滚

风险包括 Issue Form JSON 虽合法但 GitHub UI 不接受某字段、模板过度冗长、contact link 用途不清或 Community Profile 缓存延迟。必须以 GitHub API 检测与真实模板页面元数据验证为准，不能仅凭文件存在宣称成功。

若 PR 阶段发现问题，修正后重跑；若合并后才发现，通过新的 Issue/Spec/Impl revert PR 修正或删除相关文件。不得为模板问题放宽 branch protection、CodeQL Ruleset 或隐私安全控制。

## 10. 完成定义

Spec PR 与 Impl PR 均从各自创建时最新 `origin/main` 派生并合并；7 个目标文件和静态契约完整；本地/PR/main/CodeQL/Pages/PowerShell/45 项治理全部通过；Community Profile 100%；Issue/PR 入口实际检测有效；线上产物和哈希无变化；Issue #32 写入证据并关闭。
