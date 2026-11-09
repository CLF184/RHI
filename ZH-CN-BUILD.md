# RHI 简体中文版 · patch 自动构建与维护

本仓库是 [RankFTW/RHI](https://github.com/RankFTW/RHI) 的非官方简体中文分支。

默认分支 **不保存复制过来的上游源码**，只包含：

- `patches/zh-cn.patch`：全部汉化改动（约 4500 行 diff）
- `.github/workflows/zh-cn-sync.yml` + `.github/scripts/`：自动同步、构建、发布
- 说明文档与打包用的 `README-patch.md`

CI 每次检出一个上游 commit，在该 commit 的干净源码上 `git apply --3way patches/zh-cn.patch`，
再编译发布。这样仓库本身与上游的差异最小，也避免把上游历史复制进 fork。

## 下载

<https://github.com/CLF184/RHI/releases>

| 发布 | 对应内容 | 说明 |
| --- | --- | --- |
| `zhCN-RHI-<版本>` | 上游 release tag | 普通 release，带 `latest` 标记 |
| `zhCN-latest` | 上游 `main` 最新提交 | rolling 开发版，prerelease |

每个发布包含 `RHI-zhCN-<版本>-win-x64.zip` 和同名 `.sha256`。

- **全新安装**：整目录解压后运行 `RHI.exe`（不要只拷贝 exe）。
- **已装官方版**：退出 RHI，把解压出的全部文件覆盖进安装目录（默认 `C:\Program Files\RHI`），
  设置、游戏列表、已装模组全部保留。包内 `README-patch.md` 有步骤。
- **切换语言**：Settings → Language → 简体中文（默认跟随系统语言）。

> 为什么不能只替换 `RHI.exe`：WinAppSDK 的 WinRT 组件必须由 COM 从磁盘上的真实文件激活。
> 官方那个约 100 MB 的单文件 exe 重新打包后启动会报 `0x80040111 ClassFactory`。
> 因此只提供「整目录」产物。

## 应用内更新

`UpdateService` 已指向 `CLF184/RHI` 的 `/releases/latest`（不是上游官方仓库）：

- 检测到新中文版本时弹窗显示版本号，按钮「打开下载页面」打开本仓库的 release 页。
- 不会自动下载/运行安装器，也不会被官方英文安装包覆盖。
- 下载后退出 RHI、整目录覆盖即可。开发版 `zhCN-latest` 是 prerelease，不参与该检查。

## 自动化流程

`.github/workflows/zh-cn-sync.yml` 每 15 分钟轮询上游（fork 收不到上游的 push/release 事件）：

1. 读取 `RankFTW/RHI` 的最新 release tag 和 `main` HEAD。
2. 新 release → 在**该 tag 的精确 commit**上应用补丁，构建并发布 `zhCN-RHI-<tag>`。
3. `main` 有新 commit → 在该 commit 上应用补丁，构建并更新 `zhCN-latest`。
4. `git apply --3way` 冲突 → 中止，不推送源码、不发布；创建/更新带 `zh-cn-sync` 标签的 issue。
5. 构建成功后：
   - 把打好补丁的源码提交推到 `zh-cn-build` 分支（滚动分支，release tag 指向对应提交，满足 GPL 源码可得）；
   - 创建/更新 release 并上传 zip + sha256。
6. 只有源码与都构建成功才发布；构建失败不会留下半成品 release。

也可以在 Actions 页面手动运行（Run workflow），用 `upstream_ref` 指定某个 tag/SHA 补发历史版本；
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
```

### 修改翻译或解决冲突

在应用了补丁的 worktree 里编辑（通常只需要改
`RenoDXCommander/Services/LocalizationService.cs`，或在冲突文件里「保留上游新逻辑 + 补回汉化调用」），
然后**以冲突/目标的上游 commit 为基准**重新生成补丁：

```bash
cd ../build
git add -A
git commit -m "zhCN: resolve against <upstream-ref>"
git diff --no-color --full-index <upstream-sha> HEAD -- \
  RenoDXCommander RenoDXCommander.Tests > ../RHI/patches/zh-cn.patch
```

把新的 `patches/zh-cn.patch` 提交到 `zh-cn` 分支并推送，workflow 下次运行即可使用。
补丁基准会随这次重建变成新的上游 commit（更旧的 tag 不再保证能应用，通常也不需要）。

### 手工构建

```powershell
git worktree add --detach ../build <upstream-sha>
cd ../build
git apply --3way ../RHI/patches/zh-cn.patch

dotnet restore RenoDXCommander/RenoDXCommander.csproj
dotnet build   RenoDXCommander/RenoDXCommander.csproj -c Release -p:Platform=x64 --no-restore
dotnet test    RenoDXCommander.Tests/RenoDXCommander.Tests.csproj -c Release -p:Platform=x64 --filter "FullyQualifiedName~Localization"
dotnet publish RenoDXCommander/RenoDXCommander.csproj -c Release -p:Platform=x64 -r win-x64 `
    --self-contained false -o artifacts/publish/RHI-win-x64-portable
```

ClrMD 的 `Microsoft.Diagnostics.Runtime.dll` 不是 PackageReference（它会让 WinAppSDK XAML 编译器
在 publish 时崩溃）。补丁让 csproj 在该 DLL 存在时按路径复制；CI 会先从 NuGet 下载，
没有它也能构建，只是少了 freeze 诊断。

**不要用 `PublishSingleFile=true`**：WinAppSDK 的 WinRT 组件无法从 bundle 内激活，
启动即 `0x80040111`；只能发便携目录。

## 汉化实现（都在补丁里）

- `LocalizationService.cs`：约 2200 行英→中词典 + 动态文案正则。运行时用 `VisualTreeHelper`
  遍历可视树，按英文原文匹配 TextBlock / Run / TextBox 占位符 / ComboBox Header /
  ToggleSwitch / ToolTip / MenuFlyoutItem。XAML 不需要逐条加 `x:Uid`。
- 动态更新控件用 `SetText/SetContent` 显式挂接，避免遍历缓存的旧原文。
- 语言选择在新增的 `SettingsHandler.Localization.cs`（独立 partial）。
- 词条源自社区 PR [RankFTW/RHI#20](https://github.com/RankFTW/RHI/pull/20)（HexBen123），
  并补充了 2.8.x/2.9.x 新增文案。
- 技术名词保留原文：Unreal / Unity / Streamline / RenoDX / ReShade / DXVK / OptiScaler / Lilium HDR。

### 已知缺口

- 上游 2.9.x 新增的部分界面文案（游戏内覆盖层、成就等）尚未逐条翻译，会显示英文。
- Inno Setup 安装器未汉化（本项目只发便携 zip）。
- 极少数运行时拼接的组合文案可能漏翻；补词条即可。

## 许可证

遵循上游 **GPL-3.0**。补丁、构建脚本与所有汉化修改都在本仓库公开；
每个 release tag 指向 `zh-cn-build` 上实际构建的源码提交。
