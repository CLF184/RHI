# Opens/updates the zh-cn-sync issue when patches/zh-cn.patch does not apply
# cleanly to an upstream target.
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Target,
    [Parameter(Mandatory = $true)][string]$TargetSha,
    [string[]]$Conflicts = @()
)

$ErrorActionPreference = 'Continue'

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

$runUrl = if ($env:GITHUB_RUN_ID) {
    "$env:GITHUB_SERVER_URL/$env:GITHUB_REPOSITORY/actions/runs/$env:GITHUB_RUN_ID"
} else { '(local run)' }

$fileList = if ($Conflicts.Count -gt 0) {
    ($Conflicts | ForEach-Object { "- ``$_``" }) -join "`n"
} else {
    '- (git did not report file names; see the workflow log)'
}

$body = @"
## 汉化补丁应用冲突

自动构建把 ``patches/zh-cn.patch`` 应用到上游 ``$Target``（commit ``$TargetSha``）时发生冲突。
构建已中止，**没有推送源码分支，也没有创建 release**。

### 冲突文件

$fileList

### 处理方式

在本地把补丁应用到该上游目标，解决冲突，然后重新生成补丁：

``````
git clone https://github.com/$env:GITHUB_REPOSITORY.git
cd RHI
git remote add upstream https://github.com/RankFTW/RHI.git
git fetch upstream --tags
git worktree add --detach ../build $TargetSha
cd ../build
git apply --3way ../RHI/patches/zh-cn.patch
# 编辑冲突文件：保留上游新逻辑 + 补回汉化调用
git add -A
git commit -m "zhCN: resolve patch against $Target"
git diff --no-color --full-index $TargetSha HEAD -- RenoDXCommander RenoDXCommander.Tests > ../RHI/patches/zh-cn.patch
``````

提交更新后的补丁并推送 ``zh-cn`` 分支，然后重新运行 workflow（或等下一次定时任务）：

``````
cd ../RHI
git add patches/zh-cn.patch
git commit -m "zhCN: rebase localization patch onto $Target"
git push origin zh-cn
``````

运行记录：$runUrl
"@

Invoke-Gh @('label', 'create', 'zh-cn-sync', '--color', 'BFD4F2',
    '--description', 'Upstream sync conflicts', '--force') | Out-Null

$list = Invoke-Gh @('issue', 'list', '--state', 'open', '--label', 'zh-cn-sync',
    '--limit', '1', '--json', 'number', '--jq', '.[0].number')
$issueNumber = $list.Text
if ($issueNumber -and $issueNumber -ne 'null') {
    Invoke-Gh @('issue', 'comment', $issueNumber, '--body', $body) | Out-Null
    Write-Host "Commented on issue #$issueNumber"
} else {
    $created = Invoke-Gh @('issue', 'create', '--title',
        '[zh-CN sync] 汉化补丁应用冲突，需要人工处理', '--label', 'zh-cn-sync', '--body', $body)
    Write-Host "Created issue: $($created.Text)"
}
