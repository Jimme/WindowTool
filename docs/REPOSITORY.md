# GitHub 仓库整理建议

GitHub 没有强制要求所有项目使用同一种目录结构。这个项目先保持简单，源码和构建产物分开即可。

建议提交的目录结构：

```text
WindowTool/
├── .gitattributes
├── .gitignore
├── AGENTS.md
├── LICENSE
├── README.md
├── CHANGELOG.md
├── THIRD_PARTY.md
├── WindowTool.ahk
├── Hotkeys.ahk
├── TrayManager.ahk
├── docs/
├── scripts/
├── tests/                 # 仅测试源码
└── third-party/           # 第三方许可文本
```

不提交的本地内容：

| 内容 | 处理 |
| --- | --- |
| `backup-*` | 本地历史备份，Git 忽略；确认不再需要后清理 |
| `build-check/` | 本地验证产物，Git 忽略 |
| `release/` | 构建产物，Git 忽略；发布时上传需要的附件 |
| 根目录旧 EXE、`start_wt.bat` | 旧启动方式，不属于当前源码或发布包 |
| 个人 INI、hidden、log、临时文件 | Git 忽略；仍有隐藏窗口时不要清理恢复记录 |
| `tests/` 下的结果、日志、INI 等 | Git 忽略；保留 `.ahk` 测试源码 |

工作目录保留当前源码、项目文档、测试源码和 `release/<版本>/` 本地发布产物。历史产物不进入 Git 源码提交。

后续构建与测试会重新生成被忽略的产物；确认不再需要后可以清理。清理运行数据前，应退出程序、恢复全部窗口并核对恢复记录，不能直接删除非空的隐藏窗口记录。

发布检查：

- **项目许可证**：已选定 GPL-2.0-or-later 并添加 `LICENSE`；发布时保留项目和第三方许可。
- **第三方分发材料**：下载包保留第三方许可及对应 AutoHotkey 源码，项目源码和构建脚本由相同版本的标签提供。
- **仓库名称和可见性**：公开仓库为 Jimme/WindowTool，维护者署名 JimmeYoumu，发布标签与对应版本号一致。
- **一张真实界面截图**：有帮助但不是必须，截图前清空私人窗口标题。
- **首次提交审查**：确认文件清单，避免直接把整个文件夹通过网页拖上传。

可以稍后再做的内容：Issue 模板、贡献说明、自动构建。GUI 回归需要桌面，不应为了“有 CI”直接搬到未经验证的无桌面工作流。

参考：[GitHub README 指南](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/about-readmes)、[忽略文件](https://docs.github.com/en/get-started/git-basics/ignoring-files)、[Releases](https://docs.github.com/en/repositories/releasing-projects-on-github/about-releases)。
