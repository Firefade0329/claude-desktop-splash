# 第六轮复查：开屏动画 v1.1.4

- 日期：2026-11-10　版本：v1.1.4（标签 `v1.1.4`，`main` 提交 `5eeeb10`，已合并进 `claude/review-reports`）
- **整份报告都是"读代码 / 推断"，没有一条是我实际运行的**：这个项目只能在 Windows 上跑，云端是 Linux，PowerShell 脚本我一行也没执行过。
- 范围：v1.1.3 → v1.1.4 的全部改动（`launch.ps1` 一行、README 日志表、CHANGELOG、CLAUDE.md）；隐私重扫。其余部分没有变化，没有重审。
- 没有改任何脚本。

## 结论

- **没有中危及以上的问题。** R5-1 的修复是对的：一个过去、一个未来时，选过去的那个；只有一个未来时间的文件时仍然用它。
- 新发现 **2 条提示**，都只影响日志措辞或很罕见的情形，可以不改。
- README 日志表新增的几行与代码里实际写的日志一致（§2）。
- 隐私重扫：干净（§4）。

| 编号 | 严重程度 | 标注 | 位置 | 一句话 |
|---|---|---|---|---|
| R6-S1 | 提示 | 读代码 | `launch.ps1` `Get-ClaudeStateRect` | 只有一个未来时间的 `window-state.json` 时，日志写 `written 0 min ago`，看不出它的时间在未来 |
| R6-S2 | 提示 | 读代码 + 推断 | 同上；README 日志表 `last_rect` 一栏 | `window-state.json` 晚 1 秒就算"未来"，`last_rect.json` 要晚 1 天以上才算；README 两处都只写"修改时间在未来" |

## 1. R5-1 的修复（`Get-ClaudeStateRect` 选候选文件的那一段）

```powershell
$ct = (Get-Item -LiteralPath $c).LastWriteTime
if ($ct -gt (Get-Date)) { $ct = [DateTime]::MinValue }
if (-not $f -or $ct -gt $fTime) { $f = $c; $fTime = $ct }
```

遍历顺序固定：先 `Claude-Data`，后 `Packages`。我逐个情形读了一遍（**读代码，没有运行**）：

| 情形 | 结果 | 判断 |
|---|---|---|
| 一个过去、一个未来（不论谁先） | 选过去的那个：未来的被记成 `MinValue`，过去的时间一定比它大；或者过去的先进来，`MinValue -gt` 过去时间为假，不替换 | 正确，这就是 R5-1 |
| 只有一个文件，时间在未来 | `-not $f` 成立，照样选中 | 正确，与 CHANGELOG 一致 |
| 两个都在未来 | 两个都是 `MinValue`，后者 `-gt` 不成立，留下先遍历到的 `Claude-Data` | 结果确定；`Claude-Data` 是更新后的位置，选它合理 |
| 两个都不存在 | 两次都 `continue`，`$f` 为空，日志 `file not found in either place` | 正确 |
| 两个时间相等（都在过去） | `-gt` 不成立，留下 `Claude-Data` | 结果确定，合理 |
| `MinValue` 与后面的 `ageMin` | `ageMin` 是重新 `Get-Item` 读磁盘上的真实时间算的，**不用 `$fTime`**，所以 `MinValue` 不会漏到年龄计算里（否则会算出约 10 亿分钟）。未来时间时 `(现在 - 未来)` 为负，`Max(0, …)` 变成 0 | 不会出错；措辞见 R6-S1 |
| `$fTime` 初值为 `$null` | 第一次比较前 `-not $f` 已经短路，`$ct -gt $null` 不会被求值 | 没问题 |

另外两个我想过但不算问题的地方：
- `Test-Path` 之后、`Get-Item` 之前文件被删：会抛异常，被外层 `catch` 接住，日志写 `could not be read (ItemNotFoundException)`，回退到 `last_rect` 或整屏。概率极低。
- `LastWriteTime` 和 `Get-Date` 都是本地时间，由同一套 UTC → 本地换算得出，时区变化不影响两者的比较。

### R6-S1（提示）一个未来时间的文件，日志写"0 分钟前"

- **位置**：`Get-ClaudeStateRect` 里的 `$ageMin = [int][Math]::Max(0, …)` 和 `stateWhy = 'ok (… written ' + $ageMin + ' min ago)'`。
- **场景**：只有一个 `window-state.json`，修改时间在未来（比如时钟被调回过）。它照样被使用（这是对的），但日志写成 `ok (Claude-Data, written 0 min ago)`，看起来像刚写的。
- **影响**：只影响日志。`ageMin` 不参与任何判断。
- **建议**（可不改）：未来时间时写成 `ok (Claude-Data, its time is in the future)`，和 `last_rect` 一栏的措辞对齐。

