[CmdletBinding()]
param(
    [Parameter()]
    [string]$OutputPath = ".\audit-output",

    [Parameter()]
    [ValidateSet("Strict", "Standard")]
    [string]$PrivacyMode = "Strict"
)

$ErrorActionPreference = "Stop"
$ScriptVersion = "1.1.0"
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$Checks = New-Object System.Collections.Generic.List[object]
$LogLines = New-Object System.Collections.Generic.List[string]
$ExpectedCheckCount = 19
$OutputRoot = $null
$LogPath = $null
$ProgressPath = $null

function ConvertTo-SafeText {
    param([AllowNull()][object]$Value)

    if ($null -eq $Value) {
        return ""
    }

    $text = [string]$Value
    if ($PrivacyMode -eq "Strict") {
        $profile = [Environment]::GetFolderPath("UserProfile")
        $userName = [Environment]::UserName

        if (-not [string]::IsNullOrWhiteSpace($profile)) {
            $text = [regex]::Replace($text, [regex]::Escape($profile), "<USERPROFILE>", "IgnoreCase")
        }
        if (-not [string]::IsNullOrWhiteSpace($userName)) {
            $text = [regex]::Replace($text, [regex]::Escape($userName), "<USER>", "IgnoreCase")
        }

        $text = [regex]::Replace($text, "(?i)[A-Z]:\\Users\\[^\\\s]+", "<USERPROFILE>")
        $text = [regex]::Replace($text, "(?i)\b(sk-[A-Za-z0-9_-]{8,}|gh[pousr]_[A-Za-z0-9_]{8,}|Bearer\s+\S+)\b", "<REDACTED>")
        $text = [regex]::Replace($text, "(?i)(token|api[_ -]?key|secret|password)\s*[:=]\s*\S+", '$1=<REDACTED>')
    }

    return $text.Trim()
}

function Write-SafeLog {
    param(
        [string]$Level,
        [string]$Message
    )

    $safe = ConvertTo-SafeText $Message
    $line = "{0} [{1}] {2}" -f (Get-Date).ToString("o"), $Level.ToUpperInvariant(), $safe
    $LogLines.Add($line) | Out-Null
}

function Write-ProgressEvent {
    param(
        [ValidateSet("start", "check", "complete", "error")]
        [string]$Event,
        [AllowNull()][object]$Check,
        [AllowEmptyString()][string]$OverallStatus = ""
    )

    if ([string]::IsNullOrWhiteSpace($ProgressPath)) { return }
    try {
        $sequence = $Checks.Count
        $progress = [pscustomobject][ordered]@{
            schemaVersion = "1.0"
            event = $Event
            timestamp = (Get-Date).ToString("o")
            sequence = $sequence
            total = $ExpectedCheckCount
            percent = [Math]::Min(100, [Math]::Round(($sequence / [double]$ExpectedCheckCount) * 100))
            id = $(if ($null -ne $Check) { [string]$Check.id } else { "" })
            category = $(if ($null -ne $Check) { [string]$Check.category } else { "" })
            label = $(if ($null -ne $Check) { [string]$Check.label } else { "" })
            status = $(if ($null -ne $Check) { [string]$Check.status } else { $OverallStatus })
        }
        [IO.File]::AppendAllText($ProgressPath, (($progress | ConvertTo-Json -Compress) + [Environment]::NewLine), $Utf8NoBom)
    }
    catch {
        Write-SafeLog "warn" "Progress event could not be written; audit continues."
    }
}

function Add-Check {
    param(
        [string]$Id,
        [string]$Category,
        [string]$Label,
        [ValidateSet("pass", "warn", "fail", "blocked")]
        [string]$Status,
        [AllowEmptyString()]
        [string]$DetectedVersion,
        [string]$Message,
        [string]$Recommendation
    )

    $item = [pscustomobject][ordered]@{
        id = $Id
        category = $Category
        label = $Label
        status = $Status
        detectedVersion = ConvertTo-SafeText $DetectedVersion
        message = ConvertTo-SafeText $Message
        recommendation = ConvertTo-SafeText $Recommendation
    }
    $Checks.Add($item) | Out-Null
    Write-SafeLog "info" ("{0}: {1} - {2}" -f $Id, $Status, $Message)
    Write-ProgressEvent "check" $item
}

