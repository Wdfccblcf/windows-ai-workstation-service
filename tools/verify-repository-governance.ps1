[CmdletBinding()]
param(
    [ValidatePattern('^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$')]
    [string]$Repository = 'Wdfccblcf/windows-ai-workstation-service'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:PassCount = 0

function Write-Pass {
    param([Parameter(Mandatory = $true)][string]$Name)

    $script:PassCount++
    Write-Output ('PASS {0}' -f $Name)
}

function Assert-Equal {
    param(
        [Parameter(Mandatory = $true)]$Actual,
        [Parameter(Mandatory = $true)]$Expected,
        [Parameter(Mandatory = $true)][string]$Name
    )

    if (-not ($Actual -ceq $Expected)) {
        throw ('Governance assertion failed: {0}' -f $Name)
    }

    Write-Pass -Name $Name
}

function Invoke-GhJson {
    param([Parameter(Mandatory = $true)][string]$Endpoint)

    $raw = @(& gh api $Endpoint 2>$null)
    if ($LASTEXITCODE -ne 0) {
        throw ('GitHub API request failed: {0}' -f $Endpoint)
    }

    $joined = $raw -join [Environment]::NewLine
    if ([string]::IsNullOrWhiteSpace($joined)) {
        throw ('GitHub API returned no JSON: {0}' -f $Endpoint)
    }

    try {
        return ($joined | ConvertFrom-Json)
    }
    catch {
        throw ('GitHub API returned invalid JSON: {0}' -f $Endpoint)
    }
}

if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    throw 'GitHub CLI is required.'
}

& gh auth status --hostname github.com 1>$null 2>$null
if ($LASTEXITCODE -ne 0) {
    throw 'GitHub CLI is not authenticated for github.com.'
}
Write-Pass -Name 'gh-authenticated'

$repositoryInfo = Invoke-GhJson -Endpoint ('repos/{0}' -f $Repository)
Assert-Equal -Actual ([string]$repositoryInfo.default_branch) -Expected 'main' -Name 'default-branch-main'
Assert-Equal -Actual ([string]$repositoryInfo.security_and_analysis.secret_scanning.status) -Expected 'enabled' -Name 'secret-scanning-enabled'
Assert-Equal -Actual ([string]$repositoryInfo.security_and_analysis.secret_scanning_push_protection.status) -Expected 'enabled' -Name 'push-protection-enabled'
Assert-Equal -Actual ([string]$repositoryInfo.security_and_analysis.dependabot_security_updates.status) -Expected 'disabled' -Name 'dependabot-security-updates-disabled'

$automatedSecurityFixes = Invoke-GhJson -Endpoint ('repos/{0}/automated-security-fixes' -f $Repository)
Assert-Equal -Actual ([bool]$automatedSecurityFixes.enabled) -Expected $false -Name 'automated-security-fixes-disabled'

$actionPermissions = Invoke-GhJson -Endpoint ('repos/{0}/actions/permissions' -f $Repository)
Assert-Equal -Actual ([bool]$actionPermissions.enabled) -Expected $true -Name 'actions-enabled'
Assert-Equal -Actual ([string]$actionPermissions.allowed_actions) -Expected 'selected' -Name 'actions-selected'
Assert-Equal -Actual ([bool]$actionPermissions.sha_pinning_required) -Expected $false -Name 'action-sha-pinning-not-required'

$selectedActions = Invoke-GhJson -Endpoint ('repos/{0}/actions/permissions/selected-actions' -f $Repository)
Assert-Equal -Actual ([bool]$selectedActions.github_owned_allowed) -Expected $true -Name 'github-owned-actions-enabled'
Assert-Equal -Actual ([bool]$selectedActions.verified_allowed) -Expected $false -Name 'verified-actions-disabled'
Assert-Equal -Actual (@($selectedActions.patterns_allowed).Count) -Expected 0 -Name 'action-pattern-allowlist-empty'

$workflowPermissions = Invoke-GhJson -Endpoint ('repos/{0}/actions/permissions/workflow' -f $Repository)
Assert-Equal -Actual ([string]$workflowPermissions.default_workflow_permissions) -Expected 'read' -Name 'workflow-default-read'
Assert-Equal -Actual ([bool]$workflowPermissions.can_approve_pull_request_reviews) -Expected $false -Name 'workflow-pr-approval-disabled'

$protection = Invoke-GhJson -Endpoint ('repos/{0}/branches/main/protection' -f $Repository)
Assert-Equal -Actual ([bool]$protection.required_status_checks.strict) -Expected $true -Name 'required-checks-strict'

$expectedChecks = @(
    'Build Pages artifact',
    'Verify (ubuntu-latest)',
    'Verify (windows-latest)'
)
$actualChecks = @($protection.required_status_checks.checks | ForEach-Object { [string]$_.context } | Sort-Object)
$checkDifference = @(Compare-Object -ReferenceObject $expectedChecks -DifferenceObject $actualChecks)
Assert-Equal -Actual $checkDifference.Count -Expected 0 -Name 'required-check-contexts-exact'

Assert-Equal -Actual ([bool]$protection.enforce_admins.enabled) -Expected $true -Name 'enforce-admins-enabled'
Assert-Equal -Actual ([int]$protection.required_pull_request_reviews.required_approving_review_count) -Expected 0 -Name 'required-approvals-zero'
Assert-Equal -Actual ([bool]$protection.required_pull_request_reviews.require_last_push_approval) -Expected $false -Name 'last-push-approval-disabled'
Assert-Equal -Actual ([bool]$protection.required_linear_history.enabled) -Expected $true -Name 'linear-history-enabled'
Assert-Equal -Actual ([bool]$protection.required_conversation_resolution.enabled) -Expected $true -Name 'conversation-resolution-enabled'
Assert-Equal -Actual ([bool]$protection.allow_force_pushes.enabled) -Expected $false -Name 'force-push-disabled'
Assert-Equal -Actual ([bool]$protection.allow_deletions.enabled) -Expected $false -Name 'branch-deletion-disabled'

$privateReporting = Invoke-GhJson -Endpoint ('repos/{0}/private-vulnerability-reporting' -f $Repository)
Assert-Equal -Actual ([bool]$privateReporting.enabled) -Expected $true -Name 'private-vulnerability-reporting-enabled'

$alertUri = 'repos/{0}/dependabot/alerts?state=open&per_page=100' -f $Repository
$alertPageCounts = @(& gh api --paginate $alertUri --jq 'length' 2>$null)
if ($LASTEXITCODE -ne 0) {
    throw 'Dependabot alerts API is not readable.'
}

$alertCount = 0
if ($alertPageCounts.Count -eq 0) {
    throw 'Dependabot alerts API did not return page counts.'
}

foreach ($alertPageCount in $alertPageCounts) {
    $pageCount = 0
    if (-not [int]::TryParse(([string]$alertPageCount).Trim(), [ref]$pageCount)) {
        throw 'Dependabot alerts API returned an invalid page count.'
    }
    $alertCount += $pageCount
}
Write-Pass -Name ('dependabot-open-alert-count-{0}' -f $alertCount)

$pages = Invoke-GhJson -Endpoint ('repos/{0}/pages' -f $Repository)
Assert-Equal -Actual ([string]$pages.build_type) -Expected 'workflow' -Name 'pages-build-type-workflow'
Assert-Equal -Actual ([bool]$pages.https_enforced) -Expected $true -Name 'pages-https-enforced'

Write-Output ('Repository governance verification passed: {0} checks.' -f $script:PassCount)
