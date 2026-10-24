# 第四轮复查：开屏动画 v1.1.2

- 日期：2026-10-24　版本：v1.1.2（标签 `v1.1.2`，`main` 提交 `9d5334a`，已合并进 `claude/review-reports`）
- **整份报告都是"读代码 / 推断"，没有任何一条是实际运行的**：这个项目只能在 Windows 上跑，云端是 Linux。
- 范围：`launcher/launch.ps1`（v1.1.1 → v1.1.2 的全部改动）、`launcher/make_shortcut.ps1`、`splash.html` 的一行改动、README / CHANGELOG / SECURITY / CONTRIBUTING 与代码的核对、`last_rect.json` 的时间戳问题（你的第 5 点）。
- 没有改任何脚本。

## 结论

- 你让我重点读的"Claude 已在运行 / 关到托盘"这条新路径，我读下来**逻辑是通的**，没有发现会让 Claude 起不来的问题；每一支都有日志。
- 但有一个**我无法排除的风险（S4-1，中，可能性未知）**：判断"关到托盘"用的是"还有没有 Claude 包的进程"。如果 Claude 彻底退出后仍有该包的后台进程残留，动画就**永远不会播**，而且没有任何提示。需要你在 Windows 上用一条命令查（W16）。
- `last_rect.json` 的 14 天期限（你的第 5 点）：时间戳在未来时**会被当作新鲜的**（S4-4），日志里会出现负数的"几天前"。
- 另外：**14 天期限对"位置过时"本身帮助有限**（S4-5）——这个文件写的是"启动后头几秒的位置"，不是"关闭时的位置"，过时的原因通常是你之后又移动 / 缩放了窗口，而不是隔了很多天。真正解决这类问题的是 1.1.1 的 `window-state.json`，1.1.2 的期限只是兜底的兜底。
- 文档：上一轮指出的 DC-1…DC-4 都已修好（我逐项核对了）。新发现两处小的文档问题（DC-6、DC-7）。
- 隐私重扫：两个仓库的全部历史、所有分支和标签，没有真实姓名、邮箱、本机路径、令牌（见 §6）。

| 编号 | 严重程度 | 标注 | 一句话 |
|---|---|---|---|
| S4-1 | 中（可能性未知） | 推断 | 只要还有 Claude 包的进程，就不播动画；残留进程会让动画静默失效 |
| S4-2 | 低 | 读代码 | 托盘分支 8 秒内没等到窗口，只写日志，用户什么也看不到 |
| S4-3 | 低 | 读代码 | 等待之后的 `SetForegroundWindow` 可能被系统拒绝，返回值没看、没记日志 |
| S4-4 | 低 | 读代码 | `last_rect.json` 修改时间在未来 → 年龄为负 → 被信任 |
| S4-5 | 低 | 读代码 + 推断 | 记住的位置是"启动后几秒"的，过时主要不是因为天数 |
| S4-6 | 低 | 读代码 | 文件不存在时日志写成 `last_rect: not looked at`，不准确 |
| S4-7 | 低 | 读代码 | 没有真实窗口时，每个 30 毫秒循环都读一次文件（`Get-Item` + `Get-Content`） |
| S4-8 | 提示 | 读代码 | "Claude 常驻托盘 / 开机自启"的用户几乎看不到动画（设计取舍，README 已写） |
| DC-6 | 低 | 读代码 | README:116 "连点两次只启动 Claude"现在多数时候走的是另一条路径 |
| DC-7 | 低 | 读代码 | README:23 仍说按键可以跳过，CHANGELOG 1.1.2 说按键多半送给了 Claude |

## 1. 新增的"Claude 已在运行"分支（你的第 4 点）

位置：`launcher/launch.ps1:151-181`。

### 1.1 读代码：它做了什么

在互斥体之前（`:151` 起），除了 `-NoClaude`、`-Fullscreen` 和两个测试用环境变量之外：

1. `Get-ClaudeWindow`（`:158` 起）找 Claude 的主窗口：可见（含最小化）→ 日志 `Claude is already running: ...`，最小化则还原（`ShowWindow(…, 9)`），然后 `SetForegroundWindow`，结束。
2. 没有窗口，但有 Claude 包的进程（`Get-Process -Name claude` 且 `Path -like '*WindowsApps*Claude_*'`，`:166`）→ 日志 `Claude is running in the background (N processes, no window)…`，再次 `Start-ClaudeApp`（`explorer.exe shell:AppsFolder\…`），最多等 8 秒找窗口，找到就置前。
3. 两样都没有 → 走原来的流程（互斥体 → 动画）。

