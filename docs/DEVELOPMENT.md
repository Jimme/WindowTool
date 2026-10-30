# 开发说明

源码目前只有三个主要文件，保留在根目录即可。无需为了目录形式而改动运行目录、相对 include 或配置路径。

- `WindowTool.ahk`：入口、窗口定位、编译元数据。
- `TrayManager.ahk`：单实例、托盘、隐藏窗口及恢复记录。
- `Hotkeys.ahk`：功能定义、快捷键注册、设置与录制器。
- `tests/Fixture.ahk`：专用测试窗口。
- `tests/SelfTest.ahk`：本地回归及测试辅助入口。

在项目根目录运行：

```powershell
.\scripts\test.ps1
.\scripts\build.ps1
.\scripts\test.ps1 -Compiled

# 最终源码提交后打包，需事先备齐已核对的解释器源码归档
.\scripts\package.ps1
```

工具位置不同时可指定参数：

```powershell
.\scripts\build.ps1 -AhkPath '<AutoHotkey64.exe 的绝对路径>' -CompilerPath '<Ahk2Exe.exe 的绝对路径>'
.\scripts\test.ps1 -Compiled -AhkPath '<AutoHotkey64.exe 的绝对路径>'
```

构建脚本检查 Ahk2Exe 元数据和运行时版本号一致，将编译产物与说明放入 `release/<版本>/`，不覆盖根目录旧 EXE，不替换其他安装位置。

测试脚本默认使用本机 AutoHotkey v2。编译版测试在 `build-check/<版本>/` 中进行，并通过进程级环境变量 `WINDOWTOOL_AHK` 指定测试窗口使用的运行时；执行后恢复该环境变量。运行测试需要交互式 Windows 桌面，请不要并发启动多个测试实例。

个人配置、隐藏窗口记录、日志及测试产物均由 `.gitignore` 排除。若隐藏窗口逻辑、快捷键注册逻辑或录制器发生变化，应执行对应回归。纯说明文字修改不要求重新运行全部 GUI 测试。

发布前还需核对许可证、第三方分发说明、版本号以及源码和二进制是否对应同一份最终代码。不要把模拟任务栏消息测试标成真实登录自启测试。

解释器源码和当前构建工具的对应关系见 [构建来源](BUILD-PROVENANCE.md)。

打包脚本不会下载依赖或上传文件。它要求 Git 工作区已提交、EXE 版本一致且对应解释器源码归档哈希正确，然后产生项目源码 ZIP、Windows ZIP 和 SHA256SUMS。重新构建后，应重新测试和打包；不能将旧 EXE 与新源码混合发布。
