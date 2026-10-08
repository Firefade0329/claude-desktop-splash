# 参与贡献 / Contributing

*English summary: please open an issue for bugs and ideas. The project only runs on Windows; if you change `launcher/*.ps1`, say which Windows version you actually tested on. Documentation fixes are welcome as pull requests.*

这是一个个人维护的小项目，欢迎反馈问题和提出想法。

## 先说明一件事：这个项目只能在 Windows 上运行

它需要 Windows、Microsoft Edge 和已安装的 Claude 桌面应用，还会生成桌面快捷方式。因此改动的效果**只有在 Windows 上实际运行才能验证**。请在提交说明里如实写清楚你测试过什么、在哪个 Windows 版本上测的；没有运行验证的话请直接写"没有实际运行验证"，不要写"已测试通过"。

## 反馈问题

1. 先在 [Issues](../../issues) 里搜一下有没有人报告过；也可以先看 README 里的"故障排查"。
2. 新建 Issue，选 **Bug 反馈** 模板，请尽量填全：
   - Claude 桌面应用的版本；
   - Windows 的版本（按 Win+R，输入 `winver` 可以看到）；
   - 怎么复现（一步一步写）；
   - `launcher\launcher.log` 里出问题那一次运行的片段（从最近一行 `--- launcher start` 开始）。
3. **不要贴个人信息**：用户名、电脑名、本机路径、令牌。日志贴之前请自己检查一遍。

想法和建议请选 **功能建议** 模板。

## 提交改动

### 可以直接提 Pull Request 的

- `README.md` 的错字、过时说明、补充；
- `.gitignore` 的小修正。

写文档时请只写已经确认的事实；没验证过的内容请明确写"未验证"。

### 改 `launcher/*.ps1` 或 `splash.html` 时

- **请在 Windows 上实际运行过再提交**，并在 PR 里写明 Windows 版本、Edge 版本、你跑了哪些场景（正常播放、`-NoClaude`、`-NoSplash`、`-Fullscreen`、仓库路径带空格等）。
- 脚本在 **Windows PowerShell 5.1** 下运行：不要用 `&&`、`||`、`??`、三元运算符，也不要用 PowerShell 7 才有的语法。
- 脚本文件目前是纯 ASCII、没有 BOM，请保持编码不变。
- 不要随意改启动 Edge 的参数，尤其是 `--window-position=-32000,-32000` 和遮挡相关的开关（`--disable-features=CalculateNativeWinOcclusion` 等），它们是为了防止窗口被判定为被遮挡而暂停动画。
- 页面准备好之前窗口保持不可见；页面超时没准备好就放弃动画、只启动 Claude。这个兜底逻辑请保留。
- 想大改之前，请先开 Issue 说明。

### 不要改的

- `assets/claude-closed.js`、`assets/eyes-frames.js`：由维护者本机的素材生成的内嵌图片数据（base64），**不要手改，也不要重新生成**。
- `docs/` 里的截图：不要替换或新增，除非维护者明确要求。
- 版本号、标签、Release：由维护者确认后在本机完成。`CHANGELOG.md` 按版本记录，通常由维护者随发布更新，需要补充的话请在 Issue 或 PR 里说明。

### 不要提交的文件

这些文件由脚本在你本机生成，已经写在 `.gitignore` 里：`launcher/launcher.log`、`launcher/last_rect.json`、`launcher/config.json`、`launcher/claude.ico`、`launcher/edge-profile/`、`*.lnk`。

其中 `claude.ico` 是 Claude 应用的官方图标，属于商标素材，**绝对不要加入仓库**。

### 隐私和素材

- 提交、Issue、PR、截图里**不要出现**真实姓名、邮箱、本机路径（盘符、用户目录）、令牌、密码。
- 不要上传任何第三方的参考图或截图。README 的截图只能用本项目动画自己的画面，并且要去掉 EXIF 元数据。
- 动画里内嵌的角色图是 AI 生成的，不在 MIT 协议的范围内（见 [README](README.md#许可--license)）。

## 许可

提交的代码和文档按本仓库的 [MIT License](LICENSE) 授权。

## 说明

这是个人项目，没有固定的响应时间，也不保证采纳每一个建议。感谢你花时间反馈。