### 1.2 我对各种情形的推演（全部是读代码，没有一条跑过）

| 情形 | 会发生什么 | 判断 |
|---|---|---|
| Claude 窗口开着 | 置前，不播动画 | 正常 |
| Claude 窗口最小化 | `Get-ClaudeWindow` 能找到（最小化窗口 `MainWindowHandle` 非零、`IsWindowVisible` 为真），还原并置前 | 正常（推断：最小化窗口仍带 `WS_VISIBLE`） |
| 关到托盘（有进程、无窗口） | 走第 2 支。你说桌面端有约 10 个进程、只有 1 个有主窗口，托盘状态下没有窗口——和 `Process.MainWindowHandle` 只认可见窗口的行为一致 | 读代码合理；**真托盘没人测过** |
| 在另一个虚拟桌面上 | `IsWindowVisible` 对其他桌面的窗口仍为真，置前会切桌面 | 推断 |
| Claude 正在冷启动，窗口还没出来（别处启动的，或连点第二下） | 有进程、无窗口 → 走托盘分支：再激活一次（无害）、等窗口、置前，不播动画。第一个启动器的动画不受影响（不杀进程、不碰互斥体） | 合理；但这意味着 v1.1.0 的"第二个只启动 Claude"（README:116）多数时候不再走那条路径（DC-6） |
| 连点第二下发生在 Claude 启动之前（前 ~0.8 秒） | 没有进程 → 走互斥体 → `another splash launcher is already running: starting Claude only` | 和 1.1.0 一致 |
| Claude 彻底退出，但包的后台进程仍在 | 被当作"在托盘"：`Start-ClaudeApp` 冷启动 Claude，但**不播动画** | **S4-1** |
| 32 位 PowerShell 读不到 64 位进程的 `Path` | `Path` 为空 → 所有 `-like` 都假 → 窗口和进程都"找不到" → 走动画流程 | 这是 v1.1.2 之前就有的假设（快捷方式调用的是系统自带的 64 位 `powershell.exe`），不是新问题；只提示 |

### S4-1（中，可能性未知）进程残留会让动画静默失效

- **位置**：`launcher/launch.ps1:166-167`
- **场景**：用户在托盘右键"退出"后，Claude 包里仍有进程没退干净（崩溃后的收尾进程、后台服务、更新器等）；或 Claude 自己的"关闭"行为是"退出主进程但留下子进程"。此时 `$alive > 0`，启动器当作"在托盘"，激活并等窗口，**不播动画**。用户看到的是 Claude 正常打开，但永远没有动画；日志里是 `Claude is running in the background (N processes, no window)`，如果不知道这行的含义，很难想到是它。
- **标注**：推断。我无法判断 Claude 退出后进程是否会残留。
- **验证办法（需要你）**：见 W16。
- **建议（如果 W16 发现会残留）**：
  1. 退一步用"主进程"判断：只数命令行不含 `--type=`（Electron 的子进程都带这个参数）的 `claude.exe`。读命令行需要 WMI（脚本里已经为 Edge 用过 `Get-CimInstance`）。
  2. 或者在日志里把进程数和有无窗口写得更显眼（现在只有 `N processes`），并在 README 的"故障排查"里加一条："动画不播且日志是 `running in the background` → 在任务管理器里看是否还有 Claude 进程"。

### S4-2（低）托盘分支等不到窗口时，用户什么也看不到

- **位置**：`launcher/launch.ps1:176`（`Claude showed no window within 8 s`）
- **场景**：关到托盘后，再次激活 Claude，它的单实例处理没有把窗口显示出来（Electron 应用是否响应"第二次启动"并显示窗口，取决于应用自己的实现；你实测过"窗口开着"，但这一支没有在真托盘上测过）。启动器等 8 秒后只写日志就退出，用户点了快捷方式但什么也没发生。
- **建议**：这是个体验问题，不是正确性问题。可以接受；如果想加兜底，8 秒后再调用一次 `Show-ClaudeFront` 前先 `Start-ClaudeApp` 一次，或者至少把这条日志写进 README 故障排查（README:108 已经有了）。

### S4-3（低）置前可能被系统拒绝

- **位置**：`launcher/launch.ps1:154-157`（`Show-ClaudeFront`）
- **场景**：托盘分支可能已经等了好几秒，启动器进程早就过了"前台权限"窗口期，`SetForegroundWindow` 会失败，Windows 的表现是任务栏图标闪烁而不是窗口到前面。Electron 在被激活时通常自己会把窗口带到前面，所以多半不是问题。返回值没有检查，也没有日志。
- **建议**：把返回值记进日志（`Log ('foreground: ' + $ok)`），这样将来遇到"窗口出来了但没到前面"时有据可查。

