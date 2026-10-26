# 第五轮复查：开屏动画 v1.1.3

- 日期：2026-10-26　版本：v1.1.3（标签 `v1.1.3`，`main` 提交 `fb6c8f9`，已合并进 `claude/review-reports`）
- **整份报告都是"读代码 / 推断"，没有任何一条是我实际运行的**：这个项目只能在 Windows 上跑，云端是 Linux。凡是标"维护者提供"的，是你在自己电脑上得到的数据，我**无法核实**。
- 范围：v1.1.2 → v1.1.3 的 `launch.ps1`、README、CHANGELOG 的全部改动；你补充的两组真实日志数据；上一轮问题的状态；隐私重扫。
- 没有改任何脚本。

## 结论

- v1.1.3 的改动大体正确，**只有一处没有达到 CHANGELOG 所说的效果（R5-1，低）**：`window-state.json` 两个候选位置比较时，"未来的时间按现在算"——但"现在"仍然比所有真实的过去时间都新，所以一个未来时间的文件照样赢过一个真实的旧文件。`last_rect.json` 那一处是对的。
- 新增的几条日志没有写进 README 的日志对照表（R5-2，低）。
- 你补充的数据我都接受：R-2② 不改，我同意；窗口越开越大不是启动器造成的，证据与我读代码的结论相符，但样本少（见 §3）。
- S4-1 在你的电脑上已经排除；别的电脑、别的 Claude 版本无法验证。
- 隐私重扫：干净（§5）。

| 编号 | 严重程度 | 标注 | 一句话 |
|---|---|---|---|
| R5-1 | 低 | 读代码 | 未来时间的 `window-state.json` 候选仍会赢过真实的旧候选 |
| R5-2 | 低（文档） | 读代码 | README 日志表缺新增的几条日志 |
| R5-3 | 提示 | 读代码 | `last_rect` 一栏写 `written N days ago`，但这个矩形可能随后因格式或位置被弃用 |

## 1. v1.1.3 的改动逐条核对

| 改动 | 位置 | 读代码结论 |
|---|---|---|
| `last_rect.json` 修改时间比现在晚超过一天 → 当作过时 | `launcher/launch.ps1:296-300` | **正确**。`$ageDays -lt -1` 时抛异常，外层 `catch {}` 接住，落到整屏；日志写 `ignored, its time is in the future (clock set back?)`。容忍 1 天以内，覆盖跨时区带来的偏差。你手动测过（3 天后的文件被忽略，退到整屏），与代码一致 |
| 日志 `last_rect` 一栏措辞 | `:296`、`:400` | 文件不存在 → `file missing or unreadable`；没用到它（来源是 `claude` 或 `claude-state`）→ `not needed`。与 S4-6 的建议一致，**正确** |
| `SetForegroundWindow` 被拒时写日志 | `:156`、`:475` | `SetForegroundWindow` 声明为 `bool`（`:73`），判断有效。`finally` 里 `Claude brought to front` 现在**只在成功时**写，失败时写新的那一行；以前是无条件写。找日志里 `brought to front` 的人要知道这一变化 |
| `ageMin` 不再为负 | `:230` | `[Math]::Max(0, …)`，**正确**（只影响日志） |
| 两个 `window-state.json` 候选比较时，未来时间按"现在"算 | `:221-228` | **见 R5-1** |
| README：只有点击可靠；连点两次的路径；`saved` 的说明 | README | 与代码一致；这正是我上一轮 DC-6、DC-7、S4-5 提的 |

### R5-1（低）未来时间的候选仍会赢

- **位置**：`launcher/launch.ps1:224-226`
  ```
  $ct = (Get-Item -LiteralPath $c).LastWriteTime
  if ($ct -gt (Get-Date)) { $ct = Get-Date }
  if (-not $f -or $ct -gt $fTime) { $f = $c; $fTime = $ct }
  ```
- **场景**：`Claude-Data` 里的文件是 10 分钟前写的（真实、当前），`Packages` 里留着的旧文件修改时间在 3 天后（比如当时电脑时钟被调到了未来）。后者被改写成"现在"，而"现在"比 10 分钟前新，于是**仍然选中旧文件**。反过来（`Claude-Data` 是未来时间）同样选中它。也就是说只有一种情况结果变了：两个都是未来时间时，以前后者赢，现在先遍历到的赢。
- **和 CHANGELOG 的关系**：CHANGELOG 写的是"未来的时间按'现在'算，而不是比一切都新"。按"现在"算，仍然比一切真实的过去时间都新，所以这句话在"一个未来、一个过去"这个最主要的场景里没有改变结果。
- **影响**：很小。需要同时满足：时钟被调回过、两个位置都存在、且错的那个恰好是旧位置。Claude 更新后只有 `Claude-Data` 会被写，旧的 `Packages` 里那个文件基本是固定不动的残留，它几乎不会是未来时间。
- **标注**：读代码。PowerShell 的 `[DateTime]` 比较没有特殊行为，我没有看到会改变这个结论的地方，但我没有运行。
- **建议**：让未来时间的候选排在所有真实时间之后（仍然可用，如果它是唯一的候选）：
  ```powershell
  $ct = (Get-Item -LiteralPath $c).LastWriteTime
  if ($ct -gt (Get-Date)) { $ct = [DateTime]::MinValue.AddYears(1) }      # a future time ranks below every real one
  ```
  或者更简单：两个文件都在时，优先 `Claude-Data`（它是更新后的位置）。
