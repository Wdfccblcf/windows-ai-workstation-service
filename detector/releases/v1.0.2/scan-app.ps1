[CmdletBinding()]
param(
    [string]$OutputPath = ".\windows-ai-scan",
    [switch]$SelfTest,
    [switch]$DetectionOnly
)

$ErrorActionPreference = "Stop"
$adjacentAudit = Join-Path $PSScriptRoot "audit.ps1"
$publicRoot = Join-Path (Split-Path $PSScriptRoot -Parent) "public"
$auditScript = $(if (Test-Path -LiteralPath $adjacentAudit -PathType Leaf) { $adjacentAudit } else { Join-Path $publicRoot "audit.ps1" })
$repairLauncher = Join-Path $PSScriptRoot "Start-Repair-App.cmd"
$verifyScript = Join-Path $PSScriptRoot "verify-package.ps1"
$adjacentManifest = Join-Path $PSScriptRoot "SHA256SUMS.txt"
$kitRoot = $(if (Test-Path -LiteralPath $adjacentManifest -PathType Leaf) { $PSScriptRoot } else { Split-Path (Split-Path $PSScriptRoot -Parent) -Parent })
$script:RepairAvailable = $false # 检测专用发布包永久禁用修复入口

foreach ($required in @($auditScript, $verifyScript)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) { throw "缺少必需文件：$required" }
}

if ($SelfTest) {
    $source = Get-Content -Raw -Encoding UTF8 -LiteralPath $auditScript
    if ($source -notmatch '\$ExpectedCheckCount\s*=\s*19') { throw "体检脚本没有声明 19 项顺序检测。" }
    if ($source -notmatch 'audit-progress\.jsonl') { throw "体检脚本没有进度事件输出。" }
    Write-Output "SELFTEST PASS: sequential scanner declares 19 checks and progress events."
    exit 0
}

& $verifyScript -KitRoot $kitRoot -Quiet

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$script:OutputRoot = [IO.Path]::GetFullPath($OutputPath)
$script:ProgressPath = Join-Path $script:OutputRoot "audit-progress.jsonl"
$script:AuditJson = Join-Path $script:OutputRoot "audit.json"
$script:AuditReport = Join-Path $script:OutputRoot "audit-report.md"
$script:AuditProcess = $null
$script:SeenEvents = @{}

$form = New-Object System.Windows.Forms.Form
$form.Text = "Windows AI 自动检测器"
$form.StartPosition = "CenterScreen"
$form.Size = New-Object Drawing.Size(940, 720)
$form.MinimumSize = New-Object Drawing.Size(840, 640)
$form.BackColor = [Drawing.Color]::FromArgb(9, 20, 36)
$form.ForeColor = [Drawing.Color]::FromArgb(224, 242, 254)
$form.Font = New-Object Drawing.Font("Microsoft YaHei UI", 9)

$title = New-Object System.Windows.Forms.Label
$title.Text = "Windows AI 自动检测器"
$title.AutoSize = $true
$title.Font = New-Object Drawing.Font("Microsoft YaHei UI", 19, [Drawing.FontStyle]::Bold)
$title.ForeColor = [Drawing.Color]::FromArgb(34, 211, 238)
$title.Location = New-Object Drawing.Point(24, 18)
$form.Controls.Add($title)

$subtitle = New-Object System.Windows.Forms.Label
$subtitle.Text = "一项完成后自动检测下一项；单项失败不会中断整轮体检。检测只读，通常不需要管理员权限。"
$subtitle.AutoSize = $false
$subtitle.Size = New-Object Drawing.Size(870, 42)
$subtitle.Location = New-Object Drawing.Point(27, 58)
$subtitle.ForeColor = [Drawing.Color]::FromArgb(250, 204, 21)
$form.Controls.Add($subtitle)

$startButton = New-Object System.Windows.Forms.Button
$startButton.Text = "开始19项自动检测"
$startButton.Location = New-Object Drawing.Point(28, 108)
$startButton.Size = New-Object Drawing.Size(220, 40)
$startButton.BackColor = [Drawing.Color]::FromArgb(14, 116, 144)
$startButton.ForeColor = [Drawing.Color]::White
$startButton.FlatStyle = "Flat"
$form.Controls.Add($startButton)

