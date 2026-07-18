# Spec 0014：站点 landmark、跳过链接与可读交互契约

- 状态：Proposed
- 跟踪 Issue：[#14](https://github.com/Wdfccblcf/windows-ai-workstation-service/issues/14)
- 基线：`origin/main@32cc9ab7d7a8055d3400ca44c599d6bbf64c9011`
- 计划实现：独立 Impl PR，基于本 Spec PR 合并后的最新 `origin/main`

## 1. 问题与证据

公开站点已经具备响应式布局、跳过链接和语义化分区，但 2026-07-18 的桌面端与移动端浏览器检查发现：

- 唯一的 `main` 同时包住 `header`、内容与 `footer`，landmark 边界不准确；
- 跳过链接指向普通 `div#main-content`，激活后只改变 URL hash，`document.activeElement` 仍为 `body`；
- 页面没有统一的作者定义 `:focus-visible` 轮廓；
- `--mint-dark: #1c8b68` 在 `--paper: #f3f0e8` 上的对比度约为 3.73:1；
- `--muted: #637181` 在 `--paper: #f3f0e8` 上的对比度约为 4.38:1；
- 13 px 的 `.text-link` 实际高度约 16.7 px，普通导航链接约 17.3 px。

这会让键盘用户重复穿过导航，使辅助技术获得不准确的页面结构，也会降低弱视和移动端用户识别、激活链接的可靠性。

## 2. 目标

1. 建立唯一且边界正确的主内容 landmark。
2. 让跳过链接同时完成位置跳转和焦点转移。
3. 让所有链接在键盘聚焦时有一致、清晰的可见反馈。
4. 让浅色内容区的小号强调文字和次要文字达到至少 4.5:1 的对比度。
5. 将文本下载链接与导航链接的实现高度提升到至少 44 px，继续保持移动端无横向溢出。
6. 用构建后 HTML、源样式契约和真实浏览器行为共同防止回归。

## 3. 非目标

- 不重做品牌、文案、套餐、定价或信息架构。
- 不把 WCAG 合规声明扩展到未经本轮验证的全部成功标准。
- 不引入无障碍运行时、组件库、浏览器驱动或新的生产依赖。
- 不修改下载制品、SHA256、审计脚本、检测器 ZIP、Pages workflow 或服务流程。
- 不强制所有内联链接达到 44×44 px；本轮只覆盖站点主要导航和集中排列的下载文本链接。

## 4. 语义结构

页面顶层结构必须为：

```text
body
├── a.skip-link
├── header.site-header
├── main#main-content.site-main[tabindex="-1"]
└── footer
```

`main` 内只包含页面主要内容 section。`header` 与 `footer` 不得嵌套在 `main` 中；`#main-content` 不得再出现在 `.hero-grid` 或其他普通容器上；页面必须只有一个 `main` 和一个 `id="main-content"`。

`tabindex="-1"` 只允许程序化/片段导航聚焦，不把 `main` 插入正常 Tab 顺序。跳过链接仍为文档第一个可聚焦元素，并继续指向 `#main-content`。

## 5. 焦点契约

- 所有链接使用 `:focus-visible` 显示 3 px 实线高对比轮廓和至少 3 px 的偏移。
- 跳过链接聚焦时继续从视口外显现，不依赖颜色变化作为唯一反馈。
- `main#main-content:focus` 必须保留可见轮廓，确保跳过链接激活后的焦点位置可感知。
- 现有 hover、按钮位移和 `prefers-reduced-motion` 行为保持不变。
- 不允许使用 `outline: none` 或仅靠 box-shadow 隐藏原生焦点而不提供等效替代。

## 6. 色彩与尺寸

将浅色内容区使用的两个基础 token 调整为：

| Token | 新值 | 在 `#f3f0e8` 上 | 在 `#fffdf8` 上 |
|---|---:|---:|---:|
| `--mint-dark` | `#177355` | 约 5.09:1 | 约 5.71:1 |
| `--muted` | `#596874` | 约 5.04:1 | 约 5.65:1 |

以上结果必须由测试按 WCAG 相对亮度公式计算，不把 4.499:1 四舍五入为通过。深色区域继续使用其专用浅色 token，不把这两个值误用为深色背景上的正文。

主要导航链接与 `.text-link` 使用 `inline-flex` 垂直居中，并以 `min-height: 44px` 扩大可操作区域。`.text-link` 保留 13 px 粗体视觉层级，同时增加下划线与下划线偏移，让链接识别不只依赖颜色。按钮原有 `min-height: 48px` 不变。

## 7. 自动化契约

新增 `tests/accessibility-contract.test.mjs`，覆盖：

1. 读取构建后的 `out/index.html`，验证跳过链接指向 `#main-content`。
2. 验证唯一 `main` 同时具有 `id="main-content"`、`class="site-main"` 与 `tabindex="-1"`。
3. 验证 `header`、`main`、`footer` 顺序正确，且 `main` 内不包含 `header` 或 `footer`。
4. 验证 `#main-content` 唯一，不再附着在 `.hero-grid`。
5. 读取 `app/globals.css`，锁定焦点轮廓、44 px 高度、文本链接下划线及新色值。
6. 在测试内按 sRGB 相对亮度公式计算两个 token 对两种浅色背景的对比度，并逐组断言 `>= 4.5`。

现有 `npm test` 已匹配 `tests/*.test.mjs`，因此根路径构建和 Pages workflow 的项目子路径构建都会执行此契约，不需要修改 workflow。

## 8. 浏览器验收矩阵

| 场景 | 验收结果 |
|---|---|
| 桌面 1280×720 | 顶层 landmark 正确；跳过链接激活后焦点为 `MAIN#main-content` |
| 移动 390×844 | 无水平溢出；可见导航 CTA 与文本下载链接高度均至少 44 px |
| 键盘焦点 | Tab 聚焦链接时计算样式存在非零、非透明的 3 px 轮廓 |
| 浅色内容区 | 两个基础 token 对两种浅色背景的计算对比度均至少 4.5:1 |
| 控制台 | 页面加载、跳转及下载链接检查期间无新增错误 |

浏览器验收使用真实渲染结果，不用 JSX 结构推测交互行为。自动测试负责可重复的静态契约；浏览器检查负责焦点、尺寸、溢出和计算样式。

## 9. CI 与回归

Impl PR 必须同时通过：

- `npm run check`；
- 根路径 `npm test`；
- `NEXT_PUBLIC_BASE_PATH=/windows-ai-workstation-service npm test`；
- Windows PowerShell 5.1 审计契约；
- 检测器发布契约；
- `git diff --check`；
- GitHub Quality 的 Ubuntu/Windows job；
- GitHub Pages PR build，且 deploy 明确 skipped。

合并后必须等待 `origin/main` 的 Quality 与 Pages 部署成功，再对线上首页、CSS/JS、下载资源和跳过链接结构做只读回归。

## 10. 实现计划

1. 合并本 Spec PR，不夹带生产代码。
2. 从该合并提交后的最新 `origin/main` 创建 `agent/impl-14-site-accessibility`。
3. 重构 `app/page.tsx` 顶层 landmark 与跳过链接目标。
4. 更新 `app/globals.css` 的焦点、颜色和交互高度。
5. 新增自动化无障碍契约测试，不修改现有 workflow。
6. 完成本地双 base-path、PowerShell 和浏览器验收后推送 Draft Impl PR。
7. PR 全绿后转 Ready、合并，并验证主分支部署与线上页面。
8. 将测试 run、部署 SHA、浏览器指标和线上 smoke test 证据回写 Issue #14。

## 11. 风险与回滚

- `header` 使用绝对定位，移出 `main` 后仍以初始包含块定位；必须在桌面和移动视口确认位置无变化。
- 44 px 文本链接会扩大 `.audit-actions` 的高度，需确认换行和 section 间距未产生横向溢出。
- 色值变化会影响多个浅色区域，浏览器验收需抽查标题 kicker、列表标记、FAQ 编号和次要正文。
- 若合并后的 Pages 回归失败，优先 revert Impl 合并提交；Spec 和 Issue 保留作为证据，不改写历史或删除旧部署记录。

## 12. 完成定义

Spec PR 与 Impl PR 均已合并；Issue #14 关闭；自动契约、Windows/Ubuntu CI、Pages PR build、主分支部署和线上 smoke test 全部通过；浏览器证据确认跳过链接把焦点移入唯一 `main`、交互高度与对比度满足本 Spec；下载制品和哈希零变化。
