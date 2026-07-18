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

    for ($attempt = 1; $attempt -le 3; $attempt++) {
        $previousErrorActionPreference = $ErrorActionPreference
        try {
            $ErrorActionPreference = 'Continue'
            $raw = @(& gh api $Endpoint 2>$null)
            $exitCode = $LASTEXITCODE
        }
        finally {
            $ErrorActionPreference = $previousErrorActionPreference
        }

        if ($exitCode -eq 0) {
            $joined = $raw -join [Environment]::NewLine
            if (-not [string]::IsNullOrWhiteSpace($joined)) {
                try {
                    return ($joined | ConvertFrom-Json)
                }
                catch {
                    # Retry without printing the response body.
                }
            }
        }

        if ($attempt -lt 3) {
            Start-Sleep -Seconds 2
        }
    }

    throw ('GitHub API request failed after retries: {0}' -f $Endpoint)
}

function Get-GhPagedCount {
    param(
        [Parameter(Mandatory = $true)][string]$Endpoint,
        [Parameter(Mandatory = $true)][string]$ApiName
    )

    $exitCode = 1
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        $previousErrorActionPreference = $ErrorActionPreference
        try {
            $ErrorActionPreference = 'Continue'
            $pageCounts = @(& gh api --paginate $Endpoint --jq 'length' 2>$null)
            $exitCode = $LASTEXITCODE
        }
        finally {
            $ErrorActionPreference = $previousErrorActionPreference
        }

        if ($exitCode -eq 0) {
            break
        }
        if ($attempt -lt 3) {
            Start-Sleep -Seconds 2
        }
    }

    if ($exitCode -ne 0) {
        throw ('{0} API is not readable.' -f $ApiName)
    }
    if ($pageCounts.Count -eq 0) {
        throw ('{0} API did not return page counts.' -f $ApiName)
    }

    $total = 0
    foreach ($pageCountText in $pageCounts) {
        $pageCount = 0
        if (-not [int]::TryParse(([string]$pageCountText).Trim(), [ref]$pageCount)) {
            throw ('{0} API returned an invalid page count.' -f $ApiName)
        }
        $total += $pageCount
    }

    return $total
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
$checkDifference = @(Compare-Object -ReferenceObject $expectedChecks -DifferenceObject $actualChecks -CaseSensitive)
Assert-Equal -Actual $checkDifference.Count -Expected 0 -Name 'required-check-contexts-exact'

Assert-Equal -Actual ([bool]$protection.enforce_admins.enabled) -Expected $true -Name 'enforce-admins-enabled'
Assert-Equal -Actual ([int]$protection.required_pull_request_reviews.required_approving_review_count) -Expected 0 -Name 'required-approvals-zero'
Assert-Equal -Actual ([bool]$protection.required_pull_request_reviews.require_last_push_approval) -Expected $false -Name 'last-push-approval-disabled'

$bypassCount = 0
$bypassProperty = $protection.required_pull_request_reviews.PSObject.Properties['bypass_pull_request_allowances']
if ($null -ne $bypassProperty -and $null -ne $bypassProperty.Value) {
    foreach ($allowanceType in @('users', 'teams', 'apps')) {
        $allowanceProperty = $bypassProperty.Value.PSObject.Properties[$allowanceType]
        if ($null -ne $allowanceProperty) {
            $bypassCount += @($allowanceProperty.Value).Count
        }
    }
}
Assert-Equal -Actual $bypassCount -Expected 0 -Name 'bypass-pull-request-allowances-empty'

Assert-Equal -Actual ([bool]$protection.required_linear_history.enabled) -Expected $true -Name 'linear-history-enabled'
Assert-Equal -Actual ([bool]$protection.required_conversation_resolution.enabled) -Expected $true -Name 'conversation-resolution-enabled'
Assert-Equal -Actual ([bool]$protection.allow_force_pushes.enabled) -Expected $false -Name 'force-push-disabled'
Assert-Equal -Actual ([bool]$protection.allow_deletions.enabled) -Expected $false -Name 'branch-deletion-disabled'
Assert-Equal -Actual ([bool]$protection.lock_branch.enabled) -Expected $false -Name 'lock-branch-disabled'
$restrictionsProperty = $protection.PSObject.Properties['restrictions']
$restrictionsDisabled = ($null -eq $restrictionsProperty -or $null -eq $restrictionsProperty.Value)
Assert-Equal -Actual $restrictionsDisabled -Expected $true -Name 'push-restrictions-disabled'

$privateReporting = Invoke-GhJson -Endpoint ('repos/{0}/private-vulnerability-reporting' -f $Repository)
Assert-Equal -Actual ([bool]$privateReporting.enabled) -Expected $true -Name 'private-vulnerability-reporting-enabled'

$dependabotAlertUri = 'repos/{0}/dependabot/alerts?state=open&per_page=100' -f $Repository
$dependabotAlertCount = Get-GhPagedCount -Endpoint $dependabotAlertUri -ApiName 'Dependabot alerts'
Assert-Equal -Actual $dependabotAlertCount -Expected 0 -Name 'dependabot-open-alert-count-0'

$codeqlSetup = Invoke-GhJson -Endpoint ('repos/{0}/code-scanning/default-setup' -f $Repository)
Assert-Equal -Actual ([string]$codeqlSetup.state) -Expected 'configured' -Name 'codeql-default-setup-configured'

$codeqlLanguages = @($codeqlSetup.languages | ForEach-Object { [string]$_ })
Assert-Equal -Actual ($codeqlLanguages -ccontains 'actions') -Expected $true -Name 'codeql-actions-language-enabled'
Assert-Equal -Actual ($codeqlLanguages -ccontains 'javascript-typescript') -Expected $true -Name 'codeql-javascript-typescript-language-enabled'
Assert-Equal -Actual ([string]$codeqlSetup.query_suite) -Expected 'default' -Name 'codeql-query-suite-default'
Assert-Equal -Actual ([string]$codeqlSetup.threat_model) -Expected 'remote' -Name 'codeql-threat-model-remote'

$noCustomRunnerLabel = [string]::IsNullOrWhiteSpace([string]$codeqlSetup.runner_label)
$standardRunner = (([string]$codeqlSetup.runner_type -ceq 'standard') -and $noCustomRunnerLabel)
Assert-Equal -Actual $standardRunner -Expected $true -Name 'codeql-standard-runner'

$codeScanningAlertUri = 'repos/{0}/code-scanning/alerts?state=open&per_page=100' -f $Repository
$codeScanningAlertCount = Get-GhPagedCount -Endpoint $codeScanningAlertUri -ApiName 'Code scanning alerts'
Assert-Equal -Actual $codeScanningAlertCount -Expected 0 -Name 'code-scanning-open-alert-count-0'

$pages = Invoke-GhJson -Endpoint ('repos/{0}/pages' -f $Repository)
Assert-Equal -Actual ([string]$pages.build_type) -Expected 'workflow' -Name 'pages-build-type-workflow'
Assert-Equal -Actual ([bool]$pages.https_enforced) -Expected $true -Name 'pages-https-enforced'

Write-Output ('Repository governance verification passed: {0} checks.' -f $script:PassCount)
