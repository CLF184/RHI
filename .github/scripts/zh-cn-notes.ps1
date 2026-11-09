# Generates release-notes.md for a versioned zh-CN release.
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Version,
    [Parameter(Mandatory = $true)][string]$VersionTag,
    [Parameter(Mandatory = $true)][string]$BuiltSha,
    [Parameter(Mandatory = $true)][string]$UpstreamSha,
    [Parameter(Mandatory = $true)][string]$DownloadZip,
    [Parameter(Mandatory = $true)][string]$DownloadSetup
)

$notes = @"
## RHI 简体中文版 $Version

对应上游版本：$VersionTag（commit $UpstreamSha）
源码：构建分支 zh-cn-build @ $BuiltSha（由 patches/zh-cn.patch + patches/installer-zh-cn.patch 应用到上游 tag 构建）

### 下载

推荐安装器：$DownloadSetup
与官方安装器使用同一个 AppId，可直接覆盖已安装的官方版；设置、已装模组和游戏列表都会保留。

便携版：$DownloadZip
整目录解压后运行 RHI.exe，不要只拷贝 exe。

两个文件都有同名 .sha256 校验文件。

### 切换语言

Settings → Language → 简体中文（默认跟随系统语言）。

### 更新

应用内「检查更新」指向本仓库的 Releases；检测到新版本时会打开下载页面，下载安装器或便携包后更新。

### 说明

非官方简体中文构建，遵循上游 GPL-3.0 许可；除界面汉化和安装器语言外，代码与上游保持同步。
上游 2.9.x 新增的部分界面文案尚未汉化。
"@

$notes | Out-File -FilePath release-notes.md -Encoding utf8
Write-Host "Wrote release-notes.md ($Version)"
exit 0
