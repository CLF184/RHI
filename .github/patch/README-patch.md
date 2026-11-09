# RHI 简体中文版 · 使用说明

## 推荐：运行 Setup.exe

下载 `RHI-zhCN-<版本>-Setup.exe`，退出 RHI 后运行。安装器是简体中文界面，沿用官方 AppId，
可以直接覆盖已安装的官方版；设置、已装模组和游戏列表全部保留。

## 便携版：解压运行

解压到任意目录（路径不要有中文或空格），运行 `RHI.exe` 即可。
**请整目录解压，不要只拷贝 exe。**

## 已经装了官方版，用便携包覆盖

1. **完全退出 RHI**（包括系统托盘图标，托盘里右键 → Quit）。
2. 打开 RHI 的安装目录，默认是 `C:\Program Files\RHI`。
   找不到就在桌面/开始菜单的 RHI 快捷方式上右键 → **打开文件所在的位置**。
3. 把解压出来的全部文件选中，复制进该目录，**全部覆盖**
   （需要管理员权限，弹窗点「继续」）。
4. 启动 RHI → **Settings → Language → 简体中文**，界面立刻切换。
   偏好记在 `%LOCALAPPDATA%\RHI\settings.json`，下次启动自动保持。

> 只想换回英文的话，在 Language 里选 English 即可，不用换文件。

### 回滚

之前若备份过安装目录，把备份放回去即可；否则重新下载官方安装包覆盖回来。

## 为什么必须整目录覆盖

WinAppSDK（WinUI 3 的运行时）的组件是**通过 COM 从磁盘上的真实文件激活**的。
它们被打包进单个 exe 之后，COM 就找不到类工厂，程序一启动就崩：

```
COMException (0x80040111): ClassFactory 无法供应请求的类
   at Microsoft.UI.Xaml.Application.Start(...)
```

官方版那个约 100MB 的 `RHI.exe` 是把 `RHI.dll` 和 `resources.pri` 打包进 exe 的单文件发布，
看起来“换一个 exe 就行”——但照同样方式重新打包出来的 exe 无法启动（实测如此）。
**散在目录里的 WinAppSDK 文件缺一不可**，所以只能整目录覆盖。

## 更新

本分支的「检查更新」指向 <https://github.com/CLF184/RHI/releases>，不会被官方英文版覆盖。
检测到新版本时会打开下载页面；应用不会自动替换正在运行的文件。更新步骤：

1. 在提示框点「打开下载页面」，或直接到 <https://github.com/CLF184/RHI/releases>
   下载最新的 `zhCN-RHI-<版本>`。
2. 运行 `RHI-zhCN-<版本>-Setup.exe`；或退出 RHI 后用便携包整目录覆盖。

## 注意事项

- 本版本为 **framework-dependent**，需要系统装有 **.NET 8 桌面运行时**
  （官方版同样是框架依赖，能跑官方版就能跑这个）。
- 上游 2.9.x 新增的部分界面文案、安装器尚未汉化，可能显示英文。

## 许可证

源码在 <https://github.com/CLF184/RHI>，遵循上游 **GPL-3.0**，源码与修改全部开放。
