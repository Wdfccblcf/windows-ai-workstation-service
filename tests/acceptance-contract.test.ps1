[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path -Parent $PSScriptRoot
$AcceptanceScript = Join-Path $RepoRoot "tools\acceptance.ps1"
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$TempBase = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd("\")
$TempRoot = Join-Path $TempBase ("windows-ai-acceptance-contract-{0}" -f [Guid]::NewGuid().ToString("N"))
$ExpectedFiles = @("acceptance-report.md", "acceptance.json")
$ExpectedIds = @("git-init", "python-venv", "node-script", "ai-cli-status")
$ValidStatuses = @("pass", "warn", "fail", "blocked")
$OpenAiSentinel = "acceptance-contract-openai-sentinel-{0}" -f [Guid]::NewGuid().ToString("N")
$AnthropicSentinel = "acceptance-contract-anthropic-sentinel-{0}" -f [Guid]::NewGuid().ToString("N")
$OriginalOpenAiKey = [Environment]::GetEnvironmentVariable("OPENAI_API_KEY", "Process")
$OriginalAnthropicKey = [Environment]::GetEnvironmentVariable("ANTHROPIC_API_KEY", "Process")
$ContractPassed = $false

function Assert-Contract {
    param(
        [bool]$Condition,
        [string]$Message
    )

    if (-not $Condition) {
        throw "Acceptance contract failed: $Message"
    }
}

function Assert-Equal {
    param(
        [AllowNull()][object]$Expected,
        [AllowNull()][object]$Actual,
        [string]$Message
    )

    if ($Expected -ne $Actual) {
        throw "Acceptance contract failed: $Message"
    }
}

function Assert-StringProperty {
    param(
        [object]$Object,
        [string]$Name,
        [bool]$AllowEmpty = $false,
        [string]$Context
    )

    $Property = $Object.PSObject.Properties[$Name]
    Assert-Contract ($null -ne $Property) "$Context is missing $Name"
    Assert-Contract ($Property.Value -is [string]) "$Context property $Name must be a string"
    if (-not $AllowEmpty) {
        Assert-Contract (-not [string]::IsNullOrWhiteSpace([string]$Property.Value)) "$Context property $Name must not be empty"
    }
}

function Get-GitConfigCandidates {
    $Candidates = New-Object System.Collections.Generic.List[string]
    $GlobalOverride = [Environment]::GetEnvironmentVariable("GIT_CONFIG_GLOBAL", "Process")
    if (-not [string]::IsNullOrWhiteSpace($GlobalOverride)) {
        $Candidates.Add($GlobalOverride) | Out-Null
    }

    $UserProfile = [Environment]::GetFolderPath("UserProfile")
    if (-not [string]::IsNullOrWhiteSpace($UserProfile)) {
        $Candidates.Add((Join-Path $UserProfile ".gitconfig")) | Out-Null
        $Candidates.Add((Join-Path $UserProfile ".config\git\config")) | Out-Null
    }

    $XdgConfigHome = [Environment]::GetEnvironmentVariable("XDG_CONFIG_HOME", "Process")
    if (-not [string]::IsNullOrWhiteSpace($XdgConfigHome)) {
        $Candidates.Add((Join-Path $XdgConfigHome "git\config")) | Out-Null
    }

    return @($Candidates | ForEach-Object { [IO.Path]::GetFullPath($_) } | Sort-Object -Unique)
}

function Get-GitConfigSnapshot {
    param([string[]]$Paths)

    $Snapshot = New-Object System.Collections.Generic.List[object]
    foreach ($Path in $Paths) {
        $Exists = Test-Path -LiteralPath $Path -PathType Leaf
        $Hash = if ($Exists) { (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash } else { $null }
        $Snapshot.Add([pscustomobject]@{
            path = $Path
            exists = $Exists
            hash = $Hash
        }) | Out-Null
    }
    return @($Snapshot | ForEach-Object { $_ })
}

try {
    Assert-Contract (Test-Path -LiteralPath $AcceptanceScript -PathType Leaf) "tools/acceptance.ps1 is missing"

    $PowerShellPath = Join-Path $PSHOME "powershell.exe"
    Assert-Contract (Test-Path -LiteralPath $PowerShellPath -PathType Leaf) "Windows PowerShell 5.1 executable is unavailable"

    $GitConfigCandidates = @(Get-GitConfigCandidates)
    $GitConfigBefore = @(Get-GitConfigSnapshot $GitConfigCandidates)

    [Environment]::SetEnvironmentVariable("OPENAI_API_KEY", $OpenAiSentinel, "Process")
    [Environment]::SetEnvironmentVariable("ANTHROPIC_API_KEY", $AnthropicSentinel, "Process")

    # Suppress child output so runner-specific tool details never enter CI logs.
    $ChildOutput = & $PowerShellPath -NoProfile -ExecutionPolicy Bypass -File $AcceptanceScript -Package Standard -AiCli Codex -OutputPath $TempRoot 2>&1
    $ChildExitCode = $LASTEXITCODE
    $null = $ChildOutput

    $GitConfigAfter = @(Get-GitConfigSnapshot $GitConfigCandidates)
    Assert-Equal $GitConfigBefore.Count $GitConfigAfter.Count "Git configuration candidate count changed"
    for ($Index = 0; $Index -lt $GitConfigBefore.Count; $Index++) {
        Assert-Equal $GitConfigBefore[$Index].path $GitConfigAfter[$Index].path "Git configuration candidate path changed"
        Assert-Equal $GitConfigBefore[$Index].exists $GitConfigAfter[$Index].exists "Git configuration file existence changed"
        Assert-Equal $GitConfigBefore[$Index].hash $GitConfigAfter[$Index].hash "Git configuration file hash changed"
    }

    Assert-Contract ($ChildExitCode -in @(0, 1)) "acceptance exit code must be 0 or 1"
    Assert-Contract (Test-Path -LiteralPath $TempRoot -PathType Container) "acceptance output directory is missing"

    $ActualEntries = @(Get-ChildItem -LiteralPath $TempRoot -Force)
    $ActualNames = @($ActualEntries | Select-Object -ExpandProperty Name | Sort-Object)
    $SortedExpectedFiles = @($ExpectedFiles | Sort-Object)
    Assert-Equal $SortedExpectedFiles.Count $ActualNames.Count "output directory entry count changed"
    for ($Index = 0; $Index -lt $SortedExpectedFiles.Count; $Index++) {
        Assert-Equal $SortedExpectedFiles[$Index] $ActualNames[$Index] "output directory entries changed"
    }
    foreach ($Entry in $ActualEntries) {
        Assert-Contract (-not $Entry.PSIsContainer) "output directory contains an unexpected directory"
        Assert-Contract (-not ($Entry.Attributes -band [IO.FileAttributes]::ReparsePoint)) "output directory contains a reparse point"
    }

    $JsonPath = Join-Path $TempRoot "acceptance.json"
    $ReportPath = Join-Path $TempRoot "acceptance-report.md"
    foreach ($FileName in $ExpectedFiles) {
        Assert-Contract (Test-Path -LiteralPath (Join-Path $TempRoot $FileName) -PathType Leaf) "$FileName is missing"
    }

    $JsonText = [IO.File]::ReadAllText($JsonPath, $Utf8NoBom)
    $ReportText = [IO.File]::ReadAllText($ReportPath, $Utf8NoBom)
    $Document = $JsonText | ConvertFrom-Json

    Assert-Equal "1.0" $Document.schemaVersion "schemaVersion changed"
    Assert-Equal "Standard" $Document.package "package changed"
    Assert-Equal "Codex" $Document.aiCli "aiCli changed"
    Assert-Contract ($Document.overallStatus -in $ValidStatuses) "overallStatus is invalid"
    Assert-StringProperty $Document "note" $false "acceptance.json"

    $GeneratedAt = [DateTimeOffset]::MinValue
    Assert-Contract ([DateTimeOffset]::TryParse([string]$Document.generatedAt, [ref]$GeneratedAt)) "generatedAt is invalid"

    $Results = @($Document.results)
    Assert-Equal $ExpectedIds.Count $Results.Count "result count changed"
    for ($Index = 0; $Index -lt $ExpectedIds.Count; $Index++) {
        $Result = $Results[$Index]
        $Context = "result $($ExpectedIds[$Index])"
        Assert-StringProperty $Result "id" $false $Context
        Assert-StringProperty $Result "label" $false $Context
        Assert-StringProperty $Result "status" $false $Context
        Assert-StringProperty $Result "message" $false $Context
        Assert-Equal $ExpectedIds[$Index] $Result.id "result order or id changed at position $($Index + 1)"
        Assert-Contract ($Result.status -in $ValidStatuses) "$Context status is invalid"
    }

    $ExpectedOverall = "pass"
    if (@($Results | Where-Object { $_.status -eq "fail" }).Count -gt 0) {
        $ExpectedOverall = "fail"
    }
    elseif (@($Results | Where-Object { $_.status -eq "blocked" }).Count -gt 0) {
        $ExpectedOverall = "blocked"
    }
    elseif (@($Results | Where-Object { $_.status -eq "warn" }).Count -gt 0) {
        $ExpectedOverall = "warn"
    }
    Assert-Equal $ExpectedOverall $Document.overallStatus "overallStatus priority is inconsistent"
    $ExpectedExitCode = if ($ExpectedOverall -eq "pass") { 0 } else { 1 }
    Assert-Equal $ExpectedExitCode $ChildExitCode "exit code is inconsistent with overallStatus"

    Assert-Contract $ReportText.StartsWith("# Windows AI ") "acceptance-report.md title changed"
    Assert-Contract $ReportText.Contains("Standard") "acceptance-report.md package is missing"
    Assert-Contract $ReportText.Contains("**$($Document.overallStatus)**") "acceptance-report.md overall status is inconsistent"

    $ReportRows = @([regex]::Matches($ReportText, "(?m)^\| (pass|warn|fail|blocked) \| ([^|]+) \| ([^\r\n]*) \|\r?$"))
    Assert-Equal $Results.Count $ReportRows.Count "acceptance-report.md result row count changed"
    for ($Index = 0; $Index -lt $Results.Count; $Index++) {
        Assert-Equal $Results[$Index].status $ReportRows[$Index].Groups[1].Value "report result status is inconsistent"
        Assert-Equal $Results[$Index].label $ReportRows[$Index].Groups[2].Value.Trim() "report result label is inconsistent"
    }
    Assert-Equal 3 ([regex]::Matches($ReportText, "(?m)^- \[ \] ").Count) "manual confirmation checklist changed"

    $CombinedOutput = [string]::Join([Environment]::NewLine, @($JsonText, $ReportText))
    foreach ($Sentinel in @($OpenAiSentinel, $AnthropicSentinel)) {
        Assert-Contract ($CombinedOutput.IndexOf($Sentinel, [StringComparison]::Ordinal) -lt 0) "an API key sentinel leaked into an output file"
    }

    $UserProfile = [Environment]::GetFolderPath("UserProfile")
    if (-not [string]::IsNullOrWhiteSpace($UserProfile)) {
        Assert-Contract ($CombinedOutput.IndexOf($UserProfile, [StringComparison]::OrdinalIgnoreCase) -lt 0) "the full user profile leaked into an output file"
    }
    $UserName = [Environment]::UserName
    if (-not [string]::IsNullOrWhiteSpace($UserName) -and $UserName.Length -ge 4) {
        $UserPattern = "(?i)(?<![\p{L}\p{N}_])" + [regex]::Escape($UserName) + "(?![\p{L}\p{N}_])"
        Assert-Contract (-not [regex]::IsMatch($CombinedOutput, $UserPattern)) "the full user name leaked into an output file"
    }

    $ContractPassed = $true
}
finally {
    [Environment]::SetEnvironmentVariable("OPENAI_API_KEY", $OriginalOpenAiKey, "Process")
    [Environment]::SetEnvironmentVariable("ANTHROPIC_API_KEY", $OriginalAnthropicKey, "Process")

    $ResolvedTempRoot = [IO.Path]::GetFullPath($TempRoot).TrimEnd("\")
    $SafePrefix = $TempBase.TrimEnd("\") + "\"
    $LeafName = [IO.Path]::GetFileName($ResolvedTempRoot)
    $IsSafeTemp = $ResolvedTempRoot.StartsWith($SafePrefix, [StringComparison]::OrdinalIgnoreCase) -and
        $LeafName -match "^windows-ai-acceptance-contract-[0-9a-f]{32}$"
    Assert-Contract $IsSafeTemp "temporary directory cleanup safety check failed"
    if (Test-Path -LiteralPath $ResolvedTempRoot) {
        Remove-Item -LiteralPath $ResolvedTempRoot -Recurse -Force
    }
}

if ($ContractPassed) {
    Write-Host "Acceptance output and privacy contract passed."
}
