# zh-cn-sync.ps1 — decide which upstream release tag to build.
#
# Release-only: the fork follows upstream GitHub releases (tags), not main
# commits. Upstream has no Windows build workflow, so we build the exact tag
# ourselves with patches/zh-cn.patch + patches/installer-zh-cn.patch.
#
#   release -> the latest (or requested) upstream tag has no zhCN-RHI-<tag>
#   none    -> that release already exists (unless -Force)

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

# ── Resolve the upstream release tag ─────────────────────────────────────────
git remote get-url upstream *> $null
if ($LASTEXITCODE -ne 0) {
    git remote add upstream "https://github.com/$UpstreamRepo.git"
}
git fetch upstream main --tags --prune 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'git fetch upstream failed' }

if ($InputRef) {
    $versionTag = $InputRef
    git rev-parse --verify "refs/tags/$versionTag^{commit}" *> $null
    if ($LASTEXITCODE -ne 0) {
        throw "Only upstream release tags are supported; '$InputRef' is not a fetched tag."
    }
} else {
    $versionTag = Get-LatestUpstreamTag
}

$target = $versionTag
$targetSha = (& git rev-parse --verify "$target^{commit}").Trim()
if (-not $targetSha) { throw "Cannot resolve '$target' to a commit." }

$releaseTag = "zhCN-$versionTag"
$releaseExists = $false
$view = Invoke-Gh @('release', 'view', $releaseTag, '--json', 'tagName')
$releaseExists = ($view.Code -eq 0)

$action = if (-not $releaseExists -or $Force) { 'release' } else { 'none' }

Set-PlanOutput 'action' $action
Set-PlanOutput 'target' $target
Set-PlanOutput 'target_sha' $targetSha
Set-PlanOutput 'version_tag' $versionTag
Set-PlanOutput 'release_tag' $releaseTag

if ($action -eq 'none') {
    Write-Host "Nothing to do: $releaseTag already exists."
} else {
    Write-Host "Plan: action=$action target=$target sha=$targetSha versionTag=$versionTag releaseTag=$releaseTag"
}

# gh release view intentionally returns 1 when a release does not exist; do not
# let that become the script's exit code.
exit 0