function Get-Executable {
    param([string[]]$Names)

    foreach ($name in $Names) {
        $command = Get-Command $name -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($null -ne $command) {
            if (-not [string]::IsNullOrWhiteSpace($command.Path)) {
                return $command.Path
            }
            if (-not [string]::IsNullOrWhiteSpace($command.Source)) {
                return $command.Source
            }
        }
    }
    return $null
}

function Invoke-CapturedCommand {
    param(
        [string[]]$Names,
        [string[]]$ArgumentList = @(),
        [int]$TimeoutMilliseconds = 15000
    )

    $executable = Get-Executable $Names
    if ([string]::IsNullOrWhiteSpace($executable)) {
        return [pscustomobject]@{
            found = $false
            timedOut = $false
            exitCode = $null
            output = ""
        }
    }

    $argumentText = [string]::Join(" ", $ArgumentList)

    try {
        $startInfo = New-Object System.Diagnostics.ProcessStartInfo
        $startInfo.FileName = $executable
        $startInfo.Arguments = $argumentText
        $startInfo.UseShellExecute = $false
        $startInfo.CreateNoWindow = $true
        $startInfo.RedirectStandardOutput = $true
        $startInfo.RedirectStandardError = $true
        $process = New-Object System.Diagnostics.Process
        $process.StartInfo = $startInfo
        $null = $process.Start()
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        $finished = $process.WaitForExit($TimeoutMilliseconds)
        if (-not $finished) {
            try {
                $process.Kill()
            }
            catch {
            }
            return [pscustomobject]@{
                found = $true
                timedOut = $true
                exitCode = $null
                output = ""
            }
        }

        $process.WaitForExit()
        $stdout = $stdoutTask.Result
        $stderr = $stderrTask.Result

        return [pscustomobject]@{
            found = $true
            timedOut = $false
            exitCode = $process.ExitCode
            output = ConvertTo-SafeText (($stdout, $stderr -join [Environment]::NewLine).Trim())
        }
    }
    catch {
        return [pscustomobject]@{
            found = $true
            timedOut = $false
            exitCode = 9001
            output = ConvertTo-SafeText $_.Exception.Message
        }
    }
}

