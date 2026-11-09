# zh-cn-sync.ps1 — decide what to build for the patch-based zh-CN fork.
#
# The default branch stays close to upstream: it only carries this workflow,
# the scripts, patches/zh-cn.patch and docs. The workflow checks out an
# upstream tag/commit in a temp worktree, applies the patch, and builds there.
#
# This script only *plans*: it resolves the target and decides between
#   release -> a new upstream release tag needs a zhCN-RHI-<tag> release
#   dev     -> upstream main moved and zhCN-latest is stale
#   none    -> nothing to do
# Applying the patch and handling conflicts happens in the workflow step.

[CmdletBinding()]
param(
    [string]$UpstreamRepo = 'RankFTW/RHI',
    [string]$InputRef = '',
    [switch]$Force
)

# Continue (not Stop): gh writes expected "release not found" to stderr, which
# Windows PowerShell 5.1 turns into an ErrorRecord. Exit codes are checked.
$ErrorActionPreference = 'Continue'

function Set-PlanOutput {
    param([string]$Name, [string]$Value)
    if ($env:GITHUB_OUTPUT) {
        "$Name=$Value" >> $env:GITHUB_OUTPUT
    } else {
        Write-Host "plan: $Name=$Value"
    }
}

function Invoke-Gh {
    param([string[]]$GhArgs)
    $errFile = [IO.Path]::GetTempFileName()
    try {
        $out = & gh @GhArgs 2> $errFile
        $code = $LASTEXITCODE
        $text = if ($out -is [array]) { ($out -join "`n").Trim() } else { "$out".Trim() }
        return @{ Text = $text; Code = $code }
    } finally {
        Remove-Item $errFile -ErrorAction SilentlyContinue
    }
}

function Get-LatestUpstreamTag {
    for ($i = 0; $i -lt 3; $i++) {
        $r = Invoke-Gh @('api', "repos/$UpstreamRepo/releases/latest", '--jq', '.tag_name')
        if ($r.Code -eq 0 -and $r.Text) { return $r.Text }
        Start-Sleep -Seconds 3
    }

    $r = Invoke-Gh @('api', "repos/$UpstreamRepo/tags", '--jq', '.[0].name')
    if ($r.Code -eq 0 -and $r.Text) { return $r.Text }
    throw "Cannot determine the latest upstream release/tag for $UpstreamRepo."
}

function Get-CommitMessage {
    param([string]$Rev)
    return ((& git log -1 --format=%B $Rev) -join "`n").Trim()
}

# Build commits are created as:
#   zhCN: apply localization patch to <target> (upstream <40-char sha>)
# Read that SHA back to tell whether zhCN-latest already covers a commit.
function Get-UpstreamShaFromMessage {
    param([string]$Message)
    if ($Message -match 'upstream ([0-9a-f]{40})') { return $Matches[1] }
    return ''
}

# ── Fetch upstream and origin state ──────────────────────────────────────────
git remote get-url upstream *> $null
if ($LASTEXITCODE -ne 0) {
    git remote add upstream "https://github.com/$UpstreamRepo.git"
}
git fetch upstream main --tags --prune 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'git fetch upstream failed' }
git fetch origin --tags --prune 2>&1 | Out-Null

$latestTag = Get-LatestUpstreamTag
$latestSha = (& git rev-parse --verify "$latestTag^{commit}").Trim()
$mainSha = (& git rev-parse --verify 'upstream/main^{commit}').Trim()
if (-not $latestSha -or -not $mainSha) { throw 'Cannot resolve upstream refs.' }

$devUpstreamSha = ''
git rev-parse --verify 'refs/tags/zhCN-latest^{commit}' *> $null
if ($LASTEXITCODE -eq 0) {
    $devUpstreamSha = Get-UpstreamShaFromMessage (Get-CommitMessage 'zhCN-latest')
}

function Test-ReleaseExists {
    param([string]$Tag)
    $r = Invoke-Gh @('release', 'view', $Tag, '--json', 'tagName')
    return ($r.Code -eq 0)
}

$action = 'none'
$target = ''
$targetSha = ''
$versionTag = $latestTag
$releaseTag = "zhCN-$latestTag"

if ($InputRef) {
    $target = $InputRef
    git rev-parse --verify "refs/tags/$InputRef^{commit}" *> $null
    $isTag = ($LASTEXITCODE -eq 0)
    if (-not $isTag) {
        git fetch upstream $InputRef 2>&1 | Out-Null
    }
    $targetSha = (& git rev-parse --verify "$InputRef^{commit}").Trim()
    if (-not $targetSha) { throw "Cannot resolve upstream ref '$InputRef'." }

    if ($isTag) {
        $versionTag = $InputRef
        $releaseTag = "zhCN-$versionTag"
        $releaseExists = Test-ReleaseExists $releaseTag
        if (-not $releaseExists -or $Force) {
            $action = 'release'
        }
    } elseif ($Force -or $devUpstreamSha -ne $targetSha) {
        $action = 'dev'
    }
} else {
    $releaseExists = Test-ReleaseExists $releaseTag
    if (-not $releaseExists -or $Force) {
        # New upstream release: build the release tag itself (exact source).
        $action = 'release'
        $target = $latestTag
        $targetSha = $latestSha
    } elseif ($mainSha -ne $latestSha -and $devUpstreamSha -ne $mainSha) {
        # main has commits past the latest release and zhCN-latest is stale.
        $action = 'dev'
        $target = 'upstream/main'
        $targetSha = $mainSha
    }
    # main == latest release commit: the release already covers it, no dev build.
}

Set-PlanOutput 'action' $action
Set-PlanOutput 'target' $target
Set-PlanOutput 'target_sha' $targetSha
Set-PlanOutput 'version_tag' $versionTag
Set-PlanOutput 'release_tag' $releaseTag

if ($action -eq 'none') {
    Write-Host 'Nothing to do: latest release and zhCN-latest are current.'
} else {
    Write-Host "Plan: action=$action target=$target sha=$targetSha versionTag=$versionTag releaseTag=$releaseTag"
}

# gh release view intentionally returns 1 when a release does not exist; do not
# let that become the script's exit code.
exit 0
