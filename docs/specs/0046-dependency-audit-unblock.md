# Spec 0046：恢复依赖审计并解除 CI 安全死锁

## 1. 关联与基线

- 跟踪 Issue：[#46](https://github.com/Wdfccblcf/windows-ai-workstation-service/issues/46)
- 发现载体：纯文档 PR [#45](https://github.com/Wdfccblcf/windows-ai-workstation-service/pull/45)
- Pages 失败运行：[32059636388](https://github.com/Wdfccblcf/windows-ai-workstation-service/actions/runs/32059636388)
- Quality 失败运行：[32059636427](https://github.com/Wdfccblcf/windows-ai-workstation-service/actions/runs/32059636427)
- 修复基线：`origin/main@eade27e5f10be8131298e63fb0f626ac04a5ffe8`

本规格处理 2026-08-17 npm advisory 数据更新后出现的高危依赖失败。PR #45 只新增 Markdown，但 Pages 与 Quality 都在 `npm audit --audit-level=high` 失败，证明故障属于基线依赖而不是 Pages 规格变更。

## 2. 已观察故障

失败日志报告 4 个漏洞：

1. `next@16.2.10`：high，多个 App Router、Server Actions、rewrites 与缓存相关 advisory。
2. `sharp@0.34.5`：high，继承 libvips CVE。
3. `nanoid@3.3.12`：high，非安全生成器的边界输入可无限循环。
4. `postcss@8.5.19`：moderate，source map 路径读取修复不完整。

审计命令按仓库既有 high 阈值正确退出 1；不得通过降低阈值、跳过 audit 或添加 allowlist 使其变绿。

## 3. 安全升级决策

只修改依赖清单与锁文件：

- `next`: `16.2.10` → `16.3.1`
- `postcss` override: `8.5.19` → `8.5.26`

重新解析的 lockfile 必须包含安全传递版本，包括：

- `sharp@0.35.3`
- `nanoid@3.3.18`
- Next.js 16.3.1 对应的 `@next/env` 与平台 SWC 包

不得顺带升级 React、React DOM、TypeScript 或类型包；不得改变应用代码、页面、workflow、权限或发布制品。

## 4. 紧急合并形态

常规纪律要求 Issue → 纯 Spec PR → 独立 Impl PR。但当前任意 spec-only PR 都会从有高危依赖的 `main` 运行同一 audit，并在实现修复合并前永久失败。由于 checks 不允许 bypass，常规顺序形成无法推进的安全死锁。

本项采用一次性例外：

1. 建立 Issue #46。
2. 同一个紧急 PR 的第一提交只新增本规格。
3. 第二提交只更新 `package.json` 与 `package-lock.json`。
4. 最终 head 仍需通过完整 Quality、Pages、CodeQL 与 review 门禁；不 bypass、不直接 push `main`、不降低 audit。
5. 该例外不改变后续普通变更的 Issue/Spec/Impl 双 PR 要求。

## 5. 验证契约

### 5.1 本地与 fresh install

- fresh `npm ci`
- `npm audit --audit-level=high` 返回 0，报告 `found 0 vulnerabilities`
- `npm run check`
- `npm test`
- Next.js production build成功
- Node 契约测试 30/30

### 5.2 PR

- 变更文件精确为本规格、`package.json`、`package-lock.json`
- Quality 的 Ubuntu 与 Windows job 全绿
- Pages build 全绿，PR deploy 保持 skipped
- CodeQL 全绿且 open alerts 为 0
- review threads 为 0
- 固定 final head 后再合并

### 5.3 main 与被阻断 PR

- 合并后的 main Quality、Pages、CodeQL 全绿
- main `npm audit --audit-level=high` 为 0
- Pages production deployment 与 online smoke 成功
- PR #45 更新到新的 main 基线，并在没有文档内容变更的前提下重新获得全绿 checks

## 6. 不可变边界

1. `audit:dependencies` 仍为 `npm audit --audit-level=high`。
2. 不添加 `--force`、`--legacy-peer-deps`、`--omit` 或忽略 advisory 的配置。
3. 不引入新的直接生产依赖。
4. React 与 React DOM 继续固定 19.2.7。
5. 应用源码、公开页面、下载文件与生产制品字节不因本项主动修改。
6. 所有写操作仍经受保护 PR；不使用管理员 bypass。

## 7. 回滚与前向修正

- 如果 Next 16.3.1 无法构建或契约测试失败，停止合并，不降低 audit 阈值；选择更高的安全版本前向修正。
- 如果锁文件在 Ubuntu 与 Windows 解析不同，以提交的 lockfile 和 `npm ci` 为唯一安装输入，不在 CI 中运行 `npm install`。
- 如果合并后发现运行时回归，建立新的 Issue 与受保护修正 PR；不能回退到已知高危版本。
- 如果 npm 新增 advisory 再次阻断，保留失败证据并选择当时最小安全版本，不重写本次历史。

## 8. 完成条件

Issue #46 与紧急双提交 PR 完整关联；最终 diff 只包含本规格和两个依赖文件；Next.js 16.3.1、PostCSS 8.5.26、Sharp 0.35.3 与 Nanoid 3.3.18 被锁定；fresh install、audit、build、30 项 Node 测试、Ubuntu/Windows Quality、Pages、CodeQL 和 main deployment 全绿；PR #45 基于修复后的 main 重跑成功；证据回写后 Issue #46 以 `completed` 关闭。