- **在 Windows 上验证的办法（不动 Claude 的文件）**：下面这段是我写的，**没有在 Windows 上运行过**，只用临时文件：
  ```powershell
  $a = New-Item -Force -ItemType File "$env:TEMP\ws-a.json"; $b = New-Item -Force -ItemType File "$env:TEMP\ws-b.json"
  $a.LastWriteTime = (Get-Date).AddMinutes(-10)      # real and recent
  $b.LastWriteTime = (Get-Date).AddDays(3)           # in the future
  $f = $null; $fTime = $null
  foreach ($c in @($a.FullName, $b.FullName)) {
    $ct = (Get-Item -LiteralPath $c).LastWriteTime
    if ($ct -gt (Get-Date)) { $ct = Get-Date }
    if (-not $f -or $ct -gt $fTime) { $f = $c; $fTime = $ct }
  }
  Split-Path -Leaf $f      # my reading of the code: ws-b.json (the future one wins)
  Remove-Item "$env:TEMP\ws-a.json", "$env:TEMP\ws-b.json"
  ```
  如果输出是 `ws-a.json`，说明我读错了，请告诉我。

### R5-2（低，文档）新日志没有进 README 的日志表

README 的日志对照表（"`launcher.log` 里各行的含义"）没有这几条：
- `Windows did not let the launcher move the focus to Claude (its taskbar icon may flash instead)`（两处会写：托盘分支和收尾）
- `window-state: …; last_rect: file missing or unreadable` / `…ignored, its time is in the future (clock set back?)` / `…not needed`

另外，`Claude brought to front` 以前总会写，现在只在置前成功时才写。README 如果有人靠它判断"启动器有没有把 Claude 带到前面"，要改成"没有这行、而有 `Windows did not let…` 那行，就是被系统拒绝了"。

### R5-3（提示）`last_rect` 一栏可能给出"用过了"的印象

- **位置**：`launcher/launch.ps1:294-300`
- `savedWhy` 在读文件之前就被设成 `written N days ago`。之后如果 JSON 坏了，或者矩形落在屏幕之外（比如外接显示器拔了），会退到整屏，但日志里 `last_rect` 一栏仍写 `written N days ago`。同一次启动的上一行 `splash placed … source=screen` 能看出来最终用的是整屏，所以不会真的误导，只是这一栏不能单独读。可以在 `catch` 里补一句 `unusable (format or position)`。

## 2. 上一轮（v1.1.2）问题的状态

| 编号 | 状态 |
|---|---|
| S4-1 进程残留让动画失效 | **在你的电脑上排除**：彻底退出后立即和约 10 秒后 Claude 包进程数都是 0（维护者提供，有截图，我无法核实），且退出后点快捷方式动画照常播。别的电脑、别的 Claude 版本无法验证。仍是推断，不是保证 |
| S4-2 托盘分支 8 秒无窗口 | 有意不改，接受（日志里有 `Claude showed no window within 8 s`） |
| S4-3 置前被拒没有日志 | 已修（`:156`、`:475`） |
| S4-4 `last_rect.json` 未来时间 | 已修；`window-state.json` 的对应处理见 R5-1 |
| S4-5 `last_rect.json` 记的是启动后几秒的位置 | 已在 README 写明 |
| S4-6 日志措辞 | 已修 |
| S4-7 每 30 毫秒读文件 | 有意不改，接受（只发生在动画开始前很短时间） |
| S4-8 开机自启 / 常驻托盘 | **仍未回答**（维护者说用户还没回答）。如果用户开了，几乎看不到动画，这是设计取舍，README 已写 |
| DC-6 连点两次的说明 | 已修 |
| DC-7 按键能不能跳过 | 已修 |
| R-2② 动画开始前等不等真窗口 | **不改**（见 §3） |

## 3. 你补充的真实日志（维护者提供，我无法核实）

### 3.1 R-2②：为什么不改我同意

你给的 4 次冷启动：动画窗口摆好（`splash placed`）比 Claude 真窗口出现早 3.9–5.6 秒，位置来源每次都是 `claude-state`，与真窗口最终位置只差约 8 像素。另 4 次你说顺序相同但没细看。

