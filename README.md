# Claude Desktop Splash — a startup animation for the Claude desktop app (Windows)

Plays a short animation over the Claude desktop window when you start it from a shortcut, then fades out to reveal Claude. No sound. Skip any time with Esc, Space, Enter or a click.

> **Language note:** the animation's text is **Chinese (简体中文)**. **Windows only**; it needs Microsoft Edge and the Claude desktop app. This is an unofficial personal project and is not affiliated with Anthropic.

## 截图 / Screenshots

动画中段：发光的线稿，边缘光带划过。

![outline](docs/splash-outline.jpg)

动画结尾：标题和欢迎语（“Claude 启动……”），之后淡出，露出 Claude。

![final](docs/splash-final.jpg)

## 这是什么

一个给 Claude 桌面应用加的开屏动画。你双击快捷方式，动画会盖在 Claude 的窗口上播放，同时在后台启动 Claude，播完后淡出，露出 Claude。

- 动画窗口会精确盖住 Claude 的窗口，并且跟着它移动、缩放。
- 没有声音。
- 播放中按 **Esc / 空格 / 回车**，或者**点击**，可以立即跳过。右下角有一个很淡的“跳过”提示。
- 如果动画页面 8 秒内没准备好，会自动放弃动画，只启动 Claude，不会卡住。

## 要求

- Windows 10 / 11（只在 Windows 11 上测试过）
- Microsoft Edge（Windows 自带，动画窗口用它来播放）
- Claude 桌面应用（Windows 版）

## 安装和使用

1. 下载或克隆这个仓库，放在一个固定的位置（不要之后再移动文件夹，快捷方式里记着路径）。
2. 在仓库文件夹里打开 PowerShell，运行下面这一行，生成快捷方式并放到桌面：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\launcher\make_shortcut.ps1 -LinkName "Claude 开屏启动" -Desktop
```

3. 以后用桌面上的“Claude 开屏启动”快捷方式来打开 Claude。

这个脚本会做三件事：
- 查出你电脑上 Claude 的应用 ID，存进 `launcher\config.json`；
- 从你已经安装的 Claude 里提取图标，存进 `launcher\claude.ico`（只在你自己的电脑上生成，不包含在仓库里）；
- 生成快捷方式（用 `conhost --headless` 启动 PowerShell，避免启动时闪一下黑色窗口）。

## 常用选项（调试用）

在 `launcher\launch.ps1` 上可以加这些参数：

| 参数 | 作用 |
|---|---|
| `-NoClaude` | 只播动画，不启动 Claude |
| `-NoSplash` | 只启动 Claude，不播动画 |
| `-Fullscreen` | 忽略 Claude 的窗口，盖住整个主屏幕 |
| `-ClaudeDelayMs N` | 动画出现 N 毫秒后再启动 Claude（默认 800） |
| `-FadeMs N` / `-FadeInMs N` | 淡出 / 淡入时长（默认 800 / 250 毫秒） |
| `-ReadyTimeoutSec N` | 页面多久没准备好就放弃动画（默认 8 秒） |

例如只预览动画：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\launcher\launch.ps1 -NoClaude
```

## 它是怎么工作的（简述）

- `splash.html` 是动画本身（Canvas 绘制的网页）。
- `launcher\launch.ps1` 用 Edge 的 `--app` 模式打开它，把窗口裁剪到刚好盖住 Claude 的窗口，并在后台启动 Claude；播完后淡出。
- 冷启动时，窗口位置取自 Claude 自己保存的 `window-state.json`，读不到时才退回到上次记住的位置或整个屏幕。
- 运行日志写在 `launcher\launcher.log`（不会上传到仓库）。

## 已知限制

- 只支持 Windows，且只在 Windows 11 上测试过。
- 依赖 Claude 桌面应用的窗口和配置文件位置；如果以后 Claude 改了这些，可能需要调整。
- 没有测试过多显示器和不同缩放比例的所有组合。

## 许可 / License

- **代码**：[MIT License](LICENSE)，Copyright (c) 2026 Firefade0329。
- **图片**（`assets\` 里内嵌的角色图）：由 AI 工具生成，**不在 MIT 协议的授权范围内**，版权和使用许可另行说明。如需在本项目之外使用这些图片，请先联系作者。

*Code is MIT-licensed. The character images embedded in `assets\` are AI-generated and are not covered by the MIT license; contact the author before reusing them elsewhere.*
