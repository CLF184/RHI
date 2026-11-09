# RHI 简体中文版 · patch 自动构建与维护

本仓库是 [RankFTW/RHI](https://github.com/RankFTW/RHI) 的非官方简体中文分支。

默认分支基于上游 **RHI-2.9.2**，上游源码保持原样；相对上游只额外增加：

- `patches/zh-cn.patch`：应用汉化（约 4500 行 diff）
- `patches/installer-zh-cn.patch`：安装器中文语言
- `installer/ChineseSimplified.isl`：Inno Setup 官方中文语言文件（Chocolatey 包未附带，单独放入仓库）
- `.github/workflows/zh-cn-sync.yml` + `.github/scripts/`：自动同步、构建、发布
- 说明文档与打包用的 `README-patch.md`

CI 只跟随上游 **release tag**（不跟 `main` commit）。每次在上游 tag 的干净源码上应用两个补丁，
编译 app 和 Inno Setup 中文安装器，再发布。这样分支与上游的差异只有补丁和 CI。

## 下载

<https://github.com/CLF184/RHI/releases>

每个 `zhCN-RHI-<版本>` 发布包含两个产物（各带同名 `.sha256`）：

- `RHI-zhCN-<版本>-Setup.exe`：中文 Inno Setup 安装器，**推荐**。沿用官方 AppId，
  可直接覆盖已安装的官方版，设置、已装模组和游戏列表保留。
- `RHI-zhCN-<版本>-win-x64.zip`：便携版，整目录解压后运行 `RHI.exe`（不要只拷贝 exe）。

- **全新安装**：运行 Setup.exe，或解压便携包后运行 `RHI.exe`。
- **已装官方版**：运行 Setup.exe；或退出 RHI 后把便携包全部文件覆盖进安装目录
  （默认 `C:\Program Files\RHI`）。包内 `README-patch.md` 有步骤。
- **切换语言**：Settings → Language → 简体中文（默认跟随系统语言）。

> 便携版为什么不能只替换 `RHI.exe`：WinAppSDK 的 WinRT 组件必须由 COM 从磁盘上的真实文件激活。
> 官方那个约 100 MB 的单文件 exe 重新打包后启动会报 `0x80040111 ClassFactory`。
> 安装器会把完整的便携目录安装到目标文件夹，因此没有这个问题。

## 应用内更新

`UpdateService` 已指向 `CLF184/RHI` 的 `/releases/latest`（不是上游官方仓库）：

- 检测到新中文版本时弹窗显示版本号，按钮「打开下载页面」打开本仓库的 release 页。
- 不会自动下载/运行安装器，也不会被官方英文安装包覆盖。
- 下载 Setup.exe 运行，或下载便携包整目录覆盖即可。

## 自动化流程

`.github/workflows/zh-cn-sync.yml` 每 3 天北京时间 06:00（UTC 22:00）轮询一次上游 release
（cron 的 `*/3` 按每月 1、4、7…日执行，月初边界可能略有偏差；
fork 收不到上游的 release 事件，需要立即出包时用 Actions 页面的 Run workflow 手动触发）：

1. 读取 `RankFTW/RHI` 的最新 release tag（或手动的 `upstream_ref` tag）。
2. 如果对应的 `zhCN-RHI-<tag>` 已存在且未 `force`，直接结束。
3. 在该 tag 的精确 commit 上应用 `zh-cn.patch` + `installer-zh-cn.patch`。
4. 编译 app、构建 `RHI.DropHelper`、补齐 loose 文件，再用 Inno Setup 生成中文 `Setup.exe`。
5. 打包便携 zip，生成两个 `.sha256`。
6. 把打好补丁的源码提交推到 `zh-cn-build` 分支（release tag 指向该提交，满足 GPL 源码可得）。
7. 创建/更新 `zhCN-RHI-<tag>` release，上传 Setup.exe、便携 zip 和校验文件。
8. 补丁冲突或构建失败 → 中止，不推送源码、不发布；创建/更新带 `zh-cn-sync` 标签的 issue。

手动运行时可指定 `upstream_ref`（必须是已发布的 tag，例如 `RHI-2.9.2`）补发历史版本；
`force` 可强制重建已存在的版本。

### 一次性启用（fork 必须做）

1. **Actions 标签页** → “I understand my workflows, go ahead and enable them”（fork 默认禁用 Actions）。
2. **Settings → Actions → General → Workflow permissions** → **Read and write permissions**。
3. **默认分支设为 `zh-cn`**（Settings → General → Default branch）；schedule 只读取默认分支上的 workflow。
4. 仓库连续 60 天无活动时 schedule 会暂停；本 workflow 每次构建都会强制推送 `zh-cn-build`，属于仓库活动。

## 更新/维护补丁

### 本地复现补丁应用

```bash
git clone https://github.com/CLF184/RHI.git
cd RHI
git remote add upstream https://github.com/RankFTW/RHI.git
git fetch upstream --tags

git worktree add --detach ../build <upstream-sha>
cd ../build
git apply --3way ../RHI/patches/zh-cn.patch
git apply --3way ../RHI/patches/installer-zh-cn.patch
```

### 修改翻译/安装器或解决冲突

在应用了补丁的 worktree 里编辑（通常只需要改
`RenoDXCommander/Services/LocalizationService.cs`、冲突文件，或 `RHI Setup.iss` 的 `[Languages]`），
然后**以冲突/目标的上游 commit 为基准**重新生成补丁：

```bash
cd ../build
git add -A
git commit -m "zhCN: resolve against <upstream-ref>"
git diff --no-color --full-index <upstream-sha> HEAD -- \
  RenoDXCommander RenoDXCommander.Tests > ../RHI/patches/zh-cn.patch
git diff --no-color --full-index <upstream-sha> HEAD -- \
  "RHI Setup.iss" > ../RHI/patches/installer-zh-cn.patch
```

把新的两个补丁提交到 `zh-cn` 分支并推送，workflow 下次运行即可使用。
补丁基准会随这次重建变成新的上游 commit（更旧的 tag 不再保证能应用，通常也不需要）。

### 手工构建

```powershell
git worktree add --detach ../build <upstream-sha>
cd ../build
git apply --3way ../RHI/patches/zh-cn.patch
git apply --3way ../RHI/patches/installer-zh-cn.patch

dotnet restore RenoDXCommander/RenoDXCommander.csproj
dotnet build   RenoDXCommander/RenoDXCommander.csproj -c Release -p:Platform=x64 --no-restore
dotnet test    RenoDXCommander.Tests/RenoDXCommander.Tests.csproj -c Release -p:Platform=x64 --filter "FullyQualifiedName~Localization"
dotnet publish RenoDXCommander/RenoDXCommander.csproj -c Release -p:Platform=x64 -r win-x64 `
    --self-contained false -o artifacts/publish/RHI-win-x64-portable

# loose files (same as CI)
dotnet build RHI.DropHelper/RHI.DropHelper.csproj -c Release -p:Platform=x64
copy RHI.DropHelper\bin\x64\Release\net8.0-windows\RHI.DropHelper.* artifacts\publish\RHI-win-x64-portable\
copy RenoDXCommander\reshade.rdr2.ini artifacts\publish\RHI-win-x64-portable\
copy .github\patch\README-patch.md artifacts\publish\RHI-win-x64-portable\

# Chinese installer (Inno Setup 6)
& "C:\Program Files (x86)\Inno Setup 6\ISCC.exe" `
  "/DPublishDir=$PWD\artifacts\publish\RHI-win-x64-portable" `
  "/DInstallerOutputDir=$PWD" "RHI Setup.iss"
```

ClrMD 的 `Microsoft.Diagnostics.Runtime.dll` 不是 PackageReference（它会让 WinAppSDK XAML 编译器
在 publish 时崩溃）。补丁让 csproj 在该 DLL 存在时按路径复制；CI 会先从 NuGet 下载，
没有它也能构建，只是少了 freeze 诊断。

**不要用 `PublishSingleFile=true`**：WinAppSDK 的 WinRT 组件无法从 bundle 内激活，
启动即 `0x80040111`；安装器打包的是完整的便携目录。

## 汉化实现（都在补丁里）

- `LocalizationService.cs`：约 2200 行英→中词典 + 动态文案正则。运行时用 `VisualTreeHelper`
  遍历可视树，按英文原文匹配 TextBlock / Run / TextBox 占位符 / ComboBox Header /
  ToggleSwitch / ToolTip / MenuFlyoutItem。XAML 不需要逐条加 `x:Uid`。
- 动态更新控件用 `SetText/SetContent` 显式挂接，避免遍历缓存的旧原文。
- 语言选择在新增的 `SettingsHandler.Localization.cs`（独立 partial）。
- `installer-zh-cn.patch` 把 Inno Setup 的默认语言设为 `ChineseSimplified.isl`，并关闭语言选择页。
- 词条源自社区 PR [RankFTW/RHI#20](https://github.com/RankFTW/RHI/pull/20)（HexBen123），
  并补充了 2.8.x/2.9.x 新增文案。
- 技术名词保留原文：Unreal / Unity / Streamline / RenoDX / ReShade / DXVK / OptiScaler / Lilium HDR。

### 已知缺口

- 上游 2.9.x 新增的部分界面文案（游戏内覆盖层、成就等）尚未逐条翻译，会显示英文。
- 极少数运行时拼接的组合文案可能漏翻；补词条即可。

## 许可证

遵循上游 **GPL-3.0**。补丁、构建脚本与所有汉化修改都在本仓库公开；
每个 release tag 指向 `zh-cn-build` 上实际构建的源码提交。
