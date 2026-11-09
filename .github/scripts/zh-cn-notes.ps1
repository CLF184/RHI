# Generates release-notes.md for the patch-based zh-CN sync workflow.
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Action,
    [Parameter(Mandatory = $true)][string]$Version,
    [string]$VersionTag = '',
    [Parameter(Mandatory = $true)][string]$BuiltSha,
    [Parameter(Mandatory = $true)][string]$UpstreamSha,
    [Parameter(Mandatory = $true)][string]$Download
)

if ($Action -eq 'release') {
    $notes = @"
## RHI 简体中文版 $Version

对应上游版本：$VersionTag（commit $UpstreamSha）
源码：构建分支 zh-cn-build @ $BuiltSha（由 patches/zh-cn.patch 应用到上游源码构建）

### 下载

$Download（整目录解压后运行 RHI.exe，不要只拷贝 exe）

### 已经装了官方版？

退出 RHI，把解压出的全部文件覆盖进安装目录（默认 C:\Program Files\RHI）。
设置、已装模组和游戏列表都会保留。

### 切换语言

Settings → Language → 简体中文（默认跟随系统语言）。

### 说明

非官方简体中文构建，遵循上游 GPL-3.0 许可；除界面汉化外，代码与上游保持同步。
应用内的「检查更新」指向本仓库的 Releases；有新版本时会打开此页面，下载后整目录覆盖即可。
上游 2.9.x 新增的部分界面文案、安装器尚未汉化。
"@
} else {
    $notes = @"
## RHI 简体中文开发版 $Version

跟随上游 main 最新提交 $UpstreamSha 的滚动构建，可能不稳定。
上游发布正式 release 后，会另外生成对应的 zhCN-RHI-<版本> 包。

源码：构建分支 zh-cn-build @ $BuiltSha（由 patches/zh-cn.patch 应用到上游源码构建）

### 下载

$Download（整目录解压后运行 RHI.exe，不要只拷贝 exe）

### 切换语言

Settings → Language → 简体中文（默认跟随系统语言）。

### 说明

非官方简体中文构建，遵循上游 GPL-3.0 许可。
"@
}

$notes | Out-File -FilePath release-notes.md -Encoding utf8
Write-Host "Wrote release-notes.md ($Action, $Version)"
exit 0