$reportButton = New-Object System.Windows.Forms.Button
$reportButton.Text = "打开检测报告"
$reportButton.Location = New-Object Drawing.Point(265, 108)
$reportButton.Size = New-Object Drawing.Size(160, 40)
$reportButton.FlatStyle = "Flat"
$reportButton.Enabled = $false
$form.Controls.Add($reportButton)

$repairButton = New-Object System.Windows.Forms.Button
$repairButton.Text = $(if ($script:RepairAvailable) { "申请权限并进入修复" } else { "检测版不包含修复" })
$repairButton.Location = New-Object Drawing.Point(442, 108)
$repairButton.Size = New-Object Drawing.Size(190, 40)
$repairButton.BackColor = [Drawing.Color]::FromArgb(153, 27, 27)
$repairButton.ForeColor = [Drawing.Color]::White
$repairButton.FlatStyle = "Flat"
$repairButton.Enabled = $false
$form.Controls.Add($repairButton)

$folderButton = New-Object System.Windows.Forms.Button
$folderButton.Text = "打开结果目录"
$folderButton.Location = New-Object Drawing.Point(650, 108)
$folderButton.Size = New-Object Drawing.Size(150, 40)
$folderButton.FlatStyle = "Flat"
$form.Controls.Add($folderButton)

$progress = New-Object System.Windows.Forms.ProgressBar
$progress.Location = New-Object Drawing.Point(28, 166)
$progress.Size = New-Object Drawing.Size(870, 24)
$progress.Anchor = "Top,Left,Right"
$progress.Minimum = 0
$progress.Maximum = 100
$form.Controls.Add($progress)

$statusLabel = New-Object System.Windows.Forms.Label
$statusLabel.Text = "等待开始"
$statusLabel.AutoSize = $false
$statusLabel.Size = New-Object Drawing.Size(870, 28)
$statusLabel.Location = New-Object Drawing.Point(28, 198)
$statusLabel.ForeColor = [Drawing.Color]::FromArgb(125, 211, 252)
$form.Controls.Add($statusLabel)

$list = New-Object System.Windows.Forms.ListView
$list.Location = New-Object Drawing.Point(28, 232)
$list.Size = New-Object Drawing.Size(870, 380)
$list.Anchor = "Top,Bottom,Left,Right"
$list.View = "Details"
$list.FullRowSelect = $true
$list.GridLines = $true
$list.BackColor = [Drawing.Color]::FromArgb(15, 30, 50)
$list.ForeColor = [Drawing.Color]::FromArgb(226, 232, 240)
[void]$list.Columns.Add("序号", 55)
[void]$list.Columns.Add("分类", 100)
[void]$list.Columns.Add("检测项目", 350)
[void]$list.Columns.Add("状态", 100)
[void]$list.Columns.Add("进度", 100)
$form.Controls.Add($list)

$footer = New-Object System.Windows.Forms.Label
$footer.Text = "管理员权限只在客户决定执行特定修复时申请；检测阶段不会读取密码、密钥值、完整用户名或设备序列号。"
$footer.AutoSize = $false
$footer.Size = New-Object Drawing.Size(870, 42)
$footer.Location = New-Object Drawing.Point(28, 625)
$footer.Anchor = "Bottom,Left,Right"
$footer.ForeColor = [Drawing.Color]::FromArgb(148, 163, 184)
$form.Controls.Add($footer)

function Add-ProgressEventToList {
    param([object]$Event)
    if ([string]$Event.event -ne "check") { return }
    $key = "{0}:{1}" -f $Event.sequence, $Event.id
    if ($script:SeenEvents.ContainsKey($key)) { return }
    $script:SeenEvents[$key] = $true
    $item = New-Object System.Windows.Forms.ListViewItem([string]$Event.sequence)
    [void]$item.SubItems.Add([string]$Event.category)
    [void]$item.SubItems.Add([string]$Event.label)
    [void]$item.SubItems.Add(([string]$Event.status).ToUpperInvariant())
    [void]$item.SubItems.Add(("{0}%" -f $Event.percent))
    switch ([string]$Event.status) {
        "pass" { $item.ForeColor = [Drawing.Color]::FromArgb(74, 222, 128) }
        "warn" { $item.ForeColor = [Drawing.Color]::FromArgb(250, 204, 21) }
        "fail" { $item.ForeColor = [Drawing.Color]::FromArgb(248, 113, 113) }
        "blocked" { $item.ForeColor = [Drawing.Color]::FromArgb(251, 146, 60) }
    }
    [void]$list.Items.Add($item)
    $item.EnsureVisible()
    $progress.Value = [Math]::Max(0, [Math]::Min(100, [int]$Event.percent))
    $statusLabel.Text = "正在检测：$($Event.category) / $($Event.label)（$($Event.sequence)/$($Event.total)）"
}

