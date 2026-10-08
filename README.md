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

## 故障排查

> 这一节的内容来自对脚本的阅读。**我没有在 Windows 上实际运行过，除非特别说明，下面的结论都是"未运行验证"。**

### 第一步：看日志

每次运行都会往 `launcher\launcher.log`（和 `launch.ps1` 在同一个文件夹）追加一行行带时间的记录，文件超过 100 KB 会被清空重写。常见的几行和它们的意思：

| 日志里的内容 | 意思 |
|---|---|
| `no Edge/Chrome found, starting Claude only` | 没找到 Edge 或 Chrome，跳过动画，只启动了 Claude |
| `could not start the splash window: ...` | 动画窗口启动失败；之后会直接启动 Claude |
| `splash process exited` | 动画窗口的进程提前退出了 |
| `splash window created (hidden until ready)` | 动画窗口已经出现，正在等页面准备好 |
| `splash placed at ... source=...` | 动画盖到了哪里；`source` 见下面"动画位置不对" |
| `splash shown (page ready after N s)` | 页面准备好了，动画开始播放 |
| `page not ready after 8 s, giving up on the splash` | 页面超时没准备好，放弃动画，启动 Claude |
| `hard timeout` | 动画窗口一直没出现，等到约 34 秒的硬超时 |
| `safety net: starting Claude after the splash ended without starting it` | 动画流程结束时 Claude 还没启动，补启动了一次（v1.0.1 起） |
| `Claude window not found at the end` | 播完后没有找到 Claude 的窗口（所以没有把它置前） |
| `profile cleanup incomplete: ...` | 动画用的临时 Edge 配置目录没删干净 |

反馈问题时，把出问题那一次运行的日志（从最近一行 `--- launcher start` 开始）贴出来会很有帮助。**贴之前请先检查一遍，不要带上个人信息**（用户名、电脑名、不想公开的路径）。

### 用 `-NoSplash` / `-NoClaude` / `-Fullscreen` 缩小范围

这是按代码逻辑推出来的排查思路（命令格式和上面"常用选项"一样，在仓库文件夹里运行）：

| 先试 | 如果结果是 | 说明问题大概在 |
|---|---|---|
| `... -File .\launcher\launch.ps1 -NoSplash` | Claude **打不开** | Claude 的应用 ID（`launcher\config.json`，日志里 `starting Claude (...)` 那行也会写出用的 ID）或 Claude 本身，和动画无关 |
| `... -File .\launcher\launch.ps1 -NoClaude -Fullscreen` | 动画**播不出来** | Edge / 页面 / 权限一类，看日志里是 `no Edge/Chrome found`、`could not start the splash window` 还是 `page not ready` |
| 同上 | 动画**能播** | Edge 和页面没问题，问题在"找 Claude 窗口、对齐位置"这一环，继续试下一行 |
| `... -File .\launcher\launch.ps1 -NoClaude`（先手动打开 Claude） | 动画能播但**位置不对** | 看日志里 `splash placed at` 那行的 `source` |

三个开关的含义：`-NoSplash` 只启动 Claude；`-NoClaude` 只播动画、不启动 Claude；`-Fullscreen` 忽略 Claude 的窗口，盖住整个主屏幕。

### 没装 Edge

启动器会依次找 Edge（两个标准安装位置），再找 Chrome（两个标准安装位置）。都找不到就跳过动画，只启动 Claude（日志里是 `no Edge/Chrome found`）。Edge 如果装在别的位置，同样会找不到。Chrome 下的实际表现我没有验证过。

### 杀毒软件或权限策略拦截（未验证）

我没有遇到过，也没法在没有 Windows 的环境里复现，所以不知道哪些软件或策略会拦。能从代码确认的只有"拦了之后会怎样"：

- 动画窗口出现了但页面一直没准备好：`-ReadyTimeoutSec`（默认 8 秒）后放弃动画，启动 Claude。
- 动画窗口根本没出现：最长约 34 秒的硬超时后，由 v1.0.1 加的兜底启动 Claude。
- 启动器的 PowerShell 部分（编译一小段 C# 去操作窗口）如果被策略拦住，动画无法播放；这种情况下 Claude 是否仍会被兜底启动，我没有验证。

如果你怀疑被拦：先用上面的 `-NoSplash` 确认 Claude 本身能启动，再看日志停在哪一行。

### 快捷方式失效

- **移动或删除了仓库文件夹**：快捷方式里记的是 `launch.ps1` 的完整路径（见"安装和使用"），文件夹挪走后就会失效。放回原位，或者在新位置重新运行一次 `make_shortcut.ps1`。
- **点了快捷方式只播动画、Claude 没起来**：重新运行 `make_shortcut.ps1`，它会重新查一遍 Claude 的应用 ID 并写进 `launcher\config.json`（运行时会打印 `aumid = ...`）。查不到时它会退回到一个内置的默认 ID，你可以和 `Get-StartApps | Where-Object Name -eq 'Claude'` 的结果对比。
- **快捷方式没有图标**：图标是从你已安装的 Claude 里提取的，脚本会先找正在运行的 Claude 进程。先打开 Claude，再运行一次 `make_shortcut.ps1`。提取失败时脚本会打印 `icon extraction failed`，快捷方式照样会生成。

