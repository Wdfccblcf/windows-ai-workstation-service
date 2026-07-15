import type { Metadata } from "next";

const basePath = process.env.NEXT_PUBLIC_BASE_PATH || "";

export const metadata: Metadata = {
  title: "Windows 11 AI 编程环境急诊台",
};

const packages = [
  {
    name: "只读体检",
    price: "99",
    label: "先看清问题",
    time: "24 小时内交付",
    warranty: "3 天报告答疑",
    featured: false,
    items: ["系统与硬件摘要", "Git / Python / Node / 编辑器", "WSL / Docker / AI CLI / MCP", "风险、缺失项与处理建议报告"],
  },
  {
    name: "标准搭建",
    price: "399",
    label: "适合第一次安装",
    time: "最多 90 分钟",
    warranty: "7 天同问题售后",
    featured: true,
    items: ["单台 Windows 11 电脑", "Git、Python、Node", "VS Code 或 Cursor", "1 个 AI CLI 与真实运行测试"],
  },
  {
    name: "完整搭建",
    price: "699",
    label: "开发环境一步到位",
    time: "最多 180 分钟",
    warranty: "两次会话，7 天售后",
    featured: false,
    items: ["包含标准搭建全部内容", "WSL 与 Docker", "最多 2 个 MCP", "1 个示例项目完整跑通"],
  },
];

const faqs = [
  ["会不会看到我的密码或 API Key？", "不会要求你发送密码、验证码或密钥。需要输入时由你本人操作；Strict 体检只记录“存在/不存在”，不记录变量值。"],
  ["是不是下单后什么报错都包修？", "不是。下单前先确认固定范围。网络封锁、第三方账号或额度、公司管控设备、Docker 深度数据损坏属于外部阻塞，报告会写明剩余步骤。"],
  ["远程时会操作我的私人文件吗？", "不会主动打开与本次安装无关的文件。客户全程在场；管理员授权、重启和系统功能变更都要单独确认。"],
  ["为什么只支持 Windows 11？", "首期先把一个系统做稳。Windows 10 会在脚本与远程流程完成验证后再开放。"],
  ["可以私下转账更便宜吗？", "不可以。所有订单和退款均走平台担保流程，页面不放微信、二维码或站外付款方式。"],
  ["修不好怎么办？", "若范围内操作因外部条件阻塞，仍交付已完成的体检、通过项、未通过项、阻塞原因和可执行的后续步骤；取消或退款按平台规则处理。"],
];

function StatusDot({ tone = "ok" }: { tone?: "ok" | "warn" | "fail" }) {
  return <span className={"status-dot " + tone} aria-hidden="true" />;
}

