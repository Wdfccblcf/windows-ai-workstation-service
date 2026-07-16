[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"

$Version = "1.0.2"
$DetectorName = "windows-ai-detector-release-v$Version.zip"
$ExpectedZipHash = "7c8c3c5f0fa28daa90729808dd91bc6e4d3065ba79867f3968b6a303e883de80"
$RepositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
$ReleaseSourceRoot = Join-Path $RepositoryRoot "detector\releases\v$Version"
$ZipPath = Join-Path $RepositoryRoot ("public\downloads\{0}" -f $DetectorName)
$MainManifestPath = Join-Path $RepositoryRoot "public\downloads\SHA256SUMS.txt"
$ZipManifestPath = Join-Path $RepositoryRoot ("public\downloads\{0}.sha256.txt" -f $DetectorName)
$TempBase = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\', '/')
$TempRoot = Join-Path $TempBase ("windows-ai-detector-contract-{0}" -f [Guid]::NewGuid().ToString("N"))
$Archive = $null

function Assert-True {
    param(
        [bool]$Condition,
        [string]$Message
    )

    if (-not $Condition) {
        throw "DETECTOR CONTRACT: $Message"
    }
}

function Assert-Equal {
    param(
        [AllowNull()][object]$Expected,
        [AllowNull()][object]$Actual,
        [string]$Message
    )

    if ($Expected -cne $Actual) {
        throw "DETECTOR CONTRACT: $Message Expected '$Expected', got '$Actual'."
    }
}

function Assert-ExactSet {
    param(
        [string[]]$Expected,
        [string[]]$Actual,
        [string]$Message
    )

    $expectedSorted = @($Expected | Sort-Object)
    $actualSorted = @($Actual | Sort-Object)
    Assert-Equal $expectedSorted.Count $actualSorted.Count "$Message Count differs."
    for ($index = 0; $index -lt $expectedSorted.Count; $index++) {
        Assert-Equal $expectedSorted[$index] $actualSorted[$index] "$Message Entry differs at index $index."
    }
}

function Read-ZipEntryBytes {
    param([IO.Compression.ZipArchiveEntry]$Entry)

    $stream = $Entry.Open()
    try {
        $memory = New-Object IO.MemoryStream
        try {
            $stream.CopyTo($memory)
            return ,$memory.ToArray()
        }
        finally {
            $memory.Dispose()
        }
    }
    finally {
        $stream.Dispose()
    }
}

function ConvertFrom-Utf8Bytes {
    param([byte[]]$Bytes)

    $text = [Text.Encoding]::UTF8.GetString($Bytes)
    if ($text.Length -gt 0 -and $text[0] -eq [char]0xFEFF) {
        return $text.Substring(1)
    }
    return $text
}

function Get-Sha256Bytes {
    param([byte[]]$Bytes)

    $sha256 = [Security.Cryptography.SHA256]::Create()
    try {
        return ([BitConverter]::ToString($sha256.ComputeHash($Bytes))).Replace("-", "").ToLowerInvariant()
    }
    finally {
        $sha256.Dispose()
    }
}

function Assert-BytesEqual {
    param(
        [byte[]]$Expected,
        [byte[]]$Actual,
        [string]$Message
    )

    Assert-Equal $Expected.Length $Actual.Length "$Message Length differs."
    for ($index = 0; $index -lt $Expected.Length; $index++) {
        if ($Expected[$index] -ne $Actual[$index]) {
            throw "DETECTOR CONTRACT: $Message Byte differs at offset $index."
        }
    }
}

function Test-SafeEntryName {
    param([string]$Name)

    if ([string]::IsNullOrWhiteSpace($Name)) { return $false }
    if ([IO.Path]::IsPathRooted($Name)) { return $false }
    if ($Name.Contains("\")) { return $false }
    if ($Name.Contains("/")) { return $false }
    if ($Name -match '(^|[\/])\.\.([\/]|$)') { return $false }
    return $Name -cmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$'
}

try {
    foreach ($requiredPath in @($ReleaseSourceRoot, $ZipPath, $MainManifestPath, $ZipManifestPath)) {
        Assert-True (Test-Path -LiteralPath $requiredPath) "Required path is missing: $requiredPath"
    }

    $actualZipHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $ZipPath).Hash.ToLowerInvariant()
    Assert-Equal $ExpectedZipHash $actualZipHash "Published ZIP hash changed."

    $expectedZipLine = "{0}  {1}" -f $ExpectedZipHash, $DetectorName
    $standaloneZipLine = (Get-Content -Raw -Encoding UTF8 -LiteralPath $ZipManifestPath).Trim()
    Assert-Equal $expectedZipLine $standaloneZipLine "Standalone ZIP checksum changed."

    $mainManifest = Get-Content -Raw -Encoding UTF8 -LiteralPath $MainManifestPath
    Assert-True ($mainManifest -cmatch ("(?m)^{0}  {1}$" -f [regex]::Escape($ExpectedZipHash), [regex]::Escape($DetectorName))) "Main checksum manifest does not contain the published ZIP hash."

    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $Archive = [IO.Compression.ZipFile]::OpenRead($ZipPath)

    $expectedEntryNames = @(
        "audit.ps1",
        "README.md",
        "release.json",
        "scan-app.ps1",
        "SHA256SUMS.txt",
        "Start-Windows-AI-Scan.cmd",
        "verify-package.ps1"
    )
    $entries = @($Archive.Entries)
    $entryMap = @{}
    foreach ($entry in $entries) {
        $name = [string]$entry.FullName
        Assert-True (Test-SafeEntryName $name) "Unsafe or nested ZIP entry: $name"
        Assert-True (-not $entryMap.ContainsKey($name)) "Duplicate ZIP entry: $name"
        Assert-True (-not [string]::IsNullOrWhiteSpace([string]$entry.Name)) "Directory entries are not allowed: $name"
        $entryMap[$name] = $entry
    }
    Assert-ExactSet $expectedEntryNames @($entryMap.Keys) "ZIP entry set differs."
    Assert-True (-not $entryMap.ContainsKey("Start-Repair-App.cmd")) "Repair launcher must not be present."

    [byte[]]$archiveAudit = Read-ZipEntryBytes $entryMap["audit.ps1"]
    [byte[]]$rootAudit = [IO.File]::ReadAllBytes((Join-Path $RepositoryRoot "audit.ps1"))
    [byte[]]$publicAudit = [IO.File]::ReadAllBytes((Join-Path $RepositoryRoot "public\downloads\audit.ps1"))
    Assert-BytesEqual $rootAudit $publicAudit "Root and public audit scripts differ."
    Assert-BytesEqual $rootAudit $archiveAudit "Archive and canonical audit scripts differ."

    $sourceMappings = [ordered]@{
        "scan-app.ps1" = "scan-app.ps1"
        "verify-package.ps1" = "verify-package.ps1"
        "Start-Windows-AI-Scan.cmd" = "Start-Windows-AI-Scan.cmd"
        "README.md" = "README.md"
    }
    foreach ($mapping in $sourceMappings.GetEnumerator()) {
        [byte[]]$expectedBytes = [IO.File]::ReadAllBytes((Join-Path $ReleaseSourceRoot $mapping.Value))
        [byte[]]$actualBytes = Read-ZipEntryBytes $entryMap[$mapping.Key]
        Assert-BytesEqual $expectedBytes $actualBytes ("Archive source differs for {0}." -f $mapping.Key)
    }

    [byte[]]$archiveReleaseBytes = Read-ZipEntryBytes $entryMap["release.json"]
    $archiveRelease = (ConvertFrom-Utf8Bytes $archiveReleaseBytes) | ConvertFrom-Json
    $sourceRelease = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $ReleaseSourceRoot "release.json") | ConvertFrom-Json
    $archiveReleaseCanonical = $archiveRelease | ConvertTo-Json -Depth 8 -Compress
    $sourceReleaseCanonical = $sourceRelease | ConvertTo-Json -Depth 8 -Compress
    Assert-Equal $sourceReleaseCanonical $archiveReleaseCanonical "Release metadata snapshot differs."
    Assert-Equal "1.0" ([string]$archiveRelease.schemaVersion) "Unexpected release schema."
    Assert-Equal "detection-only" ([string]$archiveRelease.releaseType) "Release must remain detection-only."
    Assert-Equal $Version ([string]$archiveRelease.version) "Release version does not match the ZIP name."
    Assert-True (-not [bool]$archiveRelease.repairIncluded) "Release metadata enables repair."
    Assert-True (-not [bool]$archiveRelease.administratorPermissionRequested) "Release metadata requests administrator permission."
    Assert-ExactSet @("Windows 11") @($archiveRelease.supportedOS | ForEach-Object { [string]$_ }) "Supported OS set differs."
    Assert-True (([string]$archiveRelease.testSummarySha256) -cmatch '^[0-9a-f]{64}$') "Historical test summary hash is malformed."

    [byte[]]$manifestBytes = Read-ZipEntryBytes $entryMap["SHA256SUMS.txt"]
    $manifestText = ConvertFrom-Utf8Bytes $manifestBytes
    $manifestLines = [regex]::Split($manifestText, "\r?\n")
    $manifestMap = @{}
    foreach ($line in $manifestLines) {
        Assert-True (-not [string]::IsNullOrWhiteSpace($line)) "Internal checksum manifest contains a blank line."
        Assert-True ($line -cmatch '^([0-9a-f]{64}) {2}([A-Za-z0-9][A-Za-z0-9._-]*)$') "Invalid internal checksum line: $line"
        $expectedHash = $Matches[1]
        $name = $Matches[2]
        Assert-True (Test-SafeEntryName $name) "Unsafe internal checksum path: $name"
        Assert-True (-not $manifestMap.ContainsKey($name)) "Duplicate internal checksum entry: $name"
        Assert-True ($entryMap.ContainsKey($name)) "Internal checksum references a missing ZIP entry: $name"
        [byte[]]$entryBytes = Read-ZipEntryBytes $entryMap[$name]
        Assert-Equal $expectedHash (Get-Sha256Bytes $entryBytes) "Internal checksum mismatch for $name."
        $manifestMap[$name] = $expectedHash
    }
    $expectedManifestNames = @($expectedEntryNames | Where-Object { $_ -cne "SHA256SUMS.txt" })
    Assert-ExactSet $expectedManifestNames @($manifestMap.Keys) "Internal checksum entry set differs."

    $Archive.Dispose()
    $Archive = $null

    [IO.Compression.ZipFile]::ExtractToDirectory($ZipPath, $TempRoot)
    $powerShellExe = Join-Path $PSHOME "powershell.exe"
    Assert-True (Test-Path -LiteralPath $powerShellExe -PathType Leaf) "Windows PowerShell executable is unavailable."
    $selfTestScript = Join-Path $TempRoot "scan-app.ps1"
    $selfTestOutput = (& $powerShellExe -NoProfile -ExecutionPolicy Bypass -File $selfTestScript -SelfTest -DetectionOnly 2>&1 | Out-String).Trim()
    $selfTestExitCode = $LASTEXITCODE
    Assert-Equal 0 $selfTestExitCode "Detector self-test returned a non-zero exit code."
    Assert-True ($selfTestOutput -match 'SELFTEST PASS') "Detector self-test did not report success."

    Write-Output ("DETECTOR_RELEASE_CONTRACT PASS: v{0}, {1} approved entries, hash {2}." -f $Version, $expectedEntryNames.Count, $ExpectedZipHash)
}
finally {
    if ($null -ne $Archive) {
        $Archive.Dispose()
    }

    if (Test-Path -LiteralPath $TempRoot) {
        $resolvedTemp = [IO.Path]::GetFullPath($TempRoot)
        $expectedPrefix = $TempBase + [IO.Path]::DirectorySeparatorChar
        $leaf = Split-Path $resolvedTemp -Leaf
        if ($resolvedTemp.StartsWith($expectedPrefix, [StringComparison]::OrdinalIgnoreCase) -and $leaf -like "windows-ai-detector-contract-*") {
            Remove-Item -LiteralPath $resolvedTemp -Recurse -Force
        }
        else {
            throw "DETECTOR CONTRACT: Refusing to clean an unexpected temporary path: $resolvedTemp"
        }
    }
}
