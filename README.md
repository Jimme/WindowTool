# WindowTool · 窗口小助手

一个基于 AutoHotkey v2 的 Windows 窗口工具：用快捷键定位窗口、将当前窗口收起到托盘管理，并随时恢复。

当前开发版本：**0.1.3-alpha.2**。

## 功能

- 窗口居中，或在当前显示器工作区按上／中／下、左／中／右循环定位。
- 隐藏当前窗口，普通窗口不再显示于 Alt+Tab 和任务栏窗口按钮中，进程继续运行。
- 从管理界面恢复最近或全部窗口。
- 十项操作的快捷键均可录制、自定义或停用，支持 Tab、CapsLock 和 Win。
- 托盘图标缺失检测与恢复；再次启动可唤起已有实例。
- 通过托盘设置当前用户登录后以管理员身份自启动。
- 隐藏前写入恢复记录，正常退出恢复窗口，异常退出后尝试恢复。

## 默认快捷键

| 功能 | 默认快捷键 |
| --- | --- |
| 收起当前窗口 | Ctrl+Shift+CapsLock |
| 恢复最近窗口 | Ctrl+Alt+CapsLock |
| 打开管理界面 | Win+F9 |
| 窗口居中 | Win+F12 |
| 上／中／下循环 | Win+F11 |
| 左／中／右循环 | Win+F10 |

恢复全部、打开设置、修复托盘和退出默认不占用快捷键，可在设置中启用。组合键冲突检查有边界，特别是辅助功能或其他键盘钩子；详见[使用说明](docs/USAGE.md)。

## 开始使用

从 [GitHub Releases](https://github.com/Jimme/WindowTool/releases) 下载 Windows x64 压缩包，解压到当前用户可写的文件夹，运行 `WindowTool.exe`。编译版无需另装 AutoHotkey。二进制文件作为 Release 附件分发，不作为源码提交。

也可安装 AutoHotkey v2 后运行仓库根目录的 `WindowTool.ahk`。当前验证环境为 Windows、AutoHotkey **2.0.26 x64**；未完整验证其他系统及运行时版本。

操作以管理员权限运行的程序时，WindowTool 也需以管理员权限运行。修改键位：托盘右键菜单 → 设置 → 快捷键 → 录制 → 应用。

管理员自启：从长期安装目录运行 EXE → 托盘右键“设置…” → 常规 → 勾选管理员登录启动 → 应用。首次设置需要管理员权限，之后在当前用户登录后延迟 10 秒启动。移动安装目录后需重新启用；详细迁移规则见[使用说明](docs/USAGE.md#管理员自启动)。

更新前通过旧版托盘正常退出并恢复窗口，再替换 EXE；保留安装目录内的配置与恢复记录。不要同时运行两个版本。隐藏的是当前窗口，不保证所有特殊程序、附属窗口或自行重新显示的窗口都能按同一方式工作。

## 配置与记录

程序在自身目录生成 `WindowTool.ini`、`WindowTool.hidden` 和 `WindowTool.log`。这些是本机数据，不应提交到 Git。

异常退出后不要直接删除恢复记录；先以同一用户、足够权限从原安装目录启动并恢复窗口。托盘不可见时可用管理快捷键或再次启动程序打开管理界面。

## 开发与验证

依赖：AutoHotkey v2、Ahk2Exe、PowerShell。脚本使用默认安装目录，也支持通过参数指定工具路径。

```powershell
# 源码回归测试
.\scripts\test.ps1

# 编译到 release/<版本>/WindowTool.exe
.\scripts\build.ps1

# 在独立 build-check 目录验证编译后的 EXE
.\scripts\test.ps1 -Compiled
```

测试会创建专用 GUI 窗口，需要可交互的 Windows 桌面，不适合直接当作无桌面环境的 CI 检查。脚本不会自动下载或升级依赖，也不会发布到 GitHub。

详细内容：[使用说明](docs/USAGE.md) · [开发说明](docs/DEVELOPMENT.md) · [目录与发布准备](docs/REPOSITORY.md) · [版本规则](docs/RELEASE-POLICY.md) · [更新记录](CHANGELOG.md)。

## 已知验证边界

0.1.2 源码及编译版各通过 68 项本地回归；另验证计划任务提权运行、自启启用与关闭、旧快捷方式迁移及新建／更新失败回滚。维护者已反馈 0.1.1 实机登录自启正常，0.1.2 尚待实机登录确认。真实 Explorer 崩溃、普通权限启动唤起管理员实例及各种特殊窗口仍需进一步验证，详见使用说明。

## 许可证与反馈

Copyright (C) 2026 JimmeYoumu。

WindowTool 采用 **GNU General Public License v2.0 or later（GPL-2.0-or-later）**：你可以依据 GPL 第 2 版，或自行选择的任何更新版本，使用、复制、修改及分发本项目。项目按原样提供，不附带适销性或特定用途适用性等担保。完整条款见 [LICENSE](LICENSE)。

第三方组件保留各自的版权和许可，见 [THIRD_PARTY.md](THIRD_PARTY.md)。发布包附带对应 AutoHotkey 运行时源码；项目源码及构建脚本由本仓库的对应版本标签提供。核对记录见 [构建来源](docs/BUILD-PROVENANCE.md)。

报告问题时，请附上版本、Windows 版本、是否管理员运行、复现步骤和错误信息。提交截图或日志前，请检查并去除私人窗口标题、文件路径及其他个人信息。