export default function Home() {
  return (
    <main>
      <a className="skip-link" href="#main-content">跳到主要内容</a>
      <header className="site-header">
        <a className="brand" href="#top" aria-label="返回首页">
          <span className="brand-mark">W11</span>
          <span>AI 环境急诊台</span>
        </a>
        <nav aria-label="主要导航">
          <a href="#packages">套餐</a>
          <a href="#audit">自助体检</a>
          <a href="#boundaries">服务边界</a>
          <a className="nav-cta" href="#how-to-order">平台下单</a>
        </nav>
      </header>

      <section id="top" className="hero">
        <div className="hero-grid" id="main-content">
          <div className="hero-copy">
            <p className="eyebrow"><span>Windows 11 专项</span> · 零基础也能跟上</p>
            <h1>AI 编程环境卡住了，<br /><em>先体检，再动手。</em></h1>
            <p className="hero-lead">
              Git、Python、Node、VS Code、Cursor、Docker、WSL、AI CLI 和 MCP，
              从“装不上”到真实跑通。平台担保，客户全程在场。
            </p>
            <div className="hero-actions">
              <a className="button primary" href="#how-to-order">查看下单方式</a>
              <a className="button secondary" href={basePath + "/downloads/audit.ps1"} download>下载只读体检脚本</a>
            </div>
            <ul className="trust-list" aria-label="服务承诺">
              <li><span>01</span> 不读取密钥内容</li>
              <li><span>02</span> 不无人值守远控</li>
              <li><span>03</span> 不安装破解软件</li>
            </ul>
          </div>

          <div className="diagnostic-card" aria-label="体检报告示意">
            <div className="terminal-bar">
              <div><i /><i /><i /></div>
              <span>AUDIT / STRICT</span>
              <b>只读</b>
            </div>
            <div className="machine-line">
              <span>设备</span>
              <strong>Windows 11</strong>
              <code>已脱敏</code>
            </div>
            <div className="scan-ring">
              <div className="scan-score"><strong>12</strong><span>项检查</span></div>
            </div>
            <div className="check-list">
              <div><span><StatusDot />Git / Python / Node</span><b>PASS</b></div>
              <div><span><StatusDot tone="warn" />系统盘可用空间</span><b>WARN</b></div>
              <div><span><StatusDot tone="fail" />Docker 引擎</span><b>BLOCKED</b></div>
              <div><span><StatusDot />API Key</span><b>仅记录存在性</b></div>
            </div>
            <p className="terminal-note">输出：audit.json · audit-report.md · audit.log</p>
          </div>
        </div>
      </section>

      <section className="signal-strip" aria-label="服务特点">
        <span>平台资金托管</span><i />
        <span>操作前给出范围</span><i />
        <span>逐项真实验收</span><i />
        <span>7 天有限售后</span>
      </section>

      <section className="section problem-section">
        <div className="section-heading">
          <p className="kicker">典型症状</p>
          <h2>不是你“电脑不行”，<br />通常是环境链条断了一环。</h2>
          <p>安装教程各说各话、版本和 PATH 互相打架、Docker 装了却启动不了——先定位断点，比反复重装更省时间。</p>
        </div>
        <div className="symptom-grid">
          <article><span>01</span><h3>命令找不到</h3><p>明明安装成功，终端却提示 git、python、node 不是命令。</p></article>
          <article><span>02</span><h3>版本互相冲突</h3><p>多套 Python 或 Node 抢占 PATH，教程步骤始终对不上。</p></article>
          <article><span>03</span><h3>Docker 假在线</h3><p>桌面程序已安装，但引擎、WSL 或 Compose 实际不可用。</p></article>
          <article><span>04</span><h3>AI 工具卡登录</h3><p>CLI 已安装，却卡在账号、权限、MCP 配置或网络环境。</p></article>
        </div>
      </section>

      <section id="packages" className="section package-section">
        <div className="section-heading centered">
          <p className="kicker">首批 3 单价格</p>
          <h2>范围先说清，再开始计时</h2>
          <p>完成首批 3 单后价格调整为 199 / 599 / 999 元。收入和修复结果不作夸大保证。</p>
        </div>
        <div className="package-grid">
          {packages.map((item) => (
            <article className={"package-card" + (item.featured ? " featured" : "")} key={item.name}>
              {item.featured && <span className="recommended">新手推荐</span>}
              <p className="package-label">{item.label}</p>
              <h3>{item.name}</h3>
              <div className="price"><span>¥</span><strong>{item.price}</strong><small>首批价</small></div>
              <ul>{item.items.map((line) => <li key={line}>{line}</li>)}</ul>
              <div className="package-meta"><span>{item.time}</span><span>{item.warranty}</span></div>
              <a className="button package-button" href="#how-to-order">查看下单步骤</a>
            </article>
          ))}
        </div>
      </section>

      <section id="audit" className="section audit-section">
        <div className="audit-copy">
          <p className="kicker">公开、只读、可复核</p>
          <h2>先让电脑自己把问题说清楚</h2>
          <p>体检脚本采用 MIT 代码许可。Strict 模式不输出用户名、完整用户路径、设备序列号、账号名、令牌或环境变量值。</p>
          <div className="audit-actions">
            <a className="button primary" href={basePath + "/downloads/audit.ps1"} download>下载 audit.ps1</a>
            <a className="text-link" href={basePath + "/downloads/service-guide.pdf"} download>下载服务 PDF</a>
            <a className="text-link" href={basePath + "/downloads/SHA256SUMS.txt"} download>核对 SHA256</a>
            <a className="text-link" href="https://github.com/Wdfccblcf/windows-ai-workstation-service" target="_blank" rel="noreferrer">在 GitHub 查看源码 ↗</a>
          </div>
        </div>
        <div className="code-panel">
          <div className="code-title"><span>PowerShell 5.1+</span><b>STRICT</b></div>
          <pre><code><span>powershell.exe</span> -NoProfile {"\u0060\n"}  -ExecutionPolicy Bypass {"\u0060\n"}  -File .\audit.ps1 {"\u0060\n"}  -OutputPath .\audit-output {"\u0060\n"}  -PrivacyMode Strict</code></pre>
          <div className="code-output">
            <span>生成 3 个文件</span>
            <b>audit.json</b><b>audit-report.md</b><b>audit.log</b>
          </div>
        </div>
      </section>

      <section className="section workflow-section">
        <div className="section-heading">
          <p className="kicker">固定交付流程</p>
          <h2>每一步都有确认点</h2>
        </div>
        <ol className="workflow">
          <li><span>01</span><div><h3>问诊与定范围</h3><p>确认系统版本、目标工具、错误截图、管理员权限与备份。</p></div></li>
          <li><span>02</span><div><h3>平台资金托管</h3><p>在闲鱼或合规任务平台完成对应金额托管后才开始。</p></div></li>
          <li><span>03</span><div><h3>只读体检</h3><p>客户本人运行公开脚本，先区分风险、缺失项和外部阻塞。</p></div></li>
          <li><span>04</span><div><h3>计划与逐项确认</h3><p>给出修复计划；管理员、重启或系统功能变更分别确认。</p></div></li>
          <li><span>05</span><div><h3>真实验收</h3><p>运行 Git、Python、Node、AI CLI；完整套餐再验收 Docker。</p></div></li>
          <li><span>06</span><div><h3>报告与有限售后</h3><p>交付通过项、未通过项、外部阻塞及后续建议。</p></div></li>
        </ol>
      </section>

      <section className="section case-section">
        <div className="case-card">
          <div className="case-title">
            <p className="kicker">匿名真实案例</p>
            <h2>Docker 已安装，<br />为什么还是不能用？</h2>
            <p>来自一台真实 Windows 11 工作站的脱敏审计经历。账号、用户名、令牌、完整路径和识别性截图均已删除。</p>
          </div>
          <div className="case-flow">
            <div><span>发现</span><strong>桌面程序存在</strong><p>但引擎连接失败，测试容器无法运行。</p></div>
            <div><span>定位</span><strong>运行时状态异常</strong><p>同时发现系统盘空间偏紧，增加后续更新风险。</p></div>
            <div><span>处理</span><strong>保留数据，定点修复</strong><p>没有先做整机重置，也没有创建付费 API Key。</p></div>
            <div><span>验收</span><strong>引擎与容器通过</strong><p>docker info 与 hello-world 均真实运行成功。</p></div>
          </div>
        </div>
      </section>

      <section id="boundaries" className="section boundary-section">
        <div className="section-heading">
          <p className="kicker">服务边界与隐私</p>
          <h2>能做什么，也明确写清不能做什么</h2>
        </div>
        <div className="boundary-grid">
          <article className="do-card"><h3>会这样做</h3><ul>
            <li>客户先备份并全程在场</li>
            <li>密码、验证码和密钥由客户输入</li>
            <li>每个高权限操作单独确认</li>
            <li>验收后 7 天删除客户文件</li>
            <li>仅经书面许可制作匿名案例</li>
          </ul></article>
          <article className="dont-card"><h3>不提供</h3><ul>
            <li>破解软件、账号绕过或无人值守远控</li>
            <li>数据恢复、恶意软件清理与硬件维修</li>
            <li>公司管控设备解锁</li>
            <li>自动卸载、无关注册表修改或整机更新</li>
            <li>绕开平台付款或私下退款</li>
          </ul></article>
        </div>
        <p className="boundary-note">Docker 深度数据损坏、网络封锁、第三方账号或额度问题记为“外部阻塞”，不承诺强行解决。</p>
      </section>

      <section className="section faq-section">
        <div className="section-heading centered">
          <p className="kicker">常见问题</p>
          <h2>下单前，先把顾虑问完</h2>
        </div>
        <div className="faq-list">
          {faqs.map(([question, answer], index) => (
            <details key={question}>
              <summary><span>{String(index + 1).padStart(2, "0")}</span>{question}<b>＋</b></summary>
              <p>{answer}</p>
            </details>
          ))}
        </div>
      </section>

      <section id="how-to-order" className="section order-section">
        <div>
          <p className="kicker">平台担保下单</p>
          <h2>先从 99 元只读体检开始</h2>
          <p>闲鱼商品链接需在手机端核验账号是否具备合规“服务”类目后补入。若无该类目，将切换到一品威客普通任务模式，不购买保证金或商铺。</p>
        </div>
        <div className="order-box">
          <span className="order-status"><StatusDot tone="warn" />第 4 天：待手机端类目核验</span>
          <p>闲鱼搜索词</p>
          <strong>Windows AI 环境搭建与排错</strong>
          <small>平台聊天内不提供微信、二维码或站外付款信息。</small>
          <a className="button primary" href={basePath + "/downloads/client-intake.md"} download>先下载问诊表</a>
        </div>
      </section>

      <footer>
        <div className="footer-brand"><span className="brand-mark">W11</span><strong>AI 环境急诊台</strong></div>
        <p>首期仅支持 Windows 11 · 平台担保交易 · 客户全程在场</p>
        <p className="legal">体检脚本采用 MIT 许可；案例文字、页面设计与营销素材不在 MIT 授权范围内。第三方软件与许可证费用由客户承担。</p>
      </footer>
    </main>
  );
}