### 动画位置不对

日志里 `splash placed at ... source=X` 的 `X` 表示这次用了哪个来源（按顺序）：

| `source` | 含义 |
|---|---|
| `claude` | Claude 的窗口已经出现，直接对齐它 |
| `claude-state` | 读的是 Claude 自己保存的 `window-state.json`（冷启动时） |
| `saved` | 读的是上次记住的位置 `launcher\last_rect.json` |
| `screen` | 前面都读不到，盖住整个主屏幕 |

如果总是 `screen`：说明启动器找不到 Claude 的窗口，也没有记住过位置。目前代码只识别 Microsoft Store 版 Claude 的窗口和配置文件路径，别的安装方式找不到，是预期之内的（别的安装方式我没有验证过）。如果位置记错了，可以删掉 `launcher\last_rect.json`，它会在下次运行时重新记。

### 多显示器和缩放

我没有测试过多显示器和不同缩放比例的组合（见"已知限制"）。能从代码确认的有两点：启动器是"系统 DPI 感知"，不是"每显示器感知"，Claude 在缩放比例和主屏不同的副屏上时，位置和大小有可能算错（只是推断，未验证）；`-Fullscreen` 只盖住**主**屏幕。如果你遇到错位，欢迎在 Issues 里反馈，请写上显示器数量、各自的缩放比例，以及日志里 `splash placed at` 那一行。

### 动画窗口没有消失

先点一下动画，或者按 Esc / 空格 / 回车（键盘按键在某些情况下可能收不到，我没有验证，点击更可靠）。仍然不消失时，可以在任务管理器里结束 Microsoft Edge 的进程——注意这也会关掉你自己正在用的 Edge 窗口。正常结束时，启动器会自动结束动画用的 Edge 并删除临时配置目录 `launcher\edge-profile\`（约 100 MB）；如果启动器被强行结束，这个目录可能残留，确认动画窗口已经关闭后可以手动删除（它是一次性的，运行时会重新创建）。

## 卸载

这个项目没有安装程序，也不会写注册表、启动项或计划任务（脚本里没有这类操作）。它只会在下面这些地方产生文件：仓库文件夹里，以及你用 `-Desktop` 生成的桌面快捷方式。动画使用独立的 Edge 临时配置目录，不会碰你自己的 Edge 配置。Claude 本身也没有被修改。

1. **删除快捷方式**
   - 仓库根目录里的 `.lnk`：每次运行 `make_shortcut.ps1` 都会生成；
   - 桌面上的 `.lnk`：只有用过 `-Desktop` 才有。名字是你当时 `-LinkName` 指定的（README 里的例子是 `Claude 开屏启动`，不指定则是 `Claude (splash)`）。桌面如果被 OneDrive 重定向，快捷方式在重定向后的桌面文件夹里。
   - 删掉快捷方式不影响 Claude；以后照常从开始菜单或你原来的快捷方式打开 Claude 即可。
2. **删除仓库文件夹**：先确认没有动画在播放（也没有残留的动画窗口），然后直接删除整个文件夹。上面列出的东西都在里面。
3. **（可选）只清理自动生成的文件，保留仓库**：在仓库文件夹里运行

   ```powershell
   Remove-Item -Recurse -Force .\launcher\edge-profile -ErrorAction SilentlyContinue
   Remove-Item .\launcher\config.json, .\launcher\claude.ico, .\launcher\last_rect.json, .\launcher\launcher.log -ErrorAction SilentlyContinue
   ```

   这几个文件都会在需要时重新生成：`config.json` 和 `claude.ico` 由 `make_shortcut.ps1` 生成，`last_rect.json` 和 `launcher.log` 由运行生成。删掉 `config.json` 后，`launch.ps1` 会退回到内置的默认应用 ID，所以如果你的 Claude 应用 ID 和默认值不同，需要重新运行 `make_shortcut.ps1`。

未验证：PowerShell 每次运行时现场编译 C# 代码，可能在系统临时目录里留下临时文件，我没有检查过；如果在意，可以用 Windows 的"磁盘清理"清掉临时文件。

## 许可 / License

- **代码**：[MIT License](LICENSE)，Copyright (c) 2026 Firefade0329。
- **图片**（`assets\` 里内嵌的角色图）：由 AI 工具生成，**不在 MIT 协议的授权范围内**，版权和使用许可另行说明。如需在本项目之外使用这些图片，请先联系作者。

*Code is MIT-licensed. The character images embedded in `assets\` are AI-generated and are not covered by the MIT license; contact the author before reusing them elsewhere.*