### R6-S2（提示）两个文件对"未来"的门槛不一样

- **位置**：`window-state.json` 是 `$ct -gt (Get-Date)`（晚 1 毫秒就算）；`last_rect.json` 是 `$ageDays -lt -1`（要晚 1 天以上才算）。README 日志表里两处都只写"修改时间在未来"。
- **一种罕见情形（推断，没实测）**：Claude 刚关闭、`Claude-Data` 里的文件刚写完，Windows 校时把时钟往回拨了几十秒；这几十秒内再启动，刚写的文件会被当成"未来"排到最后，于是选中 `Packages` 里的旧残留。要两个位置都有文件、并且恰好在校时后的几十秒内启动才会碰到。后果也只是动画开头 4–6 秒的位置偏一点，真窗口出现后启动器会对齐它。
- **建议**（可不改）：`window-state.json` 也用 1 天的容忍度（和 `last_rect.json` 一样），R5-1 那种"晚了 3 天"的旧文件仍然排最后；README 写成"修改时间比现在晚 1 天以上"。如果你觉得不值得，保持现状也可以。

## 2. README 日志表新增的几行 vs 代码

| README 里的写法 | 代码里实际写的 | 核对 |
|---|---|---|
| `window-state: ...; last_rect: ...` 一栏：`file missing or unreadable` | `$script:savedWhy = 'file missing or unreadable'` | 一致 |
| `ignored, written N days ago` | `'ignored, written {0:N0} days ago' -f $ageDays` | 一致（`N` 是整数） |
| `ignored, its time is in the future` | `'ignored, its time is in the future (clock set back?)'`，只在晚 1 天以上时写 | 前半句一致，代码多了 `(clock set back?)`；门槛见 R6-S2 |
| `not needed` | `if ($script:savedWhy) {…} else { 'not needed' }` | 一致 |
| "两个候选位置里取最近写过的；修改时间在未来的排最后" | 见 §1 | 一致 |
| `Claude brought to front`：只有 Windows 接受了置前请求才写 | 收尾处 `if ([SplashWin]::SetForegroundWindow(…)) { Log 'Claude brought to front' } else { Log 'Windows did not let…' }` | 一致 |
| `Windows did not let the launcher move the focus to Claude (its taskbar icon may flash instead)` | 两处会写：Claude 已在运行时的置前分支，和动画结束后的收尾 | 一致，字符串逐字相同 |

## 3. 上一轮问题的状态

| 编号 | 状态 |
|---|---|
| R5-1 未来时间的候选仍会赢 | **已修**（§1），你用假文件测过三种情形；我没有在 Windows 上跑过，读代码结论与你一致 |
| R5-2 README 日志表缺新日志 | **已修**（§2） |
| R5-3 `last_rect` 一栏可能给人"用过了"的印象 | 未改，提示级，可以不改 |
| S4-8 开机自启 / 常驻托盘 | 仍待用户回答（上一轮的状态） |
| D-8 README 截图是旧排版 | 仍未做（你已知） |

## 4. 隐私重扫（全部分支和标签的完整历史）

- 11 个远端引用（3 个分支、8 个标签）、21 个提交（其中 1 个是我这次的合并提交）。作者和提交者全部是项目作者名加 noreply 邮箱；2 个附注标签的打标签人也一样。提交信息里出现的邮箱只有 `noreply@anthropic.com`（署名行）。
- 历史里全部 57 个文件版本逐个扫了：非 noreply 的邮箱 0；令牌形式（`ghp_`、`github_pat_`、`sk-`、`AKIA` 等）0；带用户名的路径（`C:\Users\…`、`/Users/…`、`/home/…`）0。命中的盘符路径只有通用示例 `D:\path\to`，`OneDrive` 只出现在 README 的通用说明里。
- 图片：历史里的 9 张图片（含内嵌的 base64 图片）都没有 EXIF / XMP。`assets/claude-closed.js` 内嵌的一张 WebP 带一个 ICC 色彩配置（456 字节，显示器类、内容只有 `Google Inc. 2016` 版权字样，是编码器常见的通用 sRGB 配置），**不含个人信息**。这是以前就有的文件，不是这一版新增的。
- 我这一轮写的报告里没有真实姓名、邮箱、本机路径。

## 5. 需要你在 Windows 上做的事

这一轮**没有必须做的**。R6-S1、R6-S2 都是提示级，改不改由你决定；如果改了 R6-S2，可以沿用你上次测 R5-1 的假文件方法，把"未来"的那个文件分别设成 30 秒后和 3 天后，预期：30 秒后的那个按真实时间参与比较，3 天后的那个排最后。**这一步我没有运行过。**

## 6. 需要你回答的问题

没有新问题。
