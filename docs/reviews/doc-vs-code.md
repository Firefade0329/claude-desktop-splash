# 文档与代码核对：README.md、CHANGELOG.md 对照脚本和页面（v1.0.1）

> 范围：`README.md`、`CHANGELOG.md` 里每一个数字、参数、按键、功能描述，逐条对照 `launcher/launch.ps1`、`launcher/make_shortcut.ps1`、`splash.html`、`.gitignore`（我已合并最新 main，即 v1.0.1）。
> 只报告差异（写错、过时、遗漏），**没有改任何文档**。
> **所有结论都是"未运行验证"**：这个项目只能在 Windows 上运行，我只是读代码和文档对照。"一致"的意思是"文档和代码写的是一回事"，不是"实际表现正确"。
> 严重程度：**中** = 读文档的人会得出错误的使用结论；**低** = 不够精确或遗漏。

## 结论（先看这个）

- **差异 10 条：高 0 / 中 2 / 低 8。**
- 参数默认值（`-ClaudeDelayMs 800`、`-FadeMs 800`、`-FadeInMs 250`、`-ReadyTimeoutSec 8`）、跳过按键、`make_shortcut.ps1` 的参数、日志文件名、冷启动取窗口位置的顺序，都和代码一致（见 §3）。
- 两条值得优先改的：
  - **D-1（中）**：README 把"要求"写成"Claude 桌面应用（Windows 版）"，但代码只认 **Microsoft Store 版**的窗口和配置文件路径。
  - **D-2（中）**：README 说"页面 8 秒内没准备好就放弃动画、只启动 Claude"，实际这 8 秒是从 Edge 窗口出现后才开始算；窗口一直不出现时要等到 34 秒的硬超时，Claude 才由 v1.0.1 加的兜底启动。

## 1. 差异清单

### 中

#### D-1　只支持 Microsoft Store 版 Claude，README 没说（中）　【未运行验证；对照结论本身来自读代码】
- 文档：`README.md` 的"要求"（"Claude 桌面应用（Windows 版）"）和"已知限制"（"依赖 Claude 桌面应用的窗口和配置文件位置"）。
- 代码：`launcher/launch.ps1:117`（找 Claude 窗口时要求进程路径匹配 `*WindowsApps*Claude_*`）、`:108`（默认应用 ID 是 Store 版的 `Claude_pzs8sxrjxfjjc!Claude`）、`:156`（读 `Packages\<包名>\LocalCache\Roaming\Claude\window-state.json`，Store 版的路径）；`launcher/make_shortcut.ps1:70`（提取图标时同样按 `WindowsApps` 路径找）。
- 差异：非 Store 安装包安装的 Claude（路径不含 `WindowsApps`）会找不到窗口：动画不能跟随、读不到 Claude 自己保存的位置，播完后固定多等约 8 秒，最后也不会把 Claude 置前。（启动 Claude 用的是开始菜单里查到的应用 ID，可能仍然能启动；这一点我没验证。）
- 建议：README 的"要求"写成"Claude 桌面应用（Microsoft Store 版）"，"已知限制"补一句"非 Store 版的安装方式没有支持 / 未验证"。

#### D-2　"8 秒没准备好就放弃动画"的计时起点没写清（中）　【未运行验证】
- 文档：`README.md`（"如果动画页面 8 秒内没准备好，会自动放弃动画，只启动 Claude，不会卡住"）、`-ReadyTimeoutSec` 一行（"页面多久没准备好就放弃动画（默认 8 秒）"）。
- 代码：`launcher/launch.ps1:317`（超时判断要求 `$appearAt`，即 Edge 窗口已经出现；从窗口出现起算）、`:320`（`MaxSplashSec + 12` = 34 秒的硬超时）、`:347`（v1.0.1 新增的兜底：循环结束时 Claude 还没启动就补启动）。
- 差异：8 秒是"窗口出现之后"的等待。如果 Edge 窗口根本没出现（被策略拦截、卡在对话框等），要等 34 秒硬超时之后 Claude 才会启动（v1.0.1 之前则完全不启动，见 `launcher-static-review.md` 的 H-1）。CHANGELOG 1.0.1 写了"窗口一直不出现"已兜底，但没有写会等多久。
- 建议：README 的这一句改成"窗口出现后 8 秒内页面没准备好就放弃动画；如果动画窗口一直没出现，最长约 34 秒后才会启动 Claude"。同时在"常用选项"里加上 `-MaxSplashSec`（见 D-3）。

### 低

#### D-3　选项表漏了 `-MaxSplashSec`（低）　【未运行验证】
- 文档：`README.md` 的"常用选项"表；`launch.ps1` 顶部的注释块（`:16-24`）也没有它。
- 代码：`launch.ps1:35`（`[int]$MaxSplashSec = 22`）、`:315`（动画最长播放时间）、`:320`。
- 建议：表里补一行："`-MaxSplashSec N`：动画窗口最长保留 N 秒（默认 22 秒），到时强制结束"。

