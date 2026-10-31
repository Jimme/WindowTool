# 构建来源与对应源码

当前版本：0.1.3-alpha.2，Windows x64。未修改 AutoHotkey C++ 解释器源码，项目脚本由 Ahk2Exe 嵌入官方运行时。

| 组件 | 使用版本 |
| --- | --- |
| AutoHotkey | 2.0.26 x64 |
| Ahk2Exe | 1.1.37.02a2 |

核对结果：本机编译基底 `AutoHotkey64.exe` 与官方 2.0.26 发行 ZIP 中的同名文件 SHA-256 一致。

```text
AutoHotkey64.exe
A2A54B8ABC476D7671D4DE0771BB54BF5F2373D79FF6871D0BA6A62C3B88AE00

AutoHotkey_2.0.26.zip（官方二进制发行包，供核对）
43522AA3122A57784AC5DB30ABF85C2244475C36ACD7796E2C993355F9E926AE

AutoHotkey-v2.0.26-source.zip（随下载包提供）
765ADA5AE0A543F470BCD30371A7B95438E59351B0A20508C516DF76A4F73CA4

Ahk2Exe.exe（实际使用的编译工具）
E54A599B19BAA5C1688849BBAE7A9CF049EEFCCD4F704C67941B40DA13A625B2
```

来源：

- [AutoHotkey v2.0.26 官方发行](https://github.com/AutoHotkey/AutoHotkey/releases/tag/v2.0.26)
- [对应源码归档](https://codeload.github.com/AutoHotkey/AutoHotkey/zip/refs/tags/v2.0.26)
- [Ahk2Exe 官方项目](https://github.com/AutoHotkey/Ahk2Exe)

AutoHotkey 源码归档含上游许可、`AutoHotkeyx.sln`、Visual Studio 项目及依赖源码。解释器自身的构建步骤请查看归档中的 README；项目脚本的编译与测试步骤见 [开发说明](DEVELOPMENT.md)。

正式下载包包含 `sources/AutoHotkey-v2.0.26-source.zip`。相同 Release 提供 WindowTool 项目源码 ZIP，包含 `.ahk` 源码、测试和 PowerShell 构建脚本。发布包内的 `RELEASE-MANIFEST.txt` 记录对应项目提交及最终 EXE 校验值。

上述记录说明来源与对应关系，不代表已经在本机从 C++ 源码重新构建 AutoHotkey 解释器。
