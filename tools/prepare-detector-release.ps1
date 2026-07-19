[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$TagName,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$OutputDirectory
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-True {
    param(
        [Parameter(Mandatory = $true)][bool]$Condition,
        [Parameter(Mandatory = $true)][string]$Message
    )

    if (-not $Condition) {
        throw ('DETECTOR RELEASE PREP: {0}' -f $Message)
    }
}

function Assert-Equal {
    param(
        [AllowNull()]$Actual,
        [AllowNull()]$Expected,
        [Parameter(Mandatory = $true)][string]$Message
    )

    if (-not ($Actual -ceq $Expected)) {
        throw ('DETECTOR RELEASE PREP: {0}' -f $Message)
    }
}

function Assert-ExactSet {
    param(
        [Parameter(Mandatory = $true)][string[]]$Actual,
        [Parameter(Mandatory = $true)][string[]]$Expected,
        [Parameter(Mandatory = $true)][string]$Message
    )

    $actualSorted = @($Actual | Sort-Object)
    $expectedSorted = @($Expected | Sort-Object)
    Assert-Equal -Actual $actualSorted.Count -Expected $expectedSorted.Count -Message ($Message + ' Count differs.')
    for ($index = 0; $index -lt $expectedSorted.Count; $index++) {
        Assert-Equal -Actual $actualSorted[$index] -Expected $expectedSorted[$index] -Message ($Message + ' Entry differs.')
    }
}

function Test-SafeFileName {
    param([Parameter(Mandatory = $true)][string]$Name)

    if ([string]::IsNullOrWhiteSpace($Name)) { return $false }
    if ([IO.Path]::IsPathRooted($Name)) { return $false }
    if ($Name.Contains('\') -or $Name.Contains('/')) { return $false }
    return $Name -cmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$'
}

function Read-ChecksumMap {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Label
    )

    $map = @{}
    $lines = [IO.File]::ReadAllLines($Path, [Text.Encoding]::UTF8)
    Assert-True -Condition ($lines.Count -gt 0) -Message ($Label + ' is empty.')
    foreach ($line in $lines) {
        Assert-True -Condition (-not [string]::IsNullOrWhiteSpace($line)) -Message ($Label + ' contains a blank line.')
        Assert-True -Condition ($line -cmatch '^([0-9a-f]{64}) {2}([A-Za-z0-9][A-Za-z0-9._-]*)$') -Message ($Label + ' contains an invalid entry.')
        $hash = $Matches[1]
        $name = $Matches[2]
        Assert-True -Condition (Test-SafeFileName -Name $name) -Message ($Label + ' contains an unsafe file name.')
        Assert-True -Condition (-not $map.ContainsKey($name)) -Message ($Label + ' contains a duplicate entry.')
        $map[$name] = $hash
    }
    return $map
}

function Get-Sha256 {
    param([Parameter(Mandatory = $true)][string]$Path)

    return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
}

Assert-True -Condition ($TagName -cmatch '^detector-v([0-9]+\.[0-9]+\.[0-9]+)$') -Message 'Tag must match detector-v<major>.<minor>.<patch> exactly.'
$version = $Matches[1]
$repositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$releaseRoot = Join-Path $repositoryRoot ('detector\releases\v{0}' -f $version)
$downloadRoot = Join-Path $repositoryRoot 'public\downloads'
$zipName = 'windows-ai-detector-release-v{0}.zip' -f $version
$zipChecksumName = $zipName + '.sha256.txt'
$mainManifestName = 'SHA256SUMS.txt'
$auditName = 'audit.ps1'
$releaseJsonName = 'release.json'
$provenanceName = 'PROVENANCE.md'
$notesName = 'RELEASE_NOTES.md'

$sourcePaths = [ordered]@{
    $zipName = Join-Path $downloadRoot $zipName
    $zipChecksumName = Join-Path $downloadRoot $zipChecksumName
    $mainManifestName = Join-Path $downloadRoot $mainManifestName
    $releaseJsonName = Join-Path $releaseRoot $releaseJsonName
    $provenanceName = Join-Path $releaseRoot $provenanceName
    $notesName = Join-Path $releaseRoot $notesName
}

foreach ($entry in $sourcePaths.GetEnumerator()) {
    Assert-True -Condition (Test-Path -LiteralPath $entry.Value -PathType Leaf) -Message ('Required source is missing: {0}' -f $entry.Key)
}

$releaseMetadata = Get-Content -Raw -Encoding UTF8 -LiteralPath $sourcePaths[$releaseJsonName] | ConvertFrom-Json
Assert-Equal -Actual ([string]$releaseMetadata.version) -Expected $version -Message 'release.json version does not match the tag.'
Assert-Equal -Actual ([string]$releaseMetadata.releaseType) -Expected 'detection-only' -Message 'release.json must remain detection-only.'
Assert-Equal -Actual ([bool]$releaseMetadata.repairIncluded) -Expected $false -Message 'release.json enables repair.'
Assert-Equal -Actual ([bool]$releaseMetadata.administratorPermissionRequested) -Expected $false -Message 'release.json requests administrator permission.'

$standaloneChecksums = Read-ChecksumMap -Path $sourcePaths[$zipChecksumName] -Label 'Standalone checksum'
Assert-ExactSet -Actual @($standaloneChecksums.Keys) -Expected @($zipName) -Message 'Standalone checksum file set differs.'
$mainChecksums = Read-ChecksumMap -Path $sourcePaths[$mainManifestName] -Label 'Main checksum manifest'
Assert-ExactSet -Actual @($mainChecksums.Keys) -Expected @($auditName, $zipName) -Message 'Main checksum file set differs.'

$auditPath = Join-Path $downloadRoot $auditName
Assert-True -Condition (Test-Path -LiteralPath $auditPath -PathType Leaf) -Message 'Required source is missing: audit.ps1'
$auditHash = Get-Sha256 -Path $auditPath
$zipHash = Get-Sha256 -Path $sourcePaths[$zipName]
Assert-Equal -Actual ([string]$mainChecksums[$auditName]) -Expected $auditHash -Message 'Main checksum manifest does not match audit.ps1.'
Assert-Equal -Actual ([string]$standaloneChecksums[$zipName]) -Expected $zipHash -Message 'Standalone checksum does not match the detector ZIP.'
Assert-Equal -Actual ([string]$mainChecksums[$zipName]) -Expected $zipHash -Message 'Main checksum manifest does not match the detector ZIP.'

$notes = Get-Content -Raw -Encoding UTF8 -LiteralPath $sourcePaths[$notesName]
Assert-True -Condition ($notes -cmatch ('(?m)^# Windows AI detector v{0}$' -f [regex]::Escape($version))) -Message 'Release notes title does not match the tag.'
Assert-True -Condition $notes.Contains($zipHash) -Message 'Release notes do not contain the detector ZIP hash.'

$outputFullPath = [IO.Path]::GetFullPath($OutputDirectory)
$repositoryPrefix = $repositoryRoot.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
$outputInsideRepository = (
    $outputFullPath.Equals($repositoryRoot, [StringComparison]::OrdinalIgnoreCase) -or
    $outputFullPath.StartsWith($repositoryPrefix, [StringComparison]::OrdinalIgnoreCase)
)
Assert-True -Condition (-not $outputInsideRepository) -Message 'Output directory must be outside the repository.'

$createdOutputDirectory = $false
try {
    if (Test-Path -LiteralPath $outputFullPath) {
        Assert-True -Condition (Test-Path -LiteralPath $outputFullPath -PathType Container) -Message 'Output path is not a directory.'
        Assert-Equal -Actual @(Get-ChildItem -LiteralPath $outputFullPath -Force).Count -Expected 0 -Message 'Output directory must be empty.'
    }
    else {
        [IO.Directory]::CreateDirectory($outputFullPath) | Out-Null
        $createdOutputDirectory = $true
    }

    foreach ($entry in $sourcePaths.GetEnumerator()) {
        $destination = Join-Path $outputFullPath $entry.Key
        [IO.File]::Copy($entry.Value, $destination, $false)
        Assert-Equal -Actual (Get-Sha256 -Path $destination) -Expected (Get-Sha256 -Path $entry.Value) -Message ('Staged bytes differ for {0}.' -f $entry.Key)
    }

    $expectedStagedNames = @($sourcePaths.Keys)
    $actualStagedNames = @(Get-ChildItem -LiteralPath $outputFullPath -File | ForEach-Object { $_.Name })
    Assert-ExactSet -Actual $actualStagedNames -Expected $expectedStagedNames -Message 'Staged file set differs.'

    $hashes = [ordered]@{}
    foreach ($name in $expectedStagedNames) {
        $hashes[$name] = Get-Sha256 -Path (Join-Path $outputFullPath $name)
    }

    $summary = [ordered]@{
        schemaVersion = '1.0'
        tagName = $TagName
        version = $version
        title = 'Windows AI detector v{0}' -f $version
        zipName = $zipName
        releaseAssets = @($zipName, $zipChecksumName, $mainManifestName, $releaseJsonName, $provenanceName)
        stagedFiles = $expectedStagedNames
        sha256 = $hashes
    }
    Write-Output ($summary | ConvertTo-Json -Depth 6 -Compress)
}
catch {
    if ($createdOutputDirectory -and (Test-Path -LiteralPath $outputFullPath -PathType Container)) {
        Remove-Item -LiteralPath $outputFullPath -Recurse -Force
    }
    throw
}