#### D-4　没装 Edge 时会改用 Chrome，README 没提（低）　【未运行验证】
- 文档：`README.md` 的"要求"（"Microsoft Edge（Windows 自带，动画窗口用它来播放）"）。
- 代码：`launcher/launch.ps1:205-211`（依次找两个 Edge 路径、两个 Chrome 路径；都没有就只启动 Claude 并返回）。
- 差异：只装了 Chrome 也能播；Edge 和 Chrome 都找不到时静默跳过动画、只启动 Claude。Edge 若是"只为当前用户安装"到别的目录，也找不到。
- 建议：README 补"找不到 Edge 时会尝试 Chrome（标准安装路径）；都没有则只启动 Claude，不播动画"。（只写了代码里的路径判断，Chrome 下的实际表现我没有验证。）

#### D-5　`make_shortcut.ps1` 同时在仓库根目录生成一份快捷方式（低）　【未运行验证】
- 文档：`README.md` 的"安装和使用"（"生成快捷方式并放到桌面"；"这个脚本会做三件事"）。
- 代码：`launcher/make_shortcut.ps1:87`（总是在仓库根目录生成）、`:88`（加 `-Desktop` 才再复制一份到桌面）。
- 差异：加 `-Desktop` 时，桌面和仓库根目录各有一个 `.lnk`；不加则只有仓库根目录那一个。`.lnk` 已在 `.gitignore` 里。
- 建议：改成"在仓库文件夹里生成快捷方式；加 `-Desktop` 时再复制一份到桌面"。

#### D-6　日志文件的清理规则没写（低）　【未运行验证】
- 文档：`README.md`（"运行日志写在 `launcher\launcher.log`（不会上传到仓库）"）。
- 代码：`launch.ps1:42`（超过 100 KB 就整个删除，下次重新写）。
- 建议：补半句"日志超过 100 KB 会被清空重写"。

#### D-7　没有说明动画大约多长（低）　【未运行验证】
- 文档：`README.md` 只说"一个短动画"。
- 代码：`splash.html:66`（`CFG.total: 9.3`，名义总时长 9.3 秒）、`:74` 附近（`T.end = 8.6` 秒时通知启动器开始淡出，见 `:548`）；启动器另有 `-MaxSplashSec 22` 的上限。
- 建议：写"约 9–10 秒（页面里的名义时长 9.3 秒，其中 8.6 秒处开始淡出）"。实际时长取决于机器，我没法测，**未验证**。

#### D-8　Windows 10 的说法需要更谨慎（低）　【未运行验证】
- 文档：`README.md`（"Windows 10 / 11（只在 Windows 11 上测试过）"）。
- 代码：`launch.ps1:81-84`（取消 DWM 系统背景、圆角、边框的几个属性是 Windows 11 才有的，Windows 10 上调用会失败，但返回值被忽略，不会报错）；`make_shortcut.ps1:81-82`（用 `conhost.exe --headless` 启动 PowerShell）。
- 差异：README 已经注明只在 Windows 11 测试过，这是准确的。但"Windows 10 可用"没有任何依据：Windows 10 上窗口边框是否能被完全去掉、`conhost --headless` 是否可用，我都不知道。
- 建议：把"Windows 10 / 11"改成"Windows 11（Windows 10 未验证）"。

#### D-9　欢迎语里的"博士"是写死的，没有说明（低）　【未运行验证】
- 文档：`README.md` 的截图说明（"标题和欢迎语（'Claude 启动……'），之后淡出"）。
- 代码：`splash.html:54`（`欢迎回来，<em>博士</em>` 写死在页面里，不读取系统用户名或任何设置）。
- 建议：README 补一句"欢迎语是固定文字，想改可以直接改 `splash.html`"；注意 CLAUDE.md 规定 `assets/` 里的两个数据文件不要手改，`splash.html` 不在此限。

#### D-10　`CLAUDE.md`（维护说明）的"不要提交的文件"没跟上 `.gitignore`（低）　【已确认（读文件）】
- 文档：`CLAUDE.md` 的"不要提交的文件"清单（`launcher.log`、`last_rect.json`、`config.json`、`claude.ico`、`*.lnk`）。
- 代码：`.gitignore` 在 v1.0.1 加了 `launcher/edge-profile/`。
- 说明：这条不在 README / CHANGELOG 范围内，顺带发现。
- 建议：CLAUDE.md 的清单补上 `launcher/edge-profile/`（约 100 MB 的 Edge 临时配置目录）。

## 2. CHANGELOG 逐条核对结果