## 2. `last_rect.json` 的 14 天期限（你的第 5 点）

### S4-4（低）时间戳在未来会怎样

- **位置**：`launcher/launch.ps1:292-294`
  ```
  $ageDays = ((Get-Date) - (Get-Item -LiteralPath $rectFile).LastWriteTime).TotalDays
  if ($ageDays -gt $SavedMaxDays) { … throw … }
  ```
- **读代码的结论**：修改时间晚于现在（电脑时钟被调回、曾经设错过日期后改回来、从别的电脑拷来的文件）时 `$ageDays` 是**负数**，`-gt 14` 为假，所以**被当作新鲜的，照常使用**；日志里会写 `written -30.0 days ago` 这种负数。时钟曾经被设到几年后、又改回来的话，这个文件要等到真实时间追上它才会过期。
- **影响**：只在 `window-state.json` 读不到、也没有真实窗口时才用到这个文件；所以要同时满足这几条才会出事，实际很少见。
- **建议**：`if ($ageDays -lt -1 -or $ageDays -gt $SavedMaxDays)`（容忍一点点时钟误差，未来的当过期处理，日志里写"in the future"）。同样的道理，`Get-ClaudeStateRect` 在两个 `window-state.json` 之间选"最近写过的"，如果其中一个修改时间在未来，它会一直赢；这条更少见，顺手一起改即可。
- **验证办法**：读代码即可确定；真要在 Windows 上试，需要同时让 `window-state.json` 读不到，我不建议为这个去动 Claude 自己的文件。

### S4-5（低）文件里的位置是"启动后几秒"的，过时主要不是因为天数

- **位置**：`launcher/launch.ps1:201-206`（`Save-Rect`）、`:285`
- **读代码**：`Save-Rect` 在启动器能看到真实 Claude 窗口时每秒写一次，启动器大约在 Claude 窗口出现后几秒结束，写就停了。所以 `last_rect.json` 记的是**启动后几秒时窗口的位置**，之后你拖动 / 缩放 / 最大化，它都不知道。
- **后果**：天天用快捷方式启动的人，这个文件永远是"昨天启动后几秒"的新鲜文件，14 天期限根本不起作用；真正会让它过时的，是"启动后又改了窗口"。期限只对"很久没用启动器"的人有意义。
- **含义**：1.1.2 的期限是合理的小改进，但**不要指望它解决"动画盖错位置"**。真正的解决在 1.1.1 的 `window-state.json`（Claude 自己每次移动都会写）；`last_rect.json` 只是它读不到时的备份。你之前说的"窗口出现时比上次大"那次，如果当时 `window-state.json` 读不到，就会落到这个文件；1.1.2 新增的 `window-state: …; last_rect: …` 日志行（`:394`）会在下一次出现时说明走的是哪条路。
- 顺便：`Save-Rect` 会把 Claude 窗口出现时的**瞬时大小**（比如你遇到过的那种"先开大一点再缩回"）也存下来，一秒后被新的值覆盖，一般无害。

### S4-6（低）日志措辞

- **位置**：`launcher/launch.ps1:292-294`、`:394`
- 文件不存在时 `Get-Item` 先抛异常，`savedWhy` 还是空的，日志写 `last_rect: not looked at`，其实是"文件不存在"。把 `catch` 里补一句 `if (-not $script:savedWhy) { $script:savedWhy = 'no file or unreadable' }` 即可。

### S4-7（低）没有真实窗口时每个循环读一次文件

- **位置**：`launcher/launch.ps1:292-295`
- `Get-ClaudeStateRect` 有 1 秒缓存，但这段没有；窗口还没出现的那几秒里，主循环每 30 毫秒就 `Get-Item` + `Get-Content` + `ConvertFrom-Json` 一次。1.1.1 以前就是这样（只有 `Get-Content`），现在多了 `Get-Item`。没有量过，可能不明显，但同样的 1 秒缓存放在这里更稳。

## 3. v1.1.2 的其余改动

