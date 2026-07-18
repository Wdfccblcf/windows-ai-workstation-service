# Spec 0011：从 main 自动、可追溯地部署 GitHub Pages

- 状态：Proposed
- 跟踪 Issue：[#11](https://github.com/Wdfccblcf/windows-ai-workstation-service/issues/11)
- 基线：`origin/main@bb7406e2d4bb4d74a42978071634eeaba22b2653`
- 计划实现：独立 Impl PR，基于本 Spec PR 合并后的最新 `origin/main`

## 1. 问题与证据

仓库的静态站点构建已经有跨平台质量门禁，但线上发布仍不在这条门禁链中。2026-07-18 的只读核验结果为：

- Pages `build_type=legacy`；
- 发布源为未保护的 `gh-pages:/`；
- 发布分支停在 `e1ac46a7556a301e9d7ed2fd1cd92621118b6790`；
- 最新 `main` 为 `bb7406e2d4bb4d74a42978071634eeaba22b2653`；
- 仓库没有 Pages workflow；
- 自定义域名为 null，线上地址为 `https://wdfccblcf.github.io/windows-ai-workstation-service/`；
- HTTPS 已强制启用。

因此，当前线上 artifact 来自一次独立手工分支提交，无法从 `main` 合并记录复现其依赖安装、base path、测试、打包和发布过程。公开下载及 SHA256 清单虽在仓库内受测试保护，仍缺少“受测源提交就是线上部署源”的最后一段证据。

## 2. 目标

1. 每次 `main` push 自动构建并部署 Pages，也允许在 `main` 上手工 dispatch。
2. Pull Request 运行相同的项目站点 base-path 构建和 Pages artifact 打包，但永不部署。
3. 部署只接受前置 build job 生成的 `out/` artifact，并由 GitHub Pages deployment 关联源提交和 workflow run。
4. 将构建权限与部署权限分离，默认只读，部署 job 仅获得 Pages 和 OIDC 所需最小权限。
5. 合并后安全地把 Pages source 从 legacy 切换为 workflow，完成真实部署与线上内容 smoke test。
6. 保留旧 `gh-pages` 分支作为短期回滚证据，不让迁移变成不可逆操作。

## 3. 非目标

- 不修改页面组件、样式、文案、`audit.ps1`、检测器 ZIP 或下载哈希。
- 不引入第三方托管、部署机器人、长期凭据或仓库 secret。
- 不添加或修改自定义域名。
- 不关闭 HTTPS。
- 不删除、强推或改写旧 `gh-pages` 分支。
- 不用 workflow 替代现有 Windows/Ubuntu Quality；两条工作流职责独立。

## 4. 官方动作基线

实现时使用 2026-07-18 经 GitHub 官方仓库 latest release 核验的大版本：

- `actions/checkout@v6`；
- `actions/setup-node@v6`；
- `actions/configure-pages@v6`；
- `actions/upload-pages-artifact@v5`；
- `actions/deploy-pages@v5`。

选择 major tag 以接收同一大版本的安全修复；不使用 `main`、commit 不明的第三方 Action 或已经落后的官方示例版本。Node 固定为仓库已经验证的 22。

## 5. 触发器与部署边界

新增 `.github/workflows/pages.yml`：

- `push.branches=[main]`：构建并部署；
- `workflow_dispatch`：允许人工恢复或重试；
- `pull_request.branches=[main]`：构建并上传 artifact，部署 job 必须跳过。

deploy job 的条件必须同时满足：

- `github.ref == 'refs/heads/main'`；
- 事件不是 `pull_request`。

这样即使有人在其他分支手工 dispatch，也只能验证构建，不能发布该分支。

## 6. 权限与环境

工作流顶层权限仅为：

    contents: read

build job 不得授予写权限。deploy job 独立声明：

    pages: write
    id-token: write

deploy job 必须绑定 `github-pages` environment，并将 `actions/deploy-pages` 的 `page_url` 输出设置为 environment URL。不得使用 PAT、API Key 或自定义 secret。

## 7. 构建与 base path 契约

build job 在 `ubuntu-latest` 上按以下顺序执行：

1. checkout；
2. setup-node 22，并启用 npm cache；
3. configure-pages；
4. `npm ci`；
5. `npm run check`；
6. 在 `NEXT_PUBLIC_BASE_PATH=/windows-ai-workstation-service` 环境下运行 `npm test`；
7. 将 `out/` 作为唯一 Pages artifact 上传。

仓库已有 `next.config.ts`、`app/page.tsx` 与 `app/layout.tsx` 读取 `NEXT_PUBLIC_BASE_PATH`，所以 workflow 不使用 `static_site_generator: next` 自动改写配置，避免双重注入。当前无自定义域名，项目站点固定子路径与 Pages URL 一致。

构建必须继续执行现有 6 项静态站点/下载/哈希测试，不能为了部署速度跳过质量验证。

## 8. Artifact 与部署拓扑

build job 只上传 `./out`，不得上传仓库根、`.git`、`node_modules`、审计输出或工作目录。deploy job：

- `needs: build`；
- 不重新 checkout 或重新 build；
- 只运行 `actions/deploy-pages@v5`；
- 使用默认名为 `github-pages` 的前置 artifact。

这保证被部署的字节就是 build job 已测试并上传的字节。

## 9. 并发与超时

- 生产部署使用稳定的 `pages-production` 并发组；
- PR 构建使用与 PR 号关联的独立组，不阻塞生产发布；
- `cancel-in-progress=false`，不得中断已经开始的生产部署；
- build 和 deploy 设置有限超时，防止无期限占用 Runner。

若 GitHub 表达式需要统一 workflow 级并发组，必须保证 PR 与 production 的 key 不相同。

## 10. Pages source 迁移顺序

迁移是 Impl 完成的一部分，但不是源代码提交：

1. Impl PR 的 Quality 与 Pages PR build 全绿；
2. 将 PR 转为 Ready，并记录 legacy 配置和旧分支 SHA；
3. 通过 GitHub Pages API 将 `build_type` 更新为 `workflow`，不改域名或 HTTPS；
4. 立即 squash 合并固定 head 的 Impl PR；
5. 等待该 `main` push 的 Pages run；如未触发，则只在 `main` 上 dispatch；
6. 验证 deployment 的 `sha` 等于 Impl 合并提交；
7. 把迁移前后配置、run、deployment 和线上 smoke test 证据写回 Issue/PR。

切换 source 后旧站点内容应继续服务到新 deployment 替换。若真实部署失败且无法在同一轮修复，立刻把 Pages 恢复为 `build_type=legacy`、`gh-pages:/`，保留失败日志并继续修复，不删除旧分支。

## 11. PR 验证

Pull Request 应同时出现：

- 现有 Quality：Ubuntu/Windows 均通过；
- Pages workflow：build 通过、deploy 明确 skipped。

本地实现验证包括：

- `NEXT_PUBLIC_BASE_PATH=/windows-ai-workstation-service npm test`；
- `npm run check`；
- PowerShell 5.1 audit contract；
- detector release contract；
- `git diff --check`；
- workflow 结构检查，确认触发器、权限、条件、action major、artifact path 与 environment。

## 12. 线上 smoke test

真实部署成功后必须验证：

1. 首页返回 2xx；
2. HTML 中的 `/_next/`、favicon 和下载链接带 `/windows-ai-workstation-service` 前缀；
3. CSS/JS 关键静态资源返回 2xx；
4. `audit.ps1`、检测器 ZIP、PDF、SHA256 清单返回 2xx；
5. 线上 `audit.ps1` 与检测器 ZIP 的 SHA256 等于仓库清单；
6. Pages API 显示 `build_type=workflow`；
7. 最新 `github-pages` deployment 为 success，且源 SHA 等于 Impl 合并提交。

线上验证不得执行下载物，只读取 HTTP 响应并计算哈希。

## 13. 实现计划

1. 从 Spec PR 合并后的最新 `origin/main` 创建 `agent/impl-11-pages-deployment`。
2. 新增 Pages workflow，并补充 README 的自动部署、权限和本地 base-path 验证说明。
3. 不修改业务页面、公开下载或已有质量工作流。
4. 本地完整回归后，以 GitHub App 原子发布 workflow 文件和文档。
5. 创建 Draft Impl PR，等待 Quality 与 Pages build。
6. 按第 10 节完成配置迁移、合并、真实部署和线上验证。

## 14. 完成定义

Spec PR 和 Impl PR 均合并；Issue #11 关闭；Pages 为 workflow source；最新实现合并提交的 Pages deployment 成功；线上首页、关键资源、四个下载及两个 SHA256 通过；旧 `gh-pages` 分支保持原样可回滚。
