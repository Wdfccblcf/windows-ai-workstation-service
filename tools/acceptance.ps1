[CmdletBinding()]
param(
    [Parameter()]
    [ValidateSet("Standard", "Full")]
    [string]$Package = "Standard",

    [Parameter()]
    [ValidateSet("Auto", "Codex", "Claude", "Gemini")]
    [string]$AiCli = "Auto",

    [Parameter()]
    [string]$OutputPath = ".\acceptance-output",

    [Parameter()]
    [switch]$AllowNetworkPull
)

$ErrorActionPreference = "Stop"
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$Results = New-Object System.Collections.Generic.List[object]
$OutputRoot = $null
$SessionRoot = $null

function Add-Result {
    param(
        [string]$Id,
        [string]$Label,
        [ValidateSet("pass", "warn", "fail", "blocked")]
        [string]$Status,
        [string]$Message
    )

    $Results.Add([pscustomobject][ordered]@{
        id = $Id
        label = $Label
        status = $Status
        message = $Message.Trim()
    }) | Out-Null
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

function Invoke-LocalCommand {
    param(
        [string]$Executable,
        [string[]]$ArgumentList,
        [string]$WorkingDirectory,
        [int]$TimeoutMilliseconds = 60000
    )

    try {
        $startInfo = New-Object System.Diagnostics.ProcessStartInfo
        $startInfo.FileName = $Executable
        $startInfo.Arguments = [string]::Join(" ", $ArgumentList)
        $startInfo.WorkingDirectory = $WorkingDirectory
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
            return [pscustomobject]@{ exitCode = $null; timedOut = $true; output = "" }
        }
        $process.WaitForExit()
        $output = $stdoutTask.Result
        $errorOutput = $stderrTask.Result
        return [pscustomobject]@{
            exitCode = $process.ExitCode
            timedOut = $false
            output = (($output, $errorOutput -join [Environment]::NewLine).Trim())
        }
    }
    catch {
        return [pscustomobject]@{ exitCode = 9001; timedOut = $false; output = $_.Exception.Message }
    }
}