function Refresh-ProgressEvents {
    if (-not (Test-Path -LiteralPath $script:ProgressPath -PathType Leaf)) { return }
    foreach ($line in @(Get-Content -LiteralPath $script:ProgressPath -Encoding UTF8 -ErrorAction SilentlyContinue)) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        try {
            $event = $line | ConvertFrom-Json
            Add-ProgressEventToList $event
        }
        catch {
            # 写入中的最后一行可能暂时不完整；下一次轮询会重新读取。
        }
    }
}

function Finish-Audit {
    Refresh-ProgressEvents
    $timer.Stop()
    $startButton.Enabled = $true
    $folderButton.Enabled = $true
    if (-not (Test-Path -LiteralPath $script:AuditJson -PathType Leaf)) {
        $statusLabel.Text = "检测失败：没有生成 audit.json，请查看 audit.log。"
        return
    }
    try {
        $audit = Get-Content -Raw -Encoding UTF8 -LiteralPath $script:AuditJson | ConvertFrom-Json
        $progress.Value = 100
        $statusLabel.Text = "检测完成：$(@($audit.checks).Count) 项，总体状态 $(([string]$audit.overallStatus).ToUpperInvariant())。"
        $reportButton.Enabled = (Test-Path -LiteralPath $script:AuditReport -PathType Leaf)
        $repairButton.Enabled = $script:RepairAvailable
    }
    catch {
        $statusLabel.Text = "报告读取失败：$($_.Exception.Message)"
    }
}

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 300
$timer.Add_Tick({
    Refresh-ProgressEvents
    if ($null -ne $script:AuditProcess -and $script:AuditProcess.HasExited) { Finish-Audit }
})

$startButton.Add_Click({
    if ($null -ne $script:AuditProcess -and -not $script:AuditProcess.HasExited) { return }
    try {
        [IO.Directory]::CreateDirectory($script:OutputRoot) | Out-Null
        $script:SeenEvents = @{}
        $list.Items.Clear()
        $progress.Value = 0
        $statusLabel.Text = "正在启动顺序检测引擎……"
        $startButton.Enabled = $false
        $reportButton.Enabled = $false
        $repairButton.Enabled = $false
        $arguments = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", ('"' + $auditScript + '"'), "-OutputPath", ('"' + $script:OutputRoot + '"'), "-PrivacyMode", "Strict") -join " "
        $script:AuditProcess = Start-Process -FilePath "powershell.exe" -ArgumentList $arguments -PassThru -WindowStyle Hidden
        $timer.Start()
    }
    catch {
        $startButton.Enabled = $true
        $statusLabel.Text = "启动失败：$($_.Exception.Message)"
    }
})

$reportButton.Add_Click({ if (Test-Path -LiteralPath $script:AuditReport) { Start-Process notepad.exe -ArgumentList ('"' + $script:AuditReport + '"') } })
$repairButton.Add_Click({ if ($script:RepairAvailable) { Start-Process -FilePath $repairLauncher -WorkingDirectory $PSScriptRoot } })
$folderButton.Add_Click({ [IO.Directory]::CreateDirectory($script:OutputRoot) | Out-Null; Start-Process explorer.exe -ArgumentList ('"' + $script:OutputRoot + '"') })

$form.Add_FormClosing({
    if ($null -ne $script:AuditProcess -and -not $script:AuditProcess.HasExited) {
        $answer = [System.Windows.Forms.MessageBox]::Show("检测仍在进行。关闭窗口会停止当前只读检测，已经完成的结果会保留。是否关闭？", "检测未结束", "YesNo", "Warning")
        if ($answer -ne "Yes") { $_.Cancel = $true; return }
        try { $script:AuditProcess.Kill() } catch {}
    }
})

[void]$form.ShowDialog()
