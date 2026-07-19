[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$prepareScript = Join-Path $repositoryRoot 'tools\prepare-detector-release.ps1'
$powerShellExe = Join-Path $PSHOME 'powershell.exe'
$tempBase = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\', '/')
$tempRoot = Join-Path $tempBase ('detector-release-publication-{0}' -f [Guid]::NewGuid().ToString('N'))

function Assert-True {
    param(
        [Parameter(Mandatory = $true)][bool]$Condition,
        [Parameter(Mandatory = $true)][string]$Message
    )

    if (-not $Condition) {
        throw ('DETECTOR PUBLICATION CONTRACT: {0}' -f $Message)
    }
}

function Assert-Equal {
    param(
        [AllowNull()]$Actual,
        [AllowNull()]$Expected,
        [Parameter(Mandatory = $true)][string]$Message
    )

    if (-not ($Actual -ceq $Expected)) {
        throw ('DETECTOR PUBLICATION CONTRACT: {0}' -f $Message)
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

function Invoke-Preparation {
    param(
        [Parameter(Mandatory = $true)][string]$Tag,
        [Parameter(Mandatory = $true)][string]$Output
    )

    $previousErrorActionPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $lines = @(& $powerShellExe -NoProfile -ExecutionPolicy Bypass -File $prepareScript -TagName $Tag -OutputDirectory $Output 2>&1)
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }

    return [pscustomobject]@{
        ExitCode = $exitCode
        Text = ($lines -join [Environment]::NewLine).Trim()
    }
}

try {
    Assert-True -Condition (Test-Path -LiteralPath $prepareScript -PathType Leaf) -Message 'Preparation script is missing.'
    Assert-True -Condition (Test-Path -LiteralPath $powerShellExe -PathType Leaf) -Message 'Windows PowerShell is unavailable.'
    [IO.Directory]::CreateDirectory($tempRoot) | Out-Null

    $stage = Join-Path $tempRoot 'detector-release-stage'
    $positive = Invoke-Preparation -Tag 'detector-v1.0.2' -Output $stage
    Assert-Equal -Actual $positive.ExitCode -Expected 0 -Message 'Valid release preparation failed.'
    $summary = $positive.Text | ConvertFrom-Json
    Assert-Equal -Actual ([string]$summary.tagName) -Expected 'detector-v1.0.2' -Message 'Summary tag differs.'
    Assert-Equal -Actual ([string]$summary.version) -Expected '1.0.2' -Message 'Summary version differs.'
    Assert-Equal -Actual ([string]$summary.title) -Expected 'Windows AI detector v1.0.2' -Message 'Summary title differs.'

    $expectedFiles = @(
        'PROVENANCE.md',
        'RELEASE_NOTES.md',
        'release.json',
        'SHA256SUMS.txt',
        'windows-ai-detector-release-v1.0.2.zip',
        'windows-ai-detector-release-v1.0.2.zip.sha256.txt'
    )
    $actualFiles = @(Get-ChildItem -LiteralPath $stage -File | ForEach-Object { $_.Name })
    Assert-ExactSet -Actual $actualFiles -Expected $expectedFiles -Message 'Staged files differ.'

    $sourceMap = [ordered]@{
        'PROVENANCE.md' = 'detector\releases\v1.0.2\PROVENANCE.md'
        'RELEASE_NOTES.md' = 'detector\releases\v1.0.2\RELEASE_NOTES.md'
        'release.json' = 'detector\releases\v1.0.2\release.json'
        'SHA256SUMS.txt' = 'public\downloads\SHA256SUMS.txt'
        'windows-ai-detector-release-v1.0.2.zip' = 'public\downloads\windows-ai-detector-release-v1.0.2.zip'
        'windows-ai-detector-release-v1.0.2.zip.sha256.txt' = 'public\downloads\windows-ai-detector-release-v1.0.2.zip.sha256.txt'
    }
    foreach ($entry in $sourceMap.GetEnumerator()) {
        $sourceHash = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $repositoryRoot $entry.Value)).Hash
        $stageHash = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $stage $entry.Key)).Hash
        Assert-Equal -Actual $stageHash -Expected $sourceHash -Message ('Staged hash differs for {0}.' -f $entry.Key)
    }

    $invalidTags = @(
        'v1.0.2',
        'detector-v1.0',
        'detector-v1.0.2-rc.1',
        'detector-v01.0.2',
        'DETECTOR-v1.0.2',
        'detector-v1.0.2/other',
        'detector-v1.0.2;Write-Output-bad'
    )
    for ($index = 0; $index -lt $invalidTags.Count; $index++) {
        $invalidOutput = Join-Path $tempRoot ('invalid-{0}' -f $index)
        $negative = Invoke-Preparation -Tag $invalidTags[$index] -Output $invalidOutput
        Assert-True -Condition ($negative.ExitCode -ne 0) -Message ('Invalid tag was accepted at index {0}.' -f $index)
        Assert-True -Condition (-not (Test-Path -LiteralPath $invalidOutput)) -Message ('Invalid tag created staging at index {0}.' -f $index)
    }

    $nonEmpty = Join-Path $tempRoot 'non-empty'
    [IO.Directory]::CreateDirectory($nonEmpty) | Out-Null
    $sentinel = Join-Path $nonEmpty 'sentinel.txt'
    [IO.File]::WriteAllText($sentinel, 'preserve', (New-Object Text.UTF8Encoding($false)))
    $nonEmptyResult = Invoke-Preparation -Tag 'detector-v1.0.2' -Output $nonEmpty
    Assert-True -Condition ($nonEmptyResult.ExitCode -ne 0) -Message 'Non-empty staging directory was accepted.'
    Assert-Equal -Actual ([IO.File]::ReadAllText($sentinel)) -Expected 'preserve' -Message 'Non-empty staging contents changed.'
    Assert-ExactSet -Actual @(Get-ChildItem -LiteralPath $nonEmpty -File | ForEach-Object { $_.Name }) -Expected @('sentinel.txt') -Message 'Non-empty staging contents differ.'

    $repositoryOutput = Join-Path $repositoryRoot '.detector-release-test-output'
    Assert-True -Condition (-not (Test-Path -LiteralPath $repositoryOutput)) -Message 'Repository output test path already exists.'
    $repositoryResult = Invoke-Preparation -Tag 'detector-v1.0.2' -Output $repositoryOutput
    Assert-True -Condition ($repositoryResult.ExitCode -ne 0) -Message 'Repository-local staging was accepted.'
    Assert-True -Condition $repositoryResult.Text.Contains('Output directory must be outside the repository.') -Message 'Repository-local staging failed for the wrong reason.'
    Assert-True -Condition (-not (Test-Path -LiteralPath $repositoryOutput)) -Message 'Repository-local staging path was created.'

    $caseVariantRepositoryRoot = $repositoryRoot.ToUpperInvariant()
    if (-not $caseVariantRepositoryRoot.Equals($repositoryRoot, [StringComparison]::Ordinal)) {
        $caseVariantResult = Invoke-Preparation -Tag 'detector-v1.0.2' -Output $caseVariantRepositoryRoot
        Assert-True -Condition ($caseVariantResult.ExitCode -ne 0) -Message 'Case-variant repository root was accepted.'
        Assert-True -Condition $caseVariantResult.Text.Contains('Output directory must be outside the repository.') -Message 'Case-variant repository root failed for the wrong reason.'
    }

    Write-Output 'DETECTOR_RELEASE_PUBLICATION_CONTRACT PASS: valid staging, 7 invalid tags, non-empty preservation, checksum completeness, repository isolation.'
}
finally {
    if (Test-Path -LiteralPath $tempRoot) {
        $resolvedTemp = [IO.Path]::GetFullPath($tempRoot)
        $expectedPrefix = $tempBase + [IO.Path]::DirectorySeparatorChar
        $leaf = Split-Path $resolvedTemp -Leaf
        if ($resolvedTemp.StartsWith($expectedPrefix, [StringComparison]::OrdinalIgnoreCase) -and $leaf -like 'detector-release-publication-*') {
            Remove-Item -LiteralPath $resolvedTemp -Recurse -Force
        }
        else {
            throw ('DETECTOR PUBLICATION CONTRACT: Refusing to clean unexpected path: {0}' -f $resolvedTemp)
        }
    }
}
