# Spec 0023：React 19.2 patch 与类型定义同步

- 状态：Proposed
- 跟踪 Issue：[#23](https://github.com/Wdfccblcf/windows-ai-workstation-service/issues/23)
- 基线：`origin/main@414d693bc75a141b55a882b6b75520c9e6b6b3e5`
- 计划实现：独立 Impl PR，基于本 Spec PR 合并后的最新 `origin/main`

## 1. 问题与证据

2026-07-18 对基线执行 `npm outdated --json`，同一 React 19.2 兼容性边界内有三项 patch 更新：

- `react 19.2.6 → 19.2.7`
- `react-dom 19.2.6 → 19.2.7`
- `@types/react 19.2.14 → 19.2.17`

React 官方版本页将 19.2.7 列为最新 19.2 patch；官方 changelog 说明该版本修复 19.2.6 引入的 React Server Actions `FormData` 条目缺失回归：

- [React versions](https://react.dev/versions)
- [React changelog](https://github.com/react/react/blob/main/CHANGELOG.md)

Next.js `16.2.10` 已是当前 latest，其 npm peer range 为 `react/react-dom ^18.2.0 || ... || ^19.0.0`。`react-dom@19.2.7` 自身要求 `react@^19.2.7`，因此两者必须同步更新。

基线安全状态为 npm audit 0、Dependabot open 0、secret scanning open 0。更新目的不是修复当前公开漏洞告警，而是移除已知 patch 回归、保持同版本 React 配对并同步类型修正。

## 2. 目标版本与来源完整性

`package.json` 必须精确固定：

```json
{
  "dependencies": {
    "react": "19.2.7",
    "react-dom": "19.2.7"
  },
  "devDependencies": {
    "@types/react": "19.2.17"
  }
}
```

npm registry 当前返回的目标 tarball integrity 为：

- `react@19.2.7`：`sha512-HNe9WslTbXmFK8o8cmwgAeJFSBvt1bPdHCVKtaaV+WlAN36mpT4hcRpwbf3fY56ar2oIXzsBpOAiIRHAdY0OlQ==`
- `react-dom@19.2.7`：`sha512-t0BRVXvbiE/o20Hfw669rLbMCDWtYZLvmJigy2f0MxsXF+71pxhR3xOkspmsO8h3ZlNzyibAmtCa3l4lYKk6gQ==`
- `@types/react@19.2.17`：`sha512-MXfmqaVPEVgkBT/aY0aGCkRWWtByiYQXo3xdQ8r5RzuFrPiRn8Gar2tQdXSUQ2GKV3bkXckek89V8wQBY2Q/Aw==`

Impl 验证必须从 lockfile 读取并精确核对这些值，不只相信 `package.json`。

## 3. 版本化改动边界

Impl 只允许修改：

1. `package.json`
2. `package-lock.json`

使用 npm 正常解析依赖图，建议命令：

```powershell
npm install --save-exact react@19.2.7 react-dom@19.2.7
npm install --save-dev --save-exact @types/react@19.2.17
```

`package-lock.json` 必须继续使用现有 lockfileVersion、官方 npm registry URL 和 integrity。预期改变的逻辑节点仅为：

- 根 package 的三项直接版本；
- `node_modules/react`；
- `node_modules/react-dom`，其 peer dependency 同步为 `^19.2.7`；
- `node_modules/@types/react`。

若 npm 额外更新无关直接或传递依赖，必须先解释其依赖图原因；无法证明必要时不得纳入本轮。

`node_modules`、`.next`、`out`、npm cache 和日志不得提交。

## 4. 非目标

- 不升级 `@types/node 22.19.19 → 26.x`；项目运行时和 CI 均固定 Node 22，跨 major 另行评估。
- 不升级 `typescript 5.9.3 → 7.x`；跨 major 编译行为另行评估。
- 不修改 Next.js、`@types/react-dom` 或其他已处于 latest/目标兼容版本的直接依赖。
- 不修改页面源码、CSS、Next 配置、workflow、PowerShell、检测器、下载制品、checksum、仓库设置或服务文案。
- 不执行 `npm audit fix`、`--force` 或自动依赖升级机器人。

## 5. Lockfile 契约

实现后使用 Node 只读解析 `package-lock.json` 并断言：

- 根 dependencies/devDependencies 与 `package.json` 三个目标值一致；
- 三个 `node_modules/*` 节点版本、resolved URL 和 integrity 精确匹配；
- `react-dom` peer dependency 为 `^19.2.7`；
- lockfile 中不存在 `react@19.2.6`、`react-dom@19.2.6` 或 `@types/react@19.2.14` 的实际解析节点；
- lockfileVersion、项目名称、Node engine 和其他直接依赖版本不变。

执行 `npm ci` 后，`npm ls react react-dom @types/react --json` 必须只解析到目标版本，且依赖树无 invalid、extraneous 或 peer error。

## 6. 本地验证

1. `npm ci`
2. `npm run audit:dependencies`，必须为 0 vulnerabilities
3. `npm run check`
4. 根路径 `npm test`，当前 15 项全部通过
5. 设置 `NEXT_PUBLIC_BASE_PATH=/windows-ai-workstation-service` 后再次 `npm test`
6. Windows PowerShell 5.1：
   - detector release contract
   - audit privacy/output contract
   - acceptance output/privacy contract
7. `tools/verify-repository-governance.ps1`，当前 30 项全部通过
8. `npm outdated --json` 不再报告本轮三项；只允许保留已明确排除的跨 major 项
9. `git diff --check` 与变更路径白名单

必须记录 `audit.ps1`、检测器 ZIP、`tools/acceptance.ps1` 与 `public/downloads/SHA256SUMS.txt` 的前后 SHA256，证明生产下载字节零变化。

## 7. Fresh clone、CI 与部署

1. 从远端 Impl 分支做全新 clone，核对 head/tree 后运行 install/audit/check/test 和 lockfile 契约。
2. 创建 Draft Impl PR，等待受保护的：
   - `Verify (ubuntu-latest)`
   - `Verify (windows-latest)`
   - `Build Pages artifact`
3. 确认 Linux 与 Pages dependency audit 真实执行，Windows 三条生产契约真实执行，PR deploy 跳过。
4. 转 Ready，以固定 head SHA squash 合并；不 bypass、不直接 push `main`。
5. 等待主分支 Quality、Pages build/deploy，deployment SHA 必须等于 merge SHA。
6. 在最新 `origin/main` 复验依赖树、npm audit、30 项治理设置和线上关键资源 200/哈希。

## 8. 风险与回滚

React 19.2.7 的公开修复集中于 Server Actions；当前静态导出未直接使用该功能，因此运行时行为变化风险较低，但 Next 构建仍可能因 React renderer 或类型细节暴露回归。根路径/子路径静态构建、渲染契约、可访问性契约和线上 smoke 必须全部通过，不能仅凭 semver 假设兼容。

若 install、peer tree、类型、渲染或 CI 失败，停止合并并修正或关闭本轮。若合并后才发现回归，通过新的 Issue/Spec/Impl revert PR 将三项恢复为 19.2.6 / 19.2.14；不强推、不改写历史、不降低主分支保护。

## 9. 完成定义

Spec PR 与 Impl PR 均从各自创建时最新 `origin/main` 派生并合并，Issue #23 关闭；三项目标版本与 lockfile integrity 精确；无意外依赖图变化；本地、fresh clone、受保护 PR、主分支 CI、Pages deployment、30 项治理和线上资源全部通过；生产脚本、ZIP、checksum 与站点源码未修改。