| 改动 | 读代码结论 |
|---|---|
| 互斥体创建失败也继续运行（`:183-194`） | 外层 `try` 包住创建，失败时 `$hasMutex = $true`、`$script:mutex = $null`；`finally` 里 `try { $script:mutex.ReleaseMutex() } catch {}`（`:484`）把 `$null` 上的调用异常吞掉，所以不会崩。`AbandonedMutexException` 的处理保留 |
| 仅在发现残留目录时才清进程（`:321-326`） | 先 `Get-ChildItem`，非空才 `Stop-ProcessesUsing` + 等 300 毫秒 + 删除。**一个新的细节**：上一次若只残留了进程而没有残留目录（极少见），不会被清到。可接受 |
| 淡出结束后立刻 `ShowWindow($h, 0)`（`:456`） | 合理，避免透明窗口拦截点击；`$h` 为空时 `try/catch` 吞掉 |
| `Probe-ClaudeAppear` / `Note-ClaudeRect`（`:258-275`） | 只在 `source = 'claude'` 时记；第一次 `appeared`，之后变化至多每秒一行。`Probe` 在 `claudeStarted` 之后每个循环调用，窗口缓存有效时只是一次 `IsWindow`，窗口没出现时每 400 毫秒才真正查一次进程，代价不大 |
| 找不到 Claude 窗口时补查进程（`:473-475`） | 日志里加了应用 ID，并在零进程时明说"它没启动"。读代码合理 |
| `make_shortcut.ps1`：选中的不是 Store 版时警告（`:68`） | 正好补上上一轮的 R-7 |
| `splash.html`："跳过 Esc" → "点击跳过" | 与 CHANGELOG 的解释一致；`#skip b` 的 CSS 留着无害 |

## 4. 文档与代码（v1.1.2）

### 上一轮差异的状态

| 编号 | 状态 |
|---|---|
| DC-1 `found` 记录时机 | 已修：README:103-105 和 CHANGELOG 1.1.2 都改了，并且明说 v1.1.1 写错了 |
| DC-2 脚本头注释 | 已修：`launch.ps1:11-17` 补上 `window-state.json` 一级和"Claude 已在运行"的说明 |
| DC-3 `SECURITY.md` 新路径 | 已修：`SECURITY.md:32` 写了两个位置、"只读不写" |
| DC-4 启动时也会结束进程、目录名 | 已修：`SECURITY.md:40`、`:49`；`CONTRIBUTING.md:49` 写成 `edge-profile*/` |
| DC-5 "约 13 秒" | README:25 现在写明了量法（"13–14 秒，启动到结束的时间差，其中动画约 9.3 秒…"），仍是你的实测值，我**无法核实** |

### DC-6（低）连点两次的说明已经不完全对

- **位置**：`README.md:116`："已经有一个启动器在运行（比如连点了两次快捷方式），这一个只启动 Claude"
- **代码**：第二次点击时，只要第一个已经启动了 Claude（约 0.8 秒后），第二个会先走 `:166` 的"后台运行"分支，日志是 `Claude is running in the background (N processes, no window)`，而不是 `another splash launcher is already running`。后者现在只在第一次启动后的前 ~0.8 秒内出现。
- **建议**：README:116 加半句"（Claude 已经起来之后再点，日志会是 `Claude is running in the background …`，见上面两行）"。

### DC-7（低）按键能不能跳过

- **位置**：`README.md:23`："播放中按 **Esc / 空格 / 回车**，或者**点击**，可以立即跳过"；`CHANGELOG.md` 1.1.2："启动器不让动画窗口获得焦点，按键多半送给了 Claude，只有点击是可靠的"；`README.md:176` 对按键写了"可能收不到，我没有验证"。
- README:23 应该和 :176、CHANGELOG 一样加上"按键可能收不到（未验证）"，否则同一份 README 里两处说法不一。
- 这也是 H-9 的延伸：现在提示文字已改成"点击跳过"，文档是不一致的最后一处。

### 无法核实的

- CHANGELOG 1.1.2 里标"实测"的各项（0.3 秒内返回、20 天前的文件被忽略等）是你在 Windows 上做的，我**无法核实**，只能核对"描述与代码一致"。
- "有进程没窗口"这一支是用"假装看不到窗口的变体"跑的，你已经写明**没有在真正关到托盘的状态下测过**。我同意这个说法，并把它列进 §5。

## 5. 需要在 Windows 上试的（接上一轮 W1–W13）

