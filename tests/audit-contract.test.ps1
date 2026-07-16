[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path -Parent $PSScriptRoot
$AuditScript = Join-Path $RepoRoot "audit.ps1"
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$TempBase = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd("\")
$TempRoot = Join-Path $TempBase ("windows-ai-audit-contract-{0}" -f [Guid]::NewGuid().ToString("N"))
$ExpectedFiles = @("audit-progress.jsonl", "audit-report.md", "audit.json", "audit.log")
$ExpectedIds = @(
    "system-os",
    "hardware-summary",
    "disk-system",
    "path-health",
    "tool-git",
    "tool-python",
    "tool-uv",
    "tool-node",
    "tool-npm",
    "path-conflict-git",
    "path-conflict-python",
    "path-conflict-node",
    "tool-editor",
    "platform-wsl",
    "platform-docker",
    "platform-compose",
    "ai-cli",
    "mcp-status",
    "api-key-presence"
)
$ValidStatuses = @("pass", "warn", "fail", "blocked")
$OpenAiSentinel = "audit-contract-openai-sentinel-{0}" -f [Guid]::NewGuid().ToString("N")
$AnthropicSentinel = "audit-contract-anthropic-sentinel-{0}" -f [Guid]::NewGuid().ToString("N")
$OriginalOpenAiKey = [Environment]::GetEnvironmentVariable("OPENAI_API_KEY", "Process")
$OriginalAnthropicKey = [Environment]::GetEnvironmentVariable("ANTHROPIC_API_KEY", "Process")
$TempCreated = $false
$ContractPassed = $false

function Assert-Contract {
    param(
        [bool]$Condition,
        [string]$Message
    )

    if (-not $Condition) {
        throw "Audit contract failed: $Message"
    }
}

function Assert-Equal {
    param(
        [AllowNull()][object]$Expected,
        [AllowNull()][object]$Actual,
        [string]$Message
    )

    if ($Expected -ne $Actual) {
        throw "Audit contract failed: $Message"
    }
}

function Assert-StringProperty {
    param(
        [object]$Object,
        [string]$Name,
        [bool]$AllowEmpty = $false,
        [string]$Context
    )

    $property = $Object.PSObject.Properties[$Name]
    Assert-Contract ($null -ne $property) "$Context is missing $Name"
    Assert-Contract ($property.Value -is [string]) "$Context property $Name must be a string"
    if (-not $AllowEmpty) {
        Assert-Contract (-not [string]::IsNullOrWhiteSpace([string]$property.Value)) "$Context property $Name must not be empty"
    }
}

function Assert-ParseableTimestamp {
    param(
        [string]$Value,
        [string]$Context
    )

    $parsed = [DateTimeOffset]::MinValue
    $isValid = [DateTimeOffset]::TryParse($Value, [ref]$parsed)
    Assert-Contract $isValid "$Context timestamp is invalid"
}

function ConvertFrom-CodePoints {
    param([int[]]$CodePoints)

    return -join @($CodePoints | ForEach-Object { [char]$_ })
}

try {
    Assert-Contract (Test-Path -LiteralPath $AuditScript -PathType Leaf) "audit.ps1 is missing"

    [IO.Directory]::CreateDirectory($TempRoot) | Out-Null
    $TempCreated = $true
    [Environment]::SetEnvironmentVariable("OPENAI_API_KEY", $OpenAiSentinel, "Process")
    [Environment]::SetEnvironmentVariable("ANTHROPIC_API_KEY", $AnthropicSentinel, "Process")

    $PowerShellPath = Join-Path $PSHOME "powershell.exe"
    Assert-Contract (Test-Path -LiteralPath $PowerShellPath -PathType Leaf) "Windows PowerShell 5.1 executable is unavailable"

    # Deliberately capture and suppress child output so environment details cannot enter CI logs.
    $ChildOutput = & $PowerShellPath -NoProfile -ExecutionPolicy Bypass -File $AuditScript -OutputPath $TempRoot -PrivacyMode Strict 2>&1
    $ChildExitCode = $LASTEXITCODE
    $null = $ChildOutput

    Assert-Contract ($ChildExitCode -in @(0, 1)) "audit exit code must be 0 or 1"

    $ActualEntries = @(Get-ChildItem -LiteralPath $TempRoot -Force | Select-Object -ExpandProperty Name | Sort-Object)
    $SortedExpectedFiles = @($ExpectedFiles | Sort-Object)
    Assert-Equal $SortedExpectedFiles.Count $ActualEntries.Count "output directory entry count changed"
    for ($index = 0; $index -lt $SortedExpectedFiles.Count; $index++) {
        Assert-Equal $SortedExpectedFiles[$index] $ActualEntries[$index] "output directory entries changed"
    }
    foreach ($fileName in $ExpectedFiles) {
        Assert-Contract (Test-Path -LiteralPath (Join-Path $TempRoot $fileName) -PathType Leaf) "$fileName is missing"
    }

    $JsonPath = Join-Path $TempRoot "audit.json"
    $ReportPath = Join-Path $TempRoot "audit-report.md"
    $LogPath = Join-Path $TempRoot "audit.log"
    $ProgressPath = Join-Path $TempRoot "audit-progress.jsonl"
    $JsonText = [IO.File]::ReadAllText($JsonPath, $Utf8NoBom)
    $ReportText = [IO.File]::ReadAllText($ReportPath, $Utf8NoBom)
    $LogText = [IO.File]::ReadAllText($LogPath, $Utf8NoBom)
    $ProgressText = [IO.File]::ReadAllText($ProgressPath, $Utf8NoBom)
    $Document = $JsonText | ConvertFrom-Json

    Assert-Equal "1.0" $Document.schemaVersion "schemaVersion changed"
    Assert-Equal "1.1.0" $Document.scriptVersion "scriptVersion changed"
    Assert-Equal "Strict" $Document.privacyMode "privacyMode changed"
    Assert-Contract ($Document.overallStatus -in $ValidStatuses) "overallStatus is invalid"
    Assert-ParseableTimestamp ([string]$Document.generatedAt) "audit.json"

    $Checks = @($Document.checks)
    Assert-Equal $ExpectedIds.Count $Checks.Count "check count changed"
    for ($index = 0; $index -lt $ExpectedIds.Count; $index++) {
        $check = $Checks[$index]
        $context = "check $($ExpectedIds[$index])"
        Assert-StringProperty $check "id" $false $context
        Assert-StringProperty $check "category" $false $context
        Assert-StringProperty $check "label" $false $context
        Assert-StringProperty $check "status" $false $context
        Assert-StringProperty $check "detectedVersion" $true $context
        Assert-StringProperty $check "message" $false $context
        Assert-StringProperty $check "recommendation" $false $context
        Assert-Equal $ExpectedIds[$index] $check.id "check order or id changed at position $($index + 1)"
        Assert-Contract ($check.status -in $ValidStatuses) "$context status is invalid"
    }

    $SummaryTotal = 0
    foreach ($status in $ValidStatuses) {
        $summaryProperty = $Document.summary.PSObject.Properties[$status]
        Assert-Contract ($null -ne $summaryProperty) "summary is missing $status"
        $actualCount = @($Checks | Where-Object { $_.status -eq $status }).Count
        Assert-Equal $actualCount ([int]$summaryProperty.Value) "summary count for $status is inconsistent"
        $SummaryTotal += [int]$summaryProperty.Value
    }
    Assert-Equal $ExpectedIds.Count $SummaryTotal "summary total is inconsistent"

    $ExpectedOverall = "pass"
    if (@($Checks | Where-Object { $_.status -eq "fail" }).Count -gt 0) {
        $ExpectedOverall = "fail"
    }
    elseif (@($Checks | Where-Object { $_.status -eq "blocked" }).Count -gt 0) {
        $ExpectedOverall = "blocked"
    }
    elseif (@($Checks | Where-Object { $_.status -eq "warn" }).Count -gt 0) {
        $ExpectedOverall = "warn"
    }
    Assert-Equal $ExpectedOverall $Document.overallStatus "overallStatus priority is inconsistent"
    $ExpectedExitCode = if ($ExpectedOverall -eq "pass") { 0 } else { 1 }
    Assert-Equal $ExpectedExitCode $ChildExitCode "exit code is inconsistent with overallStatus"

    $ApiKeyCheck = $Checks[$Checks.Count - 1]
    $PresentText = ConvertFrom-CodePoints @(0x5B58, 0x5728)
    $FullWidthColon = [string][char]0xFF1A
    foreach ($keyName in @("OPENAI_API_KEY", "ANTHROPIC_API_KEY")) {
        Assert-Contract ($ApiKeyCheck.message.IndexOf($keyName, [StringComparison]::Ordinal) -ge 0) "api-key-presence omitted a test variable name"
        $presencePattern = ([regex]::Escape($keyName)) + "\s*[" + [regex]::Escape($FullWidthColon) + ":]\s*" + [regex]::Escape($PresentText)
        Assert-Contract ($ApiKeyCheck.message -match $presencePattern) "api-key-presence did not report a test variable as present"
    }

    $ProgressLines = @([IO.File]::ReadAllLines($ProgressPath, $Utf8NoBom))
    Assert-Equal 21 $ProgressLines.Count "progress event count changed"
    $ProgressEvents = New-Object System.Collections.Generic.List[object]
    foreach ($line in $ProgressLines) {
        Assert-Contract (-not [string]::IsNullOrWhiteSpace($line)) "progress contains an empty event"
        try {
            $ProgressEvents.Add(($line | ConvertFrom-Json)) | Out-Null
        }
        catch {
            throw "Audit contract failed: audit-progress.jsonl contains invalid JSON"
        }
    }

    $StartEvent = $ProgressEvents[0]
    Assert-Equal "1.0" $StartEvent.schemaVersion "start schemaVersion changed"
    Assert-Equal "start" $StartEvent.event "first progress event must be start"
    Assert-Equal 0 ([int]$StartEvent.sequence) "start sequence changed"
    Assert-Equal 19 ([int]$StartEvent.total) "start total changed"
    Assert-Equal 0 ([int]$StartEvent.percent) "start percent changed"
    Assert-ParseableTimestamp ([string]$StartEvent.timestamp) "start event"

    $PreviousPercent = 0
    for ($index = 0; $index -lt $Checks.Count; $index++) {
        $event = $ProgressEvents[$index + 1]
        $check = $Checks[$index]
        $sequence = $index + 1
        $expectedPercent = [Math]::Min(100, [Math]::Round(($sequence / [double]$ExpectedIds.Count) * 100))
        Assert-Equal "1.0" $event.schemaVersion "check event schemaVersion changed"
        Assert-Equal "check" $event.event "progress event $sequence must be check"
        Assert-Equal $sequence ([int]$event.sequence) "check event sequence changed"
        Assert-Equal 19 ([int]$event.total) "check event total changed"
        Assert-Equal ([int]$expectedPercent) ([int]$event.percent) "check event percent changed"
        Assert-Contract ([int]$event.percent -ge $PreviousPercent) "check event percent is not monotonic"
        Assert-Equal $check.id $event.id "check event id is inconsistent"
        Assert-Equal $check.category $event.category "check event category is inconsistent"
        Assert-Equal $check.label $event.label "check event label is inconsistent"
        Assert-Equal $check.status $event.status "check event status is inconsistent"
        Assert-ParseableTimestamp ([string]$event.timestamp) "check event $sequence"
        $PreviousPercent = [int]$event.percent
    }

    $CompleteEvent = $ProgressEvents[$ProgressEvents.Count - 1]
    Assert-Equal "1.0" $CompleteEvent.schemaVersion "complete schemaVersion changed"
    Assert-Equal "complete" $CompleteEvent.event "last progress event must be complete"
    Assert-Equal 19 ([int]$CompleteEvent.sequence) "complete sequence changed"
    Assert-Equal 19 ([int]$CompleteEvent.total) "complete total changed"
    Assert-Equal 100 ([int]$CompleteEvent.percent) "complete percent changed"
    Assert-Equal $Document.overallStatus $CompleteEvent.status "complete status is inconsistent"
    Assert-ParseableTimestamp ([string]$CompleteEvent.timestamp) "complete event"

    $ReportTitle = "# Windows AI " + (ConvertFrom-CodePoints @(0x73AF, 0x5883, 0x53EA, 0x8BFB, 0x4F53, 0x68C0, 0x62A5, 0x544A))
    $OverallLabel = (ConvertFrom-CodePoints @(0x603B, 0x4F53, 0x72B6, 0x6001, 0xFF1A))
    $SummaryLabel = (ConvertFrom-CodePoints @(0x6C47, 0x603B, 0xFF1A))
    $PrivacyText = "Strict " + (ConvertFrom-CodePoints @(0x6A21, 0x5F0F, 0x4E0D, 0x4F1A, 0x8BB0, 0x5F55, 0x5BC6, 0x94A5, 0x503C))
    Assert-Contract ($ReportText.Contains($ReportTitle)) "audit-report.md title changed"
    Assert-Contract ($ReportText.Contains("$OverallLabel**$($Document.overallStatus)**")) "audit-report.md overall status is inconsistent"
    Assert-Contract ($ReportText.Contains("${SummaryLabel}pass $($Document.summary.pass) / warn $($Document.summary.warn) / fail $($Document.summary.fail) / blocked $($Document.summary.blocked)")) "audit-report.md summary is inconsistent"
    Assert-Contract ($ReportText.Contains($PrivacyText)) "audit-report.md privacy notice changed"
    Assert-Equal 19 ([regex]::Matches($ReportText, "(?m)^\| (pass|warn|fail|blocked) \|").Count) "audit-report.md result row count changed"

    Assert-Contract ($LogText.Contains("Windows AI workstation audit")) "audit.log start record is missing"
    Assert-Contract ($LogText.Contains("started in Strict mode")) "audit.log start mode is missing"
    Assert-Contract ($LogText.Contains("Audit completed with overall status $($Document.overallStatus).")) "audit.log completion record is inconsistent"
    foreach ($id in $ExpectedIds) {
        $pattern = "(?m)\[INFO\] " + [regex]::Escape($id) + ": (pass|warn|fail|blocked) -"
        Assert-Equal 1 ([regex]::Matches($LogText, $pattern).Count) "audit.log check record changed"
    }

    $CombinedOutput = [string]::Join([Environment]::NewLine, @($JsonText, $ReportText, $LogText, $ProgressText))
    foreach ($sentinel in @($OpenAiSentinel, $AnthropicSentinel)) {
        Assert-Contract ($CombinedOutput.IndexOf($sentinel, [StringComparison]::Ordinal) -lt 0) "an API key sentinel leaked into an output file"
    }

    $UserProfile = [Environment]::GetFolderPath("UserProfile")
    if (-not [string]::IsNullOrWhiteSpace($UserProfile)) {
        Assert-Contract ($CombinedOutput.IndexOf($UserProfile, [StringComparison]::OrdinalIgnoreCase) -lt 0) "the full user profile leaked into an output file"
    }
    $UserName = [Environment]::UserName
    if (-not [string]::IsNullOrWhiteSpace($UserName) -and $UserName.Length -ge 4) {
        $userPattern = "(?i)(?<![\p{L}\p{N}_])" + [regex]::Escape($UserName) + "(?![\p{L}\p{N}_])"
        Assert-Contract (-not [regex]::IsMatch($CombinedOutput, $userPattern)) "the full user name leaked into an output file"
    }

    $ContractPassed = $true
}
finally {
    [Environment]::SetEnvironmentVariable("OPENAI_API_KEY", $OriginalOpenAiKey, "Process")
    [Environment]::SetEnvironmentVariable("ANTHROPIC_API_KEY", $OriginalAnthropicKey, "Process")

    if ($TempCreated) {
        $ResolvedTempRoot = [IO.Path]::GetFullPath($TempRoot).TrimEnd("\")
        $SafePrefix = $TempBase.TrimEnd("\") + "\"
        $LeafName = [IO.Path]::GetFileName($ResolvedTempRoot)
        $IsSafeTemp = $ResolvedTempRoot.StartsWith($SafePrefix, [StringComparison]::OrdinalIgnoreCase) -and
            $LeafName -match "^windows-ai-audit-contract-[0-9a-f]{32}$"
        Assert-Contract $IsSafeTemp "temporary directory cleanup safety check failed"
        if (Test-Path -LiteralPath $ResolvedTempRoot) {
            Remove-Item -LiteralPath $ResolvedTempRoot -Recurse -Force
        }
    }
}

if ($ContractPassed) {
    Write-Host "Audit privacy and output contract passed."
}