function Get-VersionLine {
    param([object]$CommandResult)

    if ($null -eq $CommandResult -or [string]::IsNullOrWhiteSpace($CommandResult.output)) {
        return ""
    }

    $line = ($CommandResult.output -split "\r?\n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -First 1)
    if ($null -eq $line) {
        return ""
    }
    return ConvertTo-SafeText $line
}

function Test-CommandConflict {
    param(
        [string]$Name,
        [string[]]$Candidates
    )

    $locations = New-Object System.Collections.Generic.List[string]
    foreach ($candidate in $Candidates) {
        Get-Command $candidate -All -ErrorAction SilentlyContinue | ForEach-Object {
            $path = $_.Path
            if ([string]::IsNullOrWhiteSpace($path)) {
                $path = $_.Source
            }
            if (-not [string]::IsNullOrWhiteSpace($path) -and -not $locations.Contains($path)) {
                $locations.Add($path) | Out-Null
            }
        }
    }

    if ($locations.Count -gt 1) {
        Add-Check ("path-conflict-{0}" -f $Name) "PATH" ("{0} PATH 冲突" -f $Name) "warn" "" ("检测到 {0} 个可执行入口，未输出完整路径。" -f $locations.Count) "在正式修复前确认默认版本，不要直接删除 PATH 项。"
    }
    elseif ($locations.Count -eq 1) {
        Add-Check ("path-conflict-{0}" -f $Name) "PATH" ("{0} PATH 冲突" -f $Name) "pass" "" "仅检测到一个可执行入口。" "无需处理。"
    }
    else {
        Add-Check ("path-conflict-{0}" -f $Name) "PATH" ("{0} PATH 冲突" -f $Name) "pass" "" "工具未安装，因此不存在版本入口冲突。" "安装后重新运行体检。"
    }
}

function Add-ToolVersionCheck {
    param(
        [string]$Id,
        [string]$Label,
        [string[]]$Names,
        [string[]]$VersionArguments,
        [ValidateSet("warn", "fail")]
        [string]$MissingStatus = "warn",
        [string]$MissingRecommendation = "如本次目标需要该工具，请先确认版本后再安装。"
    )

    $result = Invoke-CapturedCommand -Names $Names -ArgumentList $VersionArguments
    if (-not $result.found) {
        Add-Check $Id "开发工具" $Label $MissingStatus "" "未检测到可执行命令。" $MissingRecommendation
        return
    }
    if ($result.timedOut) {
        Add-Check $Id "开发工具" $Label "blocked" "" "版本检查超时。" "检查本地进程或终端配置后重试。"
        return
    }
    if ($result.exitCode -ne 0) {
        Add-Check $Id "开发工具" $Label "warn" (Get-VersionLine $result) "已找到命令，但版本检查返回非零退出码。" "检查安装完整性与 PATH 配置。"
        return
    }

    Add-Check $Id "开发工具" $Label "pass" (Get-VersionLine $result) "命令可执行。" "无需处理。"
}

try {
    $OutputRoot = [IO.Path]::GetFullPath($OutputPath)
    [IO.Directory]::CreateDirectory($OutputRoot) | Out-Null
    $LogPath = Join-Path $OutputRoot "audit.log"
    $ProgressPath = Join-Path $OutputRoot "audit-progress.jsonl"
    [IO.File]::WriteAllText($ProgressPath, "", $Utf8NoBom)

    Write-SafeLog "info" ("Windows AI workstation audit {0} started in {1} mode." -f $ScriptVersion, $PrivacyMode)
    Write-ProgressEvent "start" $null

    try {
        $os = Get-CimInstance Win32_OperatingSystem
        $osVersion = "{0} {1}" -f $os.Caption, $os.Version
        if ($os.Caption -match "Windows 11") {
            Add-Check "system-os" "系统" "Windows 版本" "pass" $osVersion "检测到 Windows 11。" "无需处理。"
        }
        else {
            Add-Check "system-os" "系统" "Windows 版本" "blocked" $osVersion "首期服务范围仅支持 Windows 11。" "暂不进入远程修复，等待 Windows 10 流程验证。"
        }
    }
    catch {
        Add-Check "system-os" "系统" "Windows 版本" "warn" "" "无法读取系统版本摘要。" "由客户在「设置 > 系统 > 系统信息」中确认。"
    }

    try {
        $computer = Get-CimInstance Win32_ComputerSystem
        $processor = Get-CimInstance Win32_Processor | Select-Object -First 1
        $memoryGb = [Math]::Round($computer.TotalPhysicalMemory / 1GB, 1)
        $hardware = "{0}; 内存 {1} GB" -f (ConvertTo-SafeText $processor.Name), $memoryGb
        if ($memoryGb -lt 8) {
            Add-Check "hardware-summary" "硬件" "硬件摘要" "warn" $hardware "内存低于 8 GB，可能影响 Docker 与多工具并行使用。" "优先使用标准套餐，减少同时运行的服务。"
        }
        else {
            Add-Check "hardware-summary" "硬件" "硬件摘要" "pass" $hardware "硬件摘要读取成功；未读取设备序列号。" "无需处理。"
        }
    }
    catch {
        Add-Check "hardware-summary" "硬件" "硬件摘要" "warn" "" "无法读取完整硬件摘要。" "本项不阻塞只读体检。"
    }

    try {
        $systemDrive = $env:SystemDrive
        if ([string]::IsNullOrWhiteSpace($systemDrive)) {
            $systemDrive = "C:"
        }
        $disk = Get-CimInstance Win32_LogicalDisk -Filter ("DeviceID='{0}'" -f $systemDrive)
        $freeGb = [Math]::Round($disk.FreeSpace / 1GB, 1)
        $totalGb = [Math]::Round($disk.Size / 1GB, 1)
        $diskSummary = "{0} 可用 / {1} GB" -f $freeGb, $totalGb
        if ($freeGb -lt 15) {
            Add-Check "disk-system" "磁盘" "系统盘空间" "fail" $diskSummary "系统盘可用空间低于 15 GB，安装或更新容易失败。" "先由客户确认并清理可安全删除的文件；不自动删除客户数据。"
        }
        elseif ($freeGb -lt 30) {
            Add-Check "disk-system" "磁盘" "系统盘空间" "warn" $diskSummary "系统盘可用空间低于 30 GB。" "安装 Docker、WSL 前建议预留至少 30 GB。"
        }
        else {
            Add-Check "disk-system" "磁盘" "系统盘空间" "pass" $diskSummary "系统盘空间满足首期建议。" "无需处理。"
        }
    }
    catch {
        Add-Check "disk-system" "磁盘" "系统盘空间" "warn" "" "无法读取系统盘空间。" "由客户在资源管理器中确认。"
    }

    try {
        $pathEntries = @($env:Path -split ";" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        $normalized = @($pathEntries | ForEach-Object { $_.Trim().TrimEnd("\").ToLowerInvariant() })
        $duplicateCount = @($normalized | Group-Object | Where-Object { $_.Count -gt 1 }).Count
        $missingCount = @($pathEntries | Where-Object { -not (Test-Path -LiteralPath $_ -ErrorAction SilentlyContinue) }).Count
        if ($duplicateCount -gt 0 -or $missingCount -gt 0) {
            Add-Check "path-health" "PATH" "PATH 健康度" "warn" "" ("检测到 {0} 组重复项、{1} 个失效目录；Strict 模式未输出路径。" -f $duplicateCount, $missingCount) "先核对依赖关系，再人工清理重复或失效项。"
        }
        else {
            Add-Check "path-health" "PATH" "PATH 健康度" "pass" "" "未发现重复项或失效目录。" "无需处理。"
        }
    }
    catch {
        Add-Check "path-health" "PATH" "PATH 健康度" "warn" "" "PATH 摘要检查失败。" "不要直接覆盖 PATH；人工核对后再处理。"
    }

    Add-ToolVersionCheck "tool-git" "Git" @("git.exe", "git") @("--version") "fail" "标准套餐需要 Git。"
    Add-ToolVersionCheck "tool-python" "Python" @("python.exe", "python", "py.exe", "py") @("--version") "fail" "标准套餐需要 Python。"
    Add-ToolVersionCheck "tool-uv" "uv" @("uv.exe", "uv") @("--version") "warn" "uv 为可选工具，按客户目标决定是否安装。"
    Add-ToolVersionCheck "tool-node" "Node.js" @("node.exe", "node") @("--version") "fail" "标准套餐需要 Node.js。"
    Add-ToolVersionCheck "tool-npm" "npm" @("npm.cmd", "npm.exe", "npm") @("--version") "fail" "标准套餐需要 npm。"

    Test-CommandConflict "git" @("git.exe", "git")
    Test-CommandConflict "python" @("python.exe", "python", "py.exe", "py")
    Test-CommandConflict "node" @("node.exe", "node")

    $code = Invoke-CapturedCommand @("code.cmd", "code.exe", "code") @("--version")
    $cursor = Invoke-CapturedCommand @("cursor.cmd", "cursor.exe", "cursor") @("--version")
    if (($code.found -and $code.exitCode -eq 0) -or ($cursor.found -and $cursor.exitCode -eq 0)) {
        $editors = New-Object System.Collections.Generic.List[string]
        if ($code.found -and $code.exitCode -eq 0) {
            $editors.Add(("VS Code {0}" -f (Get-VersionLine $code))) | Out-Null
        }
        if ($cursor.found -and $cursor.exitCode -eq 0) {
            $editors.Add(("Cursor {0}" -f (Get-VersionLine $cursor))) | Out-Null
        }
        Add-Check "tool-editor" "编辑器" "VS Code / Cursor" "pass" ($editors -join "; ") "至少一个目标编辑器可执行。" "无需处理。"
    }
    else {
        Add-Check "tool-editor" "编辑器" "VS Code / Cursor" "fail" "" "未检测到可执行的 VS Code 或 Cursor 命令。" "标准套餐至少安装并验证其中一个编辑器。"
    }

    $wsl = Invoke-CapturedCommand @("wsl.exe", "wsl") @("--status")
    if (-not $wsl.found) {
        Add-Check "platform-wsl" "平台" "WSL" "warn" "" "未检测到 WSL 命令。" "仅完整套餐需要 WSL；启用系统功能前单独确认。"
    }
    elseif ($wsl.timedOut) {
        Add-Check "platform-wsl" "平台" "WSL" "blocked" "" "WSL 状态检查超时。" "检查 Windows 功能和 WSL 服务状态。"
    }
    elseif ($wsl.exitCode -eq 0) {
        Add-Check "platform-wsl" "平台" "WSL" "pass" "" "WSL 状态命令执行成功；未输出发行版账号信息。" "完整套餐中再验证发行版运行。"
    }
    else {
        Add-Check "platform-wsl" "平台" "WSL" "warn" "" "WSL 命令存在，但状态检查未通过。" "完整套餐中检查 Windows 功能、虚拟化和发行版状态。"
    }

    $dockerVersion = Invoke-CapturedCommand @("docker.exe", "docker") @("--version")
    if (-not $dockerVersion.found) {
        Add-Check "platform-docker" "平台" "Docker 引擎" "warn" "" "未检测到 Docker CLI。" "仅完整套餐需要 Docker。"
        Add-Check "platform-compose" "平台" "Docker Compose" "warn" "" "未检测到 Docker CLI，未继续检查 Compose。" "安装 Docker 后重新验证。"
    }
    else {
        $dockerInfo = Invoke-CapturedCommand @("docker.exe", "docker") @("info") 20000
        if ($dockerInfo.timedOut) {
            Add-Check "platform-docker" "平台" "Docker 引擎" "blocked" (Get-VersionLine $dockerVersion) "Docker 引擎检查超时。" "确认 Docker Desktop 是否启动；不自动重置数据。"
        }
        elseif ($dockerInfo.exitCode -ne 0) {
            Add-Check "platform-docker" "平台" "Docker 引擎" "blocked" (Get-VersionLine $dockerVersion) "Docker 已安装，但引擎当前不可用。" "先启动 Docker Desktop；若仍失败，再做保留数据的定点排查。"
        }
        else {
            Add-Check "platform-docker" "平台" "Docker 引擎" "pass" (Get-VersionLine $dockerVersion) "Docker CLI 与引擎均可用。" "完整套餐验收时再运行测试容器。"
        }

        $compose = Invoke-CapturedCommand @("docker.exe", "docker") @("compose", "version")
        if ($compose.exitCode -eq 0) {
            Add-Check "platform-compose" "平台" "Docker Compose" "pass" (Get-VersionLine $compose) "Compose 命令可执行。" "无需处理。"
        }
        else {
            Add-Check "platform-compose" "平台" "Docker Compose" "warn" "" "Compose 命令不可用或返回异常。" "检查 Docker Desktop 组件完整性。"
        }
    }

    $aiTools = @(
        @{ Name = "Codex CLI"; Commands = @("codex.cmd", "codex.exe", "codex"); Args = @("--version") },
        @{ Name = "Claude CLI"; Commands = @("claude.exe", "claude.cmd", "claude"); Args = @("--version") },
        @{ Name = "Gemini CLI"; Commands = @("gemini.exe", "gemini.cmd", "gemini"); Args = @("--version") }
    )
    $aiDetected = New-Object System.Collections.Generic.List[string]
    foreach ($tool in $aiTools) {
        $result = Invoke-CapturedCommand $tool.Commands $tool.Args
        if ($result.found -and $result.exitCode -eq 0) {
            $aiDetected.Add(("{0} {1}" -f $tool.Name, (Get-VersionLine $result))) | Out-Null
        }
    }
    if ($aiDetected.Count -gt 0) {
        Add-Check "ai-cli" "AI 工具" "AI CLI" "pass" ($aiDetected -join "; ") ("检测到 {0} 个可执行的 AI CLI；未执行登录。" -f $aiDetected.Count) "标准套餐只选择一个目标 CLI 做登录状态验收。"
    }
    else {
        Add-Check "ai-cli" "AI 工具" "AI CLI" "warn" "" "未检测到 Codex、Claude 或 Gemini CLI。" "按客户现有账号和许可证选择一个安装，不默认创建付费 API Key。"
    }

    $codexPath = Get-Executable @("codex.cmd", "codex.exe", "codex")
    if ([string]::IsNullOrWhiteSpace($codexPath)) {
        Add-Check "mcp-status" "AI 工具" "MCP 状态" "warn" "" "未检测到 Codex CLI，无法读取 MCP 状态。" "如客户选择 Codex，再按完整套餐范围配置最多两个 MCP。"
    }
    else {
        $mcp = Invoke-CapturedCommand @("codex.cmd", "codex.exe", "codex") @("mcp", "list")
        if ($mcp.timedOut) {
            Add-Check "mcp-status" "AI 工具" "MCP 状态" "blocked" "" "MCP 状态检查超时。" "检查 CLI 进程与本地配置后重试。"
        }
        elseif ($mcp.exitCode -eq 0) {
            Add-Check "mcp-status" "AI 工具" "MCP 状态" "pass" "" "MCP 状态命令可执行；Strict 模式未输出服务器地址、账号或完整路径。" "完整套餐中按固定范围验证最多两个 MCP。"
        }
        else {
            Add-Check "mcp-status" "AI 工具" "MCP 状态" "warn" "" "Codex CLI 存在，但 MCP 状态命令未通过。" "检查 Codex 版本和配置文件格式。"
        }
    }

    $keyNames = @("OPENAI_API_KEY", "ANTHROPIC_API_KEY", "GOOGLE_API_KEY", "GEMINI_API_KEY")
    $keyStates = New-Object System.Collections.Generic.List[string]
    foreach ($keyName in $keyNames) {
        $exists = -not [string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable($keyName))
        $state = if ($exists) { "存在" } else { "不存在" }
        $keyStates.Add(("{0}：{1}" -f $keyName, $state)) | Out-Null
    }
    Add-Check "api-key-presence" "隐私" "API Key 存在性" "pass" "" ($keyStates -join "；") "脚本不会输出任何密钥值；默认不创建付费 API Key。"

    $statuses = @($Checks | Select-Object -ExpandProperty status)
    $overallStatus = "pass"
    if ($statuses -contains "fail") {
        $overallStatus = "fail"
    }
    elseif ($statuses -contains "blocked") {
        $overallStatus = "blocked"
    }
    elseif ($statuses -contains "warn") {
        $overallStatus = "warn"
    }

    $summary = [ordered]@{
        pass = @($Checks | Where-Object { $_.status -eq "pass" }).Count
        warn = @($Checks | Where-Object { $_.status -eq "warn" }).Count
        fail = @($Checks | Where-Object { $_.status -eq "fail" }).Count
        blocked = @($Checks | Where-Object { $_.status -eq "blocked" }).Count
    }

    $document = [pscustomobject][ordered]@{
        schemaVersion = "1.0"
        scriptVersion = $ScriptVersion
        generatedAt = (Get-Date).ToString("o")
        privacyMode = $PrivacyMode
        overallStatus = $overallStatus
        summary = $summary
        checks = @($Checks | ForEach-Object { $_ })
        privacyNotice = "Strict 模式不输出用户名、完整用户路径、设备序列号、账号名、令牌或环境变量值。API Key 只记录存在或不存在。"
    }

    $jsonPath = Join-Path $OutputRoot "audit.json"
    [IO.File]::WriteAllText($jsonPath, ($document | ConvertTo-Json -Depth 8), $Utf8NoBom)

    $reportLines = New-Object System.Collections.Generic.List[string]
    $reportLines.Add("# Windows AI 环境只读体检报告") | Out-Null
    $reportLines.Add("") | Out-Null
    $reportLines.Add(("- 生成时间：{0}" -f $document.generatedAt)) | Out-Null
    $reportLines.Add(("- 隐私模式：{0}" -f $PrivacyMode)) | Out-Null
    $reportLines.Add(("- 总体状态：**{0}**" -f $overallStatus)) | Out-Null
    $reportLines.Add(("- 汇总：pass {0} / warn {1} / fail {2} / blocked {3}" -f $summary.pass, $summary.warn, $summary.fail, $summary.blocked)) | Out-Null
    $reportLines.Add("") | Out-Null
    $reportLines.Add("> 本报告为只读体检结果，不代表已执行修复。Strict 模式不会记录密钥值。") | Out-Null
    $reportLines.Add("") | Out-Null
    $reportLines.Add("| 状态 | 检查项 | 检测结果 | 建议 |") | Out-Null
    $reportLines.Add("|---|---|---|---|") | Out-Null
    foreach ($check in $Checks) {
        $message = (($check.message -replace "\|", "\/") -replace "\r?\n", " ")
        $recommendation = (($check.recommendation -replace "\|", "\/") -replace "\r?\n", " ")
        $version = (($check.detectedVersion -replace "\|", "\/") -replace "\r?\n", " ")
        $resultText = $message
        if (-not [string]::IsNullOrWhiteSpace($version)) {
            $resultText = "{0}（{1}）" -f $message, $version
        }
        $reportLines.Add(("| {0} | {1} | {2} | {3} |" -f $check.status, $check.label, $resultText, $recommendation)) | Out-Null
    }
    $reportLines.Add("") | Out-Null
    $reportLines.Add("## 下一步") | Out-Null
    $reportLines.Add("") | Out-Null
    $reportLines.Add("1. 不要直接运行来源不明的「一键修复」。") | Out-Null
    $reportLines.Add("2. 先确认范围、备份和平台资金托管，再生成修复计划。") | Out-Null
    $reportLines.Add("3. 管理员授权、重启或系统功能变更必须由客户逐项确认。") | Out-Null

    $reportPath = Join-Path $OutputRoot "audit-report.md"
    [IO.File]::WriteAllText($reportPath, ($reportLines -join [Environment]::NewLine), $Utf8NoBom)
    Write-SafeLog "info" ("Audit completed with overall status {0}." -f $overallStatus)
    Write-ProgressEvent "complete" $null $overallStatus
    [IO.File]::WriteAllText($LogPath, ($LogLines -join [Environment]::NewLine), $Utf8NoBom)

    if ($overallStatus -eq "pass") {
        exit 0
    }
    exit 1
}
catch {
    try {
        if ($null -eq $OutputRoot) {
            $OutputRoot = [IO.Path]::GetFullPath($OutputPath)
            [IO.Directory]::CreateDirectory($OutputRoot) | Out-Null
        }
        if ($null -eq $LogPath) {
            $LogPath = Join-Path $OutputRoot "audit.log"
        }
        Write-SafeLog "error" ("Audit execution failed: {0}" -f $_.Exception.Message)
        Write-ProgressEvent "error" $null "error"
        [IO.File]::WriteAllText($LogPath, ($LogLines -join [Environment]::NewLine), $Utf8NoBom)
    }
    catch {
    }
    exit 2
}