| 编号 | 做法 | 看什么 |
|---|---|---|
| W14 | 用窗口右上角 × 关闭 Claude（看它是退出还是留在托盘），再双击快捷方式 | 日志是否出现 `Claude is running in the background (N processes, no window)`，窗口是否出来、是否在最前面；记下 N |
| W15 | 同上，如果窗口没出来 | 日志 `Claude showed no window within 8 s`；这说明 Claude 不响应第二次激活（S4-2） |
| **W16** | 在托盘图标上右键**退出**，立刻和 10 秒后各运行一次 `(Get-Process -Name claude -ErrorAction SilentlyContinue \| Where-Object { $_.Path -like '*WindowsApps*Claude_*' }).Count` | **必须是 0**。不是 0 就是 S4-1 成立：动画永远不会播 |
| W17 | 退出后再双击快捷方式 | 动画照常播，日志没有 `already running` / `in the background` |
| W18 | Claude 设置了"开机自启 / 常驻托盘"的话，开机后点快捷方式 | 预期是不播动画（S4-8）；确认这是你想要的 |
| W19 | 冷启动时快速连点两次 | 第二个的日志是哪一条（DC-6）；第一个的动画不被打断；Claude 窗口没有盖到动画上面 |
| W20 | 最小化 Claude 后点快捷方式 | 还原并在最前面，没有动画 |
| W21 | 托盘分支下，窗口出现后看是否真的在最前面（不是任务栏闪烁） | S4-3 |
| W22 | 下一次冷启动后看日志：`Claude window appeared at` 与 `splash placed … source=…` 谁先谁后 | 你打算用它决定要不要做 R-2②。`appeared` 比 `placed` 早 → 动画能盖到真窗口上；晚于 `placed`、且 `source` 是 `claude-state` → 靠 `window-state.json` 对位；`source` 是 `saved` / `screen` → 看紧挨着的 `window-state: …` 行里的原因 |

沿用的上一轮项目（W1–W13，包括混合 DPI、最大化的 Claude、Windows 10）这一轮仍然没人测过。

## 6. 隐私重扫（两个仓库，全部历史）

方法：遍历 `git rev-list --all` 的每个提交里的每个文本文件，用正则查邮箱（排除 noreply）、盘符和用户目录形式的路径、`/home/…` `/Users/…`、令牌（`ghp_`、`github_pat_`、`sk-`、`AKIA`、私钥头）、`password/secret/api_key = …` 形式的赋值，以及你的邮箱用户名片段；再单独查所有提交的作者 / 提交者 / 标签的邮箱；二进制图片这一轮没有变化（对比上一次扫描以来的提交，没有图片文件被新增或修改），所以沿用上一轮的元数据结论（无 EXIF / 文本块）。

| 仓库 | 引用 | 提交 | 非 noreply 的邮箱 | 令牌 | 作者 / 提交者 / 标签作者 |
|---|---|---|---|---|---|
| 桌宠 | 15（含我的审核分支和 9 个标签） | 24 | 0 | 0 | 全部是项目作者名和 noreply 邮箱 |
| 开屏动画 | 12（含我的审核分支和 6 个标签） | 15 | 0 | 0 | 同上 |

- 命中的"盘符形式"位置我逐条看过，都是通用示例或系统目录，不是个人路径：桌宠 `README.md`（`D:\\path\\to\\pet` 示例，位置在不同提交里行号不同：55、57、73、74、97、113、121 一带）；开屏动画 `launcher/make_shortcut.ps1`（`'C:\Program Files\WindowsApps'`，当前在第 83 行；扫描器在不同提交里命中的行号是 71、82、83，旧提交 `4c0b8d1` 的第 87 行是注释里的 `D:\...\splash\` 示意路径）；还有我自己的报告里引用这些位置的几行（桌宠 `docs/reviews/code-review-v0.5.0-2026-10-24.md:170`、`doc-vs-code.md:54`；开屏动画 `docs/reviews/launcher-static-review.md:130、140`）。
- 两个仓库在 GitHub 上还各有一个自动创建的会话分支 `claude/zealous-darwin-i3km1k`，内容就是当时的 `main`（提交号和 `main` 相同），没有额外内容。
- 我自己这一轮写的报告里没有真实姓名、邮箱、本机路径。

## 7. 需要维护者回答的问题

1. **W16 的结果**：Claude 彻底退出后，Claude 包的进程还在吗？（决定 S4-1 是不是真问题）
2. Claude 有没有"开机自启 / 常驻托盘"的设置？你自己开着吗？如果开着，动画几乎不会再出现——这是你想要的吗（S4-8）？
3. S4-4：要不要把"修改时间在未来"当过期？（一行改动）
4. S4-5：知道 `last_rect.json` 记的是启动后几秒的位置之后，你还想保留它作为备份吗？还是让它读不到 `window-state.json` 时直接用整屏？（整屏更保守，但会在"窗口很小"时盖得太大）
5. DC-7：README:23 要不要加"按键可能收不到（未验证）"？