| 条目 | 结果 |
|---|---|
| 1.0.1：传给 Edge 的配置目录参数加了引号 | 一致：`launch.ps1:220`（`'--user-data-dir="' + $prof + '"'`），注释写明了原因 |
| 1.0.1："实测在带空格的路径下能完整播放" | **未验证**：我没有 Windows，无法复现，这是维护者的测试结论 |
| 1.0.1：窗口启动失败时直接启动 Claude | 一致：`launch.ps1:230-231`（`Start-Process` 包在 `try/catch` 里，失败时 `Start-ClaudeApp` 后返回） |
| 1.0.1：循环结束时 Claude 还没启动，补启动一次 | 一致：`launch.ps1:347`（`finally` 里，在清理 Edge 之前）；该行为涵盖了"Edge 立刻退出""窗口一直不出现（等到硬超时）"和循环里抛错的情况 |
| 1.0.1：这两处兜底"没有在真实的启动 Claude 流程里验证" | 这句话是诚实的，我也没验证 |
| 1.0.1：清理 `make_shortcut.ps1` 里带盘符的注释 | 一致：`make_shortcut.ps1:87` 现在是 `# the folder that holds launcher\ (repository root)` |
| 1.0.1：`.gitignore` 增加 `launcher/edge-profile/` | 一致 |
| 1.0.1："由一次对启动脚本的独立静态审查发现" | 与 `launcher-static-review.md` 一致；审查里的其余条目（H-3 起）这个版本没有处理，CHANGELOG 没有说它们"已处理"，没有不实 |
| 1.0.0：Edge 应用窗口覆盖播放，同时启动 Claude，播完淡出 | 一致 |
| 1.0.0：Esc / 空格 / 回车 / 点击可跳过 | 一致：`splash.html:634-638`（启动器模式下这四种都会把标题设为 `DONE`）。键盘事件在真实桌面上能否送到页面（窗口不抢焦点）**未验证**，见 `launcher-static-review.md` 的 H-9 |
| 日期：1.0.0 为 2026-10-07、1.0.1 为 2026-10-08 | 与标签 `v1.0.0`、`v1.0.1` 的提交日期一致 |

## 3. README 逐项核对（一致的部分）

| README 的说法 | 代码 | 结果 |
|---|---|---|
| 动画 Canvas 绘制，运行时只依赖 `assets/` 里两个数据文件 | `splash.html` 只引入 `assets/claude-closed.js`、`assets/eyes-frames.js` | 一致 |
| 没有声音 | `splash.html` 里没有 `Audio` / `AudioContext` | 一致 |
| 播放中按 Esc / 空格 / 回车，或点击，立即跳过 | `splash.html:634-638` | 一致（见上，键盘部分未验证） |
| 右下角有一个很淡的"跳过"提示 | `splash.html:35`、`:57`、`:493`（启动器模式显示）、`:547`（淡入淡出） | 一致 |
| 动画窗口精确盖住 Claude 窗口，并跟着移动、缩放 | `launch.ps1:307-311`（每个循环重新取 Claude 窗口矩形，变了就重新放置） | 一致 |
| 窗口位置的顺序：Claude 窗口 → `window-state.json` → 上次记住的位置 → 整个屏幕 | `launch.ps1:176-202`、`:191` | 一致（`window-state.json` 路径限 Store 版，见 D-1） |
| `-NoClaude`、`-NoSplash`、`-Fullscreen` | `launch.ps1:17-19`、`:28-30` | 一致 |
| `-ClaudeDelayMs` 默认 800、`-FadeMs` 默认 800、`-FadeInMs` 默认 250、`-ReadyTimeoutSec` 默认 8 | `launch.ps1:31-34` | 一致 |
| `make_shortcut.ps1 -LinkName ... -Desktop` | `make_shortcut.ps1:8-11` 的参数名和用法 | 一致 |
| 脚本做的三件事：查应用 ID 存 `launcher\config.json`；提取图标存 `launcher\claude.ico`；生成快捷方式（`conhost --headless` 启动 PowerShell） | `make_shortcut.ps1:61-65`、`:68-76`、`:78-85` | 一致（快捷方式位置见 D-5） |
| `config.json`、`claude.ico` 只在本机生成、不进仓库 | `.gitignore` | 一致 |
| `launcher\launcher.log` 不上传 | `.gitignore` | 一致（清理规则见 D-6） |
| 不要移动文件夹，快捷方式里记着路径 | `make_shortcut.ps1:82`（参数里写的是 `launch.ps1` 的绝对路径） | 一致 |
| 只支持 Windows，只在 Windows 11 上测试；没有测试过多显示器和不同缩放的所有组合 | 与我的静态审查结论一致（见 `launcher-static-review.md` H-6） | 一致 |
| 页面用 `?launcher` 模式由启动器打开，状态通过窗口标题传递 | `launch.ps1:214`、`splash.html:110-115` | 一致 |
| 许可：代码 MIT，`assets/` 里的图 AI 生成不在 MIT 范围 | `LICENSE` 存在 | 一致 |
| 截图 `docs/splash-outline.jpg`、`docs/splash-final.jpg` | 文件存在；我没有对照画面内容（这个仓库的画面我没法运行） | 文件存在，内容**未验证** |
