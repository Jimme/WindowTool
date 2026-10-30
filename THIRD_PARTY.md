# 第三方组件

开发与当前构建使用 AutoHotkey **v2.0.26 x64** 和 Ahk2Exe，未在本次准备工作中升级。

- AutoHotkey 官方源码：[AutoHotkey/AutoHotkey](https://github.com/AutoHotkey/AutoHotkey)。
- 对应运行时版本：[v2.0.26](https://github.com/AutoHotkey/AutoHotkey/releases/tag/v2.0.26)。
- 编译工具：[AutoHotkey/Ahk2Exe](https://github.com/AutoHotkey/Ahk2Exe)。

`third-party/AutoHotkey-LICENSE.txt` 逐字保留本地已安装 AutoHotkey 发行包附带的许可文本，包含 GPL 和 PCRE 相关条款。编译版包含 AutoHotkey 运行时，不能只考虑项目脚本本身的许可。

WindowTool 自有源码采用 **GPL-2.0-or-later**，见根目录 [LICENSE](LICENSE)。AutoHotkey 及其第三方组件仍保留原有版权与许可声明，不因项目选择许可证而被覆盖。

Windows 下载包的 `sources/AutoHotkey-v2.0.26-source.zip` 附带对应解释器的官方源码，保留了上游许可、Visual Studio 构建项目和依赖源码。源码来源及哈希见 [构建来源](docs/BUILD-PROVENANCE.md)。未修改 AutoHotkey 的 C++ 运行时代码；WindowTool 的脚本作为资源嵌入。

WindowTool 源码和构建脚本在同一 GitHub Release 的 `v0.1.0` 标签及项目源码附件中提供。复现项目构建见 [开发说明](docs/DEVELOPMENT.md)；解释器自身的构建步骤以所附上游 README 和项目文件为准。
