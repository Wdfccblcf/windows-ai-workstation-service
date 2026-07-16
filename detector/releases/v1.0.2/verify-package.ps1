[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$KitRoot,

    [Parameter()]
    [string]$ManifestPath = "",

    [switch]$Quiet
)

$ErrorActionPreference = "Stop"
$resolvedRoot = [IO.Path]::GetFullPath($KitRoot).TrimEnd('\', '/')
if (-not (Test-Path -LiteralPath $resolvedRoot -PathType Container)) { throw "交付包目录不存在。" }
if ([string]::IsNullOrWhiteSpace($ManifestPath)) { $ManifestPath = Join-Path $resolvedRoot "SHA256SUMS.txt" }
$resolvedManifest = [IO.Path]::GetFullPath($ManifestPath)
if (-not (Test-Path -LiteralPath $resolvedManifest -PathType Leaf)) { throw "缺少 SHA256SUMS.txt，拒绝启动。" }

$checked = 0
foreach ($line in Get-Content -LiteralPath $resolvedManifest -Encoding UTF8) {
    if ([string]::IsNullOrWhiteSpace($line)) { continue }
    if ($line -notmatch '^([0-9a-fA-F]{64})\s{2}(.+)$') { throw "校验清单格式不正确。" }
    $expected = $Matches[1].ToLowerInvariant()
    $relative = $Matches[2]
    if ([IO.Path]::IsPathRooted($relative) -or $relative -match '(^|[\\/])\.\.([\\/]|$)') { throw "校验清单包含越界路径。" }
    $target = [IO.Path]::GetFullPath((Join-Path $resolvedRoot $relative))
    if (-not $target.StartsWith(($resolvedRoot + [IO.Path]::DirectorySeparatorChar), [StringComparison]::OrdinalIgnoreCase)) { throw "校验目标越过交付包目录。" }
    if (-not (Test-Path -LiteralPath $target -PathType Leaf)) { throw "交付文件缺失：$relative" }
    $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $target).Hash.ToLowerInvariant()
    if ($actual -cne $expected) { throw "交付文件校验失败：$relative。文件可能损坏或被修改，拒绝继续。" }
    $checked++
}
if ($checked -lt 1) { throw "校验清单为空。" }
if (-not $Quiet) { Write-Output "完整性校验通过：$checked 个文件。" }