我的判断：
- 先摆好动画再等真窗口的顺序，对应的是"动画盖着 Claude 启动过程"，这正是动画的用途；
- 8 像素的差距来自下面 3.2 的现象，而且真窗口出现后启动器会立刻对齐它（`Get-TargetRect` 先找真窗口），所以不是每次启动都看得到的错位；
- 若要等真窗口，动画要晚 4–6 秒才出现，代价大于收益。

所以**不改**，同意。注意前提：`window-state.json` 读得到。读不到（来源是 `saved` 或 `screen`）时，日志里的 `window-state: …` 一栏会说明原因。

### 3.2 "Claude 窗口比关闭前大"：我同意"是 Claude 自己的行为"

- 经过启动器的 4 次（物理像素）：1794×1089 → 1802×1096 → 1810×1104 → 1816×1110，每次约 +8（宽 +8、+8、+6；高 +7、+8、+6）；
- 直接用开始菜单启动的对照（逻辑像素）：1420×852 → 1427×857 → 1433×860，位置不变，宽 +7、+6，高 +5、+3；
- 两组能互相对上：按之前推断的 125% 缩放，逻辑 +6–7 约等于物理 +7.5–8.75，与 +8、+8、+6 同量级。
- 没有启动器参与也在增长，启动器的代码不改 Claude 窗口大小（这一点我读 `launch.ps1` 也确认：只有 `IsIconic` 时 `ShowWindow(…, 9)` 还原），所以不是我们的缺陷。
- 对原因的推断（存档和恢复时对约 8 像素的不可见边框处理不对称）是你的，我没读过 Claude 的代码，只能说和数据相符。
- **证据强度**：对照只有两步，没有重复多轮；两次读取之间窗口没被动过是用户自己说的。想坐实可以连续直接启动 5 次，每次记下 `window-state.json` 的宽高，看是否匀速增长。这不是本仓库的问题，只为排除巧合。

### 3.3 18:46:20 的最小化坐标

- `after the splash: Claude window at -31992,-32000 183x26` 是最小化窗口的坐标（`Log-ClaudeRect` 不跳过最小化窗口，只有 `Get-TargetRect` 跳过），所以没有写进 `last_rect.json`；同一次启动结尾的 `end:` 因为 `finally` 里先还原了窗口，写的是正常坐标。与代码一致。
- 建议（可选，纯日志）：`Log-ClaudeRect` 检测到 `IsIconic` 时写 `minimized`，以后读日志的人不会被这种坐标吓到。
- 想问：那次最小化是 Claude 自己启动时就是最小化（比如记住了上次关闭时的状态），还是用户在动画期间自己最小化的？如果是后者，启动器会把用户主动最小化的窗口又还原到前面。这是 1.1.0 起的有意设计，不是缺陷，但值得知道。

## 4. 需要你在 Windows 上试的

沿用 W1–W22 中没人测过的（混合 DPI、最大化的 Claude、Windows 10、冷启动时快速连点两次）。这一版新增：

| 编号 | 做法 | 看什么 |
|---|---|---|
| W23 | 跑一遍上面 R5-1 的那段临时文件脚本 | 输出 `ws-a.json` 还是 `ws-b.json`。不碰 Claude 的任何文件 |
| W24（可选） | 日志里下次出现 `Windows did not let the launcher move the focus to Claude` 时，记下当时 Claude 窗口有没有到前面 | 这条在正常情况下很少出现，我没法让它按需出现，所以不要求专门去试 |

## 5. 隐私重扫（全部历史）

- 开屏动画：13 个引用（含我的审核分支和 7 个标签）、18 个提交；非 noreply 的邮箱 0，令牌 0；作者和提交者全部是项目作者名和 noreply 邮箱；提交元数据没有命中。
- 命中的盘符形式位置只有通用示例或系统目录（`C:\Program Files\WindowsApps`，以及旧提交 `4c0b8d1` 里注释中的 `D:\...\splash\` 示意路径），与上一轮相同，没有新增。
- 上一轮之后没有图片文件被新增或修改，沿用之前的元数据结论。
- 部分标签是轻量标签，没有标签作者信息；带标签作者的那个用的是 noreply 邮箱。
- 我这一轮写的报告里没有真实姓名、邮箱、本机路径。

## 6. 需要维护者回答的问题

1. R5-1：跑一下 W23，看输出；要不要把未来时间的候选排到最后（一行改动）？
2. S4-8（仍未回答）：Claude 有没有开机自启或常驻托盘的设置，你自己开着吗？
3. 3.3：18:46 那次最小化，是 Claude 自己启动成最小化的，还是你主动最小化的？
4. R5-2：要不要把新增的几条日志补进 README 的日志表？