try {
    $OutputRoot = [IO.Path]::GetFullPath($OutputPath)
    [IO.Directory]::CreateDirectory($OutputRoot) | Out-Null
    $SessionRoot = Join-Path $OutputRoot ("work-{0}" -f [Guid]::NewGuid().ToString("N"))
    [IO.Directory]::CreateDirectory($SessionRoot) | Out-Null

    $git = Get-Executable @("git.exe", "git")
    if ([string]::IsNullOrWhiteSpace($git)) {
        Add-Result "git-init" "Git 初始化" "fail" "未检测到 Git。"
    }
    else {
        $gitRoot = Join-Path $SessionRoot "git-check"
        [IO.Directory]::CreateDirectory($gitRoot) | Out-Null
        $gitResult = Invoke-LocalCommand $git @("init") $gitRoot 30000
        if ($gitResult.exitCode -eq 0 -and (Test-Path -LiteralPath (Join-Path $gitRoot ".git"))) {
            Add-Result "git-init" "Git 初始化" "pass" "临时仓库初始化成功；未修改全局 Git 配置。"
        }
        else {
            Add-Result "git-init" "Git 初始化" "fail" "Git 初始化失败。"
        }
    }

    $python = Get-Executable @("python.exe", "python", "py.exe", "py")
    if ([string]::IsNullOrWhiteSpace($python)) {
        Add-Result "python-venv" "Python 虚拟环境" "fail" "未检测到 Python。"
    }
    else {
        $pythonRoot = Join-Path $SessionRoot "python-check"
        [IO.Directory]::CreateDirectory($pythonRoot) | Out-Null
        [IO.File]::WriteAllText((Join-Path $pythonRoot "smoke.py"), "print('PYTHON_SMOKE_OK')", $Utf8NoBom)
        $venvResult = Invoke-LocalCommand $python @("-m", "venv", ".venv") $pythonRoot 90000
        $venvPython = Join-Path $pythonRoot ".venv\Scripts\python.exe"
        if ($venvResult.exitCode -eq 0 -and (Test-Path -LiteralPath $venvPython)) {
            $runResult = Invoke-LocalCommand $venvPython @("smoke.py") $pythonRoot 30000
            if ($runResult.exitCode -eq 0 -and $runResult.output -match "PYTHON_SMOKE_OK") {
                Add-Result "python-venv" "Python 虚拟环境" "pass" "虚拟环境创建并运行脚本成功。"
            }
            else {
                Add-Result "python-venv" "Python 虚拟环境" "fail" "虚拟环境已创建，但脚本未通过。"
            }
        }
        else {
            Add-Result "python-venv" "Python 虚拟环境" "fail" "无法创建 Python 虚拟环境。"
        }
    }

    $node = Get-Executable @("node.exe", "node")
    if ([string]::IsNullOrWhiteSpace($node)) {
        Add-Result "node-script" "Node.js 脚本" "fail" "未检测到 Node.js。"
    }
    else {
        $nodeRoot = Join-Path $SessionRoot "node-check"
        [IO.Directory]::CreateDirectory($nodeRoot) | Out-Null
        [IO.File]::WriteAllText((Join-Path $nodeRoot "smoke.js"), "console.log('NODE_SMOKE_OK');", $Utf8NoBom)
        $nodeResult = Invoke-LocalCommand $node @("smoke.js") $nodeRoot 30000
        if ($nodeResult.exitCode -eq 0 -and $nodeResult.output -match "NODE_SMOKE_OK") {
            Add-Result "node-script" "Node.js 脚本" "pass" "Node.js 脚本真实运行成功。"
        }
        else {
            Add-Result "node-script" "Node.js 脚本" "fail" "Node.js 脚本运行失败。"
        }
    }

    $cliCandidates = @()
    if ($AiCli -eq "Auto" -or $AiCli -eq "Codex") {
        $cliCandidates += ,@("Codex", @("codex.cmd", "codex.exe", "codex"))
    }
    if ($AiCli -eq "Auto" -or $AiCli -eq "Claude") {
        $cliCandidates += ,@("Claude", @("claude.exe", "claude.cmd", "claude"))
    }
    if ($AiCli -eq "Auto" -or $AiCli -eq "Gemini") {
        $cliCandidates += ,@("Gemini", @("gemini.exe", "gemini.cmd", "gemini"))
    }

    $selectedCli = $null
    foreach ($candidate in $cliCandidates) {
        $path = Get-Executable $candidate[1]
        if (-not [string]::IsNullOrWhiteSpace($path)) {
            $selectedCli = [pscustomobject]@{ name = $candidate[0]; path = $path }
            break
        }
    }
    if ($null -eq $selectedCli) {
        Add-Result "ai-cli-status" "AI CLI 状态" "fail" "未检测到所选 AI CLI。"
    }
    else {
        $cliResult = Invoke-LocalCommand $selectedCli.path @("--version") $SessionRoot 30000
        if ($cliResult.exitCode -eq 0) {
            Add-Result "ai-cli-status" "AI CLI 状态" "pass" ("{0} 命令可执行；登录或账号状态由客户本人在场确认。" -f $selectedCli.name)
        }
        else {
            Add-Result "ai-cli-status" "AI CLI 状态" "fail" ("{0} 命令存在但不可执行。" -f $selectedCli.name)
        }
    }

    if ($Package -eq "Full") {
        $docker = Get-Executable @("docker.exe", "docker")
        if ([string]::IsNullOrWhiteSpace($docker)) {
            Add-Result "docker-engine" "Docker 引擎" "fail" "未检测到 Docker CLI。"
            Add-Result "docker-compose" "Docker Compose" "fail" "未检测到 Docker CLI。"
            Add-Result "docker-container" "测试容器" "blocked" "Docker 不可用，未运行测试容器。"
        }
        else {
            $dockerInfo = Invoke-LocalCommand $docker @("info") $SessionRoot 30000
            if ($dockerInfo.exitCode -eq 0) {
                Add-Result "docker-engine" "Docker 引擎" "pass" "Docker 引擎可连接。"
            }
            else {
                Add-Result "docker-engine" "Docker 引擎" "fail" "Docker CLI 存在，但引擎不可连接。"
            }

            $composeResult = Invoke-LocalCommand $docker @("compose", "version") $SessionRoot 30000
            if ($composeResult.exitCode -eq 0) {
                Add-Result "docker-compose" "Docker Compose" "pass" "Docker Compose 命令可执行。"
            }
            else {
                Add-Result "docker-compose" "Docker Compose" "fail" "Docker Compose 命令不可用。"
            }

            if ($dockerInfo.exitCode -ne 0) {
                Add-Result "docker-container" "测试容器" "blocked" "Docker 引擎不可用，未运行测试容器。"
            }
            else {
                $imageInspect = Invoke-LocalCommand $docker @("image", "inspect", "hello-world") $SessionRoot 30000
                if ($imageInspect.exitCode -ne 0 -and -not $AllowNetworkPull) {
                    Add-Result "docker-container" "测试容器" "blocked" "本地没有 hello-world 镜像；未获准联网拉取。使用 -AllowNetworkPull 后重试。"
                }
                else {
                    $containerResult = Invoke-LocalCommand $docker @("run", "--rm", "hello-world") $SessionRoot 120000
                    if ($containerResult.exitCode -eq 0 -and $containerResult.output -match "Hello from Docker") {
                        Add-Result "docker-container" "测试容器" "pass" "hello-world 容器真实运行成功。"
                    }
                    else {
                        Add-Result "docker-container" "测试容器" "fail" "hello-world 容器未通过。"
                    }
                }
            }
        }
    }

    $statuses = @($Results | Select-Object -ExpandProperty status)
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

    $document = [pscustomobject][ordered]@{
        schemaVersion = "1.0"
        generatedAt = (Get-Date).ToString("o")
        package = $Package
        aiCli = if ($null -eq $selectedCli) { $AiCli } else { $selectedCli.name }
        overallStatus = $overallStatus
        results = @($Results | ForEach-Object { $_ })
        note = "验收脚本只在指定输出目录创建临时测试文件，不修改全局 Git 配置，不读取密钥。"
    }
    [IO.File]::WriteAllText((Join-Path $OutputRoot "acceptance.json"), ($document | ConvertTo-Json -Depth 6), $Utf8NoBom)

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("# Windows AI 环境验收单") | Out-Null
    $lines.Add("") | Out-Null
    $lines.Add(("- 套餐：{0}" -f $Package)) | Out-Null
    $lines.Add(("- 总体状态：**{0}**" -f $overallStatus)) | Out-Null
    $lines.Add(("- 生成时间：{0}" -f $document.generatedAt)) | Out-Null
    $lines.Add("") | Out-Null
    $lines.Add("| 状态 | 验收项 | 结果 |") | Out-Null
    $lines.Add("|---|---|---|") | Out-Null
    foreach ($result in $Results) {
        $safeMessage = ($result.message -replace "\|", "\/") -replace "\r?\n", " "
        $lines.Add(("| {0} | {1} | {2} |" -f $result.status, $result.label, $safeMessage)) | Out-Null
    }
    $lines.Add("") | Out-Null
    $lines.Add("## 人工确认") | Out-Null
    $lines.Add("") | Out-Null
    $lines.Add("- [ ] 客户已看到全部通过项、未通过项和外部阻塞。") | Out-Null
    $lines.Add("- [ ] 客户确认未提供密码、验证码或密钥给服务方。") | Out-Null
    $lines.Add("- [ ] 客户确认售后仅覆盖 7 天内的同一问题。") | Out-Null
    [IO.File]::WriteAllText((Join-Path $OutputRoot "acceptance-report.md"), ($lines -join [Environment]::NewLine), $Utf8NoBom)

    Remove-Item -LiteralPath $SessionRoot -Recurse -Force -ErrorAction SilentlyContinue
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
        [IO.File]::WriteAllText((Join-Path $OutputRoot "acceptance-error.log"), $_.Exception.Message, $Utf8NoBom)
        if ($null -ne $SessionRoot) {
            Remove-Item -LiteralPath $SessionRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    catch {
    }
    exit 2
}
